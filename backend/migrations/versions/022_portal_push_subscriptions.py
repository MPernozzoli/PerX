"""
022 - portal_push_subscriptions

Tabella per le subscription Web Push registrate dal portale assicurati.
Una subscription per (portal_access_id, endpoint).
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "022"
down_revision = "021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "portal_push_subscriptions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=False),
        sa.Column(
            "portal_access_id",
            sa.String(),
            sa.ForeignKey("portal_claim_accesses.id"),
            nullable=False,
        ),
        sa.Column("endpoint", sa.Text(), nullable=False),
        sa.Column("p256dh", sa.String(), nullable=False),
        sa.Column("auth", sa.String(), nullable=False),
        sa.Column("user_agent", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="active"),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "idx_portal_push_subscriptions_access",
        "portal_push_subscriptions",
        ["portal_access_id", "status"],
    )
    op.create_unique_constraint(
        "uq_portal_push_subscriptions_endpoint",
        "portal_push_subscriptions",
        ["portal_access_id", "endpoint"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_portal_push_subscriptions_endpoint",
        "portal_push_subscriptions",
        type_="unique",
    )
    op.drop_index("idx_portal_push_subscriptions_access", "portal_push_subscriptions")
    op.drop_table("portal_push_subscriptions")
