"""
Mapping between internal claim states and insured-facing macro states.
"""


MACRO_STATE_CONFIG = {
    "attention_needed": {
        "states": {"SV002", "SV022", "SV023"},
        "label": "Documentazione richiesta",
        "description": "Per proseguire serve un tuo riscontro o documentazione aggiuntiva.",
        "needs_action": True,
    },
    "inspection": {
        "states": {"SV003", "SV004", "SV005", "SV010", "SV050", "SV051", "SV052", "SV053"},
        "label": "Perizia in organizzazione",
        "description": "Stiamo organizzando o gestendo la perizia relativa al sinistro.",
        "needs_action": False,
    },
    "under_review": {
        "states": {"SV006", "SV007", "SV008", "SV009", "SV011", "SV012", "SV013", "SV014", "SV041"},
        "label": "In analisi",
        "description": "Il sinistro è attualmente in lavorazione e in verifica tecnica.",
        "needs_action": False,
    },
    "act_ready": {
        "states": {"SV020", "SV030", "SV031"},
        "label": "Atto pronto",
        "description": "È disponibile un esito o un atto da prendere in visione e confermare.",
        "needs_action": True,
    },
    "settlement": {
        "states": {"SV032", "SV033"},
        "label": "In liquidazione",
        "description": "Il sinistro è stato definito ed è in fase di liquidazione.",
        "needs_action": False,
    },
    "closed": {
        "states": {"SV090", "SV091"},
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
