"""
Automation state models.
"""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.sql import func

from app.core.database import Base


class AutomationTriggerState(Base):
    __tablename__ = "automation_trigger_states"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    trigger_type = Column(String, nullable=False, index=True)
    start_date = Column(DateTime(timezone=True), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    last_check_date = Column(DateTime(timezone=True), nullable=True)
    timeout_days = Column(Integer, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("uq_automation_trigger_state_claim_type", "claim_id", "trigger_type", unique=True),
        Index("idx_automation_trigger_state_tenant_active", "tenant_id", "is_active"),
    )
