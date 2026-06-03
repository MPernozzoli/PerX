"""
Authenticated user profile routes
"""
from datetime import datetime
import hashlib
from pathlib import Path
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.role import Role, user_roles
from app.models.user import User
from app.models.user_profile_asset import UserProfileAsset
from app.schemas.profile import UserProfileAssetResponse, UserProfileResponse, UserProfileUpdateRequest
from app.services.user_email_service import (
    ensure_personal_email,
    ensure_professional_email,
    get_user_aliases,
    set_professional_email,
)

router = APIRouter()

PROFILE_ASSET_TYPES = {"avatar_photo", "signature_image"}
PROFILE_ASSET_ROOT = Path(__file__).resolve().parents[3] / "runtime" / "profile_assets"

ROLE_MAP_TO_APP = {
    "admin_tenant": "admin",
    "admin": "admin",
    "direttore": "direttore",
    "capoTeam": "capoTeam",
    "gestore": "gestore",
    "perito": "perito",
    "expert": "perito",
    "cat": "cat",
    "segreteria": "segreteria",
}

ROLE_MAP_FROM_APP = {
    "admin": "admin_tenant",
    "direttore": "direttore",
    "capoTeam": "capoTeam",
    "gestore": "gestore",
    "perito": "perito",
    "cat": "cat",
    "segreteria": "segreteria",
}


async def _fetch_role_names(db: AsyncSession, user_id: str) -> list[str]:
    result = await db.execute(
        select(Role.name)
        .select_from(user_roles.join(Role, user_roles.c.role_id == Role.id))
        .where(user_roles.c.user_id == user_id)
    )
    raw_names = [row[0] for row in result.all()]
    mapped = []
    for name in raw_names:
        app_name = ROLE_MAP_TO_APP.get(name)
        if app_name and app_name not in mapped:
            mapped.append(app_name)
    return mapped


async def _fetch_asset_map(db: AsyncSession, user_id: str) -> dict[str, UserProfileAsset]:
    result = await db.execute(
        select(UserProfileAsset).where(UserProfileAsset.user_id == user_id)
    )
    return {asset.asset_type: asset for asset in result.scalars().all()}


def _asset_url(user_id: str, asset_type: str) -> str:
    return f"/api/v1/profiles/{user_id}/assets/{asset_type}"


def _resolve_asset_path(
    tenant_id: str,
    user_id: str,
    asset_type: str,
    filename: str,
) -> Path:
    safe_name = Path(filename).name or f"{asset_type}.bin"
    asset_dir = PROFILE_ASSET_ROOT / tenant_id / user_id
    asset_dir.mkdir(parents=True, exist_ok=True)
    return asset_dir / f"{asset_type}_{safe_name}"


def _build_full_name(first_name: str, last_name: str, fallback: str) -> str:
    combined = f"{first_name} {last_name}".strip()
    return combined or fallback


async def _to_response(db: AsyncSession, user: User) -> UserProfileResponse:
    role_names = await _fetch_role_names(db, user.id)
    assets = await _fetch_asset_map(db, user.id)
    aliases = await get_user_aliases(db, user)
    avatar_asset = assets.get("avatar_photo")
    signature_asset = assets.get("signature_image")
    return UserProfileResponse(
        id=user.id,
        email=user.personal_email or user.email,
        personal_email=user.personal_email or user.email,
        professional_email=user.professional_email,
        email_aliases=aliases,
        full_name=user.full_name,
        first_name=user.first_name or "",
        last_name=user.last_name or "",
        job_title=user.job_title,
        phone_number=user.phone_number,
        birth_date=user.birth_date,
        birthday_visibility=user.birthday_visibility or "everyone",
        notify_birthday=user.notify_birthday,
        contract_type=user.contract_type,
        roles=role_names,
        extension_number=user.extension_number,
        extension_enabled=bool(user.extension_enabled),
        extension_assigned_at=user.extension_assigned_at,
        extension_display_name=user.extension_display_name,
        availability_status=user.availability_status or "available",
        communication_status=user.communication_status or "idle",
        avatar_type=user.avatar_type or "generated",
        avatar_photo_base64=user.avatar_photo_base64,
        avatar_asset_url=_asset_url(user.id, "avatar_photo") if avatar_asset else None,
        generated_avatar_color=user.generated_avatar_color,
        generated_avatar_icon=user.generated_avatar_icon,
        avatar_gif_url=user.avatar_gif_url,
        signature_image_url=_asset_url(user.id, "signature_image") if signature_asset else None,
        enable_badges=user.enable_badges,
        send_read_receipts=user.send_read_receipts,
        email_signature_html=user.email_signature_html,
        email_signature_text=user.email_signature_text,
        tenant_id=user.tenant_id,
        is_active=user.is_active,
        is_platform_admin=user.is_platform_admin,
        created_at=user.created_at,
        updated_at=user.last_login_at,
    )


