"""API quản trị nội dung (chỉ admin) dưới `/api/admin`. Mọi sửa đổi vào hàng chờ duyệt (app.review).

- GET  /api/admin/content   → {version, content, pending}: **draft** (live ⊕ mục chờ, CÓ judge),
  `version` = hash(draft), `pending` = [{id, kind, item_id, action}].
- POST /api/admin/validate  {content} → {ok, errors}: chạy đủ luật, không ghi.
- PUT  /api/admin/content   {base_version, content} → {version, pending} | 409 version_conflict | 422 {errors}.
  KHÔNG ghi live: diff với live thành các mục chờ duyệt.
- GET  /api/admin/changes   → {changes: [...]}: mục đang chờ, kèm before/after.
- POST /api/admin/changes/{id}/approve | /reject → {id, status, version} | 404/409/422 {detail, message, errors}.
- GET/POST/DELETE /api/admin/mcp-access[/{sub}]: cấp/thu hồi quyền sửa nội dung qua `/mcp` (app.mcp_access).

Live chỉ đổi qua approve (hoặc CLI `load_content --force`): một mục, trong khoá `CONTENT_WRITE_LOCK`,
kiểm mục live còn như lúc gửi và toàn bộ live mới qua `validation_errors`. Không chạy lời giải mẫu trên
server — việc đó là của Run trên máy chấm (`/api/admin/run` chấm theo draft, ở app.main).
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
from app.load_content import validation_errors
from app.mcp_access import allow, list_access, revoke
from app import review

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


def _summary(row) -> dict:
    return {"id": row.id, "kind": row.kind, "item_id": row.item_id, "action": row.action}


@router.get("/content")
def get_admin_content(session: Session = Depends(get_session)) -> dict:
    rows = review.pending_rows(session)
    data = review.draft_content(session, rows)
    return {"version": review.admin_version(data), "content": data, "pending": [_summary(r) for r in rows]}


@router.post("/validate")
async def validate_content(request: Request):
    try:
        body = await _parse(request, ContentIn)
    except _BadBody as exc:
        return _invalid(exc.errors)
    errors = await run_in_threadpool(validation_errors, body.content)
    return {"ok": not errors, "errors": _capped(errors)}


def _review_error(exc: review.ReviewError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status,
        content={"detail": exc.code, "message": exc.message, "errors": _capped(exc.errors)},
    )


def _save(body: SaveIn, user: CurrentUser, session: Session):
    errors = validation_errors(body.content)  # trước khi khoá: nội dung sai thì không giữ khoá ghi
    if errors:
        return _invalid(errors)
    try:
        result = review.submit(session, body.base_version, body.content, user.email)
    except review.VersionConflict:
        session.rollback()
        raise HTTPException(status_code=409, detail="version_conflict") from None
    except review.ReviewError as exc:
        session.rollback()
        return _review_error(exc)
    session.commit()
    return result


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


@router.get("/changes")
def get_changes(session: Session = Depends(get_session)) -> dict:
    return {"changes": [review.change_json(r) for r in review.pending_rows(session)]}


def _decide(action, change_id: int, user: CurrentUser, session: Session):
    try:
        result = action(session, change_id, user.email)
    except review.ReviewError as exc:
        session.rollback()
        return _review_error(exc)
    except DataError as exc:
        session.rollback()
        logger.warning("approve rejected by DB: %s", type(exc.orig).__name__)
        return _invalid([f"DB từ chối nội dung ({type(exc.orig).__name__}) — kiểm độ dài id/tên"])
    version = review.draft_version(session)
    session.commit()
    return {**result, "version": version}


@router.post("/changes/{change_id}/approve")
async def approve_change(change_id: int, user: CurrentUser = Depends(require_admin), session: Session = Depends(get_session)):
    return await run_in_threadpool(_decide, review.approve, change_id, user, session)


@router.post("/changes/{change_id}/reject")
async def reject_change(change_id: int, user: CurrentUser = Depends(require_admin), session: Session = Depends(get_session)):
    return await run_in_threadpool(_decide, review.reject, change_id, user, session)


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
