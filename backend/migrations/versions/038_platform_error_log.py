"""
038 - platform_error_log: cross-tenant error tracking for platform admins.

First iteration only, backend-only scope (see Documentation/06-Decisioni-e-
Intenzioni-Future.md, 2026-09-06): `source` stays a free string so future
ingestion from web apps / native apps / PerXHub doesn't need a new migration.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "038_platform_error_log"
down_revision = "037_videoperizia_disconnect"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "platform_error_log",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=True),
        sa.Column("source", sa.String(), nullable=False, server_default="backend"),
        sa.Column("severity", sa.String(), nullable=False, server_default="error"),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("stack_trace", sa.Text(), nullable=True),
        sa.Column("path", sa.String(), nullable=True),
        sa.Column("method", sa.String(), nullable=True),
        sa.Column("status_code", sa.Integer(), nullable=True),
        sa.Column("context_json", sa.JSON(), nullable=True),
        sa.Column("resolved", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolved_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_platform_error_log_tenant_id", "platform_error_log", ["tenant_id"])
    op.create_index("ix_platform_error_log_source", "platform_error_log", ["source"])
    op.create_index("ix_platform_error_log_severity", "platform_error_log", ["severity"])
    op.create_index("ix_platform_error_log_created_at", "platform_error_log", ["created_at"])
    op.create_index(
        "idx_platform_error_log_tenant_created", "platform_error_log", ["tenant_id", "created_at"]
    )
    op.create_index(
        "idx_platform_error_log_resolved_created", "platform_error_log", ["resolved", "created_at"]
    )


def downgrade() -> None:
    op.drop_index("idx_platform_error_log_resolved_created", table_name="platform_error_log")
    op.drop_index("idx_platform_error_log_tenant_created", table_name="platform_error_log")
    op.drop_index("ix_platform_error_log_created_at", table_name="platform_error_log")
    op.drop_index("ix_platform_error_log_severity", table_name="platform_error_log")
    op.drop_index("ix_platform_error_log_source", table_name="platform_error_log")
    op.drop_index("ix_platform_error_log_tenant_id", table_name="platform_error_log")
    op.drop_table("platform_error_log")
