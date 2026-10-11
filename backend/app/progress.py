"""Tiến độ học theo user (bảng user_progress, user_state).

`record_pass` do `/run` gọi: chỉ server ghi `passed` (khi máy chấm trả passed cho user đã đăng nhập).
API GET/PUT tiến độ cho client thêm ở đây (router dưới `/api`).
"""

from __future__ import annotations

import json
import re
from collections.abc import Callable
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.auth import CurrentUser, current_user
from app.db import SessionLocal, get_session
from app.tables import Block, Exercise, UserProgress, UserState

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
            set_={"passed": True, "updated_at": func.now()},
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


# --- API cho client -------------------------------------------------------------------------

MAX_DRAFT_BYTES = 64 * 1024
MAX_HINTS = 3
MAX_ACTIVITY_ENTRIES = 400
MAX_REVIEW_ENTRIES = 2000
MAX_REVIEW_BYTES = 64 * 1024
_DATE_KEY = re.compile(r"\d{4}-\d{2}-\d{2}")


MAX_REVIEW_DEPTH = 32


def _bad_text(s: str) -> bool:
    # NUL: Postgres JSONB không lưu được (psycopg DataError → 500).
    # Surrogate lone (vd "\ud800"): không encode được UTF-8 (UnicodeEncodeError → 500).
    if "\x00" in s:
        return True
    try:
        s.encode("utf-8")
    except UnicodeEncodeError:
        return True
    return False


def _check_json_tree(root) -> None:
    """Duyệt không đệ quy: chặn text lỗi trong mọi key/value và độ lồng quá MAX_REVIEW_DEPTH.
    NaN/Infinity đã bị json.dumps(allow_nan=False) bắt sau bước này."""
    stack = [(root, 1)]
    while stack:
        node, depth = stack.pop()
        if isinstance(node, str):
            if _bad_text(node):
                raise ValueError("không được chứa ký tự NUL hoặc ký tự không hợp lệ (surrogate)")
        elif isinstance(node, dict):
            if depth > MAX_REVIEW_DEPTH:
                raise ValueError(f"review lồng quá {MAX_REVIEW_DEPTH} cấp")
            for k, v in node.items():
                if _bad_text(k):
                    raise ValueError("khoá không được chứa ký tự NUL hoặc ký tự không hợp lệ (surrogate)")
                stack.append((v, depth + 1))
        elif isinstance(node, list):
            if depth > MAX_REVIEW_DEPTH:
                raise ValueError(f"review lồng quá {MAX_REVIEW_DEPTH} cấp")
            for v in node:
                stack.append((v, depth + 1))


class ExerciseProgressIn(BaseModel):
    """`passed` cố ý không có: chỉ server ghi (extra=forbid → gửi `passed` là 422)."""

    model_config = ConfigDict(extra="forbid")

    drafts: dict[str, str]
    hints_used: dict[str, Annotated[int, Field(ge=0, le=MAX_HINTS, strict=True)]]
    solution_viewed: list[str]

    @field_validator("drafts")
    @classmethod
    def _check_drafts(cls, value: dict[str, str]) -> dict[str, str]:
        for k, v in value.items():
            if _bad_text(k) or _bad_text(v):
                raise ValueError("draft không được chứa ký tự NUL hoặc surrogate")
        return value

    @field_validator("hints_used")
    @classmethod
    def _check_hints_keys(cls, value: dict[str, int]) -> dict[str, int]:
        if any(_bad_text(k) for k in value):
            raise ValueError("khoá hints_used không được chứa ký tự NUL hoặc surrogate")
        return value

    @field_validator("solution_viewed")
    @classmethod
    def _dedupe_solution_viewed(cls, value: list[str]) -> list[str]:
        if any(_bad_text(s) for s in value):
            raise ValueError("solution_viewed không được chứa ký tự NUL hoặc surrogate")
        return sorted(set(value))


class UserStateIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    review: dict
    activity: dict[str, Annotated[int, Field(ge=0, strict=True)]]

    @field_validator("activity")
    @classmethod
    def _check_activity(cls, value: dict[str, int]) -> dict[str, int]:
        if len(value) > MAX_ACTIVITY_ENTRIES:
            raise ValueError(f"activity tối đa {MAX_ACTIVITY_ENTRIES} mục")
        for key in value:
            try:
                valid = bool(_DATE_KEY.fullmatch(key)) and date.fromisoformat(key) is not None
            except ValueError:
                valid = False
            if not valid:
                raise ValueError(f"khoá activity phải dạng YYYY-MM-DD: {key!r}")
        return value

    @field_validator("review")
    @classmethod
    def _check_review(cls, value: dict) -> dict:
        if len(value) > MAX_REVIEW_ENTRIES:
            raise ValueError(f"review tối đa {MAX_REVIEW_ENTRIES} mục")
        # Phải duyệt cấu trúc TRƯỚC json.dumps: dumps đệ quy nên lồng sâu sẽ RecursionError (500).
        _check_json_tree(value)
        # allow_nan=False: NaN/Infinity không phải JSON hợp lệ, JSONB không lưu được → ValueError → 422.
        dumped = json.dumps(value, ensure_ascii=False, allow_nan=False)
        if len(dumped.encode("utf-8")) > MAX_REVIEW_BYTES:
            raise ValueError("review quá lớn (tối đa 64KB)")
        return value


def _drafts_bytes(drafts: dict[str, str]) -> int:
    return sum(len(k.encode("utf-8")) + len(v.encode("utf-8")) for k, v in drafts.items())


# Khai báo `/progress/state` TRƯỚC `/progress/{exercise_id}` để không bị route động bắt mất.
@router.put("/progress/state", status_code=204)
def put_state(
    body: UserStateIn,
    user: CurrentUser = Depends(current_user),
    session: Session = Depends(get_session),
) -> Response:
    stmt = insert(UserState).values(user_id=user.id, review=body.review, activity=body.activity)
    session.execute(
        stmt.on_conflict_do_update(
            index_elements=[UserState.user_id],
            set_={"review": stmt.excluded.review, "activity": stmt.excluded.activity, "updated_at": func.now()},
        )
    )
    session.commit()
    return Response(status_code=204)


@router.get("/progress")
def get_progress(user: CurrentUser = Depends(current_user), session: Session = Depends(get_session)) -> dict:
    rows = session.scalars(select(UserProgress).where(UserProgress.user_id == user.id)).all()
    live = set(session.scalars(select(Exercise.id).where(Exercise.id.in_([r.exercise_id for r in rows]))).all())
    state = session.get(UserState, user.id)
    return {
        "exercises": {
            r.exercise_id: {
                "passed": r.passed,
                "drafts": r.drafts,
                "hints_used": r.hints_used,
                "solution_viewed": r.solution_viewed,
            }
            for r in rows
            if r.exercise_id in live
        },
        "state": {
            "review": state.review if state else {},
            "activity": state.activity if state else {},
        },
    }


@router.put("/progress/{exercise_id}", status_code=204)
def put_exercise_progress(
    exercise_id: str,
    body: ExerciseProgressIn,
    user: CurrentUser = Depends(current_user),
    session: Session = Depends(get_session),
) -> Response:
    if _bad_text(exercise_id) or session.get(Exercise, exercise_id) is None:
        raise HTTPException(status_code=404, detail="exercise_not_found")
    labels = set(session.scalars(select(Block.label).where(Block.exercise_id == exercise_id)).all())
    used = set(body.drafts) | set(body.hints_used) | set(body.solution_viewed)
    unknown = used - labels
    if unknown:
        raise HTTPException(status_code=422, detail=f"unknown_labels: {sorted(unknown)}")
    if _drafts_bytes(body.drafts) > MAX_DRAFT_BYTES:
        raise HTTPException(status_code=413, detail="draft_too_large")
    stmt = insert(UserProgress).values(
        user_id=user.id,
        exercise_id=exercise_id,
        passed=False,
        drafts=body.drafts,
        hints_used=body.hints_used,
        solution_viewed=body.solution_viewed,
    )
    # `passed` không nằm trong set_: PUT không bao giờ đổi nó.
    session.execute(
        stmt.on_conflict_do_update(
            index_elements=[UserProgress.user_id, UserProgress.exercise_id],
            set_={
                "drafts": stmt.excluded.drafts,
                "hints_used": stmt.excluded.hints_used,
                "solution_viewed": stmt.excluded.solution_viewed,
                "updated_at": func.now(),
            },
        )
    )
    session.commit()
    return Response(status_code=204)
