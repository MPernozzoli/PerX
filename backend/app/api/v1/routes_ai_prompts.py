"""
Admin CRUD per i template di prompt AI + history versioni.

- GET    /api/v1/ai-prompts                          → lista visibile dal tenant
- GET    /api/v1/ai-prompts/{key}                    → template effettivo
- PUT    /api/v1/ai-prompts/{key}                    → upsert override tenant (commit nuova version)
- DELETE /api/v1/ai-prompts/{key}                    → rimuove override tenant
- PUT    /api/v1/ai-prompts/global/{key}             → upsert default globale (commit nuova version)
- GET    /api/v1/ai-prompts/{key}/versions           → storico versioni del template effettivo
- GET    /api/v1/ai-prompts/{key}/versions/{vid}     → body specifico (per riprocessing / audit)

Ogni PUT crea una nuova riga in `ai_prompt_template_versions` (idempotente
sul body: stesso body = stessa version_id) e aggiorna `current_version_id`.
"""
from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_platform_admin
from app.models.ai_prompt_template import AIPromptTemplate
from app.models.ai_prompt_template_version import AIPromptTemplateVersion
from app.models.user import User
from app.services.ai_prompt_service import AIPromptService


router = APIRouter()


class AIPromptIn(BaseModel):
    title: str
    description: Optional[str] = None
    body: str
    variables: Optional[list[str]] = None
    changelog: Optional[str] = None  # opzionale, registrato sulla version creata


class AIPromptOut(BaseModel):
    id: str
    tenant_id: Optional[str]
    key: str
    title: str
    description: Optional[str]
    body: str
    variables: Optional[list[str]]
    version: int
    current_version_id: Optional[str]
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
            current_version_id=row.current_version_id,
            updated_by_user_id=row.updated_by_user_id,
        )


class AIPromptVersionOut(BaseModel):
    version_id: str
    body: str
    variables: Optional[list[str]]
    changelog: Optional[str]
    created_at: str
    created_by_user_id: Optional[str]

    @classmethod
    def from_model(cls, row: AIPromptTemplateVersion) -> "AIPromptVersionOut":
        return cls(
            version_id=row.version_id,
            body=row.body,
            variables=row.variables_json,
            changelog=row.changelog,
            created_at=row.created_at.isoformat() if row.created_at else "",
            created_by_user_id=row.created_by_user_id,
        )


@router.get("", response_model=list[AIPromptOut])
async def list_prompts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
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
    current_user: User = Depends(get_current_platform_admin),
):
    """Template effettivo per il tenant (override → default globale)."""
    try:
        row = await AIPromptService.get_template(db, current_user.tenant_id, key)
    except LookupError:
        raise HTTPException(status_code=404, detail=f"Prompt {key!r} not found")
    return AIPromptOut.from_model(row)


@router.get("/{key}/versions", response_model=list[AIPromptVersionOut])
async def list_prompt_versions(
    key: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    """Storico versioni del template effettivo per il tenant."""
    try:
        template = await AIPromptService.get_template(db, current_user.tenant_id, key)
    except LookupError:
        raise HTTPException(status_code=404, detail=f"Prompt {key!r} not found")
    versions = await AIPromptService.list_versions(db, template.id)
    return [AIPromptVersionOut.from_model(v) for v in versions]


@router.get("/{key}/versions/{version_id}", response_model=AIPromptVersionOut)
async def get_prompt_version(
    key: str,
    version_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    """Body di una versione storica (per riprocessing o audit)."""
    try:
        template = await AIPromptService.get_template(db, current_user.tenant_id, key)
        version = await AIPromptService.get_version(db, template.id, version_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    return AIPromptVersionOut.from_model(version)


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
        await db.flush()  # serve id per commit_version
    else:
        existing.title = data.title
        existing.description = data.description
        existing.body = data.body
        existing.variables_json = data.variables
        existing.version = (existing.version or 1) + 1
        existing.updated_by_user_id = user.id
        row = existing

    # crea/riusa la riga immutabile in ai_prompt_template_versions e aggiorna
    # row.current_version_id
    await AIPromptService.commit_version(
        db, row, user_id=user.id, changelog=data.changelog
    )

    await db.commit()
    await db.refresh(row)
    return row


@router.put("/{key}", response_model=AIPromptOut)
async def upsert_tenant_prompt(
    key: str,
    data: AIPromptIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    """Crea o aggiorna l'override del prompt per il tenant corrente."""
    row = await _upsert(db, current_user.tenant_id, key, data, current_user)
    return AIPromptOut.from_model(row)


@router.delete("/{key}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_tenant_prompt(
    key: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    """Rimuove l'override del tenant. Il default globale resta intatto.

    Le versioni storiche dell'override vengono droppate per CASCADE; il
    log `ai_analysis_runs` conserva comunque il `prompt_version_id` come
    riferimento storico (FK non posta per non vincolare l'audit).
    """
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
    current_user: User = Depends(get_current_platform_admin),
):
    """Crea o aggiorna il default globale. Solo platform_admin."""
    row = await _upsert(db, None, key, data, current_user)
    return AIPromptOut.from_model(row)
