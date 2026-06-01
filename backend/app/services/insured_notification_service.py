"""
Insured-portal notification dispatcher with channel fallback.

Channel priority (single delivery, first available wins):
    push → whatsapp → email → sms

Today only push and email are wired to real providers; whatsapp/sms fall back
to structured logs until the providers are integrated.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Iterable, Optional

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.claim import Claim
from app.services.resend_email_service import ResendEmailMessage, ResendEmailService
from app.services.web_push_service import WebPushService

logger = logging.getLogger(__name__)


DeeplinkTarget = str  # e.g. "inspection-scheduling", "atto", "documents"


def build_portal_deeplink(claim: Claim, target: DeeplinkTarget) -> str:
    """
    Build a portal URL targeting a specific section for the given claim.

    The portal is a single-route app (`/p/[ref]`) that switches view based on
    the `focus` query param — mirrors the existing `?focus=atto` convention.
    """
    base = settings.PORTAL_APP_URL.rstrip("/")
    claim_ref = claim.external_ref or claim.numero_sinistro or claim.id
    target = target.strip("/")
    if not target:
        return f"{base}/p/{claim_ref}"
    return f"{base}/p/{claim_ref}?focus={target}"


@dataclass(frozen=True)
class NotificationDelivery:
    channel: str  # push | whatsapp | email | sms | none
    success: bool
    detail: Optional[str] = None


class InsuredNotificationService:
    @staticmethod
    async def notify(
        db: AsyncSession,
        claim: Claim,
        *,
        kind: str,
        title: str,
        body: str,
        deeplink: str,
        tenant_branding: Optional[dict] = None,
    ) -> NotificationDelivery:
        """
        Try channels in fallback order push→whatsapp→email→sms.
        Returns as soon as one succeeds. Channel choice will become user-configurable
        once the portal exposes notification preferences.
        """
        # 1. Push
        push = await InsuredNotificationService._try_push(
            db, claim, title=title, body=body, url=deeplink,
            kind=kind, tenant_branding=tenant_branding or {},
        )
        if push.success:
            return push

        # 2. WhatsApp (stub)
        wa = InsuredNotificationService._try_whatsapp(claim, title=title, body=body, deeplink=deeplink, kind=kind)
        if wa.success:
            return wa

        # 3. Email
        email = await InsuredNotificationService._try_email(claim, title=title, body=body, deeplink=deeplink)
        if email.success:
            return email

        # 4. SMS (stub)
        sms = InsuredNotificationService._try_sms(claim, body=body, deeplink=deeplink, kind=kind)
        if sms.success:
            return sms

        return NotificationDelivery(channel="none", success=False, detail="no_channel_available")

    @staticmethod
    async def _try_push(
        db: AsyncSession,
        claim: Claim,
        *,
        title: str,
        body: str,
        url: str,
        kind: str,
        tenant_branding: dict,
    ) -> NotificationDelivery:
        if not WebPushService.is_configured():
            return NotificationDelivery(channel="push", success=False, detail="not_configured")
        # Lazy import to avoid circular dep with portal_service.
        from app.services.portal_service import PortalService

        subs = await PortalService.list_active_push_subscriptions_for_claim(
            db, claim.tenant_id, claim.id
        )
        if not subs:
            return NotificationDelivery(channel="push", success=False, detail="no_subscriptions")

        any_success = False
        now = datetime.now(timezone.utc)
        for sub in subs:
            result = WebPushService.send(
                endpoint=sub.endpoint,
                p256dh=sub.p256dh,
                auth=sub.auth,
                title=title,
                body=body,
                url=url,
                tag=f"{kind}-{claim.id}",
                data={
                    "claim_id": claim.id,
                    "kind": kind,
                    "icon": tenant_branding.get("icon_data_url"),
                    "badge": tenant_branding.get("badge_data_url"),
                },
            )
            if result.gone:
                sub.status = "revoked"
                sub.revoked_at = now
            else:
                sub.last_used_at = now
            any_success = any_success or result.success

        return NotificationDelivery(
            channel="push",
            success=any_success,
            detail=None if any_success else "all_endpoints_failed",
        )

    @staticmethod
    def _try_whatsapp(claim: Claim, *, title: str, body: str, deeplink: str, kind: str) -> NotificationDelivery:
        # Provider non ancora integrato: log strutturato, nessun invio reale.
        logger.info(
            "[insured-notify:whatsapp:stub] claim=%s kind=%s phone=%s title=%r body=%r deeplink=%s",
            claim.id, kind, getattr(claim, "telefono_assicurato", None), title, body, deeplink,
        )
        return NotificationDelivery(channel="whatsapp", success=False, detail="stub_not_implemented")

    @staticmethod
    async def _try_email(claim: Claim, *, title: str, body: str, deeplink: str) -> NotificationDelivery:
        if not claim.email_assicurato:
            return NotificationDelivery(channel="email", success=False, detail="no_recipient")
        if not settings.RESEND_API_KEY or not settings.RESEND_DEFAULT_FROM_EMAIL:
            return NotificationDelivery(channel="email", success=False, detail="not_configured")
        html_body = (
            f"<p>{body}</p>"
            f'<p><a href="{deeplink}">Apri il portale</a></p>'
        )
        await ResendEmailService.send(
            ResendEmailMessage(
                from_address=settings.RESEND_DEFAULT_FROM_EMAIL,
                to=[claim.email_assicurato],
                subject=title,
                body=html_body,
            )
        )
        return NotificationDelivery(channel="email", success=True)

    @staticmethod
    def _try_sms(claim: Claim, *, body: str, deeplink: str, kind: str) -> NotificationDelivery:
        # Provider non ancora integrato: log strutturato, nessun invio reale.
        logger.info(
            "[insured-notify:sms:stub] claim=%s kind=%s phone=%s body=%r deeplink=%s",
            claim.id, kind, getattr(claim, "telefono_assicurato", None), body, deeplink,
        )
        return NotificationDelivery(channel="sms", success=False, detail="stub_not_implemented")
