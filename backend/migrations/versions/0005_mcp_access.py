"""mcp_access: identity sub allowed to edit content via /mcp

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-11 23:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0005'
down_revision: Union[str, Sequence[str], None] = '0004'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Quyền MCP theo tài khoản identity-service; không đụng bảng nội dung hay tiến độ."""
    op.create_table(
        "mcp_access",
        sa.Column("sub", sa.String(100), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("label", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_mcp_access_user_id", "mcp_access", ["user_id"])


def downgrade() -> None:
    """Xoá quyền MCP — mọi kết nối claude.ai mất quyền ghi tới khi cấp lại."""
    op.drop_table("mcp_access")
