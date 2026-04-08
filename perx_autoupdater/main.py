#!/usr/bin/env python3
"""
PerX AutoUpdater Worker
Monitora il repository di sviluppo e notifica quando ci sono aggiornamenti disponibili.
"""

import asyncio
import hashlib
import json
import os
import sys
import signal
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import httpx
from fastapi import FastAPI
from pydantic import BaseModel
from contextlib import asynccontextmanager

__version__ = "1.0.0"
START_TIME = datetime.now()

# Configurazione
HUB_URL = os.getenv("HUB_URL", "http://localhost:8080")
SCAN_INTERVAL = int(os.getenv("SCAN_INTERVAL", "60"))  # secondi
PORT = int(os.getenv("PORT", "8084"))

# Directory di lavoro (cartella clone/repo). AutoUpdater la scannerizza; per applicare aggiornamenti riesegui install-and-launch.sh dalla repo.
REPO_BASE = Path(os.getenv("REPO_BASE", "/Users/mpernozzoli/PerX HUB"))

# Componenti da monitorare
COMPONENTS = {
    "perx_hub": {
        "path": REPO_BASE / "PerXHub",
        "type": "swift",
        "extensions": [".swift", ".json", ".plist"],
        "remote": False,  # Locale su Mac Mini
    },
    "perx_hub_monitor": {
        "path": REPO_BASE / "PerXHubMonitor",
        "type": "swift",
        "extensions": [".swift", ".json", ".plist"],
        "remote": False,
    },
    "perx_core": {
        "path": REPO_BASE / "PerXCore",
        "type": "swift",
        "extensions": [".swift", ".json"],
        "remote": False,
    },
    "perx_email_worker": {
        "path": REPO_BASE / "perx_email_worker",
        "type": "python",
        "extensions": [".py", ".json", ".txt"],
        "remote": False,
    },
    "perx_wa_bridge": {
        "path": REPO_BASE / "perx_wa_bridge",
        "type": "node",
        "extensions": [".js", ".json"],
        "remote": False,
    },
}

# Stato del worker
class UpdateState:
    def __init__(self):
        self.file_hashes: Dict[str, Dict[str, str]] = {}  # component -> {filepath: hash}
        self.pending_updates: Dict[str, List[str]] = {}  # component -> [changed files]
        self.last_scan: Optional[datetime] = None
        self.is_running = False

state = UpdateState()


# MARK: - API Models

class HealthResponse(BaseModel):
    status: str
    version: str
    uptime: float
    last_scan: Optional[str]
    components_monitored: int

class ComponentUpdate(BaseModel):
    component: str
    changed_files: List[str]
    timestamp: str

class UpdatesResponse(BaseModel):
    pending_updates: Dict[str, List[str]]
    last_scan: Optional[str]

class AckUpdateRequest(BaseModel):
    component: str


# MARK: - File Monitoring

def calculate_file_hash(filepath: Path) -> Optional[str]:
    """Calcola SHA256 di un file."""
    try:
        hasher = hashlib.sha256()
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception as e:
        print(f"[AutoUpdater] Error hashing {filepath}: {e}")
        return None

def scan_component(component_id: str, config: dict) -> Dict[str, str]:
    """Scansiona un componente e restituisce gli hash dei file."""
    path = config["path"]
    extensions = config["extensions"]
    file_hashes = {}
    
    if not path.exists():
        print(f"[AutoUpdater] Component path not found: {path}")
        return file_hashes
    
    for ext in extensions:
        for filepath in path.rglob(f"*{ext}"):
            # Ignora cartelle nascoste e build
            rel_path = filepath.relative_to(path)
            if any(part.startswith('.') or part in ['build', 'DerivedData', '__pycache__', 'node_modules', '.build'] 
                   for part in rel_path.parts):
                continue
            
            file_hash = calculate_file_hash(filepath)
            if file_hash:
                file_hashes[str(rel_path)] = file_hash
    
    return file_hashes

def detect_changes(component_id: str, new_hashes: Dict[str, str]) -> List[str]:
    """Rileva i file cambiati rispetto alla scansione precedente."""
    old_hashes = state.file_hashes.get(component_id, {})
    changes = []
    
    # File nuovi o modificati
    for filepath, new_hash in new_hashes.items():
        old_hash = old_hashes.get(filepath)
        if old_hash is None or old_hash != new_hash:
            changes.append(filepath)
    
    # File rimossi (opzionale, non li segnaliamo come update)
    # for filepath in old_hashes:
    #     if filepath not in new_hashes:
    #         changes.append(f"[deleted] {filepath}")
    
    return changes


# MARK: - Hub Notification

