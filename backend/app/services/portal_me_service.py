"""
Servizi per la sezione "Impostazioni e privacy" del portale assicurato.

Tutto è scopato sulla `PortalSessionContext` corrente: usiamo
`list_accessible_claim_accesses` per espandere multi-claim quando serve
(es. calcolo `eligible_from` per deletion request → max(closed_at) + 5y
attraverso TUTTI i sinistri dell'assicurato).
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.portal_security import PortalSessionContext, normalize_email, normalize_phone_number
from app.models.actor import Actor
from app.models.claim import Claim
from app.models.portal import PortalClaimAccess
from app.models.portal_notifications import PortalNotificationPrefs
from app.models.portal_privacy import (
    PortalConsent,
    PortalDeletionRequest,
    PortalPrivacyPolicy,
)
from app.models.portal_session import PortalSession
from app.services.portal_service import PortalService


# Retention peritale: 5 anni dall'ultimo sinistro chiuso.
RETENTION_YEARS = 5


def _mask(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    v = value.strip()
    if len(v) <= 6:
        return "*" * len(v)
    return f"{v[:3]}{'*' * (len(v) - 6)}{v[-3:]}"


class PortalMeService:
    # ------------------------------------------------------------------
    # Identity resolution
    # ------------------------------------------------------------------

    @staticmethod
    async def _current_access(
        db: AsyncSession, session: PortalSessionContext
    ) -> PortalClaimAccess:
        res = await db.execute(
            select(PortalClaimAccess).where(
                PortalClaimAccess.id == session.portal_access_id,
                PortalClaimAccess.tenant_id == session.tenant_id,
            )
        )
        access = res.scalar_one_or_none()
        if access is None:
            raise ValueError("portal_access_not_found")
        return access

    @staticmethod
    async def _current_actor_id(
        db: AsyncSession, session: PortalSessionContext
    ) -> Optional[str]:
        """L'access è collegata a un claim; recuperiamo l'actor_id del ruolo
        principale (assicurato → contraente → danneggiato in ordine)."""
        access = await PortalMeService._current_access(db, session)
        res = await db.execute(
            select(Claim).where(
                Claim.id == access.claim_id,
                Claim.tenant_id == session.tenant_id,
            )
        )
        claim = res.scalar_one_or_none()
        if claim is None:
            return None
        return claim.assicurato_id or claim.contraente_id or claim.danneggiato_id

    @staticmethod
    async def _current_actor(
        db: AsyncSession, session: PortalSessionContext
    ) -> Optional[Actor]:
        actor_id = await PortalMeService._current_actor_id(db, session)
        if actor_id is None:
            return None
        res = await db.execute(
            select(Actor).where(
                Actor.id == actor_id,
                Actor.tenant_id == session.tenant_id,
            )
        )
        return res.scalar_one_or_none()

    # ------------------------------------------------------------------
    # Profile
    # ------------------------------------------------------------------

    @staticmethod
    async def get_profile(db: AsyncSession, session: PortalSessionContext) -> dict:
        access = await PortalMeService._current_access(db, session)
        actor = await PortalMeService._current_actor(db, session)

        if actor is not None:
            if actor.actor_type == "person":
                display_name = (
                    " ".join(filter(None, [actor.nome, actor.cognome])).strip()
                    or actor.denominazione
                    or access.full_name
                )
            else:
                display_name = actor.denominazione or access.full_name
            return {
                "actor_id": actor.id,
                "display_name": display_name,
                "actor_type": actor.actor_type,
                "codice_fiscale_masked": _mask(actor.codice_fiscale),
                "partita_iva_masked": _mask(actor.partita_iva),
                "data_nascita": actor.data_nascita,
                "luogo_nascita": actor.luogo_nascita,
                "email": actor.email or access.email,
                "phone": actor.telefono or access.phone_number,
                "pec": actor.pec,
            }

        # Fallback: nessun Actor strutturato (sinistro legacy)
        return {
            "actor_id": None,
            "display_name": access.full_name,
            "actor_type": None,
            "codice_fiscale_masked": None,
            "partita_iva_masked": None,
            "data_nascita": None,
            "luogo_nascita": None,
            "email": access.email,
            "phone": access.phone_number,
            "pec": None,
        }

    @staticmethod
    async def update_profile(
        db: AsyncSession,
        session: PortalSessionContext,
        *,
        email: Optional[str] = None,
        phone: Optional[str] = None,
    ) -> tuple[dict, dict]:
        """Aggiorna SOLO email e/o telefono sia su Actor che su PortalClaimAccess.
        Ritorna (profile_dict, changes) con i campi effettivamente cambiati e
        i loro vecchi valori — utile per inviare notifica al vecchio indirizzo."""
        access = await PortalMeService._current_access(db, session)
        actor = await PortalMeService._current_actor(db, session)

        changes: dict = {}
        if email is not None:
            new_email = normalize_email(email)
            if new_email and new_email != access.email:
                changes["email"] = {"old": access.email, "new": new_email}
                access.email = new_email
                if actor is not None:
                    actor.email = new_email
        if phone is not None:
            new_phone = phone.strip() if phone else None
            normalized = normalize_phone_number(new_phone)
            if new_phone is not None and new_phone != (access.phone_number or ""):
                changes["phone"] = {"old": access.phone_number, "new": new_phone}
                access.phone_number = new_phone or None
                access.normalized_phone_number = normalized
                if actor is not None:
                    actor.telefono = new_phone or None

        await db.commit()
        if actor:
            await db.refresh(actor)
        await db.refresh(access)
        return await PortalMeService.get_profile(db, session), changes

    # ------------------------------------------------------------------
    # Privacy policy + consents
    # ------------------------------------------------------------------

    @staticmethod
    async def current_policy(
        db: AsyncSession, tenant_id: str
    ) -> Optional[PortalPrivacyPolicy]:
        res = await db.execute(
            select(PortalPrivacyPolicy)
            .where(PortalPrivacyPolicy.tenant_id == tenant_id)
            .order_by(PortalPrivacyPolicy.version.desc())
            .limit(1)
        )
        return res.scalar_one_or_none()

    @staticmethod
    async def list_consents(
        db: AsyncSession, session: PortalSessionContext
    ) -> list[PortalConsent]:
        actor_id = await PortalMeService._current_actor_id(db, session)
        if actor_id is None:
            # Fallback: solo i consensi di questa specifica access
            res = await db.execute(
                select(PortalConsent)
                .where(
                    PortalConsent.tenant_id == session.tenant_id,
                    PortalConsent.portal_access_id == session.portal_access_id,
                )
                .order_by(PortalConsent.accepted_at.desc())
            )
            return list(res.scalars().all())
        res = await db.execute(
            select(PortalConsent)
            .where(
                PortalConsent.tenant_id == session.tenant_id,
                PortalConsent.actor_id == actor_id,
            )
            .order_by(PortalConsent.accepted_at.desc())
        )
        return list(res.scalars().all())

    @staticmethod
    async def accept_consent(
        db: AsyncSession,
        session: PortalSessionContext,
        *,
        policy_id: str,
        consent_type: str,
        request: Optional[Request] = None,
    ) -> PortalConsent:
        res = await db.execute(
            select(PortalPrivacyPolicy).where(
                PortalPrivacyPolicy.id == policy_id,
                PortalPrivacyPolicy.tenant_id == session.tenant_id,
            )
        )
        policy = res.scalar_one_or_none()
        if policy is None:
            raise ValueError("policy_not_found")

        actor_id = await PortalMeService._current_actor_id(db, session)
        ip = request.client.host if request and request.client else None
        ua = request.headers.get("user-agent") if request else None

        consent = PortalConsent(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            portal_access_id=session.portal_access_id,
            actor_id=actor_id,
            policy_id=policy.id,
            policy_version=policy.version,
            ip_address=ip,
            user_agent=ua,
            consent_type=consent_type,
        )
        db.add(consent)
        await db.commit()
        await db.refresh(consent)
        return consent

    # ------------------------------------------------------------------
    # Notification preferences
    # ------------------------------------------------------------------

    @staticmethod
    async def get_notification_prefs(
        db: AsyncSession, session: PortalSessionContext
    ) -> PortalNotificationPrefs:
        actor_id = await PortalMeService._current_actor_id(db, session)
        if actor_id is None:
            # Senza Actor strutturato, restituiamo defaults transient
            return PortalNotificationPrefs(actor_id="", tenant_id=session.tenant_id)
        res = await db.execute(
            select(PortalNotificationPrefs).where(
                PortalNotificationPrefs.actor_id == actor_id
            )
        )
        prefs = res.scalar_one_or_none()
        if prefs is None:
            # Lazy create con defaults
            prefs = PortalNotificationPrefs(
                actor_id=actor_id,
                tenant_id=session.tenant_id,
            )
            db.add(prefs)
            await db.commit()
            await db.refresh(prefs)
        return prefs

    @staticmethod
    async def update_notification_prefs(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: dict,
    ) -> PortalNotificationPrefs:
        prefs = await PortalMeService.get_notification_prefs(db, session)
        if prefs.actor_id == "":
            raise ValueError("no_actor_linked")
        for key, value in payload.items():
            if hasattr(prefs, key) and value is not None:
                setattr(prefs, key, value)
        await db.commit()
        await db.refresh(prefs)
        return prefs

    # ------------------------------------------------------------------
    # Deletion request
    # ------------------------------------------------------------------

    @staticmethod
    async def compute_eligible_from(
        db: AsyncSession,
        tenant_id: str,
        portal_access_id: str,
    ) -> datetime:
        """eligible_from = max(closed_at) tra tutti i sinistri associati
        all'identità + 5 anni. Se nessun sinistro è chiuso, usa now() + 5y
        come fallback (l'admin valuterà al momento della richiesta)."""
        from app.core.portal_security import PortalSessionContext as Ctx

        # Recupera tutti i sinistri associati all'identità
        access_row = (await db.execute(
            select(PortalClaimAccess).where(
                PortalClaimAccess.id == portal_access_id,
                PortalClaimAccess.tenant_id == tenant_id,
            )
        )).scalar_one()

        ctx = Ctx(
            tenant_id=tenant_id,
            claim_id=access_row.claim_id,
            portal_access_id=portal_access_id,
            role=access_row.role,
        )
        accesses = await PortalService.list_accessible_claim_accesses(db, ctx)
        claim_ids = [a.claim_id for a in accesses]
        if not claim_ids:
            return datetime.now(timezone.utc) + timedelta(days=365 * RETENTION_YEARS)

        res = await db.execute(
            select(Claim).where(Claim.id.in_(claim_ids), Claim.tenant_id == tenant_id)
        )
        claims = list(res.scalars().all())
        closed_dates = [c.closed_at for c in claims if c.closed_at]
        last_closed = max(closed_dates) if closed_dates else None

        # Se ci sono sinistri ancora aperti, l'eligibilità slitta:
        # finché c'è un sinistro aperto, retention non parte. Usiamo
        # un fallback conservativo (oggi + 5y) — l'admin ricalcola alla
        # processazione.
        open_count = sum(1 for c in claims if c.closed_at is None)
        if open_count > 0:
            return datetime.now(timezone.utc) + timedelta(days=365 * RETENTION_YEARS)
        if last_closed is None:
            return datetime.now(timezone.utc) + timedelta(days=365 * RETENTION_YEARS)
        return last_closed + timedelta(days=365 * RETENTION_YEARS)

    @staticmethod
    async def create_deletion_request(
        db: AsyncSession,
        session: PortalSessionContext,
        *,
        reason: Optional[str] = None,
        request: Optional[Request] = None,
    ) -> PortalDeletionRequest:
        # Evita duplicati pending
        existing = (await db.execute(
            select(PortalDeletionRequest).where(
                PortalDeletionRequest.tenant_id == session.tenant_id,
                PortalDeletionRequest.portal_access_id == session.portal_access_id,
                PortalDeletionRequest.status == "pending",
            )
        )).scalar_one_or_none()
        if existing:
            return existing

        actor_id = await PortalMeService._current_actor_id(db, session)
        eligible_from = await PortalMeService.compute_eligible_from(
            db, session.tenant_id, session.portal_access_id
        )
        ip = request.client.host if request and request.client else None
        ua = request.headers.get("user-agent") if request else None

        req = PortalDeletionRequest(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            portal_access_id=session.portal_access_id,
            actor_id=actor_id,
            requested_ip=ip,
            requested_user_agent=ua,
            eligible_from=eligible_from,
            status="pending",
            reason=reason,
        )
        db.add(req)
        await db.commit()
        await db.refresh(req)
        return req

    @staticmethod
    async def get_active_deletion_request(
        db: AsyncSession, session: PortalSessionContext
    ) -> Optional[PortalDeletionRequest]:
        res = await db.execute(
            select(PortalDeletionRequest)
            .where(
                PortalDeletionRequest.tenant_id == session.tenant_id,
                PortalDeletionRequest.portal_access_id == session.portal_access_id,
                PortalDeletionRequest.status.in_(("pending", "eligible")),
            )
            .order_by(PortalDeletionRequest.requested_at.desc())
            .limit(1)
        )
        return res.scalar_one_or_none()

    @staticmethod
    async def cancel_deletion_request(
        db: AsyncSession, session: PortalSessionContext, request_id: str
    ) -> bool:
        res = await db.execute(
            select(PortalDeletionRequest).where(
                PortalDeletionRequest.id == request_id,
                PortalDeletionRequest.tenant_id == session.tenant_id,
                PortalDeletionRequest.portal_access_id == session.portal_access_id,
            )
        )
        req = res.scalar_one_or_none()
        if req is None or req.status not in ("pending", "eligible"):
            return False
        req.status = "cancelled"
        await db.commit()
        return True

    # ------------------------------------------------------------------
    # Sessions
    # ------------------------------------------------------------------

    @staticmethod
    async def list_sessions(
        db: AsyncSession, session: PortalSessionContext
    ) -> list[PortalSession]:
        res = await db.execute(
            select(PortalSession)
            .where(
                PortalSession.tenant_id == session.tenant_id,
                PortalSession.portal_access_id == session.portal_access_id,
                PortalSession.revoked_at.is_(None),
            )
            .order_by(PortalSession.last_seen_at.desc())
        )
        return list(res.scalars().all())

    @staticmethod
    async def revoke_session(
        db: AsyncSession, session: PortalSessionContext, target_session_id: str
    ) -> bool:
        res = await db.execute(
            select(PortalSession).where(
                PortalSession.id == target_session_id,
                PortalSession.tenant_id == session.tenant_id,
                PortalSession.portal_access_id == session.portal_access_id,
                PortalSession.revoked_at.is_(None),
            )
        )
        sess = res.scalar_one_or_none()
        if sess is None:
            return False
        sess.revoked_at = datetime.now(timezone.utc)
        await db.commit()
        return True
