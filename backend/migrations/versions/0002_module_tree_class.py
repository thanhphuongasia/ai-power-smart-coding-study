"""module tree + class methods

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-11 18:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0002'
down_revision: Union[str, Sequence[str], None] = '0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Sub-module (`topics.parent_id`) và bài method (`exercises.class_name`)."""
    op.add_column("topics", sa.Column("parent_id", sa.String(100), nullable=True))
    op.create_foreign_key(
        "topics_parent_id_fkey", "topics", "topics", ["parent_id"], ["id"], ondelete="CASCADE"
    )
    op.create_index("ix_topics_parent_id", "topics", ["parent_id"])
    op.add_column("exercises", sa.Column("class_name", sa.String(100), nullable=True))


def downgrade() -> None:
    """Bỏ 2 cột. Dữ liệu cha–con và class mất theo — chấp nhận được vì bảng nội dung chỉ là bản dẫn
    xuất của `content.json`: chạy lại `python -m app.load_content` sau khi upgrade là có lại đủ."""
    op.drop_column("exercises", "class_name")
    op.drop_index("ix_topics_parent_id", table_name="topics")
    op.drop_constraint("topics_parent_id_fkey", "topics", type_="foreignkey")
    op.drop_column("topics", "parent_id")
