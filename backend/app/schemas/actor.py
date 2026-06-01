"""
Pydantic schemas for Actor (contraente/assicurato/danneggiato unificato)
e relative sotto-entità: indirizzi, IBAN, relazioni, indici link.
"""
from __future__ import annotations

from datetime import date, datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, Field


ActorType = Literal["person", "company", "condo"]
RelationType = Literal[
    "figlia",
    "figlio",
    "madre",
    "padre",
    "sorella",
    "fratello",
    "coniuge",
    "amministratore",
    "tutore",
    "delegato",
    "altro",
]

LegalBasis = Literal[
    "consent",
    "contract",
    "legal_obligation",
    "vital_interest",
    "public_interest",
    "legitimate_interest",
    "other",
]


# ------------------------------------------------------------------
# Address
# ------------------------------------------------------------------

class ActorAddressBase(BaseModel):
    label: Optional[str] = None
    indirizzo: str
    civico: Optional[str] = None
    cap: Optional[str] = None
    citta: Optional[str] = None
    provincia: Optional[str] = None
    nazione: Optional[str] = "IT"
    is_primary: bool = False
    note: Optional[str] = None


class ActorAddressCreate(ActorAddressBase):
    pass


class ActorAddressUpdate(BaseModel):
    label: Optional[str] = None
    indirizzo: Optional[str] = None
    civico: Optional[str] = None
    cap: Optional[str] = None
    citta: Optional[str] = None
    provincia: Optional[str] = None
    nazione: Optional[str] = None
    is_primary: Optional[bool] = None
    note: Optional[str] = None


class ActorAddressResponse(ActorAddressBase):
    id: str
    actor_id: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


# ------------------------------------------------------------------
# IBAN
# ------------------------------------------------------------------

class ActorIbanBase(BaseModel):
    iban: str
    intestatario: Optional[str] = None
    banca: Optional[str] = None
    bic_swift: Optional[str] = None
    label: Optional[str] = None
    is_primary: bool = False
    note: Optional[str] = None


class ActorIbanCreate(ActorIbanBase):
    pass


class ActorIbanUpdate(BaseModel):
    iban: Optional[str] = None
    intestatario: Optional[str] = None
    banca: Optional[str] = None
    bic_swift: Optional[str] = None
    label: Optional[str] = None
    is_primary: Optional[bool] = None
    note: Optional[str] = None


class ActorIbanResponse(ActorIbanBase):
    id: str
    actor_id: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


# ------------------------------------------------------------------
# Relation
# ------------------------------------------------------------------

class ActorRelationBase(BaseModel):
    from_actor_id: str
    to_actor_id: str
    relation_type: RelationType
    legal_basis: Optional[LegalBasis] = None
    legal_basis_note: Optional[str] = None
    note: Optional[str] = None


class ActorRelationCreate(ActorRelationBase):
    pass


class ActorRelationResponse(ActorRelationBase):
    id: str
    created_at: datetime

    model_config = {"from_attributes": True}


# ------------------------------------------------------------------
# Actor
# ------------------------------------------------------------------

class ActorBase(BaseModel):
    actor_type: ActorType
    nome: Optional[str] = None
    cognome: Optional[str] = None
    data_nascita: Optional[date] = None
    luogo_nascita: Optional[str] = None
    sesso: Optional[str] = Field(default=None, max_length=1)
    denominazione: Optional[str] = None
    codice_fiscale: Optional[str] = None
    partita_iva: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    pec: Optional[str] = None
    note: Optional[str] = None


class ActorCreate(ActorBase):
    addresses: Optional[List[ActorAddressCreate]] = None
    ibans: Optional[List[ActorIbanCreate]] = None


class ActorUpdate(BaseModel):
    actor_type: Optional[ActorType] = None
    nome: Optional[str] = None
    cognome: Optional[str] = None
    data_nascita: Optional[date] = None
    luogo_nascita: Optional[str] = None
    sesso: Optional[str] = Field(default=None, max_length=1)
    denominazione: Optional[str] = None
    codice_fiscale: Optional[str] = None
    partita_iva: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    pec: Optional[str] = None
    note: Optional[str] = None


class ActorResponse(ActorBase):
    id: str
    tenant_id: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class ActorDetailResponse(ActorResponse):
    addresses: List[ActorAddressResponse] = []
    ibans: List[ActorIbanResponse] = []
    relations_out: List[ActorRelationResponse] = []
    relations_in: List[ActorRelationResponse] = []


class ActorListResponse(BaseModel):
    items: List[ActorResponse]
    total: int


class ActorSummaryResponse(BaseModel):
    """
    Versione minimizzata di Actor pensata per la search.

    Non espone email/telefono/indirizzo. CF/PIVA mascherati: si vedono
    solo i primi 3 e gli ultimi 3 caratteri (es. "RSS***SRO80" → utile
    per distinguere duplicati senza dare via il dato completo).
    Il dato completo lo si ottiene solo via GET /actors/{id}, che è a
    sua volta autorizzato + audit-loggato.
    """
    id: str
    actor_type: ActorType
    display_name: str
    codice_fiscale_masked: Optional[str] = None
    partita_iva_masked: Optional[str] = None


class ActorSummaryListResponse(BaseModel):
    items: List[ActorSummaryResponse]
    total: int


def _mask_identifier(value: Optional[str]) -> Optional[str]:
    """RSSMRA80A01H501Z -> RSS********501Z. Mostra solo prefisso + suffisso."""
    if value is None:
        return None
    v = value.strip()
    if len(v) <= 6:
        return "*" * len(v)
    return f"{v[:3]}{'*' * (len(v) - 6)}{v[-3:]}"


def build_actor_summary(actor) -> ActorSummaryResponse:
    """Helper per costruire il summary minimizzato da un Actor SQLAlchemy."""
    if actor.actor_type == "person":
        display = " ".join(filter(None, [actor.nome, actor.cognome])).strip() or (actor.denominazione or "—")
    else:
        display = actor.denominazione or "—"
    return ActorSummaryResponse(
        id=actor.id,
        actor_type=actor.actor_type,
        display_name=display,
        codice_fiscale_masked=_mask_identifier(actor.codice_fiscale),
        partita_iva_masked=_mask_identifier(actor.partita_iva),
    )


# ------------------------------------------------------------------
# Snapshot embedded nei sinistri
# ------------------------------------------------------------------

class ActorAddressSnapshot(BaseModel):
    """Indirizzo fotografato al momento d'uso (es. creazione sinistro)."""
    indirizzo: Optional[str] = None
    civico: Optional[str] = None
    cap: Optional[str] = None
    citta: Optional[str] = None
    provincia: Optional[str] = None
    nazione: Optional[str] = None


class ActorIbanSnapshot(BaseModel):
    iban: Optional[str] = None
    intestatario: Optional[str] = None
    banca: Optional[str] = None


# ------------------------------------------------------------------
# Indici derivati
# ------------------------------------------------------------------

class ActorAgencyLinkResponse(BaseModel):
    actor_id: str
    agency_id: str
    first_seen_claim_id: Optional[str] = None
    last_seen_claim_id: Optional[str] = None
    last_seen_at: datetime
    claim_count: int

    model_config = {"from_attributes": True}


class ActorCompanyLinkResponse(BaseModel):
    actor_id: str
    compagnia_id: str
    first_seen_claim_id: Optional[str] = None
    last_seen_claim_id: Optional[str] = None
    last_seen_at: datetime
    claim_count: int

    model_config = {"from_attributes": True}
