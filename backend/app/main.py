"""API chấm bài: `POST /run` ghép harness + test case của bài rồi gửi cho máy chấm.

Chạy: `.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000` (xem README.md).
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ValidationError

from app import harness
from app.runner import CodeRunner, RunnerUnavailable, runner_from_env

logger = logging.getLogger("judge")

APP_DIR = Path(__file__).parent
HARNESS_SOURCE = (APP_DIR / "harness.py").read_text(encoding="utf-8")
EXERCISES: dict[str, dict] = json.loads((APP_DIR / "exercises.json").read_text(encoding="utf-8"))
MAX_CODE_CHARS = 8000
# 8000 ký tự UTF-8 tối đa ~32KB, cộng JSON escape: 64KB là đủ rộng cho request hợp lệ.
MAX_BODY_BYTES = 64 * 1024
# Máy chấm công khai giới hạn theo IP: không bắn quá 4 bài cùng lúc từ một backend.
_RUN_SLOTS = asyncio.Semaphore(4)
# Tạo lúc import: CODE_RUNNER sai thì server không khởi động được, thay vì 500 ở request đầu.
_RUNNER = runner_from_env()

app = FastAPI(title="Smart Coding Study judge")


@app.middleware("http")
async def _limit_body(request: Request, call_next):
    # Field(max_length) chỉ kiểm SAU khi đọc hết body; chặn body lớn trước khi đọc.
    if request.method == "POST":
        length = request.headers.get("content-length")
        if length is None or not length.isdigit():
            return JSONResponse(status_code=411, content={"detail": "length_required"})
        if int(length) > MAX_BODY_BYTES:
            return JSONResponse(status_code=413, content={"detail": "body_too_large"})
    return await call_next(request)


class RunRequest(BaseModel):
    exercise_id: str = Field(min_length=1, max_length=100)
    code: str = Field(min_length=1, max_length=MAX_CODE_CHARS)


@app.exception_handler(RequestValidationError)
async def _invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
    # Handler mặc định trả lại nguyên `input`: vừa lặp lại code học viên, vừa nổ 500 khi input
    # chứa surrogate lẻ ("\ud800" là JSON hợp lệ nhưng không mã hoá UTF-8 được).
    fields = sorted({".".join(str(part) for part in error["loc"][1:]) for error in exc.errors()})
    return JSONResponse(status_code=422, content={"detail": "invalid_request", "fields": fields})


class RunError(BaseModel):
    kind: Literal["syntax", "runtime"]
    line: int | None
    message: str


class RunTest(BaseModel):
    call: str
    expected: str
    actual: str | None
    passed: bool


class RunResponse(BaseModel):
    status: Literal["passed", "failed", "error", "timeout"]
    error: RunError | None
    tests: list[RunTest]
    stdout: str
    duration_ms: int


def get_runner() -> CodeRunner:
    return _RUNNER


@app.post("/run", response_model=RunResponse)
async def run(request: RunRequest, runner: CodeRunner = Depends(get_runner)) -> RunResponse:
    exercise = EXERCISES.get(request.exercise_id)
    if exercise is None:
        raise HTTPException(status_code=404, detail="exercise_not_found")

    payload = json.dumps(
        {"code": request.code, "function": exercise["function"], "cases": exercise["cases"]},
        ensure_ascii=False,
    )
    started = time.monotonic()
    try:
        async with _RUN_SLOTS:
            execution = await runner.run(HARNESS_SOURCE, payload)
    except RunnerUnavailable as exc:
        logger.warning("runner unavailable for %s: %s", request.exercise_id, exc)
        raise HTTPException(status_code=503, detail="runner_unavailable") from None
    duration_ms = int((time.monotonic() - started) * 1000)

    if execution.status == "timeout":
        return RunResponse(status="timeout", error=None, tests=[], stdout="", duration_ms=duration_ms)

    result = harness.parse_result(execution.stdout)
    if result is not None:
        # Code học viên chạy cùng tiến trình với harness nên có thể in một dòng kết quả
        # sai dạng; dòng đó coi như không đọc được, không để thành 500.
        try:
            return RunResponse.model_validate({**result, "duration_ms": duration_ms})
        except ValidationError:
            logger.warning("harness result has wrong shape for %s", request.exercise_id)
    if execution.status == "error":
        # Harness bị dừng trước khi in kết quả (vd hết bộ nhớ): lỗi do code học viên.
        message = execution.message or (execution.stderr.strip().splitlines() or ["Chương trình bị dừng"])[-1]
        return RunResponse(
            status="error",
            error=RunError(kind="runtime", line=None, message=message),
            tests=[],
            stdout="",
            duration_ms=duration_ms,
        )
    logger.warning("harness output not understood for %s", request.exercise_id)
    raise HTTPException(status_code=503, detail="runner_unavailable")
