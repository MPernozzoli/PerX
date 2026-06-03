"""
Future AI triage contract.

AI agents collect structured facts only. PerX keeps routing authority in
CommunicationRoutingEngine.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class CommunicationTriageResult:
    claim_number: str | None = None
    person_name: str | None = None
    company_name: str | None = None
    reason: str | None = None
    urgency: str | None = None
    callback_requested: bool = False
    transcript: str | None = None
    summary: str | None = None
    suggested_next_action: str | None = None


class CommunicationAITriageAdapter(Protocol):
    async def collect_context(self, *, session_id: str, call_id: str | None, prompt_context: dict) -> CommunicationTriageResult: ...


class StubCommunicationAITriageAdapter:
    async def collect_context(self, *, session_id: str, call_id: str | None, prompt_context: dict) -> CommunicationTriageResult:
        return CommunicationTriageResult(
            reason="stub_triage_pending",
            urgency="unknown",
            suggested_next_action="route_to_triage_queue",
        )
