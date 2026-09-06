"""
PerX Cloud API - Main application entry point
"""
import logging
import traceback

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager

from app.core.config import settings
from app.core.database import engine, Base, get_db_context
from app.core.logging import setup_logging
from app.api.v1 import (
    routes_actors,
    routes_admin,
    routes_admin_errors,
    routes_attachments,
    routes_auth,
    routes_bignami,
    routes_claims,
    routes_communications,
    routes_cat_dispatcher,
    routes_diary,
    routes_documents,
    routes_email_processing,
    routes_emails,
    routes_internal_chat,
    routes_inspections,
    routes_videoperizia,
    routes_hub_compat,
    routes_ai_chat,
    routes_ai_prompts,
    routes_ai_routing,
    routes_planning,
    routes_portal,
    routes_portal_me,
    routes_process_jobs,
    routes_profiles,
    routes_invitations,
    routes_reporting,
    routes_routing,
    routes_tasks,
    routes_tenants,
    routes_rubrica,
    routes_user_settings,
    routes_user_directory,
    routes_processed_emails_sync,
    routes_folder_packages,
    routes_realtime,
    routes_devices,
)
from app.services.inspection_workflow_service import InspectionAutomationRuntime
from app.services.video_inspection_workflow_service import VideoInspectionAutomationRuntime
from app.services.automation_service import AutomationRuntime
from app.services.scheduled_email_service import ScheduledEmailRuntime


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan events for startup and shutdown"""
    # Startup
    setup_logging()
    # Create tables (in production, use migrations)
    # Base.metadata.create_all(bind=engine)
    await ScheduledEmailRuntime.start()
    await AutomationRuntime.start()
    await InspectionAutomationRuntime.start()
    await VideoInspectionAutomationRuntime.start()
    yield
    # Shutdown
    await VideoInspectionAutomationRuntime.stop()
    await InspectionAutomationRuntime.stop()
    await AutomationRuntime.stop()
    await ScheduledEmailRuntime.stop()


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
app.include_router(routes_bignami.router, prefix="/api/v1", tags=["bignami"])
app.include_router(routes_claims.router, prefix="/api/v1/claims", tags=["claims"])
app.include_router(routes_communications.router, prefix="/api/v1/communications", tags=["communications"])
app.include_router(routes_cat_dispatcher.router, prefix="/api/v1/cat-dispatcher", tags=["cat-dispatcher"])
app.include_router(routes_tasks.router, prefix="/api/v1", tags=["tasks"])
app.include_router(routes_documents.router, prefix="/api/v1", tags=["documents"])
app.include_router(routes_diary.router, prefix="/api/v1", tags=["diary"])
app.include_router(routes_emails.router, prefix="/api/v1/emails", tags=["emails"])
app.include_router(routes_email_processing.router, prefix="/api/v1/email-processing", tags=["email-processing"])
app.include_router(routes_process_jobs.router, prefix="/api/v1/process-jobs", tags=["process-jobs"])
app.include_router(routes_attachments.router, prefix="/api/v1/attachments", tags=["attachments"])
app.include_router(routes_hub_compat.router, prefix="/api/v1/hub", tags=["hub-compat"])
app.include_router(routes_internal_chat.router, prefix="/api/v1/internal-chat", tags=["internal-chat"])
app.include_router(routes_ai_chat.router, prefix="/api/v1/ai-chat", tags=["ai-chat"])
app.include_router(routes_ai_prompts.router, prefix="/api/v1/ai-prompts", tags=["ai-prompts"])
app.include_router(routes_ai_routing.router, prefix="/api/v1/ai-routing", tags=["ai-routing"])
app.include_router(routes_inspections.router, prefix="/api/v1", tags=["inspections"])
app.include_router(routes_videoperizia.router, prefix="/api/v1", tags=["videoperizia"])
app.include_router(routes_planning.router, prefix="/api/v1", tags=["planning"])
app.include_router(routes_portal.router, prefix="/api/v1/portal", tags=["portal"])
app.include_router(routes_portal_me.router, prefix="/api/v1/portal/me", tags=["portal-me"])
app.include_router(routes_admin.router, prefix="/api/v1/admin", tags=["admin"])
app.include_router(routes_admin_errors.router, prefix="/api/v1/admin", tags=["admin-errors"])
app.include_router(routes_invitations.router, prefix="/api/v1/invitations", tags=["invitations"])
app.include_router(routes_tenants.router, prefix="/api/v1/tenants", tags=["tenants"])
app.include_router(routes_routing.router, prefix="/api/v1/routing", tags=["routing"])
app.include_router(routes_rubrica.router, prefix="/api/v1/rubrica", tags=["rubrica"])
app.include_router(routes_actors.router, prefix="/api/v1/actors", tags=["actors"])
app.include_router(routes_user_settings.router, prefix="/api/v1/user-settings", tags=["user-settings"])
app.include_router(routes_user_directory.router, prefix="/api/v1/user-directory", tags=["user-directory"])
app.include_router(routes_processed_emails_sync.router, prefix="/api/v1/processed-emails", tags=["processed-emails"])
app.include_router(routes_folder_packages.router, prefix="/api/v1/folder-packages", tags=["folder-packages"])
app.include_router(routes_realtime.router, prefix="/api/v1/realtime", tags=["realtime"])
app.include_router(routes_devices.router, prefix="/api/v1/devices", tags=["devices"])


@app.get("/")
async def root():
    return {"message": "PerX Cloud API", "version": "1.0.0"}


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.exception_handler(Exception)
async def platform_error_log_handler(request: Request, exc: Exception):
    """Log unhandled exceptions to platform_error_log, then respond 500 as usual.

    Backend-only, first iteration of platform-wide error tracking — see
    Documentation/06-Decisioni-e-Intenzioni-Future.md (2026-09-06) for the
    intention to extend this to web apps, native apps and PerXHub later.
    """
    logging.getLogger("perx.errors").exception("Unhandled exception on %s %s", request.method, request.url.path)
    try:
        from app.api.v1.routes_admin_errors import log_platform_error

        async with get_db_context() as db:
            await log_platform_error(
                db,
                message=str(exc) or exc.__class__.__name__,
                severity="critical",
                source="backend",
                stack_trace=traceback.format_exc(),
                path=request.url.path,
                method=request.method,
            )
    except Exception:
        logging.getLogger("perx.errors").exception("Failed to persist platform_error_log row")

    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
