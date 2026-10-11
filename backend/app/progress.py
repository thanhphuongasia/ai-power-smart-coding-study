"""Tiến độ học theo user (bảng user_progress, user_state).

`record_pass` do `/run` gọi: chỉ server ghi `passed` (khi máy chấm trả passed cho user đã đăng nhập).
API GET/PUT tiến độ cho client thêm ở đây (router dưới `/api`).
"""

from __future__ import annotations

from collections.abc import Callable

from fastapi import APIRouter
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.db import SessionLocal
from app.tables import UserProgress

router = APIRouter(prefix="/api")


def record_pass(session: Session, user_id: int, exercise_id: str) -> None:
    """Đánh dấu đã xong bài; giữ nguyên draft/gợi ý đang có. Idempotent."""
    stmt = insert(UserProgress).values(
        user_id=user_id,
        exercise_id=exercise_id,
        passed=True,
        drafts={},
        hints_used={},
        solution_viewed=[],
    )
    session.execute(
        stmt.on_conflict_do_update(
            index_elements=[UserProgress.user_id, UserProgress.exercise_id],
            set_={"passed": True},
        )
    )
    session.commit()


PassRecorder = Callable[[int, str], None]


def get_pass_recorder() -> PassRecorder:
    """Cho `/run`: session DB ngắn mở SAU khi máy chấm trả kết quả."""

    def recorder(user_id: int, exercise_id: str) -> None:
        with SessionLocal() as session:
            record_pass(session, user_id, exercise_id)

    return recorder
