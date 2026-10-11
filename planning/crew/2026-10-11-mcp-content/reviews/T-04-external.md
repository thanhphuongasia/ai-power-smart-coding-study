external-agent: vendor=codex model=<default> timeout=360s
Reading additional input from stdin...
OpenAI Codex v0.148.0
--------
workdir: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: high
reasoning summaries: none
session id: 01a12b2a-d8bb-79c0-8ce1-fcf3600205d9
--------
user
Review commit 12f9085 (git show 12f9085 -- backend/app/mcp_server.py backend/app/main.py backend/tests/test_mcp.py). Context: FastAPI backend exposes /mcp (MCP Python SDK mcp==2.3.0, MCPServer stateless + json_response) for a claude.ai custom connector. McpGate (raw ASGI route) verifies an RS256 JWT from an external identity service BEFORE the SDK reads the body (401 + WWW-Authenticate resource_metadata, 503 if JWKS unavailable), stores claims in a ContextVar, and every tool re-checks an allowlist via authorize_sub. Write tools (create/update project/module/file/lesson with dry_run) must follow the same write path as the existing admin PUT in backend/app/admin_api.py (_save): validate outside the lock, then lock_content, compare admin_version, load_content(validated=True), commit. backend/app/mcp_auth.py and backend/app/content_ops.py were reviewed separately. Find real bugs only: auth bypass, ContextVar leakage between concurrent requests or failure to reach SDK tool tasks, TOCTOU in the write path, lost updates vs the admin app, DB session misuse across threads, error messages leaking internals, body-size limits not applied, lifespan/session-manager issues under uvicorn, HTTP semantics claude.ai depends on (401 vs 403 vs 200 isError), and tests that would still pass if the code were wrong. For each: severity (Critical/Major/Minor), file:line, evidence, fix. Do not modify files.
codex
Mình sẽ review đúng ba file/commit được chỉ định, đối chiếu trực tiếp với write path của admin và hành vi SDK liên quan; chỉ báo lỗi có cơ chế tái hiện rõ, không sửa file.
exec
/bin/zsh -lc 'git show --stat --oneline 12f9085 -- backend/app/mcp_server.py backend/app/main.py backend/tests/test_mcp.py && git show --format=fuller --find-renames 12f9085 -- backend/app/mcp_server.py backend/app/main.py backend/tests/test_mcp.py' in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
12f9085 feat(mcp): /mcp Streamable HTTP + 12 tool, JWKS outage → 503 (T-04, T-01 r2)
 backend/app/main.py       |  20 +++-
 backend/app/mcp_server.py | 294 ++++++++++++++++++++++++++++++++++++++++++++++
 backend/tests/test_mcp.py | 264 +++++++++++++++++++++++++++++++++++++++++
 3 files changed, 575 insertions(+), 3 deletions(-)
commit 12f908515f67dd7fcbe18105c256f073e0274448
Author:     Phuong Macbook <phuongmacbook@PhuongnoMacBook-Pro.local>
AuthorDate: Sun Oct 11 22:32:28 2026 +0900
Commit:     Phuong Macbook <phuongmacbook@PhuongnoMacBook-Pro.local>
CommitDate: Sun Oct 11 22:32:28 2026 +0900

    feat(mcp): /mcp Streamable HTTP + 12 tool, JWKS outage → 503 (T-04, T-01 r2)
    
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

diff --git a/backend/app/main.py b/backend/app/main.py
index 9e735b2..fbfc33e 100644
--- a/backend/app/main.py
+++ b/backend/app/main.py
@@ -1,6 +1,7 @@
 """API: `GET /content` (nội dung học từ Postgres, xem content_api.py), `POST /run` (ghép
 harness + test case của bài trong DB rồi gửi cho máy chấm; có Bearer hợp lệ thì ghi `passed` cho
-user), và `/api/*` (đăng nhập — auth.py, tiến độ — progress.py, quản trị nội dung — admin_api.py).
+user), `/api/*` (đăng nhập — auth.py, tiến độ — progress.py, quản trị nội dung — admin_api.py), và `/mcp`
+(Claude trên claude.ai soạn nội dung, đăng nhập qua identity-service — mcp_server.py, mcp_auth.py).
 
 Chạy: `.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000` (xem README.md).
 """
@@ -11,6 +12,7 @@ import asyncio
 import json
 import logging
 import time
+from contextlib import asynccontextmanager
 from pathlib import Path
 from typing import Literal
 
@@ -21,12 +23,13 @@ from fastapi.responses import JSONResponse
 from pydantic import BaseModel, Field, ValidationError
 from sqlalchemy.exc import DataError, OperationalError
 
-from app import harness
+from app import harness, mcp_server
 from app.admin_api import router as admin_router
 from app.auth import UserLookup, get_user_lookup, optional_bearer
 from app.auth import router as auth_router
 from app.content_api import ContentNotLoaded, JudgeLookup, get_judge_lookup
 from app.content_api import router as content_router
+from app.mcp_auth import router as mcp_auth_router
 from app.progress import PassRecorder, get_pass_recorder
 from app.progress import router as progress_router
 from app.runner import CodeRunner, RunnerUnavailable, runner_from_env
@@ -45,11 +48,22 @@ _RUN_SLOTS = asyncio.Semaphore(4)
 # Tạo lúc import: CODE_RUNNER sai thì server không khởi động được, thay vì 500 ở request đầu.
 _RUNNER = runner_from_env()
 
-app = FastAPI(title="Smart Coding Study")
+
+
+@asynccontextmanager
+async def lifespan(app: FastAPI):
+    async with mcp_server.lifespan():
+        yield
+
+
+app = FastAPI(title="Smart Coding Study", lifespan=lifespan)
 app.include_router(content_router)
 app.include_router(auth_router)
 app.include_router(progress_router)
 app.include_router(admin_router)
+app.include_router(mcp_auth_router)
+# ASGI thô (không qua FastAPI): cổng JWT phải chạy trước khi SDK MCP đọc body.
+app.router.add_route("/mcp", mcp_server.McpGate(), include_in_schema=False)
 
 
 def _body_limit(path: str) -> int:
