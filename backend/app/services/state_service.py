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
    "SV001": ["SV002", "SV003", "SV004", "SV005"],  # daScaricare
    "SV002": ["SV010", "SV003"],  # inAttesaDocumentale
    "SV003": ["SV012", "SV020", "SV021"],  # periziaDaEseguire
    "SV004": ["SV014", "SV013"],  # videoperiziaDaFissare
    "SV005": ["SV012", "SV021", "SV020"],  # periziaDaEseguireNoResidui
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
    "SV050": ["SV051", "SV012"],  # sopralluogoFissato
    "SV051": ["SV012", "SV003", "SV020", "SV021"],  # sopralluogoRestituito
    "SV090": ["SV091"],  # chiusa
    "SV091": ["SV012", "SV090"],  # richiestaRevisione
}


class StateService:
    @staticmethod
    async def transition_state(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        from_state: Optional[str],
        to_state: str,
        user_id: Optional[str],
        reason: Optional[str] = None,
        payload: Optional[dict] = None
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
            source="manual"
        )
        db.add(event)
        
        await db.commit()
        return True

