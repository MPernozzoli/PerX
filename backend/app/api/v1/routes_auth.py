"""
Authentication routes
"""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.security import (
    verify_password,
    create_access_token,
    get_current_active_user,
    is_supabase_auth_enabled,
    supabase_password_login,
)
from app.models.role import Role, user_roles
from app.models.user import User
from app.schemas.auth import LoginRequest, Token, UserResponse

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
        token_response = await supabase_password_login(login_data.username, login_data.password)

        result = await db.execute(
            select(User).where(User.email == login_data.username.lower())
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
    result = await db.execute(
        select(User).where(User.email == login_data.username)
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


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get current user information"""
    role_names = await _fetch_user_role_names(db, current_user.id)
    return UserResponse(
        id=current_user.id,
        email=current_user.email,
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
