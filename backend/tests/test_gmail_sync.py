import asyncio
import base64
import json

from app.domain.claim_mail_match import ClaimMailKey, match_mail_to_claims
from app.models.attachment import Attachment
from app.models.email import Email, Mailbox
from app.services.gmail_sync_service import (
    ATTACHMENTS_ON_GMAIL_NOTICE,
    _import_message,
    _recover_missing_attachments,
    _store_attachments,
    attachment_notice_fields,
    parse_gmail_message,
)
from app.services.supabase_storage_service import SupabaseBlob


def _encoded(value: str) -> str:
    return base64.urlsafe_b64encode(value.encode()).decode().rstrip("=")


def test_parse_gmail_message_keeps_chiari_reference():
    message = {
        "id": "abc",
        "threadId": "thr",
        "internalDate": "1732665600000",
        "labelIds": ["INBOX", "UNREAD"],
        "payload": {
            "mimeType": "multipart/alternative",
            "headers": [
                {"name": "From", "value": "Studio <studio@vittoria.it>"},
                {"name": "To", "value": "Massimo <massimo.pernozzoli@chiarisrl.it>"},
                {"name": "Subject", "value": "Incarico 26-602322"},
            ],
            "parts": [
                {
                    "mimeType": "text/plain",
                    "body": {"data": _encoded("Testo pratica 26-602322")},
                }
            ],
        },
    }
    parsed = parse_gmail_message(message)
    assert parsed["references"] == ["26-602322"]
    assert parsed["from_address"] == "studio@vittoria.it"
    assert parsed["to_addresses"] == ["massimo.pernozzoli@chiarisrl.it"]
    assert parsed["mailbox"] == "INBOX"
    assert parsed["is_read"] is False
    assert "26-602322" in parsed["body_text"]


def test_parse_sent_message_is_outgoing():
    message = {
        "id": "sent-1",
        "threadId": "thr",
        "internalDate": "1732665600000",
        "labelIds": ["SENT"],
        "payload": {
            "mimeType": "text/plain",
            "headers": [
                {"name": "From", "value": "massimo.pernozzoli@chiarisrl.it"},
                {"name": "To", "value": "cliente@example.com"},
                {"name": "Subject", "value": "Riscontro"},
            ],
            "body": {"data": _encoded("Riscontro inviato")},
        },
    }
    parsed = parse_gmail_message(message)
    assert parsed["mailbox"] == "SENT"
    assert parsed["is_read"] is True
    assert parsed["body_text"] == "Riscontro inviato"


def _claims() -> list[ClaimMailKey]:
    return [
        ClaimMailKey("a", "26-602322", "1.825.26.00637", "Condominio Galleria"),
        ClaimMailKey("b", "26-604581", "1.159.26.01145", "Calabrese Anna"),
        ClaimMailKey("c", "26-601988", "1.F53.26.01235", "Condominio Aurora"),
        ClaimMailKey("d", "26-600001", "1.026.26.00310", "Zannelli Maria Grazia"),
        ClaimMailKey("e", "26-600002", "1.026.26.00311", "Zannelli Maria Grazia"),
    ]


def test_mail_match_prefers_internal_reference():
    found = match_mail_to_claims(
        _claims(),
        "Invio Atto - rif 26-602322",
        "Numero 1.159.26.01145 per Calabrese Anna",
    )
    assert found.source == "riferimento"
    assert [item.id for item in found.claims] == ["a"]
    assert found.sinistro_ref == "26-602322"


def test_mail_match_uses_company_number_when_reference_is_missing():
    found = match_mail_to_claims(_claims(), "Sollecito", "Sinistro 825.26.00637")
    assert found.source == "numero_compagnia"
    assert [item.id for item in found.claims] == ["a"]

    letter = match_mail_to_claims(_claims(), "1.F53.26.01235", "")
    assert [item.id for item in letter.claims] == ["c"]


def test_mail_match_uses_insured_name_last():
    found = match_mail_to_claims(_claims(), "Documenti", "Per il condominio Galleria, in allegato.")
    assert found.source == "nome_assicurato"
    assert [item.id for item in found.claims] == ["a"]


def test_mail_match_keeps_the_more_specific_name():
    found = match_mail_to_claims(
        _claims(),
        "Condominio Galleria e Condominio Aurora",
        "",
    )
    assert found.source == "nome_assicurato"
    assert [item.id for item in found.claims] == ["a"]


def test_mail_match_skips_two_different_names_of_the_same_length():
    claims = [
        ClaimMailKey("a", "26-602322", "1.825.26.00637", "Rossi Mario"),
        ClaimMailKey("b", "26-604581", "1.159.26.01145", "Verdi Lucia"),
    ]
    found = match_mail_to_claims(claims, "Rossi Mario e Verdi Lucia", "")
    assert found.source is None
    assert found.claims == ()


