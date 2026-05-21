"""
Security utilities: JWT, password hashing, RBAC
"""
import asyncio
from datetime import datetime, timedelta
from typing import Optional
import json
from urllib import error as urlerror
from urllib import request as urlrequest
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.models.user import User

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """Hash a password"""
    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create JWT access token"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt


def is_supabase_auth_enabled() -> bool:
    return bool(
        settings.FF_CLOUD_AUTH_ENABLED
        and settings.SUPABASE_URL
        and settings.SUPABASE_ANON_KEY
    )


async def _supabase_http_request(
    method: str,
    path: str,
    headers: dict[str, str],
    payload: dict | None = None,
) -> dict:
    def _do_request() -> dict:
        url = f"{settings.SUPABASE_URL}{path}"
        body = None
        request_headers = headers.copy()
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            request_headers["Content-Type"] = "application/json"

        req = urlrequest.Request(url, data=body, headers=request_headers, method=method)
        with urlrequest.urlopen(req, timeout=20) as response:
            raw = response.read()
            if not raw:
                return {}
            return json.loads(raw.decode("utf-8"))

    try:
        return await asyncio.to_thread(_do_request)
    except urlerror.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=detail or "Supabase authentication failed",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except urlerror.URLError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase authentication service unavailable",
        ) from exc


async def supabase_password_login(email: str, password: str) -> dict:
    if not is_supabase_auth_enabled():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Supabase auth is not enabled",
        )

    return await _supabase_http_request(
        "POST",
        "/auth/v1/token?grant_type=password",
        headers={
            "apikey": settings.SUPABASE_ANON_KEY,
            "Accept": "application/json",
        },
        payload={"email": email, "password": password},
    )


async def get_supabase_user(token: str) -> dict:
    if not is_supabase_auth_enabled():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Cloud auth not enabled",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return await _supabase_http_request(
        "GET",
        "/auth/v1/user",
        headers={
            "apikey": settings.SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
    )


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    """Get current authenticated user from JWT token"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    user_id: str | None = None
    user_email: str | None = None
    idp_subject: str | None = None

    if is_supabase_auth_enabled():
        supabase_user = await get_supabase_user(token)
        user_email = (supabase_user.get("email") or "").lower()
        idp_subject = supabase_user.get("id")
        if not user_email:
            raise credentials_exception
    else:
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
            user_id = payload.get("sub")
            if user_id is None:
                raise credentials_exception
        except JWTError:
            raise credentials_exception
    
    # Fetch user from DB
    from sqlalchemy import select
    if is_supabase_auth_enabled():
        query = select(User).where(User.is_active == True).where(
            (User.idp_subject == idp_subject) | (User.personal_email == user_email) | (User.email == user_email)
        )
    else:
        query = select(User).where(User.id == user_id).where(User.is_active == True)

    result = await db.execute(query)
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exception

    if is_supabase_auth_enabled() and idp_subject and user.idp_subject != idp_subject:
        user.idp_subject = idp_subject
        await db.commit()
    
    return user


async def get_current_active_user(
    current_user: User = Depends(get_current_user)
) -> User:
    """Get current active user"""
    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user


async def get_current_platform_admin(
    current_user: User = Depends(get_current_active_user)
) -> User:
    """Allow only platform-level administrators."""
    if not current_user.is_platform_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Platform admin access required"
        )
    return current_user
