"""
Email model - normalized email storage
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, Text, JSON, Index, Integer
from sqlalchemy.sql import func
from app.core.database import Base


class Email(Base):
    __tablename__ = "emails"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    message_id = Column(String, unique=True, nullable=False, index=True)  # Gmail message ID
    thread_id = Column(String, nullable=True, index=True)
    from_address = Column(String, nullable=False, index=True)
    to_addresses = Column(Text, nullable=True)  # JSON array as string
    cc_addresses = Column(Text, nullable=True)  # JSON array as string
    subject = Column(String, nullable=True)
    body_text = Column(Text, nullable=True)
    body_html = Column(Text, nullable=True)
    received_at = Column(DateTime(timezone=True), nullable=False, index=True)
    ingested_at = Column(DateTime(timezone=True), server_default=func.now())
    status = Column(String, nullable=False, default="ingested")  # ingested, processed, linked, archived
    raw_headers = Column(Text, nullable=True)  # Raw email headers
    mailbox_id = Column(String, nullable=True, index=True)
    provider_id = Column(String, nullable=True)  # gmail, imap, etc.
    
    __table_args__ = (
        Index("idx_emails_tenant_received", "tenant_id", "received_at"),
    )


class EmailClaimLink(Base):
    __tablename__ = "email_claim_links"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    email_id = Column(String, ForeignKey("emails.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    link_type = Column(String, nullable=False)  # "primary", "cc", "notification"
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    created_by = Column(String, nullable=False)  # "auto", "user"


class Mailbox(Base):
    __tablename__ = "mailboxes"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    label = Column(String, nullable=False)
    provider = Column(String, nullable=False)  # gmail, imap, etc.
    email_address = Column(String, nullable=False)
    auth_type = Column(String, nullable=False)  # "oauth", "password"
    oauth_token_ref = Column(String, nullable=True)  # Reference to secret manager
    password_secret_ref = Column(String, nullable=True)  # Reference to secret manager
    settings_json = Column(JSON, nullable=True)  # Provider-specific settings
    active = Column(String, nullable=False, default="true")  # Boolean as string for simplicity


class TenantEmailDomain(Base):
    __tablename__ = "tenant_email_domains"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    domain = Column(String, nullable=False, unique=True, index=True)
    provider = Column(String, nullable=False, default="resend")
    provider_domain_id = Column(String, nullable=True)
    inbound_enabled = Column(String, nullable=False, default="true")
    outbound_enabled = Column(String, nullable=False, default="true")
    catch_all_enabled = Column(String, nullable=False, default="true")
    status = Column(String, nullable=False, default="pending")  # pending, verified, disabled
    settings_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class InboundEmailEvent(Base):
    __tablename__ = "inbound_email_events"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    domain_id = Column(String, ForeignKey("tenant_email_domains.id"), nullable=True, index=True)
    mailbox_id = Column(String, ForeignKey("mailboxes.id"), nullable=True, index=True)
    provider = Column(String, nullable=False, default="resend")
    provider_event_id = Column(String, nullable=False, unique=True, index=True)
    provider_email_id = Column(String, nullable=True, index=True)
    message_id = Column(String, nullable=True, index=True)
    from_address = Column(String, nullable=False, index=True)
    to_addresses = Column(JSON, nullable=False, default=list)
    cc_addresses = Column(JSON, nullable=False, default=list)
    subject = Column(String, nullable=True)
    body_text = Column(Text, nullable=True)
    body_html = Column(Text, nullable=True)
    received_at = Column(DateTime(timezone=True), nullable=False, index=True)
    ingested_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    status = Column(String, nullable=False, default="queued")  # queued, processing, processed, failed
    raw_payload = Column(JSON, nullable=False)
    attachments_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("idx_inbound_email_events_tenant_received", "tenant_id", "received_at"),
    )


class EmailProcessingJob(Base):
    __tablename__ = "email_processing_jobs"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    inbound_event_id = Column(String, ForeignKey("inbound_email_events.id"), nullable=False, unique=True, index=True)
    email_id = Column(String, ForeignKey("emails.id"), nullable=True, index=True)
    status = Column(String, nullable=False, default="pending", index=True)
    priority = Column(Integer, nullable=False, default=0)
    retry_count = Column(Integer, nullable=False, default=0)
    max_retries = Column(Integer, nullable=False, default=5)
    available_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    lease_owner = Column(String, nullable=True, index=True)
    lease_expires_at = Column(DateTime(timezone=True), nullable=True, index=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    last_error = Column(Text, nullable=True)
    input_json = Column(JSON, nullable=False)
    result_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_email_processing_jobs_claim", "status", "available_at", "priority"),
    )


class EmailAlias(Base):
    __tablename__ = "email_aliases"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    domain_id = Column(String, ForeignKey("tenant_email_domains.id"), nullable=True, index=True)
    address = Column(String, nullable=False, unique=True, index=True)
    local_part = Column(String, nullable=False, index=True)
    target_type = Column(String, nullable=False, default="user", index=True)  # user, team, claim, bucket
    target_id = Column(String, nullable=True, index=True)
    is_primary = Column(String, nullable=False, default="false")
    is_active = Column(String, nullable=False, default="true")
    source = Column(String, nullable=False, default="auto")  # auto, user, admin, fuzzy_confirmed
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    retired_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        Index("idx_email_aliases_tenant_target", "tenant_id", "target_type", "target_id"),
        Index("idx_email_aliases_tenant_local_part", "tenant_id", "local_part"),
    )