def test_pubsub_push_decodes_mailbox_and_history():
    from app.services.gmail_sync_service import decode_pubsub_push

    raw = base64.urlsafe_b64encode(
        b'{"emailAddress":"Massimo.Pernozzoli@chiarisrl.it","historyId":"42"}'
    ).decode().rstrip("=")
    note = decode_pubsub_push({"message": {"data": raw, "messageId": "m1"}})
    assert note == {
        "email": "massimo.pernozzoli@chiarisrl.it",
        "history_id": "42",
        "message_id": "m1",
    }


def test_watch_renews_when_missing_or_inside_a_day():
    from datetime import datetime, timedelta, timezone

    from app.services.gmail_sync_service import watch_needs_renewal

    now = datetime(2026, 11, 27, tzinfo=timezone.utc)
    assert watch_needs_renewal(None, now) is True
    assert watch_needs_renewal(now + timedelta(hours=20), now) is True
    assert watch_needs_renewal(now + timedelta(days=3), now) is False


def test_signature_is_appended_once():
    from app.services.gmail_sync_service import append_gmail_signature

    signed = append_gmail_signature("Testo", "<b>Studio Chiari</b>", False)
    assert signed == "Testo\n\nStudio Chiari"
    assert append_gmail_signature(signed, "<b>Studio Chiari</b>", False) == signed
    html = append_gmail_signature("<p>Testo</p>", "<b>Studio Chiari</b>", True)
    assert html.endswith("<b>Studio Chiari</b>")
    assert append_gmail_signature(html, "<b>Studio Chiari</b>", True) == html


class _ExistingLookup:
    def scalar_one_or_none(self):
        return None


class _SyncDb:
    def __init__(self):
        self.added = []

    async def execute(self, _query):
        return _ExistingLookup()

    def add(self, obj):
        self.added.append(obj)

    async def flush(self):
        return None


def _mailbox() -> Mailbox:
    return Mailbox(tenant_id="tenant", email_address="casella@example.com")


def _message_with_attachment() -> dict:
    return {
        "id": "g1",
        "threadId": "thr",
        "internalDate": "1732665600000",
        "labelIds": ["INBOX"],
        "payload": {
            "mimeType": "multipart/mixed",
            "headers": [
                {"name": "From", "value": "studio@example.com"},
                {"name": "To", "value": "casella@example.com"},
                {"name": "Subject", "value": "Documenti"},
            ],
            "parts": [
                {"mimeType": "text/plain", "body": {"data": _encoded("Testo")}},
                {
                    "mimeType": "application/pdf",
                    "filename": "relazione.pdf",
                    "body": {"attachmentId": "att-1", "size": 4},
                },
            ],
        },
    }


def test_hub_hides_attachment_notice_until_download_fails():
    assert attachment_notice_fields({"gmailId": "g1"}) == {
        "attachmentsOnGmail": False,
        "attachmentsNotice": None,
        "gmailWebUrl": None,
    }


def test_attachment_download_retries_then_stores(monkeypatch):
    calls = {"n": 0}
    pauses = []

    async def fake_gmail(_client, _access, _method, path, **_kwargs):
        if "/attachments/" not in path:
            return {}
        calls["n"] += 1
        if calls["n"] < 3:
            raise RuntimeError("Gmail timeout")
        return {"data": _encoded("pdf")}

    async def fake_upload(**kwargs):
        content = kwargs["content"]
        return SupabaseBlob(
            bucket="perx-attachments",
            storage_path=kwargs["object_path"],
            size_bytes=len(content),
            checksum_sha256="abc",
            mime_type=kwargs.get("mime_type"),
        )

    async def no_pause(delay):
        pauses.append(delay)

    monkeypatch.setattr("app.services.gmail_sync_service._gmail", fake_gmail)
    monkeypatch.setattr("app.services.gmail_sync_service.SupabaseStorageService.is_configured", lambda: True)
    monkeypatch.setattr("app.services.gmail_sync_service.SupabaseStorageService.upload", fake_upload)
    monkeypatch.setattr("app.services.gmail_sync_service._pause_before_attachment_retry", no_pause)

    db = _SyncDb()
    email = Email(id="mail-1", raw_headers=json.dumps({"gmailId": "g1", "sinistroRef": "26-602322"}))
    asyncio.run(
        _store_attachments(
            db,
            None,
            _mailbox(),
            "token",
            email,
            "g1",
            [{"filename": "relazione.pdf", "mime": "application/pdf", "attachment_id": "att-1", "size": 4}],
        )
    )

    assert calls["n"] == 3
    assert pauses == [0.4, 0.8]
    stored = [item for item in db.added if isinstance(item, Attachment)]
    assert len(stored) == 1
    assert stored[0].file_name == "relazione.pdf"
    assert json.loads(email.raw_headers)["sinistroRef"] == "26-602322"
    assert "attachmentsOnGmail" not in json.loads(email.raw_headers)


