"""API quản trị nội dung (chỉ admin) dưới `/api/admin`. DB là nguồn chính của nội dung.

- GET  /api/admin/content   → {version, content}: nội dung đầy đủ (CÓ judge), `version` = admin_version.
- POST /api/admin/validate  {content} → {ok, errors}: chạy đủ luật, không ghi.
- PUT  /api/admin/content   {base_version, content} → {version} | 409 version_conflict | 422 {errors}.
- GET/POST/DELETE /api/admin/mcp-access[/{sub}]: cấp/thu hồi quyền sửa nội dung qua `/mcp` (app.mcp_access).

Ghi đi đúng một đường với CLI: `load_content` (validate + thay toàn bộ, một transaction, khoá
`CONTENT_WRITE_LOCK`). Kiểm version và ghi nằm trong cùng khoá, nên hai admin không ghi đè nhau.
Không chạy lời giải mẫu trên server (không thực thi code ở đây) — việc đó là của Run trên máy chấm.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy.exc import DataError, IntegrityError
from sqlalchemy.orm import Session

from app.auth import CurrentUser, require_admin
from app.db import get_session
from app.export_content import admin_version, export_content
from app.load_content import load_content, lock_content, validation_errors
from app.mcp_access import allow, list_access, revoke

logger = logging.getLogger("admin")

# Đặt ở cấp router: route admin thêm sau này không thể quên kiểm quyền.
router = APIRouter(prefix="/api/admin", dependencies=[Depends(require_admin)])

MAX_ERRORS = 200


class ContentIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    content: dict[str, Any]


class SaveIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    base_version: str = Field(min_length=1, max_length=100)
    content: dict[str, Any]


class McpAccessIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    sub: str
    email: str
    label: str = ""


class _BadBody(Exception):
    def __init__(self, errors: list[str]):
        self.errors = errors


def _capped(errors: list[str]) -> list[str]:
    extra = len(errors) - MAX_ERRORS
    return errors[:MAX_ERRORS] + ([f"… và {extra} lỗi nữa"] if extra > 0 else [])


def _invalid(errors: list[str]) -> JSONResponse:
    """Mọi 422 của admin cùng một dạng `{errors: [...]}` để app hiện được."""
    return JSONResponse(status_code=422, content={"errors": _capped(errors)})


async def _parse(request: Request, model: type[BaseModel]):
    """Đọc body SAU khi đã qua require_admin: không khai body trong chữ ký route, vì FastAPI sẽ đọc và
    parse body (tới 4MB) trước cả khi kiểm quyền — khách chưa đăng nhập cũng bắt server parse được."""
    try:
        raw = json.loads(await request.body())
    except (ValueError, UnicodeDecodeError, RecursionError):  # RecursionError: `[[[[…` lồng sâu
        raise _BadBody(["body không phải JSON hợp lệ"]) from None
    try:
        return model.model_validate(raw)
    except ValidationError as exc:
        raise _BadBody([f'{".".join(str(p) for p in e["loc"]) or "body"}: {e["msg"]}' for e in exc.errors()]) from None


@router.get("/content")
def get_admin_content(session: Session = Depends(get_session)) -> dict:
    data = export_content(session)
    return {"version": admin_version(data), "content": data}


@router.post("/validate")
async def validate_content(request: Request):
    try:
        body = await _parse(request, ContentIn)
    except _BadBody as exc:
        return _invalid(exc.errors)
    errors = await run_in_threadpool(validation_errors, body.content)
    return {"ok": not errors, "errors": _capped(errors)}


def _save(body: SaveIn, user: CurrentUser, session: Session):
    errors = validation_errors(body.content)  # trước khi khoá: nội dung sai thì không giữ khoá ghi
    if errors:
        return _invalid(errors)
    lock_content(session)
    current = admin_version(export_content(session))
    if body.base_version != current:
        raise HTTPException(status_code=409, detail="version_conflict")
    try:
        load_content(session, body.content, validated=True)
    except DataError as exc:
        # Lọt qua validate mà DB vẫn từ chối: trả cùng dạng lỗi để admin thấy, không ghi gì.
        session.rollback()
        logger.warning("admin save rejected by DB: %s", type(exc.orig).__name__)
        return _invalid([f"DB từ chối nội dung ({type(exc.orig).__name__}) — kiểm độ dài id/tên"])
    version = admin_version(export_content(session))
    session.commit()
    logger.info("admin %s saved content %s -> %s", user.email, current, version)
    return {"version": version}


@router.put("/content")
async def save_content(
    request: Request,
    user: CurrentUser = Depends(require_admin),
    session: Session = Depends(get_session),
):
    try:
        body = await _parse(request, SaveIn)
    except _BadBody as exc:
        return _invalid(exc.errors)
    return await run_in_threadpool(_save, body, user, session)


@router.get("/mcp-access")
def get_mcp_access(session: Session = Depends(get_session)) -> dict:
    return {"items": list_access(session)}


def _grant(body: McpAccessIn, user: CurrentUser, session: Session):
    try:
        item = allow(session, body.sub, body.email, body.label)
        session.commit()
    except ValueError as exc:
        session.rollback()
        return _invalid([str(exc)])
    except IntegrityError:  # hai admin cấp cùng một sub mới đúng lúc
        session.rollback()
        return _invalid(["sub vừa được cấp ở nơi khác — tải lại danh sách rồi thử lại"])
    logger.info("admin %s granted mcp access sub=%s as %s", user.email, item["sub"], item["email"])
    return {"item": item}


@router.post("/mcp-access")
async def post_mcp_access(
    request: Request,
    user: CurrentUser = Depends(require_admin),
    session: Session = Depends(get_session),
):
    try:
        body = await _parse(request, McpAccessIn)
    except _BadBody as exc:
        return _invalid(exc.errors)
    return await run_in_threadpool(_grant, body, user, session)


@router.delete("/mcp-access/{sub}")
def delete_mcp_access(
    sub: str,
    user: CurrentUser = Depends(require_admin),
    session: Session = Depends(get_session),
):
    if not revoke(session, sub):
        raise HTTPException(status_code=404, detail="not_found")
    session.commit()
    logger.info("admin %s revoked mcp access sub=%s", user.email, sub.strip())
    return Response(status_code=204)
