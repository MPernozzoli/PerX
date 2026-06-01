"""
Portal sessions — sessioni attive del portale assicurato.

Oggi l'auth è basata su magic link + bearer token in localStorage. Questo
modello traccia esplicitamente le sessioni così l'assicurato può:
  * vedere da che device/IP è connesso
  * revocare singole sessioni o tutte le altre
  * audit log dei login

Una sessione viene creata quando il magic-link viene consumato e il bearer
token rilasciato. La sessione è valida finché non viene revocata o non
scade.
"""
from sqlalchemy import Column, DateTime, ForeignKey, Index, String
from sqlalchemy.sql import func

from app.core.database import Base


class PortalSession(Base):
    __tablename__ = "portal_sessions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    actor_id = Column(String, ForeignKey("actors.id"), nullable=True, index=True)

    # Hash del bearer token attivo (mai conserviamo il token in chiaro).
    token_hash = Column(String, nullable=False, unique=True, index=True)

    device_label = Column(String, nullable=True)  # "iPhone 15 — Safari"
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_seen_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    revoked_at = Column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        Index("idx_portal_session_active", "portal_access_id", "revoked_at"),
    )
