"""
031 - Videoperizia live session + captured media tables.

Introduces two tables used by the live video-inspection flow:

  * `videoperizia_sessions` — one row per live call, tracks lifecycle
    (scheduled → lobby_open → live → ended/aborted), perito who conducted
    it, and the LiveKit room name.
  * `videoperizia_media` — frame-grabs and short clips captured during the
    call. Storage path points to Supabase; perxHUB processes via the
    existing ProcessJob queue.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "031"
down_revision = "030"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "videoperizia_sessions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=False),
        sa.Column("livekit_room_name", sa.String(), nullable=False, unique=True),
        sa.Column("state", sa.String(), nullable=False, server_default="scheduled"),
        sa.Column("lobby_joined_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("perito_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("client_meta_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_videoperizia_sessions_tenant", "videoperizia_sessions", ["tenant_id"])
    op.create_index("ix_videoperizia_sessions_claim", "videoperizia_sessions", ["claim_id"])
    op.create_index("ix_videoperizia_sessions_state", "videoperizia_sessions", ["state"])
    op.create_index("ix_videoperizia_sessions_perito", "videoperizia_sessions", ["perito_user_id"])
    op.create_index("idx_videoperizia_sessions_claim_state", "videoperizia_sessions", ["claim_id", "state"])

    op.create_table(
        "videoperizia_media",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=False),
        sa.Column("session_id", sa.String(), sa.ForeignKey("videoperizia_sessions.id"), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("storage_path", sa.String(), nullable=False),
        sa.Column("mime_type", sa.String(), nullable=True),
        sa.Column("captured_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("captured_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("processing_status", sa.String(), nullable=False, server_default="pending_hub"),
        sa.Column("hub_result_json", sa.JSON(), nullable=True),
        sa.Column("hub_job_id", sa.String(), sa.ForeignKey("process_jobs.id"), nullable=True),
    )
    op.create_index("ix_videoperizia_media_tenant", "videoperizia_media", ["tenant_id"])
    op.create_index("ix_videoperizia_media_claim", "videoperizia_media", ["claim_id"])
    op.create_index("ix_videoperizia_media_session", "videoperizia_media", ["session_id"])
    op.create_index("ix_videoperizia_media_status", "videoperizia_media", ["processing_status"])


def downgrade() -> None:
    op.drop_table("videoperizia_media")
    op.drop_table("videoperizia_sessions")
