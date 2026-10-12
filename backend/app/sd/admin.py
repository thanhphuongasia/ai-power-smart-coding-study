"""API quản trị tài liệu System Design (chỉ admin) dưới `/api/admin/sd`.

- POST /api/admin/sd/docs               {id?, markdown, status?} → tóm tắt | 422 {errors}
  Nhập (hoặc nhập lại) một tài liệu .md. `id` bỏ trống → slug của tên tài liệu. `status` bỏ trống →
  giữ trạng thái cũ (tài liệu mới là `draft`). Nhập lại thay section/task trong MỘT transaction và KHÔNG
  chạm `sd_progress`/`sd_attempts`: tiến độ bám theo `card.id` (hash nội dung) nên card không đổi giữ nguyên.
- GET  /api/admin/sd/docs               → {items: [{id, title, status, sections, cards, tasks}]}
- PUT  /api/admin/sd/docs/{id}/status   {status} → {id, status} | 404

Không đi qua hàng chờ duyệt: đây là tài liệu đọc, không phải nội dung chấm bài.
"""

from __future__ import annotations

import logging
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import delete, func, select, text
from sqlalchemy.exc import DataError, IntegrityError
from sqlalchemy.orm import Session

from app.admin_api import _BadBody, _invalid, _parse
from app.auth import CurrentUser, require_admin
from app.db import get_session
from app.sd.parser import MdError, parse_markdown, slugify
from app.tables import SdDoc, SdSection, SdTask

logger = logging.getLogger("sd")

# Đặt ở cấp router: route thêm sau này không thể quên kiểm quyền (giống app.admin_api).
router = APIRouter(prefix="/api/admin/sd", dependencies=[Depends(require_admin)])

MAX_MD_BYTES = 1_000_000
_SLUG = r"^[a-z0-9][a-z0-9-]*$"


class ImportIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str | None = Field(default=None, max_length=100, pattern=_SLUG)
    markdown: str = Field(max_length=MAX_MD_BYTES)
    status: Literal["draft", "published"] | None = None


class StatusIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["draft", "published"]


def _card_keys(sections) -> set[tuple[str, str]]:
    return {(s["id"], c["id"]) for s in sections for c in s["cards"]}


def _import(body: ImportIn, user: CurrentUser, session: Session):
    if len(body.markdown.encode("utf-8", "replace")) > MAX_MD_BYTES:
        return _invalid([f"file .md quá lớn (tối đa {MAX_MD_BYTES} byte)"])
    try:
        parsed = parse_markdown(body.markdown)  # trước khi khoá: file sai thì không giữ khoá ghi
    except MdError as exc:
        return _invalid(exc.errors)
    doc_id = body.id or slugify(parsed["title"])[:100]
    try:
        # Hai admin nhập cùng một tài liệu đúng lúc: tuần tự hoá theo id tài liệu.
        session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:k))"), {"k": f"sd_doc:{doc_id}"})
        doc = session.get(SdDoc, doc_id)
        old = set()
        if doc is not None:
            old = {
                (s.id, c["id"]) for s in session.scalars(select(SdSection).where(SdSection.doc_id == doc_id)) for c in s.cards
            }
            doc.title, doc.context = parsed["title"], parsed["context"]
            if body.status:
                doc.status = body.status
        else:
            doc = SdDoc(
                id=doc_id,
                title=parsed["title"],
                status=body.status or "draft",
                context=parsed["context"],
                created_by=user.email,
            )
            session.add(doc)
        session.flush()
        # Xoá rồi ghi lại trong cùng transaction (unique (doc_id, position) nên xoá trước).
        session.execute(delete(SdSection).where(SdSection.doc_id == doc_id))
        session.execute(delete(SdTask).where(SdTask.doc_id == doc_id))
        session.add_all(SdSection(doc_id=doc_id, **s) for s in parsed["sections"])
        session.add_all(SdTask(doc_id=doc_id, **t) for t in parsed["tasks"])
        session.flush()
        session.commit()
    except (DataError, IntegrityError) as exc:
        session.rollback()
        logger.warning("sd import rejected by DB: %s", type(exc.orig).__name__)
        return _invalid([f"DB từ chối tài liệu ({type(exc.orig).__name__}) — kiểm độ dài id và tiêu đề"])
    new = _card_keys(parsed["sections"])
    logger.info("admin %s imported sd doc %s", user.email, doc_id)
    return {
        "id": doc_id,
        "title": parsed["title"],
        "status": doc.status,
        "chapters": len({s["chapter_position"] for s in parsed["sections"]}),
        "sections": len(parsed["sections"]),
        "cards": len(new),
        "context_cards": len(parsed["context"]),
        "tasks": len(parsed["tasks"]),
        "cards_added": len(new - old),
        "cards_removed": len(old - new),
    }


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
def list_docs(session: Session = Depends(get_session)) -> dict:
    sec = (
        select(
            SdSection.doc_id.label("doc_id"),
            func.count().label("sections"),
            func.coalesce(func.sum(func.jsonb_array_length(SdSection.cards)), 0).label("cards"),
        )
        .group_by(SdSection.doc_id)
        .subquery()
    )
    tasks = select(SdTask.doc_id.label("doc_id"), func.count().label("tasks")).group_by(SdTask.doc_id).subquery()
    rows = session.execute(
        select(SdDoc.id, SdDoc.title, SdDoc.status, sec.c.sections, sec.c.cards, tasks.c.tasks)
        .outerjoin(sec, sec.c.doc_id == SdDoc.id)
        .outerjoin(tasks, tasks.c.doc_id == SdDoc.id)
        .order_by(SdDoc.created_at, SdDoc.id)
    ).all()
    return {
        "items": [
            {"id": r.id, "title": r.title, "status": r.status, "sections": r.sections or 0, "cards": int(r.cards or 0), "tasks": r.tasks or 0}
            for r in rows
        ]
    }


def _set_status(doc_id: str, body: StatusIn, session: Session):
    doc = session.get(SdDoc, doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="doc_not_found")
    doc.status = body.status
    session.commit()
    return {"id": doc_id, "status": doc.status}


@router.put("/docs/{doc_id}/status")
async def put_status(doc_id: str, request: Request, session: Session = Depends(get_session)):
    try:
        body = await _parse(request, StatusIn)
    except _BadBody as exc:
        return _invalid(exc.errors)
    return await run_in_threadpool(_set_status, doc_id, body, session)
