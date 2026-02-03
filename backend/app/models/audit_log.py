"""
Audit log model - centralized audit trail
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON, Index
from sqlalchemy.sql import func
from app.core.database import Base


class AuditLog(Base):
    __tablename__ = "audit_log"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    action = Column(String, nullable=False, index=True)  # "create", "update", "delete", "assign", "state_change", etc.
    entity_type = Column(String, nullable=False, index=True)  # "claim", "task", "email", etc.
    entity_id = Column(String, nullable=False, index=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    details_json = Column(JSON, nullable=True)
    
    __table_args__ = (
        Index("idx_audit_log_tenant_timestamp", "tenant_id", "timestamp"),
        Index("idx_audit_log_entity", "entity_type", "entity_id"),
    )


class SyncCursor(Base):
    __tablename__ = "sync_cursors"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(String, nullable=False)  # Client device identifier
    last_event_id = Column(String, ForeignKey("claim_events.id"), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    __table_args__ = (
        Index("idx_sync_cursors_user_device", "user_id", "device_id", unique=True),
    )

