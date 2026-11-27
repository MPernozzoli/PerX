"""Sincronizzazione Gmail sul backend: storico a pagine, watch Pub/Sub e history."""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import re
import uuid
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from email.utils import parseaddr
from typing import Any

import httpx
from jose import jwt
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.domain.claim_mail_match import (
    ClaimMailKey,
    MailClaimMatch,
    match_mail_to_claims,
    plain_mail_text,
)
from app.models.attachment import Attachment
from app.models.claim import Claim
from app.models.email import Email, EmailClaimLink, EmailProcessingJob, InboundEmailEvent, Mailbox
from app.services.google_workspace_auth import open_google_tokens, seal_google_tokens
from app.services.supabase_storage_service import SupabaseStorageService

logger = logging.getLogger(__name__)


class GmailHistoryExpired(RuntimeError):
    """Lo historyId è troppo vecchio: si riparte dall'elenco."""


_GOOGLE_CERTS = "https://www.googleapis.com/oauth2/v3/certs"
_certs_cache: dict[str, Any] = {"at": None, "keys": None}


def watch_needs_renewal(expiration: datetime | None, now: datetime) -> bool:
    if expiration is None:
        return True
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    return expiration - now <= timedelta(hours=24)


def decode_pubsub_push(body: dict) -> dict[str, str]:
    message = body.get("message") if isinstance(body, dict) else None
    if not isinstance(message, dict):
        raise ValueError("message")
    payload = json.loads(_b64(message.get("data")) or "{}")
    if not isinstance(payload, dict):
        raise ValueError("payload")
    return {
        "email": str(payload.get("emailAddress") or "").strip().lower(),
        "history_id": str(payload.get("historyId") or ""),
        "message_id": str(message.get("messageId") or ""),
    }


def verify_pubsub_token(token: str, keys: list, audience: str, service_account: str) -> None:
    if not audience:
        raise ValueError("audience")
    claims = jwt.decode(
        token,
        {"keys": keys},
        algorithms=["RS256"],
        audience=audience,
        issuer="https://accounts.google.com",
    )
    if claims.get("email_verified") is not True:
        raise ValueError("email_verified")
    if service_account and claims.get("email") != service_account:
        raise ValueError("service_account")


def append_gmail_signature(body: str, signature_html: str, is_html: bool) -> str:
    signature = signature_html.strip()
    if not signature:
        return body
    if is_html:
        return body if signature in body else f"{body}<br><br>{signature}"
    plain = re.sub(r"<[^>]+>", " ", signature)
    plain = re.sub(r"\s+", " ", plain).strip()
    if not plain or plain in body:
        return body
    return f"{body}\n\n{plain}"


async def fetch_google_certs() -> list:
    now = datetime.now(timezone.utc)
    cached_at = _certs_cache.get("at")
    cached_keys = _certs_cache.get("keys")
    if cached_keys and isinstance(cached_at, datetime) and now - cached_at < timedelta(hours=6):
        return cached_keys
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.get(_GOOGLE_CERTS)
    if response.status_code >= 400:
        raise RuntimeError(f"Certificati Google non disponibili: {response.status_code}")
    keys = response.json().get("keys") or []
    _certs_cache["at"] = now
    _certs_cache["keys"] = keys
    return keys


GMAIL = "https://gmail.googleapis.com/gmail/v1/users/me"
REF_RE = re.compile(r"\b\d{2}-\d{6}\b")
MAX_ATTACHMENT_BYTES = 15_000_000


def _b64(data: str | None) -> str:
    if not data:
        return ""
    padded = data + "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii")).decode("utf-8", errors="replace")


def _b64_bytes(data: str | None) -> bytes:
    if not data:
        return b""
    padded = data + "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii"))


def _header(payload: dict, name: str) -> str:
    for item in payload.get("headers") or []:
        if str(item.get("name") or "").lower() == name.lower():
            return str(item.get("value") or "")
    return ""


def _addresses(value: str) -> list[str]:
    found: list[str] = []
    for part in value.split(","):
        _, email = parseaddr(part)
        email = email.strip().lower()
        if email:
            found.append(email)
    return found


