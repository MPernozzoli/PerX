"""
Reporting routes
"""
from collections import defaultdict
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim import Claim
from app.models.claim_assignment import ClaimAssignment
from app.models.user import User
from app.schemas.reporting import (
    ConsuntivoClaimItemResponse,
    ConsuntivoCompanyStatResponse,
    ConsuntivoDailyStatResponse,
    ConsuntivoMonthResponse,
)

router = APIRouter()


def _month_bounds(year: int, month: int) -> tuple[datetime, datetime]:
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    if month == 12:
        end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
    return start, end


def _in_range(value: datetime | None, start: datetime, end: datetime) -> bool:
    if value is None:
        return False
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return start <= value < end


def _float(value) -> float:
    return float(value or 0)


@router.get("/consuntivo", response_model=ConsuntivoMonthResponse)
async def get_monthly_consuntivo(
    year: int = Query(..., ge=2000, le=2100),
    month: int = Query(..., ge=1, le=12),
    mine_only: bool = Query(True),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    start, end = _month_bounds(year, month)

    query = select(Claim).where(Claim.tenant_id == current_user.tenant_id)
    scope = "tenant"

    if mine_only:
        active_assignment_exists = (
            select(ClaimAssignment.claim_id)
            .where(
                ClaimAssignment.tenant_id == current_user.tenant_id,
                ClaimAssignment.assignee_user_id == current_user.id,
                ClaimAssignment.unassigned_at.is_(None),
            )
        )
        query = query.where(
            or_(
                Claim.id.in_(active_assignment_exists),
                and_(Claim.owner_email.is_not(None), Claim.owner_email == current_user.email),
            )
        )
        scoped_result = await db.execute(query)
        claims = list(scoped_result.scalars().all())
        if claims:
            scope = "mine"
        else:
            fallback = await db.execute(select(Claim).where(Claim.tenant_id == current_user.tenant_id))
            claims = list(fallback.scalars().all())
            scope = "tenant_fallback"
    else:
        result = await db.execute(query)
        claims = list(result.scalars().all())

    sinistri_del_mese = [
        claim for claim in claims
        if _in_range(claim.data_assegnazione or claim.created_at, start, end)
    ]
    chiusi_nel_mese = [
        claim for claim in claims
        if _in_range(claim.closed_at, start, end)
    ]
    atti_nel_mese = [
        claim for claim in claims
        if _in_range(claim.data_invio_atto, start, end)
    ]

    daily_map: dict[int, dict[str, int]] = defaultdict(lambda: {"assegnazioni": 0, "chiusure": 0, "atti_inviati": 0})
    for claim in sinistri_del_mese:
        date_value = claim.data_assegnazione or claim.created_at
        if date_value:
            daily_map[date_value.day]["assegnazioni"] += 1
    for claim in chiusi_nel_mese:
        date_value = claim.closed_at
        if date_value:
            daily_map[date_value.day]["chiusure"] += 1
    for claim in atti_nel_mese:
        if claim.data_invio_atto:
            daily_map[claim.data_invio_atto.day]["atti_inviati"] += 1

    company_map: dict[str, dict[str, float | int | str | None]] = defaultdict(
        lambda: {
            "nome_compagnia": "",
            "gruppo_compagnia": None,
            "assegnazioni": 0,
            "chiusure": 0,
            "atti_inviati": 0,
            "liquidato_totale": 0.0,
        }
    )
    for claim in sinistri_del_mese:
        code = claim.compagnia or "Sconosciuta"
        company_map[code]["nome_compagnia"] = claim.compagnia or "Sconosciuta"
        company_map[code]["gruppo_compagnia"] = claim.gruppo
        company_map[code]["assegnazioni"] += 1
    for claim in chiusi_nel_mese:
        code = claim.compagnia or "Sconosciuta"
        company_map[code]["nome_compagnia"] = claim.compagnia or "Sconosciuta"
        company_map[code]["gruppo_compagnia"] = claim.gruppo
        company_map[code]["chiusure"] += 1
        company_map[code]["liquidato_totale"] += _float(claim.liquidato or claim.stima_danno)
    for claim in atti_nel_mese:
        code = claim.compagnia or "Sconosciuta"
        company_map[code]["nome_compagnia"] = claim.compagnia or "Sconosciuta"
        company_map[code]["gruppo_compagnia"] = claim.gruppo
        company_map[code]["atti_inviati"] += 1

    return ConsuntivoMonthResponse(
        anno=year,
        mese=month,
        scope=scope,
        sinistri_assegnati=len(sinistri_del_mese),
        sinistri_chiusi=len(chiusi_nel_mese),
        tot_liquidato=sum(_float(claim.liquidato or claim.stima_danno) for claim in chiusi_nel_mese),
        tot_compensi=0,
        tot_danno=sum(_float(claim.stima_danno) for claim in sinistri_del_mese),
        atti_inviati=len(atti_nel_mese),
        media_giornaliera=(len(chiusi_nel_mese) / 22.0) if chiusi_nel_mese else 0,
        daily_stats=[
            ConsuntivoDailyStatResponse(giorno=day, **values)
            for day, values in sorted(daily_map.items())
        ],
        company_stats=[
            ConsuntivoCompanyStatResponse(
                codice_compagnia=code,
                nome_compagnia=str(values["nome_compagnia"]),
                gruppo_compagnia=values["gruppo_compagnia"],
                assegnazioni=int(values["assegnazioni"]),
                chiusure=int(values["chiusure"]),
                atti_inviati=int(values["atti_inviati"]),
                liquidato_totale=float(values["liquidato_totale"]),
            )
            for code, values in sorted(
                company_map.items(),
                key=lambda item: (int(item[1]["chiusure"]), int(item[1]["assegnazioni"])),
                reverse=True,
            )
        ],
        sinistri_del_mese=[
            ConsuntivoClaimItemResponse(
                id=claim.id,
                riferimento=claim.external_ref or claim.id,
                stato=claim.stato_corrente,
                nome_assicurato=claim.nome_assicurato or "",
                nome_compagnia=claim.compagnia or "",
                data_assegnazione=claim.data_assegnazione or claim.created_at,
                data_chiusura=claim.closed_at,
                stima_danno=_float(claim.stima_danno) if claim.stima_danno is not None else None,
                liquidato=_float(claim.liquidato) if claim.liquidato is not None else None,
            )
            for claim in sorted(
                sinistri_del_mese,
                key=lambda claim: claim.data_assegnazione or claim.created_at or start,
                reverse=True,
            )
        ],
    )
