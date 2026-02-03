"""
Claim state transition history
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON
from sqlalchemy.sql import func
from app.core.database import Base


class ClaimState(Base):
    __tablename__ = "claim_states"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    from_state = Column(String, nullable=True)  # Stato precedente (nullable per stato iniziale)
    to_state = Column(String, nullable=False)  # Nuovo stato
    changed_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    changed_at = Column(DateTime(timezone=True), server_default=func.now())
    reason = Column(String, nullable=True)
    payload_json = Column(JSON, nullable=True)  # Dati aggiuntivi della transizione

