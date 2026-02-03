from __future__ import annotations

import threading
from pathlib import Path
from typing import Callable, Dict, Optional

try:
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer
except ImportError:  # pragma: no cover - fallback se watchdog assente
    FileSystemEventHandler = object  # type: ignore
    Observer = None  # type: ignore


class _ChangeHandler(FileSystemEventHandler):
    def __init__(self, callback: Callable[[Path], None]) -> None:
        super().__init__()
        self._callback = callback

    def on_any_event(self, event):  # type: ignore
        if event.is_directory:
            return
        try:
            self._callback(Path(event.src_path))
        except Exception:
            return


class FileWatcherService:
    """
    Wrapper minimale su watchdog per monitorare modifiche file.
    Gestisce più osservatori per percorso.
    """

    def __init__(self) -> None:
        self._observers: Dict[Path, Observer] = {}
        self._lock = threading.Lock()

    def watch(self, path: Path, callback: Callable[[Path], None]) -> None:
        if Observer is None:
            return
        path = Path(path).resolve()
        with self._lock:
            if path in self._observers:
                return
            handler = _ChangeHandler(callback)
            observer = Observer()
            observer.schedule(handler, str(path), recursive=True)
            observer.daemon = True
            observer.start()
            self._observers[path] = observer

    def unwatch(self, path: Path) -> None:
        if Observer is None:
            return
        path = Path(path).resolve()
        with self._lock:
            obs = self._observers.pop(path, None)
            if obs:
                obs.stop()
                obs.join(timeout=2)

    def shutdown(self) -> None:
        if Observer is None:
            return
        with self._lock:
            for obs in self._observers.values():
                obs.stop()
                obs.join(timeout=2)
            self._observers.clear()

