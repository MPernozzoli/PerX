"""
Portal privacy & GDPR models.

  * PortalPrivacyPolicy        - versioning della policy del tenant
                                 (markdown editabile dall'admin)
  * PortalConsent              - registro CHI ha accettato CHE versione QUANDO
  * PortalDeletionRequest      - richiesta cancellazione + countdown 5 anni
"""
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


class PortalPrivacyPolicy(Base):
    __tablename__ = "portal_privacy_policies"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)

    # Versione progressiva all'interno del tenant (1, 2, 3, ...). La policy
    # con la versione massima è quella corrente effettiva.
    version = Column(Integer, nullable=False)

    # Markdown con la privacy policy integrale dello studio (non solo del
    # portale): comprende finalità, base giuridica, retention, condivisione
    # con terzi, diritti dell'interessato.
    content_md = Column(Text, nullable=False)
    title = Column(String, nullable=True)
    summary = Column(String, nullable=True)

    # Quando entra in vigore (può essere futura). I consensi precedenti
    # restano validi per la propria versione.
    effective_from = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)

    __table_args__ = (
        UniqueConstraint("tenant_id", "version", name="uq_privacy_policy_tenant_version"),
    )


class PortalConsent(Base):
    __tablename__ = "portal_consents"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    # actor_id può essere null se l'access non è collegata a un Actor strutturato
    # (sinistri legacy pre-anagrafica unificata).
    actor_id = Column(String, ForeignKey("actors.id"), nullable=True, index=True)

    policy_id = Column(String, ForeignKey("portal_privacy_policies.id"), nullable=False)
    policy_version = Column(Integer, nullable=False)

    accepted_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)

    # consent_type: 'privacy' (policy principale) | 'cookies' | 'others future
    consent_type = Column(String, nullable=False, default="privacy")

    __table_args__ = (
        Index("idx_portal_consent_actor", "actor_id"),
        Index("idx_portal_consent_tenant_accepted", "tenant_id", "accepted_at"),
    )


class PortalDeletionRequest(Base):
    __tablename__ = "portal_deletion_requests"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    actor_id = Column(String, ForeignKey("actors.id"), nullable=True, index=True)

    requested_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    requested_ip = Column(String, nullable=True)
    requested_user_agent = Column(String, nullable=True)

    # Data minima a partire dalla quale l'eliminazione è eseguibile: deriva da
    # `ultimo_sinistro_chiuso + 5 anni` (regola di retention peritale).
    eligible_from = Column(DateTime(timezone=True), nullable=False, index=True)

    # pending | cancelled | eligible | processed | rejected
    status = Column(String, nullable=False, default="pending", index=True)

    # Quando l'admin processa la richiesta (o quando il sistema notifica
    # l'admin che la richiesta è eseguibile).
    processed_at = Column(DateTime(timezone=True), nullable=True)
    processed_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)

    reason = Column(String, nullable=True)
    note = Column(String, nullable=True)

    __table_args__ = (
        Index("idx_deletion_request_status_eligible", "status", "eligible_from"),
    )
