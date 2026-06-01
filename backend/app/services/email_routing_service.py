"""
Inbound email redistribution for disabled tenant users.

PerX uses centralized virtual mailboxes. Redistribution expands the effective
recipient list instead of sending duplicate SMTP messages.
"""
from __future__ import annotations

import json
from collections.abc import Iterable

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.claim_assignment import ClaimAssignment
from app.models.email import Email, EmailAlias
from app.models.tenant import Tenant
from app.models.user import User


def _normalized_addresses(values: Iterable[str]) -> list[str]:
    result: list[str] = []
    for value in values:
        normalized = (value or "").strip().lower()
        if normalized and normalized not in result:
            result.append(normalized)
    return result


def _json_addresses(raw_value: str | None) -> list[str]:
    try:
        values = json.loads(raw_value or "[]")
    except (TypeError, json.JSONDecodeError):
        return []
    if not isinstance(values, list):
        return []
    return _normalized_addresses(value for value in values if isinstance(value, str))


class EmailRoutingService:
    @staticmethod
    async def reroute_disabled_user_email(
        db: AsyncSession,
        email: Email,
        *,
        claim_ids: Iterable[str] = (),
    ) -> list[str]:
        recipients = _json_addresses(email.to_addresses)
        addressed_recipients = _normalized_addresses(
            [*recipients, *_json_addresses(email.cc_addresses)]
        )
        if not addressed_recipients:
            return []

        disabled_result = await db.execute(
            select(User.id)
            .join(
                EmailAlias,
                (EmailAlias.target_type == "user")
                & (EmailAlias.target_id == User.id)
                & (EmailAlias.is_active == "true"),
            )
            .where(
                User.tenant_id == email.tenant_id,
                User.is_active.is_(False),
                func.lower(EmailAlias.address).in_(addressed_recipients),
            )
        )
        disabled_user_ids = list(dict.fromkeys(row[0] for row in disabled_result.all()))
        if not disabled_user_ids:
            return []

        forwarded_to: list[str] = []
        tenant = await db.get(Tenant, email.tenant_id)
        tenant_settings = tenant.settings_json if tenant and isinstance(tenant.settings_json, dict) else {}
        forwarded_to.extend(_normalized_addresses(tenant_settings.get("secretariat_emails", [])))

        normalized_claim_ids = list(dict.fromkeys(value for value in claim_ids if value))
        if normalized_claim_ids:
            assignee_result = await db.execute(
                select(User.professional_email, User.email)
                .join(ClaimAssignment, ClaimAssignment.assignee_user_id == User.id)
                .where(
                    ClaimAssignment.tenant_id == email.tenant_id,
                    ClaimAssignment.claim_id.in_(normalized_claim_ids),
                    ClaimAssignment.unassigned_at.is_(None),
                    User.is_active.is_(True),
                )
            )
            forwarded_to.extend(
                professional_email or email_address
                for professional_email, email_address in assignee_result.all()
            )

        forwarded_to = _normalized_addresses(forwarded_to)
        merged_recipients = _normalized_addresses([*recipients, *forwarded_to])
        email.to_addresses = json.dumps(merged_recipients)

        try:
            metadata = json.loads(email.raw_headers or "{}")
        except (TypeError, json.JSONDecodeError):
            metadata = {}
        if not isinstance(metadata, dict):
            metadata = {}
        metadata["perxRouting"] = {
            "disabledUserIds": disabled_user_ids,
            "relatedClaimIds": normalized_claim_ids,
            "forwardedToAddresses": forwarded_to,
        }
        email.raw_headers = json.dumps(metadata)
        return forwarded_to
