"""
PerX Cloud API - Main application entry point
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.core.config import settings
from app.core.database import engine, Base
from app.core.logging import setup_logging
from app.api.v1 import (
    routes_admin,
    routes_attachments,
    routes_auth,
    routes_claims,
    routes_diary,
    routes_documents,
    routes_emails,
    routes_internal_chat,
    routes_inspections,
    routes_hub_compat,
    routes_ai_chat,
    routes_planning,
    routes_portal,
    routes_profiles,
    routes_reporting,
    routes_tasks,
    routes_tenants,
    routes_whatsapp,
)
from app.services.inspection_workflow_service import InspectionAutomationRuntime


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan events for startup and shutdown"""
    # Startup
    setup_logging()
    # Create tables (in production, use migrations)
    # Base.metadata.create_all(bind=engine)
    await InspectionAutomationRuntime.start()
    yield
    # Shutdown
    await InspectionAutomationRuntime.stop()


app = FastAPI(
    title="PerX Cloud API",
    description="API backend per gestione sinistri cloud-first multiutente",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(routes_auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(routes_profiles.router, prefix="/api/v1/profiles", tags=["profiles"])
app.include_router(routes_reporting.router, prefix="/api/v1/reports", tags=["reporting"])
app.include_router(routes_claims.router, prefix="/api/v1/claims", tags=["claims"])
app.include_router(routes_tasks.router, prefix="/api/v1", tags=["tasks"])
app.include_router(routes_documents.router, prefix="/api/v1", tags=["documents"])
app.include_router(routes_diary.router, prefix="/api/v1", tags=["diary"])
app.include_router(routes_emails.router, prefix="/api/v1/emails", tags=["emails"])
app.include_router(routes_attachments.router, prefix="/api/v1/attachments", tags=["attachments"])
app.include_router(routes_whatsapp.router, prefix="/api/v1/whatsapp", tags=["whatsapp"])
app.include_router(routes_hub_compat.router, prefix="/api/v1/hub", tags=["hub-compat"])
app.include_router(routes_internal_chat.router, prefix="/api/v1/internal-chat", tags=["internal-chat"])
app.include_router(routes_ai_chat.router, prefix="/api/v1/ai-chat", tags=["ai-chat"])
app.include_router(routes_inspections.router, prefix="/api/v1", tags=["inspections"])
app.include_router(routes_planning.router, prefix="/api/v1", tags=["planning"])
app.include_router(routes_portal.router, prefix="/api/v1/portal", tags=["portal"])
app.include_router(routes_admin.router, prefix="/api/v1/admin", tags=["admin"])
app.include_router(routes_tenants.router, prefix="/api/v1/tenants", tags=["tenants"])


@app.get("/")
async def root():
    return {"message": "PerX Cloud API", "version": "1.0.0"}


@app.get("/health")
async def health():
    return {"status": "healthy"}
