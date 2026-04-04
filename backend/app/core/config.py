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
    
    # Security
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 hours

    # Platform admin / multi-tenant bootstrap
    APP_ADMIN_EMAIL: str = "info@pynkstudio.it"
    APP_ADMIN_FULL_NAME: str = "Pynk Studio Admin"
    APP_ADMIN_DEFAULT_PASSWORD: str = "change-me-now"
    PLATFORM_TENANT_NAME: str = "Pynk Studio"
    PLATFORM_TENANT_SLUG: str = "pynkstudio"
    
    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:8080"]
    
    # Storage
    STORAGE_BUCKET_NAME: str = "perx-attachments"
    STORAGE_PROVIDER: str = "gcs"  # gcs, s3
    
    # Pub/Sub
    PUBSUB_PROJECT_ID: str = ""
    PUBSUB_TOPIC_EMAIL_INGESTED: str = "email_ingested"
    PUBSUB_TOPIC_CLAIM_UPDATED: str = "claim_created_or_updated"
    PUBSUB_TOPIC_CLAIM_STATE_CHANGED: str = "claim_state_changed"
    PUBSUB_TOPIC_TASK_UPDATED: str = "task_created_or_updated"
    
    # Mail Ingestion
    MAIL_INGESTION_ENABLED: bool = True
    MAIL_POLL_INTERVAL_SECONDS: int = 300  # 5 minutes
    
    # Feature Flags
    FF_CLOUD_AUTH_ENABLED: bool = False
    FF_CLOUD_EMAIL_READONLY: bool = False
    FF_CLAIMS_READ_FROM_CLOUD: bool = False
    FF_CLAIMS_WRITE_TO_CLOUD_ONLY: bool = False
    FF_TASKS_ENABLED: bool = False
    FF_AUTOMATIONS_ENABLED: bool = False
    
    class Config:
        env_file = str(ENV_FILE)
        case_sensitive = True


settings = Settings()
