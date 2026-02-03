from __future__ import annotations

import json
from pathlib import Path
from threading import Condition, Lock
from typing import Dict, Iterable, Optional, Tuple, List

from models import ClaimId, MonitoringEntry, UserId


class MonitoringRegistry:
    """
    Registry in-memory con persistenza su file JSON.
    Chiave: (user_id, claim_id).
    """

    def __init__(self, store_path: Path):
        self._store_path = store_path
        self._entries: Dict[Tuple[UserId, ClaimId], MonitoringEntry] = {}
        self._lock = Lock()
        self._cond = Condition(self._lock)
        self._change_seq = 0
        self._load()

    def _load(self) -> None:
        if not self._store_path.exists():
            return
        try:
            raw = json.loads(self._store_path.read_text(encoding="utf-8"))
            for entry_dict in raw:
                entry = MonitoringEntry(**entry_dict)
                self._entries[(entry.user_id, entry.claim_id)] = entry
        except Exception:
            # Se il file è corrotto, riparte vuoto senza bloccare.
            self._entries = {}

    def _persist(self) -> None:
        self._store_path.parent.mkdir(parents=True, exist_ok=True)
        payload = [e.dict() for e in self._entries.values()]
        self._store_path.write_text(json.dumps(payload, default=str, indent=2), encoding="utf-8")

    def register(self, entry: MonitoringEntry) -> None:
        with self._lock:
            self._entries[(entry.user_id, entry.claim_id)] = entry
            self._persist()
            self._change_seq += 1
            self._cond.notify_all()

    def unregister(self, user_id: UserId, claim_id: ClaimId) -> bool:
        with self._lock:
            removed = self._entries.pop((user_id, claim_id), None)
            if removed:
                self._persist()
                self._change_seq += 1
                self._cond.notify_all()
                return True
            return False

    def get(self, user_id: UserId, claim_id: ClaimId) -> Optional[MonitoringEntry]:
        return self._entries.get((user_id, claim_id))

    def list(self) -> Iterable[MonitoringEntry]:
        return list(self._entries.values())

    def update_last_sync(self, user_id: UserId, claim_id: ClaimId, when=None) -> None:
        from datetime import datetime

        with self._lock:
            entry = self._entries.get((user_id, claim_id))
            if entry:
                entry.last_sync_at = when or datetime.utcnow()
                self._entries[(user_id, claim_id)] = entry
                self._persist()
                self._change_seq += 1
                self._cond.notify_all()

    def touch_change(self, user_id: UserId, claim_id: ClaimId, when=None) -> None:
        from datetime import datetime

        with self._lock:
            entry = self._entries.get((user_id, claim_id))
            if entry:
                entry.last_change_at = when or datetime.utcnow()
                self._entries[(user_id, claim_id)] = entry
                self._persist()
                self._change_seq += 1
                self._cond.notify_all()

    def list_changed_since(self, user_id: Optional[UserId], since) -> List[MonitoringEntry]:
        """
        Ritorna le entry con last_change_at > since (se since è None: ritorna quelle con last_change_at valorizzato).
        Se user_id è None: tutte le entry.
        """
        out: List[MonitoringEntry] = []
        for e in self._entries.values():
            if user_id and e.user_id != user_id:
                continue
            if e.last_change_at is None:
                continue
            if since is None or e.last_change_at > since:
                out.append(e)
        return out

    def wait_for_changes(self, user_id: Optional[UserId], since, timeout_seconds: float) -> List[MonitoringEntry]:
        """
        Long-poll sicuro: attende una variazione (touch_change/register/unregister/update_last_sync)
        e poi ritorna le entry cambiate dal timestamp 'since'. Ritorna [] su timeout.
        """
        with self._lock:
            start_seq = self._change_seq
            # Se già ci sono cambiamenti dopo since, ritorna subito
            immediate = self.list_changed_since(user_id, since)
            if immediate:
                return immediate
            # Attendi un segnale oppure timeout
            self._cond.wait(timeout=timeout_seconds)
            if self._change_seq == start_seq:
                return []
            return self.list_changed_since(user_id, since)