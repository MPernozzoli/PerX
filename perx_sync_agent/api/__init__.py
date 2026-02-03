from fastapi import Depends, Request

from models import MonitoringEntry
from services.file_watcher_service import FileWatcherService
from services.filesystem_service import FilesystemService
from services.monitoring_registry import MonitoringRegistry


def get_registry(request: Request) -> MonitoringRegistry:
    return request.app.state.monitoring_registry


def get_filesystem_service(request: Request) -> FilesystemService:
    return request.app.state.filesystem_service


def get_watcher_service(request: Request) -> FileWatcherService:
    return request.app.state.watcher_service


def get_settings(request: Request):
    return request.app.state.settings


def register_watcher(entry: MonitoringEntry, watcher: FileWatcherService, on_change) -> None:
    """Registra un watcher per il sinistro, ignorando errori se watchdog non è disponibile."""
    try:
        watcher.watch(entry.root_path, on_change)
    except Exception:
        return

