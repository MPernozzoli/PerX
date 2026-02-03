"""
Claim event model - timeline events for sync
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON, Index
from sqlalchemy.sql import func
from app.core.database import Base


class ClaimEvent(Base):
    __tablename__ = "claim_events"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    event_type = Column(String, nullable=False, index=True)  # "state_changed", "assigned", "email_linked", "task_created", etc.
    event_time = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    actor_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    data_json = Column(JSON, nullable=True)  # Event-specific data
    source = Column(String, nullable=False)  # "email", "task", "manual", "ai", "system"
    
    # Indice composito per query di sync
    __table_args__ = (
        Index("idx_claim_events_tenant_time", "tenant_id", "event_time"),
    )

