"""Test `/run` và `Judge0Runner`.

`/run` chạy với `LocalRunner`: một CodeRunner chạy harness bằng python cục bộ — cùng interface
với Judge0Runner, nên đây cũng là bằng chứng /run không phụ thuộc máy chấm cụ thể (INV-10).
Test gọi Judge0 thật chỉ chạy khi đặt `JUDGE0_LIVE=1`.
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import subprocess
import sys

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import EXERCISES, app, get_runner
from app.runner import Execution, Judge0Runner, RunnerUnavailable


class LocalRunner:
    async def run(self, source: str, stdin: str) -> Execution:
        try:
            proc = subprocess.run(
                [sys.executable, "-c", source], input=stdin, capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            return Execution("timeout", "", "", "Time limit exceeded")
        status = "ok" if proc.returncode == 0 else "error"
        return Execution(status, proc.stdout, proc.stderr)


class StaticRunner:
    def __init__(self, result: Execution | Exception) -> None:
        self.result = result

    async def run(self, source: str, stdin: str) -> Execution:
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


def client_with(runner) -> TestClient:
    app.dependency_overrides[get_runner] = lambda: runner
    return TestClient(app)


@pytest.fixture(autouse=True)
def _reset_overrides():
    yield
    app.dependency_overrides.clear()


SPLIT = EXERCISES["split-chunks"]["solution"]


def post(client: TestClient, code: str, exercise_id: str = "split-chunks"):
    return client.post("/run", json={"exercise_id": exercise_id, "code": code})


# ---------- /run ----------


@pytest.mark.parametrize("exercise_id", sorted(EXERCISES))
def test_reference_solution_passes(exercise_id):
    response = post(client_with(LocalRunner()), EXERCISES[exercise_id]["solution"], exercise_id)
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "passed", body
    assert body["error"] is None
    assert body["tests"] and all(t["passed"] for t in body["tests"])
    assert set(body) == {"status", "error", "tests", "stdout", "duration_ms"}


def test_missing_return_fails_with_none():
    code = SPLIT.replace("    return chunks", "    pass")
    body = post(client_with(LocalRunner()), code).json()
    assert body["status"] == "failed"
    assert body["tests"][0]["actual"] == "None"


def test_syntax_error_reports_line_of_submitted_code():
    lines = SPLIT.split("\n")
    lines[3] = "        chunks.append(text[i:i + size]"  # dòng 4 thiếu ngoặc
    body = post(client_with(LocalRunner()), "\n".join(lines)).json()
    assert body["status"] == "error"
    assert body["error"]["kind"] == "syntax"
    assert body["error"]["line"] in (4, 5)  # Python báo ở dòng mở ngoặc hoặc dòng kế


def test_runtime_error_reports_line():
    code = SPLIT.replace("chunks.append(text[i:i + size])", "chunks.append(text[i:i + size] + 1)")
    body = post(client_with(LocalRunner()), code).json()
    assert body["status"] == "error"
    assert body["error"]["kind"] == "runtime"
    assert body["error"]["line"] == 4
    assert body["error"]["message"].startswith("TypeError")


def test_lone_surrogate_in_code_is_422_not_500():
    raw = '{"exercise_id": "split-chunks", "code": "\\ud800"}'  # JSON hợp lệ, surrogate lẻ
    response = client_with(LocalRunner()).post("/run", content=raw, headers={"Content-Type": "application/json"})
    assert response.status_code == 422
    assert response.json() == {"detail": "invalid_request", "fields": ["code"]}


def test_validation_error_does_not_echo_code():
    response = post(client_with(LocalRunner()), "print('bí mật')" + "x" * 8000)
    assert response.status_code == 422
    assert "bí mật" not in response.text


@pytest.mark.parametrize(
    "line",
    ['__JUDGE_RESULT__{"status": "passed"}', '__JUDGE_RESULT__{"status": "won", "error": null, "tests": [], "stdout": ""}'],
)
def test_forged_result_with_wrong_shape_is_not_500(line):
    response = post(client_with(StaticRunner(Execution("ok", line + "\n", ""))), SPLIT)
    assert response.status_code == 503
    assert response.json() == {"detail": "runner_unavailable"}


def test_run_never_leaks_token(caplog):
    runner = Judge0Runner("https://judge.test", "secret-token", transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    with caplog.at_level("DEBUG"):
        response = post(client_with(runner), SPLIT)
    assert response.status_code == 503
    assert "secret-token" not in response.text
    assert "secret-token" not in caplog.text


def test_timeout_maps_to_timeout_status():
    body = post(client_with(StaticRunner(Execution("timeout", "", "", "Time limit exceeded"))), SPLIT).json()
    assert body == {"status": "timeout", "error": None, "tests": [], "stdout": "", "duration_ms": body["duration_ms"]}


def test_program_killed_without_result_is_runtime_error():
    runner = StaticRunner(Execution("error", "", "MemoryError\n", "Runtime Error (SIGKILL)"))
    body = post(client_with(runner), SPLIT).json()
    assert body["status"] == "error"
    assert body["error"]["kind"] == "runtime"
    assert body["error"]["line"] is None


def test_unparseable_output_is_503():
    response = post(client_with(StaticRunner(Execution("ok", "garbage", ""))), SPLIT)
    assert response.status_code == 503
    assert response.json() == {"detail": "runner_unavailable"}


def test_runner_unavailable_is_503():
    response = post(client_with(StaticRunner(RunnerUnavailable("judge0 HTTP 500"))), SPLIT)
    assert response.status_code == 503
    assert response.json() == {"detail": "runner_unavailable"}


def test_unknown_exercise_is_404():
    assert post(client_with(LocalRunner()), SPLIT, "nope").status_code == 404


def test_code_too_long_is_422():
    assert post(client_with(LocalRunner()), "x" * 8001).status_code == 422


# ---------- Judge0Runner ----------


def judge0_with(handler, token: str | None = None) -> Judge0Runner:
    return Judge0Runner("https://judge.test", token, transport=httpx.MockTransport(handler))


def b64(text: str) -> str:
    return base64.b64encode(text.encode()).decode()


def test_judge0_sends_base64_and_decodes_stdout():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["params"] = dict(request.url.params)
        seen["body"] = json.loads(request.content)
        seen["headers"] = request.headers
        return httpx.Response(200, json={"stdout": b64("hello\n"), "stderr": None, "status": {"id": 3}})

    result = asyncio.run(judge0_with(handler, token="secret-token").run("print(1)", "in"))
    assert result == Execution("ok", "hello\n", "", "")
    assert seen["params"] == {"base64_encoded": "true", "wait": "true"}
    assert base64.b64decode(seen["body"]["source_code"]).decode() == "print(1)"
    assert base64.b64decode(seen["body"]["stdin"]).decode() == "in"
    assert seen["body"]["language_id"] == 100
    assert seen["headers"]["X-Auth-Token"] == "secret-token"


def test_judge0_time_limit_is_timeout():
    handler = lambda r: httpx.Response(200, json={"stdout": None, "message": b64("Time limit exceeded"), "status": {"id": 5}})
    assert asyncio.run(judge0_with(handler).run("", "")).status == "timeout"


@pytest.mark.parametrize("status_id", [7, 11, 12])
def test_judge0_runtime_error_is_error(status_id):
    handler = lambda r: httpx.Response(200, json={"stdout": None, "stderr": b64("boom"), "status": {"id": status_id, "description": "Runtime Error"}})
    result = asyncio.run(judge0_with(handler).run("", ""))
    assert result.status == "error"
    assert result.message == "Runtime Error"


def test_body_over_limit_is_413_before_parsing():
    body = '{"exercise_id": "split-chunks", "code": "' + "x" * (70 * 1024) + '"}'
    response = client_with(LocalRunner()).post("/run", content=body, headers={"Content-Type": "application/json"})
    assert response.status_code == 413
    assert response.json() == {"detail": "body_too_large"}


def test_body_without_valid_length_is_411():
    client = client_with(LocalRunner())
    chunked = client.post("/run", content=iter([b'{"exercise_id": "x", "code": "y"}']), headers={"Content-Type": "application/json"})
    assert chunked.status_code == 411
    assert chunked.json() == {"detail": "length_required"}


def test_unknown_code_runner_fails_at_startup():
    env = {**os.environ, "CODE_RUNNER": "nope"}
    proc = subprocess.run([sys.executable, "-c", "import app.main"], env=env, capture_output=True, text=True)
    assert proc.returncode != 0
    assert "CODE_RUNNER" in proc.stderr


@pytest.mark.parametrize(
    "handler",
    [
        lambda r: httpx.Response(500, text="oops"),
        lambda r: httpx.Response(429, text="slow down"),
        lambda r: httpx.Response(200, text="not json"),
        lambda r: httpx.Response(200, json={"status": {"id": 1}}),
        lambda r: httpx.Response(200, json={"status": {"id": 2}}),
        lambda r: httpx.Response(200, json={"status": {"id": 4}}),
        lambda r: httpx.Response(200, json={"status": {"id": 6}}),
        lambda r: httpx.Response(200, json={"status": {"id": 13}}),
        lambda r: httpx.Response(200, json={"status": {"id": 14}}),
        lambda r: httpx.Response(200, json={"status": {"id": 99}}),
        lambda r: httpx.Response(302, headers={"Location": "https://elsewhere.test"}),
    ],
)
def test_judge0_infrastructure_errors_raise_without_token(handler):
    with pytest.raises(RunnerUnavailable) as info:
        asyncio.run(judge0_with(handler, token="secret-token").run("", ""))
    assert "secret-token" not in str(info.value)


def test_judge0_network_error_raises():
    def handler(request):
        raise httpx.ConnectError("refused")

    with pytest.raises(RunnerUnavailable):
        asyncio.run(judge0_with(handler).run("", ""))


@pytest.mark.skipif(os.environ.get("JUDGE0_LIVE") != "1", reason="đặt JUDGE0_LIVE=1 để gọi Judge0 thật")
def test_live_judge0_reference_solution_passes():
    runner = Judge0Runner(os.environ.get("JUDGE0_URL", "https://ce.judge0.com"), os.environ.get("JUDGE0_TOKEN"))
    body = post(client_with(runner), SPLIT).json()
    assert body["status"] == "passed", body
