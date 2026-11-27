import base64

from app.domain.claim_mail_match import ClaimMailKey, match_mail_to_claims
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
    assert found.claims == ()


def test_same_insured_name_links_every_practice():
    found = match_mail_to_claims(_claims(), "Zannelli Maria Grazia", "")
    assert found.source == "nome_assicurato"
    assert [item.id for item in found.claims] == ["d", "e"]
