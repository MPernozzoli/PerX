"""
Audit service: scrittura centralizzata su `audit_log`.

GDPR rationale: ogni accesso a dato personale (lettura, ricerca, modifica)
deve essere tracciato per dimostrare la legittimità del trattamento.
Per le entità "Actor" (anagrafica unificata di contraente/assicurato/
danneggiato) usiamo questo helper per uniformare timestamp, contesto
sinistro (quando disponibile) e ip/user_agent.
"""
from __future__ import annotations

import uuid
from typing import Any, Optional

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit_log import AuditLog


class AuditService:
    @staticmethod
    async def log(
        db: AsyncSession,
        *,
        tenant_id: str,
        user_id: Optional[str],
        action: str,
        entity_type: str,
        entity_id: str,
        details: Optional[dict[str, Any]] = None,
        request: Optional[Request] = None,
        commit: bool = False,
    ) -> AuditLog:
        """
        Scrive una riga in `audit_log`. Per default NON committa: la chiamata
        viene incorporata nella transazione corrente del caller (es. dentro
        un endpoint che già committa l'operazione principale).
        """
        ip = None
        user_agent = None
        if request is not None:
            ip = request.client.host if request.client else None
            user_agent = request.headers.get("user-agent")

        row = AuditLog(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            ip_address=ip,
            user_agent=user_agent,
            details_json=details,
        )
        db.add(row)
        if commit:
            await db.commit()
        else:
            await db.flush()
        return row

    @staticmethod
    async def log_actor_access(
        db: AsyncSession,
        *,
        tenant_id: str,
        user_id: Optional[str],
        actor_id: str,
        action: str,
        claim_context_id: Optional[str] = None,
        extra: Optional[dict[str, Any]] = None,
        request: Optional[Request] = None,
        commit: bool = False,
    ) -> AuditLog:
        """
        Shortcut per accessi/azioni su un Actor. `action` tipico:
          - 'actor_search'   -> entity_id = '*' (la ricerca non ha singolo id)
          - 'actor_view'     -> singolo detail
          - 'actor_create'   -> upsert
          - 'actor_update'
          - 'actor_address_add' / 'actor_iban_add' / 'actor_relation_add'

        `claim_context_id` è il sinistro nel cui contesto sta avvenendo
        l'azione (utile per dimostrare la finalità del trattamento).
        """
        details = dict(extra or {})
        if claim_context_id:
            details["claim_context_id"] = claim_context_id
        return await AuditService.log(
            db,
            tenant_id=tenant_id,
            user_id=user_id,
            action=action,
            entity_type="actor",
            entity_id=actor_id,
            details=details or None,
            request=request,
            commit=commit,
        )
