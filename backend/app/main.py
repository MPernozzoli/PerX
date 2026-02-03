"""
PerX Cloud API - Main application entry point
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.core.config import settings
from app.core.database import engine, Base
from app.core.logging import setup_logging
from app.api.v1 import routes_auth, routes_claims, routes_tasks, routes_emails, routes_attachments


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan events for startup and shutdown"""
    # Startup
    setup_logging()
    # Create tables (in production, use migrations)
    # Base.metadata.create_all(bind=engine)
    yield
    # Shutdown
    pass


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
app.include_router(routes_claims.router, prefix="/api/v1/claims", tags=["claims"])
app.include_router(routes_tasks.router, prefix="/api/v1", tags=["tasks"])
app.include_router(routes_emails.router, prefix="/api/v1/emails", tags=["emails"])
app.include_router(routes_attachments.router, prefix="/api/v1/attachments", tags=["attachments"])


@app.get("/")
async def root():
    return {"message": "PerX Cloud API", "version": "1.0.0"}


@app.get("/health")
async def health():
    return {"status": "healthy"}

