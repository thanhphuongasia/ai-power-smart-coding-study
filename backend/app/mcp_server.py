"""`/mcp`: MCP server (Streamable HTTP) để Claude trên claude.ai đọc và tạo/sửa nội dung học.

- Cổng (`McpGate`) chạy TRƯỚC SDK: không có JWT hợp lệ của identity-service → 401 + `WWW-Authenticate`
  có `resource_metadata` (claude.ai chỉ hiện nút Connect khi thấy đúng thứ này trên một 401).
- Mỗi tool kiểm lại quyền bằng `authorize_sub` (bảng `mcp_access`) — thu hồi có hiệu lực ngay.
- Ghi đi đúng đường của admin PUT: hàm thuần `content_ops` trên DRAFT → `validation_errors` (ngoài khoá)
  → `review.submit` (khoá ghi, so version với draft, ghi mục chờ duyệt). KHÔNG đụng nội dung đang chạy:
  admin duyệt trong app thì học viên mới thấy. Đọc cũng đọc draft để các lần gọi nối tiếp nhau được.
- Project = theme, module = topic, file = code file, lesson = exercise. Không có xoá.

SDK chạy stateless + JSON response: mỗi POST là một request độc lập, không giữ phiên trong RAM.
"""

from __future__ import annotations

import contextvars
import logging
from collections.abc import AsyncIterator, Callable, Iterator
from contextlib import asynccontextmanager, contextmanager
from typing import Any

from fastapi.concurrency import run_in_threadpool
from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp.server.transport_security import TransportSecuritySettings
from mcp.types import ToolAnnotations
from sqlalchemy.orm import Session
from starlette.datastructures import Headers
from starlette.responses import JSONResponse
from starlette.types import Receive, Scope, Send

from app import content_ops, review
from app.content_ops import ContentOpError
from app.db import SessionLocal
from app.export_content import admin_version
from app.load_content import validation_errors
from app.mcp_auth import (
    InvalidToken,
    JwksUnavailable,
    authorize_sub,
    public_base_url,
    verify_bearer,
    www_authenticate,
)

logger = logging.getLogger("mcp")

MAX_BODY_BYTES = 64 * 1024  # bằng trần chung của main.py; một bài đầy đủ chỉ vài KB
MAX_ERRORS = 50

_claims: contextvars.ContextVar[dict | None] = contextvars.ContextVar("mcp_claims", default=None)

INSTRUCTIONS = (
    "Công cụ soạn nội dung cho app học lập trình Smart Coding Study. Cây nội dung: project → module "
    "(lồng được) → file → lesson. Mọi thay đổi chỉ vào HÀNG CHỜ DUYỆT: admin phải duyệt trong app thì học viên mới thấy — hãy nói rõ điều này với người dùng sau khi ghi. Các lần đọc thấy cả mục đang chờ duyệt. Trước khi tạo/sửa bài, gọi "
    "get_authoring_guide để biết luật; thử với dry_run=true trước, sửa hết lỗi rồi mới ghi thật."
)

mcp = MCPServer(name="smart-coding-study", instructions=INSTRUCTIONS)


@contextmanager
def open_session() -> Iterator[Session]:
    """Session DB cho một tool call. Test thay bằng session trong transaction."""
    with SessionLocal() as session:
        yield session


def _authorized(session: Session):
    claims = _claims.get()
    sub = claims["sub"] if claims else None
    user = authorize_sub(session, sub) if sub else None
    if user is None:
        raise ToolError(
            f"Tài khoản identity sub={sub} chưa được cấp quyền sửa nội dung (hoặc đã bị thu hồi). "
            f"Admin cấp bằng: python -m app.mcp_access allow {sub} --as <email admin>"
        )
    return user, sub


def _capped(errors: list[str]) -> str:
    extra = len(errors) - MAX_ERRORS
    lines = errors[:MAX_ERRORS] + ([f"… và {extra} lỗi nữa"] if extra > 0 else [])
    return "\n".join(f"- {e}" for e in lines)


def _read(fn: Callable[[dict], Any]) -> Any:
    with open_session() as session:
        _authorized(session)
        try:
            return fn(review.draft_content(session))
        except ContentOpError as exc:
            raise ToolError(str(exc)) from None


