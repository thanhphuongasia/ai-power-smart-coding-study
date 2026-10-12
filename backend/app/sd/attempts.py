"""Lần thử bài thực chiến của học viên, dưới `/api/sd` (cần đăng nhập).

- POST /api/sd/docs/{id}/tasks/{tid}/attempts  {answer} → 201 {attempt} | 404 | 409 task_locked | 422 | 429 attempt_limit
- GET  /api/sd/docs/{id}/tasks/{tid}/attempts  ?limit → {items: [attempt, mới nhất trước]}

Mỗi lần nộp là MỘT dòng (`n` = 1, 2, 3… theo user/task), không bao giờ ghi đè. Server chấm từ khoá ngay
(`status=auto`). Khi Claude chấm sâu qua MCP, dòng đó thành `status=reviewed` kèm feedback và từng ý
đạt/chưa; API chỉ trả MỘT bản: reviewed nếu có, không thì auto (`source` cho biết là bản nào).
Học viên chỉ đọc được lần thử của chính mình: mọi truy vấn lọc theo `user.id` của phiên đăng nhập.

Trả `items: [{text, ok, note}]` (nội dung ý rubric đã chấm), KHÔNG bao giờ trả từ khoá.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.auth import CurrentUser, current_user
from app.db import get_session
from app.progress import _bad_text
from app.sd.evaluator import Evaluator, get_evaluator
from app.sd.learner import _load, _published, _sections_state, _tasks_state
from app.tables import SdAttempt, SdSection, SdTask

router = APIRouter(prefix="/api/sd")

MAX_ANSWER_BYTES = 8 * 1024
MAX_ATTEMPTS_PER_DAY = 20  # mỗi (user, task) trong 24 giờ gần nhất
MAX_LIST = 50


class AttemptIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    answer: str = Field(min_length=1, max_length=MAX_ANSWER_BYTES)

    @field_validator("answer")
    @classmethod
    def _clean(cls, v: str) -> str:
        if _bad_text(v):
            raise ValueError("không được chứa ký tự NUL hoặc ký tự không hợp lệ (surrogate)")
        if not v.strip():
            raise ValueError("câu trả lời trống")
        if len(v.encode("utf-8")) > MAX_ANSWER_BYTES:
            raise ValueError(f"tối đa {MAX_ANSWER_BYTES} byte")
        return v


def attempt_view(a: SdAttempt, rubric_texts: list[str]) -> dict:
    """Một bản duy nhất cho học viên: reviewed (Claude/người chấm) thắng auto (từ khoá)."""
    if a.status == "reviewed":
        items = [{"text": v["text"], "ok": bool(v["ok"]), "note": v.get("note", "")} for v in (a.verdicts or [])]
        source = "reviewed"
    else:
        hits = (a.auto_result or {}).get("hits", [])
        items = [{"text": t, "ok": bool(hits[i]) if i < len(hits) else False, "note": ""} for i, t in enumerate(rubric_texts)]
        source = "auto"
    ok = sum(i["ok"] for i in items)
    return {
        "id": a.id,
        "n": a.n,
        "answer": a.answer,
        "created_at": a.created_at.isoformat() if a.created_at else None,
        "source": source,
        "score": round(100 * ok / len(items)) if items else 0,
        "items": items,
        "feedback": a.feedback if source == "reviewed" else None,
        "reviewed_at": a.reviewed_at.isoformat() if a.reviewed_at else None,
    }


def _task(session: Session, doc_id: str, task_id: str) -> SdTask:
    t = session.get(SdTask, (doc_id, task_id))
    if t is None:
        raise HTTPException(status_code=404, detail="task_not_found")
    return t


@router.post("/docs/{doc_id}/tasks/{task_id}/attempts", status_code=201)
def submit_attempt(
    doc_id: str,
    task_id: str,
    body: AttemptIn,
    user: CurrentUser = Depends(current_user),
    session: Session = Depends(get_session),
    evaluator: Evaluator = Depends(get_evaluator),
) -> dict:
    _published(session, doc_id)
    task = _task(session, doc_id, task_id)
    # Tuần tự hoá các lần nộp của cùng user/task: cấp `n` không trùng (unique chỉ là lưới an toàn cuối).
    session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:k))"), {"k": f"sd_att:{user.id}:{doc_id}:{task_id}"})

    sections, tasks, read, attempts = _load(session, user.id, [doc_id])
    sec = _sections_state(sections[doc_id], read[doc_id])
    phase2 = bool(sec) and all(s["done"] for s in sec)
    state = next(t for t in _tasks_state(tasks[doc_id], attempts[doc_id], phase2) if t["id"] == task_id)
    if not state["unlocked"]:
        raise HTTPException(status_code=409, detail="task_locked")

    since = datetime.now(timezone.utc) - timedelta(days=1)
    recent = session.scalar(
        select(func.count()).select_from(SdAttempt).where(
            SdAttempt.user_id == user.id,
            SdAttempt.doc_id == doc_id,
            SdAttempt.task_id == task_id,
            SdAttempt.created_at >= since,
        )
    )
    if recent >= MAX_ATTEMPTS_PER_DAY:
        raise HTTPException(status_code=429, detail="attempt_limit")

    n = (
        session.scalar(
            select(func.coalesce(func.max(SdAttempt.n), 0)).where(
                SdAttempt.user_id == user.id, SdAttempt.doc_id == doc_id, SdAttempt.task_id == task_id
            )
        )
        + 1
    )
    row = SdAttempt(
        user_id=user.id,
        doc_id=doc_id,
        task_id=task_id,
        n=n,
        answer=body.answer,
        auto_result=evaluator.evaluate(body.answer, task.rubric),
        status="auto",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return {"attempt": attempt_view(row, [r["text"] for r in task.rubric])}


@router.get("/docs/{doc_id}/tasks/{task_id}/attempts")
def list_attempts(
    doc_id: str,
    task_id: str,
    limit: int = Query(default=20, ge=1, le=MAX_LIST),
    user: CurrentUser = Depends(current_user),
    session: Session = Depends(get_session),
) -> dict:
    _published(session, doc_id)
    task = _task(session, doc_id, task_id)
    rows = session.scalars(
        select(SdAttempt)
        .where(SdAttempt.user_id == user.id, SdAttempt.doc_id == doc_id, SdAttempt.task_id == task_id)
        .order_by(SdAttempt.n.desc())
        .limit(limit)
    ).all()
    texts = [r["text"] for r in task.rubric]
    return {"items": [attempt_view(a, texts) for a in rows]}


# --- Chấm sâu qua MCP (Claude) --------------------------------------------------------------
# Các hàm dưới đây chỉ được gọi từ tool MCP (`app/mcp_server.py`), sau `authorize_sub`: MCP là đường của
# admin đã được cấp quyền, KHÔNG phải đường của học viên. Học viên chỉ đi qua các route ở trên (luôn lọc
# theo `user.id` của mình), nên không có đường nào cho học viên A đọc bài của học viên B.

MAX_FEEDBACK_CHARS = 4000
MAX_NOTE_CHARS = 500
MAX_QUEUE = 50
PREVIEW_CHARS = 200
MAX_REFERENCE_CARDS = 30
MAX_REFERENCE_CHARS = 2000


class SdError(Exception):
    """Lỗi nghiệp vụ của tool chấm; MCP đổi thành ToolError để Claude đọc được."""


def review_queue(
    session: Session, *, doc_id: str | None, task_id: str | None, status: str | None, limit: int
) -> list[dict]:
    """Lần thử cần chấm, CŨ NHẤT TRƯỚC (hàng đợi): mặc định chỉ bản `auto` chưa ai chấm sâu."""
    if status not in (None, "auto", "reviewed"):
        raise SdError("status chỉ nhận 'auto' (chưa chấm sâu), 'reviewed' hoặc bỏ trống (tất cả)")
    q = select(SdAttempt).order_by(SdAttempt.created_at, SdAttempt.id).limit(max(1, min(limit, MAX_QUEUE)))
    if doc_id:
        q = q.where(SdAttempt.doc_id == doc_id)
    if task_id:
        q = q.where(SdAttempt.task_id == task_id)
    if status:
        q = q.where(SdAttempt.status == status)
    rows = session.scalars(q).all()
    names = {
        (t.doc_id, t.id): t.name
        for t in session.scalars(select(SdTask).where(SdTask.doc_id.in_({r.doc_id for r in rows})))
    }
    return [
        {
            "attempt_id": a.id,
            "doc_id": a.doc_id,
            "task_id": a.task_id,
            "task_name": names.get((a.doc_id, a.task_id), ""),
            "learner_id": a.user_id,
            "n": a.n,
            "status": a.status,
            "auto_score": (a.auto_result or {}).get("score", 0),
            "created_at": a.created_at.isoformat() if a.created_at else None,
            "answer_preview": a.answer[:PREVIEW_CHARS],
        }
        for a in rows
    ]


def review_detail(session: Session, attempt_id: int) -> dict:
    """Mọi thứ Claude cần để chấm: câu trả lời, đề, các ý rubric (CHỈ nội dung, không từ khoá), đáp án mẫu."""
    a = session.get(SdAttempt, attempt_id)
    if a is None:
        raise SdError(f"không có lần thử id={attempt_id}")
    task = session.get(SdTask, (a.doc_id, a.task_id))
    ref = session.get(SdSection, (a.doc_id, task.ref_section_id)) if task and task.ref_section_id else None
    out = {
        "attempt_id": a.id,
        "doc_id": a.doc_id,
        "task_id": a.task_id,
        "learner_id": a.user_id,
        "n": a.n,
        "status": a.status,
        "answer": a.answer,
        "created_at": a.created_at.isoformat() if a.created_at else None,
        "task": None,
        "reference": None,
        "feedback": a.feedback,
        "verdicts": a.verdicts,
    }
    if task:
        hits = (a.auto_result or {}).get("hits", [])
        out["task"] = {
            "name": task.name,
            "prompt": task.prompt,
            "rubric_items": [r["text"] for r in task.rubric],
            "auto_hits": [bool(hits[i]) if i < len(hits) else False for i in range(len(task.rubric))],
        }
    if ref:
        out["reference"] = {
            "section_id": ref.id,
            "title": ref.title,
            "cards": [
                {"kind": c["kind"], "title": c.get("title", ""), "body": c["body"][:MAX_REFERENCE_CHARS]}
                for c in ref.cards[:MAX_REFERENCE_CARDS]
            ],
        }
    return out


def submit_feedback(session: Session, attempt_id: int, *, feedback: str, verdicts: list, reviewer: str) -> dict:
    """Ghi bản chấm sâu: `status=reviewed`. Gọi lại thì thay bản trước. Từng ý rubric được nối theo THỨ TỰ
    và lấy chữ từ rubric của server (Claude chỉ quyết đúng/sai và ghi chú), nên không đổi được nội dung rubric."""
    feedback = (feedback or "").strip()
    if not feedback or len(feedback) > MAX_FEEDBACK_CHARS:
        raise SdError(f"feedback cần 1..{MAX_FEEDBACK_CHARS} ký tự")
    if _bad_text(feedback):
        raise SdError("feedback chứa ký tự NUL hoặc ký tự không hợp lệ")
    a = session.scalar(select(SdAttempt).where(SdAttempt.id == attempt_id).with_for_update())
    if a is None:
        raise SdError(f"không có lần thử id={attempt_id}")
    task = session.get(SdTask, (a.doc_id, a.task_id))
    if task is None:
        raise SdError("task của lần thử này đã bị xoá khi nhập lại tài liệu, không chấm được")
    if not isinstance(verdicts, list) or len(verdicts) != len(task.rubric):
        raise SdError(f"verdicts cần đúng {len(task.rubric)} phần tử, mỗi ý rubric một phần tử theo thứ tự")
    out = []
    for item, rub in zip(verdicts, task.rubric):
        if not isinstance(item, dict) or not isinstance(item.get("ok"), bool):
            raise SdError("mỗi verdict cần dạng {ok: true|false, note: '...'} (ok phải là boolean)")
        note = item.get("note", "")
        if not isinstance(note, str) or len(note) > MAX_NOTE_CHARS or _bad_text(note):
            raise SdError(f"note là chuỗi ≤{MAX_NOTE_CHARS} ký tự, không chứa NUL")
        out.append({"text": rub["text"], "ok": item["ok"], "note": note.strip()})
    a.status, a.feedback, a.verdicts = "reviewed", feedback, out
    a.reviewed_by, a.reviewed_at = reviewer, datetime.now(timezone.utc)
    session.flush()
    return {"attempt_id": a.id, "status": a.status, "score": round(100 * sum(v["ok"] for v in out) / len(out)) if out else 0}
