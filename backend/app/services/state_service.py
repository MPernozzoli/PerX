"""
State service - manages claim state transitions
Based on StatoManager logic from PerX
"""
from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.claim import Claim
from app.models.claim_state import ClaimState
from app.models.claim_event import ClaimEvent


# Valid state transitions (mapped from StatoManager.StatoSinistro.validTransitions)
VALID_TRANSITIONS = {
    "SV001": ["SV002", "SV004", "SV005", "SV052"],  # daScaricare
    "SV002": ["SV010", "SV003"],  # inAttesaDocumentale
    "SV003": ["SV012", "SV020", "SV021"],  # periziaDaEseguire
    "SV004": ["SV014", "SV013"],  # videoperiziaDaFissare
    "SV005": ["SV012", "SV021", "SV020"],  # periziaDaEseguireNoResidui
    "SV006": ["SV007", "SV052"],  # istruzione
    "SV007": ["SV008", "SV009", "SV016", "SV018", "SV019", "SV026", "SV052"],  # primoContatto
    "SV008": ["SV009", "SV016", "SV018", "SV019", "SV026", "SV052"],  # secondoContatto
    "SV009": ["SV015", "SV016", "SV019", "SV026", "SV052"],  # inAttesaAssegnazione
    "SV010": ["SV011", "SV012", "SV021"],  # periziaDaEseguireDocumentale
    "SV011": ["SV021", "SV020", "SV091"],  # inGestioneDocumentale
    "SV012": ["SV020", "SV021", "SV091"],  # inGestione
    "SV013": ["SV014", "SV020", "SV021", "SV091"],  # inGestioneVideoperizia
    "SV014": ["SV013", "SV020", "SV021"],  # videoperiziaFissata
    "SV020": ["SV031"],  # attoDaInviare
    "SV021": ["SV030"],  # esitoDaComunicare
    "SV022": ["SV012", "SV011", "SV010", "SV021"],  # inAttesaDaAssicurato
    "SV023": ["SV012", "SV011", "SV010", "SV021"],  # inAttesaDaAgenzia
    "SV030": ["SV032", "SV033", "SV090", "SV012"],  # esitoComunicato
    "SV031": ["SV032", "SV033", "SV090", "SV012"],  # attoInviato
    "SV032": ["SV090"],  # attoRicevutoSottoscritto
    "SV033": ["SV090"],  # accettataVerbalmente
    "SV040": ["SV041"],  # inControllo
    "SV041": ["SV012", "SV003", "SV090", "SV091"],  # controllata
    "SV050": ["SV051", "SV053", "SV003"],  # sopralluogoFissato
    "SV051": ["SV052", "SV053", "SV050"],  # sopralluogoRestituito
    "SV052": ["SV050", "SV053"],  # sopralluogoDaFissare
    "SV053": ["SV052", "SV050"],  # sopralluogoDaConcordare
    "SV090": ["SV091"],  # chiusa
    "SV091": ["SV012", "SV090"],  # richiestaRevisione
}

INSPECTION_WORKFLOW_STAGES = {
    "SV050": "scheduled_awaiting_visit",
    "SV051": "replanning_required",
    "SV052": "automatic_scheduling_in_progress",
    "SV053": "manual_scheduling_required",
}
CAT_INSPECTION_STATES = set(INSPECTION_WORKFLOW_STAGES.keys())


class StateService:
    @staticmethod
    def _merge_claim_metadata(claim: Claim, **updates) -> None:
        metadata = dict(claim.metadata_json or {})
        for key, value in updates.items():
            if value is None:
                metadata.pop(key, None)
            else:
                metadata[key] = value
        claim.metadata_json = metadata or None

    @staticmethod
    def _parse_iso_datetime(raw_value: str | None):
        if not raw_value:
            return None
        from datetime import datetime
        candidate = raw_value.strip()
        if candidate.endswith("Z"):
            candidate = candidate[:-1] + "+00:00"
        try:
            return datetime.fromisoformat(candidate)
        except ValueError:
            return None

    @staticmethod
    async def transition_state(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        from_state: Optional[str],
        to_state: str,
        user_id: Optional[str],
        reason: Optional[str] = None,
        payload: Optional[dict] = None,
        *,
        commit: bool = True,
        event_source: str = "manual",
    ) -> bool:
        """Transition claim to new state with validation"""
        # Get claim
        result = await db.execute(
            select(Claim).where(
                (Claim.id == claim_id) & (Claim.tenant_id == tenant_id)
            )
        )
        claim = result.scalar_one_or_none()
        if not claim:
            return False
        
        # Validate transition
        current_state = claim.stato_corrente
        if from_state and current_state != from_state:
            return False
        
        if current_state in VALID_TRANSITIONS:
            if to_state not in VALID_TRANSITIONS[current_state]:
                return False
        
        # Update claim state
        old_state = claim.stato_corrente
        claim.stato_corrente = to_state
        
        # Update dates based on state (similar to StatoManager logic)
        from datetime import datetime
        now = datetime.utcnow()
        
        if to_state in ["SV031", "SV030"]:  # attoInviato, esitoComunicato
            claim.data_invio_atto = now
        elif to_state == "SV090":  # chiusa
            if not claim.closed_at:
                claim.closed_at = now
        elif to_state in ["SV012", "SV011", "SV013"]:  # inGestione variants
            if not claim.data_assegnazione:
                claim.data_assegnazione = now

        scheduled_at = StateService._parse_iso_datetime((payload or {}).get("scheduled_at"))
        if to_state in CAT_INSPECTION_STATES:
            claim.sopralluogo = True
        if to_state == "SV052" and old_state not in CAT_INSPECTION_STATES:
            claim.data_sopralluogo = None
        if to_state == "SV050" and scheduled_at:
            claim.data_sopralluogo = scheduled_at

        if to_state in INSPECTION_WORKFLOW_STAGES:
            StateService._merge_claim_metadata(
                claim,
                inspection_workflow_stage=INSPECTION_WORKFLOW_STAGES[to_state]
            )
        elif to_state == "SV003" and old_state in {"SV050", "SV051", "SV052", "SV053"}:
            claim.owner_email = None
            claim.data_assegnazione = None
            StateService._merge_claim_metadata(
                claim,
                inspection_workflow_stage="expert_assignment_pending"
            )
        elif old_state in {"SV050", "SV051", "SV052", "SV053"}:
            StateService._merge_claim_metadata(claim, inspection_workflow_stage=None)

        claim.version += 1
        claim.updated_at = now
        
        # Create state history record
        import uuid
        state_record = ClaimState(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            from_state=old_state,
            to_state=to_state,
            changed_by_user_id=user_id,
            reason=reason,
            payload_json=payload
        )
        db.add(state_record)
        
        # Create event
        event = ClaimEvent(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            event_type="state_changed",
            actor_user_id=user_id,
            data_json={"from": old_state, "to": to_state, "reason": reason},
            source=event_source
        )
        db.add(event)

        if to_state == "SV052":
            db.add(
                ClaimEvent(
                    id=str(uuid.uuid4()),
                    tenant_id=tenant_id,
                    claim_id=claim_id,
                    event_type="inspection_scheduling_requested",
                    actor_user_id=user_id,
                    data_json={
                        "address_line": claim.indirizzo_assicurato,
                        "workflow_stage": INSPECTION_WORKFLOW_STAGES.get(to_state),
                    },
                    source=event_source,
                )
            )

        if commit:
            await db.commit()
        return True
