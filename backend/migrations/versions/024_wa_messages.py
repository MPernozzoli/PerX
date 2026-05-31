"""
024 - Refactor WhatsApp: drop legacy ORM tables, introduce denormalized
`wa_messages` owned by the local Hub and published on Supabase Realtime.

The Hub (PerXHub) now owns the WhatsApp bridge (OpenWA worker) and writes
every in/out message into `wa_messages`. The iOS app and the portal read
the same table via Supabase Realtime. Scheduled outbound messages remain
on the Hub's local SQLite — only the final sent/failed result is replicated.

Legacy tables `whatsapp_messages`, `whatsapp_threads`, `whatsapp_accounts`
are dropped: the previous data was demo only and the new flow is the
single source of truth.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "024"
down_revision = "023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Drop legacy WhatsApp tables. Use IF EXISTS because in some
    # environments they may have been created via Base.metadata.create_all
    # without an Alembic record.
    op.execute("DROP TABLE IF EXISTS whatsapp_messages CASCADE")
    op.execute("DROP TABLE IF EXISTS whatsapp_threads CASCADE")
    op.execute("DROP TABLE IF EXISTS whatsapp_accounts CASCADE")

    op.create_table(
        "wa_messages",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_slug", sa.String(), nullable=False),
        sa.Column("account_id", sa.String(), nullable=False),
        sa.Column("chat_id", sa.String(), nullable=False),
        sa.Column("wa_message_id", sa.String(), nullable=True),
        sa.Column("direction", sa.String(), nullable=False),  # 'in' | 'out'
        sa.Column("from_number", sa.String(), nullable=True),
        sa.Column("to_number", sa.String(), nullable=True),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("message_type", sa.String(), nullable=False, server_default="chat"),
        sa.Column("has_media", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("media_mimetype", sa.String(), nullable=True),
        sa.Column("media_filename", sa.String(), nullable=True),
        sa.Column("media_url", sa.String(), nullable=True),  # storage URL after upload
        sa.Column("media_base64", sa.Text(), nullable=True),  # inline payload for small media
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
        # outbound lifecycle
        sa.Column(
            "status",
            sa.String(),
            nullable=False,
            server_default="received",
        ),  # received | pending | sent | delivered | read | failed
        sa.Column("ack_status", sa.Integer(), nullable=True),
        sa.Column("ack_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("sinistro_ref", sa.String(), nullable=True),
        sa.Column("is_group", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("author", sa.String(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )

    op.create_index(
        "ix_wa_messages_tenant_chat_ts",
        "wa_messages",
        ["tenant_slug", "chat_id", "timestamp"],
    )
    op.create_index(
        "ix_wa_messages_tenant_account_ts",
        "wa_messages",
        ["tenant_slug", "account_id", "timestamp"],
    )
    op.create_index(
        "ix_wa_messages_sinistro",
        "wa_messages",
        ["tenant_slug", "sinistro_ref"],
    )
    op.create_index(
        "ix_wa_messages_outbox",
        "wa_messages",
        ["account_id", "status"],
        postgresql_where=sa.text("status = 'pending'"),
    )
    op.create_unique_constraint(
        "uq_wa_messages_provider_id",
        "wa_messages",
        ["account_id", "wa_message_id"],
    )

    # Realtime publication (Supabase)
    op.execute(
        "ALTER PUBLICATION supabase_realtime ADD TABLE wa_messages"
    )


def downgrade() -> None:
    op.execute("ALTER PUBLICATION supabase_realtime DROP TABLE wa_messages")
    op.drop_index("ix_wa_messages_outbox", table_name="wa_messages")
    op.drop_index("ix_wa_messages_sinistro", table_name="wa_messages")
    op.drop_index("ix_wa_messages_tenant_account_ts", table_name="wa_messages")
    op.drop_index("ix_wa_messages_tenant_chat_ts", table_name="wa_messages")
    op.drop_table("wa_messages")
    # NOTE: we do NOT recreate the legacy tables — they are intentionally gone.
