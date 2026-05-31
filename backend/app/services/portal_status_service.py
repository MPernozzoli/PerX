"""
Mapping between internal claim states and insured-facing macro states.
"""
from app.core.claim_status import ClaimStatus


MACRO_STATE_CONFIG = {
    "attention_needed": {
        "states": {
            ClaimStatus.IN_ATTESA_DOCUMENTALE.value,
            ClaimStatus.IN_ATTESA_TERZI.value,
        },
        "label": "Documentazione richiesta",
        "description": "Per proseguire serve un tuo riscontro o documentazione aggiuntiva.",
        "needs_action": True,
    },
    "inspection": {
        "states": {
            ClaimStatus.DA_GESTIRE_TRADIZIONALE.value,
            ClaimStatus.VIDEOPERIZIA_DA_ESEGUIRE.value,
            ClaimStatus.DA_GESTIRE_NO_RESIDUI.value,
            ClaimStatus.DA_GESTIRE_DOCUMENTALE.value,
            ClaimStatus.SOPRALLUOGO.value,
        },
        "label": "Perizia in organizzazione",
        "description": "Stiamo organizzando o gestendo la perizia relativa al sinistro.",
        "needs_action": False,
    },
    "under_review": {
        "states": {
            ClaimStatus.ISTRUZIONE.value,
            ClaimStatus.PRIMO_CONTATTO.value,
            ClaimStatus.SECONDO_CONTATTO.value,
            ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value,
            ClaimStatus.DA_GESTIRE_VIDEO.value,
            ClaimStatus.IN_GESTIONE.value,
            ClaimStatus.CONTROLLATA.value,
        },
        "label": "In analisi",
        "description": "Il sinistro è attualmente in lavorazione e in verifica tecnica.",
        "needs_action": False,
    },
    "act_ready": {
        "states": {
            ClaimStatus.ATTO_DA_INVIARE.value,
            ClaimStatus.ESITO_COMUNICATO.value,
            ClaimStatus.ATTO_INVIATO.value,
            ClaimStatus.ESITO_DA_COMUNICARE.value,
        },
        "label": "Atto pronto",
        "description": "È disponibile un esito o un atto da prendere in visione e confermare.",
        "needs_action": True,
    },
    "settlement": {
        "states": {
            ClaimStatus.ATTO_RICEVUTO.value,
            ClaimStatus.DA_CHIUDERE_A_SISTEMA.value,
        },
        "label": "In liquidazione",
        "description": "Il sinistro è stato definito ed è in fase di liquidazione.",
        "needs_action": False,
    },
    "closed": {
        "states": {
            ClaimStatus.CHIUSA.value,
            ClaimStatus.DA_REVISIONARE.value,
        },
        "label": "Liquidato o chiuso",
        "description": "Il sinistro risulta definito o chiuso.",
        "needs_action": False,
    },
}


class PortalStatusService:
    @staticmethod
    def build_macro_state(internal_state: str | None) -> dict:
        for code, config in MACRO_STATE_CONFIG.items():
            if internal_state in config["states"]:
                return {
                    "code": code,
                    "label": config["label"],
                    "description": config["description"],
                    "needs_action": config["needs_action"],
                    "internal_state": internal_state,
                }

        return {
            "code": "processing",
            "label": "In lavorazione",
            "description": "Il sinistro è in gestione.",
            "needs_action": False,
            "internal_state": internal_state,
        }