def _walk(part: dict, texts: list[str], htmls: list[str], files: list[dict]) -> None:
    mime = part.get("mimeType") or ""
    body = part.get("body") or {}
    filename = part.get("filename") or ""
    if filename and body.get("attachmentId"):
        files.append(
            {
                "filename": filename,
                "mime": mime or "application/octet-stream",
                "attachment_id": body["attachmentId"],
                "size": int(body.get("size") or 0),
            }
        )
    elif body.get("data") and mime == "text/plain":
        texts.append(_b64(body.get("data")))
    elif body.get("data") and mime == "text/html":
        htmls.append(_b64(body.get("data")))
    for child in part.get("parts") or []:
        if isinstance(child, dict):
            _walk(child, texts, htmls, files)


def parse_gmail_message(message: dict) -> dict[str, Any]:
    payload = message.get("payload") or {}
    texts: list[str] = []
    htmls: list[str] = []
    files: list[dict] = []
    _walk(payload, texts, htmls, files)
    labels = set(message.get("labelIds") or [])
    internal = int(message.get("internalDate") or 0)
    received = datetime.fromtimestamp(internal / 1000, tz=timezone.utc) if internal else datetime.now(timezone.utc)
    mailbox = "SENT" if "SENT" in labels else "INBOX"
    return {
        "gmail_id": message.get("id") or "",
        "thread_id": message.get("threadId"),
        "from_address": (_addresses(_header(payload, "From")) or ["sconosciuto@gmail.com"])[0],
        "to_addresses": _addresses(_header(payload, "To")),
        "cc_addresses": _addresses(_header(payload, "Cc")),
        "subject": _header(payload, "Subject"),
        "body_text": "\n".join(part for part in texts if part).strip(),
        "body_html": "\n".join(part for part in htmls if part).strip(),
        "received_at": received,
        "mailbox": mailbox,
        "is_read": "UNREAD" not in labels,
        "attachments": files,
        "references": sorted(set(REF_RE.findall(f"{_header(payload, 'Subject')}\n{''.join(texts)}"))),
    }


