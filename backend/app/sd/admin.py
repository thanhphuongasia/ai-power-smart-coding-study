"""API quản trị tài liệu System Design (chỉ admin) dưới `/api/admin/sd`.

- POST /api/admin/sd/docs               {id?, markdown, status?} → tóm tắt | 422 {errors}
  Nhập (hoặc nhập lại) một tài liệu .md. `id` bỏ trống → slug của tên tài liệu. `status` bỏ trống →
  giữ trạng thái cũ (tài liệu mới là `draft`). Nhập lại thay section/task trong MỘT transaction và KHÔNG
  chạm `sd_progress`/`sd_attempts`: tiến độ bám theo `card.id` (hash nội dung) nên card không đổi giữ nguyên.
  Lưu ý: `section.id` là slug của tên section, đổi tên section thì tiến độ section đó mất (xem app/sd/parser.py).
- GET  /api/admin/sd/docs[?include_archived=false] → {items: [{id, title, status, sections, cards, tasks, has_markdown}]}
- PUT  /api/admin/sd/docs/{id}/status   {status: draft|published|archived} → {id, status} | 404
  `archived` = xoá mềm (học viên không thấy, bài nộp/tiến độ còn nguyên).

Nghiệp vụ nằm ở `app/sd/docs.py`, dùng chung với MCP và CLI (`app/sd/import_file.py`): mọi lần nhập lưu markdown gốc.

Không đi qua hàng chờ duyệt: đây là tài liệu đọc, không phải nội dung chấm bài.
"""

from __future__ import annotations

import logging
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Path, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.admin_api import _BadBody, _invalid, _parse
from app.auth import CurrentUser, require_admin
from app.db import get_session
from app.sd import docs

logger = logging.getLogger("sd")

# Đặt ở cấp router: route thêm sau này không thể quên kiểm quyền (giống app.admin_api).
router = APIRouter(prefix="/api/admin/sd", dependencies=[Depends(require_admin)])

MAX_MD_BYTES = docs.MAX_MD_BYTES
_SLUG = r"^[a-z0-9][a-z0-9-]*$"


class ImportIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str | None = Field(default=None, max_length=100, pattern=_SLUG)
    markdown: str = Field(max_length=MAX_MD_BYTES)
    status: Literal["draft", "published"] | None = None


class StatusIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["draft", "published", "archived"]


def _import(body: ImportIn, user: CurrentUser, session: Session):
    try:
        return docs.import_markdown(session, body.markdown, actor=user.email, doc_id=body.id, status=body.status)
    except docs.SdDocError as exc:
        return _invalid(exc.errors)


@router.post("/docs")
async def import_doc(
    request: Request,
    user: CurrentUser = Depends(require_admin),
    session: Session = Depends(get_session),
):
    try:
        body = await _parse(request, ImportIn)
    except _BadBody as exc:
        return _invalid(exc.errors)
    return await run_in_threadpool(_import, body, user, session)


@router.get("/docs")
def list_docs(include_archived: bool = True, session: Session = Depends(get_session)) -> dict:
    return {"items": docs.list_docs(session, include_archived=include_archived)}


def _set_status(doc_id: str, body: StatusIn, user: CurrentUser, session: Session):
    try:
        result = docs.set_status(session, doc_id, body.status, actor=user.email)
    except docs.SdDocNotFound:
        raise HTTPException(status_code=404, detail="doc_not_found") from None
    return {"id": result["id"], "status": result["status"]}


@router.put("/docs/{doc_id}/status")
async def put_status(
    request: Request,
    doc_id: str = Path(max_length=100, pattern=_SLUG),
    user: CurrentUser = Depends(require_admin),
    session: Session = Depends(get_session),
):
    try:
        body = await _parse(request, StatusIn)
    except _BadBody as exc:
        return _invalid(exc.errors)
    return await run_in_threadpool(_set_status, doc_id, body, user, session)
