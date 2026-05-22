"""
Rubrica models: agenzie e liquidatori
"""
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from sqlalchemy.sql import func

from app.core.database import Base


class RubricaAgenzia(Base):
    __tablename__ = "rubrica_agenzie"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    nome = Column(String, nullable=False)
    codice = Column(String, nullable=True)
    indirizzo = Column(String, nullable=True)
    citta = Column(String, nullable=True)
    provincia = Column(String(2), nullable=True)
    telefono = Column(String, nullable=True)
    email = Column(String, nullable=True)
    compagnia = Column(String, nullable=True)
    gruppo = Column(String, nullable=True)
    note = Column(String, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class RubricaLiquidatore(Base):
    __tablename__ = "rubrica_liquidatori"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    nome = Column(String, nullable=True)
    cognome = Column(String, nullable=False)
    email = Column(String, nullable=True)
    telefono = Column(String, nullable=True)
    compagnia = Column(String, nullable=True)
    zona = Column(String, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    note = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
