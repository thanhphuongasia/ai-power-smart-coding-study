"""courses: khoá học nhóm tài liệu SD; sd_docs.course_id + course_position

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-17 15:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY


# revision identifiers, used by Alembic.
revision: str = '0009'
down_revision: Union[str, Sequence[str], None] = '0008'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Bảng mới + hai cột nullable: doc cũ không thuộc course nào, hiển thị như trước."""
    op.create_table(
        "courses",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("skills", ARRAY(sa.Text()), nullable=False, server_default="{}"),
        sa.Column("domain", sa.Text(), nullable=True),
        sa.Column("status", sa.String(10), nullable=False, server_default="draft"),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("status IN ('draft','published','archived')", name="ck_courses_status"),
    )
    op.add_column(
        "sd_docs",
        sa.Column("course_id", sa.String(100), sa.ForeignKey("courses.id", ondelete="SET NULL"), nullable=True),
    )
    op.add_column("sd_docs", sa.Column("course_position", sa.Integer(), nullable=True))
    op.create_index("ix_sd_docs_course_id", "sd_docs", ["course_id"])


def downgrade() -> None:
    """MẤT cách nhóm doc theo course; nội dung doc, tiến độ, bài nộp không đổi."""
    op.drop_index("ix_sd_docs_course_id", table_name="sd_docs")
    op.drop_column("sd_docs", "course_position")
    op.drop_column("sd_docs", "course_id")
    op.drop_table("courses")
