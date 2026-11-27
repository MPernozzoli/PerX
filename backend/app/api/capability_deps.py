"""Dipendenze che chiudono le funzioni fuori dal profilo del tenant."""
from fastapi import Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.domain.tenant_capabilities import allows
from app.models.tenant import Tenant
from app.models.user import User

CAPABILITY_DENIED = "Questa funzione non è disponibile per questo studio."


async def tenant_allows(db: AsyncSession, tenant_id: str | None, capability: str) -> bool:
    if not tenant_id:
        return False
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        return False
    return allows(tenant.settings_json, capability)


async def assert_tenant_capability(db: AsyncSession, tenant_id: str | None, capability: str) -> None:
    if not await tenant_allows(db, tenant_id, capability):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=CAPABILITY_DENIED)


def require_capability(capability: str):
    async def _checker(
        db: AsyncSession = Depends(get_db),
        current_user: User = Depends(get_current_active_user),
    ) -> None:
        await assert_tenant_capability(db, current_user.tenant_id, capability)

    return _checker