def test_failed_attachment_keeps_the_mail_and_marks_gmail(monkeypatch):
    calls = {"n": 0}

    async def fake_gmail(_client, _access, _method, path, **_kwargs):
        if "/attachments/" in path:
            calls["n"] += 1
            raise RuntimeError("Gmail timeout")
        return _message_with_attachment()

    async def no_pause(_delay):
        return None

    monkeypatch.setattr("app.services.gmail_sync_service._gmail", fake_gmail)
    monkeypatch.setattr("app.services.gmail_sync_service.SupabaseStorageService.is_configured", lambda: True)
    monkeypatch.setattr("app.services.gmail_sync_service._pause_before_attachment_retry", no_pause)

    db = _SyncDb()
    imported = asyncio.run(_import_message(db, None, _mailbox(), "token", "g1", []))

    assert imported is True
    assert calls["n"] == 3
    emails = [item for item in db.added if isinstance(item, Email)]
    assert len(emails) == 1
    assert emails[0].subject == "Documenti"
    metadata = json.loads(emails[0].raw_headers)
    assert metadata["attachmentsOnGmail"] is True
    assert metadata["attachmentsNotice"] == ATTACHMENTS_ON_GMAIL_NOTICE
    assert metadata["gmailWebUrl"] == "https://mail.google.com/mail/u/0/#all/g1"
    assert metadata["failedAttachments"] == [{"filename": "relazione.pdf"}]
    assert attachment_notice_fields(metadata)["attachmentsNotice"] == ATTACHMENTS_ON_GMAIL_NOTICE
    assert not any(isinstance(item, Attachment) for item in db.added)


def test_recovery_stores_attachment_missed_on_first_import(monkeypatch):
    email = Email(
        id="mail-1",
        tenant_id="tenant",
        message_id="gmail:g1",
        provider_id="g1",
        raw_headers=json.dumps({"gmailId": "g1", "sinistroRef": "26-602322"}),
    )

    class _Emails:
        def scalars(self):
            return self

        def all(self):
            return [email]

    class _Names:
        def all(self):
            return []

    class _Db:
        def __init__(self):
            self.added = []
            self.calls = 0

        async def execute(self, _query):
            self.calls += 1
            if self.calls == 1:
                return _Emails()
            return _Names()

        def add(self, obj):
            self.added.append(obj)

    async def fake_gmail(_client, _access, _method, path, **_kwargs):
        if "/attachments/" in path:
            return {"data": _encoded("pdf")}
        return _message_with_attachment()

    async def fake_upload(**kwargs):
        content = kwargs["content"]
        return SupabaseBlob(
            bucket="perx-portal-uploads",
            storage_path=kwargs["object_path"],
            size_bytes=len(content),
            checksum_sha256="abc",
            mime_type=kwargs.get("mime_type"),
        )

    monkeypatch.setattr("app.services.gmail_sync_service._gmail", fake_gmail)
    monkeypatch.setattr("app.services.gmail_sync_service.SupabaseStorageService.is_configured", lambda: True)
    monkeypatch.setattr("app.services.gmail_sync_service.SupabaseStorageService.upload", fake_upload)

    db = _Db()
    recovered = asyncio.run(_recover_missing_attachments(db, None, _mailbox(), "token"))

    assert recovered == 1
    stored = [item for item in db.added if isinstance(item, Attachment)]
    assert len(stored) == 1
    assert stored[0].file_name == "relazione.pdf"
    metadata = json.loads(email.raw_headers)
    assert metadata["attachmentsChecked"] is True
    assert metadata["sinistroRef"] == "26-602322"
    assert "attachmentsOnGmail" not in metadata


def test_attachment_recovery_stops_after_three_fetch_failures(monkeypatch):
    email = Email(
        id="mail-1",
        tenant_id="tenant",
        message_id="gmail:g1",
        provider_id="g1",
        raw_headers=json.dumps({"gmailId": "g1"}),
    )

    class _Emails:
        def scalars(self):
            return self

        def all(self):
            return [email]

    class _Db:
        async def execute(self, _query):
            return _Emails()

        def add(self, _obj):
            return None

    async def fake_gmail(*_args, **_kwargs):
        raise RuntimeError("Gmail timeout")

    monkeypatch.setattr("app.services.gmail_sync_service._gmail", fake_gmail)
    monkeypatch.setattr("app.services.gmail_sync_service.SupabaseStorageService.is_configured", lambda: True)

    db = _Db()
    for _ in range(3):
        asyncio.run(_recover_missing_attachments(db, None, _mailbox(), "token"))

    metadata = json.loads(email.raw_headers)
    assert metadata["attachmentAttempts"] == 3
    assert metadata["attachmentsChecked"] is True
    assert metadata.get("attachmentsOnGmail") is not True


def test_same_insured_name_links_every_practice():
    found = match_mail_to_claims(_claims(), "Zannelli Maria Grazia", "")
    assert found.source == "nome_assicurato"
    assert [item.id for item in found.claims] == ["d", "e"]
