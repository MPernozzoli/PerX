"""
User email identity helpers.

PerX separates the personal login/recovery email from the tenant operational
email used for outbound/inbound communications.
"""
from __future__ import annotations

import re
import unicodedata
import uuid

from fastapi import HTTPException
from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.email import EmailAlias, TenantEmailDomain
from app.models.user import User

ROLE_PREFIX_PRIORITY = (
    "perito",
    "segreteria",
    "cat",
    "gestore",
    "capoTeam",
    "direttore",
    "admin",
)


def normalize_email(value: str | None) -> str:
    return (value or "").strip().lower()


def slugify_local_part(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    local_part = re.sub(r"[^a-zA-Z0-9]+", ".", ascii_value.lower()).strip(".")
    return re.sub(r"\.{2,}", ".", local_part)


def role_prefix(role_names: list[str], job_title: str | None = None) -> str:
    for candidate in ROLE_PREFIX_PRIORITY:
        if candidate in role_names:
            return slugify_local_part(candidate)
    if job_title:
        title_slug = slugify_local_part(job_title)
        if title_slug:
            return title_slug
    return "utente"


async def ensure_personal_email(db: AsyncSession, user: User) -> None:
    if user.personal_email:
        return
    user.personal_email = normalize_email(user.email)
    await db.flush()


async def get_tenant_email_domain(db: AsyncSession, tenant_id: str) -> TenantEmailDomain | None:
    result = await db.execute(
        select(TenantEmailDomain)
        .where(
            TenantEmailDomain.tenant_id == tenant_id,
            TenantEmailDomain.provider == "resend",
            TenantEmailDomain.inbound_enabled == "true",
            TenantEmailDomain.outbound_enabled == "true",
        )
        .order_by(
            (TenantEmailDomain.status == "verified").desc(),
            TenantEmailDomain.created_at.asc(),
        )
        .limit(1)
    )
    return result.scalar_one_or_none()


async def address_exists(db: AsyncSession, address: str, exclude_user_id: str | None = None) -> bool:
    address = normalize_email(address)

    user_query = select(User.id).where(
        func.lower(User.professional_email) == address,
    )
    if exclude_user_id:
        user_query = user_query.where(User.id != exclude_user_id)
    if (await db.execute(user_query.limit(1))).first():
        return True

    alias_query = select(EmailAlias.id).where(func.lower(EmailAlias.address) == address)
    if exclude_user_id:
        alias_query = alias_query.where(
            or_(
                EmailAlias.target_type != "user",
                EmailAlias.target_id != exclude_user_id,
            )
        )
    return (await db.execute(alias_query.limit(1))).first() is not None


async def generate_professional_email(
    db: AsyncSession,
    user: User,
    role_names: list[str],
    domain: str,
) -> str:
    first = slugify_local_part(user.first_name or "")
    last = slugify_local_part(user.last_name or "")
    if first and last:
        base = f"{first}.{last}"
    else:
        base = slugify_local_part(user.full_name)
    if not base:
        base = f"utente.{user.id[:8]}"

    candidates = [base, f"{role_prefix(role_names, user.job_title)}.{base}"]
    for index in range(2, 100):
        candidates.append(f"{candidates[1]}.{index}")

    normalized_domain = domain.lower()
    for local_part in candidates:
        address = f"{local_part}@{normalized_domain}"
        if not await address_exists(db, address, exclude_user_id=user.id):
            return address

    raise HTTPException(status_code=409, detail="Unable to generate a unique professional email")


async def _set_existing_primary_aliases_inactive(db: AsyncSession, user: User) -> None:
    await db.execute(
        update(EmailAlias)
        .where(
            EmailAlias.tenant_id == user.tenant_id,
            EmailAlias.target_type == "user",
            EmailAlias.target_id == user.id,
            EmailAlias.is_primary == "true",
        )
        .values(is_primary="false")
    )


async def ensure_user_alias(
    db: AsyncSession,
    user: User,
    address: str,
    domain_id: str | None,
    is_primary: bool,
    source: str,
) -> None:
    normalized = normalize_email(address)
    if "@" not in normalized:
        raise HTTPException(status_code=400, detail="Invalid professional email")
    local_part = normalized.split("@", 1)[0]

    result = await db.execute(select(EmailAlias).where(func.lower(EmailAlias.address) == normalized))
    alias = result.scalar_one_or_none()
    if alias and not (alias.target_type == "user" and alias.target_id == user.id):
        raise HTTPException(status_code=409, detail="Professional email alias already exists")

    if is_primary:
        await _set_existing_primary_aliases_inactive(db, user)

    if alias is None:
        alias = EmailAlias(
            id=str(uuid.uuid4()),
            tenant_id=user.tenant_id,
            domain_id=domain_id,
            address=normalized,
            local_part=local_part,
            target_type="user",
            target_id=user.id,
            is_primary="true" if is_primary else "false",
            is_active="true",
            source=source,
        )
        db.add(alias)
    else:
        alias.domain_id = domain_id or alias.domain_id
        alias.local_part = local_part
        alias.is_primary = "true" if is_primary else alias.is_primary
        alias.is_active = "true"
        alias.source = source or alias.source


async def set_professional_email(
    db: AsyncSession,
    user: User,
    new_address: str,
    source: str = "user",
) -> str:
    normalized = normalize_email(new_address)
    if "@" not in normalized:
        raise HTTPException(status_code=400, detail="Invalid professional email")

    previous = normalize_email(user.professional_email)
    domain_name = normalized.split("@", 1)[1]
    domain = await get_tenant_email_domain(db, user.tenant_id)
    if not domain or domain.domain.lower() != domain_name:
        raise HTTPException(status_code=400, detail="Professional email must use the tenant email domain")

    if previous == normalized:
        await ensure_user_alias(db, user, normalized, domain.id, is_primary=True, source=source)
        return normalized

    if await address_exists(db, normalized, exclude_user_id=user.id):
        raise HTTPException(status_code=409, detail="Professional email already exists")

    if previous and previous != normalized:
        await ensure_user_alias(db, user, previous, domain.id, is_primary=False, source="auto")

    user.professional_email = normalized
    await ensure_user_alias(db, user, normalized, domain.id, is_primary=True, source=source)
    return normalized


async def ensure_professional_email(
    db: AsyncSession,
    user: User,
    role_names: list[str],
) -> str | None:
    await ensure_personal_email(db, user)
    domain = await get_tenant_email_domain(db, user.tenant_id)
    if not domain:
        return user.professional_email

    if user.professional_email:
        await ensure_user_alias(db, user, user.professional_email, domain.id, is_primary=True, source="auto")
        return user.professional_email

    generated = await generate_professional_email(db, user, role_names, domain.domain)
    user.professional_email = generated
    await ensure_user_alias(db, user, generated, domain.id, is_primary=True, source="auto")
    return generated


async def get_user_aliases(db: AsyncSession, user: User) -> list[str]:
    result = await db.execute(
        select(EmailAlias.address)
        .where(
            EmailAlias.tenant_id == user.tenant_id,
            EmailAlias.target_type == "user",
            EmailAlias.target_id == user.id,
            EmailAlias.is_active == "true",
        )
        .order_by(EmailAlias.is_primary.desc(), EmailAlias.created_at.asc())
    )
    return [row[0] for row in result.all()]
