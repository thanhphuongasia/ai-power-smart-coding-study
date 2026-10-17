"""Nghiệp vụ tài liệu System Design — MỘT đường cho API admin (`sd/admin.py`), MCP (`mcp_server.py`) và CLI
(`sd/import_file.py`).

- Nhập: parse TRƯỚC khi khoá (file sai thì không giữ khoá), khoá theo id tài liệu, xoá-rồi-ghi section/task trong
  một transaction, KHÔNG chạm `sd_progress`/`sd_attempts` (tiến độ bám `card.id` = hash nội dung). Luôn lưu
  markdown gốc vào `sd_docs.source_md` để sửa lại được.
- `mode`: `create` (id đã có → lỗi, kể cả doc đã xoá mềm), `replace` (id phải có), `upsert` (hành vi cũ của API).
- Xoá = xoá mềm: `status='archived'`. Học viên chỉ thấy `published` (sd/learner.py), bài nộp và tiến độ còn nguyên;
  khôi phục bằng `set_status`.

Hợp đồng transaction: hàm ghi TỰ commit, và rollback khi lỗi. Caller truyền session riêng cho mỗi lần gọi, không
có việc chưa commit (MCP `open_session`, CLI, `get_session` của FastAPI đều vậy).
"""

from __future__ import annotations

import hashlib
import logging
import re
from typing import Any

from sqlalchemy import delete, func, select, text
from sqlalchemy.exc import DataError, IntegrityError
from sqlalchemy.orm import Session

from app.sd.parser import MdError, parse_markdown, slugify
from app.tables import SdDoc, SdSection, SdTask

logger = logging.getLogger("sd")

MAX_MD_BYTES = 1_000_000
STATUSES = ("draft", "published", "archived")
IMPORT_STATUSES = ("draft", "published")  # nhập không đặt được archived: xoá đi đường set_status
MODES = ("create", "replace", "upsert")
MAX_EDITS = 50
MAX_EDIT_CHARS = 20_000
_SLUG = re.compile(r"[a-z0-9][a-z0-9-]*")


class SdDocError(Exception):
    """Lỗi nghiệp vụ, `errors` đọc được cho người/Claude sửa."""

    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors))
        self.errors = errors


class SdDocNotFound(SdDocError):
    def __init__(self, doc_id: str):
        super().__init__([f'không có tài liệu id "{doc_id}"'])


def revision(source_md: str | None) -> str | None:
    """Dấu phiên bản của markdown gốc: `replace` truyền lại để không ghi đè bản ai đó vừa sửa."""
    if source_md is None:
        return None
    return hashlib.sha256(source_md.encode("utf-8", "replace")).hexdigest()[:16]


def _lock(session: Session, doc_id: str) -> None:
    # Cùng khoá với mọi lần nhập/sửa tài liệu này. Khoá giao dịch của Postgres lấy lại được trong cùng session.
    session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:k))"), {"k": f"sd_doc:{doc_id}"})


def _check_id(doc_id: str) -> None:
    if not isinstance(doc_id, str) or len(doc_id) > 100 or not _SLUG.fullmatch(doc_id):
        raise SdDocError(["id tài liệu chỉ gồm a-z, 0-9, '-', bắt đầu bằng chữ/số, tối đa 100 ký tự"])


def _card_keys(sections) -> set[tuple[str, str]]:
    return {(s["id"], c["id"]) for s in sections for c in s["cards"]}


