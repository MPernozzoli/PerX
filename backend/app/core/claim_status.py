"""
Claim status definitions: canonical state slugs, valid transitions,
substato structure, and mapping from legacy SVxxx codes used pre-cut-over.
"""
from __future__ import annotations

from enum import Enum
from typing import Literal


class ClaimStatus(str, Enum):
    ISTRUZIONE = "istruzione"
    PRIMO_CONTATTO = "primo_contatto"
    SECONDO_CONTATTO = "secondo_contatto"
    IN_ATTESA_ASSEGNAZIONE = "in_attesa_assegnazione"
    SOPRALLUOGO = "sopralluogo"
    IN_ATTESA_DOCUMENTALE = "in_attesa_documentale"
    VIDEOPERIZIA = "videoperizia"
    DA_GESTIRE_VIDEO = "da_gestire_video"
    DA_GESTIRE_TRADIZIONALE = "da_gestire_tradizionale"
    DA_GESTIRE_DOCUMENTALE = "da_gestire_documentale"
    DA_GESTIRE_NO_RESIDUI = "da_gestire_no_residui"
    IN_ATTESA_TERZI = "in_attesa_terzi"
    ATTESA_PASSIVA = "attesa_passiva"
    IN_GESTIONE = "in_gestione"
    ESITO_DA_COMUNICARE = "esito_da_comunicare"
    ESITO_COMUNICATO = "esito_comunicato"
    ATTO_DA_INVIARE = "atto_da_inviare"
    ATTO_INVIATO = "atto_inviato"
    ATTO_RICEVUTO = "atto_ricevuto"
    DA_CONTROLLARE = "da_controllare"
    CONTROLLATA = "controllata"
    DA_REVISIONARE = "da_revisionare"
    DA_CHIUDERE_A_SISTEMA = "da_chiudere_a_sistema"
    CHIUSA = "chiusa"
    # Stati ausiliari fuori dal flusso principale (rami di approvazione)
    RICHIESTA_AUTORIZZAZIONE = "richiesta_autorizzazione"
    SUPERVISIONE_NON_CONCORDATA = "supervisione_non_concordata"


SubstatoSource = Literal["user", "ai", "system"]


