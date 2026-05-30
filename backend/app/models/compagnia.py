"""
Rubrica Compagnie: entità separata per le compagnie assicurative.

Oggi `Claim.compagnia` è una stringa libera; qui introduciamo la rubrica
strutturata, così possiamo agganciare ActorCompanyLink e fare query
"tutte le compagnie con cui ha relazione l'attore X".
"""
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func

from app.core.database import Base


class RubricaCompagnia(Base):
    __tablename__ = "rubrica_compagnie"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)

    nome = Column(String, nullable=False)
    gruppo = Column(String, nullable=True)
    codice = Column(String, nullable=True)
    partita_iva = Column(String, nullable=True)
    pec = Column(String, nullable=True)
    email = Column(String, nullable=True)
    telefono = Column(String, nullable=True)
    sito_web = Column(String, nullable=True)
    note = Column(String, nullable=True)

    is_active = Column(Boolean, nullable=False, default=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint("tenant_id", "nome", name="uq_compagnia_tenant_nome"),
    )
