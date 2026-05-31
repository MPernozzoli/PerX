"""
Storico durata effettiva sopralluoghi per CAT.

Espone:
- `bucket_for_asset_count` — bucket coerente tra scrittura e lettura.
- `load_median_minutes` — lettura della mediana per (tenant, cat, bucket)
  con soglia minima di campioni.
- `recompute_for_tenant` — placeholder pronto per essere riempito quando
  l'iPad CAT inizierà a registrare actual_start_at / actual_end_at sui
  sopralluoghi (oggi `InspectionRouteStop` ha solo i tempi pianificati,
  quindi calcolare una mediana sarebbe circolare).

Finché non arrivano gli actuals il metodo `recompute_for_tenant` non
scrive nulla e `load_median_minutes` restituirà `None`, lasciando che
il planner usi la formula di default (20 min + 5/asset oltre il 3°).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.route_planning import CatInspectionDurationStat

MIN_SAMPLE_SIZE = 5


@dataclass(frozen=True)
class CatDurationStat:
    median_minutes: int
    sample_size: int


def bucket_for_asset_count(asset_count: int) -> int:
    if asset_count <= 1:
        return 1
    if asset_count == 2:
        return 2
    if asset_count == 3:
        return 3
    if asset_count <= 6:
        return 6
    if asset_count <= 10:
        return 10
    return 11


async def load_median_minutes(
    db: AsyncSession,
    tenant_id: str,
    cat_user_id: str,
    asset_count: int,
) -> Optional[CatDurationStat]:
    bucket = bucket_for_asset_count(asset_count)
    row = (
        await db.execute(
            select(CatInspectionDurationStat).where(
                CatInspectionDurationStat.tenant_id == tenant_id,
                CatInspectionDurationStat.cat_user_id == cat_user_id,
                CatInspectionDurationStat.asset_count_bucket == bucket,
            )
        )
    ).scalar_one_or_none()
    if row is None or row.sample_size < MIN_SAMPLE_SIZE:
        return None
    return CatDurationStat(median_minutes=row.median_minutes, sample_size=row.sample_size)


async def recompute_for_tenant(db: AsyncSession, tenant_id: str) -> int:
    """No-op finché non esistono actual_start_at/actual_end_at sui sopralluoghi.

    Quando i tempi reali saranno tracciati, leggere i sopralluoghi chiusi
    ultimi 90 giorni, raggrupparli per (cat_user_id, asset_count_bucket),
    calcolare la mediana dei minuti effettivi e fare upsert su
    `cat_inspection_duration_stats`. Restituisce il numero di righe scritte.
    """
    _ = tenant_id
    return 0
