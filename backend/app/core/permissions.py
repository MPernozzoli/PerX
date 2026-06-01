"""
Authorization helpers riusabili.

Concentriamo qui il calcolo del set di ruoli normalizzati di un utente
(`admin` / `perito`) e i predicati di livello applicativo che derivano
da quei ruoli (es. `is_studio_admin`).

Le query usano `user_roles` (tabella di associazione) + `roles.name` con
una normalizzazione: i nomi DB legacy `admin_tenant` e `expert` vengono
mappati su `admin` e `perito` rispettivamente.
"""
from __future__ import annotations

from typing import Set

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.role import Role, user_roles


_LEGACY_ROLE_MAP = {
    "admin_tenant": "admin",
    "expert": "perito",
}


async def get_user_role_names(db: AsyncSession, user_id: str) -> Set[str]:
    """Ritorna l'insieme dei ruoli normalizzati per l'utente."""
    result = await db.execute(
        select(Role.name)
        .select_from(user_roles.join(Role, user_roles.c.role_id == Role.id))
        .where(user_roles.c.user_id == user_id)
    )
    out: Set[str] = set()
    for row in result.all():
        raw = row[0]
        out.add(_LEGACY_ROLE_MAP.get(raw, raw))
    return out


async def is_studio_admin(db: AsyncSession, user_id: str) -> bool:
    """
    True se l'utente ha ruolo amministrativo nel proprio studio. Gli admin
    studio hanno visibilità completa sull'anagrafica del tenant (necessaria
    per gestione contabile/fiscale e per le GDPR access requests).
    """
    roles = await get_user_role_names(db, user_id)
    return "admin" in roles
