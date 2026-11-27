import base64

from app.services.gmail_sync_service import parse_gmail_message


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
