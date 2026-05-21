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
    APP_PUBLIC_URL: str = "https://app.perx.it"
    
    # Security
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 hours
    PORTAL_TOKEN_SECRET: Optional[str] = None
    PORTAL_SESSION_EXPIRE_MINUTES: int = 60 * 12
    PORTAL_CHALLENGE_EXPIRE_MINUTES: int = 30
    PORTAL_APP_URL: str = "http://localhost:3001"
    PORTAL_DEBUG_PREVIEW_LINKS: bool = True
    PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH: bool = True
    PORTAL_SIGNATURE_WEBHOOK_SECRET: Optional[str] = None

    # Platform admin / multi-tenant bootstrap
    APP_ADMIN_EMAIL: str = "info@pynkstudio.it"
    APP_ADMIN_FULL_NAME: str = "Pynk Studio Admin"
    APP_ADMIN_DEFAULT_PASSWORD: str = "change-me-now"
    PLATFORM_TENANT_NAME: str = "Pynk Studio"
    PLATFORM_TENANT_SLUG: str = "pynkstudio"
    
    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:3001", "http://localhost:8080"]
    
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
    
    # Feature Flags
    FF_CLOUD_AUTH_ENABLED: bool = False
    FF_CLOUD_EMAIL_READONLY: bool = False
    FF_CLAIMS_READ_FROM_CLOUD: bool = False
    FF_CLAIMS_WRITE_TO_CLOUD_ONLY: bool = False
    FF_TASKS_ENABLED: bool = False
    FF_AUTOMATIONS_ENABLED: bool = False
    FF_INSPECTION_AUTOMATIONS_ENABLED: bool = True
    AUTOMATION_POLL_SECONDS: int = 3600
    INSPECTION_AUTOMATION_POLL_SECONDS: int = 60
    
    class Config:
        env_file = str(ENV_FILE)
        case_sensitive = True


settings = Settings()
