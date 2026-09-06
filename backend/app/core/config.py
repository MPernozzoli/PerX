"""
Configuration management using Pydantic Settings
"""
from pathlib import Path
from pydantic_settings import BaseSettings
from typing import List, Optional


ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    # App
    APP_NAME: str = "PerX Cloud API"
    ENV: str = "dev"  # dev, staging, prod
    DEBUG: bool = True
    
    # Database
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/perx_cloud"

    # Supabase
    SUPABASE_URL: Optional[str] = None
    SUPABASE_ANON_KEY: Optional[str] = None
    SUPABASE_SERVICE_ROLE_KEY: Optional[str] = None
    SUPABASE_STORAGE_BUCKET: str = "perx-portal-uploads"
    APP_PUBLIC_URL: str = "https://app.perx.it"
    LOGIN_PUBLIC_URL: str = "https://login.perx.it"
    
    # Security
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 hours
    PORTAL_TOKEN_SECRET: Optional[str] = None
    PORTAL_SESSION_EXPIRE_MINUTES: int = 60 * 12
    PORTAL_SESSION_REMEMBER_ME_DAYS: int = 30
    PORTAL_CHALLENGE_EXPIRE_MINUTES: int = 30
    PORTAL_OTP_EXPIRE_MINUTES: int = 10
    PORTAL_OTP_MAX_ATTEMPTS: int = 5
    PORTAL_APP_URL: str = "http://localhost:3001"
    PORTAL_DEBUG_PREVIEW_LINKS: bool = True
    PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH: bool = True
    PORTAL_SIGNATURE_WEBHOOK_SECRET: Optional[str] = None
    PORTAL_VAPID_PUBLIC_KEY: Optional[str] = None
    PORTAL_VAPID_PRIVATE_KEY: Optional[str] = None
    PORTAL_VAPID_SUBJECT: str = "mailto:info@perx.it"
    ROUTING_RESOLVE_SECRET: Optional[str] = None

    # LiveKit videocall provider for videoperizia. URL is the wss:// signaling
    # endpoint (e.g. wss://<project>.livekit.cloud). API key/secret sign client
    # tokens server-side — never expose the secret to clients.
    LIVEKIT_URL: Optional[str] = None
    LIVEKIT_API_KEY: Optional[str] = None
    LIVEKIT_API_SECRET: Optional[str] = None
    LIVEKIT_TOKEN_TTL_SECONDS: int = 3600

    # Platform bridge: server-to-server key for external admin panels (PynkStudio)
    # to call /api/v1/admin/* without a human JWT session. See routes_admin.py /
    # require_platform_admin_or_api_key in security.py. None disables the bridge.
    PLATFORM_ADMIN_API_KEY: Optional[str] = None

    # Platform admin / multi-tenant bootstrap
    APP_ADMIN_EMAIL: str = "info@pynkstudio.it"
    APP_ADMIN_FULL_NAME: str = "Pynk Studio Admin"
    APP_ADMIN_DEFAULT_PASSWORD: str = "change-me-now"
    PLATFORM_TENANT_NAME: str = "Pynk Studio"
    PLATFORM_TENANT_SLUG: str = "pynkstudio"

    # Single-tenant V1 bootstrap
    SINGLE_TENANT_MODE: bool = True
    SINGLE_TENANT_ID: str = "perx-single-tenant"
    SINGLE_TENANT_NAME: str = "PerX Studio"
    SINGLE_TENANT_SLUG: str = "perx-studio"
    SINGLE_TENANT_ADMIN_EMAIL: Optional[str] = None
    SINGLE_TENANT_ADMIN_FULL_NAME: Optional[str] = None
    SINGLE_TENANT_ADMIN_PASSWORD: Optional[str] = None
    
    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:3001", "http://localhost:5173", "http://localhost:8080"]
    
    # Storage
    STORAGE_BUCKET_NAME: str = "perx-attachments"
    STORAGE_PROVIDER: str = "gcs"  # gcs, s3
    VAULT_STORAGE_PROVIDER: str = "local"  # local, mac_mini
    VAULT_STORAGE_ROOT: str = "/tmp/perx-hub-compat"
    MAC_MINI_STORAGE_URL: Optional[str] = None
    MAC_MINI_STORAGE_TOKEN: Optional[str] = None
    
    # Pub/Sub
    PUBSUB_PROJECT_ID: str = ""
    PUBSUB_TOPIC_EMAIL_INGESTED: str = "email_ingested"
    PUBSUB_TOPIC_CLAIM_UPDATED: str = "claim_created_or_updated"
    PUBSUB_TOPIC_CLAIM_STATE_CHANGED: str = "claim_state_changed"
    PUBSUB_TOPIC_TASK_UPDATED: str = "task_created_or_updated"
    
    # Mail Ingestion
    MAIL_INGESTION_ENABLED: bool = True
    MAIL_POLL_INTERVAL_SECONDS: int = 300  # 5 minutes
    LOCAL_AI_WORKER_SHARED_SECRET: Optional[str] = None

    # Resend outbound email
    RESEND_API_KEY: Optional[str] = None
    RESEND_DEFAULT_FROM_EMAIL: Optional[str] = None
    RESEND_SCHEDULED_EMAILS_ENABLED: bool = True
    RESEND_SCHEDULED_EMAIL_POLL_SECONDS: int = 30
    RESEND_SCHEDULED_EMAIL_BATCH_SIZE: int = 25
    
    # APNs (Apple Push Notifications) — used by PerX Lite iOS for push + VoIP/CallKit
    APNS_KEY_ID: Optional[str] = None
    APNS_TEAM_ID: Optional[str] = None
    APNS_KEY_PATH: Optional[str] = None  # path to AuthKey_<KEY_ID>.p8 (alt to APNS_KEY_PEM)
    APNS_KEY_PEM: Optional[str] = None   # contents of the .p8 (PEM); preferred on PaaS
    APNS_BUNDLE_ID: Optional[str] = None  # e.g. com.perx.PerXLite
    APNS_VOIP_BUNDLE_ID: Optional[str] = None  # usually same bundle for VoIP push
    APNS_USE_SANDBOX: bool = False

    # Feature Flags
    FF_CLOUD_AUTH_ENABLED: bool = False
    FF_CLOUD_EMAIL_READONLY: bool = False
    FF_CLAIMS_READ_FROM_CLOUD: bool = False
    FF_CLAIMS_WRITE_TO_CLOUD_ONLY: bool = False
    FF_TASKS_ENABLED: bool = False
    FF_AUTOMATIONS_ENABLED: bool = False
    FF_LOCAL_AI_PROCESS_JOBS_ENABLED: bool = True
    FF_INSPECTION_AUTOMATIONS_ENABLED: bool = True
    FF_PORTAL_PHOTO_AI_ANALYSIS_ENABLED: bool = True
    FF_PORTAL_PHOTO_ANTIFRAUD_ENABLED: bool = True
    PORTAL_PHOTO_SIGNED_URL_EXPIRE_SECONDS: int = 86400  # 24h
    AUTOMATION_POLL_SECONDS: int = 3600
    INSPECTION_AUTOMATION_POLL_SECONDS: int = 60
    
    class Config:
        env_file = str(ENV_FILE)
        case_sensitive = True


settings = Settings()
