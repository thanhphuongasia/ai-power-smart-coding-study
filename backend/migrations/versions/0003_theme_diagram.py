"""theme class diagram

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-11 19:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB


# revision identifiers, used by Alembic.
revision: str = '0003'
down_revision: Union[str, Sequence[str], None] = '0002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Sơ đồ class của mỗi project (theme). Hàng cũ nhận sơ đồ rỗng tới lần nạp kế."""
    op.add_column(
        "themes",
        sa.Column(
            "diagram",
            JSONB(),
            nullable=False,
            server_default=sa.text("""'{"classes": [], "relations": []}'::jsonb"""),
        ),
    )
    op.alter_column("themes", "diagram", server_default=None)


def downgrade() -> None:
    """Bỏ cột; nội dung là bản dẫn xuất của content.json, nạp lại sau upgrade là đủ."""
    op.drop_column("themes", "diagram")
