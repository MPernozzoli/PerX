from __future__ import annotations

import time
from typing import Dict, List

from fastapi import APIRouter, Depends, Request
from fastapi.responses import FileResponse

from api import get_registry, get_settings
from models import MonitoringEntry
from services.monitoring_registry import MonitoringRegistry

router = APIRouter(tags=["dashboard"])
_start_time = time.time()


@router.get("/api/status/summary")
def summary(registry: MonitoringRegistry = Depends(get_registry)) -> Dict:
    entries: List[MonitoringEntry] = list(registry.list())
    users: Dict[str, List[Dict]] = {}
    for entry in entries:
        users.setdefault(entry.user_id, []).append(
            {
                "claim_id": entry.claim_id,
                "path": str(entry.root_path),
                "last_sync_at": entry.last_sync_at,
                "last_change_at": entry.last_change_at,
                "added_at": entry.added_at,
            }
        )
    return {
        "uptime_seconds": int(time.time() - _start_time),
        "total_entries": len(entries),
        "users": users,
    }


@router.get("/dashboard")
def dashboard(request: Request, settings=Depends(get_settings)):
    dashboard_path = request.app.state.dashboard_path
    return FileResponse(dashboard_path)

