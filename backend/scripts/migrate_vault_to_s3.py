"""
Migra i file del vault dal provider attuale (mac_mini o local) a S3-compatibile.

Il Mac mini NON espone un endpoint di listing: l'elenco dei file viene letto dal
database (documents.storage_path + document_versions.storage_path), che e' la
fonte di verita' dei percorsi relativi.

Uso (dalla cartella backend/, dry-run di default):
    python scripts/migrate_vault_to_s3.py --source mac_mini --bucket perx-vault
    python scripts/migrate_vault_to_s3.py --source local --source-root /data/vault \\
        --bucket perx-vault --execute --concurrency 8 --report report.json

Garanzie: non cancella e non modifica MAI nulla alla sorgente; e' idempotente
(salta oggetti gia' presenti con stessa size e SHA-256 nei metadata) ed e'
riavviabile (--state-file). Credenziali S3 dalla catena standard AWS.
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Optional, Protocol

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.vault_storage_service import SHA256_METADATA_KEY, S3ObjectStore  # noqa: E402


@dataclass(frozen=True)
class FileEntry:
    path: str
    size_bytes: Optional[int] = None
    sha256: Optional[str] = None


class SourceReader(Protocol):
    def read(self, relative_path: str) -> bytes:
        """Ritorna i byte o solleva FileNotFoundError."""


class LocalSource:
    def __init__(self, root: str) -> None:
        self.root = Path(root)

    def read(self, relative_path: str) -> bytes:
        target = (self.root / relative_path).resolve()
        if self.root.resolve() not in target.parents:
            raise FileNotFoundError(relative_path)
        if not target.is_file():
            raise FileNotFoundError(relative_path)
        return target.read_bytes()


class MacMiniSource:
    """Lettura (solo download) via API interna del Mac mini."""

    def __init__(self, base_url: str, token: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token

    def read(self, relative_path: str) -> bytes:
        import httpx

        response = httpx.post(
            f"{self.base_url}/internal/storage/files/download",
            headers={"X-PerX-Storage-Token": self.token},
            json={"relativePath": relative_path},
            timeout=httpx.Timeout(120.0, connect=10.0),
        )
        if response.status_code == 404:
            raise FileNotFoundError(relative_path)
        response.raise_for_status()
        encoded = (response.json() if response.content else {}).get("data")
        if not encoded:
            raise FileNotFoundError(relative_path)
        return base64.b64decode(encoded)


@dataclass
class Report:
    dry_run: bool
    total: int = 0
    copied: list = field(default_factory=list)
    skipped: list = field(default_factory=list)
    would_copy: list = field(default_factory=list)
    missing_at_source: list = field(default_factory=list)
    failed: list = field(default_factory=list)
    warnings: list = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "dry_run": self.dry_run,
            "total": self.total,
            "counts": {
                "copied": len(self.copied),
                "skipped": len(self.skipped),
                "would_copy": len(self.would_copy),
                "missing_at_source": len(self.missing_at_source),
                "failed": len(self.failed),
            },
            "copied": self.copied,
            "skipped": self.skipped,
            "would_copy": self.would_copy,
            "missing_at_source": self.missing_at_source,
            "failed": self.failed,
            "warnings": self.warnings,
        }


def sha256_hex(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def _dest_matches(head: Optional[dict], size: Optional[int], sha: Optional[str]) -> bool:
    if not head or size is None or sha is None:
        return False
    meta = {k.lower(): v for k, v in (head.get("Metadata") or {}).items()}
    return int(head.get("ContentLength", -1)) == size and meta.get(SHA256_METADATA_KEY) == sha


def migrate_one(
    entry: FileEntry,
    source: SourceReader,
    dest: S3ObjectStore,
    report: Report,
    lock: threading.Lock,
) -> str:
    """Ritorna l'esito: copied | skipped | missing | failed."""
    path = entry.path
    try:
        head = dest.head(path)
        # Skip senza leggere la sorgente quando il DB ha gia' size + sha256.
        if _dest_matches(head, entry.size_bytes, entry.sha256):
            with lock:
                report.skipped.append(path)
            return "skipped"

        try:
            content = source.read(path)
        except FileNotFoundError:
            with lock:
                report.missing_at_source.append(path)
            return "missing"

        digest = sha256_hex(content)
        if entry.sha256 and entry.sha256 != digest:
            with lock:
                report.warnings.append(f"{path}: SHA-256 sorgente diverso da quello nel DB")
        if _dest_matches(head, len(content), digest):
            with lock:
                report.skipped.append(path)
            return "skipped"

        import mimetypes

        mime = mimetypes.guess_type(path)[0]
        dest.put(path, content, mime_type=mime, checksum=digest)
        # Verifica post-upload: rilettura e confronto SHA-256.
        if sha256_hex(dest.get(path)) != digest:
            raise RuntimeError("verifica SHA-256 post-upload fallita")
        with lock:
            report.copied.append(path)
        return "copied"
    except Exception as exc:  # noqa: BLE001
        with lock:
            report.failed.append({"path": path, "error": f"{type(exc).__name__}: {exc}"})
        return "failed"


