"""
Schemas for the CAT Dispatcher integration.
"""
from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


InterventionType = Literal["sopralluogo", "rfs", "both"]


class CatDispatcherAddressLookupRequest(BaseModel):
    address: Optional[str] = None
    comune: Optional[str] = None
    provincia: Optional[str] = None
    intervention_type: InterventionType = "sopralluogo"


class CatDispatcherCommuneLookupRequest(BaseModel):
    comune: str = Field(min_length=1)
    provincia: Optional[str] = None


class CatDispatcherLookupResponse(BaseModel):
    model_config = ConfigDict(extra="allow")

    success: bool
    cat_name: Optional[str] = None
    cat_alias: Optional[str] = None
    commune_name: Optional[str] = None
    multiple_cats: Optional[bool] = None
    needs_geocoding: Optional[bool] = None
    suspended: Optional[bool] = None
    suspension_reason: Optional[str] = None
    suspension_end_date: Optional[str] = None
    error: Optional[str] = None