class GmailSyncService:
    @staticmethod
    async def sync_mailbox_for(tenant_id: str, email: str) -> dict[str, int]:
        async with AsyncSessionLocal() as db:
            result = await db.execute(
            select(Mailbox).where(
                Mailbox.tenant_id == tenant_id,
                Mailbox.provider == "gmail",
                Mailbox.email_address == email.lower(),
                Mailbox.active == "true",
            )
            )
            mailbox = result.scalar_one_or_none()
            if mailbox is None:
                return {"imported": 0}
            imported = await GmailSyncService.sync_mailbox(db, mailbox)
            await db.commit()
            return {"imported": imported}

    @staticmethod
    async def sync_all() -> int:
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(Mailbox).where(Mailbox.provider == "gmail", Mailbox.active == "true")
            )
            mailboxes = list(result.scalars().all())
            total = 0
            for mailbox in mailboxes:
                try:
                    total += await GmailSyncService.sync_mailbox(db, mailbox)
                    await db.commit()
                except Exception:
                    await db.rollback()
                    logger.exception("Sincronizzazione Gmail fallita per %s", mailbox.email_address)
            return total

    @staticmethod
    async def sync_mailbox(db: AsyncSession, mailbox: Mailbox) -> int:
        access = await _access_token(db, mailbox)
        settings_json = dict(mailbox.settings_json or {})
        backfill = dict(settings_json.get("backfill") or {})
        imported = 0
        claim_keys = await _claim_keys(db, mailbox.tenant_id)
        await _relink_unmatched(db, mailbox.tenant_id, claim_keys)
        await db.commit()
        async with httpx.AsyncClient(timeout=60) as client:
            if not mailbox.gmail_history_id:
                profile = await _gmail(client, access, "GET", "/profile")
                mailbox.gmail_history_id = str(profile.get("historyId") or "")
            try:
                await _ensure_watch(client, access, mailbox)
            except Exception:
                logger.exception("Watch Gmail non rinnovato per %s", mailbox.email_address)
            if not settings_json.get("backfill_done"):
                for label in ("INBOX", "SENT"):
                    for _ in range(5):
                        if backfill.get(label) == "done":
                            break
                        imported += await _import_page(db, client, mailbox, access, label, backfill, claim_keys)
                        settings_json["backfill"] = backfill
                        settings_json["backfill_done"] = all(
                            backfill.get(item) == "done" for item in ("INBOX", "SENT")
                        )
                        mailbox.settings_json = settings_json
                        await db.commit()
            try:
                imported += await _import_history(db, client, mailbox, access, claim_keys)
            except GmailHistoryExpired:
                mailbox.gmail_history_id = None
                settings_json["backfill_done"] = False
                settings_json["backfill"] = {}
        settings_json["last_sync_at"] = datetime.now(timezone.utc).isoformat()
        settings_json.pop("last_error", None)
        mailbox.settings_json = settings_json
        return imported

    @staticmethod
    async def mailbox_for_user(db: AsyncSession, tenant_id: str, email: str) -> Mailbox | None:
        result = await db.execute(
            select(Mailbox).where(
                Mailbox.tenant_id == tenant_id,
                Mailbox.provider == "gmail",
                Mailbox.email_address == email.lower(),
                Mailbox.active == "true",
            )
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def send_message(
        db: AsyncSession,
        mailbox: Mailbox,
        *,
        to: list[str],
        cc: list[str] | None,
        bcc: list[str] | None,
        subject: str,
        body: str,
        is_html: bool,
        thread_id: str | None = None,
    ) -> str:
        access = await _access_token(db, mailbox)
        signature = ""
        async with httpx.AsyncClient(timeout=60) as client:
            try:
                signature = await _send_as_signature(client, access, mailbox)
            except Exception:
                logger.exception("Firma Gmail non letta per %s", mailbox.email_address)
            signed = append_gmail_signature(body, signature, is_html)
            message = EmailMessage()
            message["From"] = mailbox.email_address
            message["To"] = ", ".join(to)
            if cc:
                message["Cc"] = ", ".join(cc)
            if bcc:
                message["Bcc"] = ", ".join(bcc)
            message["Subject"] = subject
            if is_html:
                message.set_content(" ")
                message.add_alternative(signed, subtype="html")
            else:
                message.set_content(signed)
            raw = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii").rstrip("=")
            payload: dict[str, Any] = {"raw": raw}
            if thread_id and re.fullmatch(r"[0-9a-fA-F]{10,32}", thread_id):
                payload["threadId"] = thread_id
            sent = await _gmail(client, access, "POST", "/messages/send", json=payload)
        gmail_id = sent.get("id") or ""
        if not gmail_id:
            raise RuntimeError("Gmail non ha confermato l'invio")
        return gmail_id

    @staticmethod
    async def accept_push(db: AsyncSession, note: dict[str, str]) -> str:
        message_id = note["message_id"] or f"gmail-history:{note['email']}:{note['history_id']}"
        existing = await db.execute(
            select(InboundEmailEvent).where(InboundEmailEvent.provider_event_id == message_id)
        )
        event = existing.scalar_one_or_none()
        if event is not None and event.status == "processed":
            return "duplicate"
        result = await db.execute(
            select(Mailbox).where(
                Mailbox.provider == "gmail",
                func.lower(Mailbox.email_address) == note["email"],
                Mailbox.active == "true",
            )
        )
        mailboxes = list(result.scalars().all())
        if not mailboxes:
            return "ignored"
        mailbox = mailboxes[0]
        if event is None:
            event = InboundEmailEvent(
                id=str(uuid.uuid4()),
                tenant_id=mailbox.tenant_id,
                mailbox_id=mailbox.id,
                provider="gmail",
                provider_event_id=message_id,
                from_address=note["email"],
                to_addresses=[],
                subject="gmail-push",
                received_at=datetime.now(timezone.utc),
                status="queued",
                raw_payload={"emailAddress": note["email"], "historyId": note["history_id"]},
            )
            db.add(event)
            db.add(
                EmailProcessingJob(
                    id=str(uuid.uuid4()),
                    tenant_id=mailbox.tenant_id,
                    inbound_event_id=event.id,
                    status="pending",
                    input_json={"emailAddress": note["email"], "historyId": note["history_id"]},
                )
            )
            await db.flush()
        imported = 0
        for item in mailboxes:
            imported += await GmailSyncService.sync_mailbox(db, item)
        event.status = "processed"
        job_row = await db.execute(
            select(EmailProcessingJob).where(EmailProcessingJob.inbound_event_id == event.id)
        )
        job = job_row.scalar_one_or_none()
        if job is not None:
            job.status = "completed"
            job.completed_at = datetime.now(timezone.utc)
            job.result_json = {"imported": imported}
        await db.commit()
        try:
            from app.api.v1.routes_realtime import sse_manager

            await sse_manager.broadcast(mailbox.tenant_id, "mail_updated", {"imported": imported})
        except Exception:
            logger.exception("Segnale posta non inviato")
        return "ok"


async def _access_token(db: AsyncSession, mailbox: Mailbox) -> str:
    sealed = mailbox.oauth_token_ref or ""
    tokens = open_google_tokens(sealed) if sealed else {"access_token": "", "refresh_token": ""}
    access = tokens.get("access_token") or ""
    refresh = tokens.get("refresh_token") or ""
    if access and not refresh:
        return access
    if not refresh:
        raise RuntimeError("Manca il token Gmail della casella. Esci e accedi di nuovo con Google.")
    if not settings.GOOGLE_OAUTH_CLIENT_ID or not settings.GOOGLE_OAUTH_CLIENT_SECRET:
        if access:
            return access
        raise RuntimeError("Sul server mancano GOOGLE_OAUTH_CLIENT_ID e GOOGLE_OAUTH_CLIENT_SECRET.")
    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.post(
            "https://oauth2.googleapis.com/token",
            data={
                "client_id": settings.GOOGLE_OAUTH_CLIENT_ID,
                "client_secret": settings.GOOGLE_OAUTH_CLIENT_SECRET,
                "refresh_token": refresh,
                "grant_type": "refresh_token",
            },
        )
    if response.status_code >= 400:
        raise RuntimeError(f"Rinnovo token Gmail rifiutato: {response.status_code}")
    payload = response.json()
    access = payload.get("access_token") or ""
    refresh = payload.get("refresh_token") or refresh
    if not access:
        raise RuntimeError("Google non ha restituito un access token.")
    mailbox.oauth_token_ref = seal_google_tokens(refresh_token=refresh, access_token=access)
    await db.flush()
    return access


async def _gmail(client: httpx.AsyncClient, access: str, method: str, path: str, **kwargs) -> dict:
    response = await client.request(
        method,
        f"{GMAIL}{path}",
        headers={"Authorization": f"Bearer {access}"},
        **kwargs,
    )
    if response.status_code >= 400:
        raise RuntimeError(f"Gmail {path} ha risposto {response.status_code}")
    return response.json() if response.content else {}


async def _ensure_watch(client: httpx.AsyncClient, access: str, mailbox: Mailbox) -> None:
    topic = settings.GMAIL_PUBSUB_TOPIC.strip()
    if not topic or not watch_needs_renewal(mailbox.gmail_watch_expiration, datetime.now(timezone.utc)):
        return
    payload = await _gmail(
        client,
        access,
        "POST",
        "/watch",
        json={
            "topicName": topic,
            "labelIds": ["INBOX", "SENT"],
            "labelFilterBehavior": "include",
        },
    )
    if payload.get("historyId") and not mailbox.gmail_history_id:
        mailbox.gmail_history_id = str(payload["historyId"])
    expiration = payload.get("expiration")
    if expiration:
        mailbox.gmail_watch_expiration = datetime.fromtimestamp(int(expiration) / 1000, tz=timezone.utc)


async def _send_as_signature(client: httpx.AsyncClient, access: str, mailbox: Mailbox) -> str:
    settings_json = dict(mailbox.settings_json or {})
    cached = settings_json.get("send_as_signature")
    fetched = settings_json.get("send_as_signature_at")
    if isinstance(cached, str) and isinstance(fetched, str):
        try:
            when = datetime.fromisoformat(fetched)
        except ValueError:
            when = None
        if when is not None:
            if when.tzinfo is None:
                when = when.replace(tzinfo=timezone.utc)
            if datetime.now(timezone.utc) - when < timedelta(hours=12):
                return cached
    listing = await _gmail(client, access, "GET", "/settings/sendAs")
    signature = ""
    address = mailbox.email_address.lower()
    for item in listing.get("sendAs") or []:
        if not isinstance(item, dict):
            continue
        if str(item.get("sendAsEmail") or "").lower() == address:
            signature = str(item.get("signature") or "")
            break
        if item.get("isPrimary") and not signature:
            signature = str(item.get("signature") or "")
    settings_json["send_as_signature"] = signature
    settings_json["send_as_signature_at"] = datetime.now(timezone.utc).isoformat()
    mailbox.settings_json = settings_json
    return signature


async def _import_page(
    db: AsyncSession,
    client: httpx.AsyncClient,
    mailbox: Mailbox,
    access: str,
    label: str,
    backfill: dict,
    claim_keys: list[ClaimMailKey],
) -> int:
    params: dict[str, Any] = {"labelIds": label, "maxResults": settings.GMAIL_SYNC_PAGE_SIZE}
    page = backfill.get(label)
    if isinstance(page, str) and page not in {"", "done"}:
        params["pageToken"] = page
    listing = await _gmail(client, access, "GET", "/messages", params=params)
    imported = 0
    for item in listing.get("messages") or []:
        if await _import_message(db, client, mailbox, access, item.get("id") or "", claim_keys):
            imported += 1
    backfill[label] = listing.get("nextPageToken") or "done"
    return imported


async def _import_history(
    db: AsyncSession,
    client: httpx.AsyncClient,
    mailbox: Mailbox,
    access: str,
    claim_keys: list[ClaimMailKey],
) -> int:
    try:
        history = await _gmail(
            client,
            access,
            "GET",
            "/history",
            params={"startHistoryId": mailbox.gmail_history_id, "historyTypes": "messageAdded", "maxResults": 100},
        )
    except RuntimeError as exc:
        if "404" in str(exc):
            raise GmailHistoryExpired from exc
        raise
    imported = 0
    for item in history.get("history") or []:
        for added in item.get("messagesAdded") or []:
            message = (added.get("message") or {}).get("id")
            if message and await _import_message(db, client, mailbox, access, message, claim_keys):
                imported += 1
    if history.get("historyId"):
        mailbox.gmail_history_id = str(history["historyId"])
    return imported


async def _import_message(
    db: AsyncSession,
    client: httpx.AsyncClient,
    mailbox: Mailbox,
    access: str,
    gmail_id: str,
    claim_keys: list[ClaimMailKey],
) -> bool:
    if not gmail_id:
        return False
    message_id = f"gmail:{gmail_id}"
    existing = (
        await db.execute(select(Email).where(Email.message_id == message_id))
    ).scalar_one_or_none()
    if existing is not None:
        await _ensure_claim_link(db, existing, claim_keys)
        return False
    raw = await _gmail(client, access, "GET", f"/messages/{gmail_id}", params={"format": "full"})
    parsed = parse_gmail_message(raw)
    if not parsed["gmail_id"]:
        return False
    found = match_mail_to_claims(
        claim_keys,
        parsed["subject"],
        plain_mail_text(parsed["body_text"], parsed["body_html"]),
    )
    metadata = {
        "sinistroRef": found.sinistro_ref,
        "match": found.source,
        "direction": "out" if parsed["mailbox"] == "SENT" else "in",
        "isRead": parsed["is_read"],
        "gmailId": gmail_id,
    }
    email = Email(
        id=str(uuid.uuid4()),
        tenant_id=mailbox.tenant_id,
        message_id=message_id,
        thread_id=parsed["thread_id"],
        from_address=parsed["from_address"],
        to_addresses=json.dumps(parsed["to_addresses"]),
        cc_addresses=json.dumps(parsed["cc_addresses"]),
        subject=parsed["subject"],
        body_text=parsed["body_text"] or None,
        body_html=parsed["body_html"] or None,
        received_at=parsed["received_at"],
        status="ingested",
        raw_headers=json.dumps(metadata),
        mailbox_id=parsed["mailbox"],
        provider_id=gmail_id,
    )
    db.add(email)
    await db.flush()
    _add_claim_links(db, mailbox.tenant_id, email.id, found)
    await _store_attachments(db, client, mailbox, access, email, gmail_id, parsed["attachments"])
    return True


async def _claim_keys(db: AsyncSession, tenant_id: str) -> list[ClaimMailKey]:
    result = await db.execute(
        select(Claim.id, Claim.external_ref, Claim.numero_sinistro, Claim.nome_assicurato).where(
            Claim.tenant_id == tenant_id
        )
    )
    return [
        ClaimMailKey(
            id=row.id,
            external_ref=row.external_ref,
            numero_sinistro=row.numero_sinistro,
            nome_assicurato=row.nome_assicurato,
        )
        for row in result.all()
    ]


async def link_email_to_claims(
    db: AsyncSession,
    tenant_id: str,
    email: Email,
    subject: str,
    body: str,
) -> MailClaimMatch:
    found = match_mail_to_claims(
        await _claim_keys(db, tenant_id),
        subject,
        plain_mail_text(None, body),
    )
    _add_claim_links(db, tenant_id, email.id, found)
    return found


async def _ensure_claim_link(db: AsyncSession, email: Email, claim_keys: list[ClaimMailKey]) -> None:
    existing = await db.execute(select(EmailClaimLink.id).where(EmailClaimLink.email_id == email.id).limit(1))
    if existing.first() is not None:
        return
    found = match_mail_to_claims(
        claim_keys,
        email.subject or "",
        plain_mail_text(email.body_text, email.body_html),
    )
    try:
        metadata = json.loads(email.raw_headers or "{}")
    except json.JSONDecodeError:
        metadata = {}
    if not isinstance(metadata, dict):
        metadata = {}
    metadata["sinistroRef"] = found.sinistro_ref
    metadata["match"] = found.source or "nessuno"
    email.raw_headers = json.dumps(metadata)
    if found.claims:
        _add_claim_links(db, email.tenant_id, email.id, found)


async def _relink_unmatched(db: AsyncSession, tenant_id: str, claim_keys: list[ClaimMailKey]) -> int:
    result = await db.execute(
        select(Email)
        .where(
            Email.tenant_id == tenant_id,
            Email.message_id.like("gmail:%"),
            ~Email.id.in_(select(EmailClaimLink.email_id)),
            Email.raw_headers.is_(None) | ~Email.raw_headers.contains('"match"'),
        )
        .order_by(Email.received_at.desc())
        .limit(200)
    )
    rows = list(result.scalars().all())
    for email in rows:
        await _ensure_claim_link(db, email, claim_keys)
    return len(rows)


def _add_claim_links(db: AsyncSession, tenant_id: str, email_id: str, found: MailClaimMatch) -> None:
    for claim in found.claims:
        db.add(
            EmailClaimLink(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                email_id=email_id,
                claim_id=claim.id,
                link_type="primary",
                created_by="gmail-sync",
            )
        )


async def _store_attachments(
    db: AsyncSession,
    client: httpx.AsyncClient,
    mailbox: Mailbox,
    access: str,
    email: Email,
    gmail_id: str,
    files: list[dict],
) -> None:
    if not files or not SupabaseStorageService.is_configured():
        return
    for item in files:
        if item["size"] and item["size"] > MAX_ATTACHMENT_BYTES:
            continue
        payload = await _gmail(
            client,
            access,
            "GET",
            f"/messages/{gmail_id}/attachments/{item['attachment_id']}",
        )
        content = _b64_bytes(payload.get("data"))
        if not content or len(content) > MAX_ATTACHMENT_BYTES:
            continue
        safe_name = os.path.basename(item["filename"]) or "allegato"
        safe_name = re.sub(r"[^A-Za-z0-9._-]+", "_", safe_name).strip("._") or "allegato"
        path = f"gmail/{mailbox.tenant_id}/{gmail_id}/{uuid.uuid4().hex}-{safe_name}"
        try:
            blob = await SupabaseStorageService.upload(
                object_path=path,
                content=content,
                mime_type=item["mime"],
            )
        except Exception:
            logger.exception(
                "Allegato Gmail non salvato su Storage: mailbox=%s message=%s file=%s",
                mailbox.email_address,
                gmail_id,
                safe_name,
            )
            continue
        db.add(
            Attachment(
                id=str(uuid.uuid4()),
                tenant_id=mailbox.tenant_id,
                email_id=email.id,
                file_name=item["filename"],
                mime_type=item["mime"],
                size_bytes=blob.size_bytes,
                storage_bucket=blob.bucket,
                storage_path=blob.storage_path,
                checksum=blob.checksum_sha256,
            )
        )


class GmailSyncRuntime:
    _task: asyncio.Task | None = None
    _stop: asyncio.Event | None = None

    @classmethod
    async def start(cls) -> None:
        if not settings.GMAIL_SYNC_ENABLED or cls._task is not None:
            return
        cls._stop = asyncio.Event()
        cls._task = asyncio.create_task(cls._runner(), name="perx-gmail-sync")

    @classmethod
    async def stop(cls) -> None:
        if cls._stop is not None:
            cls._stop.set()
        if cls._task is not None:
            try:
                await cls._task
            finally:
                cls._task = None
                cls._stop = None

    @classmethod
    async def _runner(cls) -> None:
        assert cls._stop is not None
        while not cls._stop.is_set():
            try:
                await GmailSyncService.sync_all()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Ciclo Gmail fallito")
            try:
                await asyncio.wait_for(cls._stop.wait(), timeout=max(30, settings.GMAIL_SYNC_POLL_SECONDS))
            except asyncio.TimeoutError:
                continue