def _load_state(state_file: Optional[str]) -> set[str]:
    if not state_file or not os.path.exists(state_file):
        return set()
    with open(state_file, encoding="utf-8") as fh:
        return {line.strip() for line in fh if line.strip()}


def run_migration(
    entries: Iterable[FileEntry],
    source: Optional[SourceReader],
    dest: Optional[S3ObjectStore],
    *,
    execute: bool,
    concurrency: int = 4,
    state_file: Optional[str] = None,
) -> Report:
    """Core riusabile dai test: nessun accesso a DB/rete oltre a source e dest iniettati."""
    unique: dict[str, FileEntry] = {}
    for entry in entries:
        if entry.path and entry.path not in unique:
            unique[entry.path] = entry
    report = Report(dry_run=not execute, total=len(unique))
    done = _load_state(state_file)
    pending = [e for p, e in unique.items() if p not in done]
    report.skipped.extend(p for p in unique if p in done)
    lock = threading.Lock()

    if not execute:
        for entry in pending:
            if dest is not None and _dest_matches(dest.head(entry.path), entry.size_bytes, entry.sha256):
                report.skipped.append(entry.path)
            else:
                report.would_copy.append(entry.path)
        return report

    assert source is not None and dest is not None
    state_fh = open(state_file, "a", encoding="utf-8") if state_file else None
    try:
        def work(entry: FileEntry) -> None:
            outcome = migrate_one(entry, source, dest, report, lock)
            if state_fh is not None and outcome in {"copied", "skipped"}:
                with lock:
                    state_fh.write(entry.path + "\n")
                    state_fh.flush()

        with ThreadPoolExecutor(max_workers=max(1, concurrency)) as pool:
            list(pool.map(work, pending))
    finally:
        if state_fh is not None:
            state_fh.close()
    return report


# --- Sorgente lista file: DB -------------------------------------------------

async def _query_entries_from_db(providers: list[str]) -> list[FileEntry]:
    from sqlalchemy import select

    from app.core.database import AsyncSessionLocal
    from app.models.document import Document
    from app.models.document_version import DocumentVersion

    entries: list[FileEntry] = []
    async with AsyncSessionLocal() as session:
        docs = await session.execute(
            select(Document.storage_path, Document.size_bytes, Document.checksum_sha256).where(
                Document.status != "deleted",
                Document.storage_provider.in_(providers),
            )
        )
        entries += [FileEntry(p, s, c) for p, s, c in docs.all() if p]
        versions = await session.execute(
            select(DocumentVersion.storage_path, DocumentVersion.size_bytes, DocumentVersion.checksum_sha256)
            .join(Document, Document.id == DocumentVersion.document_id)
            .where(Document.status != "deleted", Document.storage_provider.in_(providers))
        )
        entries += [FileEntry(p, s, c) for p, s, c in versions.all() if p]
    return entries


