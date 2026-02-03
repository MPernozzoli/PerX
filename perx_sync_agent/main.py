from __future__ import annotations

"""
PerX Sync Agent - Hub Worker Mode
Agent passivo che comunica solo con l'Hub per gestione file sinistri.
"""

import os
import sys
import asyncio
import logging
import shutil
from datetime import datetime
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import List, Optional

import uvicorn
from fastapi import FastAPI, UploadFile, File, Depends, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel

from config import load_settings
from services.auth_service import get_token
from services.filesystem_service import FilesystemService
from services.hub_worker import HubWorkerService
from services.job_queue import JobQueue

__version__ = "2.0.0"
START_TIME = datetime.now()


def configure_logging(log_dir: Path, level: str) -> logging.Logger:
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "perx_sync_agent.log"

    logger = logging.getLogger("perx_sync_agent")
    logger.setLevel(level.upper())

    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s - %(message)s")

    sh = logging.StreamHandler()
    sh.setFormatter(formatter)
    logger.addHandler(sh)

    fh = RotatingFileHandler(
        log_path, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    fh.setFormatter(formatter)
    logger.addHandler(fh)

    return logger


# Response Models
class HealthResponse(BaseModel):
    status: str
    version: str
    uptime: float
    hub_url: str
    active_jobs: int
    queue_size: int


class VersionResponse(BaseModel):
    version: str
    install_path: str


class UpdateResponse(BaseModel):
    status: str
    files: List[str]


def create_app() -> FastAPI:
    settings = load_settings()
    logger = configure_logging(settings.log_dir, settings.log_level)

    app = FastAPI(
        title="PerX Sync Agent",
        version=__version__,
        description="Hub Worker for file sync between FS Legacy and Vault"
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Stato condiviso
    app.state.settings = settings
    app.state.logger = logger
    app.state.filesystem_service = FilesystemService(
        root_path=settings.gestionale_root_path,
        user_mapping=settings.user_mapping,
    )
    
    # Job queue con limiti
    app.state.job_queue = JobQueue(
        max_concurrent=4,
        max_upload=2,
        max_download=2
    )
    
    # Hub worker (avviato dopo startup)
    app.state.hub_worker: Optional[HubWorkerService] = None

    # === Health & Status Endpoints ===
    
    @app.get("/health", response_model=HealthResponse)
    def health():
        uptime = (datetime.now() - START_TIME).total_seconds()
        hub_worker = app.state.hub_worker
        
        return HealthResponse(
            status="ok",
            version=__version__,
            uptime=uptime,
            hub_url=settings.hub_url or "not configured",
            active_jobs=app.state.job_queue.active_count,
            queue_size=app.state.job_queue.queue_size
        )
    
    # === Restart Endpoint (richiede autenticazione) ===
    
    @app.post("/restart")
    async def restart(token: str = Depends(get_token)):
        """Riavvia l'agent (Task Scheduler lo riavviera)"""
        asyncio.create_task(delayed_shutdown())
        return {"status": "restarting"}
    
    # === Update Endpoints (richiedono autenticazione) ===
    
    @app.get("/update/version", response_model=VersionResponse)
    def get_version(token: str = Depends(get_token)):
        """Restituisce versione corrente e path installazione"""
        return VersionResponse(
            version=__version__,
            install_path=str(settings.agent_install_path or Path(__file__).parent)
        )
    
    @app.post("/update/upload", response_model=UpdateResponse)
    async def upload_update(files: List[UploadFile] = File(...), token: str = Depends(get_token)):
        """Riceve file di aggiornamento dall'Hub"""
        install_path = Path(settings.agent_install_path or Path(__file__).parent)
        uploaded_files = []
        
        for file in files:
            # Validazione sicurezza: previeni path traversal
            safe_filename = Path(file.filename).name
            if ".." in file.filename or file.filename.startswith("/"):
                logger.warning(f"Path traversal attempt blocked: {file.filename}")
                continue
            
            target = install_path / safe_filename
            
            # Backup file esistente
            if target.exists():
                backup = target.with_suffix(target.suffix + ".bak")
                shutil.copy(target, backup)
                logger.info(f"Backup created: {backup}")
            
            # Salva nuovo file
            content = await file.read()
            with open(target, "wb") as f:
                f.write(content)
            
            uploaded_files.append(safe_filename)
            logger.info(f"Updated file: {target}")
        
        return UpdateResponse(
            status="uploaded",
            files=uploaded_files
        )
    
    # === Startup/Shutdown ===
    
    @app.on_event("startup")
    async def startup():
        logger.info(f"PerX Sync Agent v{__version__} starting...")
        logger.info(f"Hub URL: {settings.hub_url}")
        logger.info(f"Root Path: {settings.gestionale_root_path}")
        
        # Avvia Hub Worker se configurato
        if settings.hub_url:
            app.state.hub_worker = HubWorkerService(
                hub_url=settings.hub_url,
                filesystem_service=app.state.filesystem_service,
                job_queue=app.state.job_queue,
                logger=logger,
                scan_interval=4 * 60 * 60  # 4 ore
            )
            asyncio.create_task(app.state.hub_worker.start())
        else:
            logger.warning("Hub URL not configured - running in standalone mode")
    
    @app.on_event("shutdown")
    async def shutdown():
        if app.state.hub_worker:
            await app.state.hub_worker.stop()
        logger.info("Sync Agent stopped")

    return app


async def delayed_shutdown():
    """Shutdown dopo risposta API"""
    await asyncio.sleep(1)
    os._exit(0)


app = create_app()


if __name__ == "__main__":
    settings = load_settings()
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=settings.port,
        reload=False,
    )
