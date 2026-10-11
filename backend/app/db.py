"""Kết nối Postgres. `DATABASE_URL` mặc định trỏ DB local của Homebrew Postgres."""

from __future__ import annotations

import os
from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

DEFAULT_DATABASE_URL = "postgresql+psycopg://localhost:5432/smart_coding_study"


def database_url() -> str:
    return os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL)


engine = create_engine(database_url(), pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_session() -> Iterator[Session]:
    """Dependency FastAPI: một session mỗi request."""
    with SessionLocal() as session:
        yield session