def import_markdown(
    session: Session,
    markdown: str,
    *,
    actor: str,
    doc_id: str | None = None,
    status: str | None = None,
    mode: str = "upsert",
    dry_run: bool = False,
    base_revision: str | None = None,
) -> dict:
    """Nhập (hoặc nhập lại) một tài liệu. Ghi thật thì commit; `dry_run` chỉ parse + so với bản hiện có."""
    if mode not in MODES:
        raise SdDocError([f"mode phải là một trong {list(MODES)}"])
    if status is not None and status not in IMPORT_STATUSES:
        raise SdDocError([f"status khi nhập chỉ nhận {list(IMPORT_STATUSES)} (xoá dùng set_status archived)"])
    if not isinstance(markdown, str):
        raise SdDocError(["markdown phải là chuỗi"])
    if len(markdown.encode("utf-8", "replace")) > MAX_MD_BYTES:
        raise SdDocError([f"file .md quá lớn (tối đa {MAX_MD_BYTES} byte)"])
    if doc_id is not None:
        _check_id(doc_id)
    try:
        parsed = parse_markdown(markdown)  # trước khi khoá: file sai thì không giữ khoá ghi
    except MdError as exc:
        raise SdDocError(exc.errors) from None
    doc_id = doc_id or slugify(parsed["title"])[:100]

    try:
        _lock(session, doc_id)  # hai lần nhập cùng tài liệu đúng lúc: tuần tự hoá theo id
        doc = session.get(SdDoc, doc_id, populate_existing=True)  # đọc lại SAU khoá, không lấy bản cũ trong session
        if mode == "create" and doc is not None:
            raise SdDocError(
                [f'đã có tài liệu id "{doc_id}" (trạng thái {doc.status}) — sửa bằng replace/edit, '
                 "khôi phục bằng set_status, hoặc chọn id khác"]
            )
        if mode == "replace" and doc is None:
            raise SdDocNotFound(doc_id)
        if base_revision is not None and doc is not None and base_revision != revision(doc.source_md):
            raise SdDocError(["tài liệu vừa được sửa sau lần bạn đọc (revision khác) — đọc lại rồi sửa"])
        old: set[tuple[str, str]] = set()
        if doc is not None:
            old = {
                (s.id, c["id"]) for s in session.scalars(select(SdSection).where(SdSection.doc_id == doc_id)) for c in s.cards
            }
        new = _card_keys(parsed["sections"])
        final_status = status or (doc.status if doc is not None else "draft")
        summary = {
            "id": doc_id,
            "title": parsed["title"],
            "status": final_status,
            "chapters": len({s["chapter_position"] for s in parsed["sections"]}),
            "sections": len(parsed["sections"]),
            "cards": len(new),
            "context_cards": len(parsed["context"]),
            "tasks": len(parsed["tasks"]),
            "cards_added": len(new - old),
            "cards_removed": len(old - new),
        }
        if dry_run:
            # Không rollback: chưa ghi gì, và rollback sẽ huỷ cả việc chưa commit của caller. Khoá nhả khi
            # caller đóng session (MCP/CLI/API đều mở session riêng cho mỗi lần gọi).
            return {**summary, "dry_run": True}

        if doc is not None:
            doc.title, doc.context, doc.source_md = parsed["title"], parsed["context"], markdown
            if status:
                doc.status = status
        else:
            doc = SdDoc(
                id=doc_id,
                title=parsed["title"],
                status=final_status,
                context=parsed["context"],
                source_md=markdown,
                created_by=actor,
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
    except SdDocError:
        session.rollback()
        raise
    except (DataError, IntegrityError) as exc:
        session.rollback()
        logger.warning("sd import rejected by DB: %s", type(exc.orig).__name__)
        raise SdDocError([f"DB từ chối tài liệu ({type(exc.orig).__name__}) — kiểm độ dài id và tiêu đề"]) from None
    logger.info("%s imported sd doc %s (%s)", actor, doc_id, mode)
    return summary


def apply_edits(source: str, edits: Any) -> str:
    """Thay từng đoạn `old_text` (phải xuất hiện ĐÚNG một lần) bằng `new_text`, theo thứ tự. Hàm thuần."""
    if not isinstance(edits, list) or not edits:
        raise SdDocError(["edits phải là danh sách có ít nhất 1 phần tử {old_text, new_text}"])
    if len(edits) > MAX_EDITS:
        raise SdDocError([f"tối đa {MAX_EDITS} edit mỗi lần"])
    errors: list[str] = []
    out = source
    for i, e in enumerate(edits, 1):
        if not isinstance(e, dict) or set(e) != {"old_text", "new_text"}:
            errors.append(f"edit {i}: phải có đúng hai khoá old_text, new_text")
            continue
        old, new = e["old_text"], e["new_text"]
        if not isinstance(old, str) or not isinstance(new, str) or not old:
            errors.append(f"edit {i}: old_text (không rỗng) và new_text phải là chuỗi")
            continue
        if len(old) > MAX_EDIT_CHARS or len(new) > MAX_EDIT_CHARS:
            errors.append(f"edit {i}: mỗi chuỗi tối đa {MAX_EDIT_CHARS} ký tự")
            continue
        first = out.find(old)
        if first < 0:
            errors.append(f"edit {i}: không tìm thấy old_text trong markdown hiện tại")
            continue
        if out.find(old, first + 1) >= 0:  # bắt cả lần xuất hiện chồng lấn
            errors.append(f"edit {i}: old_text xuất hiện nhiều hơn một lần — thêm ngữ cảnh cho duy nhất")
            continue
        out = out[:first] + new + out[first + len(old):]
    if errors:
        raise SdDocError(errors)
    return out


def edit_doc(session: Session, doc_id: str, edits: Any, *, actor: str, dry_run: bool = False) -> dict:
    """Sửa theo đoạn trên markdown gốc rồi nhập lại (giữ status, giữ tiến độ card không đổi)."""
    _check_id(doc_id)
    _lock(session, doc_id)  # khoá TRƯỚC khi đọc source_md: hai lần sửa đồng thời không mất bản của nhau
    doc = session.get(SdDoc, doc_id, populate_existing=True)
    if doc is None:
        session.rollback()
        raise SdDocNotFound(doc_id)
    if doc.source_md is None:
        session.rollback()
        raise SdDocError(["tài liệu này nhập trước khi có lưu markdown gốc — gửi toàn bộ markdown bằng replace"])
    try:
        new_md = apply_edits(doc.source_md, edits)
    except SdDocError:
        session.rollback()
        raise
    return import_markdown(session, new_md, actor=actor, doc_id=doc_id, mode="replace", dry_run=dry_run)


def list_docs(session: Session, *, include_archived: bool = False) -> list[dict]:
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
    query = (
        select(SdDoc.id, SdDoc.title, SdDoc.status, sec.c.sections, sec.c.cards, tasks.c.tasks, SdDoc.source_md.isnot(None))
        .outerjoin(sec, sec.c.doc_id == SdDoc.id)
        .outerjoin(tasks, tasks.c.doc_id == SdDoc.id)
        .order_by(SdDoc.created_at, SdDoc.id)
    )
    if not include_archived:
        query = query.where(SdDoc.status != "archived")
    return [
        {
            "id": r[0],
            "title": r[1],
            "status": r[2],
            "sections": r[3] or 0,
            "cards": int(r[4] or 0),
            "tasks": r[5] or 0,
            "has_markdown": bool(r[6]),
        }
        for r in session.execute(query).all()
    ]


def get_doc(session: Session, doc_id: str) -> dict:
    """Meta + mục lục + task + markdown gốc (None nếu nhập trước khi có cột source_md)."""
    _check_id(doc_id)
    _lock(session, doc_id)  # markdown và mục lục cùng một lần nhập (không lẫn với lần nhập đang commit dở)
    doc = session.get(SdDoc, doc_id, populate_existing=True)
    if doc is None:
        raise SdDocNotFound(doc_id)
    sections = session.scalars(select(SdSection).where(SdSection.doc_id == doc_id).order_by(SdSection.position)).all()
    tasks = session.scalars(select(SdTask).where(SdTask.doc_id == doc_id).order_by(SdTask.position)).all()
    return {
        "id": doc.id,
        "title": doc.title,
        "status": doc.status,
        "revision": revision(doc.source_md),
        "outline": [
            {"chapter": s.chapter, "section_id": s.id, "title": s.title, "cards": len(s.cards)} for s in sections
        ],
        "context_cards": len(doc.context),
        "tasks": [
            {"id": t.id, "name": t.name, "prompt": t.prompt, "hints": t.hints, "rubric_items": len(t.rubric)}
            for t in tasks
        ],
        "markdown": doc.source_md,
    }


def set_status(session: Session, doc_id: str, status: str, *, actor: str) -> dict:
    if status not in STATUSES:
        raise SdDocError([f"status phải là một trong {list(STATUSES)}"])
    _check_id(doc_id)
    _lock(session, doc_id)
    doc = session.get(SdDoc, doc_id, populate_existing=True)
    if doc is None:
        session.rollback()
        raise SdDocNotFound(doc_id)
    previous = doc.status
    doc.status = status
    session.commit()
    logger.info("%s set sd doc %s status %s -> %s", actor, doc_id, previous, status)
    return {"id": doc_id, "status": status, "previous": previous}
