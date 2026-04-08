"""
Platform-admin routes
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_platform_admin
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.admin import TenantResponse, AdminUserResponse

router = APIRouter()


@router.get("/tenants", response_model=list[TenantResponse])
async def list_tenants(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin)
):
    result = await db.execute(select(Tenant).order_by(Tenant.name.asc()))
    return [TenantResponse.model_validate(item) for item in result.scalars().all()]


@router.get("/users", response_model=list[AdminUserResponse])
async def list_users(
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin)
):
    query = select(User).order_by(User.email.asc())
    if tenant_id:
        query = query.where(User.tenant_id == tenant_id)

    result = await db.execute(query)
    return [AdminUserResponse.model_validate(item) for item in result.scalars().all()]
