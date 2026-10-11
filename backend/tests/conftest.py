"""Fixture DB cho test: Postgres thật, DB riêng `smart_coding_study_test` (tự tạo nếu chưa có).

Đặt `TEST_DATABASE_URL` để dùng server khác. Mỗi phiên test chạy lại migration từ đầu
(downgrade base → upgrade head), nên schema test luôn đúng bản migration hiện tại.
"""

from __future__ import annotations

import json
import os
import re
from collections.abc import Iterator

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session, sessionmaker

from app.db import database_url
from app.load_content import load_content

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL", "postgresql+psycopg://localhost:5432/smart_coding_study_test"
)


def _guard_test_database(url: str) -> None:
    """Fixture DROP toàn bộ bảng: chỉ cho chạy trên DB tên `*_test`, khác DATABASE_URL của app."""
    name = make_url(url).database or ""
    if not re.fullmatch(r"[a-z0-9_]+_test", name):
        raise RuntimeError(f"TEST_DATABASE_URL phải trỏ DB tên dạng '<tên>_test', đang là {name!r}")
    if make_url(url) == make_url(database_url()):
        raise RuntimeError("TEST_DATABASE_URL trùng DATABASE_URL — từ chối chạy test phá dữ liệu")


def _ensure_database(url: str) -> None:
    target = make_url(url)
    admin = create_engine(target.set(database="postgres"), isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        exists = conn.execute(text("select 1 from pg_database where datname = :n"), {"n": target.database}).scalar()
        if not exists:
            conn.execute(text(f'create database "{target.database}"'))
    admin.dispose()


def alembic_config(url: str) -> Config:
    config = Config(os.path.join(BACKEND_DIR, "alembic.ini"))
    config.set_main_option("script_location", os.path.join(BACKEND_DIR, "migrations"))
    config.set_main_option("sqlalchemy.url", url)
    return config


@pytest.fixture(scope="session")
def db_engine() -> Iterator[Engine]:
    _guard_test_database(TEST_DATABASE_URL)
    _ensure_database(TEST_DATABASE_URL)
    config = alembic_config(TEST_DATABASE_URL)
    command.downgrade(config, "base")
    command.upgrade(config, "head")
    engine = create_engine(TEST_DATABASE_URL)
    yield engine
    engine.dispose()


@pytest.fixture()
def db_session(db_engine: Engine) -> Iterator[Session]:
    """Session trong một transaction, rollback sau mỗi test (test không để lại dữ liệu)."""
    connection = db_engine.connect()
    transaction = connection.begin()
    session = sessionmaker(bind=connection, join_transaction_mode="create_savepoint")()
    yield session
    session.close()
    transaction.rollback()
    connection.close()


CONTENT_PATH = os.path.join(BACKEND_DIR, "content", "content.json")


@pytest.fixture(scope="session")
def content_data() -> dict:
    """Nội dung thật trong repo (nguồn soạn), dùng chung cho mọi test."""
    with open(CONTENT_PATH, encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture()
def loaded_session(db_session: Session, content_data: dict) -> Session:
    """`db_session` đã nạp content.json (rollback sau test như db_session)."""
    load_content(db_session, content_data)
    db_session.flush()
    return db_session
