from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Tuple

from services.monitoring_registry import MonitoringRegistry


@dataclass(frozen=True)
class _Signature:
    files: int
    bytes: int
    max_mtime_ns: int


def _compute_signature(root: Path) -> _Signature:
    """
    Firma veloce e sicura della directory:
    - conta file
    - somma bytes
    - max mtime (ns)
    Non legge contenuti (niente hash), quindi è sostenibile periodicamente.
    """
    files = 0
    total_bytes = 0
    max_mtime = 0

    def walk(p: Path) -> None:
        nonlocal files, total_bytes, max_mtime
        try:
            with os.scandir(p) as it:
                for entry in it:
                    try:
                        if entry.is_dir(follow_symlinks=False):
                            walk(Path(entry.path))
                        elif entry.is_file(follow_symlinks=False):
                            try:
                                st = entry.stat(follow_symlinks=False)
                            except OSError:
                                continue
                            files += 1
                            total_bytes += int(st.st_size)
                            max_mtime = max(max_mtime, int(getattr(st, "st_mtime_ns", int(st.st_mtime * 1_000_000_000))))
                    except OSError:
                        continue
        except OSError:
            return

    walk(Path(root))
    return _Signature(files=files, bytes=total_bytes, max_mtime_ns=max_mtime)


class ReconcileService:
    """
    Job periodico “rete di sicurezza”:
    - scorre tutte le entry monitorate
    - calcola una firma veloce
    - se cambia rispetto alla precedente, fa touch_change (così il client può reagire)
    """

    def __init__(self, registry: MonitoringRegistry, interval_seconds: int, logger):
        self._registry = registry
        self._interval = max(60, int(interval_seconds))  # minimo 1 minuto
        self._logger = logger
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._last: Dict[Tuple[str, str], _Signature] = {}

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._run, name="perx_reconcile", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _run(self) -> None:
        # loop infinito con sleep interruptible
        while not self._stop.is_set():
            try:
                self._tick()
            except Exception as e:
                try:
                    self._logger.error("reconcile tick error: %s", e)
                except Exception:
                    pass
            self._stop.wait(self._interval)

    def _tick(self) -> None:
        entries = list(self._registry.list())
        for entry in entries:
            key = (entry.user_id, entry.claim_id)
            root = Path(entry.root_path)
            sig = _compute_signature(root)
            prev = self._last.get(key)
            if prev is None:
                self._last[key] = sig
                continue
            if sig != prev:
                self._last[key] = sig
                self._registry.touch_change(entry.user_id, entry.claim_id)