async def _ensure_roles(db: AsyncSession, user: User, app_role_names: list[str]) -> None:
    normalized = []
    for name in app_role_names:
        mapped = ROLE_MAP_FROM_APP.get(name)
        if mapped and mapped not in normalized:
            normalized.append(mapped)

    await db.execute(delete(user_roles).where(user_roles.c.user_id == user.id))

    if not normalized:
        return

    existing = await db.execute(
        select(Role).where(Role.tenant_id == user.tenant_id, Role.name.in_(normalized))
    )
    by_name = {role.name: role for role in existing.scalars().all()}

    for name in normalized:
        role = by_name.get(name)
        if role is None:
            import uuid
            role = Role(
                id=str(uuid.uuid4()),
                tenant_id=user.tenant_id,
                name=name,
                description=f"Ruolo {name}"
            )
            db.add(role)
            await db.flush()
        await db.execute(
            user_roles.insert().values(user_id=user.id, role_id=role.id)
        )


@router.get("/me", response_model=UserProfileResponse)
async def get_my_profile(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    role_names = await _fetch_role_names(db, current_user.id)
    await ensure_personal_email(db, current_user)
    await ensure_professional_email(db, current_user, role_names)
    await db.commit()
    await db.refresh(current_user)
    return await _to_response(db, current_user)


@router.put("/me", response_model=UserProfileResponse)
async def update_my_profile(
    payload: UserProfileUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    current_user.first_name = payload.first_name.strip()
    current_user.last_name = payload.last_name.strip()
    current_user.full_name = _build_full_name(
        current_user.first_name,
        current_user.last_name,
        current_user.full_name
    )
    current_user.job_title = payload.job_title
    current_user.phone_number = payload.phone_number
    current_user.birth_date = payload.birth_date
    current_user.birthday_visibility = payload.birthday_visibility or "everyone"
    current_user.notify_birthday = payload.notify_birthday
    current_user.contract_type = payload.contract_type
    if payload.extension_number is not None:
        current_user.extension_number = payload.extension_number
        current_user.extension_enabled = payload.extension_enabled if payload.extension_enabled is not None else True
        current_user.extension_assigned_at = datetime.utcnow()
    elif payload.extension_enabled is not None:
        current_user.extension_enabled = payload.extension_enabled
    current_user.extension_display_name = payload.extension_display_name
    current_user.availability_status = payload.availability_status or "available"
    current_user.communication_status = payload.communication_status or "idle"
    current_user.avatar_type = payload.avatar_type or "generated"
    current_user.avatar_photo_base64 = payload.avatar_photo_base64
    current_user.generated_avatar_color = payload.generated_avatar_color
    current_user.generated_avatar_icon = payload.generated_avatar_icon
    current_user.avatar_gif_url = payload.avatar_gif_url
    current_user.enable_badges = payload.enable_badges
    current_user.send_read_receipts = payload.send_read_receipts
    current_user.email_signature_html = payload.email_signature_html
    current_user.email_signature_text = payload.email_signature_text
    current_user.last_login_at = datetime.utcnow()

    await _ensure_roles(db, current_user, payload.roles)
    await ensure_personal_email(db, current_user)
    if payload.professional_email:
        await set_professional_email(db, current_user, payload.professional_email, source="user")
    else:
        await ensure_professional_email(db, current_user, payload.roles)
    await db.commit()
    await db.refresh(current_user)

    return await _to_response(db, current_user)


async def _get_tenant_user_or_404(db: AsyncSession, current_user: User, user_id: str) -> User:
    result = await db.execute(
        select(User).where(
            User.id == user_id,
            User.tenant_id == current_user.tenant_id,
            User.is_active == True,
        )
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.get("/me/assets/{asset_type}", response_model=UserProfileAssetResponse)
async def get_my_asset_metadata(
    asset_type: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if asset_type not in PROFILE_ASSET_TYPES:
        raise HTTPException(status_code=404, detail="Unsupported asset type")
    result = await db.execute(
        select(UserProfileAsset).where(
            UserProfileAsset.user_id == current_user.id,
            UserProfileAsset.asset_type == asset_type,
        )
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    return UserProfileAssetResponse(
        asset_type=asset.asset_type,
        file_name=asset.file_name,
        mime_type=asset.mime_type,
        size_bytes=asset.size_bytes,
        asset_url=_asset_url(current_user.id, asset.asset_type),
        updated_at=asset.updated_at,
    )


@router.get("/{user_id}/assets/{asset_type}")
async def download_user_asset(
    user_id: str,
    asset_type: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if asset_type not in PROFILE_ASSET_TYPES:
        raise HTTPException(status_code=404, detail="Unsupported asset type")
    await _get_tenant_user_or_404(db, current_user, user_id)
    result = await db.execute(
        select(UserProfileAsset).where(
            UserProfileAsset.user_id == user_id,
            UserProfileAsset.asset_type == asset_type,
        )
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    file_path = Path(asset.storage_path)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Asset file missing")
    return FileResponse(
        path=file_path,
        media_type=asset.mime_type or "application/octet-stream",
        filename=asset.file_name,
    )


@router.put("/me/assets/{asset_type}", response_model=UserProfileAssetResponse)
async def upload_my_asset(
    asset_type: str,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if asset_type not in PROFILE_ASSET_TYPES:
        raise HTTPException(status_code=404, detail="Unsupported asset type")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty asset payload")

    storage_path = _resolve_asset_path(
        current_user.tenant_id,
        current_user.id,
        asset_type,
        file.filename or f"{asset_type}.bin",
    )
    storage_path.write_bytes(content)
    checksum_sha256 = hashlib.sha256(content).hexdigest()

    result = await db.execute(
        select(UserProfileAsset).where(
            UserProfileAsset.user_id == current_user.id,
            UserProfileAsset.asset_type == asset_type,
        )
    )
    asset = result.scalar_one_or_none()
    if asset is None:
        asset = UserProfileAsset(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            user_id=current_user.id,
            asset_type=asset_type,
            file_name=file.filename or storage_path.name,
            mime_type=file.content_type,
            size_bytes=len(content),
            storage_path=str(storage_path),
            checksum_sha256=checksum_sha256,
        )
        db.add(asset)
    else:
        previous_path = Path(asset.storage_path)
        if previous_path != storage_path and previous_path.exists():
            previous_path.unlink(missing_ok=True)
        asset.file_name = file.filename or storage_path.name
        asset.mime_type = file.content_type
        asset.size_bytes = len(content)
        asset.storage_path = str(storage_path)
        asset.checksum_sha256 = checksum_sha256
        asset.updated_at = datetime.utcnow()

    if asset_type == "avatar_photo":
        current_user.avatar_type = "photo"
        current_user.avatar_photo_base64 = None
        current_user.last_login_at = datetime.utcnow()

    await db.commit()
    await db.refresh(asset)
    await db.refresh(current_user)

    return UserProfileAssetResponse(
        asset_type=asset.asset_type,
        file_name=asset.file_name,
        mime_type=asset.mime_type,
        size_bytes=asset.size_bytes,
        asset_url=_asset_url(current_user.id, asset.asset_type),
        updated_at=asset.updated_at,
    )


@router.delete("/me/assets/{asset_type}", status_code=204)
async def delete_my_asset(
    asset_type: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if asset_type not in PROFILE_ASSET_TYPES:
        raise HTTPException(status_code=404, detail="Unsupported asset type")

    result = await db.execute(
        select(UserProfileAsset).where(
            UserProfileAsset.user_id == current_user.id,
            UserProfileAsset.asset_type == asset_type,
        )
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    file_path = Path(asset.storage_path)
    if file_path.exists():
        file_path.unlink(missing_ok=True)

    await db.delete(asset)
    if asset_type == "avatar_photo":
        current_user.avatar_type = "generated"
        current_user.avatar_photo_base64 = None
        current_user.last_login_at = datetime.utcnow()
    await db.commit()


@router.get("", response_model=list[UserProfileResponse])
async def list_tenant_profiles(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(User)
        .where(User.tenant_id == current_user.tenant_id, User.is_active == True)
        .order_by(User.full_name.asc(), User.email.asc())
    )
    users = result.scalars().all()
    responses = []
    for user in users:
        responses.append(await _to_response(db, user))
    return responses
