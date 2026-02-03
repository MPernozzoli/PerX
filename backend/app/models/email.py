"""
Email model - normalized email storage
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, Text, JSON, Index
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

