"""
Claim schemas
"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from decimal import Decimal


class ClaimBase(BaseModel):
    external_ref: Optional[str] = None
    numero_sinistro: Optional[str] = None
    compagnia: Optional[str] = None
    stato_corrente: str
    agenzia: Optional[str] = None
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


class ClaimCreate(ClaimBase):
    pass


class ClaimUpdate(ClaimBase):
    version: int  # For optimistic locking


class ClaimResponse(ClaimBase):
    id: str
    tenant_id: str
    created_at: datetime
    updated_at: datetime
    closed_at: Optional[datetime] = None
    priority: int
    version: int
    
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

