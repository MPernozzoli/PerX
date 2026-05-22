"""
Pydantic schemas for rubrica (agenzie e liquidatori)
"""
from __future__ import annotations
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel


# ------------------------------------------------------------------
# Agenzia
# ------------------------------------------------------------------

class AgenziaBase(BaseModel):
    nome: str
    codice: Optional[str] = None
    indirizzo: Optional[str] = None
    citta: Optional[str] = None
    provincia: Optional[str] = None
    telefono: Optional[str] = None
    email: Optional[str] = None
    compagnia: Optional[str] = None
    gruppo: Optional[str] = None
    note: Optional[str] = None
    is_active: bool = True


class AgenziaCreate(AgenziaBase):
    pass


class AgenziaUpdate(BaseModel):
    nome: Optional[str] = None
    codice: Optional[str] = None
    indirizzo: Optional[str] = None
    citta: Optional[str] = None
    provincia: Optional[str] = None
    telefono: Optional[str] = None
    email: Optional[str] = None
    compagnia: Optional[str] = None
    gruppo: Optional[str] = None
    note: Optional[str] = None
    is_active: Optional[bool] = None


class AgenziaResponse(AgenziaBase):
    id: str
    tenant_id: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class AgenziaListResponse(BaseModel):
    items: List[AgenziaResponse]
    total: int


# ------------------------------------------------------------------
# Liquidatore
# ------------------------------------------------------------------

class LiquidatoreBase(BaseModel):
    nome: Optional[str] = None
    cognome: str
    email: Optional[str] = None
    telefono: Optional[str] = None
    compagnia: Optional[str] = None
    zona: Optional[str] = None
    is_active: bool = True
    note: Optional[str] = None


class LiquidatoreCreate(LiquidatoreBase):
    pass


class LiquidatoreUpdate(BaseModel):
    nome: Optional[str] = None
    cognome: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    compagnia: Optional[str] = None
    zona: Optional[str] = None
    is_active: Optional[bool] = None
    note: Optional[str] = None


class LiquidatoreResponse(LiquidatoreBase):
    id: str
    tenant_id: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class LiquidatoreListResponse(BaseModel):
    items: List[LiquidatoreResponse]
    total: int


# ------------------------------------------------------------------
# Combined sync response
# ------------------------------------------------------------------

class RubricaAllResponse(BaseModel):
    agenzie: List[AgenziaResponse]
    liquidatori: List[LiquidatoreResponse]
    synced_at: datetime
