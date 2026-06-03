"""
035 - Communications core infrastructure.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "035_communications_core"
down_revision = "034_communications_extensions"
branch_labels = None
depends_on = None


def json_type():
    return postgresql.JSONB(astext_type=sa.Text()) if op.get_bind().dialect.name == "postgresql" else sa.JSON()


def upgrade() -> None:
    op.create_table(
        "communication_sessions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("created_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("scheduled_communication_id", sa.String(), nullable=True),
        sa.Column("destination_type", sa.String(), nullable=False),
        sa.Column("transport", sa.String(), nullable=False),
        sa.Column("state", sa.String(), nullable=False, server_default="pending"),
        sa.Column("display_name", sa.String(), nullable=True),
        sa.Column("livekit_room_name", sa.String(), nullable=True, unique=True),
        sa.Column("external_provider", sa.String(), nullable=True),
        sa.Column("provider_session_id", sa.String(), nullable=True),
        sa.Column("recording_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("transcription_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("metadata_json", json_type(), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("idx_communication_sessions_tenant_state", "communication_sessions", ["tenant_id", "state"])
    op.create_index("idx_communication_sessions_claim_created", "communication_sessions", ["claim_id", "created_at"])
    op.create_index("ix_communication_sessions_provider_session_id", "communication_sessions", ["provider_session_id"])
    op.create_index("ix_communication_sessions_scheduled_communication_id", "communication_sessions", ["scheduled_communication_id"])

    op.create_table(
        "communication_calls",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("session_id", sa.String(), sa.ForeignKey("communication_sessions.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("direction", sa.String(), nullable=False),
        sa.Column("state", sa.String(), nullable=False, server_default="pending"),
        sa.Column("from_value", sa.String(), nullable=True),
        sa.Column("to_value", sa.String(), nullable=True),
        sa.Column("caller_id", sa.String(), nullable=True),
        sa.Column("provider", sa.String(), nullable=True),
        sa.Column("provider_call_id", sa.String(), nullable=True),
        sa.Column("livekit_room_name", sa.String(), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("failure_reason", sa.String(), nullable=True),
        sa.Column("recording_url", sa.String(), nullable=True),
        sa.Column("transcript_url", sa.String(), nullable=True),
        sa.Column("transcript_text", sa.Text(), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("answered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_communication_calls_session_id", "communication_calls", ["session_id"])
    op.create_index("ix_communication_calls_provider_call_id", "communication_calls", ["provider_call_id"])
    op.create_index("ix_communication_calls_tenant_id", "communication_calls", ["tenant_id"])
    op.create_index("ix_communication_calls_claim_id", "communication_calls", ["claim_id"])
    op.create_index("ix_communication_calls_state", "communication_calls", ["state"])

    op.create_table(
        "communication_call_participants",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("session_id", sa.String(), sa.ForeignKey("communication_sessions.id"), nullable=False),
        sa.Column("call_id", sa.String(), sa.ForeignKey("communication_calls.id"), nullable=True),
        sa.Column("participant_type", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("external_contact_id", sa.String(), nullable=True),
        sa.Column("display_name", sa.String(), nullable=True),
        sa.Column("phone_number", sa.String(), nullable=True),
        sa.Column("livekit_identity", sa.String(), nullable=True),
        sa.Column("role", sa.String(), nullable=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("left_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("metadata_json", json_type(), nullable=True),
    )
    op.create_index("ix_communication_call_participants_tenant_id", "communication_call_participants", ["tenant_id"])
    op.create_index("ix_communication_call_participants_session_id", "communication_call_participants", ["session_id"])
    op.create_index("ix_communication_call_participants_call_id", "communication_call_participants", ["call_id"])
    op.create_index("ix_communication_call_participants_user_id", "communication_call_participants", ["user_id"])

    op.create_table(
        "communication_phone_numbers",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("e164", sa.String(), nullable=False),
        sa.Column("display_name", sa.String(), nullable=True),
        sa.Column("provider", sa.String(), nullable=False),
        sa.Column("provider_number_id", sa.String(), nullable=True),
        sa.Column("owner_type", sa.String(), nullable=False, server_default="tenant"),
        sa.Column("owner_id", sa.String(), nullable=True),
        sa.Column("caller_id_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("inbound_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("metadata_json", json_type(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("idx_communication_phone_numbers_tenant_e164", "communication_phone_numbers", ["tenant_id", "e164"], unique=True)

    op.create_table(
        "communication_virtual_extensions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("extension_number", sa.String(length=3), nullable=False),
        sa.Column("target_type", sa.String(), nullable=False),
        sa.Column("target_id", sa.String(), nullable=False),
        sa.Column("display_name", sa.String(), nullable=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("assigned_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("metadata_json", json_type(), nullable=True),
    )
    op.create_index("idx_virtual_extensions_tenant_number", "communication_virtual_extensions", ["tenant_id", "extension_number"], unique=True)

    op.create_table(
        "communication_call_routing_rules",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="100"),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("trigger_json", json_type(), nullable=False),
        sa.Column("action_json", json_type(), nullable=False),
        sa.Column("fallback_json", json_type(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_communication_call_routing_rules_tenant_id", "communication_call_routing_rules", ["tenant_id"])

    op.create_table(
        "communication_call_queues",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("slug", sa.String(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("strategy", sa.String(), nullable=False, server_default="first_available"),
        sa.Column("member_user_ids_json", json_type(), nullable=True),
        sa.Column("fallback_action_json", json_type(), nullable=True),
        sa.Column("metadata_json", json_type(), nullable=True),
    )
    op.create_index("idx_call_queues_tenant_slug", "communication_call_queues", ["tenant_id", "slug"], unique=True)

    op.create_table(
        "communication_call_logs",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("session_id", sa.String(), sa.ForeignKey("communication_sessions.id"), nullable=False),
        sa.Column("call_id", sa.String(), sa.ForeignKey("communication_calls.id"), nullable=True),
        sa.Column("actor_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("event_type", sa.String(), nullable=False),
        sa.Column("state", sa.String(), nullable=True),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("payload_json", json_type(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_communication_call_logs_tenant_id", "communication_call_logs", ["tenant_id"])
    op.create_index("ix_communication_call_logs_session_id", "communication_call_logs", ["session_id"])
    op.create_index("ix_communication_call_logs_call_id", "communication_call_logs", ["call_id"])
    op.create_index("ix_communication_call_logs_actor_user_id", "communication_call_logs", ["actor_user_id"])
    op.create_index("ix_communication_call_logs_event_type", "communication_call_logs", ["event_type"])

    op.create_table(
        "communication_scheduled",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("created_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("state", sa.String(), nullable=False, server_default="scheduled"),
        sa.Column("livekit_room_name", sa.String(), nullable=True, unique=True),
        sa.Column("internal_participants_json", json_type(), nullable=True),
        sa.Column("external_invites_json", json_type(), nullable=True),
        sa.Column("reminders_json", json_type(), nullable=True),
        sa.Column("metadata_json", json_type(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_communication_scheduled_tenant_id", "communication_scheduled", ["tenant_id"])
    op.create_index("ix_communication_scheduled_claim_id", "communication_scheduled", ["claim_id"])
    op.create_index("ix_communication_scheduled_starts_at", "communication_scheduled", ["starts_at"])
    op.create_index("ix_communication_scheduled_state", "communication_scheduled", ["state"])

    op.create_table(
        "communication_external_invite_links",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("session_id", sa.String(), sa.ForeignKey("communication_sessions.id"), nullable=True),
        sa.Column("scheduled_communication_id", sa.String(), sa.ForeignKey("communication_scheduled.id"), nullable=True),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("token_hash", sa.String(), nullable=False, unique=True),
        sa.Column("guest_role", sa.String(), nullable=False),
        sa.Column("permissions_json", json_type(), nullable=False),
        sa.Column("valid_from", sa.DateTime(timezone=True), nullable=False),
        sa.Column("valid_until", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_accessed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("access_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_communication_external_invite_links_tenant_id", "communication_external_invite_links", ["tenant_id"])
    op.create_index("ix_communication_external_invite_links_session_id", "communication_external_invite_links", ["session_id"])
    op.create_index("ix_comm_ext_invite_links_sched_comm_id", "communication_external_invite_links", ["scheduled_communication_id"])
    op.create_index("ix_communication_external_invite_links_claim_id", "communication_external_invite_links", ["claim_id"])

    op.create_table(
        "communication_tasks",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("session_id", sa.String(), sa.ForeignKey("communication_sessions.id"), nullable=True),
        sa.Column("call_id", sa.String(), sa.ForeignKey("communication_calls.id"), nullable=True),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("assigned_to_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("task_type", sa.String(), nullable=False),
        sa.Column("state", sa.String(), nullable=False, server_default="pending"),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("payload_json", json_type(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_communication_tasks_tenant_id", "communication_tasks", ["tenant_id"])
    op.create_index("ix_communication_tasks_session_id", "communication_tasks", ["session_id"])
    op.create_index("ix_communication_tasks_call_id", "communication_tasks", ["call_id"])
    op.create_index("ix_communication_tasks_claim_id", "communication_tasks", ["claim_id"])

    op.create_table(
        "communication_provider_webhook_events",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=True),
        sa.Column("provider", sa.String(), nullable=False),
        sa.Column("provider_event_id", sa.String(), nullable=True),
        sa.Column("event_type", sa.String(), nullable=False),
        sa.Column("signature_valid", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("normalized_payload_json", json_type(), nullable=False),
        sa.Column("raw_payload_json", json_type(), nullable=True),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_communication_provider_webhook_events_tenant_id", "communication_provider_webhook_events", ["tenant_id"])
    op.create_index("ix_communication_provider_webhook_events_provider", "communication_provider_webhook_events", ["provider"])
    op.create_index("ix_communication_provider_webhook_events_provider_event_id", "communication_provider_webhook_events", ["provider_event_id"])
    op.create_index("ix_communication_provider_webhook_events_event_type", "communication_provider_webhook_events", ["event_type"])


def downgrade() -> None:
    op.drop_table("communication_provider_webhook_events")
    op.drop_table("communication_tasks")
    op.drop_table("communication_external_invite_links")
    op.drop_table("communication_scheduled")
    op.drop_table("communication_call_logs")
    op.drop_table("communication_call_queues")
    op.drop_table("communication_call_routing_rules")
    op.drop_table("communication_virtual_extensions")
    op.drop_table("communication_phone_numbers")
    op.drop_table("communication_call_participants")
    op.drop_table("communication_calls")
    op.drop_table("communication_sessions")
