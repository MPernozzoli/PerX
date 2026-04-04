"""
Claim (Sinistro) model - core entity
"""
from sqlalchemy import Column, String, DateTime, Integer, Numeric, Boolean, ForeignKey, JSON, Index
from sqlalchemy.sql import func
from app.core.database import Base


class Claim(Base):
    __tablename__ = "claims"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    external_ref = Column(String, nullable=True, index=True)  # riferimento
    numero_sinistro = Column(String, nullable=True, index=True)  # numeroSinistroCompagnia
    compagnia = Column(String, nullable=True)  # nomeCompagnia
    stato_corrente = Column(String, nullable=False, index=True)  # stato (ID come "SV001")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    closed_at = Column(DateTime(timezone=True), nullable=True)  # dataChiusura
    priority = Column(Integer, default=0, nullable=False)  # Calcolata dinamicamente
    version = Column(Integer, default=1, nullable=False)  # Per optimistic locking
    
    # Campi principali dal modello locale
    agenzia = Column(String, nullable=True)
    codice_agenzia = Column(String, nullable=True)
    email_agenzia = Column(String, nullable=True)
    telefono_agenzia = Column(String, nullable=True)
    
    # Assicurato
    nome_assicurato = Column(String, nullable=True)
    email_assicurato = Column(String, nullable=True)
    telefono_assicurato = Column(String, nullable=True)
    indirizzo_assicurato = Column(String, nullable=True)
    
    # Contraente
    nome_contraente = Column(String, nullable=True)
    email_contraente = Column(String, nullable=True)
    telefono_contraente = Column(String, nullable=True)
    indirizzo_contraente = Column(String, nullable=True)
    
    # Danneggiato
    nome_danneggiato = Column(String, nullable=True)
    email_danneggiato = Column(String, nullable=True)
    telefono_danneggiato = Column(String, nullable=True)
    indirizzo_danneggiato = Column(String, nullable=True)
    
    # Date importanti
    data_sinistro = Column(DateTime(timezone=True), nullable=True)
    data_denuncia = Column(DateTime(timezone=True), nullable=True)
    data_incarico = Column(DateTime(timezone=True), nullable=True)
    data_apertura_gestione = Column(DateTime(timezone=True), nullable=True)
    data_assegnazione = Column(DateTime(timezone=True), nullable=True)
    data_invio_atto = Column(DateTime(timezone=True), nullable=True)
    data_ritorno_atto = Column(DateTime(timezone=True), nullable=True)
    data_revoca = Column(DateTime(timezone=True), nullable=True)
    data_sopralluogo = Column(DateTime(timezone=True), nullable=True)
    
    # Finanziario
    richiesta = Column(Numeric(12, 2), nullable=True)
    liquidato = Column(Numeric(12, 2), nullable=True)
    danno_accertato = Column(Numeric(12, 2), nullable=True)
    danno_accertato_netto = Column(Numeric(12, 2), nullable=True)
    stima_danno = Column(Numeric(12, 2), nullable=True)
    
    # Polizza
    numero_polizza = Column(String, nullable=True)
    tipo_polizza = Column(String, nullable=True)
    divisione_compagnia = Column(String, nullable=True)
    garanzia = Column(String, nullable=False, default="Fenomeno Elettrico")
    
    # Flags
    iban = Column(Boolean, default=False, nullable=False)
    sinistro_collegato = Column(Boolean, default=False, nullable=False)
    id_sinistro_collegato = Column(String, nullable=True)
    sopralluogo = Column(Boolean, default=False, nullable=False)
    giustificativi = Column(Boolean, default=False, nullable=False)
    foto = Column(Boolean, default=False, nullable=False)
    oltre_dieci_beni = Column(Boolean, default=False, nullable=False)
    concordata = Column(Boolean, default=False, nullable=False)
    negativa = Column(Boolean, default=False, nullable=False)
    ubicazione_validata = Column(Boolean, default=False, nullable=False)
    
    # Classificazione
    fulminazione = Column(String, nullable=True)
    gruppo = Column(String, nullable=True)
    area = Column(String, nullable=True)
    complessita = Column(String, nullable=True)
    definizione = Column(String, nullable=True)
    propensione_perito = Column(String, nullable=True)
    ubicazione_note = Column(String, nullable=True)
    
    # Cartella locale (legacy, da rimuovere in futuro)
    cartella = Column(String, nullable=True)
    owner_email = Column(String, nullable=True)  # Legacy assignment
    
    # Metadata JSON per estensioni future
    metadata_json = Column(JSON, nullable=True)
    
    # Indici compositi per query comuni
    __table_args__ = (
        Index("idx_claims_tenant_stato", "tenant_id", "stato_corrente"),
        Index("idx_claims_tenant_created", "tenant_id", "created_at"),
    )
