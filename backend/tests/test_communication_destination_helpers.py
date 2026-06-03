import pytest

from app.models.claim import Claim
from app.schemas.communication import CommunicationDestinationType, CommunicationNotificationActionType, CommunicationTransport
from app.services.communication_contact_resolver import CommunicationContactResolver
from app.services.communication_destination_resolver import EXTENSION_RE
from app.services.communication_extension_service import CommunicationExtensionService


def test_three_digit_extension_pattern():
    assert EXTENSION_RE.match("101")
    assert not EXTENSION_RE.match("1001")
    assert not EXTENSION_RE.match("+39101")


def test_extension_validation_requires_three_digits():
    CommunicationExtensionService._validate_extension("999")

    with pytest.raises(ValueError):
        CommunicationExtensionService._validate_extension("99")

    with pytest.raises(ValueError):
        CommunicationExtensionService._validate_extension("abc")


def test_destination_transport_contract_values():
    assert CommunicationDestinationType.external_phone.value == "external_phone"
    assert CommunicationDestinationType.internal_extension.value == "internal_extension"
    assert CommunicationTransport.telecom_provider.value == "telecom_provider"
    assert CommunicationTransport.livekit.value == "livekit"
    assert CommunicationTransport.routing_engine.value == "routing_engine"


def test_notification_action_contract_values():
    assert CommunicationNotificationActionType.answer.value == "answer"
    assert CommunicationNotificationActionType.answer_and_open_claim.value == "answer_and_open_claim"
    assert CommunicationNotificationActionType.open_claim_only.value == "open_claim_only"
    assert CommunicationNotificationActionType.send_to_voicemail_ai_triage.value == "send_to_voicemail_ai_triage"


def test_contact_resolver_prefers_matching_claim_phone_role():
    claim = Claim(
        id="claim-1",
        tenant_id="tenant-1",
        stato_corrente="SV012",
        nome_assicurato="Mario Rossi",
        telefono_assicurato="+39 333 1234567",
        agenzia="Agenzia Milano",
        telefono_agenzia="02 555010",
    )

    match = CommunicationContactResolver()._matched_claim_phone(claim, "02555010")

    assert match.role == "agency"
    assert match.display_name == "Agenzia Milano"
