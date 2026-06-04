"""
037 - Videoperizia: insured_disconnected_at on sessions.

Adds a nullable timestamp that is stamped when the insured explicitly leaves
the portal page (POST /claim/videoperizia/leave) or a LiveKit participant_left
webhook fires for their identity.  Exposed to the expert app via the normal
session-polling response so the UI can show a disconnect badge without extra
round-trips.
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "037_videoperizia_insured_disconnect"
down_revision = "036_device_tokens"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "videoperizia_sessions",
        sa.Column("insured_disconnected_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("videoperizia_sessions", "insured_disconnected_at")