diff --git a/backend/app/mcp_server.py b/backend/app/mcp_server.py
new file mode 100644
index 0000000..784732f
--- /dev/null
+++ b/backend/app/mcp_server.py
@@ -0,0 +1,294 @@
+"""`/mcp`: MCP server (Streamable HTTP) để Claude trên claude.ai đọc và tạo/sửa nội dung học.
+
+- Cổng (`McpGate`) chạy TRƯỚC SDK: không có JWT hợp lệ của identity-service → 401 + `WWW-Authenticate`
+  có `resource_metadata` (claude.ai chỉ hiện nút Connect khi thấy đúng thứ này trên một 401).
+- Mỗi tool kiểm lại quyền bằng `authorize_sub` (bảng `mcp_access`) — thu hồi có hiệu lực ngay.
+- Ghi đi đúng đường của admin PUT: hàm thuần `content_ops` → `validation_errors` (ngoài khoá) → khoá
+  ghi → so `admin_version` → `load_content(validated=True)`. Màn Admin cầm version cũ sẽ nhận 409.
+- Project = theme, module = topic, file = code file, lesson = exercise. Không có xoá.
+
+SDK chạy stateless + JSON response: mỗi POST là một request độc lập, không giữ phiên trong RAM.
+"""
+
+from __future__ import annotations
+
+import contextvars
+import json
+import logging
+from collections.abc import AsyncIterator, Callable, Iterator
+from contextlib import asynccontextmanager, contextmanager
+from typing import Any
+
+from fastapi.concurrency import run_in_threadpool
+from mcp.server.mcpserver import MCPServer
+from mcp.server.mcpserver.exceptions import ToolError
+from mcp.server.transport_security import TransportSecuritySettings
+from mcp.types import ToolAnnotations
+from sqlalchemy.exc import DataError
+from sqlalchemy.orm import Session
+from starlette.datastructures import Headers
+from starlette.responses import JSONResponse
+from starlette.types import Receive, Scope, Send
+
+from app import content_ops
+from app.content_ops import ContentOpError
+from app.db import SessionLocal
+from app.export_content import admin_version, export_content
+from app.load_content import load_content, lock_content, validation_errors
+from app.mcp_auth import (
+    InvalidToken,
+    JwksUnavailable,
+    authorize_sub,
+    public_base_url,
+    verify_bearer,
+    www_authenticate,
+)
+
+logger = logging.getLogger("mcp")
+
+MAX_BODY_BYTES = 64 * 1024  # bằng trần chung của main.py; một bài đầy đủ chỉ vài KB
+MAX_ERRORS = 50
+
+_claims: contextvars.ContextVar[dict | None] = contextvars.ContextVar("mcp_claims", default=None)
+
+INSTRUCTIONS = (
+    "Công cụ soạn nội dung cho app học lập trình Smart Coding Study. Cây nội dung: project → module "
+    "(lồng được) → file → lesson. Mọi thay đổi có hiệu lực NGAY với học viên. Trước khi tạo/sửa bài, gọi "
+    "get_authoring_guide để biết luật; thử với dry_run=true trước, sửa hết lỗi rồi mới ghi thật."
+)
+
+mcp = MCPServer(name="smart-coding-study", instructions=INSTRUCTIONS)
+
+
+@contextmanager
+def open_session() -> Iterator[Session]:
+    """Session DB cho một tool call. Test thay bằng session trong transaction."""
+    with SessionLocal() as session:
+        yield session
+
+
+def _authorized(session: Session):
+    claims = _claims.get()
+    sub = claims["sub"] if claims else None
+    user = authorize_sub(session, sub) if sub else None
+    if user is None:
+        raise ToolError(
+            f"Tài khoản identity sub={sub} chưa được cấp quyền sửa nội dung (hoặc đã bị thu hồi). "
+            f"Admin cấp bằng: python -m app.mcp_access allow {sub} --as <email admin>"
+        )
+    return user, sub
+
+
+def _capped(errors: list[str]) -> str:
+    extra = len(errors) - MAX_ERRORS
+    lines = errors[:MAX_ERRORS] + ([f"… và {extra} lỗi nữa"] if extra > 0 else [])
+    return "\n".join(f"- {e}" for e in lines)
+
+
+def _read(fn: Callable[[dict], Any]) -> Any:
+    with open_session() as session:
+        _authorized(session)
+        try:
+            return fn(export_content(session))
+        except ContentOpError as exc:
+            raise ToolError(str(exc)) from None
+
+
+def _write(tool: str, op: Callable[[dict], dict], dry_run: bool) -> dict:
+    with open_session() as session:
+        user, sub = _authorized(session)
+        before = export_content(session)
+        base = admin_version(before)
+        try:
+            after = op(before)
+        except ContentOpError as exc:
+            raise ToolError(str(exc)) from None
+        # Kiểm luật TRƯỚC khi giữ khoá ghi (như admin PUT): nội dung sai không chặn ai.
+        errors = validation_errors(after)
+        if errors:
+            raise ToolError("Nội dung không hợp lệ, chưa ghi gì:\n" + _capped(errors))
+        if dry_run:
+            return {"ok": True, "dry_run": True, "message": "Hợp lệ. Gọi lại với dry_run=false để ghi."}
+        lock_content(session)
+        if admin_version(export_content(session)) != base:
+            session.rollback()
+            raise ToolError("Nội dung vừa được người khác sửa trong lúc kiểm. Đọc lại rồi thử lại.")
+        try:
+            load_content(session, after, validated=True)
+        except DataError as exc:
+            session.rollback()
+            raise ToolError(f"DB từ chối nội dung ({type(exc.orig).__name__}) — kiểm độ dài id/tên") from None
+        version = admin_version(export_content(session))
+        session.commit()
+    logger.info("mcp %s by %s (sub=%s): %s -> %s", tool, user.email, sub, base, version)
+    return {"ok": True, "version": version}
+
+
+_READ = ToolAnnotations(read_only_hint=True)
+_WRITE = ToolAnnotations(read_only_hint=False, destructive_hint=False, idempotent_hint=False)
+_UPDATE = ToolAnnotations(read_only_hint=False, destructive_hint=True, idempotent_hint=True)
+
+
+@mcp.tool(annotations=_READ)
+async def list_projects() -> list[dict]:
+    """Liệt kê mọi project (id, tên, mô tả, số module/file/bài)."""
+    return await run_in_threadpool(_read, content_ops.list_projects)
+
+
+@mcp.tool(annotations=_READ)
+async def get_project(project_id: str) -> dict:
+    """Cây của một project: module (lồng nhau) → file → tên bài, kèm sơ đồ class."""
+    return await run_in_threadpool(_read, lambda c: content_ops.project_tree(c, project_id))
+
+
+@mcp.tool(annotations=_READ)
+async def get_lesson(lesson_id: str) -> dict:
+    """Bài đầy đủ (template, ô, gợi ý, challenge, judge gồm lời giải + test case) và các file chứa bài."""
+    return await run_in_threadpool(_read, lambda c: content_ops.get_lesson(c, lesson_id))
+
+
+AUTHORING_GUIDE = """Luật soạn bài (server kiểm hết khi ghi; vi phạm thì tool trả danh sách lỗi):
+
+Cấu trúc
+- id duy nhất TOÀN CỤC giữa project/module/file/bài/ô, ≤100 ký tự. Project cần ≥1 module.
+- Bài: {id, title, class_name (null = hàm rời; tên class = method), function_name, params[], template,
+  challenge{statement, motivation, small{caption,input,output,note}, project{...}}, blocks[], judge{solution, cases[]}}.
+- function_name "__init__" cần class_name. Bài method chỉ chấm được bằng case kịch bản (xem bài mẫu).
+
+Ô (blocks) và template
+- ≤3 ô. Mỗi ô: {id, label, title, prompt, indent_level, accepted_answers[], expected_output, explanation, hints[], vocab[]}.
+- label là MỘT chữ in hoa (A, B, C); id ô = "<id bài>-<label viết thường>" (vd "add_flight-a").
+- template có đúng một dòng "# TODO <label>" cho mỗi ô, thụt đúng 4 × indent_level khoảng trắng, không marker thừa.
+- Mỗi đáp án ≤2 dòng; tổng dòng đáp án đầu tiên của mọi ô ≤10; đúng 3 gợi ý; vocab và explanation không rỗng.
+- Thay mỗi "# TODO <label>" bằng accepted_answers[0] của ô đó phải ra ĐÚNG judge.solution (từng ký tự).
+- Không đặt ô sau "return" trong cùng nhánh (code chết).
+
+Challenge và sơ đồ
+- challenge không rỗng, ví dụ phải gọi đúng tên hàm.
+- Sơ đồ class của project phải khớp code: class tồn tại, thuộc tính `self.x =`, method `def m(`.
+
+judge.cases: ≥1 case, cùng dạng với bài mẫu.
+
+Cách làm: get_lesson một bài cùng loại làm mẫu → soạn → gọi tool với dry_run=true → sửa lỗi → ghi thật."""
+
+
+@mcp.tool(annotations=_READ)
+async def get_authoring_guide() -> dict:
+    """Luật nội dung + một bài mẫu thật. Đọc trước khi tạo/sửa bài."""
+
+    def build(content: dict) -> dict:
+        example = next(iter(content["exercises"].values()), None)
+        return {"rules": AUTHORING_GUIDE, "example_lesson": example}
+
+    return await run_in_threadpool(_read, build)
+
+
+def _writer(tool: str, op: Callable[[dict], dict], dry_run: bool):
+    return run_in_threadpool(_write, tool, op, dry_run)
+
+
+@mcp.tool(annotations=_WRITE)
+async def create_project(project: dict[str, Any], first_module: dict[str, Any], dry_run: bool = False) -> dict:
+    """Tạo project mới (id, name, description, tags?, diagram?) cùng module đầu tiên (id, name, description)."""
+    return await _writer("create_project", lambda c: content_ops.create_project(c, project, first_module), dry_run)
+
+
+@mcp.tool(annotations=_UPDATE)
+async def update_project(project_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
+    """Sửa project; chỉ các field name, description, tags, diagram."""
+    return await _writer("update_project", lambda c: content_ops.update_project(c, project_id, changes), dry_run)
+
+
+@mcp.tool(annotations=_WRITE)
+async def create_module(
+    project_id: str, module: dict[str, Any], parent_module_id: str | None = None, dry_run: bool = False
+) -> dict:
+    """Tạo module (id, name, description) trong project, hoặc làm module con của parent_module_id."""
+    return await _writer(
+        "create_module", lambda c: content_ops.create_module(c, project_id, module, parent_module_id), dry_run
+    )
+
+
+@mcp.tool(annotations=_UPDATE)
+async def update_module(module_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
+    """Sửa module; chỉ name, description."""
+    return await _writer("update_module", lambda c: content_ops.update_module(c, module_id, changes), dry_run)
+
+
+@mcp.tool(annotations=_WRITE)
+async def create_file(module_id: str, file: dict[str, Any], dry_run: bool = False) -> dict:
+    """Tạo file code (id, name) trong module."""
+    return await _writer("create_file", lambda c: content_ops.create_file(c, module_id, file), dry_run)
+
+
+@mcp.tool(annotations=_UPDATE)
+async def update_file(file_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
+    """Sửa file; chỉ name và exercise_ids (thứ tự bài / gắn bài có sẵn)."""
+    return await _writer("update_file", lambda c: content_ops.update_file(c, file_id, changes), dry_run)
+
+
+@mcp.tool(annotations=_WRITE)
+async def create_lesson(file_id: str, lesson: dict[str, Any], dry_run: bool = False) -> dict:
+    """Tạo bài mới đầy đủ (gồm judge) và gắn vào cuối file. Đọc get_authoring_guide trước."""
+    return await _writer("create_lesson", lambda c: content_ops.create_lesson(c, file_id, lesson), dry_run)
+
+
+@mcp.tool(annotations=_UPDATE)
+async def update_lesson(lesson_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
+    """Sửa bài: thay nguyên các field top-level được truyền (không đổi id)."""
+    return await _writer("update_lesson", lambda c: content_ops.update_lesson(c, lesson_id, changes), dry_run)
+
+
+def _json(status: int, body: dict, headers: dict[str, str] | None = None) -> JSONResponse:
+    return JSONResponse(status_code=status, content=body, headers=headers)
+
+
+class McpGate:
+    """ASGI cho `/mcp`: xác thực JWT trước khi SDK đọc body, rồi chuyển cho session manager."""
+
+    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
+        if scope["method"] != "POST":
+            # Stateless: không có luồng SSE GET hay phiên để DELETE. GET để SDK xử lý sẽ mở một luồng
+            # SSE treo mãi, giữ chỗ worker uvicorn (spec cho phép 405 ở đây).
+            await _json(405, {"detail": "method_not_allowed"}, {"Allow": "POST"})(scope, receive, send)
+            return
+        base = public_base_url()
+        if base is None:
+            await _json(503, {"detail": "mcp_not_configured"})(scope, receive, send)
+            return
+        authorization = Headers(scope=scope).get("authorization")
+        try:
+            claims = await run_in_threadpool(verify_bearer, authorization, base)
+        except InvalidToken:
+            challenge = {"WWW-Authenticate": www_authenticate(base, invalid=authorization is not None)}
+            await _json(401, {"error": "invalid_token"}, challenge)(scope, receive, send)
+            return
+        except JwksUnavailable:
+            logger.warning("identity JWKS unavailable")
+            await _json(503, {"detail": "auth_unavailable"})(scope, receive, send)
+            return
+        reset = _claims.set(claims)
+        try:
+            await mcp.session_manager.handle_request(scope, receive, send)
+        finally:
+            _claims.reset(reset)
+
+
+@asynccontextmanager
+async def lifespan() -> AsyncIterator[None]:
+    """Session manager chỉ `run()` được một lần mỗi instance: dựng mới mỗi lần app khởi động."""
+    # Không bật chống DNS rebinding của SDK: endpoint đòi Bearer token, trình duyệt không tự gắn được
+    # token cho trang lạ, và Host thật đứng sau nginx khác nhau giữa môi trường.
+    mcp.streamable_http_app(
+        json_response=True,
+        stateless_http=True,
+        max_request_body_size=MAX_BODY_BYTES,
+        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
+    )
+    async with mcp.session_manager.run():
+        yield
+
+
+def describe_tools() -> str:
+    """Tên tool, dùng cho log/README."""
+    return json.dumps(sorted(t.name for t in mcp._tool_manager.list_tools()))
diff --git a/backend/tests/test_mcp.py b/backend/tests/test_mcp.py
new file mode 100644
index 0000000..0adc849
--- /dev/null
+++ b/backend/tests/test_mcp.py
@@ -0,0 +1,264 @@
+"""`/mcp` qua HTTP thật (TestClient + lifespan): cổng 401 trước SDK (INV-05), không rơi về chế độ mở hay
+token app (INV-03), ghi đúng một đường + hiện ở /content (INV-02), Admin cầm version cũ nhận 409
+(INV-01), thu hồi có hiệu lực ngay (INV-04)."""
+
+from __future__ import annotations
+
+import copy
+import json
+from contextlib import contextmanager
+
+import httpx
+import pytest
+
+from app import mcp_auth, mcp_server
+from app.content_api import read_content
+from app.mcp_access import allow, revoke
+from app.mcp_auth import JwksCache
+from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
+from tests.test_mcp_auth import AUD, BASE, ISS, SUB, Signer
+
+ADMIN = "admin@gmail.com"
+PROTOCOL = "2025-06-18"
+ACCEPT = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
+
+
+@pytest.fixture(scope="module")
+def signer() -> Signer:
+    return Signer()
+
+
+@pytest.fixture()
+def env(monkeypatch, signer):
+    monkeypatch.setenv("PUBLIC_BASE_URL", BASE)
+    monkeypatch.setenv("IDENTITY_ISSUER", ISS)
+    monkeypatch.delenv("AUTH_OPEN_AS", raising=False)
+    monkeypatch.setitem(mcp_auth._caches, ISS, signer.cache())
+
+
+@pytest.fixture()
+def mcp(env, loaded_session, client_for, monkeypatch):
+    """Client đã chạy lifespan; tool dùng session test (rollback sau test)."""
+
+    @contextmanager
+    def session():
+        yield loaded_session
+
+    monkeypatch.setattr(mcp_server, "open_session", session)
+    add_user(loaded_session, email=ADMIN, roles=("learner", "admin"))
+    with client_for(loaded_session) as client:
+        yield client
+
+
+@pytest.fixture()
+def granted(mcp, loaded_session):
+    allow(loaded_session, SUB, ADMIN, "test")
+    loaded_session.flush()
+    return mcp
+
+
+def _headers(token: str | None) -> dict:
+    headers = {**ACCEPT, "MCP-Protocol-Version": PROTOCOL}
+    if token is not None:
+        headers["Authorization"] = f"Bearer {token}"
+    return headers
+
+
+def rpc(client, method: str, params: dict | None = None, token: str | None = None) -> httpx.Response:
+    body = {"jsonrpc": "2.0", "id": 1, "method": method, **({"params": params} if params is not None else {})}
+    return client.post("/mcp", json=body, headers=_headers(token))
+
+
+def call(client, signer, name: str, **arguments) -> dict:
+    r = rpc(client, "tools/call", {"name": name, "arguments": arguments}, signer.token())
+    assert r.status_code == 200, r.text
+    return r.json()["result"]
+
+
+def _text(result: dict) -> str:
+    return "\n".join(c["text"] for c in result["content"] if c["type"] == "text")
+
+
+def _data(result: dict):
+    assert not result.get("isError"), _text(result)
+    structured = result.get("structuredContent")
+    if structured is not None:
+        return structured.get("result", structured)
+    return json.loads(_text(result))
+
+
+def _new_lesson(content: dict, new_id: str = "zz-mcp-lesson") -> dict:
+    src = next(iter(content["exercises"]))
+    lesson = copy.deepcopy(content["exercises"][src])
+    lesson["id"] = new_id
+    for b in lesson["blocks"]:
+        b["id"] = f"{new_id}-{b['label'].lower()}"
+    return lesson
+
+
+def _first_file(content: dict) -> str:
+    return content["themes"][0]["topics"][0]["files"][0]["id"]
+
+
+# --- Cổng HTTP (INV-05, INV-03, INV-07) -----------------------------------------------------------
+
+
+def test_no_token_is_401_with_resource_metadata(mcp):
+    r = mcp.post("/mcp", content=b"{not json", headers=ACCEPT)  # body rác: cổng không đọc body
+    assert r.status_code == 401
+    challenge = r.headers["www-authenticate"]
+    assert challenge.startswith("Bearer ")
+    assert f'resource_metadata="{BASE}/.well-known/oauth-protected-resource/mcp"' in challenge
+    assert "error=" not in challenge
+
+
+@pytest.mark.parametrize("overrides", [{"aud": "fishing-rod"}, {"aud": "https://moneyflow.jacons-corp.com/mcp"}, {"iss": "https://x.test"}])
+def test_token_for_other_resource_is_401(mcp, signer, overrides):
+    r = rpc(mcp, "tools/list", token=signer.token(**overrides))
+    assert r.status_code == 401 and 'error="invalid_token"' in r.headers["www-authenticate"]
+
+
+def test_open_mode_and_app_session_token_do_not_open_mcp(mcp, loaded_session, monkeypatch):
+    monkeypatch.setenv("AUTH_OPEN_AS", ADMIN)
+    assert rpc(mcp, "tools/list").status_code == 401
+    app_token = login(mcp, email=ADMIN).json()["token"]
+    assert rpc(mcp, "tools/list", token=app_token).status_code == 401
+
+
+def test_get_and_delete_are_405(mcp, signer):
+    assert mcp.get("/mcp", headers=_headers(signer.token())).status_code == 405
+    assert mcp.delete("/mcp", headers=_headers(signer.token())).status_code == 405
+
+
+def test_not_configured_is_503(mcp, signer, monkeypatch):
+    monkeypatch.delenv("PUBLIC_BASE_URL")
+    assert rpc(mcp, "tools/list", token=signer.token()).status_code == 503
+
+
+def test_identity_down_is_503_not_401(mcp, signer, monkeypatch):
+    def down(url):
+        raise httpx.ConnectError("down")
+
+    monkeypatch.setitem(mcp_auth._caches, ISS, JwksCache("u", fetch=down))
+    r = rpc(mcp, "tools/list", token=signer.token())
+    assert r.status_code == 503 and "www-authenticate" not in r.headers
+
+
+def test_prm_on_main_app(mcp):
+    body = mcp.get("/.well-known/oauth-protected-resource/mcp").json()
+    assert body["resource"] == AUD and body["authorization_servers"] == [ISS]
+
+
+# --- Giao thức + quyền -----------------------------------------------------------------------------
+
+
+def test_initialize_and_list_tools(mcp, signer):
+    init = rpc(mcp, "initialize", {"protocolVersion": PROTOCOL, "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}}, signer.token())
+    assert init.status_code == 200 and init.json()["result"]["serverInfo"]["name"] == "smart-coding-study"
+    tools = {t["name"]: t for t in rpc(mcp, "tools/list", token=signer.token()).json()["result"]["tools"]}
+    assert set(tools) == {
+        "list_projects", "get_project", "get_lesson", "get_authoring_guide",
+        "create_project", "update_project", "create_module", "update_module",
+        "create_file", "update_file", "create_lesson", "update_lesson",
+    }
+    assert tools["list_projects"]["annotations"]["readOnlyHint"] is True
+    assert "dry_run" in tools["create_lesson"]["inputSchema"]["properties"]
+
+
+def test_tools_refuse_sub_without_grant(mcp, signer):
+    result = call(mcp, signer, "list_projects")
+    assert result["isError"] and SUB in _text(result)
+
+
+def test_open_mode_does_not_grant_tools(mcp, signer, monkeypatch):
+    # INV-03: JWT hợp lệ nhưng sub chưa cấp; chế độ mở trỏ tới admin cũng không được bù quyền.
+    monkeypatch.setenv("AUTH_OPEN_AS", ADMIN)
+    assert call(mcp, signer, "list_projects")["isError"]
+
+
+def test_read_tools(granted, signer, content_data):
+    projects = _data(call(granted, signer, "list_projects"))
+    assert [p["id"] for p in projects] == [t["id"] for t in content_data["themes"]]
+    lesson_id = next(iter(content_data["exercises"]))
+    lesson = _data(call(granted, signer, "get_lesson", lesson_id=lesson_id))
+    assert lesson["id"] == lesson_id and "judge" in lesson
+    guide = _data(call(granted, signer, "get_authoring_guide"))
+    assert "TODO" in guide["rules"] and guide["example_lesson"]["id"]
+    missing = call(granted, signer, "get_lesson", lesson_id="khong-co")
+    assert missing["isError"]
+
+
+# --- Ghi (INV-01, INV-02, INV-04) ------------------------------------------------------------------
+
+
+def _admin_version(client) -> str:
+    token = login(client, email=ADMIN).json()["token"]
+    return client.get("/api/admin/content", headers=bearer(token)).json()["version"]
+
+
+def test_dry_run_does_not_write(granted, signer, loaded_session, content_data):
+    before = _admin_version(granted)
+    lesson = _new_lesson(content_data)
+    result = _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson, dry_run=True))
+    assert result["dry_run"] is True
+    assert _admin_version(granted) == before
+    assert lesson["id"] not in read_content(loaded_session)["exercises"]
+
+
+def test_create_lesson_shows_in_content_and_stale_admin_gets_409(granted, signer, loaded_session, content_data):
+    token = login(granted, email=ADMIN).json()["token"]
+    stale = granted.get("/api/admin/content", headers=bearer(token)).json()
+    lesson = _new_lesson(content_data)
+    file_id = _first_file(content_data)
+    result = _data(call(granted, signer, "create_lesson", file_id=file_id, lesson=lesson))
+    assert result["ok"] and result["version"] != stale["version"]
+    # INV-02: app thấy bài qua /content.
+    public = granted.get("/content").json()
+    assert lesson["id"] in public["exercises"] and "judge" not in public["exercises"][lesson["id"]]
+    # INV-01: màn Admin cầm version cũ không ghi đè được bài Claude vừa tạo.
+    r = granted.put("/api/admin/content", json={"base_version": stale["version"], "content": stale["content"]}, headers=bearer(token))
+    assert r.status_code == 409
+
+
+def test_invalid_lesson_is_tool_error_and_nothing_written(granted, signer, content_data):
+    before = _admin_version(granted)
+    lesson = _new_lesson(content_data)
+    lesson["judge"]["solution"] = "def khac():\n    pass\n"  # không khớp template + đáp án
+    result = call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson)
+    assert result["isError"] and "không hợp lệ" in _text(result)
+    assert _admin_version(granted) == before
+
+
+def test_content_op_error_is_tool_error(granted, signer):
+    result = call(granted, signer, "update_module", module_id="khong-co", changes={"name": "x"})
+    assert result["isError"]
+
+
+def test_create_project_module_file_chain(granted, signer, loaded_session):
+    project = {"id": "zz-proj", "name": "Dự án thử", "description": "mô tả", "tags": ["python"]}
+    first = {"id": "zz-mod", "name": "Module 1", "description": "m1"}
+    assert _data(call(granted, signer, "create_project", project=project, first_module=first))["ok"]
+    sub = {"id": "zz-sub", "name": "Module con", "description": "m2"}
+    assert _data(call(granted, signer, "create_module", project_id="zz-proj", module=sub, parent_module_id="zz-mod"))["ok"]
+    assert _data(call(granted, signer, "create_file", module_id="zz-sub", file={"id": "zz-file", "name": "main.py"}))["ok"]
+    tree = _data(call(granted, signer, "get_project", project_id="zz-proj"))
+    assert tree["modules"][0]["modules"][0]["files"][0]["id"] == "zz-file"
+
+
+def test_revoke_takes_effect_on_next_call(granted, signer, loaded_session):
+    assert not call(granted, signer, "list_projects").get("isError")
+    revoke(loaded_session, SUB)
+    loaded_session.flush()
+    result = call(granted, signer, "update_module", module_id="x", changes={"name": "y"})
+    assert result["isError"] and SUB in _text(result)
+
+
+def test_admin_demoted_loses_mcp(granted, signer, loaded_session):
+    from sqlalchemy import select
+
+    from app.tables import User
+
+    user = loaded_session.scalar(select(User).where(User.email == ADMIN))
+    user.roles = ["learner"]
+    loaded_session.flush()
+    assert call(granted, signer, "list_projects")["isError"]

exec
/bin/zsh -lc "git show 12f9085:backend/app/main.py | nl -ba | sed -n '1,240p'; git show 12f9085:backend/app/admin_api.py | nl -ba | sed -n '1,260p'; git show 12f9085:backend/app/load_content.py | nl -ba | sed -n '1,260p'; rg -n \"mcp==|mcp\\s*[=~><]\" backend pyproject.toml requirements* uv.lock 2>/dev/null || true" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
     1	"""API: `GET /content` (nội dung học từ Postgres, xem content_api.py), `POST /run` (ghép
     2	harness + test case của bài trong DB rồi gửi cho máy chấm; có Bearer hợp lệ thì ghi `passed` cho
     3	user), `/api/*` (đăng nhập — auth.py, tiến độ — progress.py, quản trị nội dung — admin_api.py), và `/mcp`
     4	(Claude trên claude.ai soạn nội dung, đăng nhập qua identity-service — mcp_server.py, mcp_auth.py).
     5	
     6	Chạy: `.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000` (xem README.md).
     7	"""
     8	
     9	from __future__ import annotations
    10	
    11	import asyncio
    12	import json
    13	import logging
    14	import time
    15	from contextlib import asynccontextmanager
    16	from pathlib import Path
    17	from typing import Literal
    18	
    19	from fastapi import Depends, FastAPI, HTTPException, Request
    20	from fastapi.concurrency import run_in_threadpool
    21	from fastapi.exceptions import RequestValidationError
    22	from fastapi.responses import JSONResponse
    23	from pydantic import BaseModel, Field, ValidationError
    24	from sqlalchemy.exc import DataError, OperationalError
    25	
    26	from app import harness, mcp_server
    27	from app.admin_api import router as admin_router
    28	from app.auth import UserLookup, get_user_lookup, optional_bearer
    29	from app.auth import router as auth_router
    30	from app.content_api import ContentNotLoaded, JudgeLookup, get_judge_lookup
    31	from app.content_api import router as content_router
    32	from app.mcp_auth import router as mcp_auth_router
    33	from app.progress import PassRecorder, get_pass_recorder
    34	from app.progress import router as progress_router
    35	from app.runner import CodeRunner, RunnerUnavailable, runner_from_env
    36	
    37	logger = logging.getLogger("judge")
    38	
    39	APP_DIR = Path(__file__).parent
    40	HARNESS_SOURCE = (APP_DIR / "harness.py").read_text(encoding="utf-8")
    41	MAX_CODE_CHARS = 8000
    42	# 8000 ký tự UTF-8 tối đa ~32KB, cộng JSON escape: 64KB là đủ rộng cho request hợp lệ.
    43	MAX_BODY_BYTES = 64 * 1024
    44	# Admin gửi cả bộ nội dung (content.json ~vài trăm KB) khi kiểm tra/lưu.
    45	MAX_ADMIN_BODY_BYTES = 4 * 1024 * 1024
    46	# Máy chấm công khai giới hạn theo IP: không bắn quá 4 bài cùng lúc từ một backend.
    47	_RUN_SLOTS = asyncio.Semaphore(4)
    48	# Tạo lúc import: CODE_RUNNER sai thì server không khởi động được, thay vì 500 ở request đầu.
    49	_RUNNER = runner_from_env()
    50	
    51	
    52	
    53	@asynccontextmanager
    54	async def lifespan(app: FastAPI):
    55	    async with mcp_server.lifespan():
    56	        yield
    57	
    58	
    59	app = FastAPI(title="Smart Coding Study", lifespan=lifespan)
    60	app.include_router(content_router)
    61	app.include_router(auth_router)
    62	app.include_router(progress_router)
    63	app.include_router(admin_router)
    64	app.include_router(mcp_auth_router)
    65	# ASGI thô (không qua FastAPI): cổng JWT phải chạy trước khi SDK MCP đọc body.
    66	app.router.add_route("/mcp", mcp_server.McpGate(), include_in_schema=False)
    67	
    68	
    69	def _body_limit(path: str) -> int:
    70	    return MAX_ADMIN_BODY_BYTES if path.startswith("/api/admin/") else MAX_BODY_BYTES
    71	
    72	
    73	@app.middleware("http")
    74	async def _limit_body(request: Request, call_next):
    75	    # Field(max_length) chỉ kiểm SAU khi đọc hết body; chặn body lớn trước khi đọc.
    76	    if request.method not in ("GET", "HEAD", "OPTIONS"):
    77	        length = request.headers.get("content-length")
    78	        if length is None and "transfer-encoding" not in request.headers:
    79	            return await call_next(request)  # không có body (vd POST /api/auth/logout từ curl)
    80	        if length is None or not length.isdigit():
    81	            return JSONResponse(status_code=411, content={"detail": "length_required"})
    82	        if int(length) > _body_limit(request.url.path):
    83	            return JSONResponse(status_code=413, content={"detail": "body_too_large"})
    84	    return await call_next(request)
    85	
    86	
    87	class RunRequest(BaseModel):
    88	    exercise_id: str = Field(min_length=1, max_length=100)
    89	    code: str = Field(min_length=1, max_length=MAX_CODE_CHARS)
    90	
    91	
    92	@app.exception_handler(RequestValidationError)
    93	async def _invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
    94	    # Handler mặc định trả lại nguyên `input`: vừa lặp lại code học viên, vừa nổ 500 khi input
    95	    # chứa surrogate lẻ ("\ud800" là JSON hợp lệ nhưng không mã hoá UTF-8 được).
    96	    fields = sorted({".".join(str(part) for part in error["loc"][1:]) for error in exc.errors()})
    97	    return JSONResponse(status_code=422, content={"detail": "invalid_request", "fields": fields})
    98	
    99	
   100	@app.exception_handler(OperationalError)
   101	async def _database_unavailable(request: Request, exc: OperationalError) -> JSONResponse:
   102	    # DB chết / không kết nối được: 503 có nghĩa thay vì 500, không lộ chi tiết kết nối.
   103	    logger.warning("database unavailable on %s: %s", request.url.path, type(exc.orig).__name__)
   104	    return JSONResponse(status_code=503, content={"detail": "database_unavailable"})
   105	
   106	
   107	@app.exception_handler(DataError)
   108	async def _unstorable_input(request: Request, exc: DataError) -> JSONResponse:
   109	    # Lưới cuối: dữ liệu Postgres không lưu được (NUL, JSON NaN…) lọt qua validate của endpoint →
   110	    # 422 thay vì 500. Validate ở boundary vẫn là chỗ chính; đây chỉ để không có lỗ hổng nào thành 500.
   111	    logger.warning("unstorable input on %s: %s", request.url.path, type(exc.orig).__name__)
   112	    return JSONResponse(status_code=422, content={"detail": "invalid_request"})
   113	
   114	
   115	@app.exception_handler(ContentNotLoaded)
   116	async def _content_not_loaded(request: Request, exc: ContentNotLoaded) -> JSONResponse:
   117	    return JSONResponse(status_code=503, content={"detail": "content_not_loaded"})
   118	
   119	
   120	class RunError(BaseModel):
   121	    kind: Literal["syntax", "runtime"]
   122	    line: int | None
   123	    message: str
   124	
   125	
   126	class RunTest(BaseModel):
   127	    call: str
   128	    expected: str
   129	    actual: str | None
   130	    passed: bool
   131	
   132	
   133	class RunResponse(BaseModel):
   134	    status: Literal["passed", "failed", "error", "timeout"]
   135	    error: RunError | None
   136	    tests: list[RunTest]
   137	    stdout: str
   138	    duration_ms: int
   139	
   140	
   141	def get_runner() -> CodeRunner:
   142	    return _RUNNER
   143	
   144	
   145	@app.post("/run", response_model=RunResponse)
   146	async def run(
   147	    request: RunRequest,
   148	    runner: CodeRunner = Depends(get_runner),
   149	    lookup_judge: JudgeLookup = Depends(get_judge_lookup),
   150	    token: str | None = Depends(optional_bearer),
   151	    lookup_user: UserLookup = Depends(get_user_lookup),
   152	    record_pass: PassRecorder = Depends(get_pass_recorder),
   153	) -> RunResponse:
   154	    # Tra DB (sync) trong threadpool để không chặn event loop; kết nối trả lại pool trước khi
   155	    # chờ máy chấm.
   156	    judge = await run_in_threadpool(lookup_judge, request.exercise_id)
   157	    if judge is None:
   158	        raise HTTPException(status_code=404, detail="exercise_not_found")
   159	    # Token sai/hết hạn: vẫn chấm như khách (không ghi tiến độ), không chặn việc Run. Chế độ mở
   160	    # (AUTH_OPEN_AS): không token cũng ra user mở → ghi tiến độ cho user đó.
   161	    user = await run_in_threadpool(lookup_user, token)
   162	
   163	    payload = json.dumps(
   164	        {
   165	            "code": request.code,
   166	            "function": judge.function,
   167	            "class_name": judge.class_name,
   168	            "cases": judge.cases,
   169	        },
   170	        ensure_ascii=False,
   171	    )
   172	    started = time.monotonic()
   173	    try:
   174	        async with _RUN_SLOTS:
   175	            execution = await runner.run(HARNESS_SOURCE, payload)
   176	    except RunnerUnavailable as exc:
   177	        logger.warning("runner unavailable for %s: %s", request.exercise_id, exc)
   178	        raise HTTPException(status_code=503, detail="runner_unavailable") from None
   179	    duration_ms = int((time.monotonic() - started) * 1000)
   180	
   181	    if execution.status == "timeout":
   182	        return RunResponse(status="timeout", error=None, tests=[], stdout="", duration_ms=duration_ms)
   183	
   184	    result = harness.parse_result(execution.stdout)
   185	    if result is not None:
   186	        # Code học viên chạy cùng tiến trình với harness nên có thể in một dòng kết quả
   187	        # sai dạng; dòng đó coi như không đọc được, không để thành 500.
   188	        try:
   189	            response = RunResponse.model_validate({**result, "duration_ms": duration_ms})
   190	        except ValidationError:
   191	            logger.warning("harness result has wrong shape for %s", request.exercise_id)
   192	        else:
   193	            # Chỉ server ghi passed, và chỉ khi máy chấm xác nhận (client không tự khai được).
   194	            if user is not None and response.status == "passed":
   195	                try:
   196	                    await run_in_threadpool(record_pass, user.id, request.exercise_id)
   197	                except Exception:
   198	                    # Kết quả chấm vẫn trả về; chỉ mất lần ghi tiến độ này (Run lại là ghi được).
   199	                    logger.exception("record_pass failed for %s", request.exercise_id)
   200	            return response
   201	    if execution.status == "error":
   202	        # Harness bị dừng trước khi in kết quả (vd hết bộ nhớ): lỗi do code học viên.
   203	        message = execution.message or (execution.stderr.strip().splitlines() or ["Chương trình bị dừng"])[-1]
   204	        return RunResponse(
   205	            status="error",
   206	            error=RunError(kind="runtime", line=None, message=message),
   207	            tests=[],
   208	            stdout="",
   209	            duration_ms=duration_ms,
   210	        )
   211	    logger.warning("harness output not understood for %s", request.exercise_id)
   212	    raise HTTPException(status_code=503, detail="runner_unavailable")
     1	"""API quản trị nội dung (chỉ admin) dưới `/api/admin`. DB là nguồn chính của nội dung.
     2	
     3	- GET  /api/admin/content   → {version, content}: nội dung đầy đủ (CÓ judge), `version` = admin_version.
     4	- POST /api/admin/validate  {content} → {ok, errors}: chạy đủ luật, không ghi.
     5	- PUT  /api/admin/content   {base_version, content} → {version} | 409 version_conflict | 422 {errors}.
     6	- GET/POST/DELETE /api/admin/mcp-access[/{sub}]: cấp/thu hồi quyền sửa nội dung qua `/mcp` (app.mcp_access).
     7	
     8	Ghi đi đúng một đường với CLI: `load_content` (validate + thay toàn bộ, một transaction, khoá
     9	`CONTENT_WRITE_LOCK`). Kiểm version và ghi nằm trong cùng khoá, nên hai admin không ghi đè nhau.
    10	Không chạy lời giải mẫu trên server (không thực thi code ở đây) — việc đó là của Run trên máy chấm.
    11	"""
    12	
    13	from __future__ import annotations
    14	
    15	import json
    16	import logging
    17	from typing import Any
    18	
    19	from fastapi import APIRouter, Depends, HTTPException, Request
    20	from fastapi.concurrency import run_in_threadpool
    21	from fastapi.responses import JSONResponse, Response
    22	from pydantic import BaseModel, ConfigDict, Field, ValidationError
    23	from sqlalchemy.exc import DataError, IntegrityError
    24	from sqlalchemy.orm import Session
    25	
    26	from app.auth import CurrentUser, require_admin
    27	from app.db import get_session
    28	from app.export_content import admin_version, export_content
    29	from app.load_content import load_content, lock_content, validation_errors
    30	from app.mcp_access import allow, list_access, revoke
    31	
    32	logger = logging.getLogger("admin")
    33	
    34	# Đặt ở cấp router: route admin thêm sau này không thể quên kiểm quyền.
    35	router = APIRouter(prefix="/api/admin", dependencies=[Depends(require_admin)])
    36	
    37	MAX_ERRORS = 200
    38	
    39	
    40	class ContentIn(BaseModel):
    41	    model_config = ConfigDict(extra="forbid")
    42	    content: dict[str, Any]
    43	
    44	
    45	class SaveIn(BaseModel):
    46	    model_config = ConfigDict(extra="forbid")
    47	    base_version: str = Field(min_length=1, max_length=100)
    48	    content: dict[str, Any]
    49	
    50	
    51	class McpAccessIn(BaseModel):
    52	    model_config = ConfigDict(extra="forbid")
    53	    sub: str
    54	    email: str
    55	    label: str = ""
    56	
    57	
    58	class _BadBody(Exception):
    59	    def __init__(self, errors: list[str]):
    60	        self.errors = errors
    61	
    62	
    63	def _capped(errors: list[str]) -> list[str]:
    64	    extra = len(errors) - MAX_ERRORS
    65	    return errors[:MAX_ERRORS] + ([f"… và {extra} lỗi nữa"] if extra > 0 else [])
    66	
    67	
    68	def _invalid(errors: list[str]) -> JSONResponse:
    69	    """Mọi 422 của admin cùng một dạng `{errors: [...]}` để app hiện được."""
    70	    return JSONResponse(status_code=422, content={"errors": _capped(errors)})
    71	
    72	
    73	async def _parse(request: Request, model: type[BaseModel]):
    74	    """Đọc body SAU khi đã qua require_admin: không khai body trong chữ ký route, vì FastAPI sẽ đọc và
    75	    parse body (tới 4MB) trước cả khi kiểm quyền — khách chưa đăng nhập cũng bắt server parse được."""
    76	    try:
    77	        raw = json.loads(await request.body())
    78	    except (ValueError, UnicodeDecodeError, RecursionError):  # RecursionError: `[[[[…` lồng sâu
    79	        raise _BadBody(["body không phải JSON hợp lệ"]) from None
    80	    try:
    81	        return model.model_validate(raw)
    82	    except ValidationError as exc:
    83	        raise _BadBody([f'{".".join(str(p) for p in e["loc"]) or "body"}: {e["msg"]}' for e in exc.errors()]) from None
    84	
    85	
    86	@router.get("/content")
    87	def get_admin_content(session: Session = Depends(get_session)) -> dict:
    88	    data = export_content(session)
    89	    return {"version": admin_version(data), "content": data}
    90	
    91	
    92	@router.post("/validate")
    93	async def validate_content(request: Request):
    94	    try:
    95	        body = await _parse(request, ContentIn)
    96	    except _BadBody as exc:
    97	        return _invalid(exc.errors)
    98	    errors = await run_in_threadpool(validation_errors, body.content)
    99	    return {"ok": not errors, "errors": _capped(errors)}
   100	
   101	
   102	def _save(body: SaveIn, user: CurrentUser, session: Session):
   103	    errors = validation_errors(body.content)  # trước khi khoá: nội dung sai thì không giữ khoá ghi
   104	    if errors:
   105	        return _invalid(errors)
   106	    lock_content(session)
   107	    current = admin_version(export_content(session))
   108	    if body.base_version != current:
   109	        raise HTTPException(status_code=409, detail="version_conflict")
   110	    try:
   111	        load_content(session, body.content, validated=True)
   112	    except DataError as exc:
   113	        # Lọt qua validate mà DB vẫn từ chối: trả cùng dạng lỗi để admin thấy, không ghi gì.
   114	        session.rollback()
   115	        logger.warning("admin save rejected by DB: %s", type(exc.orig).__name__)
   116	        return _invalid([f"DB từ chối nội dung ({type(exc.orig).__name__}) — kiểm độ dài id/tên"])
   117	    version = admin_version(export_content(session))
   118	    session.commit()
   119	    logger.info("admin %s saved content %s -> %s", user.email, current, version)
   120	    return {"version": version}
   121	
   122	
   123	@router.put("/content")
   124	async def save_content(
   125	    request: Request,
   126	    user: CurrentUser = Depends(require_admin),
   127	    session: Session = Depends(get_session),
   128	):
   129	    try:
   130	        body = await _parse(request, SaveIn)
   131	    except _BadBody as exc:
   132	        return _invalid(exc.errors)
   133	    return await run_in_threadpool(_save, body, user, session)
   134	
   135	
   136	@router.get("/mcp-access")
   137	def get_mcp_access(session: Session = Depends(get_session)) -> dict:
   138	    return {"items": list_access(session)}
   139	
   140	
   141	def _grant(body: McpAccessIn, user: CurrentUser, session: Session):
   142	    try:
   143	        item = allow(session, body.sub, body.email, body.label)
   144	        session.commit()
   145	    except ValueError as exc:
   146	        session.rollback()
   147	        return _invalid([str(exc)])
   148	    except IntegrityError:  # hai admin cấp cùng một sub mới đúng lúc
   149	        session.rollback()
   150	        return _invalid(["sub vừa được cấp ở nơi khác — tải lại danh sách rồi thử lại"])
   151	    logger.info("admin %s granted mcp access sub=%s as %s", user.email, item["sub"], item["email"])
   152	    return {"item": item}
   153	
   154	
   155	@router.post("/mcp-access")
   156	async def post_mcp_access(
   157	    request: Request,
   158	    user: CurrentUser = Depends(require_admin),
   159	    session: Session = Depends(get_session),
   160	):
   161	    try:
   162	        body = await _parse(request, McpAccessIn)
   163	    except _BadBody as exc:
   164	        return _invalid(exc.errors)
   165	    return await run_in_threadpool(_grant, body, user, session)
   166	
   167	
   168	@router.delete("/mcp-access/{sub}")
   169	def delete_mcp_access(
   170	    sub: str,
   171	    user: CurrentUser = Depends(require_admin),
   172	    session: Session = Depends(get_session),
   173	):
   174	    if not revoke(session, sub):
   175	        raise HTTPException(status_code=404, detail="not_found")
   176	    session.commit()
   177	    logger.info("admin %s revoked mcp access sub=%s", user.email, sub.strip())
   178	    return Response(status_code=204)
     1	"""Nạp `content/content.json` vào Postgres: thay toàn bộ, một transaction (idempotent).
     2	
     3	DB là nguồn chính của nội dung (admin sửa thẳng DB qua `/api/admin/content`), nên CLI không còn
     4	mặc định ghi đè:
     5	
     6	    python -m app.load_content --if-empty [path]   # chỉ nạp khi DB chưa có nội dung (deploy dùng cái này)
     7	    python -m app.load_content --force [path]      # ghi đè có chủ ý (export trước: app.export_content)
     8	
     9	`version` = sha256 của payload công khai (bỏ `judge` và `version`), nên cùng nội dung thì cùng version.
    10	"""
    11	
    12	from __future__ import annotations
    13	
    14	import hashlib
    15	import json
    16	import math
    17	import sys
    18	from collections import Counter
    19	from typing import Any
    20	
    21	from pydantic import ValidationError
    22	from sqlalchemy import delete, select, text
    23	from sqlalchemy.orm import Session
    24	
    25	from app.content_rules import content_rule_errors
    26	from app.content_schema import SourceContent
    27	from app.tables import Block, CodeFile, ContentMeta, Exercise, FileExercise, Theme, Topic
    28	
    29	DEFAULT_PATH = "content/content.json"
    30	# Mọi đường ghi nội dung (CLI + admin PUT) giữ khoá này tới hết transaction: hai lần ghi không xen nhau,
    31	# và admin kiểm version rồi ghi trong cùng một khoá.
    32	CONTENT_WRITE_LOCK = 0x5C5_C0DE
    33	
    34	
    35	def public_payload(data: dict) -> dict:
    36	    """Phần công khai của content.json: bỏ `version` và `judge` của từng bài (không sửa `data`)."""
    37	    return {
    38	        "themes": data["themes"],
    39	        "exercises": {
    40	            key: {k: v for k, v in exercise.items() if k != "judge"}
    41	            for key, exercise in data["exercises"].items()
    42	        },
    43	    }
    44	
    45	
    46	def compute_version(data: dict) -> str:
    47	    canonical = json.dumps(public_payload(data), sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    48	    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    49	
    50	
    51	def _walk_topics(topics: list[dict], parent_id: str | None = None):
    52	    """Duyệt trước (preorder) cây module: yield (topic, parent_id) — cha trước con."""
    53	    for tp in topics:
    54	        yield tp, parent_id
    55	        yield from _walk_topics(tp.get("modules", []), tp.get("id"))
    56	
    57	
    58	def _scenario_errors(cases: list) -> list[tuple[int, str]]:
    59	    """Case dạng kịch bản (`call`): steps/call phải compile được và expect có `return` hoặc `raises`.
    60	
    61	    Bắt lỗi soạn bài ở đây — để lọt tới harness thì người học thấy lỗi như thể code của mình sai.
    62	    """
    63	    out: list[tuple[int, str]] = []
    64	    for i, case in enumerate(cases):
    65	        if not isinstance(case, dict):
    66	            out.append((i, "case phải là object"))
    67	            continue
    68	        if "call" not in case:
    69	            out.extend((i, msg) for msg in _args_case_errors(case))
    70	            continue
    71	        steps = case.get("steps", [])
    72	        if not isinstance(steps, list) or not all(isinstance(x, str) for x in steps) or not isinstance(case["call"], str):
    73	            out.append((i, "`steps` phải là list chuỗi và `call` là chuỗi"))
    74	            continue
    75	        try:
    76	            for step in steps:
    77	                compile(step, "<case>", "exec")
    78	            compile(case["call"], "<case>", "eval")
    79	        except (SyntaxError, TypeError, ValueError, MemoryError, RecursionError) as exc:
    80	            # MemoryError/RecursionError: biểu thức lồng quá sâu làm parser tràn — vẫn là lỗi soạn bài.
    81	            out.append((i, f"steps/call không compile được: {type(exc).__name__}: {exc}"[:300]))
    82	        expect = case.get("expect")
    83	        if not isinstance(expect, dict) or not ({"return", "raises"} & expect.keys()):
    84	            out.append((i, "expect cần `return` hoặc `raises`"))
    85	        elif "raises" in expect and not isinstance(expect["raises"], str):
    86	            out.append((i, "`raises` phải là tên exception (chuỗi)"))
    87	    return out
    88	
    89	
    90	def _args_case_errors(case: dict) -> list[str]:
    91	    """Case dạng `args` (hàm rời) đúng shape harness đọc: `args` list, `expect` có `return`, hoặc
    92	    `value` + `arg` (chỉ số tham số bị sửa tại chỗ). Sai shape thì học viên Run sẽ thấy lỗi như thể
    93	    code của mình sai."""
    94	    expect = case.get("expect")
    95	    if not isinstance(case.get("args"), list):
    96	        return ["case cần `args` (list) hoặc `call`"]
    97	    if not isinstance(expect, dict):
    98	        return ["case cần `expect` (object)"]
    99	    if "return" in expect:
   100	        return []
   101	    arg = expect.get("arg")
   102	    if "value" in expect and isinstance(arg, int) and not isinstance(arg, bool) and 0 <= arg < len(case["args"]):
   103	        return []
   104	    return ["expect cần `return`, hoặc `value` + `arg` là chỉ số hợp lệ trong `args`"]
   105	
   106	
   107	def _diagram_errors(diagram: dict) -> list[str]:
   108	    """Sơ đồ class: tên class duy nhất; quan hệ trỏ tới class có thật; `via` là method của `from`."""
   109	    out: list[str] = []
   110	    classes = diagram.get("classes", [])
   111	    dup = _duplicates([c.get("name") for c in classes])
   112	    if dup:
   113	        out.append(f"sơ đồ: class trùng {dup}")
   114	    methods = {c.get("name"): set(c.get("methods", [])) for c in classes}
   115	    for r in diagram.get("relations", []):
   116	        src, dst = r.get("from"), r.get("to")
   117	        for end in (src, dst):
   118	            if end not in methods:
   119	                out.append(f'sơ đồ: quan hệ {src} → {dst} trỏ tới class không có: "{end}"')
   120	        if src in methods:
   121	            extra = [m for m in r.get("via", []) if m not in methods[src]]
   122	            if extra:
   123	                out.append(f"sơ đồ: via {extra} không phải method của {src}")
   124	    return out
   125	
   126	
   127	def _duplicates(ids: list[str]) -> list[str]:
   128	    return sorted(i for i, n in Counter(ids).items() if n > 1)
   129	
   130	
   131	MAX_DEPTH = 64
   132	MAX_NODES = 200_000  # tổng số giá trị trong cây (content.json thật ~10k); chặn trước pydantic
   133	
   134	
   135	def _unstorable(value: Any) -> str | None:
   136	    """Thứ Postgres không lưu được trong text/JSONB: ký tự NUL, chuỗi không mã hoá UTF-8 được (surrogate
   137	    lẻ), NaN/Infinity. Duyệt từng giá trị (không đệ quy) — kiểm trên JSON đã dump sẽ bắt nhầm chuỗi
   138	    hợp lệ chứa chữ `\\u0000` (vd bài dạy escape)."""
   139	    stack: list[tuple[Any, int]] = [(value, 0)]
   140	    nodes = 0
   141	    while stack:
   142	        v, depth = stack.pop()
   143	        nodes += 1
   144	        if nodes > MAX_NODES:
   145	            return f"content quá lớn (> {MAX_NODES} giá trị)"
   146	        if depth > MAX_DEPTH:
   147	            return f"content lồng quá {MAX_DEPTH} tầng"
   148	        if isinstance(v, dict):
   149	            stack.extend((k, depth + 1) for k in v.keys())
   150	            stack.extend((x, depth + 1) for x in v.values())
   151	        elif isinstance(v, list):
   152	            if len(v) > MAX_LIST:
   153	                return f"có danh sách quá {MAX_LIST} phần tử"
   154	            stack.extend((x, depth + 1) for x in v)
   155	        elif isinstance(v, str):
   156	            if len(v) > MAX_TEXT:
   157	                return f"có chuỗi dài quá {MAX_TEXT} ký tự"
   158	            if "\x00" in v:
   159	                return "content chứa ký tự NUL"
   160	            try:
   161	                v.encode("utf-8")
   162	            except UnicodeEncodeError:
   163	                return "content chứa chuỗi không mã hoá UTF-8 được"
   164	        elif isinstance(v, float) and not math.isfinite(v):
   165	            return "content chứa số NaN/Infinity"
   166	    return None
   167	
   168	
   169	# Trần số lượng: nội dung thật ~3 theme / ~25 bài; trần rộng gấp nhiều lần nhưng giữ chi phí kiểm có hạn.
   170	MAX_THEMES = 50
   171	MAX_TOPICS = 1000
   172	MAX_EXERCISES = 1000
   173	MAX_DIAGRAM_CLASSES = 200
   174	# Trần độ dài: luật nội dung có regex/quét chuỗi; không có trần thì một chuỗi dài vài trăm KB làm CPU
   175	# chạy hàng chục giây (regex giữ GIL → treo cả server, kể cả /run của học viên).
   176	MAX_TEXT = 20_000  # template/solution thật vài trăm ký tự
   177	MAX_LIST = 1000
   178	MAX_ANSWER = 500  # đáp án một ô ≤ 2 dòng
   179	MAX_CLASS_MEMBERS = 100  # thuộc tính + method của một lớp trong sơ đồ
   180	MAX_CASES = 1000  # tổng test case toàn bộ nội dung (thật ~110) — mỗi steps/call được compile()
   181	MAX_CODE_LINE = 1000  # một step/call: compile biểu thức lồng sâu dài vài chục KB tốn hàng chục ms
   182	
   183	
   184	def _size_errors(data: dict) -> list[str]:
   185	    out = []
   186	    themes = data["themes"]
   187	    topics = sum(1 for th in themes for _ in _walk_topics(th["topics"]))
   188	    for what, n, cap in (
   189	        ("theme", len(themes), MAX_THEMES),
   190	        ("module", topics, MAX_TOPICS),
   191	        ("bài", len(data["exercises"]), MAX_EXERCISES),
   192	    ):
   193	        if n > cap:
   194	            out.append(f"quá nhiều {what}: {n} > {cap}")
   195	    for th in themes:
   196	        n = len(th["diagram"]["classes"])
   197	        if n > MAX_DIAGRAM_CLASSES:
   198	            out.append(f'theme {th["id"]}: sơ đồ quá nhiều class: {n} > {MAX_DIAGRAM_CLASSES}')
   199	        for c in th["diagram"]["classes"]:
   200	            if len(c["attributes"]) + len(c["methods"]) > MAX_CLASS_MEMBERS:
   201	                out.append(f'theme {th["id"]}: class {c["name"][:40]} quá {MAX_CLASS_MEMBERS} thuộc tính + method')
   202	    cases = [c for ex in data["exercises"].values() for c in ex["judge"]["cases"]]
   203	    if len(cases) > MAX_CASES:
   204	        out.append(f"quá nhiều test case: {len(cases)} > {MAX_CASES}")
   205	    if any(
   206	        isinstance(c, dict) and any(isinstance(x, str) and len(x) > MAX_CODE_LINE for x in [c.get("call"), *(c.get("steps") or [] if isinstance(c.get("steps"), list) else [])])
   207	        for c in cases
   208	    ):
   209	        out.append(f"có steps/call dài quá {MAX_CODE_LINE} ký tự")
   210	    for key, ex in data["exercises"].items():
   211	        for b in ex["blocks"]:
   212	            if any(len(a) > MAX_ANSWER for a in b["accepted_answers"]):
   213	                out.append(f"bài {key[:40]}: đáp án dài quá {MAX_ANSWER} ký tự")
   214	    return out
   215	
   216	
   217	def validation_errors(data: Any) -> list[str]:
   218	    """Mọi lỗi của bộ nội dung (rỗng = hợp lệ). Không đụng DB. Dùng chung cho CLI và admin."""
   219	    if not isinstance(data, dict):
   220	        return ["content phải là object"]
   221	    bad = _unstorable(data)
   222	    if bad:
   223	        return [bad]
   224	    try:
   225	        SourceContent.model_validate(data)
   226	    except ValidationError as exc:
   227	        return [f'{".".join(str(p) for p in err["loc"])}: {err["msg"]}' for err in exc.errors()]
   228	    too_big = _size_errors(data)
   229	    if too_big:
   230	        return too_big  # chặn trước các luật tốn CPU (ghép code, sơ đồ)
   231	
   232	    errors: list[str] = []
   233	    themes = data.get("themes")
   234	    exercises = data.get("exercises")
   235	
   236	    topics = [t for th in themes for t, _ in _walk_topics(th.get("topics", []))]
   237	    files = [f for t in topics for f in t.get("files", [])]
   238	    for kind, items in (("theme", themes), ("topic", topics), ("file", files)):
   239	        dup = _duplicates([i.get("id") for i in items])
   240	        if dup:
   241	            errors.append(f"id {kind} trùng: {dup}")
   242	
   243	    for th in themes:
   244	        errors.extend(f'theme {th.get("id")}: {msg}' for msg in _diagram_errors(th.get("diagram") or {}))
   245	
   246	    for key, ex in exercises.items():
   247	        if ex.get("id") != key:
   248	            errors.append(f'exercises["{key}"] có id khác key: "{ex.get("id")}"')
   249	        blocks = ex.get("blocks", [])
   250	        dup_labels = _duplicates([b.get("label") for b in blocks])
   251	        if dup_labels:
   252	            errors.append(f"bài {key}: label ô trùng {dup_labels}")
   253	        judge = ex.get("judge")
   254	        if not isinstance(judge, dict) or not judge.get("solution"):
   255	            errors.append(f"bài {key}: thiếu judge.solution")
   256	        if not isinstance(judge, dict) or not judge.get("cases"):
   257	            errors.append(f"bài {key}: judge.cases cần ít nhất 1 case")
   258	        else:
   259	            errors.extend(f"bài {key}: case {i}: {msg}" for i, msg in _scenario_errors(judge["cases"]))
   260	            if ex.get("class_name"):
zsh:1: no matches found: requirements*

codex
Điểm mình đang kiểm kỹ nhất là ranh giới task/thread: JWT claims được đặt ở async request task nhưng tool chạy qua SDK rồi lại offload sang threadpool. Nếu propagation không đúng, toàn bộ tool sẽ fail hoặc tệ hơn là dùng nhầm identity; test hiện tại có thể che lỗi này vì dùng chung một SQLAlchemy session.
exec
/bin/zsh -lc "git show 12f9085:backend/app/load_content.py | nl -ba | sed -n '260,560p'; git show 12f9085:backend/app/db.py | nl -ba; git show 12f9085:backend/app/mcp_auth.py | nl -ba | sed -n '1,280p'; find backend -maxdepth 3 -type f \\( -name 'pyproject.toml' -o -name 'requirements.txt' -o -name 'uv.lock' \\) -print; find . -maxdepth 4 -type d -name 'mcp' -path '*site-packages*' -print 2>/dev/null | head" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
   260	            if ex.get("class_name"):
   261	                # Bài method chỉ chấm được bằng case kịch bản (harness không gọi method theo `args`).
   262	                errors.extend(
   263	                    f"bài {key}: case {i}: bài method cần case dạng `call`"
   264	                    for i, case in enumerate(judge["cases"])
   265	                    if not isinstance(case, dict) or "call" not in case
   266	                )
   267	
   268	    dup_blocks = _duplicates([b.get("id") for ex in exercises.values() for b in ex.get("blocks", [])])
   269	    if dup_blocks:
   270	        errors.append(f"id block trùng: {dup_blocks}")
   271	
   272	    for f in files:
   273	        for ex_id in f.get("exercise_ids", []):
   274	            if ex_id not in exercises:
   275	                errors.append(f'file {f.get("id")}: exercise_ids có id không tồn tại: "{ex_id}"')
   276	        dup_ex = _duplicates(f.get("exercise_ids", []))
   277	        if dup_ex:
   278	            errors.append(f'file {f.get("id")}: exercise_ids lặp {dup_ex}')
   279	
   280	    if not errors:
   281	        # Luật nội dung (marker, ghép == solution, ≤3 ô, sơ đồ khớp code…) cần cấu trúc đã đúng.
   282	        errors.extend(content_rule_errors(data))
   283	    return errors
   284	
   285	
   286	def validate(data: dict) -> None:
   287	    """Ném ValueError nêu rõ chỗ sai. Không đụng DB."""
   288	    errors = validation_errors(data)
   289	    if errors:
   290	        raise ValueError("content không hợp lệ: " + "; ".join(errors))
   291	
   292	
   293	# Chờ khoá tối đa chừng này (một lần ghi đang treo không được chặn mọi lần ghi khác vô hạn). SET LOCAL
   294	# áp cho MỌI lần chờ khoá tới hết transaction (cả DELETE/INSERT sau đó), không chỉ advisory lock.
   295	LOCK_TIMEOUT = "15s"
   296	
   297	
   298	def lock_content(session: Session) -> None:
   299	    session.execute(text(f"SET LOCAL lock_timeout = '{LOCK_TIMEOUT}'"))
   300	    session.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": CONTENT_WRITE_LOCK})
   301	
   302	
   303	def has_content(session: Session) -> bool:
   304	    return session.scalar(select(ContentMeta.value).where(ContentMeta.key == "version")) is not None
   305	
   306	
   307	def load_content(session: Session, data: dict[str, Any], *, validated: bool = False) -> str:
   308	    """Validate rồi thay toàn bộ nội dung trong transaction của `session`. Trả version.
   309	
   310	    Không commit — caller quyết định (CLI commit; test rollback). Lỗi giữa chừng thì caller rollback.
   311	    """
   312	    if not validated:  # admin đã validate NGOÀI khoá ghi, không chạy lại luật tốn CPU trong khoá
   313	        validate(data)
   314	    version = compute_version(data)
   315	    lock_content(session)
   316	
   317	    # FileExercise/Block xoá trước cho rõ ràng; phần còn lại cascade theo FK.
   318	    for model in (FileExercise, Block, CodeFile, Topic, Theme, Exercise, ContentMeta):
   319	        session.execute(delete(model))
   320	
   321	    exercises = data["exercises"]
   322	    for key, ex in exercises.items():
   323	        session.add(
   324	            Exercise(
   325	                id=key,
   326	                title=ex["title"],
   327	                class_name=ex["class_name"],
   328	                function_name=ex["function_name"],
   329	                params=ex["params"],
   330	                template=ex["template"],
   331	                challenge=ex["challenge"],
   332	                judge_solution=ex["judge"]["solution"],
   333	                judge_cases=ex["judge"]["cases"],
   334	            )
   335	        )
   336	    session.flush()
   337	    for ex in exercises.values():
   338	        for pos, b in enumerate(ex["blocks"]):
   339	            session.add(
   340	                Block(
   341	                    id=b["id"],
   342	                    exercise_id=ex["id"],
   343	                    position=pos,
   344	                    label=b["label"],
   345	                    title=b["title"],
   346	                    prompt=b["prompt"],
   347	                    indent_level=b["indent_level"],
   348	                    accepted_answers=b["accepted_answers"],
   349	                    expected_output=b["expected_output"],
   350	                    explanation=b["explanation"],
   351	                    hints=b["hints"],
   352	                    vocab=b["vocab"],
   353	                )
   354	            )
   355	    for ti, th in enumerate(data["themes"]):
   356	        session.add(
   357	            Theme(
   358	                id=th["id"],
   359	                position=ti,
   360	                name=th["name"],
   361	                description=th["description"],
   362	                tags=th["tags"],
   363	                diagram=th["diagram"],
   364	            )
   365	        )
   366	        session.flush()
   367	        # position = thứ tự preorder trong theme → cha flush trước con (FK parent_id).
   368	        for pi, (tp, parent_id) in enumerate(_walk_topics(th["topics"])):
   369	            session.add(
   370	                Topic(
   371	                    id=tp["id"],
   372	                    theme_id=th["id"],
   373	                    parent_id=parent_id,
   374	                    position=pi,
   375	                    name=tp["name"],
   376	                    description=tp["description"],
   377	                )
   378	            )
   379	            session.flush()
   380	            for fi, f in enumerate(tp["files"]):
   381	                session.add(CodeFile(id=f["id"], topic_id=tp["id"], position=fi, name=f["name"]))
   382	                session.flush()
   383	                for ei, ex_id in enumerate(f["exercise_ids"]):
   384	                    session.add(FileExercise(file_id=f["id"], exercise_id=ex_id, position=ei))
   385	    session.add(ContentMeta(key="version", value=version))
   386	    session.flush()
   387	    return version
   388	
   389	
   390	USAGE = "usage: python -m app.load_content (--if-empty | --force) [path]"
   391	
   392	
   393	def main(argv: list[str]) -> int:
   394	    from app.db import SessionLocal
   395	
   396	    flags = [a for a in argv[1:] if a.startswith("--")]
   397	    paths = [a for a in argv[1:] if not a.startswith("--")]
   398	    if len(flags) != 1 or flags[0] not in ("--if-empty", "--force") or len(paths) > 1:
   399	        print(USAGE, file=sys.stderr)
   400	        return 2
   401	    path = paths[0] if paths else DEFAULT_PATH
   402	    with open(path, encoding="utf-8") as fh:
   403	        data = json.load(fh)
   404	    with SessionLocal() as session:
   405	        try:
   406	            lock_content(session)  # kiểm "rỗng" và ghi trong cùng khoá
   407	            if flags[0] == "--if-empty" and has_content(session):
   408	                print("skip: DB đã có nội dung (DB là nguồn chính; ghi đè thì dùng --force)")
   409	                return 0
   410	            version = load_content(session, data)
   411	            session.commit()
   412	        except Exception:
   413	            session.rollback()
   414	            raise
   415	    print(version)
   416	    return 0
   417	
   418	
   419	if __name__ == "__main__":
   420	    sys.exit(main(sys.argv))
     1	"""Kết nối Postgres. `DATABASE_URL` mặc định trỏ DB local của Homebrew Postgres."""
     2	
     3	from __future__ import annotations
     4	
     5	import os
     6	from collections.abc import Iterator
     7	
     8	from sqlalchemy import create_engine
     9	from sqlalchemy.orm import Session, sessionmaker
    10	
    11	DEFAULT_DATABASE_URL = "postgresql+psycopg://localhost:5432/smart_coding_study"
    12	
    13	
    14	def database_url() -> str:
    15	    return os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL)
    16	
    17	
    18	# Tạo lazy: chưa mở kết nối lúc import. connect_timeout để request không treo khi DB chết.
    19	engine = create_engine(database_url(), pool_pre_ping=True, connect_args={"connect_timeout": 5})
    20	SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)
    21	
    22	
    23	def get_session() -> Iterator[Session]:
    24	    """Dependency FastAPI: một session mỗi request."""
    25	    with SessionLocal() as session:
    26	        yield session
     1	"""Xác thực cho `/mcp`: claude.ai đăng nhập qua identity-service (OAuth 2.1 + PKCE, GitHub), backend này
     2	chỉ là resource server — verify JWT, không giữ secret, không phát token.
     3	
     4	- Discovery (RFC 9728): `/.well-known/oauth-protected-resource[/mcp]` chỉ claude.ai tới identity-service.
     5	- Token: JWT RS256 do identity-service ký; kiểm chữ ký (JWKS), `iss`, `aud` == `<PUBLIC_BASE_URL>/mcp`
     6	  (RFC 8707 — token phát cho app/resource khác bị từ chối), `exp`.
     7	- Quyền: JWT hợp lệ mới chỉ chứng minh "ai đó có tài khoản GitHub". Được sửa nội dung hay không do bảng
     8	  `mcp_access` quyết (`authorize_sub`), kiểm ở MỖI tool call nên thu hồi có hiệu lực ngay dù JWT còn hạn.
     9	- Không bao giờ dùng `AUTH_OPEN_AS` hay token `user_sessions` của app: đây là đường xác thực riêng.
    10	
    11	Env (đọc lúc gọi): `PUBLIC_BASE_URL` (vd https://codewithphuong.jacons-corp.com — thiếu thì MCP tắt),
    12	`IDENTITY_ISSUER` (mặc định https://identity.jacons-corp.com).
    13	"""
    14	
    15	from __future__ import annotations
    16	
    17	import os
    18	import threading
    19	import time
    20	from collections.abc import Callable
    21	from typing import Any
    22	
    23	import httpx
    24	import jwt
    25	from fastapi import APIRouter, HTTPException
    26	from sqlalchemy import select
    27	from sqlalchemy.orm import Session
    28	
    29	from app.auth import CurrentUser
    30	from app.tables import McpAccess, User
    31	
    32	DEFAULT_ISSUER = "https://identity.jacons-corp.com"
    33	MCP_PATH = "/mcp"
    34	SCOPES = ["content"]
    35	LEEWAY_SECONDS = 30
    36	# Phiên "ảo" của MCP trong CurrentUser: không có dòng user_sessions nào (khác OPEN_SESSION_ID = 0).
    37	MCP_SESSION_ID = -1
    38	
    39	router = APIRouter()
    40	
    41	
    42	class InvalidToken(Exception):
    43	    """Token thiếu/sai/hết hạn/không dành cho resource này → 401."""
    44	
    45	
    46	class JwksUnavailable(Exception):
    47	    """Không lấy được khoá công khai của identity-service → 503 (không phải lỗi của token)."""
    48	
    49	
    50	def public_base_url() -> str | None:
    51	    base = os.environ.get("PUBLIC_BASE_URL", "").strip().rstrip("/")
    52	    return base or None
    53	
    54	
    55	def issuer() -> str:
    56	    return os.environ.get("IDENTITY_ISSUER", "").strip().rstrip("/") or DEFAULT_ISSUER
    57	
    58	
    59	def mcp_resource(base: str) -> str:
    60	    return base + MCP_PATH
    61	
    62	
    63	def resource_metadata_url(base: str) -> str:
    64	    return f"{base}/.well-known/oauth-protected-resource{MCP_PATH}"
    65	
    66	
    67	def www_authenticate(base: str, invalid: bool) -> str:
    68	    """Header của 401: claude.ai chỉ bắt đầu đăng nhập khi thấy `resource_metadata` trên một 401."""
    69	    error = 'error="invalid_token", ' if invalid else ""
    70	    return f'Bearer {error}resource_metadata="{resource_metadata_url(base)}", scope="{" ".join(SCOPES)}"'
    71	
    72	
    73	def _http_get_json(url: str) -> Any:
    74	    response = httpx.get(url, timeout=5.0, follow_redirects=False)
    75	    response.raise_for_status()
    76	    return response.json()
    77	
    78	
    79	class JwksCache:
    80	    """Khoá công khai của identity-service, theo `kid`.
    81	
    82	    Không dùng thẳng `PyJWKClient`: nó tải lại JWKS mỗi lần gặp `kid` lạ, nên ai cũng gửi được token
    83	    `kid` ngẫu nhiên để bắt server gọi identity-service liên tục. Ở đây mọi lần tải (thành công hay lỗi)
    84	    cách nhau ít nhất `min_refresh` giây.
    85	
    86	    - Khoá hợp lệ `max_age` giây kể từ lần tải THÀNH CÔNG gần nhất; quá hạn thì tải lại.
    87	    - Tải lại lỗi: dùng tiếp khoá cũ thêm tối đa `grace` giây rồi thôi (khoá đã bị thu hồi ở identity
    88	      không được sống mãi chỉ vì identity chết).
    89	    - Lần tải gần nhất lỗi mà không có khoá dùng được → `JwksUnavailable` (503) cho MỌI request trong
    90	      lúc đó, không lẫn thành 401 — claude.ai coi 401 là token hỏng và bắt đăng nhập lại.
    91	
    92	    Giữ khoá suốt lần tải (≤5s, tối đa một lần mỗi `min_refresh`): request khác chờ chứ không bắn thêm.
    93	    """
    94	
    95	    def __init__(
    96	        self,
    97	        url: str,
    98	        fetch: Callable[[str], Any] = _http_get_json,
    99	        min_refresh: float = 60.0,
   100	        max_age: float = 3600.0,
   101	        grace: float = 3600.0,
   102	        clock: Callable[[], float] = time.monotonic,
   103	    ):
   104	        self.url = url
   105	        self._fetch = fetch
   106	        self._min_refresh = min_refresh
   107	        self._max_age = max_age
   108	        self._grace = grace
   109	        self._clock = clock
   110	        self._keys: dict[str, Any] = {}
   111	        self._last_success: float | None = None
   112	        self._last_attempt: float | None = None
   113	        self._last_failed = False
   114	        self._lock = threading.Lock()
   115	
   116	    def _load(self) -> dict[str, Any]:
   117	        try:
   118	            data = self._fetch(self.url)
   119	            if not isinstance(data, dict) or not isinstance(data.get("keys"), list):
   120	                raise ValueError("jwks shape")
   121	            jwks = jwt.PyJWKSet.from_dict(data)
   122	        except (httpx.HTTPError, ValueError, TypeError, AttributeError, KeyError, jwt.PyJWTError) as exc:
   123	            raise JwksUnavailable(type(exc).__name__) from None
   124	        keys = {k.key_id: k.key for k in jwks.keys if k.key_id and k.key_type == "RSA"}
   125	        if not keys:
   126	            raise JwksUnavailable("no RSA keys")  # không xoá khoá đang dùng được
   127	        return keys
   128	
   129	    def _try_refresh(self, now: float) -> None:
   130	        self._last_attempt = now
   131	        try:
   132	            keys = self._load()
   133	        except JwksUnavailable:
   134	            self._last_failed = True
   135	            return
   136	        self._keys, self._last_success, self._last_failed = keys, now, False
   137	
   138	    def key_for(self, kid: str) -> Any:
   139	        with self._lock:
   140	            now = self._clock()
   141	            age = None if self._last_success is None else now - self._last_success
   142	            want = age is None or age >= self._max_age or kid not in self._keys
   143	            may = self._last_attempt is None or now - self._last_attempt >= self._min_refresh
   144	            if want and may:
   145	                self._try_refresh(now)
   146	                age = None if self._last_success is None else now - self._last_success
   147	            usable = age is not None and age < self._max_age + self._grace
   148	            key = self._keys.get(kid) if usable else None
   149	            failed = self._last_failed
   150	        if key is not None:
   151	            return key
   152	        if failed or not usable:
   153	            raise JwksUnavailable("jwks")
   154	        raise InvalidToken("unknown kid")
   155	
   156	
   157	_caches: dict[str, JwksCache] = {}
   158	_caches_lock = threading.Lock()
   159	
   160	
   161	def jwks_for(iss: str) -> JwksCache:
   162	    with _caches_lock:
   163	        cache = _caches.get(iss)
   164	        if cache is None:
   165	            cache = _caches[iss] = JwksCache(f"{iss}/.well-known/jwks.json")
   166	        return cache
   167	
   168	
   169	def verify_token(token: str, *, audience: str, iss: str, keys: JwksCache) -> dict:
   170	    """Claims của JWT nếu hợp lệ cho đúng resource này; ngược lại `InvalidToken`."""
   171	    try:
   172	        header = jwt.get_unverified_header(token)
   173	    except jwt.PyJWTError:
   174	        raise InvalidToken("malformed") from None
   175	    # Chỉ RS256: chặn `alg=none` và nhầm khoá công khai thành secret HMAC (HS256).
   176	    if header.get("alg") != "RS256" or not isinstance(header.get("kid"), str):
   177	        raise InvalidToken("alg")
   178	    key = keys.key_for(header["kid"])
   179	    try:
   180	        claims = jwt.decode(
   181	            token,
   182	            key,
   183	            algorithms=["RS256"],
   184	            audience=audience,
   185	            issuer=iss,
   186	            leeway=LEEWAY_SECONDS,
   187	            options={"require": ["exp", "iss", "aud", "sub"]},
   188	        )
   189	    except jwt.PyJWTError:
   190	        raise InvalidToken("claims") from None
   191	    if not isinstance(claims.get("sub"), str) or not claims["sub"].strip():
   192	        raise InvalidToken("sub")
   193	    return claims
   194	
   195	
   196	def verify_bearer(authorization: str | None, base: str) -> dict:
   197	    """Header `Authorization` → claims. Blocking (có thể tải JWKS): gọi trong threadpool."""
   198	    scheme, _, token = (authorization or "").partition(" ")
   199	    if scheme.lower() != "bearer" or not token.strip():
   200	        raise InvalidToken("missing")
   201	    iss = issuer()
   202	    return verify_token(token.strip(), audience=mcp_resource(base), iss=iss, keys=jwks_for(iss))
   203	
   204	
   205	def authorize_sub(session: Session, sub: str) -> CurrentUser | None:
   206	    """Admin mà tài khoản identity `sub` được phép hành động thay; None nếu chưa cấp / đã thu hồi /
   207	    user đích không còn là admin. Gọi ở MỖI tool call."""
   208	    row = session.execute(
   209	        select(User.id, User.email, User.roles)
   210	        .join(McpAccess, McpAccess.user_id == User.id)
   211	        .where(McpAccess.sub == sub, McpAccess.revoked_at.is_(None))
   212	    ).first()
   213	    if row is None:
   214	        return None
   215	    user_id, email, roles = row
   216	    if "admin" not in roles:
   217	        return None
   218	    return CurrentUser(id=user_id, email=email, roles=tuple(roles), session_id=MCP_SESSION_ID)
   219	
   220	
   221	def protected_resource_metadata(base: str) -> dict:
   222	    return {
   223	        "resource": mcp_resource(base),
   224	        "authorization_servers": [issuer()],
   225	        "scopes_supported": SCOPES,
   226	        "bearer_methods_supported": ["header"],
   227	    }
   228	
   229	
   230	@router.get("/.well-known/oauth-protected-resource")
   231	@router.get("/.well-known/oauth-protected-resource/mcp")
   232	def get_protected_resource_metadata() -> dict:
   233	    base = public_base_url()
   234	    if base is None:
   235	        raise HTTPException(status_code=404, detail="mcp_not_configured")
   236	    return protected_resource_metadata(base)
backend/requirements.txt

exec
/bin/zsh -lc "sed -n '1,220p' backend/requirements.txt; find backend -maxdepth 2 -type d -name '.venv' -print; find . -maxdepth 3 -type d -name '.venv' -print; python - <<'PY'
try:
 import mcp, inspect
 print(mcp.__file__)
except Exception as e: print(type(e).__name__, e)
PY
rg -n \"class StreamableHTTPSessionManager|def handle_request|ContextVar|copy_context|max_request_body_size|session_manager\" backend/.venv .venv 2>/dev/null | head -200" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
fastapi==0.143.0
uvicorn[standard]==0.54.0
httpx==0.28.1
pytest==9.1.1
SQLAlchemy==2.1.4
psycopg[binary]==3.3.6
alembic==1.20.0
argon2-cffi==25.1.0
PyJWT[crypto]==2.15.1
mcp==2.3.0
backend/.venv
./backend/.venv
zsh:1: command not found: python

exec
/bin/zsh -lc "backend/.venv/bin/python - <<'PY'
import mcp
print(mcp.__file__)
PY
rg -n \"class StreamableHTTPSessionManager|def handle_request|ContextVar|copy_context|max_request_body_size|session_manager\" backend/.venv/lib/python*/site-packages/mcp | head -240" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 169ms:
/Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content/backend/.venv/lib/python3.14/site-packages/mcp/__init__.py

exec
/bin/zsh -lc "rg -n \"StreamableHTTPSessionManager|handle_request|max_request_body_size|copy_context|ContextVar\" backend/.venv/lib/python3.14/site-packages/mcp backend/.venv/lib/python3.14/site-packages/anyio | sed -n '1,280p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
exec
/bin/zsh -lc "find backend/.venv/lib/python3.14/site-packages/mcp -maxdepth 4 -type f | sed -n '1,200p'; backend/.venv/bin/python - <<'PY'
from mcp.server.mcpserver import MCPServer
import inspect
print(inspect.getsourcefile(MCPServer))
print(inspect.getsource(MCPServer.streamable_http_app))
print(inspect.getsource(MCPServer.session_manager.fget))
PY" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 147ms:
/Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content/backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py
    def streamable_http_app(
        self,
        *,
        streamable_http_path: str = "/mcp",
        json_response: bool = False,
        stateless_http: bool = False,
        event_store: EventStore | None = None,
        retry_interval: int | None = None,
        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
        session_idle_timeout: float | None = DEFAULT_SESSION_IDLE_TIMEOUT,
        max_sessions: int | None = DEFAULT_MAX_SESSIONS,
        transport_security: TransportSecuritySettings | None = None,
        host: str = "127.0.0.1",
    ) -> Starlette:
        """Return an instance of the StreamableHTTP server app."""
        return self._lowlevel_server.streamable_http_app(
            streamable_http_path=streamable_http_path,
            json_response=json_response,
            stateless_http=stateless_http,
            event_store=event_store,
            retry_interval=retry_interval,
            max_request_body_size=max_request_body_size,
            session_idle_timeout=session_idle_timeout,
            max_sessions=max_sessions,
            transport_security=transport_security,
            host=host,
            auth=self.settings.auth,
            token_verifier=self._token_verifier,
            auth_server_provider=self._auth_server_provider,
            custom_starlette_routes=self._custom_starlette_routes,
            debug=self.settings.debug,
        )

    @property
    def session_manager(self) -> StreamableHTTPSessionManager:
        """Get the StreamableHTTP session manager.

        This is exposed to enable advanced use cases like mounting multiple
        MCPServer instances in a single FastAPI application.

        Raises:
            RuntimeError: If called before streamable_http_app() has been called.
        """
        return self._lowlevel_server.session_manager


exec
/bin/zsh -lc "rg -uu -n \"class StreamableHTTPSessionManager|def handle_request|max_request_body_size|copy_context|ContextVar\" backend/.venv/lib/python3.14/site-packages/mcp backend/.venv/lib/python3.14/site-packages/anyio | sed -n '1,360p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py | sed -n '1,420p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/_streamable_http_modern.py | sed -n '1,360p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
backend/.venv/lib/python3.14/site-packages/anyio/lowlevel.py:135:    Like a :class:`~contextvars.ContextVar`, except scoped to the running event loop.
backend/.venv/lib/python3.14/site-packages/anyio/lowlevel.py:137:    Can be used as a context manager, Just like :class:`~contextvars.ContextVar`, that
backend/.venv/lib/python3.14/site-packages/mcp/client/streamable_http.py:658:                    async def handle_request_async():
backend/.venv/lib/python3.14/site-packages/mcp/server/sse.py:88:        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
backend/.venv/lib/python3.14/site-packages/mcp/server/sse.py:97:            max_request_body_size: Maximum size in bytes for POSTed message bodies. Requests that
backend/.venv/lib/python3.14/site-packages/mcp/server/sse.py:116:        if max_request_body_size <= 0:
backend/.venv/lib/python3.14/site-packages/mcp/server/sse.py:117:            raise ValueError("max_request_body_size must be a positive number of bytes")
backend/.venv/lib/python3.14/site-packages/mcp/server/sse.py:134:        self._post_message_app = RequestBodyLimitMiddleware(self._handle_post_message, max_request_body_size)
backend/.venv/lib/python3.14/site-packages/mcp/server/sse.py:223:        `max_request_body_size` are answered with 413 before the message is handled.
backend/.venv/lib/python3.14/site-packages/anyio/_backends/_asyncio.py:35:from contextvars import Context, copy_context
backend/.venv/lib/python3.14/site-packages/anyio/_backends/_asyncio.py:246:            self._context = contextvars.copy_context()
backend/.venv/lib/python3.14/site-packages/anyio/_backends/_asyncio.py:2698:                context = copy_context()
backend/.venv/lib/python3.14/site-packages/anyio/_backends/_asyncio.py:2747:        context = copy_context()
backend/.venv/lib/python3.14/site-packages/mcp/shared/_context_streams.py:29:    """Send-side wrapper that snapshots ``contextvars.copy_context()`` on every ``send()``."""
backend/.venv/lib/python3.14/site-packages/mcp/shared/_context_streams.py:37:        await self._inner.send((contextvars.copy_context(), item))
backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py:658:    return ctx if ctx is not None else contextvars.copy_context()
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:45:class StreamableHTTPSessionManager:
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:78:        max_request_body_size: Maximum size in bytes for Streamable HTTP request bodies. Requests that
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:95:        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:100:        if max_request_body_size <= 0:
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:101:            raise ValueError("max_request_body_size must be a positive number of bytes")
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:112:        self.max_request_body_size = max_request_body_size
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:114:        self.asgi_app = RequestBodyLimitMiddleware(self._handle_request, max_request_body_size)
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py:176:    async def handle_request(self, scope: Scope, receive: Receive, send: Send) -> None:
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http.py:474:    async def handle_request(self, scope: Scope, receive: Receive, send: Send) -> None:
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:382:        max_request_body_size: int = ...,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:398:        max_request_body_size: int = ...,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1090:        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1099:            max_request_body_size=max_request_body_size,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1123:        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1137:            max_request_body_size=max_request_body_size,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1158:        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1172:            message_path, security_settings=transport_security, max_request_body_size=max_request_body_size
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1296:        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:1309:            max_request_body_size=max_request_body_size,
backend/.venv/lib/python3.14/site-packages/mcp/server/auth/middleware/auth_context.py:10:auth_context_var = contextvars.ContextVar[AuthenticatedUser | None]("auth_context", default=None)
backend/.venv/lib/python3.14/site-packages/mcp/server/lowlevel/server.py:740:        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
backend/.venv/lib/python3.14/site-packages/mcp/server/lowlevel/server.py:767:            max_request_body_size=max_request_body_size,
backend/.venv/lib/python3.14/site-packages/mcp/shared/_request_clock.py:3:The clock travels in a `ContextVar`: the HTTP transports run each outgoing message in its sender's
backend/.venv/lib/python3.14/site-packages/mcp/shared/_request_clock.py:13:from contextvars import ContextVar
backend/.venv/lib/python3.14/site-packages/mcp/shared/_request_clock.py:44:_clock: ContextVar[RequestClock | None] = ContextVar("request_clock", default=None)
     1	"""StreamableHTTP Session Manager for MCP servers."""
     2	
     3	from __future__ import annotations
     4	
     5	import contextlib
     6	import logging
     7	import math
     8	from collections.abc import AsyncIterator
     9	from typing import TYPE_CHECKING, Any, Final
    10	from uuid import uuid4
    11	
    12	import anyio
    13	from anyio.abc import TaskStatus
    14	from mcp_types import DEFAULT_NEGOTIATED_VERSION, INTERNAL_ERROR, INVALID_REQUEST, ErrorData, JSONRPCError
    15	from mcp_types.version import HANDSHAKE_PROTOCOL_VERSIONS
    16	from starlette.requests import Request
    17	from starlette.responses import Response
    18	from starlette.types import ASGIApp, Message, Receive, Scope, Send
    19	
    20	from mcp.server._streamable_http_modern import handle_modern_request
    21	from mcp.server.auth.middleware.bearer_auth import AuthenticatedUser, AuthorizationContext, authorization_context
    22	from mcp.server.connection import Connection
    23	from mcp.server.runner import serve_connection, serve_loop
    24	from mcp.server.streamable_http import MCP_SESSION_ID_HEADER, EventStore, StreamableHTTPServerTransport
    25	from mcp.server.transport_security import DEFAULT_MAX_REQUEST_BODY_SIZE as DEFAULT_MAX_REQUEST_BODY_SIZE
    26	from mcp.server.transport_security import RequestBodyLimitMiddleware as RequestBodyLimitMiddleware
    27	from mcp.server.transport_security import TransportSecuritySettings
    28	from mcp.shared._compat import resync_tracer
    29	from mcp.shared.inbound import MCP_PROTOCOL_VERSION_HEADER
    30	from mcp.shared.jsonrpc_dispatcher import JSONRPCDispatcher
    31	from mcp.shared.transport_context import TransportContext
    32	
    33	if TYPE_CHECKING:
    34	    from mcp.server.lowlevel.server import Server
    35	
    36	logger = logging.getLogger(__name__)
    37	
    38	DEFAULT_SESSION_IDLE_TIMEOUT: Final = 30 * 60
    39	"""Default idle period in seconds after which a stateful Streamable HTTP session is closed (30 minutes)."""
    40	
    41	DEFAULT_MAX_SESSIONS: Final = 10_000
    42	"""Default maximum number of concurrent stateful Streamable HTTP sessions per session manager."""
    43	
    44	
    45	class StreamableHTTPSessionManager:
    46	    """Manages StreamableHTTP sessions with optional resumability via event store.
    47	
    48	    This class abstracts away the complexity of session management, event storage,
    49	    and request handling for StreamableHTTP transports. It handles:
    50	
    51	    1. Session tracking for clients
    52	    2. Resumability via an optional event store
    53	    3. Connection management and lifecycle
    54	    4. Request handling and transport setup
    55	    5. Idle session cleanup
    56	
    57	    Important: Only one StreamableHTTPSessionManager instance should be created
    58	    per application. The instance cannot be reused after its run() context has
    59	    completed. If you need to restart the manager, create a new instance.
    60	
    61	    Args:
    62	        app: The MCP server instance
    63	        event_store: Optional event store for resumability support. If provided, enables resumable connections
    64	            where clients can reconnect and receive missed events. If None, sessions are still tracked but not
    65	            resumable.
    66	        json_response: Whether to use JSON responses instead of SSE streams
    67	        stateless: If True, creates a completely fresh transport for each request with no session tracking or
    68	            state persistence between requests.
    69	        security_settings: Optional transport security settings.
    70	        retry_interval: Retry interval in milliseconds to suggest to clients in SSE retry field. Used for SSE
    71	            polling behavior.
    72	        session_idle_timeout: Idle timeout in seconds for stateful sessions. A session that has had no HTTP
    73	            request in flight for this long (no request being served, no open GET stream) is terminated and
    74	            removed; its ID then answers 404 and the client has to initialize a new session. When retry_interval
    75	            is also configured, ensure the idle timeout comfortably exceeds the retry interval to avoid reaping
    76	            sessions during normal SSE polling gaps. Defaults to 1800 (30 minutes); None disables the timeout so
    77	            sessions live until the client deletes them or the manager shuts down. Unused in stateless mode.
    78	        max_request_body_size: Maximum size in bytes for Streamable HTTP request bodies. Requests that
    79	            exceed this limit receive a 413 response before parsing or session creation. Defaults to 4 MiB.
    80	        max_sessions: Maximum number of concurrent stateful sessions. While that many sessions are open, a
    81	            request that would open another one receives a 503 response; existing sessions are unaffected and
    82	            room frees up as they end or expire. Defaults to 10 000; None removes the limit. Unused in stateless
    83	            mode.
    84	    """
    85	
    86	    def __init__(
    87	        self,
    88	        app: Server[Any],
    89	        event_store: EventStore | None = None,
    90	        json_response: bool = False,
    91	        stateless: bool = False,
    92	        security_settings: TransportSecuritySettings | None = None,
    93	        retry_interval: int | None = None,
    94	        session_idle_timeout: float | None = DEFAULT_SESSION_IDLE_TIMEOUT,
    95	        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
    96	        max_sessions: int | None = DEFAULT_MAX_SESSIONS,
    97	    ):
    98	        if session_idle_timeout is not None and not (math.isfinite(session_idle_timeout) and session_idle_timeout > 0):
    99	            raise ValueError("session_idle_timeout must be a positive, finite number of seconds")
   100	        if max_request_body_size <= 0:
   101	            raise ValueError("max_request_body_size must be a positive number of bytes")
   102	        if max_sessions is not None and max_sessions <= 0:
   103	            raise ValueError("max_sessions must be a positive number of sessions or None")
   104	
   105	        self.app = app
   106	        self.event_store = event_store
   107	        self.json_response = json_response
   108	        self.stateless = stateless
   109	        self.security_settings = security_settings
   110	        self.retry_interval = retry_interval
   111	        self.session_idle_timeout = session_idle_timeout
   112	        self.max_request_body_size = max_request_body_size
   113	        self.max_sessions = max_sessions
   114	        self.asgi_app = RequestBodyLimitMiddleware(self._handle_request, max_request_body_size)
   115	
   116	        # Session tracking (only used if not stateless)
   117	        self._session_creation_lock = anyio.Lock()
   118	        self._server_instances: dict[str, StreamableHTTPServerTransport] = {}
   119	        # Identity of the credential that created each session; requests for a
   120	        # session must present the same credential.
   121	        self._session_owners: dict[str, AuthorizationContext] = {}
   122	
   123	        # The task group and lifespan state are set during run()
   124	        self._task_group = None
   125	        self._lifespan_state: Any = None
   126	        # Thread-safe tracking of run() calls
   127	        self._run_lock = anyio.Lock()
   128	        self._has_started = False
   129	
   130	    @contextlib.asynccontextmanager
   131	    async def run(self) -> AsyncIterator[None]:
   132	        """Run the session manager with proper lifecycle management.
   133	
   134	        This creates and manages the task group for all session operations.
   135	
   136	        Important: This method can only be called once per instance. The same
   137	        StreamableHTTPSessionManager instance cannot be reused after this
   138	        context manager exits. Create a new instance if you need to restart.
   139	
   140	        Use this in the lifespan context manager of your Starlette app:
   141	
   142	        @contextlib.asynccontextmanager
   143	        async def lifespan(app: Starlette) -> AsyncIterator[None]:
   144	            async with session_manager.run():
   145	                yield
   146	        """
   147	        # Thread-safe check to ensure run() is only called once
   148	        async with self._run_lock:
   149	            if self._has_started:
   150	                raise RuntimeError(
   151	                    "StreamableHTTPSessionManager .run() can only be called "
   152	                    "once per instance. Create a new instance if you need to run again."
   153	                )
   154	            self._has_started = True
   155	
   156	        async with self.app.lifespan(self.app) as lifespan_state, anyio.create_task_group() as tg:
   157	            # Store for handle_request: lifespan is entered once for the
   158	            # manager's lifetime, not per request (per-connection cleanup
   159	            # belongs on `connection.exit_stack`).
   160	            self._lifespan_state = lifespan_state
   161	            self._task_group = tg
   162	            logger.info("StreamableHTTP session manager started")
   163	            try:
   164	                yield  # Let the application run
   165	            finally:
   166	                logger.info("StreamableHTTP session manager shutting down")
   167	                # Cancel task group to stop all spawned tasks
   168	                tg.cancel_scope.cancel()
   169	                self._task_group = None
   170	                self._lifespan_state = None
   171	                # Clear any remaining server instances
   172	                self._server_instances.clear()
   173	                self._session_owners.clear()
   174	        await resync_tracer()
   175	
   176	    async def handle_request(self, scope: Scope, receive: Receive, send: Send) -> None:
   177	        """Process ASGI request with proper session handling and transport setup.
   178	
   179	        Dispatches to the appropriate handler based on stateless mode.
   180	        """
   181	        await self.asgi_app(scope, receive, send)
   182	
   183	    async def _handle_request(self, scope: Scope, receive: Receive, send: Send) -> None:
   184	        if self._task_group is None:
   185	            raise RuntimeError("Task group is not initialized. Make sure to use run().")
   186	
   187	        # TODO(L49): header-only era-routing for now; body-primary classification
   188	        # is a follow-up. The legacy paths below own only the known
   189	        # initialize-handshake versions; anything else (including unknown
   190	        # values) goes to the modern entry so the classifier can validate it
   191	        # and return a structured rejection. 2025 paths below remain unchanged.
   192	        header = MCP_PROTOCOL_VERSION_HEADER.encode("ascii")
   193	        pv = next((v.decode("latin-1") for k, v in scope["headers"] if k == header), None)
   194	        if pv is not None and pv not in HANDSHAKE_PROTOCOL_VERSIONS:
   195	            await handle_modern_request(
   196	                self.app, self.security_settings, self.json_response, self._lifespan_state, scope, receive, send
   197	            )
   198	            return
   199	
   200	        # Dispatch to the appropriate handler
   201	        if self.stateless:
   202	            await self._handle_stateless_request(pv, scope, receive, send)
   203	        else:
   204	            await self._handle_stateful_request(scope, receive, send)
   205	
   206	    async def _handle_stateless_request(
   207	        self, protocol_version_hint: str | None, scope: Scope, receive: Receive, send: Send
   208	    ) -> None:
   209	        """Process request in stateless mode - creating a new transport for each request."""
   210	        logger.debug("Stateless mode: Creating new transport for this request")
   211	        # No session ID needed in stateless mode
   212	        http_transport = StreamableHTTPServerTransport(
   213	            mcp_session_id=None,  # No session tracking in stateless mode
   214	            is_json_response_enabled=self.json_response,
   215	            event_store=None,  # No event store in stateless mode
   216	            security_settings=self.security_settings,
   217	        )
   218	
   219	        # Start server in a new task
   220	        async def run_stateless_server(*, task_status: TaskStatus[None] = anyio.TASK_STATUS_IGNORED):
   221	            async with http_transport.connect() as streams:
   222	                read_stream, write_stream = streams
   223	                task_status.started()
   224	                dispatcher: JSONRPCDispatcher[TransportContext] = JSONRPCDispatcher(
   225	                    read_stream,
   226	                    write_stream,
   227	                    inline_methods=frozenset({"initialize"}),
   228	                    # No session ID means a server-to-client request can be
   229	                    # written to this POST's response stream, but the client's
   230	                    # reply has nowhere to land — `can_send_request=False`
   231	                    # makes the per-request channel raise `NoBackChannelError`
   232	                    # for requests while still allowing notifications.
   233	                    transport_builder=lambda _md: TransportContext(kind="streamable-http", can_send_request=False),
   234	                )
   235	                # Born-ready, no standalone channel: the legacy stateless path
   236	                # never opens a GET stream and need not see `initialize`. The
   237	                # header (or the spec's default-absent value) seeds
   238	                # `ctx.protocol_version`.
   239	                connection = Connection.from_envelope(
   240	                    protocol_version_hint if protocol_version_hint is not None else DEFAULT_NEGOTIATED_VERSION,
   241	                    None,
   242	                    None,
   243	                )
   244	                try:
   245	                    await serve_connection(
   246	                        self.app, dispatcher, connection=connection, lifespan_state=self._lifespan_state
   247	                    )
   248	                except Exception:  # pragma: lax no cover
   249	                    logger.exception("Stateless session crashed")
   250	
   251	        # The per-request server task only ends once the transport is
   252	        # terminated, so terminate it even if the request was cancelled.
   253	        assert self._task_group is not None
   254	        try:
   255	            await self._task_group.start(run_stateless_server)
   256	            await http_transport.handle_request(scope, receive, send)
   257	        finally:
   258	            with anyio.CancelScope(shield=True):
   259	                await http_transport.terminate()
   260	
   261	    async def _handle_stateful_request(self, scope: Scope, receive: Receive, send: Send) -> None:
   262	        """Process request in stateful mode - maintaining session state between requests."""
   263	        request = Request(scope, receive)
   264	        request_mcp_session_id = request.headers.get(MCP_SESSION_ID_HEADER)
   265	
   266	        user = scope.get("user")
   267	        requestor = authorization_context(user) if isinstance(user, AuthenticatedUser) else None
   268	
   269	        # Existing session case
   270	        if request_mcp_session_id is not None and request_mcp_session_id in self._server_instances:
   271	            transport = self._server_instances[request_mcp_session_id]
   272	            if requestor != self._session_owners.get(request_mcp_session_id):
   273	                # A session can only be used with the credential that created
   274	                # it. Respond exactly as if the session did not exist.
   275	                logger.warning(
   276	                    "Rejecting request for session %s: credential does not match the one that created the session",
   277	                    request_mcp_session_id[:64],
   278	                )
   279	                await _error_response("Session not found", 404)(scope, receive, send)
   280	                return
   281	            logger.debug("Session already exists, handling request directly")
   282	            await transport.handle_request(scope, receive, send)
   283	            if transport.is_terminated:
   284	                # The client ended the session (DELETE): forget it now rather
   285	                # than when its server task winds down.
   286	                await self._discard_session(request_mcp_session_id, transport)
   287	            return
   288	
   289	        if request_mcp_session_id is None:
   290	            # New session case. Admission (the session limit and registration)
   291	            # is decided under the lock; the request itself is served outside
   292	            # it, so one client that is slow to send its opening request does
   293	            # not hold up the others.
   294	            async with self._session_creation_lock:
   295	                http_transport = self._admit_session(requestor)
   296	            if http_transport is None:
   297	                logger.warning("Refusing to open a new session: %d sessions are already open", self.max_sessions)
   298	                await _error_response("Too many open sessions", 503, INTERNAL_ERROR)(scope, receive, send)
   299	                return
   300	            await self._serve_opening_request(http_transport, scope, receive, send)
   301	        else:
   302	            # Unknown or expired session ID - return 404 per MCP spec
   303	            # TODO(L62): Align error code once spec clarifies
   304	            # See: https://github.com/modelcontextprotocol/python-sdk/issues/1821
   305	            logger.info(f"Rejected request with unknown or expired session ID: {request_mcp_session_id[:64]}")
   306	            await _error_response("Session not found", 404)(scope, receive, send)
   307	
   308	    def _admit_session(self, requestor: AuthorizationContext | None) -> StreamableHTTPServerTransport | None:
   309	        """Register a new session for `requestor` and return its transport, or None at the session limit."""
   310	        if self.max_sessions is not None and len(self._server_instances) >= self.max_sessions:
   311	            return None
   312	        http_transport = StreamableHTTPServerTransport(
   313	            mcp_session_id=uuid4().hex,
   314	            is_json_response_enabled=self.json_response,
   315	            event_store=self.event_store,  # May be None (no resumability)
   316	            security_settings=self.security_settings,
   317	            retry_interval=self.retry_interval,
   318	            idle_timeout=self.session_idle_timeout,
   319	        )
   320	        session_id = http_transport.mcp_session_id
   321	        assert session_id is not None
   322	        if requestor is not None:
   323	            self._session_owners[session_id] = requestor
   324	        self._server_instances[session_id] = http_transport
   325	        logger.info(f"Created new transport with session ID: {session_id}")
   326	        return http_transport
   327	
   328	    async def _serve_opening_request(
   329	        self, http_transport: StreamableHTTPServerTransport, scope: Scope, receive: Receive, send: Send
   330	    ) -> None:
   331	        """Start the session's server task and let its transport answer the request that opens it.
   332	
   333	        Without a session ID only an initialize request can succeed, so if this
   334	        one is refused, fails or is cancelled (or the session's server task
   335	        cannot even be started) nothing was established: the session is
   336	        discarded again rather than kept (with its server task) around.
   337	        """
   338	        session_id = http_transport.mcp_session_id
   339	        assert session_id is not None
   340	
   341	        async def run_server(*, task_status: TaskStatus[None] = anyio.TASK_STATUS_IGNORED) -> None:
   342	            async with http_transport.connect() as streams:
   343	                read_stream, write_stream = streams
   344	                task_status.started()
   345	                try:
   346	                    # The transport cancels its idle scope once no request
   347	                    # has been in flight for `session_idle_timeout`; that
   348	                    # ends the loop and execution continues after the
   349	                    # `with` block. Without a timeout there is nothing to fire.
   350	                    idle_scope = http_transport.idle_scope
   351	                    if idle_scope is None:
   352	                        idle_scope = anyio.CancelScope()
   353	                    with idle_scope:
   354	                        # Drive via `serve_loop` (not `Server.run()`) so the
   355	                        # manager's already-entered lifespan is reused
   356	                        # rather than re-entered per session.
   357	                        await serve_loop(
   358	                            self.app,
   359	                            read_stream,
   360	                            write_stream,
   361	                            lifespan_state=self._lifespan_state,
   362	                            session_id=session_id,
   363	                        )
   364	
   365	                    if idle_scope.cancelled_caught:
   366	                        logger.info(f"Session {session_id} idle timeout")
   367	                except Exception:
   368	                    logger.exception(f"Session {session_id} crashed")
   369	                finally:
   370	                    # However the session ended (client DELETE, idle
   371	                    # timeout, crash), discard it.
   372	                    await self._discard_session(session_id, http_transport)
   373	
   374	        established = False
   375	        try:
   376	            assert self._task_group is not None
   377	            await self._task_group.start(run_server)
   378	            status = await _send_and_report_status(http_transport.handle_request, scope, receive, send)
   379	            established = status is not None and status < 400
   380	        finally:
   381	            if not established:  # pragma: no branch
   382	                await self._discard_session(session_id, http_transport)
   383	
   384	    async def _discard_session(self, session_id: str, transport: StreamableHTTPServerTransport) -> None:
   385	        """Stop tracking the session and make sure its transport refuses anything that still reaches it.
   386	
   387	        The session is forgotten first, before any await, so its ID answers 404
   388	        from the moment this is called; terminating the transport is shielded so
   389	        it completes even while the caller is being cancelled.
   390	        """
   391	        self._server_instances.pop(session_id, None)
   392	        self._session_owners.pop(session_id, None)
   393	        if not transport.is_terminated:
   394	            with anyio.CancelScope(shield=True):
   395	                await transport.terminate()
   396	
   397	
   398	def _error_response(message: str, status_code: int, code: int = INVALID_REQUEST) -> Response:
   399	    """A JSON-RPC error body (no request id) with the given HTTP status."""
   400	    body = JSONRPCError(jsonrpc="2.0", id=None, error=ErrorData(code=code, message=message))
   401	    return Response(
   402	        body.model_dump_json(by_alias=True, exclude_unset=True), status_code=status_code, media_type="application/json"
   403	    )
   404	
   405	
   406	async def _send_and_report_status(app: ASGIApp, scope: Scope, receive: Receive, send: Send) -> int | None:
   407	    """Run `app` for one request and return the HTTP status it answered with (None if it sent no response)."""
   408	    status: int | None = None
   409	
   410	    async def watch_status(message: Message) -> None:
   411	        nonlocal status
   412	        if message["type"] == "http.response.start":
   413	            status = message["status"]
   414	        await send(message)
   415	
   416	    await app(scope, receive, watch_status)
   417	    return status
   418	
   419	
   420	class StreamableHTTPASGIApp:
     1	"""Single-exchange HTTP serving for protocol version 2026-07-28.
     2	
     3	Private module — entry is via `StreamableHTTPSessionManager.handle_request`.
     4	The legacy streamable-HTTP transport is untouched and remains the supported
     5	path for earlier protocol revisions.
     6	
     7	A 2026-07-28 request is a self-contained POST: no `initialize` handshake, no
     8	`Mcp-Session-Id`, one JSON-RPC request in, one JSON-RPC response out. A
     9	notification POST is acknowledged `202` and dropped: the core protocol defines
    10	no client-to-server notifications on this wire (cancellation is closing the
    11	response stream), and a per-request entry has nothing for one to act on. JSON
    12	mode handles the request directly in the ASGI task. SSE mode runs the handler
    13	as a sibling task and defers committing to `text/event-stream` until the
    14	handler emits a notification or `_SSE_PING_INTERVAL` elapses, whichever
    15	comes first: a handler that completes (or raises) within that window without
    16	emitting still gets a JSON response with the table-mapped HTTP status, so
    17	the spec's `404`/`400` MUSTs hold for kernel-dispatch errors; a handler that
    18	runs silent past the window commits SSE so the keepalive ping can keep the
    19	connection open behind a proxy idle-read timeout.
    20	"""
    21	
    22	from __future__ import annotations
    23	
    24	import json
    25	import logging
    26	from collections.abc import Awaitable, Mapping
    27	from dataclasses import dataclass, field
    28	from typing import TYPE_CHECKING, Any, Final, cast
    29	
    30	import anyio
    31	from anyio.streams.memory import MemoryObjectSendStream
    32	from mcp_types import (
    33	    CLIENT_CAPABILITIES_META_KEY,
    34	    CLIENT_INFO_META_KEY,
    35	    HEADER_MISMATCH,
    36	    INVALID_REQUEST,
    37	    PARSE_ERROR,
    38	    PROTOCOL_VERSION_META_KEY,
    39	    ErrorData,
    40	    JSONRPCError,
    41	    JSONRPCNotification,
    42	    JSONRPCRequest,
    43	    JSONRPCResponse,
    44	    ProgressToken,
    45	    RequestId,
    46	)
    47	from mcp_types import methods as _methods
    48	from pydantic import ValidationError
    49	from starlette.requests import Request
    50	from starlette.responses import Response
    51	from starlette.types import Receive, Scope, Send
    52	
    53	from mcp.server.connection import Connection
    54	from mcp.server.runner import modern_error_data, serve_one
    55	from mcp.server.streamable_http import check_accept_headers
    56	from mcp.server.transport_security import TransportSecurityMiddleware, TransportSecuritySettings
    57	from mcp.shared.dispatcher import CallOptions
    58	from mcp.shared.exceptions import NoBackChannelError
    59	from mcp.shared.inbound import (
    60	    ERROR_CODE_HTTP_STATUS,
    61	    MCP_PARAM_HEADER_PREFIX,
    62	    MCP_PROTOCOL_VERSION_HEADER,
    63	    InboundLadderRejection,
    64	    InboundModernRoute,
    65	    classify_inbound_request,
    66	    find_duplicated_routing_header,
    67	    unsupported_protocol_version_rejection,
    68	    validate_mcp_param_headers,
    69	)
    70	from mcp.shared.jsonrpc_dispatcher import progress_token_from_params
    71	from mcp.shared.message import MessageMetadata, ServerMessageMetadata
    72	from mcp.shared.transport_context import TransportContext
    73	
    74	if TYPE_CHECKING:
    75	    from mcp.server.lowlevel.server import Server
    76	
    77	logger = logging.getLogger(__name__)
    78	
    79	
    80	_OK_STATUS = 200
    81	
    82	
    83	@dataclass
    84	class _SingleExchangeDispatchContext:
    85	    """`DispatchContext` for one inbound HTTP request.
    86	
    87	    Structurally satisfies `mcp.shared.dispatcher.DispatchContext`. The
    88	    back-channel is closed by construction: a 2026-07-28 server cannot send
    89	    requests to the client. The SSE sink, when present, carries request-scoped
    90	    notifications onto this request's response stream.
    91	    """
    92	
    93	    transport: TransportContext
    94	    request_id: RequestId
    95	    message_metadata: MessageMetadata
    96	    progress_token: ProgressToken | None = None
    97	    sink: MemoryObjectSendStream[bytes] | None = None
    98	    cancel_requested: anyio.Event = field(default_factory=anyio.Event)
    99	    can_send_request: bool = field(default=False, init=False)
   100	
   101	    async def send_raw_request(
   102	        self,
   103	        method: str,
   104	        params: Mapping[str, Any] | None,
   105	        opts: CallOptions | None = None,
   106	    ) -> dict[str, Any]:
   107	        raise NoBackChannelError(method)
   108	
   109	    async def notify(self, method: str, params: Mapping[str, Any] | None, opts: CallOptions | None = None) -> None:
   110	        if self.sink is None:
   111	            return
   112	        body = dict(params) if params is not None else None
   113	        try:
   114	            await self.sink.send(_sse_event(JSONRPCNotification(jsonrpc="2.0", method=method, params=body)))
   115	        except (anyio.ClosedResourceError, anyio.BrokenResourceError):
   116	            logger.debug("dropped %s: response stream closed", method)
   117	
   118	    async def progress(self, progress: float, total: float | None = None, message: str | None = None) -> None:
   119	        if self.progress_token is None:
   120	            return
   121	        params: dict[str, Any] = {"progressToken": self.progress_token, "progress": progress}
   122	        if total is not None:
   123	            params["total"] = total
   124	        if message is not None:
   125	            params["message"] = message
   126	        await self.notify("notifications/progress", params)
   127	
   128	
   129	async def _to_jsonrpc_response(
   130	    request_id: RequestId, coro: Awaitable[dict[str, Any]]
   131	) -> JSONRPCResponse | JSONRPCError:
   132	    """Await ``coro`` and wrap its outcome as the JSON-RPC reply for ``request_id``.
   133	
   134	    The exception-to-wire boundary for the modern HTTP entry, composed around
   135	    `serve_one`: `modern_error_data` maps the shared ladder and surfaces
   136	    anything else as a generic `INTERNAL_ERROR` so handler internals never
   137	    reach the wire.
   138	    """
   139	    try:
   140	        result = await coro
   141	    except Exception as exc:
   142	        return JSONRPCError(jsonrpc="2.0", id=request_id, error=modern_error_data(exc))
   143	    return JSONRPCResponse(jsonrpc="2.0", id=request_id, result=result)
   144	
   145	
   146	_SSE_PING_INTERVAL: float = 15.0
   147	"""Seconds between SSE comment-line keepalives once `text/event-stream` has committed."""
   148	
   149	_SSE_HEADERS: Final[list[tuple[bytes, bytes]]] = [
   150	    (b"content-type", b"text/event-stream"),
   151	    (b"cache-control", b"no-cache, no-transform"),
   152	    (b"connection", b"keep-alive"),
   153	    (b"x-accel-buffering", b"no"),
   154	]
   155	
   156	
   157	def _sse_event(msg: JSONRPCResponse | JSONRPCError | JSONRPCNotification) -> bytes:
   158	    """Serialise a JSON-RPC message as one SSE `event: message` frame.
   159	
   160	    SSE mode begins after the handler has emitted, so a `JSONRPCError` here
   161	    always carries the request's id; the `id: null` case lives in `_write`.
   162	    """
   163	    body = msg.model_dump(mode="json", by_alias=True, exclude_none=True)
   164	    data = json.dumps(body, separators=(",", ":"))
   165	    return f"event: message\r\ndata: {data}\r\n\r\n".encode()
   166	
   167	
   168	async def _write_rejection(
   169	    rejection: InboundLadderRejection,
   170	    request_id: RequestId | None,
   171	    scope: Scope,
   172	    receive: Receive,
   173	    send: Send,
   174	) -> None:
   175	    """Send a ladder rejection as its JSON-RPC error with the table-mapped HTTP status."""
   176	    rej = JSONRPCError(
   177	        jsonrpc="2.0",
   178	        id=request_id,
   179	        error=ErrorData(code=rejection.code, message=rejection.message, data=rejection.data),
   180	    )
   181	    await _write(rej, scope, receive, send)
   182	
   183	
   184	async def _write(
   185	    msg: JSONRPCResponse | JSONRPCError,
   186	    scope: Scope,
   187	    receive: Receive,
   188	    send: Send,
   189	) -> None:
   190	    """Serialise a JSON-RPC reply with the table-mapped HTTP status."""
   191	    status = ERROR_CODE_HTTP_STATUS.get(msg.error.code, _OK_STATUS) if isinstance(msg, JSONRPCError) else _OK_STATUS
   192	    body = msg.model_dump(mode="json", by_alias=True, exclude_none=True)
   193	    if isinstance(msg, JSONRPCError) and msg.id is None:
   194	        # JSON-RPC requires `id: null` to appear on the wire when the request
   195	        # id couldn't be parsed; `exclude_none` would otherwise drop it.
   196	        body["id"] = None
   197	    await Response(
   198	        json.dumps(body, separators=(",", ":")),
   199	        status_code=status,
   200	        media_type="application/json",
   201	    )(scope, receive, send)
   202	
   203	
   204	_INVALID_BODY: Final = JSONRPCError(
   205	    jsonrpc="2.0",
   206	    id=None,
   207	    error=ErrorData(code=INVALID_REQUEST, message="Body must be a single JSON-RPC request or notification object"),
   208	)
   209	"""Well-formed JSON that is not one request or notification: a batch, a posted response, a malformed envelope."""
   210	
   211	
   212	def _is_notification_shaped(decoded: Any) -> bool:
   213	    """Whether a decoded POST body is a single JSON object without an `id` member.
   214	
   215	    JSON-RPC 2.0 §4.1: a notification is a request object without an "id"
   216	    member, so key presence — not which model happens to validate — picks the
   217	    arm. (The notification model ignores unknown keys; letting it catch a
   218	    request whose id is malformed would 202 a message that is owed an error.)
   219	    """
   220	    return isinstance(decoded, dict) and "id" not in decoded
   221	
   222	
   223	async def _acknowledge_notification(
   224	    decoded: dict[str, Any],
   225	    request: Request,
   226	    scope: Scope,
   227	    receive: Receive,
   228	    send: Send,
   229	) -> None:
   230	    """Answer an id-less POST body: `202` for a notification at a served version, a rejection otherwise.
   231	
   232	    Streamable-http §Sending Messages item 5 lets a server accept (202, no
   233	    body) or refuse (4xx) a notification POST; this entry accepts and drops.
   234	    The 2026-07-28 core protocol defines no client-to-server notifications over
   235	    HTTP (a client cancels by closing the response stream) and a per-request
   236	    entry holds no cross-request state for one to act on — honouring a posted
   237	    `notifications/cancelled` by client-chosen request id would let one
   238	    anonymous caller cancel another's work — but clients in the field still
   239	    POST them, and notifications are fire-and-forget, so they are acknowledged
   240	    as the handshake-era transport does rather than answered with an error
   241	    nobody reads. Header requirements for notification POSTs are undefined at
   242	    this revision; only the routing header that brought the POST here is
   243	    checked, so a version this entry does not serve is told so, as a request is.
   244	    """
   245	    try:
   246	        notification = JSONRPCNotification.model_validate(decoded)
   247	    except ValidationError:
   248	        await _write(_INVALID_BODY, scope, receive, send)
   249	        return
   250	    requested = request.headers.get(MCP_PROTOCOL_VERSION_HEADER, "")
   251	    if (unsupported := unsupported_protocol_version_rejection(requested)) is not None:
   252	        await _write_rejection(unsupported, None, scope, receive, send)
   253	        return
   254	    logger.debug("acknowledged and dropped client notification %s at %s", notification.method, requested)
   255	    await Response(status_code=202)(scope, receive, send)
   256	
   257	
   258	_MCP_PARAM_PREFIX_LOWER: Final = MCP_PARAM_HEADER_PREFIX.lower()
   259	
   260	_MCP_PARAM_LIST_PAGE_CAP: Final = 100
   261	"""Page cap for the schema-resolving tools/list walk: a buggy paginator degrades to a logged skip, not a hang."""
   262	
   263	
   264	async def _tool_input_schema(
   265	    app: Server[Any],
   266	    request: Request,
   267	    request_id: RequestId,
   268	    verdict: InboundModernRoute,
   269	    lifespan_state: Any,
   270	    name: str,
   271	) -> Any | None:
   272	    """Resolve `name`'s inputSchema from the server's own registered `tools/list` handler.
   273	
   274	    The listing runs through the normal `serve_one` path, so a visibility-scoped
   275	    catalog yields exactly what *this* caller was advertised. Returns None
   276	    (caller skips validation) when the listing fails or never advertises the tool.
   277	    """
   278	    meta = {
   279	        PROTOCOL_VERSION_META_KEY: verdict.protocol_version,
   280	        CLIENT_CAPABILITIES_META_KEY: verdict.client_capabilities,
   281	    }
   282	    if verdict.client_info is not None:
   283	        # Optional key: a conforming pair-only caller omits it rather than sending null.
   284	        meta[CLIENT_INFO_META_KEY] = verdict.client_info
   285	    list_params: dict[str, Any] = {"_meta": meta}
   286	    try:
   287	        _methods.validate_client_request("tools/list", verdict.protocol_version, list_params)
   288	    except ValidationError:
   289	        # Client-fault envelope: the real dispatch produces the INVALID_PARAMS
   290	        # reply, and anything above a debug line would let clients flood the log.
   291	        logger.debug("Mcp-Param header validation skipped: the request envelope fails tools/list validation")
   292	        return None
   293	    seen_cursors: set[str] = set()
   294	    dctx = _SingleExchangeDispatchContext(
   295	        transport=TransportContext(kind="streamable-http", can_send_request=False, headers=request.headers),
   296	        request_id=request_id,
   297	        message_metadata=ServerMessageMetadata(request_context=request),
   298	    )
   299	    for _ in range(_MCP_PARAM_LIST_PAGE_CAP):
   300	        # Fresh Connection per page: serve_one tears down the connection's exit stack on the way out.
   301	        connection = Connection.from_envelope(
   302	            verdict.protocol_version, verdict.client_info, verdict.client_capabilities
   303	        )
   304	        try:
   305	            result = await serve_one(
   306	                app, dctx, "tools/list", list_params, connection=connection, lifespan_state=lifespan_state
   307	            )
   308	            for tool in result.get("tools", []):
   309	                if tool.get("name") == name:
   310	                    return tool.get("inputSchema")
   311	            cursor = result.get("nextCursor")
   312	        except Exception:
   313	            # Fail-open boundary by design: header validation must never break a
   314	            # working call path. Loud, precisely because the skip is fail-open.
   315	            logger.exception("Mcp-Param header validation skipped: the tools/list listing failed")
   316	            return None
   317	        if not isinstance(cursor, str):
   318	            # Listing exhausted without advertising `name`; dispatch owns rejecting an unknown tool.
   319	            return None
   320	        if cursor in seen_cursors:
   321	            logger.warning("Mcp-Param header validation skipped: the tools/list handler returned a cursor cycle")
   322	            return None
   323	        seen_cursors.add(cursor)
   324	        list_params = {"_meta": meta, "cursor": cursor}
   325	    logger.warning(
   326	        "Mcp-Param header validation skipped: tools/list pagination did not terminate within %d pages",
   327	        _MCP_PARAM_LIST_PAGE_CAP,
   328	    )
   329	    return None
   330	
   331	
   332	async def _mcp_param_rejection(
   333	    app: Server[Any],
   334	    request: Request,
   335	    req: JSONRPCRequest,
   336	    verdict: InboundModernRoute,
   337	    lifespan_state: Any,
   338	) -> InboundLadderRejection | None:
   339	    """Validate a `tools/call` request's `Mcp-Param-*` headers against the called tool's schema.
   340	
   341	    Runs pre-dispatch, before any SSE machinery, so a rejection is always a
   342	    plain `application/json` 400 (the spec's MUST). The schema comes from the
   343	    server's `get_tool_input_schema` when set, else from its `tools/list` handler;
   344	    with neither there is no recognized header to validate.
   345	    """
   346	    lookup = app.get_tool_input_schema
   347	    if req.method != "tools/call" or (lookup is None and app.get_request_handler("tools/list") is None):
   348	        return None
   349	    params = req.params or {}
   350	    name = params.get("name")
   351	    if not isinstance(name, str):
   352	        return None
   353	    raw_arguments = params.get("arguments")
   354	    if raw_arguments is not None and not isinstance(raw_arguments, Mapping):
   355	        return None
   356	    arguments: Mapping[str, Any] = cast("Mapping[str, Any]", raw_arguments) if raw_arguments is not None else {}
   357	    # ASGI guarantees lowercase header names, so no case-folding here.
   358	    if not arguments and not any(header.startswith(_MCP_PARAM_PREFIX_LOWER) for header in request.headers):
   359	        # No argument values and no `Mcp-Param-*` headers: no declaration can be violated either way.
   360	        return None

exec
/bin/zsh -lc "nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http_manager.py | sed -n '206,315p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py | sed -n '560,720p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/shared/_context_streams.py | sed -n '1,160p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/transport_security.py | sed -n '1,260p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
   206	    async def _handle_stateless_request(
   207	        self, protocol_version_hint: str | None, scope: Scope, receive: Receive, send: Send
   208	    ) -> None:
   209	        """Process request in stateless mode - creating a new transport for each request."""
   210	        logger.debug("Stateless mode: Creating new transport for this request")
   211	        # No session ID needed in stateless mode
   212	        http_transport = StreamableHTTPServerTransport(
   213	            mcp_session_id=None,  # No session tracking in stateless mode
   214	            is_json_response_enabled=self.json_response,
   215	            event_store=None,  # No event store in stateless mode
   216	            security_settings=self.security_settings,
   217	        )
   218	
   219	        # Start server in a new task
   220	        async def run_stateless_server(*, task_status: TaskStatus[None] = anyio.TASK_STATUS_IGNORED):
   221	            async with http_transport.connect() as streams:
   222	                read_stream, write_stream = streams
   223	                task_status.started()
   224	                dispatcher: JSONRPCDispatcher[TransportContext] = JSONRPCDispatcher(
   225	                    read_stream,
   226	                    write_stream,
   227	                    inline_methods=frozenset({"initialize"}),
   228	                    # No session ID means a server-to-client request can be
   229	                    # written to this POST's response stream, but the client's
   230	                    # reply has nowhere to land — `can_send_request=False`
   231	                    # makes the per-request channel raise `NoBackChannelError`
   232	                    # for requests while still allowing notifications.
   233	                    transport_builder=lambda _md: TransportContext(kind="streamable-http", can_send_request=False),
   234	                )
   235	                # Born-ready, no standalone channel: the legacy stateless path
   236	                # never opens a GET stream and need not see `initialize`. The
   237	                # header (or the spec's default-absent value) seeds
   238	                # `ctx.protocol_version`.
   239	                connection = Connection.from_envelope(
   240	                    protocol_version_hint if protocol_version_hint is not None else DEFAULT_NEGOTIATED_VERSION,
   241	                    None,
   242	                    None,
   243	                )
   244	                try:
   245	                    await serve_connection(
   246	                        self.app, dispatcher, connection=connection, lifespan_state=self._lifespan_state
   247	                    )
   248	                except Exception:  # pragma: lax no cover
   249	                    logger.exception("Stateless session crashed")
   250	
   251	        # The per-request server task only ends once the transport is
   252	        # terminated, so terminate it even if the request was cancelled.
   253	        assert self._task_group is not None
   254	        try:
   255	            await self._task_group.start(run_stateless_server)
   256	            await http_transport.handle_request(scope, receive, send)
   257	        finally:
   258	            with anyio.CancelScope(shield=True):
   259	                await http_transport.terminate()
   260	
   261	    async def _handle_stateful_request(self, scope: Scope, receive: Receive, send: Send) -> None:
   262	        """Process request in stateful mode - maintaining session state between requests."""
   263	        request = Request(scope, receive)
   264	        request_mcp_session_id = request.headers.get(MCP_SESSION_ID_HEADER)
   265	
   266	        user = scope.get("user")
   267	        requestor = authorization_context(user) if isinstance(user, AuthenticatedUser) else None
   268	
   269	        # Existing session case
   270	        if request_mcp_session_id is not None and request_mcp_session_id in self._server_instances:
   271	            transport = self._server_instances[request_mcp_session_id]
   272	            if requestor != self._session_owners.get(request_mcp_session_id):
   273	                # A session can only be used with the credential that created
   274	                # it. Respond exactly as if the session did not exist.
   275	                logger.warning(
   276	                    "Rejecting request for session %s: credential does not match the one that created the session",
   277	                    request_mcp_session_id[:64],
   278	                )
   279	                await _error_response("Session not found", 404)(scope, receive, send)
   280	                return
   281	            logger.debug("Session already exists, handling request directly")
   282	            await transport.handle_request(scope, receive, send)
   283	            if transport.is_terminated:
   284	                # The client ended the session (DELETE): forget it now rather
   285	                # than when its server task winds down.
   286	                await self._discard_session(request_mcp_session_id, transport)
   287	            return
   288	
   289	        if request_mcp_session_id is None:
   290	            # New session case. Admission (the session limit and registration)
   291	            # is decided under the lock; the request itself is served outside
   292	            # it, so one client that is slow to send its opening request does
   293	            # not hold up the others.
   294	            async with self._session_creation_lock:
   295	                http_transport = self._admit_session(requestor)
   296	            if http_transport is None:
   297	                logger.warning("Refusing to open a new session: %d sessions are already open", self.max_sessions)
   298	                await _error_response("Too many open sessions", 503, INTERNAL_ERROR)(scope, receive, send)
   299	                return
   300	            await self._serve_opening_request(http_transport, scope, receive, send)
   301	        else:
   302	            # Unknown or expired session ID - return 404 per MCP spec
   303	            # TODO(L62): Align error code once spec clarifies
   304	            # See: https://github.com/modelcontextprotocol/python-sdk/issues/1821
   305	            logger.info(f"Rejected request with unknown or expired session ID: {request_mcp_session_id[:64]}")
   306	            await _error_response("Session not found", 404)(scope, receive, send)
   307	
   308	    def _admit_session(self, requestor: AuthorizationContext | None) -> StreamableHTTPServerTransport | None:
   309	        """Register a new session for `requestor` and return its transport, or None at the session limit."""
   310	        if self.max_sessions is not None and len(self._server_instances) >= self.max_sessions:
   311	            return None
   312	        http_transport = StreamableHTTPServerTransport(
   313	            mcp_session_id=uuid4().hex,
   314	            is_json_response_enabled=self.json_response,
   315	            event_store=self.event_store,  # May be None (no resumability)
   560	
   561	    _inner: DispatchContext[TransportContext]
   562	
   563	    @property
   564	    def transport(self) -> TransportContext:
   565	        # Mask the per-message flag so the transport metadata agrees with this
   566	        # wrapper's denial: the modern HTTP entry builds its context with
   567	        # can_send_request=False, while the loop's default builder says True.
   568	        transport = self._inner.transport
   569	        return replace(transport, can_send_request=False) if transport.can_send_request else transport
   570	
   571	    @property
   572	    def can_send_request(self) -> bool:
   573	        return False
   574	
   575	    @property
   576	    def request_id(self) -> RequestId | None:
   577	        return self._inner.request_id
   578	
   579	    @property
   580	    def message_metadata(self) -> MessageMetadata:
   581	        return self._inner.message_metadata
   582	
   583	    @property
   584	    def cancel_requested(self) -> anyio.Event:
   585	        return self._inner.cancel_requested
   586	
   587	    async def send_raw_request(
   588	        self,
   589	        method: str,
   590	        params: Mapping[str, Any] | None,
   591	        opts: CallOptions | None = None,
   592	    ) -> dict[str, Any]:
   593	        raise NoBackChannelError(method)
   594	
   595	    async def notify(self, method: str, params: Mapping[str, Any] | None, opts: CallOptions | None = None) -> None:
   596	        await self._inner.notify(method, params, opts)
   597	
   598	    async def progress(self, progress: float, total: float | None = None, message: str | None = None) -> None:
   599	        await self._inner.progress(progress, total, message)
   600	
   601	
   602	async def serve_dual_era_loop(
   603	    server: Server[LifespanT],
   604	    read_stream: ReadStream[SessionMessage | Exception],
   605	    write_stream: WriteStream[SessionMessage],
   606	    *,
   607	    lifespan_state: LifespanT,
   608	    session_id: str | None = None,
   609	    init_options: InitializationOptions | None = None,
   610	    raise_exceptions: bool = False,
   611	) -> None:
   612	    """Drive `server` over a duplex stream pair, in the era the client opens with.
   613	
   614	    The client's first request decides the connection's protocol era, once:
   615	    a request carrying the 2026-07-28 per-request `_meta` envelope opens a
   616	    modern connection, and anything else - the `initialize` handshake, which
   617	    does not exist at 2026 versions even when a client stamps the envelope on
   618	    it - opens a legacy one. The deciding frame is replayed into the chosen
   619	    serving loop along with everything the client sent before it. A later
   620	    claim from the other era is refused: `initialize` on a modern connection
   621	    gets UNSUPPORTED_PROTOCOL_VERSION naming the served versions, and an
   622	    enveloped request on a legacy connection gets INVALID_REQUEST.
   623	    """
   624	    # This loop owns both streams from the moment it is called, so the write
   625	    # stream is closed even if the client leaves before sending any request.
   626	    try:
   627	        async with _replay_from_opening_request(read_stream) as (opening, replayed):
   628	            opens_modern = (
   629	                opening is not None and opening.method != "initialize" and _has_modern_envelope(opening.params)
   630	            )
   631	            if opens_modern:
   632	                await _serve_modern_stream(
   633	                    server, replayed, write_stream, lifespan_state=lifespan_state, raise_exceptions=raise_exceptions
   634	                )
   635	            else:
   636	                await _serve_legacy_stream(
   637	                    server,
   638	                    replayed,
   639	                    write_stream,
   640	                    lifespan_state=lifespan_state,
   641	                    session_id=session_id,
   642	                    init_options=init_options,
   643	                    raise_exceptions=raise_exceptions,
   644	                )
   645	    finally:
   646	        await write_stream.aclose()
   647	
   648	
   649	_PRE_REQUEST_REPLAY_LIMIT: int = 8
   650	"""How many frames arriving ahead of the client's first request are kept
   651	for the chosen era's loop (a bare `notifications/initialized` is the one that
   652	matters); further ones are dropped and never decide the era."""
   653	
   654	
   655	def _sender_context(stream: ReadStream[Any]) -> contextvars.Context:
   656	    """The per-message sender context a context-aware stream carries, else the current one."""
   657	    ctx = getattr(stream, "last_context", None)
   658	    return ctx if ctx is not None else contextvars.copy_context()
   659	
   660	
   661	@asynccontextmanager
   662	async def _replay_from_opening_request(
   663	    read_stream: ReadStream[SessionMessage | Exception],
   664	) -> AsyncIterator[tuple[JSONRPCRequest | None, ReadStream[SessionMessage | Exception]]]:
   665	    """Peek at the client's first request without consuming it.
   666	
   667	    Yields that request together with a stream that replays it - preceded by
   668	    up to `_PRE_REQUEST_REPLAY_LIMIT` earlier frames - and relays the rest of
   669	    `read_stream` behind it, sender contexts included. The request is `None`
   670	    if the channel closes before one arrives.
   671	    """
   672	    lead: list[tuple[contextvars.Context, SessionMessage | Exception]] = []
   673	    opening_request: JSONRPCRequest | None = None
   674	    replay_send, replay_receive = anyio.create_memory_object_stream[
   675	        tuple[contextvars.Context, SessionMessage | Exception]
   676	    ]()
   677	    replayed = ContextReceiveStream(replay_receive)
   678	
   679	    async def replay_then_relay() -> None:
   680	        async with replay_send:
   681	            for envelope in lead:
   682	                await replay_send.send(envelope)
   683	            try:
   684	                async for item in read_stream:
   685	                    await replay_send.send((_sender_context(read_stream), item))
   686	            except anyio.ClosedResourceError:
   687	                # Receive end closed under us (stateless SHTTP teardown); same as EOF.
   688	                logger.debug("read stream closed by transport; treating as EOF")
   689	
   690	    # This helper takes ownership of `read_stream` from the serving loop, so
   691	    # every exit - including cancellation while awaiting the first request -
   692	    # closes it and the replay channel.
   693	    try:
   694	        try:
   695	            async for item in read_stream:
   696	                if isinstance(item, SessionMessage) and isinstance(item.message, JSONRPCRequest):
   697	                    opening_request = item.message
   698	                elif len(lead) >= _PRE_REQUEST_REPLAY_LIMIT:
   699	                    logger.debug("dropped a frame received before the first request: %r", item)
   700	                    continue
   701	                lead.append((_sender_context(read_stream), item))
   702	                if opening_request is not None:
   703	                    break
   704	        except anyio.ClosedResourceError:
   705	            # Receive end closed under us (stateless SHTTP teardown); same as EOF.
   706	            logger.debug("read stream closed by transport; treating as EOF")
   707	        async with anyio.create_task_group() as tg:
   708	            tg.start_soon(replay_then_relay)
   709	            yield opening_request, replayed
   710	            tg.cancel_scope.cancel()
   711	    finally:
   712	        await read_stream.aclose()
   713	        replay_send.close()
   714	        replay_receive.close()
   715	
   716	
   717	async def _serve_legacy_stream(
   718	    server: Server[LifespanT],
   719	    read_stream: ReadStream[SessionMessage | Exception],
   720	    write_stream: WriteStream[SessionMessage],
     1	"""Context-aware memory stream wrappers.
     2	
     3	anyio memory streams do not propagate ``contextvars.Context`` across task
     4	boundaries.  These thin wrappers capture the sender's context at ``send()``
     5	time and expose it on the receive side via ``last_context``, so consumers
     6	can restore it with ``ctx.run(handler, item)``.
     7	
     8	The iteration interface is unchanged (yields ``T``, not tuples), keeping
     9	these wrappers duck-type compatible with plain ``MemoryObjectSendStream``
    10	and ``MemoryObjectReceiveStream``.
    11	"""
    12	
    13	from __future__ import annotations
    14	
    15	import contextvars
    16	from types import TracebackType
    17	from typing import Any, Generic, TypeVar
    18	
    19	import anyio
    20	from anyio.streams.memory import MemoryObjectReceiveStream, MemoryObjectSendStream
    21	
    22	T = TypeVar("T")
    23	
    24	# Internal payload carried through the underlying raw stream.
    25	_Envelope = tuple[contextvars.Context, T]
    26	
    27	
    28	class ContextSendStream(Generic[T]):
    29	    """Send-side wrapper that snapshots ``contextvars.copy_context()`` on every ``send()``."""
    30	
    31	    __slots__ = ("_inner",)
    32	
    33	    def __init__(self, inner: MemoryObjectSendStream[_Envelope[T]]) -> None:
    34	        self._inner = inner
    35	
    36	    async def send(self, item: T) -> None:
    37	        await self._inner.send((contextvars.copy_context(), item))
    38	
    39	    def close(self) -> None:
    40	        self._inner.close()
    41	
    42	    async def aclose(self) -> None:
    43	        await self._inner.aclose()
    44	
    45	    def clone(self) -> ContextSendStream[T]:  # pragma: no cover
    46	        return ContextSendStream(self._inner.clone())
    47	
    48	    async def __aenter__(self) -> ContextSendStream[T]:
    49	        return self
    50	
    51	    async def __aexit__(
    52	        self,
    53	        exc_type: type[BaseException] | None,
    54	        exc_val: BaseException | None,
    55	        exc_tb: TracebackType | None,
    56	    ) -> bool | None:
    57	        await self.aclose()
    58	        return None
    59	
    60	
    61	class ContextReceiveStream(Generic[T]):
    62	    """Receive-side wrapper that yields ``T`` and stores the sender's context in ``last_context``."""
    63	
    64	    __slots__ = ("_inner", "last_context")
    65	
    66	    def __init__(self, inner: MemoryObjectReceiveStream[_Envelope[T]]) -> None:
    67	        self._inner = inner
    68	        self.last_context: contextvars.Context | None = None
    69	
    70	    async def receive(self) -> T:
    71	        ctx, item = await self._inner.receive()
    72	        self.last_context = ctx
    73	        return item
    74	
    75	    def close(self) -> None:
    76	        self._inner.close()
    77	
    78	    async def aclose(self) -> None:
    79	        await self._inner.aclose()
    80	
    81	    def clone(self) -> ContextReceiveStream[T]:  # pragma: no cover
    82	        return ContextReceiveStream(self._inner.clone())
    83	
    84	    def __aiter__(self) -> ContextReceiveStream[T]:
    85	        return self
    86	
    87	    async def __anext__(self) -> T:
    88	        try:
    89	            return await self.receive()
    90	        except anyio.EndOfStream:
    91	            raise StopAsyncIteration
    92	
    93	    async def __aenter__(self) -> ContextReceiveStream[T]:
    94	        return self
    95	
    96	    async def __aexit__(
    97	        self,
    98	        exc_type: type[BaseException] | None,
    99	        exc_val: BaseException | None,
   100	        exc_tb: TracebackType | None,
   101	    ) -> bool | None:
   102	        await self.aclose()
   103	        return None
   104	
   105	
   106	class create_context_streams(
   107	    tuple[ContextSendStream[T], ContextReceiveStream[T]],
   108	):
   109	    """Create context-aware memory object streams.
   110	
   111	    Supports ``create_context_streams[T](n)`` bracket syntax,
   112	    matching anyio's ``create_memory_object_stream`` API style.
   113	    """
   114	
   115	    def __new__(cls, max_buffer_size: float = 0) -> tuple[ContextSendStream[T], ContextReceiveStream[T]]:  # type: ignore[type-var]
   116	        raw_send: MemoryObjectSendStream[Any]
   117	        raw_receive: MemoryObjectReceiveStream[Any]
   118	        raw_send, raw_receive = anyio.create_memory_object_stream(max_buffer_size)
   119	        return (ContextSendStream(raw_send), ContextReceiveStream(raw_receive))
     1	"""Request checks shared by the HTTP server transports: Host/Origin header validation and body size limits."""
     2	
     3	import logging
     4	from collections import deque
     5	from typing import Final
     6	
     7	from pydantic import BaseModel, Field
     8	from starlette.datastructures import Headers
     9	from starlette.requests import Request
    10	from starlette.responses import Response
    11	from starlette.types import ASGIApp, Message, Receive, Scope, Send
    12	
    13	logger = logging.getLogger(__name__)
    14	
    15	DEFAULT_MAX_REQUEST_BODY_SIZE: Final = 4 * 1024 * 1024
    16	"""Default maximum HTTP request body size in bytes (4 MiB)."""
    17	
    18	
    19	# TODO(Marcelo): We should flatten these settings. To be fair, I don't think we should even have this middleware.
    20	class TransportSecuritySettings(BaseModel):
    21	    """Settings for MCP transport security features.
    22	
    23	    These settings help protect against DNS rebinding attacks by validating incoming request headers.
    24	    """
    25	
    26	    enable_dns_rebinding_protection: bool = True
    27	    """Enable DNS rebinding protection (recommended for production)."""
    28	
    29	    allowed_hosts: list[str] = Field(default_factory=list)
    30	    """List of allowed Host header values.
    31	
    32	    Only applies when `enable_dns_rebinding_protection` is `True`.
    33	    """
    34	
    35	    allowed_origins: list[str] = Field(default_factory=list)
    36	    """List of allowed Origin header values.
    37	
    38	    Only applies when `enable_dns_rebinding_protection` is `True`.
    39	    """
    40	
    41	
    42	# TODO(Marcelo): This should be a proper ASGI middleware. I'm sad to see this.
    43	class TransportSecurityMiddleware:
    44	    """Middleware to enforce DNS rebinding protection for MCP transport endpoints."""
    45	
    46	    def __init__(self, settings: TransportSecuritySettings | None = None):
    47	        # If not specified, disable DNS rebinding protection by default for backwards compatibility
    48	        self.settings = settings or TransportSecuritySettings(enable_dns_rebinding_protection=False)
    49	
    50	    def _validate_host(self, host: str | None) -> bool:
    51	        """Validate the Host header against allowed values."""
    52	        if not host:
    53	            logger.warning("Missing Host header in request")
    54	            return False
    55	
    56	        # Check exact match first
    57	        if host in self.settings.allowed_hosts:
    58	            return True
    59	
    60	        # Check wildcard port patterns
    61	        for allowed in self.settings.allowed_hosts:
    62	            if allowed.endswith(":*"):
    63	                # Extract base host from pattern
    64	                base_host = allowed[:-2]
    65	                # Check if the actual host starts with base host and has a port
    66	                if host.startswith(base_host + ":"):
    67	                    return True
    68	
    69	        logger.warning(f"Invalid Host header: {host}")
    70	        return False
    71	
    72	    def _validate_origin(self, origin: str | None) -> bool:
    73	        """Validate the Origin header against allowed values."""
    74	        # Origin can be absent for same-origin requests
    75	        if not origin:
    76	            return True
    77	
    78	        # Check exact match first
    79	        if origin in self.settings.allowed_origins:
    80	            return True
    81	
    82	        # Check wildcard port patterns
    83	        for allowed in self.settings.allowed_origins:
    84	            if allowed.endswith(":*"):
    85	                # Extract base origin from pattern
    86	                base_origin = allowed[:-2]
    87	                # Check if the actual origin starts with base origin and has a port
    88	                if origin.startswith(base_origin + ":"):
    89	                    return True
    90	
    91	        logger.warning(f"Invalid Origin header: {origin}")
    92	        return False
    93	
    94	    def _validate_content_type(self, content_type: str | None) -> bool:
    95	        """Validate the Content-Type header for POST requests."""
    96	        return content_type is not None and content_type.lower().startswith("application/json")
    97	
    98	    async def validate_request(self, request: Request, is_post: bool = False) -> Response | None:
    99	        """Validate request headers for DNS rebinding protection.
   100	
   101	        Returns None if validation passes, or an error Response if validation fails.
   102	        """
   103	        # Always validate Content-Type for POST requests
   104	        if is_post:
   105	            content_type = request.headers.get("content-type")
   106	            if not self._validate_content_type(content_type):
   107	                return Response("Invalid Content-Type header", status_code=400)
   108	
   109	        # Skip remaining validation if DNS rebinding protection is disabled
   110	        if not self.settings.enable_dns_rebinding_protection:
   111	            return None
   112	
   113	        # Validate Host header
   114	        host = request.headers.get("host")
   115	        if not self._validate_host(host):
   116	            return Response("Invalid Host header", status_code=421)
   117	
   118	        # Validate Origin header
   119	        origin = request.headers.get("origin")
   120	        if not self._validate_origin(origin):
   121	            return Response("Invalid Origin header", status_code=403)
   122	
   123	        return None
   124	
   125	
   126	class RequestBodyLimitMiddleware:
   127	    """Reject oversized HTTP request bodies before invoking an ASGI application."""
   128	
   129	    def __init__(self, app: ASGIApp, max_body_size: int) -> None:
   130	        self.app = app
   131	        self.max_body_size = max_body_size
   132	
   133	    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
   134	        if scope["type"] != "http":
   135	            await self.app(scope, receive, send)
   136	            return
   137	
   138	        headers = Headers(scope=scope)
   139	        content_length = headers.get("content-length")
   140	        if content_length is not None:
   141	            try:
   142	                declared_size = int(content_length)
   143	            except ValueError:
   144	                pass
   145	            else:
   146	                if declared_size > self.max_body_size:
   147	                    response = Response("Request body too large", status_code=413)
   148	                    return await response(scope, receive, send)
   149	
   150	        received_body = bytearray()
   151	        received_request = False
   152	        body_complete = False
   153	        trailing_message: Message | None = None
   154	        while True:
   155	            message = await receive()
   156	            if message["type"] != "http.request":
   157	                trailing_message = message
   158	                break
   159	
   160	            received_request = True
   161	            body = message.get("body", b"")
   162	            if len(received_body) + len(body) > self.max_body_size:
   163	                response = Response("Request body too large", status_code=413)
   164	                return await response(scope, receive, send)
   165	            received_body.extend(body)
   166	            if not message.get("more_body", False):
   167	                body_complete = True
   168	                break
   169	
   170	        cached_messages: deque[Message] = deque()
   171	        if received_request:
   172	            cached_messages.append(
   173	                {"type": "http.request", "body": bytes(received_body), "more_body": not body_complete}
   174	            )
   175	        if trailing_message is not None:
   176	            cached_messages.append(trailing_message)
   177	
   178	        async def replay() -> Message:
   179	            if cached_messages:
   180	                return cached_messages.popleft()
   181	            return await receive()
   182	
   183	        await self.app(scope, replay, send)

exec
/bin/zsh -lc "git status --short; git rev-parse HEAD; git log --oneline -5; git diff 12f9085 -- backend/app/mcp_server.py backend/app/main.py backend/tests/test_mcp.py; rg -uu -n \"create_context_streams|last_context|\\.run\\(\" backend/.venv/lib/python3.14/site-packages/mcp/server/{streamable_http.py,runner.py,session.py,lowlevel/server.py} | sed -n '1,300p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
 M backend/README.md
 M deploy/deploy.sh
 M deploy/nginx/smart-coding-study.conf
12f908515f67dd7fcbe18105c256f073e0274448
12f9085 feat(mcp): /mcp Streamable HTTP + 12 tool, JWKS outage → 503 (T-04, T-01 r2)
1b9aaf4 feat(mcp): cấp/thu hồi quyền MCP qua API admin + CLI (T-03)
ddb2bc0 feat(mcp): verify JWT identity-service + mcp_access + content_ops (T-01, T-02)
6c6e6dd docs: distill python-oop-bank run
48d8fb5 docs(crew): run python-oop-bank — done, VPS loaded
backend/.venv/lib/python3.14/site-packages/mcp/server/lowlevel/server.py:25:           await server.run(
backend/.venv/lib/python3.14/site-packages/mcp/server/lowlevel/server.py:31:   asyncio.run(main())
backend/.venv/lib/python3.14/site-packages/mcp/server/lowlevel/server.py:851:            lifespan=lambda app: session_manager.run(),
backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py:459:    to `dispatcher.run()`, and tears down `connection.exit_stack` (shielded)
backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py:465:        await dispatcher.run(runner.on_request, runner.on_notify, task_status=task_status)
backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py:657:    ctx = getattr(stream, "last_context", None)
backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py:750:        await dispatcher.run(on_request, runner.on_notify)
backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py:812:    await dispatcher.run(on_request, on_notify)
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http.py:45:from mcp.shared._context_streams import ContextReceiveStream, ContextSendStream, create_context_streams
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http.py:1044:        read_stream_writer, read_stream = create_context_streams[SessionMessage | Exception](0)
backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http.py:1045:        write_stream, write_stream_reader = create_context_streams[SessionMessage](0)

exec
/bin/zsh -lc "nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py | sed -n '430,500p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/runner.py | sed -n '717,830p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http.py | sed -n '1020,1075p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/shared/dispatcher.py | sed -n '150,320p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
   430	        _, negotiated = self._negotiate_initialize(params)
   431	        opts = self.init_options if self.init_options is not None else self.server.create_initialization_options()
   432	        return InitializeResult(
   433	            protocol_version=negotiated,
   434	            capabilities=opts.capabilities,
   435	            server_info=Implementation(
   436	                name=opts.server_name,
   437	                title=opts.title,
   438	                description=opts.description,
   439	                version=opts.server_version,
   440	                website_url=opts.website_url,
   441	                icons=opts.icons,
   442	            ),
   443	            instructions=opts.instructions,
   444	        )
   445	
   446	
   447	async def serve_connection(
   448	    server: Server[LifespanT],
   449	    dispatcher: Dispatcher[Any],
   450	    *,
   451	    connection: Connection,
   452	    lifespan_state: LifespanT,
   453	    init_options: InitializationOptions | None = None,
   454	    task_status: anyio.abc.TaskStatus[None] = anyio.TASK_STATUS_IGNORED,
   455	) -> None:
   456	    """Drive ``dispatcher`` until the underlying channel closes.
   457	
   458	    The loop-mode driver: builds the kernel, hands `on_request`/`on_notify`
   459	    to `dispatcher.run()`, and tears down `connection.exit_stack` (shielded)
   460	    on the way out. The entry constructs the `Connection`; this only consumes
   461	    it.
   462	    """
   463	    runner = ServerRunner(server, connection, lifespan_state, init_options=init_options)
   464	    try:
   465	        await dispatcher.run(runner.on_request, runner.on_notify, task_status=task_status)
   466	    finally:
   467	        await aclose_shielded(connection)
   468	
   469	
   470	async def serve_loop(
   471	    server: Server[LifespanT],
   472	    read_stream: ReadStream[SessionMessage | Exception],
   473	    write_stream: WriteStream[SessionMessage],
   474	    *,
   475	    lifespan_state: LifespanT,
   476	    session_id: str | None = None,
   477	    init_options: InitializationOptions | None = None,
   478	    raise_exceptions: bool = False,
   479	) -> None:
   480	    """Drive ``server`` in handshake-only loop mode over a stream pair until the channel closes.
   481	
   482	    Builds the loop-mode `JSONRPCDispatcher` + `Connection` and hands them to
   483	    `serve_connection`. The streamable-HTTP manager (which owns its lifespan
   484	    and serves the modern era on the single-exchange entry instead) calls
   485	    this; `Server.run` drives `serve_dual_era_loop`, which extends the same
   486	    dispatcher recipe (notably the `inline_methods={"initialize"}` rule) with
   487	    era routing.
   488	    """
   489	    dispatcher: JSONRPCDispatcher[TransportContext] = JSONRPCDispatcher(
   490	        read_stream,
   491	        write_stream,
   492	        raise_handler_exceptions=raise_exceptions,
   493	        # Handle `initialize` inline so a client that pipelines it with the
   494	        # next request (spec: SHOULD NOT, not MUST NOT) sees the initialized
   495	        # state instead of failing the init-gate.
   496	        inline_methods=frozenset({"initialize"}),
   497	    )
   498	    connection = Connection.for_loop(dispatcher, session_id=session_id)
   499	    await serve_connection(
   500	        server, dispatcher, connection=connection, lifespan_state=lifespan_state, init_options=init_options
   717	async def _serve_legacy_stream(
   718	    server: Server[LifespanT],
   719	    read_stream: ReadStream[SessionMessage | Exception],
   720	    write_stream: WriteStream[SessionMessage],
   721	    *,
   722	    lifespan_state: LifespanT,
   723	    session_id: str | None,
   724	    init_options: InitializationOptions | None,
   725	    raise_exceptions: bool,
   726	) -> None:
   727	    """Serve a 2025 handshake connection; enveloped requests are refused."""
   728	    dispatcher: JSONRPCDispatcher[TransportContext] = JSONRPCDispatcher(
   729	        read_stream,
   730	        write_stream,
   731	        raise_handler_exceptions=raise_exceptions,
   732	        # `initialize` inline for the same pipelining reason as `serve_loop`.
   733	        inline_methods=frozenset({"initialize"}),
   734	    )
   735	    connection = Connection.for_loop(dispatcher, session_id=session_id)
   736	    runner = ServerRunner(server, connection, lifespan_state, init_options=init_options)
   737	
   738	    async def on_request(
   739	        dctx: DispatchContext[TransportContext], method: str, params: Mapping[str, Any] | None
   740	    ) -> dict[str, Any]:
   741	        if method != "initialize" and _has_modern_envelope(params):
   742	            raise MCPError(
   743	                code=INVALID_REQUEST,
   744	                message="this connection serves the handshake protocol era; "
   745	                "requests carrying the 2026-07-28 envelope are not accepted on it",
   746	            )
   747	        return await runner.on_request(dctx, method, params)
   748	
   749	    try:
   750	        await dispatcher.run(on_request, runner.on_notify)
   751	    finally:
   752	        await aclose_shielded(connection)
   753	
   754	
   755	async def _serve_modern_stream(
   756	    server: Server[LifespanT],
   757	    read_stream: ReadStream[SessionMessage | Exception],
   758	    write_stream: WriteStream[SessionMessage],
   759	    *,
   760	    lifespan_state: LifespanT,
   761	    raise_exceptions: bool,
   762	) -> None:
   763	    """Serve a 2026-07-28 connection: every request carries its own envelope."""
   764	    dispatcher: JSONRPCDispatcher[TransportContext] = JSONRPCDispatcher(
   765	        read_stream, write_stream, raise_handler_exceptions=raise_exceptions
   766	    )
   767	    outbound = NotifyOnlyOutbound(dispatcher)
   768	
   769	    async def on_request(
   770	        dctx: DispatchContext[TransportContext], method: str, params: Mapping[str, Any] | None
   771	    ) -> dict[str, Any]:
   772	        if method == "initialize":
   773	            raise MCPError(
   774	                code=UNSUPPORTED_PROTOCOL_VERSION,
   775	                message="connection is serving the 2026-07-28 protocol; the initialize handshake is not accepted",
   776	                data=_initialize_after_modern_data(params),
   777	            )
   778	        route = classify_inbound_request({"method": method, "params": params})
   779	        if isinstance(route, InboundLadderRejection):
   780	            raise MCPError(code=route.code, message=route.message, data=route.data)
   781	        connection = Connection.from_envelope(
   782	            route.protocol_version, route.client_info, route.client_capabilities, outbound=outbound
   783	        )
   784	        try:
   785	            return await serve_one(
   786	                server,
   787	                _NoServerRequestsDispatchContext(dctx),
   788	                method,
   789	                params,
   790	                connection=connection,
   791	                lifespan_state=lifespan_state,
   792	            )
   793	        except (MCPError, ValidationError):
   794	            # The dispatcher's shared ladder maps these to the wire error.
   795	            raise
   796	        except Exception as exc:
   797	            if raise_exceptions:
   798	                raise
   799	            error = modern_error_data(exc)
   800	            raise MCPError(code=error.code, message=error.message, data=error.data) from exc
   801	
   802	    async def on_notify(dctx: DispatchContext[TransportContext], method: str, params: Mapping[str, Any] | None) -> None:
   803	        # The envelope is request-only, so a notification runs at the latest
   804	        # served version; the modern protocol has nothing version-specific here.
   805	        connection = Connection.from_envelope(LATEST_MODERN_VERSION, None, None, outbound=outbound)
   806	        notify_runner = ServerRunner(server, connection, lifespan_state)
   807	        try:
   808	            await notify_runner.on_notify(_NoServerRequestsDispatchContext(dctx), method, params)
   809	        finally:
   810	            await aclose_shielded(connection)
   811	
   812	    await dispatcher.run(on_request, on_notify)
   813	
   814	
   815	async def serve_one(
   816	    server: Server[LifespanT],
   817	    dctx: DispatchContext[TransportContext],
   818	    method: str,
   819	    params: Mapping[str, Any] | None,
   820	    *,
   821	    connection: Connection,
   822	    lifespan_state: LifespanT,
   823	) -> dict[str, Any]:
   824	    """Handle a single request ``(method, params)`` and return its result dict.
   825	
   826	    The single-exchange driver: builds the kernel, runs `on_request` once under
   827	    `dctx`, and tears down `connection.exit_stack` (shielded) on the way out.
   828	    The entry constructs the (born-ready) `Connection` and the `dctx`; this
   829	    only consumes them.
   830	
  1020	                INTERNAL_ERROR,
  1021	            )
  1022	            await response(request.scope, request.receive, send)
  1023	
  1024	    @asynccontextmanager
  1025	    async def connect(
  1026	        self,
  1027	    ) -> AsyncGenerator[
  1028	        tuple[
  1029	            ReadStream[SessionMessage | Exception],
  1030	            WriteStream[SessionMessage],
  1031	        ],
  1032	        None,
  1033	    ]:
  1034	        """Context manager that provides read and write streams for a connection.
  1035	
  1036	        Yields:
  1037	            Tuple of (read_stream, write_stream) for bidirectional communication
  1038	        """
  1039	        if self._idle_timeout is not None:
  1040	            self.idle_scope = anyio.CancelScope()
  1041	
  1042	        # Create the memory streams for this connection
  1043	
  1044	        read_stream_writer, read_stream = create_context_streams[SessionMessage | Exception](0)
  1045	        write_stream, write_stream_reader = create_context_streams[SessionMessage](0)
  1046	
  1047	        # Store the streams
  1048	        self._read_stream_writer = read_stream_writer
  1049	        self._read_stream = read_stream
  1050	        self._write_stream_reader = write_stream_reader
  1051	        self._write_stream = write_stream
  1052	
  1053	        # Start a task group for message routing
  1054	        async with anyio.create_task_group() as tg:
  1055	            # Create a message router that distributes messages to request streams
  1056	            async def message_router():
  1057	                try:
  1058	                    async for session_message in write_stream_reader:  # pragma: no branch
  1059	                        # Determine which request stream(s) should receive this message
  1060	                        message = session_message.message
  1061	                        target_request_id = None
  1062	                        # Check if this is a response with a known request id.
  1063	                        # Null-id errors (e.g., parse errors) fall through to
  1064	                        # the GET stream since they can't be correlated.
  1065	                        if isinstance(message, JSONRPCResponse | JSONRPCError) and message.id is not None:
  1066	                            target_request_id = str(message.id)
  1067	                        # Extract related_request_id from meta if it exists
  1068	                        elif (
  1069	                            session_message.metadata is not None
  1070	                            and isinstance(
  1071	                                session_message.metadata,
  1072	                                ServerMessageMetadata,
  1073	                            )
  1074	                            and session_message.metadata.related_request_id is not None
  1075	                        ):
   150	        params: Mapping[str, Any] | None,
   151	        opts: CallOptions | None = None,
   152	    ) -> dict[str, Any]:
   153	        """Send a request and await its raw result dict.
   154	
   155	        Raises:
   156	            MCPError: If the peer responded with an error, or the handler
   157	                raised. Implementations normalize all handler exceptions to
   158	                `MCPError` so callers see a single exception type.
   159	        """
   160	        ...
   161	
   162	    async def notify(self, method: str, params: Mapping[str, Any] | None, opts: CallOptions | None = None) -> None:
   163	        """Send a fire-and-forget notification."""
   164	        ...
   165	
   166	
   167	class DispatchContext(Outbound, Protocol[TransportT_co]):
   168	    """Per-request context handed to `on_request` / `on_notify`.
   169	
   170	    Carries the transport metadata for the inbound message and provides the
   171	    back-channel for sending requests/notifications to the peer while handling
   172	    it. `send_raw_request` raises `NoBackChannelError` if `can_send_request`
   173	    is `False`.
   174	    """
   175	
   176	    @property
   177	    def transport(self) -> TransportT_co:
   178	        """Transport-specific metadata for this inbound message."""
   179	        ...
   180	
   181	    @property
   182	    def can_send_request(self) -> bool:
   183	        """Whether the back-channel can currently deliver server-initiated requests.
   184	
   185	        `False` when the transport has no back-channel, or when this context has
   186	        been closed (the inbound request finished). `send_raw_request` raises
   187	        `NoBackChannelError` exactly when this is `False`.
   188	        """
   189	        ...
   190	
   191	    @property
   192	    def request_id(self) -> RequestId | None:
   193	        """The id of the inbound request, or `None` for a notification.
   194	
   195	        For JSON-RPC this is the wire `id` field. Handlers thread it through
   196	        as `related_request_id` on outbound notifications so HTTP transports
   197	        can route them onto the originating request's response stream.
   198	        """
   199	        ...
   200	
   201	    @property
   202	    def message_metadata(self) -> MessageMetadata:
   203	        """The metadata the transport attached to this inbound message, if any.
   204	
   205	        This is `SessionMessage.metadata` passed through verbatim: HTTP
   206	        transports attach `ServerMessageMetadata` (the HTTP request, SSE
   207	        stream-close callbacks); stdio and in-memory dispatch attach nothing.
   208	        Tied to the `SessionMessage` wire format - goes away when transports
   209	        stop delivering messages that way.
   210	        """
   211	        # TODO(maxisbey): remove for context rework
   212	        ...
   213	
   214	    @property
   215	    def cancel_requested(self) -> anyio.Event:
   216	        """Set when the peer sends `notifications/cancelled` for this request."""
   217	        ...
   218	
   219	    async def progress(self, progress: float, total: float | None = None, message: str | None = None) -> None:
   220	        """Report progress for the inbound request, if the peer supplied a progress token.
   221	
   222	        A no-op when no token was supplied.
   223	        """
   224	        ...
   225	
   226	
   227	OnRequest = Callable[[DispatchContext[TransportContext], str, Mapping[str, Any] | None], Awaitable[dict[str, Any]]]
   228	"""Handler for inbound requests: `(ctx, method, params) -> result`. Raise `MCPError` to send an error response."""
   229	
   230	OnNotify = Callable[[DispatchContext[TransportContext], str, Mapping[str, Any] | None], Awaitable[None]]
   231	"""Handler for inbound notifications: `(ctx, method, params)`."""
   232	
   233	OnNotifyIntercept = Callable[[str, Mapping[str, Any] | None], bool]
   234	"""Synchronous receive-order intercept for inbound notifications: `(method, params) -> consumed`.
   235	
   236	Runs before `on_notify` is scheduled so correlation state advances in wire order
   237	relative to response resolution (the client's listen demux depends on this).
   238	Returning True consumes the notification. Must not block the receive path.
   239	"""
   240	
   241	
   242	def run_notify_intercept(intercept: OnNotifyIntercept | None, method: str, params: Mapping[str, Any] | None) -> bool:
   243	    """Invoke `intercept`, containing a raise to that one notification (never the receive loop)."""
   244	    if intercept is None:
   245	        return False
   246	    try:
   247	        return intercept(method, params)
   248	    except Exception:
   249	        logger.exception("notification intercept raised; passing %r through", method)
   250	        return False
   251	
   252	
   253	class Dispatcher(Outbound, Protocol[TransportT_co]):
   254	    """A duplex request/notification channel with call-return semantics.
   255	
   256	    Implementations own correlation of outbound requests to inbound results, the
   257	    receive loop, per-request concurrency, and cancellation/progress wiring.
   258	
   259	    The lifecycle surface is provisional; `run()` may change in a 2.x minor
   260	    release.
   261	    """
   262	
   263	    async def run(
   264	        self,
   265	        on_request: OnRequest,
   266	        on_notify: OnNotify,
   267	        on_notify_intercept: OnNotifyIntercept | None = None,
   268	        *,
   269	        task_status: anyio.abc.TaskStatus[None] = anyio.TASK_STATUS_IGNORED,
   270	    ) -> None:
   271	        """Drive the receive loop until the underlying channel closes.
   272	
   273	        Each inbound request is dispatched to `on_request` in its own task;
   274	        the returned dict (or raised `MCPError`) is sent back as the response.
   275	        Implementations MUST offer every inbound notification to
   276	        `on_notify_intercept` synchronously in receive order (via
   277	        `run_notify_intercept`), handing only unconsumed ones to `on_notify`.
   278	
   279	        `task_status.started()` is called once the dispatcher is ready to
   280	        accept `send_request`/`notify` calls, so callers can use
   281	        `await tg.start(dispatcher.run, on_request, on_notify)`.
   282	        """
   283	        ...

exec
/bin/zsh -lc "rg -uu -n \"last_context|context.*run|start_soon|on_request\" backend/.venv/lib/python3.14/site-packages/mcp/shared/{jsonrpc_dispatcher.py,direct_dispatcher.py} | sed -n '1,260p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py | sed -n '280,560p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:4:request on one side directly invokes the other side's `on_request`. There is no
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:104:    `on_request`. `run` parks until `close` is called.
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:118:        self._on_request: OnRequest | None = None
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:137:        """Send a request by invoking the peer's `on_request` directly.
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:171:        on_request: OnRequest,
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:183:            self._on_request = on_request
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:228:                tg.start_soon(wake_on, self._ready)
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:229:                tg.start_soon(wake_on, self._close_event)
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:245:                assert self._on_request is not None
backend/.venv/lib/python3.14/site-packages/mcp/shared/direct_dispatcher.py:269:                    return await self._on_request(dctx, method, params)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:495:        on_request: OnRequest,
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:521:                                        self._read_stream, "last_context", None
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:523:                                    await self._dispatch(item, on_request, on_notify, sender_ctx)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:546:        on_request: OnRequest,
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:568:                await self._dispatch_request(msg, metadata, on_request, sender_ctx)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:581:        on_request: OnRequest,
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:616:                    await self._handle_request(req, dctx, scope, on_request)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:623:            self._spawn(self._handle_request, req, dctx, scope, on_request, sender_ctx=sender_ctx)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:705:            sender_ctx.run(self._tg.start_soon, run)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:707:            self._tg.start_soon(run)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:726:        on_request: OnRequest,
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:728:        """Run `on_request` for one inbound request and write its response.
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:740:                    result = await on_request(dctx, req.method, req.params)
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:813:        """Run the transport's `on_request_unanswered` hook: this request settled with no response.
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:820:        if not isinstance(metadata, ServerMessageMetadata) or metadata.on_request_unanswered is None:
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:823:            await metadata.on_request_unanswered()
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:825:            logger.debug("on_request_unanswered dropped: connection closing")
backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py:827:            logger.exception("on_request_unanswered hook raised")
   280	    ) -> None:
   281	        """Wire a dispatcher over a transport's `SessionMessage` stream pair.
   282	
   283	        Args:
   284	            transport_builder: Builds each message's `TransportContext` from
   285	                its `SessionMessage.metadata`.
   286	            raise_handler_exceptions: Re-raise handler exceptions out of
   287	                `run()` after the error response is written.
   288	            inline_methods: Methods awaited in the read loop before the next
   289	                message is dequeued (e.g. `initialize`); an inline handler
   290	                that awaits the peer deadlocks the parked loop.
   291	            on_stream_exception: Observer for `Exception` items on the read
   292	                stream; without it they are debug-logged and dropped. Awaited
   293	                inline in the read loop, so a slow observer stalls dispatch.
   294	        """
   295	        self._read_stream = read_stream
   296	        self._write_stream = write_stream
   297	        # With transport_builder omitted, TransportT defaults to
   298	        # TransportContext; pyright can't connect the two, hence the cast.
   299	        self._transport_builder = cast(
   300	            "Callable[[MessageMetadata], TransportT]",
   301	            transport_builder or _default_transport_builder,
   302	        )
   303	        self._peer_cancel_mode: PeerCancelMode = peer_cancel_mode
   304	        self._raise_handler_exceptions = raise_handler_exceptions
   305	        self._inline_methods = inline_methods
   306	        self.on_stream_exception = on_stream_exception
   307	        """Observer for ``Exception`` items on the read stream. Mutable so a session can
   308	        bind it after the dispatcher is built (e.g. ``ClientSession`` routing into
   309	        ``message_handler``); only consulted inside ``run()`` so pre-enter assignment is safe."""
   310	
   311	        self._next_id = 0
   312	        self._pending: dict[RequestId, _Pending] = {}
   313	        self._in_flight: dict[RequestId, _InFlight[TransportT]] = {}
   314	        self._on_notify_intercept: OnNotifyIntercept | None = None
   315	        self._tg: anyio.abc.TaskGroup | None = None
   316	        self._running = False
   317	        self._closed = False
   318	
   319	    async def send_raw_request(
   320	        self,
   321	        method: str,
   322	        params: Mapping[str, Any] | None,
   323	        opts: CallOptions | None = None,
   324	        *,
   325	        _related_request_id: RequestId | None = None,
   326	    ) -> dict[str, Any]:
   327	        """Send a JSON-RPC request and await its response.
   328	
   329	        `_related_request_id` is set only by `_JSONRPCDispatchContext` so that
   330	        mid-handler requests route onto the inbound request's SSE stream.
   331	
   332	        Raises:
   333	            MCPError: Peer error response; `REQUEST_TIMEOUT` if
   334	                `opts["timeout"]` elapsed; `CONNECTION_CLOSED` if the
   335	                transport closed or the dispatcher shut down.
   336	            RuntimeError: Called before `run()`.
   337	        """
   338	        # Post-close sends get the same CONNECTION_CLOSED contract as in-flight waiters.
   339	        if self._closed:
   340	            raise MCPError(code=CONNECTION_CLOSED, message="Connection closed")
   341	        if not self._running:
   342	            raise RuntimeError("JSONRPCDispatcher.send_raw_request called before run()")
   343	        opts = opts or {}
   344	        supplied_id = opts.get("request_id")
   345	        if supplied_id is not None:
   346	            request_id: RequestId = supplied_id
   347	            # The pending key gets the same coercion `_resolve_pending` applies
   348	            # to inbound response ids, so a supplied "7" still correlates
   349	            # whether the peer echoes "7" or 7. The wire id stays verbatim.
   350	            pending_key = coerce_request_id(request_id)
   351	            if pending_key in self._pending:
   352	                raise ValueError(f"request id {request_id!r} is already in flight")
   353	        else:
   354	            # Mint past any key a supplied id occupies: the collision error is
   355	            # reserved for the caller who actually chose the id.
   356	            request_id = self._allocate_id()
   357	            while request_id in self._pending:
   358	                request_id = self._allocate_id()
   359	            pending_key = request_id
   360	        out_params = dict(params) if params is not None else {}
   361	        out_meta = dict(out_params.get("_meta") or {})
   362	        on_progress = opts.get("on_progress")
   363	        if on_progress is not None:
   364	            # The request id doubles as the progress token, so `_pending[token]` finds `on_progress` directly.
   365	            out_meta["progressToken"] = request_id
   366	
   367	        # buffer=1: a close signal can arrive before the waiter parks in receive();
   368	        # a WouldBlock later just means the waiter already has its one outcome.
   369	        send, receive = anyio.create_memory_object_stream[dict[str, Any] | ErrorData](1)
   370	        pending = _Pending(send=send, receive=receive, on_progress=on_progress)
   371	        self._pending[pending_key] = pending
   372	
   373	        plan = _plan_outbound(_related_request_id, opts)
   374	        # Spec MUST: only previously-issued requests may be cancelled. A write
   375	        # interrupted by cancellation may still have delivered (a memory-stream
   376	        # send can hand its item to the receiver and still raise), so a started
   377	        # write counts as issued: the peer ignores a cancel for an id it never
   378	        # saw, while skipping it would leak a delivered request's handler.
   379	        request_write_started = False
   380	        timeout_armed = False
   381	
   382	        target = out_params.get("name")
   383	        span_name = f"MCP send {method}{f' {target}' if isinstance(target, str) else ''}"
   384	        # TODO(maxisbey): move the otel span + inject into an outbound
   385	        # middleware once that seam exists; the dispatcher should not own otel.
   386	        try:
   387	            with otel_span(
   388	                span_name,
   389	                kind=SpanKind.CLIENT,
   390	                attributes={"mcp.method.name": method, "jsonrpc.request.id": str(request_id)},
   391	            ) as span:
   392	                # SEP-414: inject W3C trace context.
   393	                inject_trace_context(out_meta)
   394	                if out_meta:
   395	                    out_params["_meta"] = out_meta
   396	                else:
   397	                    out_params.pop("_meta", None)
   398	                # Leave `params` unset when empty: with `exclude_unset=True` an explicit
   399	                # None would serialize as `"params": null`, which JSON-RPC 2.0 forbids.
   400	                if out_params:
   401	                    msg = JSONRPCRequest(jsonrpc="2.0", id=request_id, method=method, params=out_params)
   402	                else:
   403	                    msg = JSONRPCRequest(jsonrpc="2.0", id=request_id, method=method)
   404	                # Surface a pre-existing cancellation while the request provably
   405	                # never started; past this point a cancelled write counts as issued.
   406	                await anyio.lowlevel.checkpoint_if_cancelled()
   407	                request_write_started = True
   408	                with request_clock(opts.get("timeout")) as clock:
   409	                    try:
   410	                        await self._write(msg, plan.metadata)
   411	                    except (anyio.BrokenResourceError, anyio.ClosedResourceError):
   412	                        # Transport tore down before run() noticed EOF; surface the documented contract.
   413	                        raise MCPError(code=CONNECTION_CLOSED, message="Connection closed") from None
   414	                    clock.start()
   415	                    timeout_armed = True
   416	                    outcome = await receive.receive()
   417	                if isinstance(outcome, ErrorData) and outcome is not _CLOSED_OUTCOME:
   418	                    code = str(outcome.code)
   419	                    span.set_attributes({"error.type": code, "rpc.response.status_code": code})
   420	                    span.set_status(StatusCode.ERROR, outcome.message)
   421	        except TimeoutError:
   422	            if not timeout_armed:
   423	                # The clock starts only after the write, so this TimeoutError is the
   424	                # transport's own bounded send() failing - a transport error, not
   425	                # `opts["timeout"]` elapsing. Propagate it raw (v1 kept the write
   426	                # outside the timeout-catching try and did the same).
   427	                raise
   428	            # Courtesy cancel (spec-recommended, new vs v1) so the peer stops work;
   429	            # unshielded so an outer caller cancellation can still interrupt the write.
   430	            if plan.cancel_on_abandon:
   431	                await self._final_write(
   432	                    partial(
   433	                        self._cancel_outbound,
   434	                        request_id,
   435	                        f"timed out after {opts.get('timeout')}s",
   436	                        _related_request_id,
   437	                    ),
   438	                    shield=False,
   439	                    timeout=_ABANDON_WRITE_TIMEOUT,
   440	                    describe=f"courtesy cancel for timed-out request {request_id!r}",
   441	                )
   442	            raise MCPError(code=REQUEST_TIMEOUT, message=f"Request {method!r} timed out") from None
   443	        except anyio.get_cancelled_exc_class():
   444	            # Caller cancelled: bare awaits re-raise here, so the shielded helper
   445	            # lets the courtesy cancel go out before we propagate.
   446	            if plan.cancel_on_abandon and request_write_started:
   447	                await self._final_write(
   448	                    partial(self._cancel_outbound, request_id, "caller cancelled", _related_request_id),
   449	                    shield=True,
   450	                    timeout=_ABANDON_WRITE_TIMEOUT,
   451	                    describe=f"courtesy cancel for caller-cancelled request {request_id!r}",
   452	                )
   453	            raise
   454	        finally:
   455	            # Remove the waiter on every path so a late response is dropped, not leaked.
   456	            self._pending.pop(pending_key, None)
   457	            send.close()
   458	            receive.close()
   459	
   460	        if isinstance(outcome, ErrorData):
   461	            raise MCPError(code=outcome.code, message=outcome.message, data=outcome.data)
   462	        return outcome
   463	
   464	    async def notify(
   465	        self,
   466	        method: str,
   467	        params: Mapping[str, Any] | None,
   468	        opts: CallOptions | None = None,
   469	        *,
   470	        _related_request_id: RequestId | None = None,
   471	    ) -> None:
   472	        """Send a fire-and-forget notification.
   473	
   474	        Fire-and-forget all the way: a post-close send or a write onto a
   475	        torn-down transport drops the notification with a debug log instead
   476	        of raising (same policy as the response writes and `ctx.notify`).
   477	        """
   478	        if self._closed:
   479	            logger.debug("dropped %s: dispatcher closed", method)
   480	            return
   481	        # Leave `params` unset when None: with `exclude_unset=True` an explicit
   482	        # None would serialize as `"params": null`, which JSON-RPC 2.0 forbids.
   483	        if params is not None:
   484	            msg = JSONRPCNotification(jsonrpc="2.0", method=method, params=dict(params))
   485	        else:
   486	            msg = JSONRPCNotification(jsonrpc="2.0", method=method)
   487	        try:
   488	            await self._write(msg, _plan_outbound(_related_request_id, opts).metadata)
   489	        except (anyio.BrokenResourceError, anyio.ClosedResourceError):
   490	            # Transport tore down before run() noticed EOF.
   491	            logger.debug("dropped %s: write stream closed", method)
   492	
   493	    async def run(
   494	        self,
   495	        on_request: OnRequest,
   496	        on_notify: OnNotify,
   497	        on_notify_intercept: OnNotifyIntercept | None = None,
   498	        *,
   499	        task_status: anyio.abc.TaskStatus[None] = anyio.TASK_STATUS_IGNORED,
   500	    ) -> None:
   501	        """Drive the receive loop until the read stream closes.
   502	
   503	        `task_status.started()` fires once `send_raw_request` is usable.
   504	        Single-shot: once the loop ends the dispatcher stays closed and cannot be restarted.
   505	        """
   506	        self._on_notify_intercept = on_notify_intercept
   507	        try:
   508	            # LIFO exits: the write stream closes only after the task-group join, so teardown writes still land.
   509	            async with self._write_stream:
   510	                async with anyio.create_task_group() as tg:
   511	                    self._tg = tg
   512	                    self._running = True
   513	                    task_status.started()
   514	                    try:
   515	                        async with self._read_stream:
   516	                            try:
   517	                                async for item in self._read_stream:
   518	                                    # Duck-typed: only `ContextReceiveStream` carries the
   519	                                    # sender's per-message contextvars snapshot.
   520	                                    sender_ctx: contextvars.Context | None = getattr(
   521	                                        self._read_stream, "last_context", None
   522	                                    )
   523	                                    await self._dispatch(item, on_request, on_notify, sender_ctx)
   524	                            except anyio.ClosedResourceError:
   525	                                # Receive end closed under us (stateless SHTTP teardown); same as EOF.
   526	                                logger.debug("read stream closed by transport; treating as EOF")
   527	                        # EOF: wake blocked `send_raw_request` waiters with CONNECTION_CLOSED.
   528	                        self._running = False
   529	                        self._closed = True
   530	                        self._fan_out_closed()
   531	                    finally:
   532	                        # Cancel in-flight handlers; otherwise the task-group join
   533	                        # waits on handlers whose callers are already gone.
   534	                        tg.cancel_scope.cancel()
   535	        finally:
   536	            # Covers cancel/crash paths that skip the inline fan-out; idempotent.
   537	            self._running = False
   538	            self._closed = True
   539	            self._tg = None
   540	            self._fan_out_closed()
   541	            await resync_tracer()
   542	
   543	    async def _dispatch(
   544	        self,
   545	        item: SessionMessage | Exception,
   546	        on_request: OnRequest,
   547	        on_notify: OnNotify,
   548	        sender_ctx: contextvars.Context | None,
   549	    ) -> None:
   550	        """Route one inbound item.
   551	
   552	        Only `inline_methods` requests and the `on_stream_exception` observer
   553	        are awaited; any other `await` would head-of-line block the read loop.
   554	        """
   555	        if isinstance(item, Exception):
   556	            if self.on_stream_exception is None:
   557	                logger.debug("transport yielded exception: %r", item)
   558	                return
   559	            try:
   560	                await self.on_stream_exception(item)

exec
/bin/zsh -lc "nl -ba backend/.venv/lib/python3.14/site-packages/mcp/shared/jsonrpc_dispatcher.py | sed -n '543,760p'; rg -uu -n \"def handle_request|_read_stream_writer.send|SessionMessage\\(\" backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http.py | sed -n '1,220p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/streamable_http.py | sed -n '460,700p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
   543	    async def _dispatch(
   544	        self,
   545	        item: SessionMessage | Exception,
   546	        on_request: OnRequest,
   547	        on_notify: OnNotify,
   548	        sender_ctx: contextvars.Context | None,
   549	    ) -> None:
   550	        """Route one inbound item.
   551	
   552	        Only `inline_methods` requests and the `on_stream_exception` observer
   553	        are awaited; any other `await` would head-of-line block the read loop.
   554	        """
   555	        if isinstance(item, Exception):
   556	            if self.on_stream_exception is None:
   557	                logger.debug("transport yielded exception: %r", item)
   558	                return
   559	            try:
   560	                await self.on_stream_exception(item)
   561	            except Exception:
   562	                logger.exception("on_stream_exception observer raised")
   563	            return
   564	        metadata = item.metadata
   565	        msg = item.message
   566	        match msg:
   567	            case JSONRPCRequest():
   568	                await self._dispatch_request(msg, metadata, on_request, sender_ctx)
   569	            case JSONRPCNotification():
   570	                self._dispatch_notification(msg, metadata, on_notify, sender_ctx)
   571	            case JSONRPCResponse():
   572	                self._resolve_pending(msg.id, msg.result)
   573	            case JSONRPCError():  # pragma: no branch
   574	                # Exhaustive over JSONRPCMessage, so the no-match arc is unreachable.
   575	                self._resolve_pending(msg.id, msg.error)
   576	
   577	    async def _dispatch_request(
   578	        self,
   579	        req: JSONRPCRequest,
   580	        metadata: MessageMetadata,
   581	        on_request: OnRequest,
   582	        sender_ctx: contextvars.Context | None,
   583	    ) -> None:
   584	        progress_token = progress_token_from_params(req.params)
   585	        try:
   586	            transport_ctx = self._transport_builder(metadata)
   587	        except Exception:
   588	            # A raising builder must cost only this message, not the connection.
   589	            logger.exception("transport_builder raised; rejecting request %r", req.id)
   590	            self._spawn(
   591	                self._write_error,
   592	                req.id,
   593	                ErrorData(code=INTERNAL_ERROR, message="transport context unavailable"),
   594	                sender_ctx=sender_ctx,
   595	            )
   596	            return
   597	        dctx = _JSONRPCDispatchContext(
   598	            transport=transport_ctx,
   599	            _dispatcher=self,
   600	            _request_id=req.id,
   601	            message_metadata=metadata,
   602	            _progress_token=progress_token,
   603	        )
   604	        scope = anyio.CancelScope()
   605	        # TODO(maxisbey): duplicate ids blind-overwrite (v1/TS parity); revisit
   606	        # rejecting with INVALID_REQUEST. Key coerced so a stringified
   607	        # `notifications/cancelled` id still correlates.
   608	        self._in_flight[coerce_request_id(req.id)] = _InFlight(scope=scope, dctx=dctx)
   609	        if req.method in self._inline_methods:
   610	            # Spawn so `sender_ctx` applies, but park the read loop until the
   611	            # handler returns - that's the inline ordering guarantee.
   612	            done = anyio.Event()
   613	
   614	            async def _run_inline() -> None:
   615	                try:
   616	                    await self._handle_request(req, dctx, scope, on_request)
   617	                finally:
   618	                    done.set()
   619	
   620	            self._spawn(_run_inline, sender_ctx=sender_ctx)
   621	            await done.wait()
   622	        else:
   623	            self._spawn(self._handle_request, req, dctx, scope, on_request, sender_ctx=sender_ctx)
   624	
   625	    def _dispatch_notification(
   626	        self,
   627	        msg: JSONRPCNotification,
   628	        metadata: MessageMetadata,
   629	        on_notify: OnNotify,
   630	        sender_ctx: contextvars.Context | None,
   631	    ) -> None:
   632	        """Route one inbound notification.
   633	
   634	        `notifications/cancelled` and `notifications/progress` are intercepted
   635	        here (they correlate against the `_in_flight`/`_pending` tables this
   636	        layer owns) and still teed to `on_notify` afterwards. The caller's
   637	        `on_notify_intercept` then runs in receive order; only unconsumed
   638	        notifications reach the spawned `on_notify`.
   639	        """
   640	        if msg.method == "notifications/cancelled":
   641	            rid = cancelled_request_id_from_params(msg.params)
   642	            if rid is not None and (in_flight := self._in_flight.get(coerce_request_id(rid))) is not None:
   643	                in_flight.dctx.cancel_requested.set()
   644	                if self._peer_cancel_mode == "interrupt":
   645	                    in_flight.scope.cancel()
   646	        elif msg.method == "notifications/progress":
   647	            match msg.params:
   648	                case {"progressToken": str() | int() as token, "progress": int() | float() as progress} if (
   649	                    not isinstance(token, bool)
   650	                    and not isinstance(progress, bool)
   651	                    and (pending := self._pending.get(coerce_request_id(token))) is not None
   652	                    and pending.on_progress is not None
   653	                ):
   654	                    total = msg.params.get("total")
   655	                    message = msg.params.get("message")
   656	                    self._spawn(
   657	                        _shielded_progress(pending.on_progress),
   658	                        float(progress),
   659	                        float(total) if isinstance(total, int | float) else None,
   660	                        message if isinstance(message, str) else None,
   661	                        sender_ctx=sender_ctx,
   662	                    )
   663	                case _:
   664	                    pass
   665	        if run_notify_intercept(self._on_notify_intercept, msg.method, msg.params):
   666	            return
   667	        try:
   668	            transport_ctx = self._transport_builder(metadata)
   669	        except Exception:
   670	            # Same containment as `_dispatch_request`: drop the notification, keep the loop.
   671	            logger.exception("transport_builder raised; dropping notification %r", msg.method)
   672	            return
   673	        dctx = _JSONRPCDispatchContext(
   674	            transport=transport_ctx, _dispatcher=self, _request_id=None, message_metadata=metadata
   675	        )
   676	        self._spawn(_contained_notify(on_notify), dctx, msg.method, msg.params, sender_ctx=sender_ctx)
   677	
   678	    def _resolve_pending(self, request_id: RequestId | None, outcome: dict[str, Any] | ErrorData) -> None:
   679	        pending = self._pending.get(coerce_request_id(request_id)) if request_id is not None else None
   680	        if pending is None:
   681	            logger.debug("dropping response for unknown/late request id %r", request_id)
   682	            return
   683	        try:
   684	            pending.send.send_nowait(outcome)
   685	        except (anyio.WouldBlock, anyio.BrokenResourceError, anyio.ClosedResourceError):
   686	            logger.debug("waiter for request id %r already gone", request_id)
   687	
   688	    def _spawn(
   689	        self,
   690	        fn: Callable[..., Awaitable[Any]],
   691	        *args: object,
   692	        sender_ctx: contextvars.Context | None,
   693	    ) -> None:
   694	        """Schedule `fn(*args)` in the run() task group, propagating the sender's contextvars.
   695	
   696	        ASGI middleware (auth, OTel) sets contextvars on the task that wrote the
   697	        message; `Context.run` makes the spawned handler inherit that context.
   698	        """
   699	        assert self._tg is not None
   700	
   701	        async def run() -> None:
   702	            await fn(*args)
   703	
   704	        if sender_ctx is not None:
   705	            sender_ctx.run(self._tg.start_soon, run)
   706	        else:
   707	            self._tg.start_soon(run)
   708	
   709	    def _fan_out_closed(self) -> None:
   710	        """Wake every pending `send_raw_request` waiter with `CONNECTION_CLOSED`.
   711	
   712	        Synchronous: callers may be inside a cancelled scope. Idempotent.
   713	        """
   714	        for pending in self._pending.values():
   715	            try:
   716	                pending.send.send_nowait(_CLOSED_OUTCOME)
   717	            except (anyio.WouldBlock, anyio.BrokenResourceError, anyio.ClosedResourceError):
   718	                pass
   719	        self._pending.clear()
   720	
   721	    async def _handle_request(
   722	        self,
   723	        req: JSONRPCRequest,
   724	        dctx: _JSONRPCDispatchContext[TransportT],
   725	        scope: anyio.CancelScope,
   726	        on_request: OnRequest,
   727	    ) -> None:
   728	        """Run `on_request` for one inbound request and write its response.
   729	
   730	        The single exception-to-wire boundary: handler exceptions become
   731	        `JSONRPCError` here. A request the peer cancelled is never answered
   732	        (spec: MUST NOT send further messages for it) - it settles unanswered
   733	        instead, and `_settle_unanswered` tells the transport.
   734	        """
   735	        answer_write_started = False
   736	        handler_failure: BaseException | None = None  # re-raised once the request settles
   737	        try:
   738	            with scope:
   739	                try:
   740	                    result = await on_request(dctx, req.method, req.params)
   741	                finally:
   742	                    # Close the back-channel and drop from `_in_flight`; no checkpoint
   743	                    # since handler return, so a peer cancel can't interleave.
   744	                    # Identity guard: don't evict a duplicate id's newer entry.
   745	                    dctx.close()
   746	                    key = coerce_request_id(req.id)
   747	                    if (entry := self._in_flight.get(key)) is not None and entry.dctx is dctx:
   748	                        del self._in_flight[key]
   749	                if not dctx.cancel_requested.is_set():
   750	                    # A write interrupted by cancellation may still have delivered
   751	                    # (a memory-stream send can hand its item to the receiver and
   752	                    # still raise), so a started answer write counts as sent below:
   753	                    # peers drop late responses, while a second answer for one id
   754	                    # would break JSON-RPC.
   755	                    answer_write_started = True
   756	                    await self._write_result(req.id, result)
   757	        except anyio.get_cancelled_exc_class():
   758	            # Shutdown: answer the request so the peer isn't left waiting - unless
   759	            # an answer write already started (it may have reached the transport;
   760	            # prefer possibly-zero answers over possibly-two), or the peer already
336:        return SessionMessage(message, metadata=metadata)
458:        await self._write_stream.send(SessionMessage(JSONRPCError(jsonrpc="2.0", id=request_id, error=error)))
474:    async def handle_request(self, scope: Scope, receive: Receive, send: Send) -> None:
628:                session_message = SessionMessage(message, metadata=self._message_metadata(request))
653:                session_message = SessionMessage(message, metadata=metadata)
   460	    async def _clean_up_memory_streams(self, request_id: RequestId) -> None:
   461	        """Clean up memory streams for a given request ID."""
   462	        if request_id in self._request_streams:  # pragma: no branch
   463	            try:
   464	                # Close the request stream
   465	                await self._request_streams[request_id][0].aclose()
   466	                await self._request_streams[request_id][1].aclose()
   467	            except Exception:  # pragma: no cover
   468	                # During cleanup, we catch all exceptions since streams might be in various states
   469	                logger.debug("Error closing memory streams - may already be closed")
   470	            finally:
   471	                # Remove the request stream from the mapping
   472	                self._request_streams.pop(request_id, None)
   473	
   474	    async def handle_request(self, scope: Scope, receive: Receive, send: Send) -> None:
   475	        """Application entry point that handles all HTTP requests."""
   476	        if self.idle_scope is None or self._idle_timeout is None:
   477	            await self._handle_request(scope, receive, send)
   478	            return
   479	
   480	        if self.idle_scope.cancel_called:
   481	            # The idle period already ran out and the host is ending this
   482	            # session: answer as terminated rather than dispatch into a
   483	            # message loop that is going away.
   484	            if not self._terminated:
   485	                await self.terminate()
   486	            await self._handle_request(scope, receive, send)
   487	            return
   488	
   489	        # A request in flight (an open GET stream included) holds the session:
   490	        # the idle countdown is suspended while any is being served and
   491	        # restarts when the last one completes.
   492	        self._requests_in_flight += 1
   493	        self.idle_scope.deadline = math.inf
   494	        try:
   495	            await self._handle_request(scope, receive, send)
   496	        finally:
   497	            self._requests_in_flight -= 1
   498	            if not self._requests_in_flight:
   499	                self.idle_scope.deadline = anyio.current_time() + self._idle_timeout
   500	
   501	    async def _handle_request(self, scope: Scope, receive: Receive, send: Send) -> None:
   502	        request = Request(scope, receive)
   503	
   504	        # Validate request headers for DNS rebinding protection
   505	        is_post = request.method == "POST"
   506	        error_response = await self._security.validate_request(request, is_post=is_post)
   507	        if error_response:
   508	            await error_response(scope, receive, send)
   509	            return
   510	
   511	        if self._terminated:
   512	            # If the session has been terminated, return 404 Not Found
   513	            response = self._create_error_response(
   514	                "Not Found: Session has been terminated",
   515	                HTTPStatus.NOT_FOUND,
   516	            )
   517	            await response(scope, receive, send)
   518	            return
   519	
   520	        if request.method == "POST":
   521	            await self._handle_post_request(scope, request, receive, send)
   522	        elif request.method == "GET":
   523	            await self._handle_get_request(request, send)
   524	        elif request.method == "DELETE":
   525	            await self._handle_delete_request(request, send)
   526	        else:
   527	            await self._handle_unsupported_request(request, send)
   528	
   529	    def _check_content_type(self, request: Request) -> bool:
   530	        """Check if the request has the correct Content-Type."""
   531	        content_type = request.headers.get("content-type", "")
   532	        content_type_parts = [part.strip() for part in content_type.split(";")[0].split(",")]
   533	
   534	        return any(part == CONTENT_TYPE_JSON for part in content_type_parts)
   535	
   536	    async def _validate_accept_header(self, request: Request, scope: Scope, send: Send) -> bool:
   537	        """Validate Accept header based on response mode. Returns True if valid."""
   538	        has_json, has_sse = check_accept_headers(request)
   539	        if self.is_json_response_enabled:
   540	            # For JSON-only responses, only require application/json
   541	            if not has_json:
   542	                response = self._create_error_response(
   543	                    "Not Acceptable: Client must accept application/json",
   544	                    HTTPStatus.NOT_ACCEPTABLE,
   545	                )
   546	                await response(scope, request.receive, send)
   547	                return False
   548	        # For SSE responses, require both content types
   549	        elif not (has_json and has_sse):
   550	            response = self._create_error_response(
   551	                "Not Acceptable: Client must accept both application/json and text/event-stream",
   552	                HTTPStatus.NOT_ACCEPTABLE,
   553	            )
   554	            await response(scope, request.receive, send)
   555	            return False
   556	        return True
   557	
   558	    async def _handle_post_request(self, scope: Scope, request: Request, receive: Receive, send: Send) -> None:
   559	        """Handle POST requests containing JSON-RPC messages."""
   560	        writer = self._read_stream_writer
   561	        if writer is None:  # pragma: no cover
   562	            raise ValueError("No read stream writer available. Ensure connect() is called first.")
   563	        try:
   564	            # Validate Accept header
   565	            if not await self._validate_accept_header(request, scope, send):
   566	                return
   567	
   568	            # Validate Content-Type
   569	            if not self._check_content_type(request):  # pragma: no cover
   570	                response = self._create_error_response(
   571	                    "Unsupported Media Type: Content-Type must be application/json",
   572	                    HTTPStatus.UNSUPPORTED_MEDIA_TYPE,
   573	                )
   574	                await response(scope, receive, send)
   575	                return
   576	
   577	            # Parse the body - only read it once
   578	            body = await request.body()
   579	
   580	            try:
   581	                raw_message = pydantic_core.from_json(body)
   582	            except ValueError as e:
   583	                response = self._create_error_response(f"Parse error: {str(e)}", HTTPStatus.BAD_REQUEST, PARSE_ERROR)
   584	                await response(scope, receive, send)
   585	                return
   586	
   587	            try:
   588	                message = jsonrpc_message_adapter.validate_python(raw_message, by_name=False)
   589	            except ValidationError as e:
   590	                response = self._create_error_response(
   591	                    f"Validation error: {str(e)}",
   592	                    HTTPStatus.BAD_REQUEST,
   593	                    INVALID_PARAMS,
   594	                )
   595	                await response(scope, receive, send)
   596	                return
   597	
   598	            # Check if this is an initialization request
   599	            is_initialization_request = isinstance(message, JSONRPCRequest) and message.method == "initialize"
   600	
   601	            if is_initialization_request:
   602	                # Check if the server already has an established session
   603	                if self.mcp_session_id:
   604	                    # Check if request has a session ID
   605	                    request_session_id = self._get_session_id(request)
   606	
   607	                    # If request has a session ID but doesn't match, return 404
   608	                    if request_session_id and request_session_id != self.mcp_session_id:  # pragma: no cover
   609	                        response = self._create_error_response(
   610	                            "Not Found: Invalid or expired session ID",
   611	                            HTTPStatus.NOT_FOUND,
   612	                        )
   613	                        await response(scope, receive, send)
   614	                        return
   615	            elif not await self._validate_request_headers(request, send):
   616	                return
   617	
   618	            # For notifications and responses only, return 202 Accepted
   619	            if not isinstance(message, JSONRPCRequest):
   620	                # Create response object and send it
   621	                response = self._create_json_response(
   622	                    None,
   623	                    HTTPStatus.ACCEPTED,
   624	                )
   625	                await response(scope, receive, send)
   626	
   627	                # Process the message after sending the response
   628	                session_message = SessionMessage(message, metadata=self._message_metadata(request))
   629	                await writer.send(session_message)
   630	
   631	                return
   632	
   633	            # Extract protocol version for priming event decision.
   634	            # For initialize requests, get from request params.
   635	            # For other requests, get from header (already validated).
   636	            protocol_version = (
   637	                str(message.params.get("protocolVersion", DEFAULT_NEGOTIATED_VERSION))
   638	                if is_initialization_request and message.params
   639	                else request.headers.get(MCP_PROTOCOL_VERSION_HEADER, DEFAULT_NEGOTIATED_VERSION)
   640	            )
   641	
   642	            request_id = str(message.id)
   643	
   644	            if self.is_json_response_enabled:
   645	                self._request_streams[request_id] = anyio.create_memory_object_stream[EventMessage](
   646	                    REQUEST_STREAM_BUFFER_SIZE
   647	                )
   648	                request_stream_reader = self._request_streams[request_id][1]
   649	                # Process the message
   650	                metadata = self._message_metadata(
   651	                    request, on_request_unanswered=partial(self._terminate_unanswered_request, message.id)
   652	                )
   653	                session_message = SessionMessage(message, metadata=metadata)
   654	                await writer.send(session_message)
   655	                try:
   656	                    # `message_router` deposits only this request's own response
   657	                    # here: anything else scoped to the request has no wire in
   658	                    # JSON-response mode.
   659	                    event_message = await request_stream_reader.receive()
   660	                except (anyio.EndOfStream, anyio.ClosedResourceError):
   661	                    # The stream closed with no response: the session was
   662	                    # terminated while this request was in flight.
   663	                    logger.debug(f"Session terminated with request {request_id} in flight; no response to send")
   664	                    response = self._create_error_response(
   665	                        "Session terminated before the request completed",
   666	                        HTTPStatus.INTERNAL_SERVER_ERROR,
   667	                        INTERNAL_ERROR,
   668	                    )
   669	                else:
   670	                    response = self._create_json_response(event_message.message)
   671	                finally:
   672	                    await self._clean_up_memory_streams(request_id)
   673	                await response(scope, receive, send)
   674	            else:
   675	                # Mint the priming event before any per-request state exists:
   676	                # `EventStore.store_event` is user code and may raise, in which
   677	                # case the outer handler returns a 500 with nothing to clean up.
   678	                # Still strictly precedes dispatch, so storage order == wire order.
   679	                priming_event = await self._mint_priming_event(request_id, protocol_version)
   680	
   681	                sse_stream_writer, sse_stream_reader = anyio.create_memory_object_stream[SSEEvent](0)
   682	                self._sse_stream_writers[request_id] = sse_stream_writer
   683	                self._request_streams[request_id] = anyio.create_memory_object_stream[EventMessage](
   684	                    REQUEST_STREAM_BUFFER_SIZE
   685	                )
   686	                request_stream_reader = self._request_streams[request_id][1]
   687	
   688	                headers = {
   689	                    "Cache-Control": "no-cache, no-transform",
   690	                    "Connection": "keep-alive",
   691	                    "Content-Type": CONTENT_TYPE_SSE,
   692	                    **({MCP_SESSION_ID_HEADER: self.mcp_session_id} if self.mcp_session_id else {}),
   693	                }
   694	                response = EventSourceResponse(
   695	                    content=sse_stream_reader,
   696	                    data_sender_callable=partial(
   697	                        self._run_sse_writer, request_id, sse_stream_writer, request_stream_reader, priming_event
   698	                    ),
   699	                    headers=headers,
   700	                )

exec
/bin/zsh -lc "git show 12f9085:backend/app/export_content.py | nl -ba | sed -n '1,260p'; git show 12f9085:backend/app/content_ops.py | nl -ba | sed -n '1,420p'; git show 12f9085:backend/tests/test_admin_api.py | nl -ba | sed -n '1,340p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
     1	"""Xuất nội dung trong DB ra đúng shape `content.json` (CÓ judge) — DB là nguồn chính.
     2	
     3	    python -m app.export_content [path]     # mặc định in ra stdout
     4	
     5	Sửa nội dung bằng file thì: export → sửa file → `python -m app.load_content --force <file>`.
     6	`admin_version` là sha256 của TOÀN BỘ nội dung (kể cả judge) — khác `version` công khai của
     7	`/content` (bỏ judge): admin chỉ sửa test case cũng phải đổi version để kiểm xung đột (409).
     8	"""
     9	
    10	from __future__ import annotations
    11	
    12	import hashlib
    13	import json
    14	import sys
    15	
    16	from sqlalchemy import select
    17	from sqlalchemy.orm import Session
    18	
    19	from app.content_api import ContentNotLoaded, _read_tree, _version
    20	from app.tables import Exercise
    21	
    22	_READ_ATTEMPTS = 3
    23	
    24	
    25	def _with_judges(session: Session, tree: dict) -> dict:
    26	    judges = {
    27	        i: {"solution": s, "cases": c}
    28	        for i, s, c in session.execute(select(Exercise.id, Exercise.judge_solution, Exercise.judge_cases))
    29	    }
    30	    return {
    31	        "themes": tree["themes"],
    32	        "exercises": {i: {**ex, "judge": judges[i]} for i, ex in tree["exercises"].items()},
    33	    }
    34	
    35	
    36	def export_content(session: Session) -> dict:
    37	    """Nội dung đầy đủ đang có trong DB. Cùng cơ chế đọc-lại của `read_content`: version đầu == cuối
    38	    thì mọi câu SELECT thấy cùng một lần nạp."""
    39	    for _ in range(_READ_ATTEMPTS):
    40	        before = _version(session)
    41	        if before is None:
    42	            raise ContentNotLoaded()
    43	        try:
    44	            data = _with_judges(session, _read_tree(session))
    45	        except KeyError:
    46	            continue
    47	        if _version(session) == before:
    48	            return data
    49	    raise RuntimeError("Nội dung đang được nạp lại liên tục, đọc không ổn định")
    50	
    51	
    52	def admin_version(data: dict) -> str:
    53	    full = {"themes": data["themes"], "exercises": data["exercises"]}
    54	    canonical = json.dumps(full, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    55	    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    56	
    57	
    58	def main(argv: list[str]) -> int:
    59	    from app.db import SessionLocal
    60	
    61	    with SessionLocal() as session:
    62	        data = export_content(session)
    63	    text = json.dumps({"version": "source", **data}, ensure_ascii=False, indent=2) + "\n"
    64	    if len(argv) > 1:
    65	        with open(argv[1], "w", encoding="utf-8") as fh:
    66	            fh.write(text)
    67	    else:
    68	        sys.stdout.write(text)
    69	    return 0
    70	
    71	
    72	if __name__ == "__main__":
    73	    sys.exit(main(sys.argv))
     1	"""Phép đọc/ghi THUẦN trên cây nội dung (shape `content.json`) cho MCP server.
     2	
     3	Không đụng DB, không mutate input: hàm ghi deepcopy rồi trả bản mới. Chỉ kiểm cấu trúc (tồn tại /
     4	trùng / field cho phép / kiểu cơ bản); luật nội dung chi tiết là việc của `load_content.validation_errors`
     5	ở tầng gọi. "project" = theme, "module" = topic, "lesson" = exercise.
     6	"""
     7	
     8	from __future__ import annotations
     9	
    10	import copy
    11	from typing import Any, Iterator
    12	
    13	
    14	class ContentOpError(Exception):
    15	    """Thao tác sai (id không tồn tại / đã tồn tại / field không cho sửa / kiểu sai). Thông điệp tiếng Việt."""
    16	
    17	
    18	# ---------- helper nội bộ ----------
    19	
    20	
    21	def _need_dict(value: Any, what: str) -> dict:
    22	    if not isinstance(value, dict):
    23	        raise ContentOpError(f"{what} phải là object (dict)")
    24	    return value
    25	
    26	
    27	def _need_id(value: Any, what: str) -> str:
    28	    if not isinstance(value, str) or not value.strip():
    29	        raise ContentOpError(f"{what} phải là chuỗi không rỗng")
    30	    return value
    31	
    32	
    33	def _need_str(value: Any, what: str) -> str:
    34	    if not isinstance(value, str):
    35	        raise ContentOpError(f"{what} phải là chuỗi")
    36	    return value
    37	
    38	
    39	def _need_list(value: Any, what: str) -> list:
    40	    if not isinstance(value, list):
    41	        raise ContentOpError(f"{what} phải là danh sách")
    42	    return value
    43	
    44	
    45	def _walk(topics: list[dict]) -> Iterator[dict]:
    46	    for tp in topics:
    47	        yield tp
    48	        yield from _walk(tp.get("modules", []))
    49	
    50	
    51	def _all_modules(content: dict) -> Iterator[tuple[dict, dict]]:
    52	    """(theme, module) cho mọi module ở mọi độ sâu."""
    53	    for th in content.get("themes", []):
    54	        for tp in _walk(th.get("topics", [])):
    55	            yield th, tp
    56	
    57	
    58	def _all_files(content: dict) -> Iterator[tuple[dict, dict, dict]]:
    59	    for th, tp in _all_modules(content):
    60	        for f in tp.get("files", []):
    61	            yield th, tp, f
    62	
    63	
    64	def _used_ids(content: dict) -> set[str]:
    65	    """Không gian tên chung: theme, module, file, bài, ô."""
    66	    ids: set[str] = set()
    67	    for th in content.get("themes", []):
    68	        ids.add(th["id"])
    69	    for _, tp in _all_modules(content):
    70	        ids.add(tp["id"])
    71	    for _, _, f in _all_files(content):
    72	        ids.add(f["id"])
    73	    for key, ex in content.get("exercises", {}).items():
    74	        ids.add(key)
    75	        ids.add(ex.get("id", key))
    76	        for b in ex.get("blocks", []):
    77	            if isinstance(b, dict) and "id" in b:
    78	                ids.add(b["id"])
    79	    return ids
    80	
    81	
    82	def _find_theme(content: dict, project_id: str) -> dict:
    83	    for th in content.get("themes", []):
    84	        if th["id"] == project_id:
    85	            return th
    86	    raise ContentOpError(f"Không tìm thấy project '{project_id}'")
    87	
    88	
    89	def _find_module(content: dict, module_id: str) -> tuple[dict, dict]:
    90	    for th, tp in _all_modules(content):
    91	        if tp["id"] == module_id:
    92	            return th, tp
    93	    raise ContentOpError(f"Không tìm thấy module '{module_id}'")
    94	
    95	
    96	def _find_file(content: dict, file_id: str) -> dict:
    97	    for _, _, f in _all_files(content):
    98	        if f["id"] == file_id:
    99	            return f
   100	    raise ContentOpError(f"Không tìm thấy file '{file_id}'")
   101	
   102	
   103	def _find_lesson(content: dict, lesson_id: str) -> dict:
   104	    ex = content.get("exercises", {})
   105	    if lesson_id not in ex:
   106	        raise ContentOpError(f"Không tìm thấy bài '{lesson_id}'")
   107	    return ex[lesson_id]
   108	
   109	
   110	def _check_free(content: dict, new_id: str, what: str, extra: set[str] | None = None) -> None:
   111	    if new_id in _used_ids(content) or (extra and new_id in extra):
   112	        raise ContentOpError(f"{what} '{new_id}' đã tồn tại (id dùng chung cho project/module/file/bài/ô)")
   113	
   114	
   115	def _check_changes(changes: Any, allowed: set[str], what: str) -> dict:
   116	    _need_dict(changes, "changes")
   117	    bad = sorted(set(changes) - allowed)
   118	    if bad:
   119	        raise ContentOpError(f"Không được sửa field {bad} của {what}; chỉ được sửa {sorted(allowed)}")
   120	    return changes
   121	
   122	
   123	def _check_fields(obj: dict, fields: dict[str, type], what: str) -> None:
   124	    for name, typ in fields.items():
   125	        if name not in obj:
   126	            raise ContentOpError(f"{what} thiếu field '{name}'")
   127	        if not isinstance(obj[name], typ):
   128	            raise ContentOpError(f"{what}: field '{name}' sai kiểu (cần {typ.__name__})")
   129	
   130	
   131	# ---------- đọc ----------
   132	
   133	
   134	def _count(topics: list[dict]) -> tuple[int, int, set[str]]:
   135	    modules = files = 0
   136	    lessons: set[str] = set()
   137	    for tp in _walk(topics):
   138	        modules += 1
   139	        files += len(tp.get("files", []))
   140	        for f in tp.get("files", []):
   141	            lessons.update(f.get("exercise_ids", []))
   142	    return modules, files, lessons
   143	
   144	
   145	def list_projects(content: dict) -> list[dict]:
   146	    out = []
   147	    for th in content.get("themes", []):
   148	        m, f, lessons = _count(th.get("topics", []))
   149	        out.append(
   150	            {
   151	                "id": th["id"],
   152	                "name": th["name"],
   153	                "description": th["description"],
   154	                "tags": copy.deepcopy(th.get("tags", [])),
   155	                "module_count": m,
   156	                "file_count": f,
   157	                "lesson_count": len(lessons),
   158	            }
   159	        )
   160	    return out
   161	
   162	
   163	def project_tree(content: dict, project_id: str) -> dict:
   164	    th = _find_theme(content, project_id)
   165	    exercises = content.get("exercises", {})
   166	
   167	    def mod(tp: dict) -> dict:
   168	        files = []
   169	        for f in tp.get("files", []):
   170	            lessons = []
   171	            for eid in f.get("exercise_ids", []):
   172	                ex = exercises.get(eid, {})
   173	                lessons.append(
   174	                    {
   175	                        "id": eid,
   176	                        "title": ex.get("title"),
   177	                        "class_name": ex.get("class_name"),
   178	                        "function_name": ex.get("function_name"),
   179	                    }
   180	                )
   181	            files.append({"id": f["id"], "name": f["name"], "lessons": lessons})
   182	        return {
   183	            "id": tp["id"],
   184	            "name": tp["name"],
   185	            "description": tp["description"],
   186	            "files": files,
   187	            "modules": [mod(s) for s in tp.get("modules", [])],
   188	        }
   189	
   190	    return {
   191	        "id": th["id"],
   192	        "name": th["name"],
   193	        "description": th["description"],
   194	        "tags": copy.deepcopy(th.get("tags", [])),
   195	        "diagram": copy.deepcopy(th.get("diagram", {"classes": [], "relations": []})),
   196	        "modules": [mod(tp) for tp in th.get("topics", [])],
   197	    }
   198	
   199	
   200	def get_lesson(content: dict, lesson_id: str) -> dict:
   201	    ex = copy.deepcopy(_find_lesson(content, lesson_id))
   202	    locations = [
   203	        {"project_id": th["id"], "module_id": tp["id"], "file_id": f["id"]}
   204	        for th, tp, f in _all_files(content)
   205	        if lesson_id in f.get("exercise_ids", [])
   206	    ]
   207	    ex["locations"] = locations
   208	    return ex
   209	
   210	
   211	# ---------- ghi: bài ----------
   212	
   213	
   214	def create_lesson(content: dict, file_id: str, lesson: dict) -> dict:
   215	    _need_dict(lesson, "lesson")
   216	    lid = _need_id(lesson.get("id"), "lesson.id")
   217	    new = copy.deepcopy(content)
   218	    f = _find_file(new, file_id)
   219	    blocks = lesson.get("blocks", [])
   220	    _need_list(blocks, "lesson.blocks")
   221	    block_ids: list[str] = []
   222	    for b in blocks:
   223	        _need_dict(b, "ô (block)")
   224	        block_ids.append(_need_id(b.get("id"), "block.id"))
   225	    if len(set(block_ids)) != len(block_ids):
   226	        raise ContentOpError("lesson có id ô (block) bị trùng nhau")
   227	    _check_free(new, lid, "id bài")
   228	    for bid in block_ids:
   229	        _check_free(new, bid, "id ô", extra={lid})
   230	    new["exercises"][lid] = copy.deepcopy(lesson)
   231	    f["exercise_ids"].append(lid)
   232	    return new
   233	
   234	
   235	def update_lesson(content: dict, lesson_id: str, changes: dict) -> dict:
   236	    _need_dict(changes, "changes")
   237	    if "id" in changes:
   238	        raise ContentOpError("Không được đổi 'id' của bài")
   239	    new = copy.deepcopy(content)
   240	    ex = _find_lesson(new, lesson_id)
   241	    if "blocks" in changes:
   242	        _need_list(changes["blocks"], "blocks")
   243	        old_ids = {b["id"] for b in ex.get("blocks", []) if isinstance(b, dict) and "id" in b}
   244	        taken = _used_ids(new) - old_ids
   245	        seen: set[str] = set()
   246	        for b in changes["blocks"]:
   247	            _need_dict(b, "ô (block)")
   248	            bid = _need_id(b.get("id"), "block.id")
   249	            if bid in taken or bid in seen:
   250	                raise ContentOpError(f"id ô '{bid}' đã tồn tại hoặc bị trùng")
   251	            seen.add(bid)
   252	    ex.update(copy.deepcopy(changes))
   253	    return new
   254	
   255	
   256	# ---------- ghi: project / module / file ----------
   257	
   258	
   259	def create_project(content: dict, project: dict, first_module: dict) -> dict:
   260	    _need_dict(project, "project")
   261	    _need_dict(first_module, "first_module")
   262	    pid = _need_id(project.get("id"), "project.id")
   263	    mid = _need_id(first_module.get("id"), "first_module.id")
   264	    _check_fields(project, {"name": str, "description": str}, "project")
   265	    _check_fields(first_module, {"name": str, "description": str}, "first_module")
   266	    if pid == mid:
   267	        raise ContentOpError(f"project và module đầu không được cùng id '{pid}'")
   268	    new = copy.deepcopy(content)
   269	    _check_free(new, pid, "id project")
   270	    _check_free(new, mid, "id module", extra={pid})
   271	    module = {
   272	        "id": mid,
   273	        "name": first_module["name"],
   274	        "description": first_module["description"],
   275	        "files": copy.deepcopy(first_module.get("files", [])),
   276	        "modules": copy.deepcopy(first_module.get("modules", [])),
   277	    }
   278	    theme = {
   279	        "id": pid,
   280	        "name": project["name"],
   281	        "description": project["description"],
   282	        "tags": copy.deepcopy(project.get("tags", [])),
   283	        "diagram": copy.deepcopy(project.get("diagram", {"classes": [], "relations": []})),
   284	        "topics": [module],
   285	    }
   286	    new["themes"].append(theme)
   287	    return new
   288	
   289	
   290	_PROJECT_EDITABLE = {"name", "description", "tags", "diagram"}
   291	
   292	
   293	def update_project(content: dict, project_id: str, changes: dict) -> dict:
   294	    _check_changes(changes, _PROJECT_EDITABLE, "project")
   295	    new = copy.deepcopy(content)
   296	    _find_theme(new, project_id).update(copy.deepcopy(changes))
   297	    return new
   298	
   299	
   300	def create_module(content: dict, project_id: str, module: dict, parent_module_id: str | None = None) -> dict:
   301	    _need_dict(module, "module")
   302	    mid = _need_id(module.get("id"), "module.id")
   303	    _check_fields(module, {"name": str, "description": str}, "module")
   304	    new = copy.deepcopy(content)
   305	    th = _find_theme(new, project_id)
   306	    _check_free(new, mid, "id module")
   307	    entry = {
   308	        "id": mid,
   309	        "name": module["name"],
   310	        "description": module["description"],
   311	        "files": copy.deepcopy(module.get("files", [])),
   312	        "modules": copy.deepcopy(module.get("modules", [])),
   313	    }
   314	    if parent_module_id is None:
   315	        th["topics"].append(entry)
   316	        return new
   317	    for tp in _walk(th["topics"]):
   318	        if tp["id"] == parent_module_id:
   319	            tp["modules"].append(entry)
   320	            return new
   321	    # phân biệt "không tồn tại" và "thuộc project khác"
   322	    try:
   323	        _find_module(new, parent_module_id)
   324	    except ContentOpError:
   325	        raise ContentOpError(f"Không tìm thấy module cha '{parent_module_id}'") from None
   326	    raise ContentOpError(f"Module cha '{parent_module_id}' không thuộc project '{project_id}'")
   327	
   328	
   329	def update_module(content: dict, module_id: str, changes: dict) -> dict:
   330	    _check_changes(changes, {"name", "description"}, "module")
   331	    new = copy.deepcopy(content)
   332	    _find_module(new, module_id)[1].update(copy.deepcopy(changes))
   333	    return new
   334	
   335	
   336	def create_file(content: dict, module_id: str, file: dict) -> dict:
   337	    _need_dict(file, "file")
   338	    fid = _need_id(file.get("id"), "file.id")
   339	    _check_fields(file, {"name": str}, "file")
   340	    eids = _need_list(file.get("exercise_ids", []), "file.exercise_ids")
   341	    new = copy.deepcopy(content)
   342	    _, tp = _find_module(new, module_id)
   343	    _check_free(new, fid, "id file")
   344	    _check_exercise_ids(new, eids)
   345	    tp["files"].append({"id": fid, "name": file["name"], "exercise_ids": list(eids)})
   346	    return new
   347	
   348	
   349	def _check_exercise_ids(content: dict, eids: list) -> None:
   350	    for e in eids:
   351	        _need_id(e, "exercise_ids[]")
   352	        if e not in content.get("exercises", {}):
   353	            raise ContentOpError(f"Bài '{e}' không tồn tại trong exercises")
   354	
   355	
   356	def update_file(content: dict, file_id: str, changes: dict) -> dict:
   357	    _check_changes(changes, {"name", "exercise_ids"}, "file")
   358	    if "name" in changes:
   359	        _need_str(changes["name"], "name")
   360	    if "exercise_ids" in changes:
   361	        _need_list(changes["exercise_ids"], "exercise_ids")
   362	    new = copy.deepcopy(content)
   363	    f = _find_file(new, file_id)
   364	    if "exercise_ids" in changes:
   365	        _check_exercise_ids(new, changes["exercise_ids"])
   366	    f.update(copy.deepcopy(changes))
   367	    return new
     1	"""API quản trị nội dung: quyền (INV-02), một đường ghi + version (INV-06), tiến độ sống sót (INV-04)."""
     2	
     3	from __future__ import annotations
     4	
     5	import copy
     6	
     7	import pytest
     8	
     9	from app.content_api import read_content
    10	from app.load_content import has_content, main as load_main
    11	from app.progress import record_pass
    12	from app.tables import UserProgress
    13	from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
    14	
    15	ADMIN = "phuongtt.tech1508@gmail.com"
    16	
    17	
    18	@pytest.fixture()
    19	def admin(loaded_session, client_for):
    20	    add_user(loaded_session, email=ADMIN, roles=("learner", "admin"))
    21	    client = client_for(loaded_session)
    22	    token = login(client, email=ADMIN).json()["token"]
    23	    return client, bearer(token)
    24	
    25	
    26	def _source(content_data: dict) -> dict:
    27	    return {k: v for k, v in content_data.items() if k != "version"}
    28	
    29	
    30	@pytest.mark.parametrize("roles", [None, ("learner",)])
    31	def test_admin_endpoints_need_admin_role(loaded_session, client_for, content_data, roles):
    32	    client = client_for(loaded_session)
    33	    headers = {}
    34	    if roles:
    35	        add_user(loaded_session, roles=roles)
    36	        headers = bearer(login(client).json()["token"])
    37	    expected = 403 if roles else 401
    38	    body = {"content": _source(content_data)}
    39	    assert client.get("/api/admin/content", headers=headers).status_code == expected
    40	    assert client.post("/api/admin/validate", json=body, headers=headers).status_code == expected
    41	    put = {"base_version": "x", **body}
    42	    assert client.put("/api/admin/content", json=put, headers=headers).status_code == expected
    43	
    44	
    45	def test_get_returns_full_content_with_judge(admin, content_data):
    46	    client, h = admin
    47	    r = client.get("/api/admin/content", headers=h)
    48	    assert r.status_code == 200
    49	    body = r.json()
    50	    assert body["version"].startswith("sha256:")
    51	    assert body["content"]["themes"] == content_data["themes"]
    52	    assert body["content"]["exercises"] == content_data["exercises"]  # CÓ judge
    53	
    54	
    55	def test_validate_reports_errors_without_writing(admin, content_data, loaded_session):
    56	    client, h = admin
    57	    ok = client.post("/api/admin/validate", json={"content": _source(content_data)}, headers=h).json()
    58	    assert ok == {"ok": True, "errors": []}
    59	    bad = copy.deepcopy(_source(content_data))
    60	    bad["exercises"]["split-chunks"]["judge"]["solution"] += "\n"
    61	    r = client.post("/api/admin/validate", json={"content": bad}, headers=h).json()
    62	    assert r["ok"] is False and any("judge.solution" in e for e in r["errors"])
    63	    assert read_content(loaded_session)["exercises"]["split-chunks"]["title"] == content_data["exercises"]["split-chunks"]["title"]
    64	
    65	
    66	def test_save_with_current_version_updates_content_and_version(admin, loaded_session):
    67	    client, h = admin
    68	    got = client.get("/api/admin/content", headers=h).json()
    69	    content = got["content"]
    70	    content["exercises"]["split-chunks"]["title"] = "Chia văn bản (đã sửa)"
    71	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
    72	    assert r.status_code == 200
    73	    new_version = r.json()["version"]
    74	    assert new_version != got["version"]
    75	    assert client.get("/api/admin/content", headers=h).json()["version"] == new_version
    76	    public = client.get("/content").json()
    77	    assert public["exercises"]["split-chunks"]["title"] == "Chia văn bản (đã sửa)"
    78	
    79	
    80	def test_stale_base_version_is_409_and_keeps_db(admin, loaded_session):
    81	    client, h = admin
    82	    got = client.get("/api/admin/content", headers=h).json()
    83	    first = copy.deepcopy(got["content"])
    84	    first["exercises"]["split-chunks"]["title"] = "Admin A"
    85	    assert client.put("/api/admin/content", json={"base_version": got["version"], "content": first}, headers=h).status_code == 200
    86	    second = copy.deepcopy(got["content"])
    87	    second["exercises"]["split-chunks"]["title"] = "Admin B"
    88	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": second}, headers=h)
    89	    assert r.status_code == 409 and r.json() == {"detail": "version_conflict"}
    90	    assert client.get("/content").json()["exercises"]["split-chunks"]["title"] == "Admin A"
    91	
    92	
    93	def test_judge_only_edit_changes_admin_version(admin):
    94	    """Sửa mỗi test case (không công khai) vẫn phải đổi version, để admin khác bị 409."""
    95	    client, h = admin
    96	    got = client.get("/api/admin/content", headers=h).json()
    97	    content = got["content"]
    98	    content["exercises"]["split-chunks"]["judge"]["cases"].append(copy.deepcopy(content["exercises"]["split-chunks"]["judge"]["cases"][0]))
    99	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
   100	    assert r.status_code == 200 and r.json()["version"] != got["version"]
   101	
   102	
   103	def test_invalid_save_is_422_with_errors_and_keeps_db(admin, content_data):
   104	    client, h = admin
   105	    got = client.get("/api/admin/content", headers=h).json()
   106	    content = got["content"]
   107	    content["exercises"]["split-chunks"]["blocks"][0]["hints"] = ["chỉ một"]
   108	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
   109	    assert r.status_code == 422
   110	    assert any("đúng 3 gợi ý" in e for e in r.json()["errors"])
   111	    assert client.get("/api/admin/content", headers=h).json()["version"] == got["version"]
   112	
   113	
   114	def test_admin_save_keeps_learner_progress(admin, loaded_session):
   115	    """INV-04: admin lưu = thay toàn bộ nội dung; tiến độ học viên không mất, kể cả bài bị xoá."""
   116	    client, h = admin
   117	    learner = add_user(loaded_session, email="test@gmail.com")
   118	    record_pass(loaded_session, learner.id, "split-chunks")
   119	    got = client.get("/api/admin/content", headers=h).json()
   120	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": got["content"]}, headers=h)
   121	    assert r.status_code == 200
   122	    assert loaded_session.get(UserProgress, (learner.id, "split-chunks")).passed is True
   123	
   124	
   125	def test_admin_body_limit_is_larger_than_learner_limit(admin, content_data):
   126	    """content.json lớn hơn 64KB: lọt qua middleware ở /api/admin nhưng không ở chỗ khác."""
   127	    import json
   128	
   129	    client, h = admin
   130	    raw = json.dumps({"content": _source(content_data)}).encode()
   131	    assert len(raw) > 64 * 1024
   132	    r = client.post("/api/admin/validate", content=raw, headers={**h, "Content-Type": "application/json"})
   133	    assert r.status_code == 200
   134	    r = client.post("/api/auth/login", content=raw, headers={"Content-Type": "application/json"})
   135	    assert r.status_code == 413
   136	
   137	
   138	def test_extra_keys_rejected(admin, content_data):
   139	    client, h = admin
   140	    r = client.post("/api/admin/validate", json={"content": _source(content_data), "x": 1}, headers=h)
   141	    assert r.status_code == 422
   142	
   143	
   144	def test_cli_requires_explicit_mode(capsys):
   145	    """DB là nguồn chính: CLI không còn mặc định ghi đè."""
   146	    assert load_main(["load_content"]) == 2
   147	    assert load_main(["load_content", "--yes"]) == 2
   148	    assert "--if-empty" in capsys.readouterr().err
   149	
   150	
   151	def test_has_content(loaded_session, db_session):
   152	    assert has_content(loaded_session) is True
   153	
   154	
   155	def test_unauthenticated_body_is_not_parsed(loaded_session, client_for):
   156	    """Khách chưa đăng nhập gửi body hỏng: 401 (không phải 422) — server không parse body trước kiểm quyền."""
   157	    client = client_for(loaded_session)
   158	    r = client.post("/api/admin/validate", content=b"{", headers={"Content-Type": "application/json"})
   159	    assert r.status_code == 401
   160	
   161	
   162	@pytest.mark.parametrize("body", [b"{", b'{"content": {}}', b'{"base_version": "x", "content": [], "x": 1}'])
   163	def test_every_admin_422_has_errors_list(admin, body):
   164	    client, h = admin
   165	    r = client.put("/api/admin/content", content=body, headers={**h, "Content-Type": "application/json"})
   166	    assert r.status_code == 422 and r.json()["errors"], r.json()
   167	
   168	
   169	def test_long_id_rejected_by_validate_and_by_save_with_errors(admin):
   170	    """validate và save cùng luật: id > 100 ký tự (cột String(100)) bị báo ở cả hai, có `errors`."""
   171	    client, h = admin
   172	    got = client.get("/api/admin/content", headers=h).json()
   173	    content = got["content"]
   174	    content["themes"][0]["id"] = "y" * 150
   175	    v = client.post("/api/admin/validate", json={"content": content}, headers=h).json()
   176	    assert v["ok"] is False and any("dài quá 100" in e for e in v["errors"])
   177	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
   178	    assert r.status_code == 422 and any("dài quá 100" in e for e in r.json()["errors"])
   179	
   180	
   181	def test_deleting_exercise_with_progress_keeps_progress_and_state(admin, loaded_session):
   182	    """INV-04: admin xoá hẳn một bài học viên đã làm → dòng tiến độ + lịch ôn vẫn còn (ẩn ở GET)."""
   183	    from app.tables import UserState
   184	
   185	    client, h = admin
   186	    learner = add_user(loaded_session, email="test@gmail.com")
   187	    record_pass(loaded_session, learner.id, "split-chunks")
   188	    loaded_session.add(UserState(user_id=learner.id, review={"split-chunks-a": {"reps": 1}}, activity={"2026-10-11": 1}))
   189	    loaded_session.flush()
   190	    got = client.get("/api/admin/content", headers=h).json()
   191	    content = got["content"]
   192	    for th in content["themes"]:
   193	        stack = list(th["topics"])
   194	        while stack:
   195	            tp = stack.pop()
   196	            stack.extend(tp["modules"])
   197	            for f in tp["files"]:
   198	                f["exercise_ids"] = [i for i in f["exercise_ids"] if i != "split-chunks"]
   199	    del content["exercises"]["split-chunks"]
   200	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
   201	    assert r.status_code == 200, r.json()
   202	    assert "split-chunks" not in client.get("/content").json()["exercises"]
   203	    assert loaded_session.get(UserProgress, (learner.id, "split-chunks")).passed is True
   204	    assert loaded_session.get(UserState, learner.id).activity == {"2026-10-11": 1}
   205	
   206	
   207	def test_version_check_runs_while_holding_the_write_lock(admin, monkeypatch):
   208	    """Kiểm version và ghi phải nằm trong cùng khoá ghi (không thì hai admin đua nhau ghi đè).
   209	
   210	    Đo thứ tự gọi, không đo pg_locks: fixture đã nạp nội dung trong cùng transaction test nên khoá
   211	    xact luôn đang được giữ — đo pg_locks thì bỏ lock_content khỏi admin_api test vẫn xanh."""
   212	    from app import admin_api
   213	
   214	    client, h = admin
   215	    got = client.get("/api/admin/content", headers=h).json()
   216	    calls: list[str] = []
   217	    real_lock, real_export = admin_api.lock_content, admin_api.export_content
   218	
   219	    def lock(session):
   220	        calls.append("lock")
   221	        real_lock(session)
   222	
   223	    def export(session):
   224	        calls.append("export")
   225	        return real_export(session)
   226	
   227	    monkeypatch.setattr(admin_api, "lock_content", lock)
   228	    monkeypatch.setattr(admin_api, "export_content", export)
   229	    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": got["content"]}, headers=h)
   230	    assert r.status_code == 200
   231	    assert calls[:2] == ["lock", "export"]
   232	
   233	
   234	def test_deeply_nested_json_body_is_422_not_500(admin):
   235	    client, h = admin
   236	    r = client.post("/api/admin/validate", content=b"[" * 300000, headers={**h, "Content-Type": "application/json"})
   237	    assert r.status_code == 422 and r.json()["errors"]

exec
/bin/zsh -lc "nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/lowlevel/server.py | sed -n '720,875p'; rg -n \"lifespan|on_event\\(|add_event_handler\" backend/app backend/tests | sed -n '1,240p'; git show 12f9085"'^:backend/app/main.py | nl -ba | sed -n '"'35,90p'; rg -n \"client_for\" backend/tests/conftest.py backend/tests/test_auth.py | sed -n '1,160p'; sed -n '1,220p' backend/tests/conftest.py" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
   720	        call `serve_loop` directly instead.
   721	        """
   722	        async with self.lifespan(self) as lifespan_context:
   723	            await serve_dual_era_loop(
   724	                self,
   725	                read_stream,
   726	                write_stream,
   727	                lifespan_state=lifespan_context,
   728	                init_options=initialization_options,
   729	                raise_exceptions=raise_exceptions,
   730	            )
   731	
   732	    def streamable_http_app(
   733	        self,
   734	        *,
   735	        streamable_http_path: str = "/mcp",
   736	        json_response: bool = False,
   737	        stateless_http: bool = False,
   738	        event_store: EventStore | None = None,
   739	        retry_interval: int | None = None,
   740	        max_request_body_size: int = DEFAULT_MAX_REQUEST_BODY_SIZE,
   741	        session_idle_timeout: float | None = DEFAULT_SESSION_IDLE_TIMEOUT,
   742	        max_sessions: int | None = DEFAULT_MAX_SESSIONS,
   743	        transport_security: TransportSecuritySettings | None = None,
   744	        host: str = "127.0.0.1",
   745	        auth: AuthSettings | None = None,
   746	        token_verifier: TokenVerifier | None = None,
   747	        auth_server_provider: OAuthAuthorizationServerProvider[Any, Any, Any] | None = None,
   748	        custom_starlette_routes: list[Route] | None = None,
   749	        debug: bool = False,
   750	    ) -> Starlette:
   751	        """Return an instance of the StreamableHTTP server app."""
   752	        # Auto-enable DNS rebinding protection for localhost (IPv4 and IPv6)
   753	        if transport_security is None and host in ("127.0.0.1", "localhost", "::1"):
   754	            transport_security = TransportSecuritySettings(
   755	                enable_dns_rebinding_protection=True,
   756	                allowed_hosts=["127.0.0.1:*", "localhost:*", "[::1]:*"],
   757	                allowed_origins=["http://127.0.0.1:*", "http://localhost:*", "http://[::1]:*"],
   758	            )
   759	
   760	        session_manager = StreamableHTTPSessionManager(
   761	            app=self,
   762	            event_store=event_store,
   763	            retry_interval=retry_interval,
   764	            json_response=json_response,
   765	            stateless=stateless_http,
   766	            security_settings=transport_security,
   767	            max_request_body_size=max_request_body_size,
   768	            session_idle_timeout=session_idle_timeout,
   769	            max_sessions=max_sessions,
   770	        )
   771	        self._session_manager = session_manager
   772	
   773	        # Create the ASGI handler
   774	        streamable_http_app = StreamableHTTPASGIApp(session_manager)
   775	
   776	        # Create routes
   777	        routes: list[Route | Mount] = []
   778	        middleware: list[Middleware] = []
   779	        required_scopes: list[str] = []
   780	
   781	        # Set up auth if configured
   782	        if auth:
   783	            required_scopes = auth.required_scopes or []
   784	
   785	            # Add auth middleware if token verifier is available
   786	            if token_verifier:
   787	                middleware = [
   788	                    Middleware(
   789	                        AuthenticationMiddleware,
   790	                        backend=BearerAuthBackend(
   791	                            token_verifier,
   792	                            resource_server_url=auth.resource_server_url if auth.validate_token_resource else None,
   793	                        ),
   794	                    ),
   795	                    Middleware(AuthContextMiddleware),
   796	                ]
   797	
   798	            # Add auth endpoints if auth server provider is configured
   799	            if auth_server_provider:
   800	                routes.extend(
   801	                    create_auth_routes(
   802	                        provider=auth_server_provider,
   803	                        issuer_url=auth.issuer_url,
   804	                        service_documentation_url=auth.service_documentation_url,
   805	                        client_registration_options=auth.client_registration_options,
   806	                        revocation_options=auth.revocation_options,
   807	                        identity_assertion_enabled=auth.identity_assertion_enabled,
   808	                    )
   809	                )
   810	
   811	        # Set up routes with or without auth
   812	        if token_verifier:
   813	            # Determine resource metadata URL
   814	            resource_metadata_url = None
   815	            if auth and auth.resource_server_url:  # pragma: no branch
   816	                # Build compliant metadata URL for WWW-Authenticate header
   817	                resource_metadata_url = build_resource_metadata_url(auth.resource_server_url)
   818	
   819	            routes.append(
   820	                Route(
   821	                    streamable_http_path,
   822	                    endpoint=RequireAuthMiddleware(streamable_http_app, required_scopes, resource_metadata_url),
   823	                )
   824	            )
   825	        else:
   826	            # Auth is disabled, no wrapper needed
   827	            routes.append(
   828	                Route(
   829	                    streamable_http_path,
   830	                    endpoint=streamable_http_app,
   831	                )
   832	            )
   833	
   834	        # Add protected resource metadata endpoint if configured as RS
   835	        if auth and auth.resource_server_url:
   836	            routes.extend(
   837	                create_protected_resource_routes(
   838	                    resource_url=auth.resource_server_url,
   839	                    authorization_servers=[auth.issuer_url],
   840	                    scopes_supported=auth.required_scopes,
   841	                )
   842	            )
   843	
   844	        if custom_starlette_routes:
   845	            routes.extend(custom_starlette_routes)
   846	
   847	        return Starlette(
   848	            debug=debug,
   849	            routes=routes,
   850	            middleware=middleware,
   851	            lifespan=lambda app: session_manager.run(),
   852	        )
backend/tests/test_mcp.py:1:"""`/mcp` qua HTTP thật (TestClient + lifespan): cổng 401 trước SDK (INV-05), không rơi về chế độ mở hay
backend/tests/test_mcp.py:41:    """Client đã chạy lifespan; tool dùng session test (rollback sau test)."""
backend/app/mcp_server.py:278:async def lifespan() -> AsyncIterator[None]:
backend/app/main.py:54:async def lifespan(app: FastAPI):
backend/app/main.py:55:    async with mcp_server.lifespan():
backend/app/main.py:59:app = FastAPI(title="Smart Coding Study", lifespan=lifespan)
    35	
    36	APP_DIR = Path(__file__).parent
    37	HARNESS_SOURCE = (APP_DIR / "harness.py").read_text(encoding="utf-8")
    38	MAX_CODE_CHARS = 8000
    39	# 8000 ký tự UTF-8 tối đa ~32KB, cộng JSON escape: 64KB là đủ rộng cho request hợp lệ.
    40	MAX_BODY_BYTES = 64 * 1024
    41	# Admin gửi cả bộ nội dung (content.json ~vài trăm KB) khi kiểm tra/lưu.
    42	MAX_ADMIN_BODY_BYTES = 4 * 1024 * 1024
    43	# Máy chấm công khai giới hạn theo IP: không bắn quá 4 bài cùng lúc từ một backend.
    44	_RUN_SLOTS = asyncio.Semaphore(4)
    45	# Tạo lúc import: CODE_RUNNER sai thì server không khởi động được, thay vì 500 ở request đầu.
    46	_RUNNER = runner_from_env()
    47	
    48	app = FastAPI(title="Smart Coding Study")
    49	app.include_router(content_router)
    50	app.include_router(auth_router)
    51	app.include_router(progress_router)
    52	app.include_router(admin_router)
    53	
    54	
    55	def _body_limit(path: str) -> int:
    56	    return MAX_ADMIN_BODY_BYTES if path.startswith("/api/admin/") else MAX_BODY_BYTES
    57	
    58	
    59	@app.middleware("http")
    60	async def _limit_body(request: Request, call_next):
    61	    # Field(max_length) chỉ kiểm SAU khi đọc hết body; chặn body lớn trước khi đọc.
    62	    if request.method not in ("GET", "HEAD", "OPTIONS"):
    63	        length = request.headers.get("content-length")
    64	        if length is None and "transfer-encoding" not in request.headers:
    65	            return await call_next(request)  # không có body (vd POST /api/auth/logout từ curl)
    66	        if length is None or not length.isdigit():
    67	            return JSONResponse(status_code=411, content={"detail": "length_required"})
    68	        if int(length) > _body_limit(request.url.path):
    69	            return JSONResponse(status_code=413, content={"detail": "body_too_large"})
    70	    return await call_next(request)
    71	
    72	
    73	class RunRequest(BaseModel):
    74	    exercise_id: str = Field(min_length=1, max_length=100)
    75	    code: str = Field(min_length=1, max_length=MAX_CODE_CHARS)
    76	
    77	
    78	@app.exception_handler(RequestValidationError)
    79	async def _invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
    80	    # Handler mặc định trả lại nguyên `input`: vừa lặp lại code học viên, vừa nổ 500 khi input
    81	    # chứa surrogate lẻ ("\ud800" là JSON hợp lệ nhưng không mã hoá UTF-8 được).
    82	    fields = sorted({".".join(str(part) for part in error["loc"][1:]) for error in exc.errors()})
    83	    return JSONResponse(status_code=422, content={"detail": "invalid_request", "fields": fields})
    84	
    85	
    86	@app.exception_handler(OperationalError)
    87	async def _database_unavailable(request: Request, exc: OperationalError) -> JSONResponse:
    88	    # DB chết / không kết nối được: 503 có nghĩa thay vì 500, không lộ chi tiết kết nối.
    89	    logger.warning("database unavailable on %s: %s", request.url.path, type(exc.orig).__name__)
    90	    return JSONResponse(status_code=503, content={"detail": "database_unavailable"})
backend/tests/test_auth.py:41:def client_for():
backend/tests/test_auth.py:69:def test_password_stored_hashed_and_token_stored_as_digest(db_session, client_for):
backend/tests/test_auth.py:72:    r = login(client_for(db_session))
backend/tests/test_auth.py:79:def test_login_ok_returns_token_and_roles_email_case_insensitive(db_session, client_for):
backend/tests/test_auth.py:81:    r = login(client_for(db_session), email="  PhuongTT.Tech1508@Gmail.com ")
backend/tests/test_auth.py:87:def test_login_wrong_password_or_unknown_email_same_401(db_session, client_for, email, password):
backend/tests/test_auth.py:89:    r = login(client_for(db_session), email=email, password=password)
backend/tests/test_auth.py:93:def test_login_throttled_after_5_failures_even_with_right_password(db_session, client_for):
backend/tests/test_auth.py:95:    client = client_for(db_session)
backend/tests/test_auth.py:102:def test_me_requires_valid_token(db_session, client_for):
backend/tests/test_auth.py:104:    client = client_for(db_session)
backend/tests/test_auth.py:112:def test_expired_session_is_401(db_session, client_for):
backend/tests/test_auth.py:114:    client = client_for(db_session)
backend/tests/test_auth.py:122:def test_logout_revokes_only_that_token(db_session, client_for):
backend/tests/test_auth.py:124:    client = client_for(db_session)
backend/tests/test_auth.py:132:def test_change_password_rules_and_revokes_other_sessions(db_session, client_for):
backend/tests/test_auth.py:134:    client = client_for(db_session)
backend/tests/test_auth.py:177:def test_run_records_passed_only_for_logged_in_user_and_only_when_passed(loaded_session, content_data, client_for):
backend/tests/test_auth.py:179:    client = client_for(loaded_session)
backend/tests/test_auth.py:241:def test_successful_login_does_not_use_up_ip_budget(db_session, client_for):
backend/tests/test_auth.py:243:    client = client_for(db_session)
backend/tests/test_auth.py:248:def test_ip_capped_across_many_emails(db_session, client_for):
backend/tests/test_auth.py:250:    client = client_for(db_session)
backend/tests/test_auth.py:257:def test_change_password_wrong_guesses_are_throttled(db_session, client_for):
backend/tests/test_auth.py:259:    client = client_for(db_session)
backend/tests/test_auth.py:269:def test_run_still_returns_result_when_recording_pass_fails(loaded_session, content_data, client_for):
backend/tests/test_auth.py:271:    client = client_for(loaded_session)
backend/tests/test_auth.py:283:def test_logout_without_body_or_content_length_is_not_411(db_session, client_for):
backend/tests/test_auth.py:285:    client = client_for(db_session)
backend/tests/test_auth.py:310:def test_unstorable_input_is_422_not_500(db_session, client_for):
backend/tests/test_auth.py:312:    r = login(client_for(db_session), email="a\u0000b@gmail.com")
"""Fixture DB cho test: Postgres thật, DB riêng `smart_coding_study_test` (tự tạo nếu chưa có).

Đặt `TEST_DATABASE_URL` để dùng server khác. Mỗi phiên test chạy lại migration từ đầu
(downgrade base → upgrade head), nên schema test luôn đúng bản migration hiện tại.
"""

from __future__ import annotations

import json
import os
import re
from collections.abc import Iterator

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session, sessionmaker

from app.db import database_url
from app.load_content import load_content

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL", "postgresql+psycopg://localhost:5432/smart_coding_study_test"
)


def _guard_test_database(url: str) -> None:
    """Fixture DROP toàn bộ bảng: chỉ cho chạy trên DB tên `*_test`, khác DATABASE_URL của app."""
    name = make_url(url).database or ""
    if not re.fullmatch(r"[a-z0-9_]+_test", name):
        raise RuntimeError(f"TEST_DATABASE_URL phải trỏ DB tên dạng '<tên>_test', đang là {name!r}")
    if make_url(url) == make_url(database_url()):
        raise RuntimeError("TEST_DATABASE_URL trùng DATABASE_URL — từ chối chạy test phá dữ liệu")


def _ensure_database(url: str) -> None:
    target = make_url(url)
    admin = create_engine(target.set(database="postgres"), isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        exists = conn.execute(text("select 1 from pg_database where datname = :n"), {"n": target.database}).scalar()
        if not exists:
            conn.execute(text(f'create database "{target.database}"'))
    admin.dispose()


def alembic_config(url: str) -> Config:
    config = Config(os.path.join(BACKEND_DIR, "alembic.ini"))
    config.set_main_option("script_location", os.path.join(BACKEND_DIR, "migrations"))
    config.set_main_option("sqlalchemy.url", url)
    return config


@pytest.fixture(scope="session")
def db_engine() -> Iterator[Engine]:
    _guard_test_database(TEST_DATABASE_URL)
    _ensure_database(TEST_DATABASE_URL)
    config = alembic_config(TEST_DATABASE_URL)
    command.downgrade(config, "base")
    command.upgrade(config, "head")
    engine = create_engine(TEST_DATABASE_URL)
    yield engine
    engine.dispose()


@pytest.fixture()
def db_session(db_engine: Engine) -> Iterator[Session]:
    """Session trong một transaction, rollback sau mỗi test (test không để lại dữ liệu)."""
    connection = db_engine.connect()
    transaction = connection.begin()
    session = sessionmaker(bind=connection, join_transaction_mode="create_savepoint")()
    yield session
    session.close()
    transaction.rollback()
    connection.close()


CONTENT_PATH = os.path.join(BACKEND_DIR, "content", "content.json")


@pytest.fixture(scope="session")
def content_data() -> dict:
    """Nội dung thật trong repo (nguồn soạn), dùng chung cho mọi test."""
    with open(CONTENT_PATH, encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture()
def loaded_session(db_session: Session, content_data: dict) -> Session:
    """`db_session` đã nạp content.json (rollback sau test như db_session)."""
    load_content(db_session, content_data)
    db_session.flush()
    return db_session

exec
/bin/zsh -lc "nl -ba backend/tests/test_auth.py | sed -n '1,72p'; backend/.venv/bin/python - <<'PY'
import mcp, importlib.metadata
print(importlib.metadata.version('mcp'))
PY
cd backend && .venv/bin/pytest -q tests/test_mcp.py" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 exited 4 in 453ms:
2.3.0
ImportError while loading conftest '/Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content/backend/tests/conftest.py'.
tests/conftest.py:21: in <module>
    from app.db import database_url
E   ModuleNotFoundError: No module named 'app'

codex
Code SDK 2.3.0 đã xác nhận claims được snapshot ở lúc transport nhận message, khôi phục vào task xử lý riêng, rồi AnyIO copy tiếp sang worker thread; vì vậy cơ chế ContextVar hiện tại không có leakage/rơi claims theo luồng đó. Mình đang chuyển sang các race transaction thật và các test “xanh giả”.
exec
/bin/zsh -lc 'PYTHONPATH=. .venv/bin/python -m pytest -q tests/test_mcp.py' in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content/backend
 exited 1 in 2881ms:
EEEEEEEEEEEEEEEEEEEE                                                     [100%]
==================================== ERRORS ====================================
________ ERROR at setup of test_no_token_is_401_with_resource_metadata _________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
______ ERROR at setup of test_token_for_other_resource_is_401[overrides0] ______

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
______ ERROR at setup of test_token_for_other_resource_is_401[overrides1] ______

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
______ ERROR at setup of test_token_for_other_resource_is_401[overrides2] ______

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
____ ERROR at setup of test_open_mode_and_app_session_token_do_not_open_mcp ____

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
________________ ERROR at setup of test_get_and_delete_are_405 _________________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
_________________ ERROR at setup of test_not_configured_is_503 _________________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
_____________ ERROR at setup of test_identity_down_is_503_not_401 ______________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
____________________ ERROR at setup of test_prm_on_main_app ____________________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
_______________ ERROR at setup of test_initialize_and_list_tools _______________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
____________ ERROR at setup of test_tools_refuse_sub_without_grant _____________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
____________ ERROR at setup of test_open_mode_does_not_grant_tools _____________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
______________________ ERROR at setup of test_read_tools _______________________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
________________ ERROR at setup of test_dry_run_does_not_write _________________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
_ ERROR at setup of test_create_lesson_shows_in_content_and_stale_admin_gets_409 _

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
___ ERROR at setup of test_invalid_lesson_is_tool_error_and_nothing_written ____

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
____________ ERROR at setup of test_content_op_error_is_tool_error _____________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
___________ ERROR at setup of test_create_project_module_file_chain ____________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
___________ ERROR at setup of test_revoke_takes_effect_on_next_call ____________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
________________ ERROR at setup of test_admin_demoted_loses_mcp ________________

self = <sqlalchemy.engine.base.Connection object at 0x10c5442f0>
engine = Engine(postgresql+psycopg://localhost:5432/postgres), connection = None
_has_events = None, _allow_revalidate = True, _allow_autobegin = True

    def __init__(
        self,
        engine: Engine,
        connection: Optional[PoolProxiedConnection] = None,
        _has_events: Optional[bool] = None,
        _allow_revalidate: bool = True,
        _allow_autobegin: bool = True,
    ):
        """Construct a new Connection."""
        self.engine = engine
        self.dialect = dialect = engine.dialect
    
        if connection is None:
            try:
>               self._dbapi_connection = engine.raw_connection()
                                         ^^^^^^^^^^^^^^^^^^^^^^^

.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           psycopg.OperationalError: connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError

The above exception was the direct cause of the following exception:

    @pytest.fixture(scope="session")
    def db_engine() -> Iterator[Engine]:
        _guard_test_database(TEST_DATABASE_URL)
>       _ensure_database(TEST_DATABASE_URL)

tests/conftest.py:59: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
tests/conftest.py:42: in _ensure_database
    with admin.connect() as conn:
         ^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3263: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:151: in __init__
    Connection._handle_dbapi_exception_noconnection(
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:2420: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:149: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/base.py:3287: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:445: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:1303: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:709: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:176: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/impl.py:174: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:386: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:671: in __init__
    self.__connect()
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:906: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/util/langhelpers.py:166: in __exit__
    raise exc_value.with_traceback(exc_tb)
.venv/lib/python3.14/site-packages/sqlalchemy/pool/base.py:902: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/create.py:645: in connect
    return dialect.connect(*cargs_tup, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
.venv/lib/python3.14/site-packages/sqlalchemy/engine/default.py:869: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

cls = <class 'psycopg.Connection'>
conninfo = 'host=localhost dbname=postgres port=5432 hostaddr=127.0.0.1'
autocommit = False, prepare_threshold = 5
context = <psycopg.adapt.AdaptersMap object at 0x10c532210>, row_factory = None
cursor_factory = None
kwargs = {'host': 'localhost', 'dbname': 'postgres', 'port': 5432}

    @classmethod
    def connect(
        cls,
        conninfo: str = "",
        *,
        autocommit: bool = False,
        prepare_threshold: int | None = 5,
        context: AdaptContext | None = None,
        row_factory: RowFactory[Row] | None = None,
        cursor_factory: type[Cursor[Row]] | None = None,
        **kwargs: ConnParam,
    ) -> Self:
        """
        Connect to a database server and return a new `Connection` instance.
        """
    
        params = cls._get_connection_params(conninfo, **kwargs)
        timeout = timeout_from_conninfo(params)
        rv = None
        attempts = conninfo_attempts(params)
        conn_errors: list[tuple[e.Error, str]] = []
        for attempt in attempts:
            tdescr = (attempt.get("host"), attempt.get("port"), attempt.get("hostaddr"))
            descr = "host: %r, port: %r, hostaddr: %r" % tdescr
            logger.debug("connection attempt: %s", descr)
            try:
                conninfo = make_conninfo("", **attempt)
                gen = cls._connect_gen(conninfo)
                rv = waiting.wait_conn(gen, interval=_WAIT_INTERVAL, timeout=timeout)
            except e._WaitTimeout:
                tex = e.ConnectionTimeout("connection timeout expired")
                logger.debug("connection failed: %s: %s", descr, str(tex))
                conn_errors.append((tex, descr))
            except e.Error as ex:
                logger.debug("connection failed: %s: %s", descr, str(ex))
                conn_errors.append((ex, descr))
            except e._NO_TRACEBACK as ex:
                raise ex.with_traceback(None)
            else:
                logger.debug("connection succeeded: %s", descr)
                break
    
        if not rv:
            last_ex = conn_errors[-1][0]
            if len(conn_errors) == 1:
                raise last_ex.with_traceback(None)
    
            # Create a new exception with the same type as the last one, containing
            # all attempt errors while preserving backward compatibility.
            lines = [str(last_ex)]
            lines.append("Multiple connection attempts failed. All failures were:")
            lines.extend((f"- {descr}: {error}" for error, descr in conn_errors))
            new_ex = type(last_ex)("\n".join(lines), pgconn=last_ex.pgconn)
>           raise new_ex.with_traceback(None)
E           sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           Multiple connection attempts failed. All failures were:
E           - host: 'localhost', port: 5432, hostaddr: '::1': connection is bad: connection to server at "::1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           - host: 'localhost', port: 5432, hostaddr: '127.0.0.1': connection is bad: connection to server at "127.0.0.1", port 5432 failed: Operation not permitted
E           	Is the server running on that host and accepting TCP/IP connections?
E           (Background on this error at: https://sqlalche.me/e/21/e3q8)

.venv/lib/python3.14/site-packages/psycopg/connection.py:134: OperationalError
=========================== short test summary info ============================
ERROR tests/test_mcp.py::test_no_token_is_401_with_resource_metadata - sqlalc...
ERROR tests/test_mcp.py::test_token_for_other_resource_is_401[overrides0] - s...
ERROR tests/test_mcp.py::test_token_for_other_resource_is_401[overrides1] - s...
ERROR tests/test_mcp.py::test_token_for_other_resource_is_401[overrides2] - s...
ERROR tests/test_mcp.py::test_open_mode_and_app_session_token_do_not_open_mcp
ERROR tests/test_mcp.py::test_get_and_delete_are_405 - sqlalchemy.exc.Operati...
ERROR tests/test_mcp.py::test_not_configured_is_503 - sqlalchemy.exc.Operatio...
ERROR tests/test_mcp.py::test_identity_down_is_503_not_401 - sqlalchemy.exc.O...
ERROR tests/test_mcp.py::test_prm_on_main_app - sqlalchemy.exc.OperationalErr...
ERROR tests/test_mcp.py::test_initialize_and_list_tools - sqlalchemy.exc.Oper...
ERROR tests/test_mcp.py::test_tools_refuse_sub_without_grant - sqlalchemy.exc...
ERROR tests/test_mcp.py::test_open_mode_does_not_grant_tools - sqlalchemy.exc...
ERROR tests/test_mcp.py::test_read_tools - sqlalchemy.exc.OperationalError: (...
ERROR tests/test_mcp.py::test_dry_run_does_not_write - sqlalchemy.exc.Operati...
ERROR tests/test_mcp.py::test_create_lesson_shows_in_content_and_stale_admin_gets_409
ERROR tests/test_mcp.py::test_invalid_lesson_is_tool_error_and_nothing_written
ERROR tests/test_mcp.py::test_content_op_error_is_tool_error - sqlalchemy.exc...
ERROR tests/test_mcp.py::test_create_project_module_file_chain - sqlalchemy.e...
ERROR tests/test_mcp.py::test_revoke_takes_effect_on_next_call - sqlalchemy.e...
ERROR tests/test_mcp.py::test_admin_demoted_loses_mcp - sqlalchemy.exc.Operat...
20 errors in 2.57s

exec
/bin/zsh -lc "nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/tool_manager.py | sed -n '1,300p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py | sed -n '650,900p'; rg -uu -n \"ToolError|is_error|isError|CallToolResult\" backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver | sed -n '1,240p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
     1	from __future__ import annotations
     2	
     3	from collections.abc import Callable
     4	from typing import TYPE_CHECKING, Any
     5	
     6	from mcp_types import Icon, ToolAnnotations
     7	
     8	from mcp.server.mcpserver.exceptions import ToolError
     9	from mcp.server.mcpserver.tools.base import Tool
    10	from mcp.server.mcpserver.utilities.logging import get_logger
    11	
    12	if TYPE_CHECKING:
    13	    from mcp.server.context import LifespanContextT, RequestT
    14	    from mcp.server.mcpserver.context import Context
    15	
    16	logger = get_logger(__name__)
    17	
    18	
    19	class ToolManager:
    20	    """Manages MCPServer tools."""
    21	
    22	    def __init__(self, warn_on_duplicate_tools: bool = True, *, tools: list[Tool] | None = None):
    23	        self._tools: dict[str, Tool] = {}
    24	        for tool in tools or ():
    25	            if warn_on_duplicate_tools and tool.name in self._tools:
    26	                logger.warning(f"Tool already exists: {tool.name}")
    27	            self._tools[tool.name] = tool
    28	
    29	        self.warn_on_duplicate_tools = warn_on_duplicate_tools
    30	
    31	    def get_tool(self, name: str) -> Tool | None:
    32	        """Get tool by name."""
    33	        return self._tools.get(name)
    34	
    35	    def list_tools(self) -> list[Tool]:
    36	        """List all registered tools."""
    37	        return list(self._tools.values())
    38	
    39	    def add_tool(
    40	        self,
    41	        fn: Callable[..., Any],
    42	        name: str | None = None,
    43	        title: str | None = None,
    44	        description: str | None = None,
    45	        annotations: ToolAnnotations | None = None,
    46	        icons: list[Icon] | None = None,
    47	        meta: dict[str, Any] | None = None,
    48	        structured_output: bool | None = None,
    49	    ) -> Tool:
    50	        """Add a tool to the server."""
    51	        tool = Tool.from_function(
    52	            fn,
    53	            name=name,
    54	            title=title,
    55	            description=description,
    56	            annotations=annotations,
    57	            icons=icons,
    58	            meta=meta,
    59	            structured_output=structured_output,
    60	        )
    61	        existing = self._tools.get(tool.name)
    62	        if existing:
    63	            if self.warn_on_duplicate_tools:
    64	                logger.warning(f"Tool already exists: {tool.name}")
    65	            return existing
    66	        self._tools[tool.name] = tool
    67	        return tool
    68	
    69	    def remove_tool(self, name: str) -> None:
    70	        """Remove a tool by name."""
    71	        if name not in self._tools:
    72	            raise ToolError(f"Unknown tool: {name}")
    73	        del self._tools[name]
    74	
    75	    async def call_tool(
    76	        self,
    77	        name: str,
    78	        arguments: dict[str, Any],
    79	        context: Context[LifespanContextT, RequestT],
    80	        convert_result: bool = False,
    81	    ) -> Any:
    82	        """Call a tool by name with arguments."""
    83	        tool = self.get_tool(name)
    84	        if not tool:
    85	            raise ToolError(f"Unknown tool: {name}")
    86	
    87	        return await tool.run(arguments, context, convert_result=convert_result)
   650	            title=title,
   651	            description=description,
   652	            annotations=annotations,
   653	            icons=icons,
   654	            meta=meta,
   655	            structured_output=structured_output,
   656	        )
   657	
   658	    def remove_tool(self, name: str) -> None:
   659	        """Remove a tool from the server by name.
   660	
   661	        Args:
   662	            name: The name of the tool to remove
   663	
   664	        Raises:
   665	            ToolError: If the tool does not exist
   666	        """
   667	        self._tool_manager.remove_tool(name)
   668	
   669	    def tool(
   670	        self,
   671	        name: str | None = None,
   672	        title: str | None = None,
   673	        description: str | None = None,
   674	        annotations: ToolAnnotations | None = None,
   675	        icons: list[Icon] | None = None,
   676	        meta: dict[str, Any] | None = None,
   677	        structured_output: bool | None = None,
   678	    ) -> Callable[[_CallableT], _CallableT]:
   679	        """Decorator to register a tool.
   680	
   681	        Tools can optionally request a Context object by adding a parameter with the
   682	        Context type annotation. The context provides access to MCP capabilities like
   683	        logging, progress reporting, and resource access.
   684	
   685	        Args:
   686	            name: Optional name for the tool (defaults to function name)
   687	            title: Optional human-readable title for the tool
   688	            description: Optional description of what the tool does
   689	            annotations: Optional ToolAnnotations providing additional tool information
   690	            icons: Optional list of icons for the tool
   691	            meta: Optional metadata dictionary for the tool
   692	            structured_output: Controls whether the tool's output is structured or unstructured
   693	                - If None, auto-detects based on the function's return type annotation
   694	                - If True, creates a structured tool (return type annotation permitting)
   695	                - If False, unconditionally creates an unstructured tool
   696	
   697	        Example:
   698	            ```python
   699	            @server.tool()
   700	            def my_tool(x: int) -> str:
   701	                return str(x)
   702	            ```
   703	
   704	            ```python
   705	            @server.tool()
   706	            async def tool_with_context(x: int, ctx: Context) -> str:
   707	                await ctx.info(f"Processing {x}")
   708	                return str(x)
   709	            ```
   710	
   711	            ```python
   712	            @server.tool()
   713	            async def async_tool(x: int, context: Context) -> str:
   714	                await context.report_progress(50, 100)
   715	                return str(x)
   716	            ```
   717	        """
   718	        # Check if user passed function directly instead of calling decorator
   719	        if callable(name):
   720	            raise TypeError(
   721	                "The @tool decorator was used incorrectly. Did you forget to call it? Use @tool() instead of @tool"
   722	            )
   723	
   724	        def decorator(fn: _CallableT) -> _CallableT:
   725	            self.add_tool(
   726	                fn,
   727	                name=name,
   728	                title=title,
   729	                description=description,
   730	                annotations=annotations,
   731	                icons=icons,
   732	                meta=meta,
   733	                structured_output=structured_output,
   734	            )
   735	            return fn
   736	
   737	        return decorator
   738	
   739	    def completion(self):
   740	        """Decorator to register a completion handler.
   741	
   742	        The completion handler receives:
   743	        - ref: PromptReference or ResourceTemplateReference
   744	        - argument: CompletionArgument with name and partial value
   745	        - context: Optional CompletionContext with previously resolved arguments
   746	
   747	        Example:
   748	            ```python
   749	            @mcp.completion()
   750	            async def handle_completion(ref, argument, context):
   751	                if isinstance(ref, ResourceTemplateReference):
   752	                    # Return completions based on ref, argument, and context
   753	                    return Completion(values=["option1", "option2"])
   754	                return None
   755	            ```
   756	        """
   757	
   758	        def decorator(func: _CallableT) -> _CallableT:
   759	            async def handler(
   760	                ctx: ServerRequestContext[LifespanResultT], params: CompleteRequestParams
   761	            ) -> CompleteResult:
   762	                try:
   763	                    result = await func(params.ref, params.argument, params.context)
   764	                    return CompleteResult(
   765	                        completion=result if result is not None else Completion(values=[], total=None, has_more=None),
   766	                    )
   767	                except MCPError:
   768	                    raise
   769	                except Exception as exc:
   770	                    logger.exception("Completion for argument %r raised an unexpected exception", params.argument.name)
   771	                    raise MCPError(
   772	                        code=INTERNAL_ERROR, message=f"Error completing argument {params.argument.name}"
   773	                    ) from exc
   774	
   775	            self._lowlevel_server.add_request_handler("completion/complete", CompleteRequestParams, handler)
   776	            return func
   777	
   778	        return decorator
   779	
   780	    def add_resource(self, resource: Resource) -> None:
   781	        """Add a resource to the server.
   782	
   783	        Args:
   784	            resource: A Resource instance to add
   785	        """
   786	        self._resource_manager.add_resource(resource)
   787	
   788	    def resource(
   789	        self,
   790	        uri: str,
   791	        *,
   792	        name: str | None = None,
   793	        title: str | None = None,
   794	        description: str | None = None,
   795	        mime_type: str | None = None,
   796	        icons: list[Icon] | None = None,
   797	        annotations: Annotations | None = None,
   798	        meta: dict[str, Any] | None = None,
   799	        security: ResourceSecurity | None = None,
   800	    ) -> Callable[[_CallableT], _CallableT]:
   801	        """Decorator to register a function as a resource.
   802	
   803	        The function will be called when the resource is read to generate its content.
   804	        The function can return:
   805	        - str for text content
   806	        - bytes for binary content
   807	        - an InputRequiredResult (template resources only; passed through
   808	          unchanged for the 2026-07-28 multi-round-trip flow — read
   809	          `ctx.input_responses` on the retry)
   810	        - other types will be converted to JSON
   811	
   812	        If the URI contains parameters (e.g. "resource://{param}"), it is
   813	        registered as a template resource. Otherwise it is registered as a
   814	        static resource; function parameters on a static URI raise an error.
   815	
   816	        Args:
   817	            uri: URI for the resource (e.g. "resource://my-resource" or "resource://{param}")
   818	            name: Optional name for the resource
   819	            title: Optional human-readable title for the resource
   820	            description: Optional description of the resource
   821	            mime_type: Optional MIME type for the resource
   822	            icons: Optional list of icons for the resource
   823	            annotations: Optional annotations for the resource
   824	            meta: Optional metadata dictionary for the resource
   825	            security: Path-safety policy for extracted template parameters.
   826	                Defaults to the server's ``resource_security`` setting.
   827	                Only applies to template resources.
   828	
   829	        Example:
   830	            ```python
   831	            @server.resource("resource://my-resource")
   832	            def get_data() -> str:
   833	                return "Hello, world!"
   834	
   835	            @server.resource("resource://my-resource")
   836	            async def get_data() -> str:
   837	                data = await fetch_data()
   838	                return f"Hello, world! {data}"
   839	
   840	            @server.resource("resource://{city}/weather")
   841	            def get_weather(city: str) -> str:
   842	                return f"Weather for {city}"
   843	
   844	            @server.resource("resource://{city}/weather")
   845	            async def get_weather(city: str) -> str:
   846	                data = await fetch_weather(city)
   847	                return f"Weather for {city}: {data}"
   848	            ```
   849	
   850	        Raises:
   851	            InvalidUriTemplate: If ``uri`` is not a valid RFC 6570 template.
   852	            ValueError: If URI template parameters don't match the
   853	                function's parameters, or if a parameter bound to a
   854	                ``{?...}``/``{&...}`` query variable has no default
   855	                (the client may omit it).
   856	            TypeError: If the decorator is applied without being called
   857	                (``@resource`` instead of ``@resource("uri")``).
   858	        """
   859	        # Check if user passed function directly instead of calling decorator
   860	        if callable(uri):
   861	            raise TypeError(
   862	                "The @resource decorator was used incorrectly. "
   863	                "Did you forget to call it? Use @resource('uri') instead of @resource"
   864	            )
   865	
   866	        # Parse once, early — surfaces malformed-template errors at
   867	        # decoration time with a clear position, and gives us correct
   868	        # variable names for all RFC 6570 operators.
   869	        parsed = UriTemplate.parse(uri)
   870	        uri_params = set(parsed.variable_names)
   871	
   872	        def decorator(fn: _CallableT) -> _CallableT:
   873	            sig = inspect.signature(fn)
   874	            context_param = find_context_parameter(fn)
   875	            func_params = {p for p in sig.parameters.keys() if p != context_param}
   876	
   877	            # Template/static is decided purely by the URI: variables
   878	            # present means template, none means static.
   879	            if uri_params:
   880	                if uri_params != func_params:
   881	                    raise ValueError(
   882	                        f"Mismatch between URI parameters {uri_params} and function parameters {func_params}"
   883	                    )
   884	
   885	                # A {?...}/{&...} query variable is optional on the wire:
   886	                # match() omits it from the extracted parameters when the
   887	                # client leaves it out of the URI. The handler parameter
   888	                # bound to it must therefore have a Python default; without
   889	                # one, the author only finds out on the first request that
   890	                # omits it, as an opaque internal error.
   891	                missing_defaults = sorted(
   892	                    name
   893	                    for name in parsed.query_variable_names
   894	                    if sig.parameters[name].default is inspect.Parameter.empty
   895	                )
   896	                if missing_defaults:
   897	                    raise ValueError(
   898	                        f"Resource {uri!r}: query parameter(s) {missing_defaults} have no "
   899	                        f"default value. A client may omit a {{?...}}/{{&...}} query "
   900	                        f"parameter, so the matching handler parameter must declare a "
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py:43:class ToolError(MCPServerError):
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py:47:    call returns `is_error=True` with your message in `content` for the model to
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py:56:    the input schema, and `UnexpectedToolError` subclasses it, so `except ToolError`
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py:61:class UnexpectedToolError(ToolError):
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py:62:    """A tool call failed with something other than `ToolError`, `ResourceError`, or `MCPError`.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py:70:    traceback before returning the `is_error=True` result. Catch it around
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py:71:    `MCPServer.call_tool()` to tell a crash from a deliberate `ToolError`.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:21:    CallToolResult,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:77:    ToolError,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:79:    UnexpectedToolError,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:439:    ) -> CallToolResult | InputRequiredResult:
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:446:            if isinstance(exc, ToolError) and not isinstance(exc, UnexpectedToolError):
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:456:            return CallToolResult(content=[TextContent(type="text", text=str(exc))], is_error=True)
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:535:    ) -> CallToolResult | InputRequiredResult:
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:539:            ToolError: If the tool is unknown, the arguments fail validation, or the
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:540:                tool (or a resolver) raises `ToolError` or `ResourceError`.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:541:            UnexpectedToolError: If the tool (or a resolver) raises anything else, or
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:665:            ToolError: If the tool does not exist
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:81:from mcp.server.mcpserver.exceptions import InvalidSignature, ToolError
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:494:        ToolError: If an elicited value is declined or cancelled and the consumer
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:582:                # client mistake the input_required path below reports as a ToolError.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:586:                raise ToolError(f"Resolver {key!r}: {detail}") from e
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:620:            raise ToolError(f"Resolver {key!r} received a response of the wrong kind") from e
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:624:        raise ToolError(f"Resolver {key!r} received a non-elicitation response")
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:627:            raise ToolError(f"Resolver {key!r} received an accepted elicitation with no content")
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:631:            raise ToolError(
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/resolve.py:648:    raise ToolError(f"Resolver for parameter {name!r} could not resolve: elicitation was {outcome.action}")
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:13:    ToolError,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:15:    UnexpectedToolError,
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:140:        Every failure other than `MCPError` is raised as a `ToolError` whose message
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:146:            ToolError: If the arguments fail validation against the input schema, or
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:147:                the tool function (or a resolver) raises `ToolError` or `ResourceError`.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:148:            UnexpectedToolError: If argument validation, the tool function, or a
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:155:            # to read and correct, so it is reported like a deliberate ToolError.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:156:            raise ToolError(f"Error executing tool {self.name}: {exc}") from exc
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:161:            raise UnexpectedToolError(f"Error executing tool {self.name}") from exc
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:183:            # an authoring bug, so it is raised as a crash rather than a ToolError.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:200:            # `CallToolResult(isError=True)` execution failure.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:202:        # Everything else reaches the model as an is_error result under this tool's
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:204:        except (UnexpectedToolError, UnexpectedResourceError) as exc:
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:207:            raise UnexpectedToolError(f"Error executing tool {self.name}: {exc}") from exc
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:208:        except (ToolError, ResourceError) as exc:
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:210:            raise ToolError(f"Error executing tool {self.name}: {exc}") from exc
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py:213:            raise UnexpectedToolError(f"Error executing tool {self.name}") from exc
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/tool_manager.py:8:from mcp.server.mcpserver.exceptions import ToolError
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/tool_manager.py:72:            raise ToolError(f"Unknown tool: {name}")
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/tool_manager.py:85:            raise ToolError(f"Unknown tool: {name}")
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:13:from mcp_types import CallToolResult, ContentBlock, InputRequiredResult, TextContent
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:186:    def convert_result(self, result: Any) -> CallToolResult | InputRequiredResult:
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:187:        """Convert a function call result into a `CallToolResult`.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:204:        if isinstance(result, CallToolResult):
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:205:            if output_model is not None and not result.is_error:
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:212:            return CallToolResult(content=unstructured_content)
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:226:        return CallToolResult(content=unstructured_content, structured_content=structured_content)
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:404:            # so the CallToolResult/BaseModel/TypedDict dispatch below sees the bare type.
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:408:            isinstance(a, type) and issubclass(a, CallToolResult) for a in residual if a is not type(None)
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:411:                f"Function {func.__name__}: CallToolResult cannot be used in Union or Optional types. "
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:412:                "To return empty results, use: CallToolResult(content=[])"
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:416:    # if the typehint is CallToolResult, the user either intends to return without validation
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:418:    if isinstance(return_type_expr, type) and issubclass(return_type_expr, CallToolResult):
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:423:                # i.e. from `Annotated[CallToolResult, ReturnType, Gt(1)]` to
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:429:                # We only had `Annotated[CallToolResult, ReturnType]`, treat the original annotation
backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/utilities/func_metadata.py:440:        # unless the tool builds its own CallToolResult, echo every block into structured_content).

exec
/bin/zsh -lc "nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py | sed -n '410,470p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/tools/base.py | sed -n '120,225p'; nl -ba backend/.venv/lib/python3.14/site-packages/mcp/server/mcpserver/exceptions.py | sed -n '1,95p'" in /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
 succeeded in 0ms:
   410	
   411	        Args:
   412	            transport: Transport protocol to use ("stdio", "sse", or "streamable-http")
   413	            **kwargs: Transport-specific options (see overloads for details)
   414	        """
   415	        TRANSPORTS = Literal["stdio", "sse", "streamable-http"]
   416	        if transport not in TRANSPORTS.__args__:  # type: ignore  # pragma: no cover
   417	            raise ValueError(f"Unknown transport: {transport}")
   418	
   419	        match transport:
   420	            case "stdio":
   421	                anyio.run(self.run_stdio_async)
   422	            case "sse":  # pragma: no cover
   423	                anyio.run(lambda: self.run_sse_async(**kwargs))
   424	            case "streamable-http":  # pragma: no cover
   425	                anyio.run(lambda: self.run_streamable_http_async(**kwargs))
   426	
   427	    async def _handle_list_tools(
   428	        self, ctx: ServerRequestContext[LifespanResultT], params: PaginatedRequestParams | None
   429	    ) -> ListToolsResult:
   430	        return ListToolsResult(tools=await self.list_tools())
   431	
   432	    def _tool_input_schema(self, name: str) -> dict[str, Any] | None:
   433	        """Called before middleware runs, so it also finds a tool that middleware hides from the caller."""
   434	        tool = self._tool_manager.get_tool(name)
   435	        return None if tool is None else tool.parameters
   436	
   437	    async def _handle_call_tool(
   438	        self, ctx: ServerRequestContext[LifespanResultT], params: CallToolRequestParams
   439	    ) -> CallToolResult | InputRequiredResult:
   440	        context = Context(request_context=ctx, mcp_server=self, input_params=params, subscriptions=self._subscriptions)
   441	        try:
   442	            return await self.call_tool(params.name, params.arguments or {}, context)
   443	        except MCPError:
   444	            raise
   445	        except Exception as exc:
   446	            if isinstance(exc, ToolError) and not isinstance(exc, UnexpectedToolError):
   447	                if isinstance(exc.__cause__, ValidationError):
   448	                    # Field names only: the rejected values are the caller's data.
   449	                    fields = sorted({".".join(str(part) for part in err["loc"]) for err in exc.__cause__.errors()})
   450	                    logger.info("Tool %r rejected arguments: %r", params.name, fields)
   451	                else:
   452	                    # %r keeps peer-supplied text on one line.
   453	                    logger.info("Tool %r failed: %r", params.name, str(exc))
   454	            else:
   455	                logger.exception("Tool %r raised an unexpected exception", params.name)
   456	            return CallToolResult(content=[TextContent(type="text", text=str(exc))], is_error=True)
   457	
   458	    async def _handle_list_resources(
   459	        self, ctx: ServerRequestContext[LifespanResultT], params: PaginatedRequestParams | None
   460	    ) -> ListResourcesResult:
   461	        return ListResourcesResult(resources=await self.list_resources())
   462	
   463	    async def _handle_read_resource(
   464	        self, ctx: ServerRequestContext[LifespanResultT], params: ReadResourceRequestParams
   465	    ) -> ReadResourceResult | InputRequiredResult:
   466	        context = Context(request_context=ctx, mcp_server=self, input_params=params, subscriptions=self._subscriptions)
   467	        try:
   468	            results = await self.read_resource(params.uri, context)
   469	        except ResourceError as err:
   470	            if isinstance(err, UnexpectedResourceError):
   120	            description=func_doc,
   121	            parameters=parameters,
   122	            fn_metadata=func_arg_metadata,
   123	            is_async=is_async,
   124	            context_kwarg=context_kwarg,
   125	            resolved_params=dict(resolved_params),
   126	            resolver_plans=resolver_plans,
   127	            annotations=annotations,
   128	            icons=icons,
   129	            meta=meta,
   130	        )
   131	
   132	    async def run(
   133	        self,
   134	        arguments: dict[str, Any],
   135	        context: Context[LifespanContextT, RequestT],
   136	        convert_result: bool = False,
   137	    ) -> Any:
   138	        """Run the tool with arguments.
   139	
   140	        Every failure other than `MCPError` is raised as a `ToolError` whose message
   141	        starts `Error executing tool <name>` and whose `__cause__` is what was raised.
   142	        An anticipated failure keeps its own text after the prefix. A crash does not,
   143	        so nothing from an unexpected exception reaches the client.
   144	
   145	        Raises:
   146	            ToolError: If the arguments fail validation against the input schema, or
   147	                the tool function (or a resolver) raises `ToolError` or `ResourceError`.
   148	            UnexpectedToolError: If argument validation, the tool function, or a
   149	                resolver raises anything else, or the return value fails output conversion.
   150	        """
   151	        try:
   152	            validated = self.fn_metadata.validate_arguments(arguments)
   153	        except ValidationError as exc:
   154	            # The caller's arguments don't match the input schema: the model's mistake
   155	            # to read and correct, so it is reported like a deliberate ToolError.
   156	            raise ToolError(f"Error executing tool {self.name}: {exc}") from exc
   157	        except MCPError:
   158	            raise
   159	        except Exception as exc:
   160	            # A custom validator or default_factory that raises is a crash.
   161	            raise UnexpectedToolError(f"Error executing tool {self.name}") from exc
   162	
   163	        try:
   164	            pass_directly: dict[str, Any] = {}
   165	            if self.context_kwarg is not None:
   166	                pass_directly[self.context_kwarg] = context
   167	
   168	            # Resolvers see the same validated arguments the tool body receives, so a
   169	            # `default_factory`/stateful validator can't hand a by-name resolver a
   170	            # different value than the body.
   171	            if self.resolved_params:
   172	                resolved = await resolve_arguments(self.resolved_params, self.resolver_plans, validated, context)
   173	                if isinstance(resolved, InputRequiredResult):
   174	                    # A resolver still needs client input (>= 2026-07-28): surface the
   175	                    # batched questions instead of running the tool body this round.
   176	                    return self.fn_metadata.convert_result(resolved) if convert_result else resolved
   177	                pass_directly |= resolved
   178	
   179	            result = await self.fn_metadata.call_fn(self.fn, self.is_async, validated, pass_directly)
   180	
   181	            # Registration rejects the annotated form of this combination; this covers
   182	            # a body that returns an InputRequiredResult without declaring it. It is
   183	            # an authoring bug, so it is raised as a crash rather than a ToolError.
   184	            if self.resolved_params and isinstance(result, InputRequiredResult):
   185	                raise RuntimeError(
   186	                    "the tool returned an InputRequiredResult but its parameters use Resolve(...); "
   187	                    "a call has one input_required channel, so the multi-round flow is driven "
   188	                    "either by resolvers or by the tool body, not both"
   189	                )
   190	
   191	            if convert_result:
   192	                result = self.fn_metadata.convert_result(result)
   193	
   194	            return result
   195	        except MCPError:
   196	            # `MCPError` (and subclasses such as `UrlElicitationRequiredError`)
   197	            # carries a JSON-RPC `ErrorData(code, message, data)` and means
   198	            # "respond with a protocol error" - re-raise so the kernel surfaces
   199	            # it as a top-level JSON-RPC error rather than wrapping it as a
   200	            # `CallToolResult(isError=True)` execution failure.
   201	            raise
   202	        # Everything else reaches the model as an is_error result under this tool's
   203	        # name, and the wrapper's type tells the server whether to log a crash.
   204	        except (UnexpectedToolError, UnexpectedResourceError) as exc:
   205	            # A nested tool call or resource read crashed: still a crash here. Its
   206	            # message is already the generic one, so it is safe to carry along.
   207	            raise UnexpectedToolError(f"Error executing tool {self.name}: {exc}") from exc
   208	        except (ToolError, ResourceError) as exc:
   209	            # Raised deliberately by the tool, a resolver, or a resource it read.
   210	            raise ToolError(f"Error executing tool {self.name}: {exc}") from exc
   211	        except Exception as exc:
   212	            # A crash: the exception's own text stays on the server.
   213	            raise UnexpectedToolError(f"Error executing tool {self.name}") from exc
     1	"""Custom exceptions for MCPServer."""
     2	
     3	
     4	class MCPServerError(Exception):
     5	    """Base error for MCPServer."""
     6	
     7	
     8	class ResourceError(MCPServerError):
     9	    """A resource failure you anticipated.
    10	
    11	    Raise this from a resource or resource template handler for a failure you saw
    12	    coming: the client receives a `-32603` protocol error carrying your message
    13	    (`ResourceNotFoundError` below is the `-32602` variant), and the server logs it
    14	    at INFO without a traceback. Any other exception (bar `MCPError`, which is a
    15	    protocol error) is treated as a crash: the client gets a generic message naming
    16	    only the URI, and the server logs the traceback at ERROR.
    17	
    18	    The SDK raises it too, and `UnexpectedResourceError` subclasses it, so
    19	    `except ResourceError` around `MCPServer.read_resource()` catches every read
    20	    failure, crash or not.
    21	    """
    22	
    23	
    24	class ResourceNotFoundError(ResourceError):
    25	    """Resource does not exist.
    26	
    27	    Raise this from a resource handler to signal that the requested instance does not exist.
    28	    Clients receive `-32602` (invalid params) per
    29	    [SEP-2164](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2164).
    30	    """
    31	
    32	
    33	class UnexpectedResourceError(ResourceError):
    34	    """A resource read failed with something other than `ResourceError` or `MCPError`.
    35	
    36	    The SDK raises this itself, around a crash in a resource or resource template
    37	    handler. You never raise it. `__cause__` is the original exception, which the
    38	    server logs with its traceback. The message names only the URI, so the
    39	    original text is withheld from the client.
    40	    """
    41	
    42	
    43	class ToolError(MCPServerError):
    44	    """A tool failure you anticipated.
    45	
    46	    Raise this from a tool (or a resolver) for a failure you saw coming: the
    47	    call returns `is_error=True` with your message in `content` for the model to
    48	    read, and the server logs it at INFO without a traceback. A `ResourceError`
    49	    that escapes the tool (say from `ctx.read_resource()`) counts the same. Any
    50	    other exception bar `MCPError` (a protocol error) is treated as a crash: the
    51	    model sees only `Error executing tool <name>`, and the server logs the
    52	    traceback at ERROR. Inside a pydantic validator, raise `ValueError` as pydantic
    53	    expects; it arrives as an argument-validation failure, which is anticipated too.
    54	
    55	    The SDK raises it too, for an unknown tool name and for arguments that fail
    56	    the input schema, and `UnexpectedToolError` subclasses it, so `except ToolError`
    57	    around `MCPServer.call_tool()` catches every tool failure, crash or not.
    58	    """
    59	
    60	
    61	class UnexpectedToolError(ToolError):
    62	    """A tool call failed with something other than `ToolError`, `ResourceError`, or `MCPError`.
    63	
    64	    The SDK raises this itself, around a crash in the tool (or a resolver) or a
    65	    return value that fails output conversion. You never raise it. The message is
    66	    only `Error executing tool <name>` (followed by the same for a nested tool or
    67	    resource that crashed), so nothing from the original reaches the client.
    68	    `__cause__` is the original exception (or, for a nested tool or resource
    69	    crash, its `Unexpected...Error` wrapper), which the server logs with its
    70	    traceback before returning the `is_error=True` result. Catch it around
    71	    `MCPServer.call_tool()` to tell a crash from a deliberate `ToolError`.
    72	    """
    73	
    74	
    75	class InvalidSignature(Exception):
    76	    """Invalid signature for use with MCPServer."""

codex
**Answer:** Không thấy lỗi thực thi trong auth, `ContextVar`, write-path hay lifespan; phát hiện 3 lỗ hổng test.

**Major — backend/tests/test_mcp.py:39:** Mọi request dùng chung `loaded_session`; advisory lock và transaction isolation không được kiểm tra thật. Test stale-admin vẫn xanh nếu bỏ `lock_content`. Fix: dùng session/connection độc lập và race có barrier.

**Major — backend/tests/test_mcp.py:65:** Tất cả tool call tuần tự với cùng `SUB`; thay `ContextVar` bằng global mutable vẫn có thể xanh. Fix: gửi đồng thời hai JWT/sub khác nhau, chặn giữa dispatch và authorization rồi kiểm tra không lẫn quyền.

**Minor — backend/tests/test_mcp.py:92:** Body rác không chứng minh auth xảy ra trước khi đọc body; implementation đọc toàn bộ rồi trả 401 vẫn xanh. Không có test body chunked/no `Content-Length` vượt 64 KiB. Fix: gọi ASGI với `receive` sentinel và stream nhiều chunk, kỳ vọng 401/413 tương ứng.

**Before vs After:** Hiện implementation đúng nhưng các invariant concurrency/DoS chưa được test; sau fix, regression auth leakage, lost update và bỏ SDK body limit sẽ bị bắt.

**Example:** Xóa `lock_content()` ở `mcp_server.py:99` vẫn không làm test hiện tại fail. Không chạy được suite DB vì sandbox chặn kết nối PostgreSQL localhost.
tokens used
137,555
**Answer:** Không thấy lỗi thực thi trong auth, `ContextVar`, write-path hay lifespan; phát hiện 3 lỗ hổng test.

**Major — backend/tests/test_mcp.py:39:** Mọi request dùng chung `loaded_session`; advisory lock và transaction isolation không được kiểm tra thật. Test stale-admin vẫn xanh nếu bỏ `lock_content`. Fix: dùng session/connection độc lập và race có barrier.

**Major — backend/tests/test_mcp.py:65:** Tất cả tool call tuần tự với cùng `SUB`; thay `ContextVar` bằng global mutable vẫn có thể xanh. Fix: gửi đồng thời hai JWT/sub khác nhau, chặn giữa dispatch và authorization rồi kiểm tra không lẫn quyền.

**Minor — backend/tests/test_mcp.py:92:** Body rác không chứng minh auth xảy ra trước khi đọc body; implementation đọc toàn bộ rồi trả 401 vẫn xanh. Không có test body chunked/no `Content-Length` vượt 64 KiB. Fix: gọi ASGI với `receive` sentinel và stream nhiều chunk, kỳ vọng 401/413 tương ứng.

**Before vs After:** Hiện implementation đúng nhưng các invariant concurrency/DoS chưa được test; sau fix, regression auth leakage, lost update và bỏ SDK body limit sẽ bị bắt.

**Example:** Xóa `lock_content()` ở `mcp_server.py:99` vẫn không làm test hiện tại fail. Không chạy được suite DB vì sandbox chặn kết nối PostgreSQL localhost.
