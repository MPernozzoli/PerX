"""
Communication domain models.

These tables model PerX-owned communication state. Telecom providers and
LiveKit are adapters/transports; they do not own routing decisions.
"""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, Integer, JSON, String, Text
from sqlalchemy.sql import func

from app.core.database import Base


class CommunicationSession(Base):
    __tablename__ = "communication_sessions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    scheduled_communication_id = Column(String, nullable=True, index=True)
    destination_type = Column(String, nullable=False, index=True)
    transport = Column(String, nullable=False, index=True)
    state = Column(String, nullable=False, default="pending", index=True)
    display_name = Column(String, nullable=True)
    livekit_room_name = Column(String, nullable=True, unique=True)
    external_provider = Column(String, nullable=True)
    provider_session_id = Column(String, nullable=True, index=True)
    recording_enabled = Column(Boolean, nullable=False, default=False)
    transcription_enabled = Column(Boolean, nullable=False, default=False)
    metadata_json = Column(JSON, nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    ended_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_communication_sessions_tenant_state", "tenant_id", "state"),
        Index("idx_communication_sessions_claim_created", "claim_id", "created_at"),
    )


class Call(Base):
    __tablename__ = "communication_calls"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("communication_sessions.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    direction = Column(String, nullable=False, index=True)
    state = Column(String, nullable=False, default="pending", index=True)
    from_value = Column(String, nullable=True)
    to_value = Column(String, nullable=True)
    caller_id = Column(String, nullable=True)
    provider = Column(String, nullable=True)
    provider_call_id = Column(String, nullable=True, index=True)
    livekit_room_name = Column(String, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    failure_reason = Column(String, nullable=True)
    recording_url = Column(String, nullable=True)
    transcript_url = Column(String, nullable=True)
    transcript_text = Column(Text, nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    answered_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class CallParticipant(Base):
    __tablename__ = "communication_call_participants"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("communication_sessions.id"), nullable=False, index=True)
    call_id = Column(String, ForeignKey("communication_calls.id"), nullable=True, index=True)
    participant_type = Column(String, nullable=False)
    user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    external_contact_id = Column(String, nullable=True)
    display_name = Column(String, nullable=True)
    phone_number = Column(String, nullable=True)
    livekit_identity = Column(String, nullable=True)
    role = Column(String, nullable=True)
    joined_at = Column(DateTime(timezone=True), nullable=True)
    left_at = Column(DateTime(timezone=True), nullable=True)
    metadata_json = Column(JSON, nullable=True)


class PhoneNumber(Base):
    __tablename__ = "communication_phone_numbers"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    e164 = Column(String, nullable=False, index=True)
    display_name = Column(String, nullable=True)
    provider = Column(String, nullable=False)
    provider_number_id = Column(String, nullable=True)
    owner_type = Column(String, nullable=False, default="tenant")
    owner_id = Column(String, nullable=True)
    caller_id_enabled = Column(Boolean, nullable=False, default=True)
    inbound_enabled = Column(Boolean, nullable=False, default=True)
    is_primary = Column(Boolean, nullable=False, default=False)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_communication_phone_numbers_tenant_e164", "tenant_id", "e164", unique=True),
    )


class VirtualExtension(Base):
    __tablename__ = "communication_virtual_extensions"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    extension_number = Column(String(3), nullable=False)
    target_type = Column(String, nullable=False)
    target_id = Column(String, nullable=False)
    display_name = Column(String, nullable=True)
    enabled = Column(Boolean, nullable=False, default=True)
    assigned_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    metadata_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("idx_virtual_extensions_tenant_number", "tenant_id", "extension_number", unique=True),
    )


class CallRoutingRule(Base):
    __tablename__ = "communication_call_routing_rules"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    name = Column(String, nullable=False)
    priority = Column(Integer, nullable=False, default=100)
    enabled = Column(Boolean, nullable=False, default=True)
    trigger_json = Column(JSON, nullable=False)
    action_json = Column(JSON, nullable=False)
    fallback_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class CallQueue(Base):
    __tablename__ = "communication_call_queues"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    name = Column(String, nullable=False)
    slug = Column(String, nullable=False)
    enabled = Column(Boolean, nullable=False, default=True)
    strategy = Column(String, nullable=False, default="first_available")
    member_user_ids_json = Column(JSON, nullable=True)
    fallback_action_json = Column(JSON, nullable=True)
    metadata_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("idx_call_queues_tenant_slug", "tenant_id", "slug", unique=True),
    )


class CallLog(Base):
    __tablename__ = "communication_call_logs"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("communication_sessions.id"), nullable=False, index=True)
    call_id = Column(String, ForeignKey("communication_calls.id"), nullable=True, index=True)
    actor_user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    event_type = Column(String, nullable=False, index=True)
    state = Column(String, nullable=True)
    message = Column(Text, nullable=True)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ScheduledCommunication(Base):
    __tablename__ = "communication_scheduled"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    title = Column(String, nullable=False)
    starts_at = Column(DateTime(timezone=True), nullable=False, index=True)
    ends_at = Column(DateTime(timezone=True), nullable=False)
    state = Column(String, nullable=False, default="scheduled", index=True)
    livekit_room_name = Column(String, nullable=True, unique=True)
    internal_participants_json = Column(JSON, nullable=True)
    external_invites_json = Column(JSON, nullable=True)
    reminders_json = Column(JSON, nullable=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ExternalInviteLink(Base):
    __tablename__ = "communication_external_invite_links"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("communication_sessions.id"), nullable=True, index=True)
    scheduled_communication_id = Column(String, ForeignKey("communication_scheduled.id"), nullable=True, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    token_hash = Column(String, nullable=False, unique=True)
    guest_role = Column(String, nullable=False)
    permissions_json = Column(JSON, nullable=False)
    valid_from = Column(DateTime(timezone=True), nullable=False)
    valid_until = Column(DateTime(timezone=True), nullable=False)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    last_accessed_at = Column(DateTime(timezone=True), nullable=True)
    access_count = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class CommunicationTask(Base):
    __tablename__ = "communication_tasks"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("communication_sessions.id"), nullable=True, index=True)
    call_id = Column(String, ForeignKey("communication_calls.id"), nullable=True, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    assigned_to_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    task_type = Column(String, nullable=False)
    state = Column(String, nullable=False, default="pending")
    title = Column(String, nullable=False)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ProviderWebhookEvent(Base):
    __tablename__ = "communication_provider_webhook_events"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=True, index=True)
    provider = Column(String, nullable=False, index=True)
    provider_event_id = Column(String, nullable=True, index=True)
    event_type = Column(String, nullable=False, index=True)
    signature_valid = Column(Boolean, nullable=False, default=False)
    normalized_payload_json = Column(JSON, nullable=False)
    raw_payload_json = Column(JSON, nullable=True)
    processed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