def list_entries_from_db(providers: list[str]) -> list[FileEntry]:
    return asyncio.run(_query_entries_from_db(providers))


# --- CLI ----------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--source", choices=["mac_mini", "local"], help="provider sorgente (obbligatorio con --execute)")
    p.add_argument("--source-root", help="radice del vault locale (obbligatorio con --source local --execute)")
    p.add_argument("--include-provider", action="append", default=[], help="altri valori di documents.storage_provider da migrare (es. hub)")
    p.add_argument("--bucket", help="bucket di destinazione (default: VAULT_S3_BUCKET)")
    p.add_argument("--region", help="default: VAULT_S3_REGION")
    p.add_argument("--endpoint-url", help="default: VAULT_S3_ENDPOINT_URL (endpoint locale o Supabase S3)")
    p.add_argument("--prefix", help="default: VAULT_S3_PREFIX")
    p.add_argument("--path-style", action="store_true", help="forza path-style (endpoint locali)")
    p.add_argument("--concurrency", type=int, default=4)
    p.add_argument("--state-file", help="file di stato per riprendere un'esecuzione interrotta")
    p.add_argument("--report", help="scrive il report JSON su file (altrimenti stdout)")
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="default: non copia nulla")
    mode.add_argument("--execute", action="store_true", help="esegue la copia")
    return p


def main(
    argv: Optional[list[str]] = None,
    *,
    list_entries: Optional[Callable[[list[str]], list[FileEntry]]] = None,
    source_factory: Optional[Callable[[argparse.Namespace], SourceReader]] = None,
    dest_factory: Optional[Callable[[argparse.Namespace], S3ObjectStore]] = None,
) -> int:
    args = build_parser().parse_args(argv)
    execute = bool(args.execute)

    from app.core.config import settings

    bucket = args.bucket or settings.VAULT_S3_BUCKET
    errors = []
    if execute:
        if not args.source:
            errors.append("--source e' obbligatorio con --execute")
        if args.source == "local" and not args.source_root:
            errors.append("--source-root e' obbligatorio con --source local --execute")
        if args.source == "mac_mini" and not (settings.MAC_MINI_STORAGE_URL and settings.MAC_MINI_STORAGE_TOKEN):
            errors.append("MAC_MINI_STORAGE_URL/MAC_MINI_STORAGE_TOKEN non configurati")
        if not bucket:
            errors.append("bucket di destinazione mancante (--bucket o VAULT_S3_BUCKET)")
    if errors:
        for e in errors:
            print(f"ERRORE: {e}", file=sys.stderr)
        return 2

    def default_source(a: argparse.Namespace) -> SourceReader:
        if a.source == "local":
            return LocalSource(a.source_root)
        return MacMiniSource(settings.MAC_MINI_STORAGE_URL, settings.MAC_MINI_STORAGE_TOKEN)

    def default_dest(a: argparse.Namespace) -> S3ObjectStore:
        return S3ObjectStore(
            bucket=bucket,
            region=a.region or settings.VAULT_S3_REGION,
            endpoint_url=a.endpoint_url or settings.VAULT_S3_ENDPOINT_URL,
            prefix=a.prefix if a.prefix is not None else settings.VAULT_S3_PREFIX,
            force_path_style=a.path_style or settings.VAULT_S3_FORCE_PATH_STYLE,
        )

    providers = [p for p in [args.source, *args.include_provider] if p]
    entries = (list_entries or list_entries_from_db)(providers or ["mac_mini", "local"])
    source = (source_factory or default_source)(args) if execute else None
    dest = (dest_factory or default_dest)(args) if (execute or bucket) else None

    report = run_migration(
        entries, source, dest, execute=execute, concurrency=args.concurrency, state_file=args.state_file
    )
    payload = json.dumps(report.to_dict(), indent=2, ensure_ascii=False)
    if args.report:
        Path(args.report).write_text(payload, encoding="utf-8")
        print(json.dumps(report.to_dict()["counts"]))
    else:
        print(payload)
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
