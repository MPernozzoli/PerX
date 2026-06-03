"""
Application service for CommunicationSession lifecycle.
"""
from __future__ import annotations

import hashlib
import logging
import re
import secrets
import uuid

logger = logging.getLogger(__name__)
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.communication import (
    Call,
    CallParticipant,
    CallLog,
    CommunicationSession,
    ExternalInviteLink,
    ProviderWebhookEvent,
    ScheduledCommunication,
)
from app.models.user import User
from app.schemas.communication import (
    CommunicationCallerContext,
    CommunicationIncomingCallListResponse,
    CommunicationIncomingCallResponse,
    CommunicationContext,
    CommunicationDestination,
    CommunicationLiveKitTokenResponse,
    CommunicationNotificationAction,
    CommunicationNotificationActionType,
    CommunicationSessionActionResponse,
    CommunicationStartResponse,
    ExternalInviteCreateRequest,
    ExternalInviteResponse,
    ProviderWebhookResponse,
    ScheduledCommunicationCreateRequest,
    ScheduledCommunicationResponse,
)
from app.services.communication_ai_triage import StubCommunicationAITriageAdapter
from app.services.communication_contact_resolver import CommunicationContactResolver
from app.services.communication_extension_service import CommunicationExtensionService
from app.services.livekit_token_service import LiveKitGrant, LiveKitTokenService
from app.services.communication_routing_engine import CommunicationRoutingEngine
from app.services.telecom_provider_adapter import NormalizedProviderEvent, adapter_for_provider

_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.IGNORECASE)


