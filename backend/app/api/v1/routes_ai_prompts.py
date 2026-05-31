"""
Admin CRUD per i template di prompt AI.

- GET    /api/v1/ai-prompts                → lista (default globali + override del proprio tenant)
- GET    /api/v1/ai-prompts/{key}          → template effettivo per il tenant corrente
- PUT    /api/v1/ai-prompts/{key}          → crea o aggiorna l'override per il tenant
- DELETE /api/v1/ai-prompts/{key}          → rimuove l'override del tenant (resta il default globale)
- PUT    /api/v1/ai-prompts/global/{key}   → crea/aggiorna il default globale (solo platform_admin)

L'aggiornamento incrementa `version` e registra `updated_by_user_id`.
"""
from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.ai_prompt_template import AIPromptTemplate
from app.models.user import User


router = APIRouter()


class AIPromptIn(BaseModel):
    title: str
    description: Optional[str] = None
    body: str
    variables: Optional[list[str]] = None


class AIPromptOut(BaseModel):
    id: str
    tenant_id: Optional[str]
    key: str
    title: str
    description: Optional[str]
    body: str
    variables: Optional[list[str]]
    version: int
    updated_by_user_id: Optional[str]

    @classmethod
    def from_model(cls, row: AIPromptTemplate) -> "AIPromptOut":
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            key=row.key,
            title=row.title,
            description=row.description,
            body=row.body,
            variables=row.variables_json,
            version=row.version,
            updated_by_user_id=row.updated_by_user_id,
        )


@router.get("", response_model=list[AIPromptOut])
async def list_prompts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Lista i template visibili dal tenant: globali + override del tenant."""
    rows = (
        await db.execute(
            select(AIPromptTemplate).where(
                or_(
                    AIPromptTemplate.tenant_id == current_user.tenant_id,
                    AIPromptTemplate.tenant_id.is_(None),
                )
            )
        )
    ).scalars().all()
    return [AIPromptOut.from_model(r) for r in rows]


@router.get("/{key}", response_model=AIPromptOut)
async def get_prompt(
    key: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Ritorna il template effettivo per il tenant (override → default globale)."""
    rows = (
        await db.execute(
            select(AIPromptTemplate).where(
                AIPromptTemplate.key == key,
                or_(
                    AIPromptTemplate.tenant_id == current_user.tenant_id,
                    AIPromptTemplate.tenant_id.is_(None),
                ),
            )
        )
    ).scalars().all()
    if not rows:
        raise HTTPException(status_code=404, detail=f"Prompt {key!r} not found")
    tenant_specific = next((r for r in rows if r.tenant_id == current_user.tenant_id), None)
    return AIPromptOut.from_model(tenant_specific or rows[0])


async def _upsert(
    db: AsyncSession,
    tenant_id: Optional[str],
    key: str,
    data: AIPromptIn,
    user: User,
) -> AIPromptTemplate:
    existing = (
        await db.execute(
            select(AIPromptTemplate).where(
                AIPromptTemplate.key == key,
                AIPromptTemplate.tenant_id.is_(None) if tenant_id is None
                else AIPromptTemplate.tenant_id == tenant_id,
            )
        )
    ).scalar_one_or_none()

    if existing is None:
        row = AIPromptTemplate(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            key=key,
            title=data.title,
            description=data.description,
            body=data.body,
            variables_json=data.variables,
            version=1,
            updated_by_user_id=user.id,
        )
        db.add(row)
    else:
        existing.title = data.title
        existing.description = data.description
        existing.body = data.body
        existing.variables_json = data.variables
        existing.version = (existing.version or 1) + 1
        existing.updated_by_user_id = user.id
        row = existing

    await db.commit()
    await db.refresh(row)
    return row


@router.put("/{key}", response_model=AIPromptOut)
async def upsert_tenant_prompt(
    key: str,
    data: AIPromptIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Crea o aggiorna l'override del prompt per il tenant corrente."""
    row = await _upsert(db, current_user.tenant_id, key, data, current_user)
    return AIPromptOut.from_model(row)


@router.delete("/{key}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_tenant_prompt(
    key: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Rimuove l'override del tenant. Il default globale resta intatto."""
    existing = (
        await db.execute(
            select(AIPromptTemplate).where(
                AIPromptTemplate.key == key,
                AIPromptTemplate.tenant_id == current_user.tenant_id,
            )
        )
    ).scalar_one_or_none()
    if existing is None:
        raise HTTPException(status_code=404, detail="No tenant override for this key")
    await db.delete(existing)
    await db.commit()


@router.put("/global/{key}", response_model=AIPromptOut)
async def upsert_global_prompt(
    key: str,
    data: AIPromptIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Crea o aggiorna il default globale. Solo platform_admin."""
    if not getattr(current_user, "is_platform_admin", False):
        raise HTTPException(status_code=403, detail="platform_admin required")
    row = await _upsert(db, None, key, data, current_user)
    return AIPromptOut.from_model(row)
