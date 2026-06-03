"""
Tenant-aware virtual extension management.

PerX extensions are internal destinations, not PSTN numbers. They are unique
inside a tenant only; different tenants may reuse the same 3 digit extension.
"""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


class ExtensionUnavailableError(ValueError):
    pass


class CommunicationExtensionService:
    MIN_EXTENSION = 100
    MAX_EXTENSION = 999

    @classmethod
    async def first_available_extension(cls, db: AsyncSession, tenant_id: str) -> str:
        result = await db.execute(
            select(User.extension_number).where(
                User.tenant_id == tenant_id,
                User.extension_enabled == True,
                User.extension_number.is_not(None),
            )
        )
        used = {row[0] for row in result.all() if row[0]}
        for number in range(cls.MIN_EXTENSION, cls.MAX_EXTENSION + 1):
            candidate = f"{number:03d}"
            if candidate not in used:
                return candidate
        raise ExtensionUnavailableError("No virtual extensions available for tenant")

    @classmethod
    async def assign_extension(
        cls,
        db: AsyncSession,
        user: User,
        extension_number: str | None = None,
        display_name: str | None = None,
        reassign_if_necessary: bool = True,
    ) -> User:
        candidate = extension_number or await cls.first_available_extension(db, user.tenant_id)
        cls._validate_extension(candidate)

        owner = await cls.find_user_by_extension(db, user.tenant_id, candidate)
        if owner and owner.id != user.id:
            if not reassign_if_necessary:
                raise ExtensionUnavailableError(f"Extension {candidate} already assigned in tenant")
            candidate = await cls.first_available_extension(db, user.tenant_id)

        user.extension_number = candidate
        user.extension_enabled = True
        user.extension_assigned_at = datetime.now(timezone.utc)
        user.extension_display_name = display_name or user.full_name
        return user

    @classmethod
    async def disable_extension(cls, db: AsyncSession, user: User) -> User:
        user.extension_enabled = False
        user.communication_status = "unavailable"
        return user

    @classmethod
    async def find_user_by_extension(
        cls,
        db: AsyncSession,
        tenant_id: str,
        extension_number: str,
    ) -> User | None:
        cls._validate_extension(extension_number)
        result = await db.execute(
            select(User).where(
                User.tenant_id == tenant_id,
                User.extension_number == extension_number,
                User.extension_enabled == True,
                User.is_active == True,
            )
        )
        return result.scalar_one_or_none()

    @classmethod
    def _validate_extension(cls, extension_number: str) -> None:
        if len(extension_number) != 3 or not extension_number.isdigit():
            raise ValueError("Virtual extension must be exactly 3 digits")
