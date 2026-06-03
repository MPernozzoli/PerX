"""
Authentication routes
"""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from jose import JWTError, jwt

from app.core.config import settings
from app.core.security import (
    verify_password,
    create_access_token,
    get_current_active_user,
    is_supabase_auth_enabled,
    supabase_password_login,
    supabase_refresh_token,
)
from app.models.role import Role, user_roles
from app.models.user import User
from app.schemas.auth import LoginRequest, RefreshRequest, Token, UserResponse
from app.services.user_email_service import ensure_personal_email, ensure_professional_email, get_user_aliases

router = APIRouter()


async def _fetch_user_role_names(db: AsyncSession, user_id: str) -> list[str]:
    result = await db.execute(
        select(Role.name)
        .select_from(user_roles.join(Role, user_roles.c.role_id == Role.id))
        .where(user_roles.c.user_id == user_id)
    )
    role_names = []
    for row in result.all():
        name = row[0]
        if name == "admin_tenant":
            mapped = "admin"
        elif name == "expert":
            mapped = "perito"
        else:
            mapped = name
        if mapped not in role_names:
            role_names.append(mapped)
    return role_names


@router.post("/login", response_model=Token)
async def login(
    login_data: LoginRequest,
    db: AsyncSession = Depends(get_db)
):
    """Login with username/password, returns JWT tokens"""
    if is_supabase_auth_enabled():
        login_email = login_data.username.strip().lower()
        token_response = await supabase_password_login(login_email, login_data.password)

        result = await db.execute(
            select(User).where(
                (User.personal_email == login_email) | (User.email == login_email)
            )
        )
        user = result.scalar_one_or_none()

        if not user or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User exists in Supabase but is not provisioned in PerX"
            )

        user.last_login_at = datetime.utcnow()
        await db.commit()

        return {
            "access_token": token_response["access_token"],
            "refresh_token": token_response.get("refresh_token", ""),
            "token_type": token_response.get("token_type", "bearer"),
        }

    # Find user by email
    login_email = login_data.username.strip().lower()
    result = await db.execute(
        select(User).where((User.personal_email == login_email) | (User.email == login_email))
    )
    user = result.scalar_one_or_none()
    
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password"
        )
    
    # Verify password
    if not user.password_hash or not verify_password(login_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password"
        )
    
    # Update last login
    user.last_login_at = datetime.utcnow()
    await db.commit()
    
    # Create tokens
    access_token = create_access_token(
        data={
            "sub": user.id,
            "tenant_id": user.tenant_id,
            "is_platform_admin": user.is_platform_admin
        }
    )
    refresh_token = create_access_token(data={"sub": user.id, "type": "refresh"}, expires_delta=None)
    
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer"
    }


@router.post("/refresh", response_model=Token)
async def refresh(
    payload: RefreshRequest,
    db: AsyncSession = Depends(get_db),
):
    """Scambia un refresh_token con una nuova coppia di token."""
    if is_supabase_auth_enabled():
        token_response = await supabase_refresh_token(payload.refresh_token)
        return {
            "access_token": token_response["access_token"],
            "refresh_token": token_response.get("refresh_token", payload.refresh_token),
            "token_type": token_response.get("token_type", "bearer"),
        }

    invalid = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid refresh token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        claims = jwt.decode(
            payload.refresh_token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
    except JWTError:
        raise invalid

    if claims.get("type") != "refresh":
        raise invalid
    user_id = claims.get("sub")
    if not user_id:
        raise invalid

    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user or not user.is_active:
        raise invalid

    access_token = create_access_token(
        data={
            "sub": user.id,
            "tenant_id": user.tenant_id,
            "is_platform_admin": user.is_platform_admin,
        }
    )
    new_refresh = create_access_token(
        data={"sub": user.id, "type": "refresh"}, expires_delta=None
    )
    return {
        "access_token": access_token,
        "refresh_token": new_refresh,
        "token_type": "bearer",
    }


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get current user information"""
    role_names = await _fetch_user_role_names(db, current_user.id)
    await ensure_personal_email(db, current_user)
    await ensure_professional_email(db, current_user, role_names)
    await db.commit()
    aliases = await get_user_aliases(db, current_user)
    return UserResponse(
        id=current_user.id,
        email=current_user.personal_email or current_user.email,
        personal_email=current_user.personal_email or current_user.email,
        professional_email=current_user.professional_email,
        email_aliases=aliases,
        full_name=current_user.full_name,
        first_name=current_user.first_name or "",
        last_name=current_user.last_name or "",
        job_title=current_user.job_title,
        phone_number=current_user.phone_number,
        birth_date=current_user.birth_date.isoformat() if current_user.birth_date else None,
        birthday_visibility=current_user.birthday_visibility or "everyone",
        notify_birthday=current_user.notify_birthday,
        contract_type=current_user.contract_type,
        roles=role_names,
        avatar_type=current_user.avatar_type or "generated",
        avatar_photo_base64=current_user.avatar_photo_base64,
        generated_avatar_color=current_user.generated_avatar_color,
        generated_avatar_icon=current_user.generated_avatar_icon,
        avatar_gif_url=current_user.avatar_gif_url,
        enable_badges=current_user.enable_badges,
        send_read_receipts=current_user.send_read_receipts,
        email_signature_html=current_user.email_signature_html,
        email_signature_text=current_user.email_signature_text,
        is_active=current_user.is_active,
        tenant_id=current_user.tenant_id,
        is_platform_admin=current_user.is_platform_admin
    )