def _write(tool: str, op: Callable[[dict], dict], dry_run: bool) -> dict:
    with open_session() as session:
        user, sub = _authorized(session)
        before = review.draft_content(session)
        base = admin_version(before)
        try:
            after = op(before)
        except ContentOpError as exc:
            raise ToolError(str(exc)) from None
        # Kiểm luật TRƯỚC khi giữ khoá ghi (như admin PUT): nội dung sai không chặn ai.
        errors = validation_errors(after)
        if errors:
            raise ToolError("Nội dung không hợp lệ, chưa ghi gì:\n" + _capped(errors))
        if dry_run:
            return {"ok": True, "dry_run": True, "message": "Hợp lệ. Gọi lại với dry_run=false để gửi vào hàng chờ duyệt."}
        author = f"mcp:{sub} ({user.email})" if user.email else f"mcp:{sub}"
        try:
            result = review.submit(session, base, after, author)
        except review.VersionConflict:
            session.rollback()
            raise ToolError("Người khác vừa sửa nội dung trong lúc kiểm. Đọc lại rồi thử lại.") from None
        except review.ReviewError as exc:
            session.rollback()
            raise ToolError(exc.message) from None
        session.commit()
    logger.info("mcp %s by %s (sub=%s): %s -> %s (%d pending)", tool, user.email, sub, base, result["version"], result["pending"])
    return {
        "ok": True,
        "version": result["version"],
        "pending": result["pending"],
        "message": "Đã gửi vào hàng chờ duyệt — admin cần duyệt trong app thì học viên mới thấy.",
    }


# open_world_hint=False: tool chỉ chạm DB nội dung của app này (mặc định của spec là True).
_READ = ToolAnnotations(read_only_hint=True, open_world_hint=False)
_WRITE = ToolAnnotations(read_only_hint=False, destructive_hint=False, idempotent_hint=False, open_world_hint=False)
_UPDATE = ToolAnnotations(read_only_hint=False, destructive_hint=True, idempotent_hint=True, open_world_hint=False)


@mcp.tool(annotations=_READ)
async def list_projects() -> list[dict]:
    """Liệt kê mọi project (id, tên, mô tả, số module/file/bài)."""
    return await run_in_threadpool(_read, content_ops.list_projects)


@mcp.tool(annotations=_READ)
async def get_project(project_id: str) -> dict:
    """Cây của một project: module (lồng nhau) → file → tên bài, kèm sơ đồ class."""
    return await run_in_threadpool(_read, lambda c: content_ops.project_tree(c, project_id))


@mcp.tool(annotations=_READ)
async def get_lesson(lesson_id: str) -> dict:
    """Bài đầy đủ (template, ô, gợi ý, challenge, judge gồm lời giải + test case) và các file chứa bài."""
    return await run_in_threadpool(_read, lambda c: content_ops.get_lesson(c, lesson_id))


AUTHORING_GUIDE = """Luật soạn bài (server kiểm hết khi ghi; vi phạm thì tool trả danh sách lỗi):

Cấu trúc
- id duy nhất TOÀN CỤC giữa project/module/file/bài/ô, ≤100 ký tự. Project cần ≥1 module.
- Bài: {id, title, class_name (null = hàm rời; tên class = method), function_name, params[], template,
  challenge{statement, motivation, small{caption,input,output,note}, project{...}}, blocks[], judge{solution, cases[]}}.
- function_name "__init__" cần class_name. Bài method chỉ chấm được bằng case kịch bản (xem bài mẫu).

Ô (blocks) và template
- ≤3 ô. Mỗi ô: {id, label, title, prompt, indent_level, accepted_answers[], expected_output, explanation, hints[], vocab[]}.
- label là MỘT chữ in hoa (A, B, C); id ô = "<id bài>-<label viết thường>" (vd "add_flight-a").
- template có đúng một dòng "# TODO <label>" cho mỗi ô, thụt đúng 4 × indent_level khoảng trắng, không marker thừa.
- Mỗi đáp án ≤2 dòng; tổng dòng đáp án đầu tiên của mọi ô ≤10; đúng 3 gợi ý; vocab và explanation không rỗng.
- Thay mỗi "# TODO <label>" bằng accepted_answers[0] của ô đó phải ra ĐÚNG judge.solution (từng ký tự).
- Không đặt ô sau "return" trong cùng nhánh (code chết).

Challenge và sơ đồ
- challenge không rỗng, ví dụ phải gọi đúng tên hàm.
- Sơ đồ class của project phải khớp code: class tồn tại, thuộc tính `self.x =`, method `def m(`.

judge.cases: ≥1 case, cùng dạng với bài mẫu.

Cách làm: get_lesson một bài cùng loại làm mẫu → soạn → gọi tool với dry_run=true → sửa lỗi → ghi thật."""


@mcp.tool(annotations=_READ)
async def get_authoring_guide() -> dict:
    """Luật nội dung + một bài mẫu thật. Đọc trước khi tạo/sửa bài."""

    def build(content: dict) -> dict:
        example = next(iter(content["exercises"].values()), None)
        return {"rules": AUTHORING_GUIDE, "example_lesson": example}

    return await run_in_threadpool(_read, build)


def _writer(tool: str, op: Callable[[dict], dict], dry_run: bool):
    return run_in_threadpool(_write, tool, op, dry_run)


