"""API học viên cho chế độ System Design, dưới `/api/sd` (cần đăng nhập).

- GET /api/sd/docs                                   → {items: [tóm tắt tài liệu ĐÃ PUBLISH + tiến độ của tôi + course_id],
  courses: [course published có ≥1 doc trong items]}. Course chỉ để nhóm, không đổi tập doc được xem.
- GET /api/sd/docs/{id}                              → tài liệu: section (kèm card, đã đọc, done, unlocked),
  bối cảnh (chỉ khi Phase 2 mở) và task (kèm unlocked, done, số lần thử).
- PUT /api/sd/docs/{id}/sections/{sid}/progress      {read_cards} → {read, done, next_section_id, phase2_unlocked}
  | 404. Chỉ THÊM card đã đọc (không bao giờ bỏ); id lạ (card đã bị sửa/xoá khi nhập lại) bỏ qua.
- DELETE /api/sd/docs/{id}/progress                   → 204 | 404. Đặt lại tiến độ ĐỌC của tôi cho tài liệu này;
  bài đã nộp (`sd_attempts`) giữ nguyên.

Trạng thái khoá/xong chỉ tính ở đây (server), client chỉ vẽ:
- mọi section luôn mở (issue #66: học section nào trước cũng được); `unlocked` vẫn trả về (luôn true) để app cũ
  không vỡ. `done` = mọi card HIỆN HÀNH đã đọc.
- Phase 2 mở khi mọi section `done`; khi đó MỌI task mở cùng lúc (không khoá tuần tự), làm task nào trước cũng được.
  Task `done` khi có ≥1 lần thử.

Không bao giờ trả `rubric`/từ khoá của task: chúng là dữ liệu chấm, chỉ server đọc.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from sqlalchemy import delete, func, select, text
from sqlalchemy.orm import Session

from app.auth import CurrentUser, current_user
from app.db import get_session
from app.sd.courses import DOC_ORDER
from app.tables import Course, SdAttempt, SdDoc, SdProgress, SdSection, SdTask

router = APIRouter(prefix="/api/sd")

MAX_READ_IDS = 200  # = MAX_CARDS_PER_SECTION của parser: không thể đọc nhiều hơn số card có thể có
_CardId = Annotated[str, StringConstraints(max_length=20)]


class ProgressIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    read_cards: list[_CardId] = Field(max_length=MAX_READ_IDS)


def _published(session: Session, doc_id: str) -> SdDoc:
    doc = session.get(SdDoc, doc_id)
    if doc is None or doc.status != "published":
        raise HTTPException(status_code=404, detail="doc_not_found")
    return doc


def _sections_state(sections: list[SdSection], read_by_section: dict[str, set[str]]) -> list[dict]:
    """Section theo thứ tự + trạng thái. Mọi section đều mở (không khoá tuần tự)."""
    out = []
    for s in sections:
        ids = [c["id"] for c in s.cards]
        have = read_by_section.get(s.id, set())
        read = [i for i in ids if i in have]
        done = bool(ids) and len(read) == len(ids)
        out.append(
            {
                "id": s.id,
                "position": s.position,
                "chapter": s.chapter,
                "chapter_position": s.chapter_position,
                "title": s.title,
                "cards": s.cards,
                "read": read,
                "done": done,
                "unlocked": True,
            }
        )
    return out


def _tasks_state(tasks: list[SdTask], attempts: dict[str, int], phase2: bool) -> list[dict]:
    out = []
    for t in tasks:
        n = attempts.get(t.id, 0)
        unlocked = phase2  # task không khoá tuần tự: Phase 2 mở là mọi task mở
        out.append(
            {
                "id": t.id,
                "position": t.position,
                "name": t.name,
                "unlocked": unlocked,
                "done": n >= 1,
                "attempts": n,
                # Đề và gợi ý chỉ lộ khi task đã mở; rubric/từ khoá không bao giờ ra khỏi server.
                "prompt": t.prompt if unlocked else None,
                "hints": t.hints if unlocked else [],
                "ref_section_id": t.ref_section_id if unlocked else None,
            }
        )
    return out


def _load(session: Session, user_id: int, doc_ids: list[str]):
    """Gom theo lô (không N+1): section, task, tiến độ đọc và số lần thử của user cho các tài liệu."""
    sections: dict[str, list[SdSection]] = {d: [] for d in doc_ids}
    for s in session.scalars(select(SdSection).where(SdSection.doc_id.in_(doc_ids)).order_by(SdSection.position)):
        sections[s.doc_id].append(s)
    tasks: dict[str, list[SdTask]] = {d: [] for d in doc_ids}
    for t in session.scalars(select(SdTask).where(SdTask.doc_id.in_(doc_ids)).order_by(SdTask.position)):
        tasks[t.doc_id].append(t)
    read: dict[str, dict[str, set[str]]] = {d: {} for d in doc_ids}
    for p in session.scalars(select(SdProgress).where(SdProgress.user_id == user_id, SdProgress.doc_id.in_(doc_ids))):
        read[p.doc_id][p.section_id] = set(p.read_cards)
    attempts: dict[str, dict[str, int]] = {d: {} for d in doc_ids}
    rows = session.execute(
        select(SdAttempt.doc_id, SdAttempt.task_id, func.count())
        .where(SdAttempt.user_id == user_id, SdAttempt.doc_id.in_(doc_ids))
        .group_by(SdAttempt.doc_id, SdAttempt.task_id)
    )
    for d, t, n in rows:
        attempts[d][t] = n
    return sections, tasks, read, attempts


@router.get("/docs")
def list_docs(user: CurrentUser = Depends(current_user), session: Session = Depends(get_session)) -> dict:
    docs = list(session.scalars(select(SdDoc).where(SdDoc.status == "published").order_by(*DOC_ORDER)).all())
    course_ids = {d.course_id for d in docs if d.course_id}
    courses = (
        {c.id: c for c in session.scalars(select(Course).where(Course.id.in_(course_ids), Course.status == "published"))}
        if course_ids
        else {}
    )
    # Doc thuộc course published đứng trước (theo course rồi DOC_ORDER); sort ổn định giữ DOC_ORDER trong course.
    grouped = sorted((d for d in docs if d.course_id in courses), key=lambda d: (courses[d.course_id].position, d.course_id))
    rest = sorted((d for d in docs if d.course_id not in courses), key=lambda d: (d.created_at, d.id))
    docs = grouped + rest
    shown = sorted({d.course_id for d in grouped}, key=lambda i: (courses[i].position, i))
    ids = [d.id for d in docs]
    sections, tasks, read, attempts = _load(session, user.id, ids)
    items = []
    for d in docs:
        sec = _sections_state(sections[d.id], read[d.id])
        phase1 = bool(sec) and all(s["done"] for s in sec)
        tsk = _tasks_state(tasks[d.id], attempts[d.id], phase1)
        items.append(
            {
                "id": d.id,
                "title": d.title,
                "sections": len(sec),
                "sections_done": sum(s["done"] for s in sec),
                "cards": sum(len(s["cards"]) for s in sec),
                "cards_read": sum(len(s["read"]) for s in sec),
                "phase2_unlocked": phase1,
                "tasks": len(tsk),
                "tasks_done": sum(t["done"] for t in tsk),
                "course_id": d.course_id if d.course_id in courses else None,
            }
        )
    return {
        "items": items,
        "courses": [
            {"id": i, "title": courses[i].title, "skills": list(courses[i].skills), "domain": courses[i].domain}
            for i in shown
        ],
    }


@router.get("/docs/{doc_id}")
def get_doc(doc_id: str, user: CurrentUser = Depends(current_user), session: Session = Depends(get_session)) -> dict:
    doc = _published(session, doc_id)
    sections, tasks, read, attempts = _load(session, user.id, [doc_id])
    sec = _sections_state(sections[doc_id], read[doc_id])
    phase2 = bool(sec) and all(s["done"] for s in sec)
    return {
        "id": doc.id,
        "title": doc.title,
        "sections": sec,
        "phase2_unlocked": phase2,
        "context": doc.context if phase2 else [],
        "tasks": _tasks_state(tasks[doc_id], attempts[doc_id], phase2),
    }


def _lock_progress(session: Session, user_id: int, doc_id: str, section_id: str) -> None:
    session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:k))"), {"k": f"sd_prog:{user_id}:{doc_id}:{section_id}"})


@router.put("/docs/{doc_id}/sections/{section_id}/progress")
def put_progress(
    doc_id: str,
    section_id: str,
    body: ProgressIn,
    user: CurrentUser = Depends(current_user),
    session: Session = Depends(get_session),
) -> dict:
    _published(session, doc_id)
    # Hai PUT đồng thời của cùng user/section: tuần tự hoá để hợp (union) không làm mất card của nhau.
    _lock_progress(session, user.id, doc_id, section_id)
    sections, _, read, _ = _load(session, user.id, [doc_id])
    state = _sections_state(sections[doc_id], read[doc_id])
    target = next((s for s in state if s["id"] == section_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail="section_not_found")

    valid = {c["id"] for c in target["cards"]}
    row = session.get(SdProgress, (user.id, doc_id, section_id))
    merged = list(row.read_cards) if row else []
    seen = set(merged)
    for cid in body.read_cards:
        if cid in valid and cid not in seen:
            merged.append(cid)
            seen.add(cid)
    if row is None:
        session.add(SdProgress(user_id=user.id, doc_id=doc_id, section_id=section_id, read_cards=merged))
    else:
        row.read_cards = merged
    session.commit()

    read[doc_id][section_id] = seen
    state = _sections_state(sections[doc_id], read[doc_id])
    i = next(k for k, s in enumerate(state) if s["id"] == section_id)
    now = state[i]
    nxt = state[i + 1]["id"] if now["done"] and i + 1 < len(state) else None
    return {
        "section_id": section_id,
        "read": now["read"],
        "done": now["done"],
        "next_section_id": nxt,
        "phase2_unlocked": all(s["done"] for s in state),
    }


@router.delete("/docs/{doc_id}/progress", status_code=204)
def reset_progress(doc_id: str, user: CurrentUser = Depends(current_user), session: Session = Depends(get_session)) -> Response:
    _published(session, doc_id)
    # Khoá MỌI section của doc (cùng khoá với PUT), thứ tự cố định nên không deadlock: PUT nào cũng xong hẳn trước
    # hoặc chạy hẳn sau lần xoá, kể cả PUT đầu tiên của một section chưa có dòng tiến độ.
    section_ids = sorted(session.scalars(select(SdSection.id).where(SdSection.doc_id == doc_id)))
    for sid in section_ids:
        _lock_progress(session, user.id, doc_id, sid)
    session.execute(delete(SdProgress).where(SdProgress.user_id == user.id, SdProgress.doc_id == doc_id))
    session.commit()
    return Response(status_code=204)