class CommunicationService:
    async def _resolve_target_id(
        self,
        db: AsyncSession,
        tenant_id: str,
        destination: CommunicationDestination,
    ) -> CommunicationDestination:
        """Return destination with target_id guaranteed to be a real user UUID.

        The iOS/macOS client resolves contacts locally from seed data and may
        send a placeholder id (e.g. "user-massimo") or an extension number
        instead of the actual user UUID. Re-resolve here so FK constraints hold.
        """
        if destination.destination_type.value not in {"internal_user", "internal_extension"}:
            return destination
        target = destination.target_id or ""
        if _UUID_RE.match(target):
            return destination  # already a real UUID, nothing to do
        # Try to resolve by extension number
        if re.match(r"^\d{1,6}$", target):
            user = await CommunicationExtensionService.find_user_by_extension(db, tenant_id, target)
            if user:
                destination.target_id = user.id
                destination.display_name = user.extension_display_name or user.full_name or destination.display_name
                return destination
        # Try to resolve by raw_value if it looks like an extension number
        raw = destination.raw_value or ""
        if re.match(r"^\d{1,6}$", raw):
            user = await CommunicationExtensionService.find_user_by_extension(db, tenant_id, raw)
            if user:
                destination.target_id = user.id
                destination.display_name = user.extension_display_name or user.full_name or destination.display_name
                return destination
        # Could not resolve to a UUID — clear target_id so FK won't fail; call
        # will still be logged but won't create a broken participant row.
        logger.warning(
            "Could not resolve internal target_id %r (raw=%r) for tenant %s; clearing target_id",
            target, raw, tenant_id,
        )
        destination.target_id = None
        return destination

    async def start_communication(
        self,
        db: AsyncSession,
        current_user: User,
        destination: CommunicationDestination,
        context: CommunicationContext,
    ) -> CommunicationStartResponse:
        destination = await self._resolve_target_id(db, current_user.tenant_id, destination)
        session = CommunicationSession(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            claim_id=destination.context_claim_id or context.claim_id,
            created_by_user_id=current_user.id,
            scheduled_communication_id=context.scheduled_communication_id,
            destination_type=destination.destination_type.value,
            transport=destination.transport.value,
            state="ringing" if destination.transport.value == "livekit" else "pending",
            display_name=destination.display_name,
            livekit_room_name=self._room_name(current_user.tenant_id, destination.target_id) if destination.transport.value == "livekit" else None,
            external_provider="telnyx" if destination.transport.value == "telecom_provider" else None,
            metadata_json={"raw_destination": destination.raw_value, "service_contract": "startCommunication(destination, context)"},
        )
        call = Call(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            session_id=session.id,
            claim_id=session.claim_id,
            direction="outbound",
            state="ringing" if destination.transport.value == "livekit" else "pending",
            from_value=destination.suggested_caller_id,
            to_value=destination.target_id or destination.raw_value,
            caller_id=destination.suggested_caller_id,
            provider=session.external_provider,
            livekit_room_name=session.livekit_room_name,
        )
        db.add(session)
        await db.flush()  # persist session row before call FK references it
        db.add(call)
        await db.flush()  # persist call row before participant FK references it
        self._add_participants(db, session, call, current_user, destination)
        self._log(db, session, call.id, current_user.id, "communication.start_requested", "pending", destination.model_dump(mode="json"))

        livekit_token = None
        if destination.transport.value == "telecom_provider":
            adapter = adapter_for_provider(session.external_provider or "telnyx")
            provider_action = await adapter.create_outbound_call(
                to_value=destination.target_id or destination.raw_value,
                from_value=destination.suggested_caller_id,
                metadata={"session_id": session.id, "call_id": call.id, "tenant_id": current_user.tenant_id},
            )
            self._log(db, session, call.id, current_user.id, "provider.outbound_call_requested", "pending", provider_action)
        elif destination.transport.value == "livekit":
            self._log(db, session, call.id, current_user.id, "livekit.room_reserved", "pending", {"room_name": session.livekit_room_name})
            livekit_token = self.mint_livekit_token_for_session_row(
                session=session,
                current_user=current_user,
                call_id=call.id,
            )
        else:
            self._log(db, session, call.id, current_user.id, "routing_engine.dispatch_requested", "pending", {"target_id": destination.target_id})

        await db.commit()

        if destination.destination_type.value in {"internal_user", "internal_extension"}:
            try:
                from app.services.push_notifier import notify_incoming_call
                await notify_incoming_call(db, session.id)
            except Exception as e:
                logger.warning("VoIP push dispatch failed for session %s: %s", session.id, e)

        return CommunicationStartResponse(
            session_id=session.id,
            call_id=call.id,
            state=session.state,
            destination=destination,
            created_at=session.created_at or datetime.now(timezone.utc),
            livekit_token=livekit_token,
        )

    async def list_incoming_calls(
        self,
        db: AsyncSession,
        current_user: User,
    ) -> CommunicationIncomingCallListResponse:
        result = await db.execute(
            select(CommunicationSession, Call.id)
            .join(CallParticipant, CallParticipant.session_id == CommunicationSession.id)
            .outerjoin(Call, Call.session_id == CommunicationSession.id)
            .where(
            CommunicationSession.tenant_id == current_user.tenant_id,
                CommunicationSession.transport == "livekit",
                CommunicationSession.state.in_(["pending", "ringing", "active"]),
                CallParticipant.user_id == current_user.id,
                CallParticipant.role == "callee",
            )
            .order_by(CommunicationSession.created_at.desc())
            .limit(20)
        )
        items = [
            CommunicationIncomingCallResponse(
                session_id=session.id,
                call_id=call_id,
                display_name=session.display_name,
                state=session.state,
                destination_type=session.destination_type,
                transport=session.transport,
                livekit_room_name=session.livekit_room_name,
                claim_id=session.claim_id,
                caller_context=self._caller_context_from_session(session),
                notification_actions=self.notification_actions(has_claim=bool(session.claim_id)),
                created_at=session.created_at,
            )
            for session, call_id in result.all()
        ]
        return CommunicationIncomingCallListResponse(items=items)

    async def mint_livekit_token(
        self,
        db: AsyncSession,
        current_user: User,
        session_id: str,
        call_id: str | None = None,
    ) -> CommunicationLiveKitTokenResponse:
        result = await db.execute(
            select(CommunicationSession).where(
                CommunicationSession.id == session_id,
                CommunicationSession.tenant_id == current_user.tenant_id,
            )
        )
        session = result.scalar_one_or_none()
        if session is None:
            raise ValueError("Communication session not found")
        if session.transport != "livekit" or not session.livekit_room_name:
            raise ValueError("Communication session is not a LiveKit session")
        if session.state in {"completed", "failed", "cancelled", "expired"}:
            raise ValueError("Communication session is closed")
        return self.mint_livekit_token_for_session_row(
            session=session,
            current_user=current_user,
            call_id=call_id,
        )

    def mint_livekit_token_for_session_row(
        self,
        session: CommunicationSession,
        current_user: User,
        call_id: str | None,
    ) -> CommunicationLiveKitTokenResponse:
        grant = LiveKitGrant(can_subscribe=True, can_publish=True, can_publish_data=True)
        minted = LiveKitTokenService.mint(
            identity=f"user:{current_user.id}",
            room_name=session.livekit_room_name or self._room_name(session.tenant_id, session.id),
            grant=grant,
            display_name=current_user.full_name or current_user.email,
            metadata={
                "role": "internal_user",
                "user_id": current_user.id,
                "tenant_id": current_user.tenant_id,
                "session_id": session.id,
                "call_id": call_id,
                "module": "communications",
            },
        )
        return CommunicationLiveKitTokenResponse(
            token=minted.token,
            livekit_url=minted.livekit_url,
            room_name=minted.room_name,
            identity=minted.identity,
            expires_at=minted.expires_at,
            can_publish=grant.can_publish,
            can_subscribe=grant.can_subscribe,
            session_id=session.id,
            call_id=call_id,
            display_name=current_user.full_name or current_user.email,
        )

    async def handle_provider_webhook(
        self,
        db: AsyncSession,
        provider: str,
        headers: dict[str, str],
        payload: dict,
        tenant_id: str | None,
    ) -> ProviderWebhookResponse:
        adapter = adapter_for_provider(provider)
        signature_valid = adapter.validate_webhook_signature(headers, payload)
        normalized = adapter.handle_inbound_webhook(payload)
        event = ProviderWebhookEvent(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            provider=normalized.provider,
            provider_event_id=normalized.provider_event_id,
            event_type=normalized.event_type,
            signature_valid=signature_valid,
            normalized_payload_json=self._normalized_event_payload(normalized),
            raw_payload_json=payload,
            processed_at=datetime.now(timezone.utc),
        )
        db.add(event)

        action: dict = {"type": "noop"}
        caller_context: CommunicationCallerContext | None = None
        session: CommunicationSession | None = None
        call: Call | None = None
        if tenant_id and normalized.event_type in {"call.initiated", "call.ringing"}:
            caller_context = await CommunicationContactResolver().resolve_caller(
                db,
                tenant_id=tenant_id,
                phone_number=normalized.from_value,
            )
            decision = await CommunicationRoutingEngine().route_inbound_call(
                db,
                tenant_id=tenant_id,
                from_value=normalized.from_value,
                to_value=normalized.to_value,
            )
            action = {"type": decision.action, "target_type": decision.target_type, "target_id": decision.target_id, "state": decision.state, "reason": decision.reason, "metadata": decision.metadata or {}}
            session, call = await self._ensure_inbound_provider_session(
                db=db,
                tenant_id=tenant_id,
                normalized=normalized,
                state=decision.state,
                caller_context=caller_context,
                claim_id=(caller_context.claim_context.claim_id if caller_context and caller_context.claim_context else decision.metadata.get("claim_id") if decision.metadata else None),
            )
            action["session_id"] = session.id
            action["call_id"] = call.id

            if decision.action == "ring_user" and decision.target_type == "user_email" and decision.target_id:
                target_user = (await db.execute(
                    select(User).where(
                        User.tenant_id == tenant_id,
                        User.email == decision.target_id,
                        User.is_active == True,  # noqa: E712
                    )
                )).scalar_one_or_none()
                if target_user:
                    existing_callee = (await db.execute(
                        select(CallParticipant).where(
                            CallParticipant.session_id == session.id,
                            CallParticipant.user_id == target_user.id,
                            CallParticipant.role == "callee",
                        )
                    )).scalar_one_or_none()
                    if existing_callee is None:
                        db.add(CallParticipant(
                            id=str(uuid.uuid4()),
                            tenant_id=tenant_id,
                            session_id=session.id,
                            call_id=call.id,
                            participant_type="internal_user",
                            user_id=target_user.id,
                            display_name=target_user.full_name or target_user.email,
                            livekit_identity=f"user:{target_user.id}",
                            role="callee",
                        ))

        await db.commit()

        if session and call and action.get("type") == "ring_user":
            try:
                from app.services.push_notifier import notify_incoming_call
                await notify_incoming_call(db, session.id)
            except Exception as e:
                logger.warning("Inbound VoIP push dispatch failed for session %s: %s", session.id, e)
        return ProviderWebhookResponse(
            event_id=event.id,
            provider=event.provider,
            event_type=event.event_type,
            signature_valid=signature_valid,
            action=action,
            session_id=session.id if session else None,
            call_id=call.id if call else None,
            caller_context=caller_context,
            notification_actions=self.notification_actions(has_claim=bool(session and session.claim_id)),
        )

    async def handle_session_action(
        self,
        db: AsyncSession,
        current_user: User,
        session_id: str,
        action_type: CommunicationNotificationActionType,
    ) -> CommunicationSessionActionResponse:
        result = await db.execute(
            select(CommunicationSession, Call)
            .outerjoin(Call, Call.session_id == CommunicationSession.id)
            .where(
                CommunicationSession.id == session_id,
                CommunicationSession.tenant_id == current_user.tenant_id,
            )
            .limit(1)
        )
        row = result.first()
        if row is None:
            raise ValueError("Communication session not found")
        session, call = row

        livekit_token = None
        provider_action: dict = {}
        open_claim = False
        state = session.state

        if action_type in {
            CommunicationNotificationActionType.answer,
            CommunicationNotificationActionType.answer_and_open_claim,
        }:
            session.state = "active"
            if call:
                call.state = "active"
                call.answered_at = datetime.now(timezone.utc)
            state = "active"
            open_claim = action_type == CommunicationNotificationActionType.answer_and_open_claim and bool(session.claim_id)
            if session.transport == "livekit":
                livekit_token = self.mint_livekit_token_for_session_row(
                    session=session,
                    current_user=current_user,
                    call_id=call.id if call else None,
                )
            elif session.external_provider and call and call.provider_call_id:
                adapter = adapter_for_provider(session.external_provider)
                provider_action = await adapter.answer_call(call.provider_call_id)
        elif action_type == CommunicationNotificationActionType.end:
            session.state = "ended"
            session.ended_at = datetime.now(timezone.utc)
            if call:
                call.state = "ended"
                call.completed_at = datetime.now(timezone.utc)
            state = "ended"
        elif action_type == CommunicationNotificationActionType.open_claim_only:
            open_claim = bool(session.claim_id)
        elif action_type == CommunicationNotificationActionType.send_to_voicemail_ai_triage:
            session.state = "needs_triage"
            if call:
                call.state = "needs_triage"
            state = "needs_triage"
            if session.external_provider and call and call.provider_call_id:
                adapter = adapter_for_provider(session.external_provider)
                provider_action = await adapter.transfer_call(call.provider_call_id, "ai_triage")
            triage = await StubCommunicationAITriageAdapter().collect_context(
                session_id=session.id,
                call_id=call.id if call else None,
                prompt_context={
                    "message": "Il perito non e disponibile in questo momento. Prendi una nota strutturata della chiamata.",
                    "claim_id": session.claim_id,
                },
            )
            provider_action = {
                **provider_action,
                "type": "send_to_voicemail_ai_triage",
                "triage": triage.__dict__,
            }

        self._log(
            db,
            session,
            call.id if call else None,
            current_user.id,
            f"communication.notification_action.{action_type.value}",
            state,
            {"open_claim": open_claim, "provider_action": provider_action},
        )
        await db.commit()
        return CommunicationSessionActionResponse(
            session_id=session.id,
            call_id=call.id if call else None,
            action_type=action_type,
            state=state,
            claim_id=session.claim_id,
            open_claim=open_claim,
            livekit_token=livekit_token,
            provider_action=provider_action,
        )

    async def create_scheduled_communication(
        self,
        db: AsyncSession,
        current_user: User,
        payload: ScheduledCommunicationCreateRequest,
    ) -> ScheduledCommunicationResponse:
        scheduled = ScheduledCommunication(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            claim_id=payload.claim_id,
            created_by_user_id=current_user.id,
            title=payload.title,
            starts_at=payload.starts_at,
            ends_at=payload.ends_at,
            state="scheduled",
            livekit_room_name=self._room_name(current_user.tenant_id, payload.claim_id or payload.title),
            internal_participants_json=payload.internal_participants,
            external_invites_json=payload.external_invites,
            reminders_json=payload.reminders,
        )
        db.add(scheduled)
        await db.commit()
        return ScheduledCommunicationResponse(
            id=scheduled.id,
            tenant_id=scheduled.tenant_id,
            title=scheduled.title,
            starts_at=scheduled.starts_at,
            ends_at=scheduled.ends_at,
            state=scheduled.state,
            livekit_room_name=scheduled.livekit_room_name,
            claim_id=scheduled.claim_id,
        )

    async def create_external_invite(
        self,
        db: AsyncSession,
        current_user: User,
        payload: ExternalInviteCreateRequest,
    ) -> ExternalInviteResponse:
        token = secrets.token_urlsafe(32)
        invite = ExternalInviteLink(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            session_id=payload.session_id,
            scheduled_communication_id=payload.scheduled_communication_id,
            claim_id=payload.claim_id,
            token_hash=hashlib.sha256(token.encode("utf-8")).hexdigest(),
            guest_role=payload.guest_role,
            permissions_json=payload.permissions,
            valid_from=payload.valid_from,
            valid_until=payload.valid_until,
        )
        db.add(invite)
        await db.commit()
        return ExternalInviteResponse(
            id=invite.id,
            url_path=f"/guest/communications/{token}",
            guest_role=invite.guest_role,
            valid_from=invite.valid_from,
            valid_until=invite.valid_until,
            revoked_at=invite.revoked_at,
        )

    def _log(self, db: AsyncSession, session: CommunicationSession, call_id: str | None, actor_user_id: str | None, event_type: str, state: str, payload: dict) -> None:
        db.add(CallLog(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            session_id=session.id,
            call_id=call_id,
            actor_user_id=actor_user_id,
            event_type=event_type,
            state=state,
            payload_json=payload,
        ))

    def _add_participants(
        self,
        db: AsyncSession,
        session: CommunicationSession,
        call: Call,
        current_user: User,
        destination: CommunicationDestination,
    ) -> None:
        db.add(CallParticipant(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            session_id=session.id,
            call_id=call.id,
            participant_type="internal_user",
            user_id=current_user.id,
            display_name=current_user.full_name or current_user.email,
            livekit_identity=f"user:{current_user.id}",
            role="caller",
        ))
        if destination.destination_type.value in {"internal_user", "internal_extension"} and destination.target_id:
            db.add(CallParticipant(
                id=str(uuid.uuid4()),
                tenant_id=session.tenant_id,
                session_id=session.id,
                call_id=call.id,
                participant_type="internal_user",
                user_id=destination.target_id,
                display_name=destination.display_name,
                livekit_identity=f"user:{destination.target_id}",
                role="callee",
            ))

    async def _ensure_inbound_provider_session(
        self,
        db: AsyncSession,
        tenant_id: str,
        normalized: NormalizedProviderEvent,
        state: str,
        caller_context: CommunicationCallerContext | None,
        claim_id: str | None,
    ) -> tuple[CommunicationSession, Call]:
        if normalized.provider_call_id:
            existing = await db.execute(
                select(CommunicationSession, Call)
                .join(Call, Call.session_id == CommunicationSession.id)
                .where(
                    CommunicationSession.tenant_id == tenant_id,
                    Call.provider == normalized.provider,
                    Call.provider_call_id == normalized.provider_call_id,
                )
                .limit(1)
            )
            row = existing.first()
            if row:
                session, call = row
                session.state = state
                call.state = state
                if caller_context:
                    metadata = session.metadata_json or {}
                    metadata["caller_context"] = caller_context.model_dump(mode="json")
                    session.metadata_json = metadata
                    session.display_name = caller_context.display_name
                return session, call

        session = CommunicationSession(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            destination_type="external_phone",
            transport="telecom_provider",
            state=state,
            display_name=caller_context.display_name if caller_context else normalized.from_value,
            external_provider=normalized.provider,
            provider_session_id=normalized.provider_call_id,
            metadata_json={
                "caller_context": caller_context.model_dump(mode="json") if caller_context else None,
                "provider_event_id": normalized.provider_event_id,
            },
        )
        call = Call(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            session_id=session.id,
            claim_id=claim_id,
            direction="inbound",
            state=state,
            from_value=normalized.from_value,
            to_value=normalized.to_value,
            provider=normalized.provider,
            provider_call_id=normalized.provider_call_id,
        )
        db.add(session)
        db.add(call)
        if caller_context:
            db.add(CallParticipant(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                session_id=session.id,
                call_id=call.id,
                participant_type="external_contact",
                display_name=caller_context.display_name,
                phone_number=normalized.from_value,
                role="caller",
                metadata_json=caller_context.model_dump(mode="json"),
            ))
        self._log(db, session, call.id, None, "provider.inbound_call_detected", state, self._normalized_event_payload(normalized))
        return session, call

    def _room_name(self, tenant_id: str, seed: str | None) -> str:
        # Always unique per call: deterministic prefix for readability, random suffix
        # to avoid UniqueViolation when the same destination is called again.
        random_suffix = uuid.uuid4().hex[:8]
        base = uuid.uuid5(uuid.NAMESPACE_URL, seed or str(uuid.uuid4())).hex[:8]
        return f"perx-{tenant_id[:8]}-{base}{random_suffix}"

    def _normalized_event_payload(self, event: NormalizedProviderEvent) -> dict:
        return {
            "provider": event.provider,
            "event_type": event.event_type,
            "provider_event_id": event.provider_event_id,
            "provider_call_id": event.provider_call_id,
            "from": event.from_value,
            "to": event.to_value,
        }

    def notification_actions(self, has_claim: bool) -> list[CommunicationNotificationAction]:
        return [
            CommunicationNotificationAction(action_type=CommunicationNotificationActionType.answer, title="Rispondi"),
            CommunicationNotificationAction(
                action_type=CommunicationNotificationActionType.answer_and_open_claim,
                title="Rispondi e apri sinistro",
                emphasized=True,
                requires_claim=True,
            ),
            CommunicationNotificationAction(
                action_type=CommunicationNotificationActionType.open_claim_only,
                title="Apri solo sinistro",
                requires_claim=True,
            ),
            CommunicationNotificationAction(
                action_type=CommunicationNotificationActionType.send_to_voicemail_ai_triage,
                title="Manda alla segreteria",
            ),
        ] if has_claim else [
            CommunicationNotificationAction(action_type=CommunicationNotificationActionType.answer, title="Rispondi"),
            CommunicationNotificationAction(
                action_type=CommunicationNotificationActionType.send_to_voicemail_ai_triage,
                title="Manda alla segreteria",
            ),
        ]

    def _caller_context_from_session(self, session: CommunicationSession) -> CommunicationCallerContext | None:
        metadata = session.metadata_json or {}
        raw = metadata.get("caller_context")
        if not isinstance(raw, dict):
            return None
        return CommunicationCallerContext.model_validate(raw)
