"""
Resend email transport used by every backend outbound email path.
"""
from __future__ import annotations

from dataclasses import dataclass

import httpx

from app.core.config import settings
from app.models.user import User


@dataclass(frozen=True)
class ResendEmailMessage:
    from_address: str
    to: list[str]
    subject: str
    body: str
    is_html: bool = True
    cc: list[str] | None = None
    bcc: list[str] | None = None
    in_reply_to: str | None = None
    references: str | None = None
    attachments: list[dict] | None = None


@dataclass(frozen=True)
class ResendEmailResult:
    success: bool
    message_id: str | None = None
    error: str | None = None


class ResendEmailService:
    endpoint = "https://api.resend.com/emails"

    @staticmethod
    def resolve_from_address(
        *,
        account_id: str | None = None,
        user: User | None = None,
        fallback_email: str | None = None,
    ) -> str:
        candidates = [
            account_id,
            getattr(user, "professional_email", None),
            getattr(user, "email", None),
            fallback_email,
            settings.RESEND_DEFAULT_FROM_EMAIL,
        ]
        for candidate in candidates:
            if candidate and "@" in candidate:
                return candidate.strip()
        raise ValueError("Missing sender email for Resend")

    @staticmethod
    def normalize_attachments(items: list[dict] | None) -> list[dict]:
        attachments: list[dict] = []
        for item in items or []:
            filename = item.get("filename")
            content = item.get("data") or item.get("content")
            if not filename or not content:
                continue
            attachment = {
                "filename": filename,
                "content": content,
            }
            content_type = item.get("mimeType") or item.get("mime_type") or item.get("content_type")
            if content_type:
                attachment["content_type"] = content_type
            attachments.append(attachment)
        return attachments

    @classmethod
    async def send(cls, message: ResendEmailMessage) -> ResendEmailResult:
        if not settings.RESEND_API_KEY:
            return ResendEmailResult(success=False, error="RESEND_API_KEY is not configured")

        payload: dict = {
            "from": message.from_address,
            "to": message.to,
            "subject": message.subject,
        }
        if message.cc:
            payload["cc"] = message.cc
        if message.bcc:
            payload["bcc"] = message.bcc
        if message.is_html:
            payload["html"] = message.body
        else:
            payload["text"] = message.body

        headers: dict[str, str] = {}
        if message.in_reply_to:
            headers["In-Reply-To"] = message.in_reply_to
        if message.references:
            headers["References"] = message.references
        if headers:
            payload["headers"] = headers

        attachments = cls.normalize_attachments(message.attachments)
        if attachments:
            payload["attachments"] = attachments

        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=5.0)) as client:
                response = await client.post(
                    cls.endpoint,
                    json=payload,
                    headers={
                        "Authorization": f"Bearer {settings.RESEND_API_KEY}",
                        "Content-Type": "application/json",
                        "Accept": "application/json",
                    },
                )
            if response.status_code >= 400:
                return ResendEmailResult(success=False, error=response.text)
            data = response.json() if response.content else {}
            return ResendEmailResult(success=True, message_id=data.get("id"))
        except httpx.RequestError as exc:
            return ResendEmailResult(success=False, error=f"Resend unavailable: {exc}")
        except ValueError as exc:
            return ResendEmailResult(success=False, error=f"Invalid Resend response: {exc}")