# Canonical transition graph. Keys are starting states; values are the set of
# states they may transition to. Substato changes are NOT transitions.
VALID_TRANSITIONS: dict[str, set[str]] = {
    ClaimStatus.ISTRUZIONE.value: {
        ClaimStatus.PRIMO_CONTATTO.value,
        ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value,
        ClaimStatus.SOPRALLUOGO.value,
    },
    ClaimStatus.PRIMO_CONTATTO.value: {
        ClaimStatus.SECONDO_CONTATTO.value,
        ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value,
        ClaimStatus.IN_ATTESA_DOCUMENTALE.value,
        ClaimStatus.VIDEOPERIZIA.value,
        ClaimStatus.DA_GESTIRE_TRADIZIONALE.value,
        ClaimStatus.DA_GESTIRE_DOCUMENTALE.value,
        ClaimStatus.SOPRALLUOGO.value,
    },
    ClaimStatus.SECONDO_CONTATTO.value: {
        ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value,
        ClaimStatus.IN_ATTESA_DOCUMENTALE.value,
        ClaimStatus.VIDEOPERIZIA.value,
        ClaimStatus.DA_GESTIRE_TRADIZIONALE.value,
        ClaimStatus.DA_GESTIRE_DOCUMENTALE.value,
        ClaimStatus.SOPRALLUOGO.value,
        ClaimStatus.ATTESA_PASSIVA.value,
    },
    ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value: {
        ClaimStatus.DA_GESTIRE_TRADIZIONALE.value,
        ClaimStatus.DA_GESTIRE_DOCUMENTALE.value,
        ClaimStatus.DA_GESTIRE_VIDEO.value,
        ClaimStatus.DA_GESTIRE_NO_RESIDUI.value,
        ClaimStatus.SOPRALLUOGO.value,
    },
    ClaimStatus.SOPRALLUOGO.value: {
        ClaimStatus.DA_GESTIRE_TRADIZIONALE.value,
        ClaimStatus.DA_GESTIRE_NO_RESIDUI.value,
    },
    ClaimStatus.IN_ATTESA_DOCUMENTALE.value: {
        ClaimStatus.DA_GESTIRE_DOCUMENTALE.value,
        ClaimStatus.ATTESA_PASSIVA.value,
    },
    ClaimStatus.VIDEOPERIZIA.value: {
        ClaimStatus.DA_GESTIRE_VIDEO.value,
        # Outcome alternatives when perizia ends without enough evidence:
        ClaimStatus.VIDEOPERIZIA.value,   # reschedule → restart da_fissare flow
        ClaimStatus.SOPRALLUOGO.value,    # escalate → physical inspection with CAT
    },
    ClaimStatus.DA_GESTIRE_VIDEO.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.IN_ATTESA_TERZI.value,
        ClaimStatus.ESITO_DA_COMUNICARE.value,
        ClaimStatus.ATTO_DA_INVIARE.value,
    },
    ClaimStatus.DA_GESTIRE_TRADIZIONALE.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.IN_ATTESA_TERZI.value,
        ClaimStatus.ESITO_DA_COMUNICARE.value,
        ClaimStatus.ATTO_DA_INVIARE.value,
    },
    ClaimStatus.DA_GESTIRE_DOCUMENTALE.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.IN_ATTESA_TERZI.value,
        ClaimStatus.ESITO_DA_COMUNICARE.value,
        ClaimStatus.ATTO_DA_INVIARE.value,
    },
    ClaimStatus.DA_GESTIRE_NO_RESIDUI.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.ESITO_DA_COMUNICARE.value,
        ClaimStatus.ATTO_DA_INVIARE.value,
    },
    ClaimStatus.IN_ATTESA_TERZI.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.DA_GESTIRE_TRADIZIONALE.value,
        ClaimStatus.DA_GESTIRE_DOCUMENTALE.value,
        ClaimStatus.DA_GESTIRE_VIDEO.value,
        ClaimStatus.ESITO_DA_COMUNICARE.value,
        ClaimStatus.ATTESA_PASSIVA.value,
    },
    ClaimStatus.ATTESA_PASSIVA.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.DA_CHIUDERE_A_SISTEMA.value,
    },
    ClaimStatus.IN_GESTIONE.value: {
        ClaimStatus.ESITO_DA_COMUNICARE.value,
        ClaimStatus.ATTO_DA_INVIARE.value,
        ClaimStatus.IN_ATTESA_TERZI.value,
        ClaimStatus.DA_CONTROLLARE.value,
    },
    ClaimStatus.ESITO_DA_COMUNICARE.value: {
        ClaimStatus.ESITO_COMUNICATO.value,
        ClaimStatus.IN_GESTIONE.value,
    },
    ClaimStatus.ESITO_COMUNICATO.value: {
        ClaimStatus.ATTO_DA_INVIARE.value,
        ClaimStatus.ATTO_RICEVUTO.value,
        ClaimStatus.DA_CONTROLLARE.value,
        ClaimStatus.IN_GESTIONE.value,
    },
    ClaimStatus.ATTO_DA_INVIARE.value: {
        ClaimStatus.ATTO_INVIATO.value,
    },
    ClaimStatus.ATTO_INVIATO.value: {
        ClaimStatus.ATTO_RICEVUTO.value,
        ClaimStatus.DA_CONTROLLARE.value,
    },
    ClaimStatus.ATTO_RICEVUTO.value: {
        ClaimStatus.DA_CONTROLLARE.value,
        ClaimStatus.DA_CHIUDERE_A_SISTEMA.value,
    },
    ClaimStatus.DA_CONTROLLARE.value: {
        ClaimStatus.CONTROLLATA.value,
        ClaimStatus.DA_REVISIONARE.value,
    },
    ClaimStatus.CONTROLLATA.value: {
        ClaimStatus.DA_CHIUDERE_A_SISTEMA.value,
        ClaimStatus.DA_REVISIONARE.value,
        ClaimStatus.IN_GESTIONE.value,
    },
    ClaimStatus.DA_REVISIONARE.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.DA_CHIUDERE_A_SISTEMA.value,
    },
    ClaimStatus.DA_CHIUDERE_A_SISTEMA.value: {
        ClaimStatus.CHIUSA.value,
    },
    ClaimStatus.CHIUSA.value: set(),
    ClaimStatus.RICHIESTA_AUTORIZZAZIONE.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.ATTO_DA_INVIARE.value,
    },
    ClaimStatus.SUPERVISIONE_NON_CONCORDATA.value: {
        ClaimStatus.IN_GESTIONE.value,
        ClaimStatus.ATTO_DA_INVIARE.value,
    },
}


