"""
Test puri per la normalizzazione dei destinatari del routing mail.
"""
from app.services.email_routing_service import _json_addresses, _normalized_addresses


def test_normalized_addresses_trims_lowercases_and_deduplicates():
    assert _normalized_addresses(
        [" Mario@Studio.IT ", "mario@studio.it", "", "Segreteria@Studio.it"]
    ) == ["mario@studio.it", "segreteria@studio.it"]


def test_json_addresses_rejects_invalid_payload():
    assert _json_addresses("not-json") == []
    assert _json_addresses('{"email": "mario@studio.it"}') == []


def test_json_addresses_ignores_non_string_values():
    assert _json_addresses('["Perito@Studio.it", null, 42]') == ["perito@studio.it"]
