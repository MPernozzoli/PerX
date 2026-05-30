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
