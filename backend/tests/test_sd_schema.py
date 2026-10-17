"""Bảng System Design: migration 0007 khớp model, một head, không FK từ tiến độ/lần thử tới nội dung SD."""

from __future__ import annotations

from alembic.script import ScriptDirectory
from sqlalchemy import inspect

from tests.conftest import TEST_DATABASE_URL, alembic_config

SD_TABLES = {"sd_docs", "sd_sections", "sd_tasks", "sd_progress", "sd_attempts"}
SD_CONTENT = {"sd_docs", "sd_sections", "sd_tasks"}


def test_single_alembic_head():
    heads = ScriptDirectory.from_config(alembic_config(TEST_DATABASE_URL)).get_heads()
    assert heads == ["0009"]


def test_upgrade_creates_sd_tables(db_engine):
    assert SD_TABLES <= set(inspect(db_engine).get_table_names())


def test_progress_and_attempts_only_reference_users(db_engine):
    insp = inspect(db_engine)
    for table in ("sd_progress", "sd_attempts"):
        targets = {fk["referred_table"] for fk in insp.get_foreign_keys(table)}
        assert targets == {"users"}, f"{table} không được FK tới nội dung SD (nhập lại sẽ xoá tiến độ)"


def test_content_children_cascade_with_doc(db_engine):
    insp = inspect(db_engine)
    for table in ("sd_sections", "sd_tasks"):
        (fk,) = insp.get_foreign_keys(table)
        assert fk["referred_table"] == "sd_docs"
        assert fk["options"].get("ondelete") == "CASCADE"


# --- Ràng buộc dữ liệu (compare_metadata không so CheckConstraint nên phải thử thật) ---------------

import pytest
from sqlalchemy.exc import IntegrityError

from app.tables import SdAttempt, User


def _attempt(user_id: int, **over) -> SdAttempt:
    base = dict(user_id=user_id, doc_id="d", task_id="t", n=1, answer="a", auto_result={})
    return SdAttempt(**{**base, **over})


@pytest.fixture()
def uid(db_session) -> int:
    user = User(email="sd-schema@example.com", password_hash="x", roles=["learner"])
    db_session.add(user)
    db_session.flush()
    return user.id


def test_attempt_number_is_unique_per_user_task(db_session, uid):
    db_session.add(_attempt(uid))
    db_session.flush()
    db_session.add(_attempt(uid))  # cùng (user, doc, task, n): chống hai lần nộp đồng thời lấy trùng n
    with pytest.raises(IntegrityError):
        db_session.flush()


@pytest.mark.parametrize(
    "over",
    [
        {"status": "weird"},
        {"n": 0},
        {"status": "reviewed"},  # reviewed mà thiếu feedback/reviewed_at
    ],
)
def test_attempt_rejects_invalid_rows(db_session, uid, over):
    db_session.add(_attempt(uid, **over))
    with pytest.raises(IntegrityError):
        db_session.flush()
