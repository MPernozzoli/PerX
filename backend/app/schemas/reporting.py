"""
Reporting schemas
"""
from datetime import datetime
from pydantic import BaseModel, Field


class ConsuntivoDailyStatResponse(BaseModel):
    giorno: int
    assegnazioni: int = 0
    chiusure: int = 0
    atti_inviati: int = 0


class ConsuntivoCompanyStatResponse(BaseModel):
    codice_compagnia: str
    nome_compagnia: str
    gruppo_compagnia: str | None = None
    assegnazioni: int = 0
    chiusure: int = 0
    atti_inviati: int = 0
    liquidato_totale: float = 0


class ConsuntivoClaimItemResponse(BaseModel):
    id: str
    riferimento: str
    stato: str
    nome_assicurato: str
    nome_compagnia: str
    data_assegnazione: datetime | None = None
    data_chiusura: datetime | None = None
    stima_danno: float | None = None
    liquidato: float | None = None


class ConsuntivoMonthResponse(BaseModel):
    anno: int
    mese: int
    scope: str
    sinistri_assegnati: int = 0
    sinistri_chiusi: int = 0
    tot_liquidato: float = 0
    tot_compensi: float = 0
    tot_danno: float = 0
    atti_inviati: int = 0
    media_giornaliera: float = 0
    daily_stats: list[ConsuntivoDailyStatResponse] = Field(default_factory=list)
    company_stats: list[ConsuntivoCompanyStatResponse] = Field(default_factory=list)
    sinistri_del_mese: list[ConsuntivoClaimItemResponse] = Field(default_factory=list)
