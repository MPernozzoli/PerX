"""
036 - APNs / VoIP device tokens for push notifications.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "036_device_tokens"
down_revision = "035_communications_core"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "device_tokens",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token", sa.String(), nullable=False),
        sa.Column("token_type", sa.String(), nullable=False),
        sa.Column("platform", sa.String(), nullable=False, server_default="ios"),
        sa.Column("bundle_id", sa.String(), nullable=True),
        sa.Column("environment", sa.String(), nullable=False, server_default="production"),
        sa.Column("app", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("token", "token_type", name="uq_device_tokens_token_type"),
    )
    op.create_index("ix_device_tokens_tenant_id", "device_tokens", ["tenant_id"])
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])
    op.create_index("ix_device_tokens_user_type", "device_tokens", ["user_id", "token_type"])


def downgrade() -> None:
    op.drop_index("ix_device_tokens_user_type", table_name="device_tokens")
    op.drop_index("ix_device_tokens_user_id", table_name="device_tokens")
    op.drop_index("ix_device_tokens_tenant_id", table_name="device_tokens")
    op.drop_table("device_tokens")
