"""
Telecom provider adapter contract.

Provider-specific code belongs here, not in routes or routing logic.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol


@dataclass(frozen=True)
class NormalizedProviderEvent:
    provider: str
    event_type: str
    provider_event_id: str | None
    provider_call_id: str | None
    from_value: str | None
    to_value: str | None
    payload: dict[str, Any]


class TelecomProviderAdapter(Protocol):
    provider_name: str

    def validate_webhook_signature(self, headers: dict[str, str], payload: dict[str, Any]) -> bool: ...
    def handle_inbound_webhook(self, payload: dict[str, Any]) -> NormalizedProviderEvent: ...
    async def create_outbound_call(self, *, to_value: str, from_value: str | None, metadata: dict[str, Any]) -> dict[str, Any]: ...
    async def answer_call(self, provider_call_id: str) -> dict[str, Any]: ...
    async def bridge_call_to_livekit_room(self, provider_call_id: str, room_name: str) -> dict[str, Any]: ...
    async def transfer_call(self, provider_call_id: str, target: str) -> dict[str, Any]: ...
    async def hangup_call(self, provider_call_id: str) -> dict[str, Any]: ...
    async def start_recording(self, provider_call_id: str) -> dict[str, Any]: ...
    async def stop_recording(self, provider_call_id: str) -> dict[str, Any]: ...
    async def fetch_recording(self, provider_call_id: str) -> dict[str, Any]: ...
    async def fetch_transcription(self, provider_call_id: str) -> dict[str, Any]: ...


class TelnyxAdapter:
    provider_name = "telnyx"

    def validate_webhook_signature(self, headers: dict[str, str], payload: dict[str, Any]) -> bool:
        # TODO: verify Telnyx signature with configured public key.
        return bool(headers) or bool(payload)

    def handle_inbound_webhook(self, payload: dict[str, Any]) -> NormalizedProviderEvent:
        data = payload.get("data", payload)
        event_type = data.get("event_type") or data.get("type") or "unknown"
        call_control_id = (
            data.get("payload", {}).get("call_control_id")
            or data.get("call_control_id")
            or data.get("id")
        )
        event_id = data.get("id") or payload.get("id")
        nested = data.get("payload", {})
        return NormalizedProviderEvent(
            provider=self.provider_name,
            event_type=event_type,
            provider_event_id=event_id,
            provider_call_id=call_control_id,
            from_value=nested.get("from") or data.get("from"),
            to_value=nested.get("to") or data.get("to"),
            payload=payload,
        )

    async def create_outbound_call(self, *, to_value: str, from_value: str | None, metadata: dict[str, Any]) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "create_outbound_call", "to": to_value, "from": from_value, "metadata": metadata}

    async def answer_call(self, provider_call_id: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "answer", "provider_call_id": provider_call_id}

    async def bridge_call_to_livekit_room(self, provider_call_id: str, room_name: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "bridge_to_livekit", "provider_call_id": provider_call_id, "room_name": room_name}

    async def transfer_call(self, provider_call_id: str, target: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "transfer", "provider_call_id": provider_call_id, "target": target}

    async def hangup_call(self, provider_call_id: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "hangup", "provider_call_id": provider_call_id}

    async def start_recording(self, provider_call_id: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "start_recording", "provider_call_id": provider_call_id}

    async def stop_recording(self, provider_call_id: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "stop_recording", "provider_call_id": provider_call_id}

    async def fetch_recording(self, provider_call_id: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "fetch_recording", "provider_call_id": provider_call_id}

    async def fetch_transcription(self, provider_call_id: str) -> dict[str, Any]:
        return {"provider": self.provider_name, "action": "fetch_transcription", "provider_call_id": provider_call_id}


def adapter_for_provider(provider: str) -> TelecomProviderAdapter:
    normalized = provider.lower().strip()
    if normalized in {"telnyx", "default"}:
        return TelnyxAdapter()
    # TODO: add TwilioAdapter/VonageAdapter behind the same contract.
    return TelnyxAdapter()
