"""
Pydantic schemas per la rubrica compagnie.
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class CompagniaBase(BaseModel):
    nome: str
    gruppo: Optional[str] = None
    codice: Optional[str] = None
    partita_iva: Optional[str] = None
    pec: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    sito_web: Optional[str] = None
    note: Optional[str] = None
    is_active: bool = True


class CompagniaCreate(CompagniaBase):
    pass


class CompagniaUpdate(BaseModel):
    nome: Optional[str] = None
    gruppo: Optional[str] = None
    codice: Optional[str] = None
    partita_iva: Optional[str] = None
    pec: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    sito_web: Optional[str] = None
    note: Optional[str] = None
    is_active: Optional[bool] = None


class CompagniaResponse(CompagniaBase):
    id: str
    tenant_id: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class CompagniaListResponse(BaseModel):
    items: List[CompagniaResponse]
    total: int
