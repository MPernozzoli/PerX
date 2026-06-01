"""
032 - Videoperizia GPS location pings (timeline streamed during the call).
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "032"
down_revision = "031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "videoperizia_location_pings",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=False),
        sa.Column("session_id", sa.String(), sa.ForeignKey("videoperizia_sessions.id"), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("accuracy_m", sa.Float(), nullable=True),
        sa.Column("altitude_m", sa.Float(), nullable=True),
        sa.Column("speed_mps", sa.Float(), nullable=True),
        sa.Column("heading_deg", sa.Float(), nullable=True),
        sa.Column("source", sa.String(), nullable=False, server_default="portal"),
    )
    op.create_index("ix_vp_pings_tenant", "videoperizia_location_pings", ["tenant_id"])
    op.create_index("ix_vp_pings_claim", "videoperizia_location_pings", ["claim_id"])
    op.create_index("ix_vp_pings_session", "videoperizia_location_pings", ["session_id"])
    op.create_index("ix_vp_pings_recorded_at", "videoperizia_location_pings", ["recorded_at"])


def downgrade() -> None:
    op.drop_table("videoperizia_location_pings")
