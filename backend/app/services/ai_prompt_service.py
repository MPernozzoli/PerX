"""
Caricamento, versioning, rendering e routing dei prompt AI.

Lookup template:
- prima cerca una riga con `tenant_id=<tenant>` e `key=<key>`;
- in fallback usa la riga `tenant_id IS NULL, key=<key>` (default globale);
- se nessuna riga esiste, solleva `PromptNotFoundError`.

Versioning:
- ogni `commit_version(template)` calcola un `version_id` short-hash (8 char)
  derivato da `(template.id, body)` e crea una riga immutabile in
  `ai_prompt_template_versions`. Se la stessa coppia (template, body) è già
  stata committata, riusa la riga (idempotente).
- `template.current_version_id` viene aggiornato per puntare alla versione
  appena committata.
- per riprocessare un'analisi vecchia il client passa il `version_id` salvato
  in `ai_analysis_runs` e ottiene il body identico a quello usato allora
  tramite `get_version_body`.

Rendering:
- usa `str.format_map` con default `""` per le variabili non passate;
- accetta opzionalmente un `version_id` per renderizzare una versione storica
  invece del body corrente.

Routing policy:
- lookup (tenant, phase, trigger) -> mode con fallback al default globale.
- se nessuna riga esiste -> `prefer_local` (scelta conservativa: il client
  prova prima il locale e cade su cloud al primo errore/output malformato).
"""
from __future__ import annotations

import hashlib
import uuid
from typing import Optional

from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ai_prompt_template import AIPromptTemplate
from app.models.ai_prompt_template_version import AIPromptTemplateVersion
from app.models.ai_routing_policy import AIRoutingPolicy


class PromptNotFoundError(LookupError):
    pass


class PromptVersionNotFoundError(LookupError):
    pass


class _SafeDict(dict):
    def __missing__(self, key: str) -> str:  # noqa: D401
        return ""


def short_version_id(template_id: str, body: str) -> str:
    """Hash stabile 8 char. Stesso (template, body) -> stessa version_id.

    Coerente con il backfill della migration 030.
    """
    h = hashlib.sha1(f"{template_id}\x00{body}".encode("utf-8")).hexdigest()
    return h[:8]


class AIPromptService:
    # --- Template lookup -----------------------------------------------------

    @staticmethod
    async def get_template(
        db: AsyncSession,
        tenant_id: Optional[str],
        key: str,
    ) -> AIPromptTemplate:
        """Template più specifico disponibile per (tenant, key)."""
        result = await db.execute(
            select(AIPromptTemplate).where(
                AIPromptTemplate.key == key,
                or_(
                    AIPromptTemplate.tenant_id == tenant_id,
                    AIPromptTemplate.tenant_id.is_(None),
                ),
            )
        )
        rows = result.scalars().all()
        if not rows:
            raise PromptNotFoundError(f"No prompt template found for key={key!r}")
        tenant_specific = next((r for r in rows if r.tenant_id == tenant_id), None)
        return tenant_specific or rows[0]

    # --- Versioning ----------------------------------------------------------

    @staticmethod
    async def commit_version(
        db: AsyncSession,
        template: AIPromptTemplate,
        user_id: Optional[str] = None,
        changelog: Optional[str] = None,
    ) -> AIPromptTemplateVersion:
        """Crea (o riusa) una riga in ai_prompt_template_versions per il body
        corrente del template e aggiorna `template.current_version_id`.

        Idempotente: lo stesso body produce sempre lo stesso `version_id`, e
        la unique constraint (template_id, version_id) evita duplicati.
        """
        body = template.body or ""
        version_id = short_version_id(template.id, body)

        existing = (
            await db.execute(
                select(AIPromptTemplateVersion).where(
                    AIPromptTemplateVersion.template_id == template.id,
                    AIPromptTemplateVersion.version_id == version_id,
                )
            )
        ).scalar_one_or_none()

        if existing is None:
            existing = AIPromptTemplateVersion(
                id=str(uuid.uuid4()),
                template_id=template.id,
                version_id=version_id,
                body=body,
                variables_json=template.variables_json,
                changelog=changelog,
                created_by_user_id=user_id,
            )
            db.add(existing)

        template.current_version_id = version_id
        # caller commits

        return existing

    @staticmethod
    async def get_version(
        db: AsyncSession,
        template_id: str,
        version_id: str,
    ) -> AIPromptTemplateVersion:
        row = (
            await db.execute(
                select(AIPromptTemplateVersion).where(
                    AIPromptTemplateVersion.template_id == template_id,
                    AIPromptTemplateVersion.version_id == version_id,
                )
            )
        ).scalar_one_or_none()
        if row is None:
            raise PromptVersionNotFoundError(
                f"No version {version_id!r} for template {template_id!r}"
            )
        return row

    @staticmethod
    async def list_versions(
        db: AsyncSession,
        template_id: str,
    ) -> list[AIPromptTemplateVersion]:
        rows = (
            await db.execute(
                select(AIPromptTemplateVersion)
                .where(AIPromptTemplateVersion.template_id == template_id)
                .order_by(AIPromptTemplateVersion.created_at.desc())
            )
        ).scalars().all()
        return list(rows)

    # --- Rendering -----------------------------------------------------------

    @staticmethod
    async def render(
        db: AsyncSession,
        tenant_id: Optional[str],
        key: str,
        *,
        version_id: Optional[str] = None,
        **variables,
    ) -> str:
        """Renderizza il prompt corrente (o una versione storica se passata).

        version_id != None ⇒ usa lo storico (audit / riprocessing).
        """
        template = await AIPromptService.get_template(db, tenant_id, key)
        if version_id is not None:
            version = await AIPromptService.get_version(db, template.id, version_id)
            body = version.body
        else:
            body = template.body
        return body.format_map(_SafeDict(variables))

    # --- Routing policy ------------------------------------------------------

    @staticmethod
    async def get_routing_mode(
        db: AsyncSession,
        tenant_id: Optional[str],
        phase: str,
        trigger: str,
    ) -> str:
        """Mode di routing per (tenant, phase, trigger).

        Lookup: tenant-specific -> default globale -> 'prefer_local' come
        fallback (il client tenterà locale e cadrà su cloud al primo errore).
        """
        rows = (
            await db.execute(
                select(AIRoutingPolicy).where(
                    AIRoutingPolicy.phase == phase,
                    AIRoutingPolicy.trigger == trigger,
                    or_(
                        AIRoutingPolicy.tenant_id == tenant_id,
                        AIRoutingPolicy.tenant_id.is_(None),
                    ),
                )
            )
        ).scalars().all()
        if not rows:
            return "prefer_local"
        tenant_specific = next((r for r in rows if r.tenant_id == tenant_id), None)
        return (tenant_specific or rows[0]).mode
