"""content tables

Revision ID: 0001
Revises: 
Create Date: 2026-10-11 12:19:03.601038

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY, JSONB


# revision identifiers, used by Alembic.
revision: str = '0001'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

TEXT_ARRAY = ARRAY(sa.Text())


def upgrade() -> None:
    """Bảng nội dung học (khớp app/tables.py)."""
    op.create_table(
        "themes",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("tags", TEXT_ARRAY, nullable=False),
    )
    op.create_table(
        "topics",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("theme_id", sa.String(100), sa.ForeignKey("themes.id", ondelete="CASCADE"), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
    )
    op.create_index("ix_topics_theme_id", "topics", ["theme_id"])
    op.create_table(
        "code_files",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("topic_id", sa.String(100), sa.ForeignKey("topics.id", ondelete="CASCADE"), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
    )
    op.create_index("ix_code_files_topic_id", "code_files", ["topic_id"])
    op.create_table(
        "exercises",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("function_name", sa.String(100), nullable=False),
        sa.Column("params", TEXT_ARRAY, nullable=False),
        sa.Column("template", sa.Text(), nullable=False),
        sa.Column("challenge", JSONB(), nullable=False),
        sa.Column("judge_solution", sa.Text(), nullable=False),
        sa.Column("judge_cases", JSONB(), nullable=False),
    )
    op.create_table(
        "file_exercises",
        sa.Column("file_id", sa.String(100), sa.ForeignKey("code_files.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("exercise_id", sa.String(100), sa.ForeignKey("exercises.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("position", sa.Integer(), nullable=False),
    )
    op.create_table(
        "blocks",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("exercise_id", sa.String(100), sa.ForeignKey("exercises.id", ondelete="CASCADE"), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("label", sa.String(10), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("prompt", sa.Text(), nullable=False),
        sa.Column("indent_level", sa.Integer(), nullable=False),
        sa.Column("accepted_answers", TEXT_ARRAY, nullable=False),
        sa.Column("expected_output", sa.Text(), nullable=False),
        sa.Column("explanation", sa.Text(), nullable=False),
        sa.Column("hints", TEXT_ARRAY, nullable=False),
        sa.Column("vocab", TEXT_ARRAY, nullable=False),
        sa.UniqueConstraint("exercise_id", "label", name="uq_blocks_exercise_label"),
    )
    op.create_index("ix_blocks_exercise_id", "blocks", ["exercise_id"])
    op.create_table(
        "content_meta",
        sa.Column("key", sa.String(50), primary_key=True),
        sa.Column("value", sa.Text(), nullable=False),
    )


def downgrade() -> None:
    """Xoá toàn bộ bảng nội dung."""
    for table in ("content_meta", "blocks", "file_exercises", "exercises", "code_files", "topics", "themes"):
        op.drop_table(table)
