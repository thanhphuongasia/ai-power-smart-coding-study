"""content_changes: hàng chờ duyệt nội dung (mỗi dòng một mục so với live)

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-12 00:30:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '0006'
down_revision: Union[str, Sequence[str], None] = '0005'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Bảng mới, không đụng nội dung live hay tiến độ. Live hiện tại = draft (chưa có mục chờ)."""
    op.create_table(
        "content_changes",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("item_id", sa.String(100), nullable=False),
        sa.Column("action", sa.String(10), nullable=False),
        sa.Column("before", postgresql.JSONB(), nullable=True),
        sa.Column("after", postgresql.JSONB(), nullable=True),
        sa.Column("status", sa.String(10), nullable=False),
        sa.Column("author", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("decided_by", sa.Text(), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("kind IN ('project','module','file','exercise')", name="ck_content_changes_kind"),
        sa.CheckConstraint("action IN ('create','update','delete')", name="ck_content_changes_action"),
        sa.CheckConstraint("status IN ('pending','approved','rejected')", name="ck_content_changes_status"),
    )
    op.create_index("ix_content_changes_status", "content_changes", ["status"])
    # Tối đa một mục chờ cho mỗi (kind, item_id): gửi lại thì cập nhật dòng đó.
    op.create_index(
        "uq_content_changes_pending_item",
        "content_changes",
        ["kind", "item_id"],
        unique=True,
        postgresql_where=sa.text("status = 'pending'"),
    )


def downgrade() -> None:
    """Xoá hàng chờ — mọi mục chưa duyệt mất; live không đổi."""
    op.drop_table("content_changes")
