"""
Claim schemas
"""
from datetime import datetime
from decimal import Decimal
from typing import List, Literal, Optional

from pydantic import BaseModel

from app.core.claim_status import ClaimStatus
from app.schemas.actor import (
    ActorAddressSnapshot,
    ActorCreate,
    ActorIbanSnapshot,
)


class SubstatoEntry(BaseModel):
    tag: str
    source: Literal["user", "ai", "system"]
    added_at: Optional[str] = None


class ClaimBase(BaseModel):
    external_ref: Optional[str] = None
    numero_sinistro: Optional[str] = None
    compagnia: Optional[str] = None
    stato_corrente: ClaimStatus
    stato_substati: List[SubstatoEntry] = []
    garanzia: str = "Fenomeno Elettrico"
    agenzia: Optional[str] = None
    # Campi piatti legacy — vengono ancora popolati dal claim_service per
    # retro-compatibilità con i client che non sanno degli Actor. Andranno
    # rimossi una volta migrati iOS / portal-web.
    nome_assicurato: Optional[str] = None
    email_assicurato: Optional[str] = None
    telefono_assicurato: Optional[str] = None
    indirizzo_assicurato: Optional[str] = None
    nome_contraente: Optional[str] = None
    nome_danneggiato: Optional[str] = None
    data_sinistro: Optional[datetime] = None
    richiesta: Optional[Decimal] = None
    liquidato: Optional[Decimal] = None
    numero_polizza: Optional[str] = None
    tipo_polizza: Optional[str] = None

    # --- Riferimenti ad anagrafica unificata (Actor) ------------------
    contraente_id: Optional[str] = None
    assicurato_id: Optional[str] = None
    danneggiato_id: Optional[str] = None
    agency_id: Optional[str] = None
    compagnia_id: Optional[str] = None


class ClaimActorInput(BaseModel):
    """
    Modalità di passaggio di un attore in creazione/aggiornamento sinistro.

    Opzioni mutuamente esclusive:
      * actor_id: si riferisce a un attore esistente.
      * actor_data: payload anagrafico da upsertare (per CF/PIVA).

    `address_id` e `iban_id` (opzionali) selezionano quale indirizzo/IBAN
    dell'attore va snapshottato sul sinistro. Se omessi, viene usato il
    primary (o il più recente).
    """
    actor_id: Optional[str] = None
    actor_data: Optional[ActorCreate] = None
    address_id: Optional[str] = None
    iban_id: Optional[str] = None


class ClaimCreate(ClaimBase):
    # Input strutturati che hanno priorità sui campi piatti quando passati.
    contraente: Optional[ClaimActorInput] = None
    assicurato: Optional[ClaimActorInput] = None
    danneggiato: Optional[ClaimActorInput] = None


class ClaimUpdate(ClaimBase):
    version: int  # For optimistic locking
    contraente: Optional[ClaimActorInput] = None
    assicurato: Optional[ClaimActorInput] = None
    danneggiato: Optional[ClaimActorInput] = None


class ClaimResponse(ClaimBase):
    id: str
    tenant_id: str
    created_at: datetime
    updated_at: datetime
    closed_at: Optional[datetime] = None
    priority: int
    version: int

    contraente_address_snapshot: Optional[ActorAddressSnapshot] = None
    assicurato_address_snapshot: Optional[ActorAddressSnapshot] = None
    danneggiato_address_snapshot: Optional[ActorAddressSnapshot] = None
    iban_snapshot: Optional[ActorIbanSnapshot] = None

    class Config:
        from_attributes = True


class ClaimListResponse(BaseModel):
    items: List[ClaimResponse]
    total: int
    page: int
    page_size: int


class ClaimStateTransitionRequest(BaseModel):
    from_state: Optional[str] = None
    to_state: str
    reason: Optional[str] = None
    payload: Optional[dict] = None
    # Substato implicito per stati come SOPRALLUOGO (es. "fissato", "da_fissare").
    # Permette al client di propagare il substato corretto in un'unica chiamata.
    sopralluogo_substato: Optional[str] = None


class ClaimAssignmentRequest(BaseModel):
    assignee_user_id: str
    reason: Optional[str] = None


class ClaimEventResponse(BaseModel):
    id: str
    claim_id: str
    event_type: str
    event_time: datetime
    actor_user_id: Optional[str] = None
    data_json: Optional[dict] = None
    source: str
    
    class Config:
        from_attributes = True
