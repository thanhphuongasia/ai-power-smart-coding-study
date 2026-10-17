"""sd_docs: markdown gốc (source_md) + trạng thái archived (xoá mềm)

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-17 12:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0008'
down_revision: Union[str, Sequence[str], None] = '0007'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Thêm cột, nới constraint. Doc có sẵn giữ source_md = NULL tới khi nhập lại (backfill bằng app.sd.import_file)."""
    op.add_column("sd_docs", sa.Column("source_md", sa.Text(), nullable=True))
    op.drop_constraint("ck_sd_docs_status", "sd_docs", type_="check")
    op.create_check_constraint("ck_sd_docs_status", "sd_docs", "status IN ('draft','published','archived')")


def downgrade() -> None:
    """Doc archived trở về draft (không còn trạng thái xoá mềm); MẤT markdown gốc đã lưu."""
    op.execute("UPDATE sd_docs SET status = 'draft' WHERE status = 'archived'")
    op.drop_constraint("ck_sd_docs_status", "sd_docs", type_="check")
    op.create_check_constraint("ck_sd_docs_status", "sd_docs", "status IN ('draft','published')")
    op.drop_column("sd_docs", "source_md")