# Mapping from legacy SVxxx codes (pre-2026-05-30) to canonical slugs and the
# substato tag, if any, induced by the legacy split.
# Used only by migration 020.
LEGACY_SV_TO_SLUG: dict[str, tuple[str, str | None]] = {
    "SV001": (ClaimStatus.ISTRUZIONE.value, None),
    "SV002": (ClaimStatus.IN_ATTESA_DOCUMENTALE.value, None),
    "SV003": (ClaimStatus.DA_GESTIRE_TRADIZIONALE.value, None),
    "SV004": (ClaimStatus.VIDEOPERIZIA.value, "da_fissare"),
    "SV005": (ClaimStatus.DA_GESTIRE_NO_RESIDUI.value, None),
    "SV006": (ClaimStatus.ISTRUZIONE.value, None),
    "SV007": (ClaimStatus.PRIMO_CONTATTO.value, None),
    "SV008": (ClaimStatus.SECONDO_CONTATTO.value, None),
    "SV009": (ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value, None),
    "SV010": (ClaimStatus.DA_GESTIRE_DOCUMENTALE.value, "da_aprire"),
    "SV011": (ClaimStatus.DA_GESTIRE_DOCUMENTALE.value, None),
    "SV012": (ClaimStatus.IN_GESTIONE.value, None),
    "SV013": (ClaimStatus.VIDEOPERIZIA.value, "da_eseguire"),
    "SV014": (ClaimStatus.VIDEOPERIZIA.value, "fissata"),
    "SV020": (ClaimStatus.ATTO_DA_INVIARE.value, None),
    "SV021": (ClaimStatus.ESITO_DA_COMUNICARE.value, None),
    "SV022": (ClaimStatus.IN_ATTESA_TERZI.value, "assicurato"),
    "SV023": (ClaimStatus.IN_ATTESA_TERZI.value, "agenzia"),
    "SV030": (ClaimStatus.ESITO_COMUNICATO.value, None),
    "SV031": (ClaimStatus.ATTO_INVIATO.value, None),
    "SV032": (ClaimStatus.ATTO_RICEVUTO.value, "sottoscritto"),
    "SV033": (ClaimStatus.ATTO_RICEVUTO.value, "verbale"),
    "SV040": (ClaimStatus.DA_CONTROLLARE.value, None),
    "SV041": (ClaimStatus.CONTROLLATA.value, None),
    "SV050": (ClaimStatus.SOPRALLUOGO.value, "fissato"),
    "SV051": (ClaimStatus.SOPRALLUOGO.value, "da_rifissare"),
    "SV052": (ClaimStatus.SOPRALLUOGO.value, "da_fissare"),
    "SV053": (ClaimStatus.SOPRALLUOGO.value, "da_concordare"),
    "SV090": (ClaimStatus.CHIUSA.value, None),
    "SV091": (ClaimStatus.DA_REVISIONARE.value, None),
    "SV042": (ClaimStatus.RICHIESTA_AUTORIZZAZIONE.value, None),
    "SV043": (ClaimStatus.SUPERVISIONE_NON_CONCORDATA.value, None),
}


# Entry criterion: a claim leaves ISTRUZIONE only when these fields are set.
ISTRUZIONE_REQUIRED_FIELDS = (
    "nome_assicurato",
    "nome_contraente",
    "numero_polizza",
    "garanzia",
)

# Number of solleciti after which a claim auto-transitions to ATTESA_PASSIVA.
SOLLECITO_THRESHOLD = 2

# States from which a sollecito timeout pushes the claim into ATTESA_PASSIVA.
SOLLECITABLE_STATES: frozenset[str] = frozenset({
    ClaimStatus.IN_ATTESA_DOCUMENTALE.value,
    ClaimStatus.IN_ATTESA_TERZI.value,
})

# Substato tags reserved for the inspection workflow on SOPRALLUOGO.
SOPRALLUOGO_SUBSTATI = ("da_fissare", "fissato", "confermato", "da_concordare", "da_rifissare")

# Substato tags reserved for the video-inspection workflow on VIDEOPERIZIA.
# Lifecycle:
#   da_fissare → assicurato deve scegliere lo slot dal portale
#   fissata    → slot confermato dall'assicurato, in attesa del giorno X
#   da_eseguire→ giorno X, perito assegnato, videochiamata imminente
VIDEOPERIZIA_SUBSTATI = ("da_fissare", "fissata", "da_eseguire")


def is_valid_transition(from_state: str | None, to_state: str) -> bool:
    if from_state is None:
        return to_state == ClaimStatus.ISTRUZIONE.value
    allowed = VALID_TRANSITIONS.get(from_state)
    return allowed is not None and to_state in allowed