async def notify_hub_update(component_id: str, changed_files: List[str]):
    """Notifica l'Hub di un aggiornamento disponibile."""
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            payload = {
                "component": component_id,
                "changed_files": changed_files,
                "timestamp": datetime.now().isoformat()
            }
            response = await client.post(
                f"{HUB_URL}/internal/updates/notify",
                json=payload
            )
            if response.status_code == 200:
                print(f"[AutoUpdater] ✅ Hub notified of {component_id} update ({len(changed_files)} files)")
            else:
                print(f"[AutoUpdater] ⚠️ Hub notification failed: {response.status_code}")
    except Exception as e:
        print(f"[AutoUpdater] ❌ Failed to notify Hub: {e}")


# MARK: - Scan Loop

async def scan_loop():
    """Loop principale di scansione."""
    print(f"[AutoUpdater] Starting scan loop (interval: {SCAN_INTERVAL}s)")
    state.is_running = True
    
    # Prima scansione: stabilisci baseline
    for component_id, config in COMPONENTS.items():
        state.file_hashes[component_id] = scan_component(component_id, config)
        print(f"[AutoUpdater] Baseline for {component_id}: {len(state.file_hashes[component_id])} files")
    
    state.last_scan = datetime.now()
    
    while state.is_running:
        await asyncio.sleep(SCAN_INTERVAL)
        
        for component_id, config in COMPONENTS.items():
            new_hashes = scan_component(component_id, config)
            changes = detect_changes(component_id, new_hashes)
            
            if changes:
                print(f"[AutoUpdater] 🔄 Changes detected in {component_id}: {len(changes)} files")
                
                # Aggiungi ai pending updates
                if component_id not in state.pending_updates:
                    state.pending_updates[component_id] = []
                
                for changed_file in changes:
                    if changed_file not in state.pending_updates[component_id]:
                        state.pending_updates[component_id].append(changed_file)
                
                # Notifica l'Hub
                await notify_hub_update(component_id, changes)
            
            # Aggiorna gli hash
            state.file_hashes[component_id] = new_hashes
        
        state.last_scan = datetime.now()


# MARK: - FastAPI App

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Gestisce il ciclo di vita dell'applicazione."""
    # Startup
    scan_task = asyncio.create_task(scan_loop())
    print(f"[AutoUpdater] Worker started on port {PORT}")
    
    yield
    
    # Shutdown
    state.is_running = False
    scan_task.cancel()
    try:
        await scan_task
    except asyncio.CancelledError:
        pass
    print("[AutoUpdater] Worker stopped")

app = FastAPI(
    title="PerX AutoUpdater",
    version=__version__,
    lifespan=lifespan
)


@app.get("/health", response_model=HealthResponse)
async def health():
    """Stato di salute del worker."""
    uptime = (datetime.now() - START_TIME).total_seconds()
    
    return HealthResponse(
        status="ok",
        version=__version__,
        uptime=uptime,
        last_scan=state.last_scan.isoformat() if state.last_scan else None,
        components_monitored=len(COMPONENTS)
    )


@app.get("/updates", response_model=UpdatesResponse)
async def get_updates():
    """Restituisce gli aggiornamenti pendenti."""
    return UpdatesResponse(
        pending_updates=state.pending_updates,
        last_scan=state.last_scan.isoformat() if state.last_scan else None
    )


@app.post("/updates/ack")
async def ack_update(request: AckUpdateRequest):
    """Conferma che un aggiornamento è stato applicato."""
    component = request.component
    
    if component in state.pending_updates:
        del state.pending_updates[component]
        print(f"[AutoUpdater] ✅ Update acknowledged for {component}")
        return {"status": "ok", "component": component}
    
    return {"status": "not_found", "component": component}


@app.post("/scan")
async def trigger_scan():
    """Forza una scansione immediata."""
    changes_detected = {}
    
    for component_id, config in COMPONENTS.items():
        new_hashes = scan_component(component_id, config)
        changes = detect_changes(component_id, new_hashes)
        
        if changes:
            changes_detected[component_id] = changes
            
            if component_id not in state.pending_updates:
                state.pending_updates[component_id] = []
            
            for changed_file in changes:
                if changed_file not in state.pending_updates[component_id]:
                    state.pending_updates[component_id].append(changed_file)
            
            await notify_hub_update(component_id, changes)
        
        state.file_hashes[component_id] = new_hashes
    
    state.last_scan = datetime.now()
    
    return {
        "status": "ok",
        "changes_detected": changes_detected,
        "scan_time": state.last_scan.isoformat()
    }


@app.post("/restart")
async def restart():
    """Riavvia il worker."""
    print("[AutoUpdater] 🔄 Restart requested")
    
    # Programma restart
    async def do_restart():
        await asyncio.sleep(1)
        os.execv(sys.executable, [sys.executable] + sys.argv)
    
    asyncio.create_task(do_restart())
    
    return {"status": "restarting"}


# MARK: - Main

if __name__ == "__main__":
    import uvicorn
    
    # Gestione segnali
    def handle_signal(signum, frame):
        print(f"[AutoUpdater] Received signal {signum}, shutting down...")
        state.is_running = False
        sys.exit(0)
    
    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=PORT,
        log_level="info"
    )
