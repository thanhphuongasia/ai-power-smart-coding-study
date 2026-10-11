"""Máy chấm: interface `CodeRunner` và bản dùng Judge0.

Backend chỉ cần một khả năng từ máy chấm: "chạy chương trình Python này với stdin này, cho tôi
stdout". Mọi thứ khác (ghép test, so kết quả) nằm trong harness, nên đổi máy chấm chỉ là đổi
class cài `CodeRunner`:

- tự host Judge0 CE (docker-compose) → giữ `Judge0Runner`, chỉ đổi `JUDGE0_URL`;
- tự chạy container → viết `DockerRunner` cùng interface, đặt `CODE_RUNNER=docker`.
"""

from __future__ import annotations

import base64
import os
from dataclasses import dataclass
from typing import Literal, Protocol

import httpx

ExecStatus = Literal["ok", "timeout", "error"]


@dataclass(frozen=True)
class Execution:
    """Kết quả chạy một chương trình.

    `status`: `ok` = chương trình thoát bình thường; `timeout` = quá giới hạn thời gian;
    `error` = chương trình bị dừng bất thường (thoát mã khác 0, bị kill vì bộ nhớ...).
    `message` mô tả lý do khi `status` khác `ok`.
    """

    status: ExecStatus
    stdout: str
    stderr: str
    message: str = ""


class RunnerUnavailable(Exception):
    """Máy chấm không trả lời hoặc trả lỗi hạ tầng. Message không bao giờ chứa token."""


class CodeRunner(Protocol):
    async def run(self, source: str, stdin: str) -> Execution: ...


def _b64(text: str) -> str:
    return base64.b64encode(text.encode()).decode()


def _unb64(value: str | None) -> str:
    if not value:
        return ""
    return base64.b64decode(value).decode(errors="replace")


class Judge0Runner:
    """Gọi Judge0 (`POST /submissions?wait=true`, base64) với Python 3.12.

    Mã trạng thái Judge0 đã kiểm trên ce.judge0.com: 3 = Accepted, 5 = Time Limit Exceeded.
    1/2 (còn trong hàng đợi dù đã `wait=true`) và 13/14 (lỗi nội bộ máy chấm) là lỗi hạ tầng.
    """

    PYTHON_3_12 = 100
    _ACCEPTED = 3
    _TIME_LIMIT_EXCEEDED = 5
    _INFRA_ERRORS = {1, 2, 13, 14}

    def __init__(
        self,
        base_url: str,
        token: str | None = None,
        *,
        language_id: int = PYTHON_3_12,
        timeout_s: float = 15.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._token = token
        self._language_id = language_id
        self._timeout_s = timeout_s
        self._transport = transport

    async def run(self, source: str, stdin: str) -> Execution:
        payload = {
            "source_code": _b64(source),
            "stdin": _b64(stdin),
            "language_id": self._language_id,
            "cpu_time_limit": 2,
            "wall_time_limit": 5,
            "memory_limit": 128000,
        }
        headers = {"X-Auth-Token": self._token} if self._token else {}
        try:
            async with httpx.AsyncClient(
                base_url=self._base_url, timeout=self._timeout_s, transport=self._transport
            ) as client:
                response = await client.post(
                    "/submissions",
                    params={"base64_encoded": "true", "wait": "true"},
                    json=payload,
                    headers=headers,
                )
        except httpx.HTTPError as exc:
            raise RunnerUnavailable(f"judge0 request failed: {type(exc).__name__}") from None

        if response.status_code not in (200, 201):
            raise RunnerUnavailable(f"judge0 HTTP {response.status_code}")
        try:
            data = response.json()
            status_id = int(data["status"]["id"])
            description = str(data["status"].get("description", ""))
            stdout = _unb64(data.get("stdout"))
            stderr = _unb64(data.get("stderr"))
            message = _unb64(data.get("message"))
        except (ValueError, KeyError, TypeError):
            raise RunnerUnavailable("judge0 response not understood") from None

        if status_id in self._INFRA_ERRORS:
            raise RunnerUnavailable(f"judge0 status {status_id}")
        if status_id == self._ACCEPTED:
            return Execution("ok", stdout, stderr)
        if status_id == self._TIME_LIMIT_EXCEEDED:
            return Execution("timeout", stdout, stderr, message or description)
        return Execution("error", stdout, stderr, message or description)


def runner_from_env() -> CodeRunner:
    """Chọn máy chấm theo biến môi trường. Hiện chỉ có `judge0`."""
    kind = os.environ.get("CODE_RUNNER", "judge0")
    if kind == "judge0":
        return Judge0Runner(
            os.environ.get("JUDGE0_URL", "https://ce.judge0.com"),
            os.environ.get("JUDGE0_TOKEN") or None,
        )
    raise ValueError(f"CODE_RUNNER không hỗ trợ: {kind!r}")
