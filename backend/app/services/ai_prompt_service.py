"""
Caricamento e rendering dei prompt AI editabili.

Pattern d'uso:
    body = await AIPromptService.render(
        db, tenant_id, "perizia.beni",
        ref=claim.external_ref, beni_list=...,
    )

Lookup:
- prima cerca una riga con `tenant_id=<tenant>` e `key=<key>`;
- in fallback usa la riga `tenant_id IS NULL, key=<key>` (default globale);
- se nessuna riga esiste, solleva `PromptNotFoundError`.

Rendering:
- usa `str.format_map` con default `""` per le variabili non passate;
- mantiene la sintassi `{var}` (singole graffe). Eventuali `{{var}}`
  Python-escape vengono ridotti a `{var}` come per str.format normale.
"""
from __future__ import annotations

from typing import Optional

from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ai_prompt_template import AIPromptTemplate


class PromptNotFoundError(LookupError):
    pass


class _SafeDict(dict):
    def __missing__(self, key: str) -> str:  # noqa: D401
        return ""


class AIPromptService:
    @staticmethod
    async def get_template(
        db: AsyncSession,
        tenant_id: Optional[str],
        key: str,
    ) -> AIPromptTemplate:
        """Ritorna il template più specifico disponibile per (tenant, key).

        Strategia: una sola query che prende tenant-specific + default; preferisce
        il tenant-specific se presente.
        """
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

    @staticmethod
    async def render(
        db: AsyncSession,
        tenant_id: Optional[str],
        key: str,
        **variables,
    ) -> str:
        template = await AIPromptService.get_template(db, tenant_id, key)
        return template.body.format_map(_SafeDict(variables))
