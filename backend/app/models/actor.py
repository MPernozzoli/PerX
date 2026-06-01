"""
Actor models: contraente / assicurato / danneggiato unificati.

Un Actor rappresenta una persona fisica, un'azienda o un condominio.
Viene referenziato dai sinistri tramite (contraente_id, assicurato_id,
danneggiato_id) e permette di indicizzare cross-sinistro tutte le
polizze, agenzie e compagnie con cui ha avuto relazioni.

Indirizzi e IBAN sono tabelle figlie con storico (is_current + validity).
Le relazioni (figlia/padre/amministratore/...) sono modellate come archi
tra due Actor in ActorRelation.
"""
from sqlalchemy import (
    Column,
    String,
    Date,
    DateTime,
    Boolean,
    Integer,
    ForeignKey,
    UniqueConstraint,
    Index,
)
from sqlalchemy.sql import func

from app.core.database import Base


class Actor(Base):
    __tablename__ = "actors"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)

    # person | company | condo
    actor_type = Column(String, nullable=False, index=True)

    # Persona fisica
    nome = Column(String, nullable=True)
    cognome = Column(String, nullable=True)
    data_nascita = Column(Date, nullable=True)
    luogo_nascita = Column(String, nullable=True)
    sesso = Column(String(1), nullable=True)  # M/F/X

    # Azienda / condominio
    denominazione = Column(String, nullable=True)

    # Identificativi fiscali (chiavi naturali)
    codice_fiscale = Column(String, nullable=True, index=True)
    partita_iva = Column(String, nullable=True, index=True)

    # Contatti rapidi (snapshot del "preferito"; storico in tabelle figlie se serve)
    email = Column(String, nullable=True)
    telefono = Column(String, nullable=True)
    pec = Column(String, nullable=True)

    note = Column(String, nullable=True)

    # GDPR art. 17: soft delete. Quando valorizzato l'attore è "cancellato"
    # logicamente: invisibile a search/get, ma il record persiste per integrità
    # storica sui sinistri (i campi piatti sul Claim vengono però pseudonimizzati
    # contestualmente — vedi soft_delete_actor in actor_service).
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        # CF e P.IVA univoci per tenant (quando presenti)
        UniqueConstraint("tenant_id", "codice_fiscale", name="uq_actor_tenant_cf"),
        UniqueConstraint("tenant_id", "partita_iva", name="uq_actor_tenant_piva"),
        Index("idx_actor_tenant_type", "tenant_id", "actor_type"),
    )


class ActorAddress(Base):
    """
    Indirizzo di un attore. Un attore può averne N contemporaneamente
    (es. persona con più case, azienda con più sedi). Niente vincolo
    "uno solo attivo": è una lista pura. `is_primary` è una pura
    preferenza UI per suggerire un default in fase di creazione sinistro.
    """
    __tablename__ = "actor_addresses"

    id = Column(String, primary_key=True, index=True)
    actor_id = Column(String, ForeignKey("actors.id", ondelete="CASCADE"), nullable=False, index=True)

    label = Column(String, nullable=True)  # residenza / sede legale / sede operativa / recapito / ...
    indirizzo = Column(String, nullable=False)
    civico = Column(String, nullable=True)
    cap = Column(String, nullable=True)
    citta = Column(String, nullable=True)
    provincia = Column(String(2), nullable=True)
    nazione = Column(String, nullable=True, default="IT")

    is_primary = Column(Boolean, nullable=False, default=False)

    note = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_actor_address_actor", "actor_id"),
    )


class ActorIban(Base):
    """
    IBAN di un attore. Lista pura: è normale averne più contemporaneamente
    (personale + aziendale, conti diversi). `is_primary` è suggerimento UI.
    """
    __tablename__ = "actor_ibans"

    id = Column(String, primary_key=True, index=True)
    actor_id = Column(String, ForeignKey("actors.id", ondelete="CASCADE"), nullable=False, index=True)

    iban = Column(String, nullable=False)
    intestatario = Column(String, nullable=True)
    banca = Column(String, nullable=True)
    bic_swift = Column(String, nullable=True)
    label = Column(String, nullable=True)  # es. "conto personale", "conto azienda"

    is_primary = Column(Boolean, nullable=False, default=False)

    note = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_actor_iban_actor", "actor_id"),
    )


class ActorRelation(Base):
    """
    Arco tra due Actor. La direzione è "from_actor è {relation_type} di to_actor".
    Es: from=figlia, to=padre  -> relation_type = 'figlia'
    """
    __tablename__ = "actor_relations"

    id = Column(String, primary_key=True, index=True)
    from_actor_id = Column(String, ForeignKey("actors.id", ondelete="CASCADE"), nullable=False, index=True)
    to_actor_id = Column(String, ForeignKey("actors.id", ondelete="CASCADE"), nullable=False, index=True)

    # figlia/figlio/madre/padre/sorella/fratello/coniuge/amministratore/tutore/delegato/altro
    relation_type = Column(String, nullable=False)

    # GDPR art. 6: base giuridica del trattamento del sub-contatto
    # (dato personale di un terzo). Valori:
    #   consent              - consenso esplicito dell'interessato
    #   contract             - esecuzione contratto (es. delegato in polizza)
    #   legal_obligation     - obbligo di legge
    #   vital_interest       - interesse vitale (caso medico/emergenza)
    #   public_interest      - interesse pubblico
    #   legitimate_interest  - interesse legittimo (es. contatto di emergenza)
    #   other                - da specificare in legal_basis_note
    legal_basis = Column(String, nullable=True)
    legal_basis_note = Column(String, nullable=True)

    note = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint("from_actor_id", "to_actor_id", "relation_type", name="uq_actor_relation"),
    )


class ActorAgencyLink(Base):
    """
    Indice derivato: quali agenzie hanno gestito sinistri di questo attore.
    Aggiornato da claim_service quando un sinistro viene creato/modificato.
    """
    __tablename__ = "actor_agency_links"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    actor_id = Column(String, ForeignKey("actors.id", ondelete="CASCADE"), nullable=False, index=True)
    agency_id = Column(String, ForeignKey("rubrica_agenzie.id", ondelete="CASCADE"), nullable=False, index=True)

    first_seen_claim_id = Column(String, ForeignKey("claims.id"), nullable=True)
    last_seen_claim_id = Column(String, ForeignKey("claims.id"), nullable=True)
    last_seen_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    claim_count = Column(Integer, nullable=False, default=1)

    __table_args__ = (
        UniqueConstraint("actor_id", "agency_id", name="uq_actor_agency"),
    )


class ActorCompanyLink(Base):
    """
    Indice derivato: quali compagnie hanno coperto sinistri di questo attore.
    """
    __tablename__ = "actor_company_links"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    actor_id = Column(String, ForeignKey("actors.id", ondelete="CASCADE"), nullable=False, index=True)
    compagnia_id = Column(String, ForeignKey("rubrica_compagnie.id", ondelete="CASCADE"), nullable=False, index=True)

    first_seen_claim_id = Column(String, ForeignKey("claims.id"), nullable=True)
    last_seen_claim_id = Column(String, ForeignKey("claims.id"), nullable=True)
    last_seen_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    claim_count = Column(Integer, nullable=False, default=1)

    __table_args__ = (
        UniqueConstraint("actor_id", "compagnia_id", name="uq_actor_compagnia"),
    )