@mcp.tool(annotations=_WRITE)
async def create_project(project: dict[str, Any], first_module: dict[str, Any], dry_run: bool = False) -> dict:
    """Tạo project mới (id, name, description, tags?, diagram?) cùng module đầu tiên (id, name, description). Vào hàng chờ duyệt: báo người dùng là admin cần duyệt."""
    return await _writer("create_project", lambda c: content_ops.create_project(c, project, first_module), dry_run)


@mcp.tool(annotations=_UPDATE)
async def update_project(project_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
    """Sửa project; chỉ các field name, description, tags, diagram."""
    return await _writer("update_project", lambda c: content_ops.update_project(c, project_id, changes), dry_run)


@mcp.tool(annotations=_WRITE)
async def create_module(
    project_id: str, module: dict[str, Any], parent_module_id: str | None = None, dry_run: bool = False
) -> dict:
    """Tạo module (id, name, description) trong project, hoặc làm module con của parent_module_id."""
    return await _writer(
        "create_module", lambda c: content_ops.create_module(c, project_id, module, parent_module_id), dry_run
    )


@mcp.tool(annotations=_UPDATE)
async def update_module(module_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
    """Sửa module; chỉ name, description."""
    return await _writer("update_module", lambda c: content_ops.update_module(c, module_id, changes), dry_run)


@mcp.tool(annotations=_WRITE)
async def create_file(module_id: str, file: dict[str, Any], dry_run: bool = False) -> dict:
    """Tạo file code (id, name) trong module."""
    return await _writer("create_file", lambda c: content_ops.create_file(c, module_id, file), dry_run)


@mcp.tool(annotations=_UPDATE)
async def update_file(file_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
    """Sửa file; chỉ name và exercise_ids (thứ tự bài / gắn bài có sẵn)."""
    return await _writer("update_file", lambda c: content_ops.update_file(c, file_id, changes), dry_run)


@mcp.tool(annotations=_WRITE)
async def create_lesson(file_id: str, lesson: dict[str, Any], dry_run: bool = False) -> dict:
    """Tạo bài mới đầy đủ (gồm judge) và gắn vào cuối file. Đọc get_authoring_guide trước. Vào hàng chờ duyệt: báo người dùng là admin cần duyệt."""
    return await _writer("create_lesson", lambda c: content_ops.create_lesson(c, file_id, lesson), dry_run)


@mcp.tool(annotations=_UPDATE)
async def update_lesson(lesson_id: str, changes: dict[str, Any], dry_run: bool = False) -> dict:
    """Sửa bài: thay nguyên các field top-level được truyền (không đổi id). Vào hàng chờ duyệt: báo người dùng là admin cần duyệt."""
    return await _writer("update_lesson", lambda c: content_ops.update_lesson(c, lesson_id, changes), dry_run)


def _json(status: int, body: dict, headers: dict[str, str] | None = None) -> JSONResponse:
    return JSONResponse(status_code=status, content=body, headers=headers)


class McpGate:
    """ASGI cho `/mcp`: xác thực JWT trước khi SDK đọc body, rồi chuyển cho session manager."""

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["method"] != "POST":
            # Stateless: không có luồng SSE GET hay phiên để DELETE. GET để SDK xử lý sẽ mở một luồng
            # SSE treo mãi, giữ chỗ worker uvicorn (spec cho phép 405 ở đây).
            await _json(405, {"detail": "method_not_allowed"}, {"Allow": "POST"})(scope, receive, send)
            return
        base = public_base_url()
        if base is None:
            await _json(503, {"detail": "mcp_not_configured"})(scope, receive, send)
            return
        authorization = Headers(scope=scope).get("authorization")
        try:
            claims = await run_in_threadpool(verify_bearer, authorization, base)
        except InvalidToken:
            challenge = {"WWW-Authenticate": www_authenticate(base, invalid=authorization is not None)}
            await _json(401, {"error": "invalid_token"}, challenge)(scope, receive, send)
            return
        except JwksUnavailable:
            logger.warning("identity JWKS unavailable")
            await _json(503, {"detail": "auth_unavailable"})(scope, receive, send)
            return
        reset = _claims.set(claims)
        try:
            await mcp.session_manager.handle_request(scope, receive, send)
        finally:
            _claims.reset(reset)


@asynccontextmanager
async def lifespan() -> AsyncIterator[None]:
    """Session manager chỉ `run()` được một lần mỗi instance: dựng mới mỗi lần app khởi động."""
    # Không bật chống DNS rebinding của SDK: endpoint đòi Bearer token, trình duyệt không tự gắn được
    # token cho trang lạ, và Host thật đứng sau nginx khác nhau giữa môi trường.
    mcp.streamable_http_app(
        json_response=True,
        stateless_http=True,
        max_request_body_size=MAX_BODY_BYTES,
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
    )
    async with mcp.session_manager.run():
        yield
