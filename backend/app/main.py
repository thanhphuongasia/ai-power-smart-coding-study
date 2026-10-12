"""API: `GET /content` (nội dung học từ Postgres, xem content_api.py), `POST /run` (ghép
harness + test case của bài trong DB rồi gửi cho máy chấm; có Bearer hợp lệ thì ghi `passed` cho
user), `/api/*` (đăng nhập — auth.py, tiến độ — progress.py, quản trị nội dung — admin_api.py), và `/mcp`
(Claude trên claude.ai soạn nội dung, đăng nhập qua identity-service — mcp_server.py, mcp_auth.py).

Chạy: `.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000` (xem README.md).
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy.exc import DataError, OperationalError

from app import harness, mcp_server
from app.admin_api import router as admin_router
from app.auth import UserLookup, get_user_lookup, optional_bearer, require_admin
from app.auth import router as auth_router
from app.content_api import ContentNotLoaded, JudgeLookup, get_judge_lookup
from app.review import get_draft_judge_lookup
from app.content_api import router as content_router
from app.mcp_auth import router as mcp_auth_router
from app.progress import PassRecorder, get_pass_recorder
from app.progress import router as progress_router
from app.runner import CodeRunner, RunnerUnavailable, runner_from_env
from app.sd.admin import router as sd_admin_router
from app.sd.learner import router as sd_learner_router

logger = logging.getLogger("judge")

APP_DIR = Path(__file__).parent
HARNESS_SOURCE = (APP_DIR / "harness.py").read_text(encoding="utf-8")
MAX_CODE_CHARS = 8000
# 8000 ký tự UTF-8 tối đa ~32KB, cộng JSON escape: 64KB là đủ rộng cho request hợp lệ.
MAX_BODY_BYTES = 64 * 1024
# Admin gửi cả bộ nội dung (content.json ~vài trăm KB) khi kiểm tra/lưu.
MAX_ADMIN_BODY_BYTES = 4 * 1024 * 1024
# Máy chấm công khai giới hạn theo IP: không bắn quá 4 bài cùng lúc từ một backend.
_RUN_SLOTS = asyncio.Semaphore(4)
# Tạo lúc import: CODE_RUNNER sai thì server không khởi động được, thay vì 500 ở request đầu.
_RUNNER = runner_from_env()



@asynccontextmanager
async def lifespan(app: FastAPI):
    async with mcp_server.lifespan():
        yield


app = FastAPI(title="Smart Coding Study", lifespan=lifespan)
app.include_router(content_router)
app.include_router(auth_router)
app.include_router(progress_router)
app.include_router(admin_router)
app.include_router(sd_admin_router)
app.include_router(sd_learner_router)
app.include_router(mcp_auth_router)
# ASGI thô (không qua FastAPI): cổng JWT phải chạy trước khi SDK MCP đọc body.
app.router.add_route("/mcp", mcp_server.McpGate(), include_in_schema=False)


def _body_limit(path: str) -> int:
    return MAX_ADMIN_BODY_BYTES if path.startswith("/api/admin/") else MAX_BODY_BYTES


@app.middleware("http")
async def _limit_body(request: Request, call_next):
    # Field(max_length) chỉ kiểm SAU khi đọc hết body; chặn body lớn trước khi đọc.
    if request.method not in ("GET", "HEAD", "OPTIONS"):
        length = request.headers.get("content-length")
        if length is None and "transfer-encoding" not in request.headers:
            return await call_next(request)  # không có body (vd POST /api/auth/logout từ curl)
        if length is None or not length.isdigit():
            return JSONResponse(status_code=411, content={"detail": "length_required"})
        if int(length) > _body_limit(request.url.path):
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


@app.exception_handler(OperationalError)
async def _database_unavailable(request: Request, exc: OperationalError) -> JSONResponse:
    # DB chết / không kết nối được: 503 có nghĩa thay vì 500, không lộ chi tiết kết nối.
    logger.warning("database unavailable on %s: %s", request.url.path, type(exc.orig).__name__)
    return JSONResponse(status_code=503, content={"detail": "database_unavailable"})


@app.exception_handler(DataError)
async def _unstorable_input(request: Request, exc: DataError) -> JSONResponse:
    # Lưới cuối: dữ liệu Postgres không lưu được (NUL, JSON NaN…) lọt qua validate của endpoint →
    # 422 thay vì 500. Validate ở boundary vẫn là chỗ chính; đây chỉ để không có lỗ hổng nào thành 500.
    logger.warning("unstorable input on %s: %s", request.url.path, type(exc.orig).__name__)
    return JSONResponse(status_code=422, content={"detail": "invalid_request"})


@app.exception_handler(ContentNotLoaded)
async def _content_not_loaded(request: Request, exc: ContentNotLoaded) -> JSONResponse:
    return JSONResponse(status_code=503, content={"detail": "content_not_loaded"})


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


async def _execute(runner: CodeRunner, judge, request: RunRequest) -> RunResponse:
    """Ghép harness + case của `judge` với code rồi gửi máy chấm. Không ghi gì (caller quyết)."""
    payload = json.dumps(
        {
            "code": request.code,
            "function": judge.function,
            "class_name": judge.class_name,
            "cases": judge.cases,
        },
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


@app.post("/run", response_model=RunResponse)
async def run(
    request: RunRequest,
    runner: CodeRunner = Depends(get_runner),
    lookup_judge: JudgeLookup = Depends(get_judge_lookup),
    token: str | None = Depends(optional_bearer),
    lookup_user: UserLookup = Depends(get_user_lookup),
    record_pass: PassRecorder = Depends(get_pass_recorder),
) -> RunResponse:
    # Tra DB (sync) trong threadpool để không chặn event loop; kết nối trả lại pool trước khi
    # chờ máy chấm.
    judge = await run_in_threadpool(lookup_judge, request.exercise_id)
    if judge is None:
        raise HTTPException(status_code=404, detail="exercise_not_found")
    # Token sai/hết hạn: vẫn chấm như khách (không ghi tiến độ), không chặn việc Run. Chế độ mở
    # (AUTH_OPEN_AS): không token cũng ra user mở → ghi tiến độ cho user đó.
    user = await run_in_threadpool(lookup_user, token)
    response = await _execute(runner, judge, request)
    # Chỉ server ghi passed, và chỉ khi máy chấm xác nhận (client không tự khai được).
    if user is not None and response.status == "passed":
        try:
            await run_in_threadpool(record_pass, user.id, request.exercise_id)
        except Exception:
            # Kết quả chấm vẫn trả về; chỉ mất lần ghi tiến độ này (Run lại là ghi được).
            logger.exception("record_pass failed for %s", request.exercise_id)
    return response


@app.post("/api/admin/run", response_model=RunResponse)
async def admin_run(
    http_request: Request,
    _admin=Depends(require_admin),
    runner: CodeRunner = Depends(get_runner),
    lookup_judge: JudgeLookup = Depends(get_draft_judge_lookup),
):
    """Preview của admin: chấm theo bài trong DRAFT (kể cả bài chưa duyệt). KHÔNG ghi tiến độ.

    Body đọc SAU khi qua require_admin (khai body trong chữ ký thì FastAPI parse trước khi kiểm quyền)."""
    try:
        request = RunRequest.model_validate_json(await http_request.body())
    except ValidationError:
        return JSONResponse(status_code=422, content={"detail": "invalid_request"})
    judge = await run_in_threadpool(lookup_judge, request.exercise_id)
    if judge is None:
        raise HTTPException(status_code=404, detail="exercise_not_found")
    return await _execute(runner, judge, request)
