"""Migration Alembic phải khớp model SQLAlchemy (app/tables.py) và đi được cả hai chiều."""

from __future__ import annotations

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect

from app.tables import Base
import pytest

from tests.conftest import TEST_DATABASE_URL, _guard_test_database, alembic_config

TABLES = {"themes", "topics", "code_files", "exercises", "file_exercises", "blocks", "content_meta"}


def test_migration_matches_models(db_engine):
    with db_engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == []


def test_upgrade_creates_all_tables(db_engine):
    assert TABLES <= set(inspect(db_engine).get_table_names())


def test_downgrade_then_upgrade_round_trip(db_engine):
    config = alembic_config(TEST_DATABASE_URL)
    command.downgrade(config, "base")
    engine = create_engine(TEST_DATABASE_URL)
    try:
        assert not TABLES & set(inspect(engine).get_table_names())
    finally:
        engine.dispose()
        command.upgrade(config, "head")
    assert TABLES <= set(inspect(db_engine).get_table_names())


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+psycopg://localhost:5432/smart_coding_study",  # DB thật
        "postgresql+psycopg://localhost:5432/prod",
        'postgresql+psycopg://localhost:5432/x"; drop database y; --_test',
    ],
)
def test_guard_refuses_non_test_database(url):
    with pytest.raises(RuntimeError):
        _guard_test_database(url)


def test_guard_accepts_test_database():
    _guard_test_database("postgresql+psycopg://localhost:5432/smart_coding_study_test")
