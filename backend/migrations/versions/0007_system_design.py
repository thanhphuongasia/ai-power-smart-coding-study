"""system design: tài liệu học SD, tiến độ đọc và lần thử thực chiến

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-12 12:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '0007'
down_revision: Union[str, Sequence[str], None] = '0006'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Bảng mới, không đụng nội dung code hay tiến độ code. Tiến độ/lần thử chỉ FK users."""
    op.create_table(
        "sd_docs",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("status", sa.String(10), server_default="draft", nullable=False),
        sa.Column("context", postgresql.JSONB(), nullable=False),
        sa.Column("created_by", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("status IN ('draft','published')", name="ck_sd_docs_status"),
    )
    op.create_table(
        "sd_sections",
        sa.Column("doc_id", sa.String(100), sa.ForeignKey("sd_docs.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("chapter", sa.Text(), nullable=False),
        sa.Column("chapter_position", sa.Integer(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("cards", postgresql.JSONB(), nullable=False),
        sa.UniqueConstraint("doc_id", "position", name="uq_sd_sections_doc_position"),
    )
    op.create_table(
        "sd_tasks",
        sa.Column("doc_id", sa.String(100), sa.ForeignKey("sd_docs.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("prompt", sa.Text(), nullable=False),
        sa.Column("hints", postgresql.JSONB(), nullable=False),
        sa.Column("rubric", postgresql.JSONB(), nullable=False),
        sa.Column("ref_section_id", sa.String(100), nullable=True),
        sa.UniqueConstraint("doc_id", "position", name="uq_sd_tasks_doc_position"),
    )
    op.create_table(
        "sd_progress",
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("doc_id", sa.String(100), primary_key=True),
        sa.Column("section_id", sa.String(100), primary_key=True),
        sa.Column("read_cards", postgresql.JSONB(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        "sd_attempts",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("doc_id", sa.String(100), nullable=False),
        sa.Column("task_id", sa.String(100), nullable=False),
        sa.Column("n", sa.Integer(), nullable=False),
        sa.Column("answer", sa.Text(), nullable=False),
        sa.Column("auto_result", postgresql.JSONB(), nullable=False),
        sa.Column("status", sa.String(10), server_default="auto", nullable=False),
        sa.Column("feedback", sa.Text(), nullable=True),
        sa.Column("verdicts", postgresql.JSONB(), nullable=True),
        sa.Column("reviewed_by", sa.Text(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "doc_id", "task_id", "n", name="uq_sd_attempts_user_task_n"),
        sa.CheckConstraint("status IN ('auto','reviewed')", name="ck_sd_attempts_status"),
        sa.CheckConstraint("n >= 1", name="ck_sd_attempts_n"),
        sa.CheckConstraint(
            "status = 'auto' OR (feedback IS NOT NULL AND reviewed_at IS NOT NULL)", name="ck_sd_attempts_reviewed"
        ),
    )
    op.create_index("ix_sd_attempts_status", "sd_attempts", ["status"])


def downgrade() -> None:
    """Xoá toàn bộ tài liệu SD, tiến độ đọc và lần thử; nội dung/tiến độ code không đổi."""
    op.drop_table("sd_attempts")
    op.drop_table("sd_progress")
    op.drop_table("sd_tasks")
    op.drop_table("sd_sections")
    op.drop_table("sd_docs")
