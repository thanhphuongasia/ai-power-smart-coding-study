"""Migration Alembic phải khớp model SQLAlchemy (app/tables.py) và đi được cả hai chiều."""

from __future__ import annotations

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect

from app.tables import Base
from tests.conftest import TEST_DATABASE_URL, alembic_config

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
