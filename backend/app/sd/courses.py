"""Khoá học (course) nhóm tài liệu System Design — phase 1 issue #56. Dùng chung cho MCP (và API sau này).

- Course CHỈ để nhóm khi hiển thị: quyền xem doc vẫn theo `sd_docs.status` (sd/learner.py). Course không published
  thì doc của nó hiện ở nhóm "Khác".
- Xoá = xoá mềm (`archived`): doc giữ `course_id`, khôi phục course là doc về đúng nhóm.
- Thứ tự doc trong course: `DOC_ORDER` — API học viên dùng đúng hằng này để hai bên không lệch.
- Hợp đồng transaction như `sd/docs.py`: hàm ghi tự commit, rollback khi lỗi; caller dùng session riêng mỗi lần gọi.
"""

from __future__ import annotations

import logging
from typing import Any

from sqlalchemy import nulls_last, select, text
from sqlalchemy.orm import Session

from app.sd.docs import STATUSES, SdDocError, SdDocNotFound, _check_id
from app.sd.docs import _lock as _lock_doc
from app.tables import Course, SdDoc

logger = logging.getLogger("sd")

CREATE_STATUSES = ("draft", "published")
EDITABLE = ("title", "skills", "domain", "position")
MAX_TITLE = 200
MAX_DOMAIN = 100
MAX_SKILLS = 20
MAX_SKILL = 40
MAX_POSITION = 10_000

# Thứ tự doc trong một course: vị trí đã đặt (chưa đặt thì cuối), rồi ngày tạo, rồi id.
DOC_ORDER = (nulls_last(SdDoc.course_position.asc()), SdDoc.created_at, SdDoc.id)


class CourseNotFound(SdDocError):
    def __init__(self, course_id: str):
        super().__init__([f'không có course id "{course_id}"'])


def _lock(session: Session, course_id: str) -> None:
    session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:k))"), {"k": f"course:{course_id}"})


def _position(value: Any, field: str = "position") -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= MAX_POSITION:
        raise SdDocError([f"{field} phải là số nguyên 0..{MAX_POSITION}"])
    return value


def _fields(changes: Any) -> dict:
    """Chuẩn hoá các field sửa được; key lạ hoặc sai kiểu → lỗi đọc được."""
    if not isinstance(changes, dict) or not changes:
        raise SdDocError([f"changes phải là object có ít nhất một trong {list(EDITABLE)}"])
    unknown = sorted(set(changes) - set(EDITABLE))
    if unknown:
        raise SdDocError([f"không sửa được {unknown} — chỉ {list(EDITABLE)}"])
    out: dict = {}
    if "title" in changes:
        title = changes["title"]
        if not isinstance(title, str) or not title.strip() or len(title) > MAX_TITLE:
            raise SdDocError([f"title phải là chuỗi không rỗng, tối đa {MAX_TITLE} ký tự"])
        out["title"] = title.strip()
    if "skills" in changes:
        skills = changes["skills"]
        if not isinstance(skills, list) or len(skills) > MAX_SKILLS:
            raise SdDocError([f"skills phải là danh sách tối đa {MAX_SKILLS} chuỗi"])
        seen: dict[str, None] = {}
        for s in skills:
            if not isinstance(s, str) or not s.strip() or len(s) > MAX_SKILL:
                raise SdDocError([f"mỗi skill là chuỗi không rỗng, tối đa {MAX_SKILL} ký tự"])
            seen.setdefault(s.strip(), None)
        out["skills"] = list(seen)
    if "domain" in changes:
        domain = changes["domain"]
        if domain is not None and (not isinstance(domain, str) or len(domain) > MAX_DOMAIN):
            raise SdDocError([f"domain là chuỗi tối đa {MAX_DOMAIN} ký tự hoặc null"])
        out["domain"] = (domain.strip() or None) if domain is not None else None
    if "position" in changes:
        out["position"] = _position(changes["position"])
    return out


def _docs_of(session: Session, course_ids: list[str]) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = {cid: [] for cid in course_ids}
    if not course_ids:
        return out
    rows = session.execute(
        select(SdDoc.course_id, SdDoc.id, SdDoc.title, SdDoc.status, SdDoc.course_position)
        .where(SdDoc.course_id.in_(course_ids))
        .order_by(SdDoc.course_id, *DOC_ORDER)
    ).all()
    for course_id, doc_id, title, status, position in rows:
        out[course_id].append({"id": doc_id, "title": title, "status": status, "course_position": position})
    return out


def _as_dict(c: Course, docs: list[dict] | None = None) -> dict:
    out = {"id": c.id, "title": c.title, "skills": list(c.skills), "domain": c.domain, "status": c.status, "position": c.position}
    if docs is not None:
        out["docs"] = docs
    return out


def list_courses(session: Session, *, include_archived: bool = False) -> list[dict]:
    query = select(Course).order_by(Course.position, Course.id)
    if not include_archived:
        query = query.where(Course.status != "archived")
    courses = session.scalars(query).all()
    docs = _docs_of(session, [c.id for c in courses])
    return [_as_dict(c, docs[c.id]) for c in courses]


def create_course(
    session: Session,
    *,
    course_id: str,
    title: str,
    actor: str,
    skills: list[str] | None = None,
    domain: str | None = None,
    status: str = "draft",
    position: int = 0,
) -> dict:
    _check_id(course_id)
    if status not in CREATE_STATUSES:
        raise SdDocError([f"status khi tạo chỉ nhận {list(CREATE_STATUSES)}"])
    # Chỉ None mới là "không có skill": "", 0, False… phải bị _fields từ chối, không lặng lẽ thành [].
    fields = _fields({"title": title, "skills": [] if skills is None else skills, "domain": domain, "position": position})
    _lock(session, course_id)
    existing = session.get(Course, course_id, populate_existing=True)
    if existing is not None:
        session.rollback()
        raise SdDocError([f'đã có course id "{course_id}" (trạng thái {existing.status}) — sửa bằng update hoặc khôi phục bằng set_status'])
    course = Course(id=course_id, status=status, **fields)
    session.add(course)
    session.commit()
    logger.info("%s created course %s", actor, course_id)
    return _as_dict(course, [])


def update_course(session: Session, course_id: str, changes: Any, *, actor: str) -> dict:
    _check_id(course_id)
    fields = _fields(changes)
    _lock(session, course_id)
    course = session.get(Course, course_id, populate_existing=True)
    if course is None:
        session.rollback()
        raise CourseNotFound(course_id)
    for k, v in fields.items():
        setattr(course, k, v)
    session.commit()
    logger.info("%s updated course %s: %s", actor, course_id, sorted(fields))
    return _as_dict(course, _docs_of(session, [course_id])[course_id])


def set_course_status(session: Session, course_id: str, status: str, *, actor: str) -> dict:
    if status not in STATUSES:
        raise SdDocError([f"status phải là một trong {list(STATUSES)}"])
    _check_id(course_id)
    _lock(session, course_id)
    course = session.get(Course, course_id, populate_existing=True)
    if course is None:
        session.rollback()
        raise CourseNotFound(course_id)
    previous = course.status
    course.status = status  # doc giữ course_id: archived là xoá mềm, khôi phục là về đúng nhóm
    session.commit()
    logger.info("%s set course %s status %s -> %s", actor, course_id, previous, status)
    return {"id": course_id, "status": status, "previous": previous}


def assign_doc(session: Session, doc_id: str, course_id: str | None, *, actor: str, position: int | None = None) -> dict:
    """Gán doc vào course (hoặc gỡ: course_id=None). Không gán vào course đã xoá mềm."""
    _check_id(doc_id)
    if position is not None:
        position = _position(position)  # validate trước khi giữ khoá
    if course_id is not None:
        _check_id(course_id)
        _lock(session, course_id)  # khoá course trước doc: không gán vào course đang bị archive cùng lúc
    _lock_doc(session, doc_id)  # cùng khoá với nhập/sửa doc
    if course_id is not None:
        course = session.get(Course, course_id, populate_existing=True)
        if course is None:
            session.rollback()
            raise CourseNotFound(course_id)
        if course.status == "archived":
            session.rollback()
            raise SdDocError([f'course "{course_id}" đã xoá mềm — khôi phục bằng set_status trước khi gán doc'])
    doc = session.get(SdDoc, doc_id, populate_existing=True)
    if doc is None:
        session.rollback()
        raise SdDocNotFound(doc_id)
    previous = doc.course_id
    doc.course_id = course_id
    doc.course_position = position if course_id is not None else None
    session.commit()
    logger.info("%s assigned sd doc %s: %s -> %s", actor, doc_id, previous, course_id)
    return {"doc_id": doc_id, "course_id": course_id, "course_position": doc.course_position, "previous_course_id": previous}
