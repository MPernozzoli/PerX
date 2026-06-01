"""
033 - Seed default sinistri AI: prompt 'sinistri.tagging' + routing policy.

Estrae il prompt di tagging foto da AutoTaggingService.swift
(buildBatchAnalysisPrompt, righe ~1414-1533) e lo registra come default
globale `sinistri.tagging`. Crea anche la prima riga immutabile in
ai_prompt_template_versions e aggiorna current_version_id.

Seed matrice routing policy default (tenant_id NULL = globale) per le 5 fasi
del flusso sinistri × 3 trigger (user_initiated, background, regenerate),
secondo la regola:
  - immagini + user_initiated  -> prefer_cloud (velocita UX)
  - immagini + background      -> prefer_local (no spreco budget cloud)
  - solo testo + qualsiasi     -> prefer_local (fallback cloud su output malformato)
  - regenerate qualsiasi       -> cloud_only (utente non soddisfatto del locale)

Idempotente: ON CONFLICT DO NOTHING su tutte le insert.
"""
from __future__ import annotations

import hashlib
import json
import uuid

from alembic import op
import sqlalchemy as sa


revision = "033_seed_sinistri_ai"
down_revision = "032_ai_prompt_versioning"
branch_labels = None
depends_on = None


# ---------------------------------------------------------------------------#
# Prompt tagging
# ---------------------------------------------------------------------------#

_TAGGING_KEY = "sinistri.tagging"
_TAGGING_TITLE = "Sinistri — tagging foto (batch)"
_TAGGING_DESCRIPTION = (
    "Classifica le foto del sinistro: tipo (bene/componente/ubicazione/test/"
    "documento), bene di riferimento, qualita, decisione 'da allegare'. NON "
    "produce analisi approfondite — quelle sono fase 1 Perxia."
)
_TAGGING_VARIABLES = ["n_foto", "file_list", "context_section", "tag_list"]

# Prompt estratto da AutoTaggingService.buildBatchAnalysisPrompt.
# Variabili in stile str.format (singole graffe): {n_foto}, {file_list},
# {context_section}, {tag_list}. context_section puo essere stringa vuota.
_TAGGING_BODY = """COMPITO: Classifica queste {n_foto} foto per un sistema di tagging automatico. NON fare analisi approfondite, solo classificazione.

FOTO DA CLASSIFICARE:
{file_list}
{context_section}

⛔ COSA NON FARE:
- NON estrarre dettagli tecnici (marca, modello, specifiche)
- NON fare analisi approfondite del contenuto
- NON descrivere in dettaglio cosa vedi
- NON usare chiavi come "analisi_documento", "dettagli_tecnici", "immagini"

✅ COSA FARE:
- Identifica il TIPO di foto (bene, componente, ubicazione, documento, test)
- Identifica il BENE (solo nome generico, es. "caldaia" non "Ignis AFE 941")
- Identifica il COMPONENTE se presente (solo nome, es. "scheda elettronica")
- Valuta la QUALITÀ visiva
- Decidi se ALLEGARE (true se rappresentativa, false se duplicata/dettaglio)

REGOLE IMPORTANTI:
1. BENE = impianto completo (caldaia, cancello, fotovoltaico) - SOLO NOME, NO MARCA/MODELLO
2. COMPONENTE = parte del bene (scheda, motore, varistore) - SOLO NOME, NO MARCA/MODELLO
3. BENE RIFERIMENTO OBBLIGATORIO per:
   - foto_componente: DEVI sempre indicare il bene a cui appartiene il componente
   - foto_test_funzionale: DEVI sempre indicare il bene su cui è stato fatto il test
   - test_strumentale: DEVI sempre indicare il bene su cui è stato fatto il test
   - foto_ripristino: DEVI sempre indicare il bene che è stato riparato
4. UBICAZIONE: identifica il tipo corretto:
   - "foto_ubicazione_rischio": ubicazione del rischio assicurato (esterno, stabile, indirizzo)
   - "foto_ubicazione_tecnico": ubicazione tecnica del bene/impianto (locale tecnico, box, garage)
   - "foto_ubicazione_amministratore": ubicazione amministratore (sede amministrativa, uffici)
   - "foto_ubicazione_altra": altra ubicazione non classificabile nelle precedenti
5. DOCUMENTI: identifica se fattura, preventivo, atto
6. QUALITÀ: "buona" (nitida), "media" (accettabile), "scarsa" (sfocata), "irrilevante"

TAG DISPONIBILI: {tag_list}

FORMATO RISPOSTA (JSON OBBLIGATORIO):
{{
    "results": [
        {{
            "filename": "1000136694.jpg",
            "tipo": "foto_bene",
            "tagSuggerito": "foto_bene",
            "beneRiferimento": "caldaia",
            "componente": null,
            "descrizione": "Foto caldaia",
            "qualita": "buona",
            "daAllegare": true,
            "confidenza": 0.9
        }},
        {{
            "filename": "test_funzionale.jpg",
            "tipo": "foto_test_funzionale",
            "tagSuggerito": "foto_test_funzionale",
            "beneRiferimento": "caldaia",
            "componente": null,
            "descrizione": "Test funzionale caldaia",
            "qualita": "buona",
            "daAllegare": true,
            "confidenza": 0.9
        }},
        {{
            "filename": "test_strumentale.jpg",
            "tipo": "test_strumentale",
            "tagSuggerito": "test_strumentale",
            "beneRiferimento": "caldaia",
            "componente": null,
            "descrizione": "Test strumentale caldaia",
            "qualita": "buona",
            "daAllegare": true,
            "confidenza": 0.9
        }},
        {{
            "filename": "componente.jpg",
            "tipo": "foto_componente",
            "tagSuggerito": "foto_componente",
            "beneRiferimento": "caldaia",
            "componente": "scheda elettronica",
            "descrizione": "Scheda elettronica caldaia",
            "qualita": "buona",
            "daAllegare": true,
            "confidenza": 0.9
        }}
    ]
}}

⚠️ RISPOSTA: Solo JSON con chiave "results" contenente array. Ogni oggetto DEVE avere "filename".
⚠️ IMPORTANTE: Per foto_componente, foto_test_funzionale, test_strumentale e foto_ripristino, il campo "beneRiferimento" è OBBLIGATORIO (non può essere null).
"""


# ---------------------------------------------------------------------------#
# Routing policy default
# ---------------------------------------------------------------------------#

# (phase, trigger, mode)
_ROUTING_SEED: list[tuple[str, str, str]] = [
    # tagging — immagini
    ("sinistri.tagging", "user_initiated", "prefer_cloud"),
    ("sinistri.tagging", "background",     "prefer_local"),
    ("sinistri.tagging", "regenerate",     "cloud_only"),
    # fase 1 approfondita — immagini + testo
    ("sinistri.fase1_approfondita", "user_initiated", "prefer_cloud"),
    ("sinistri.fase1_approfondita", "background",     "prefer_local"),
    ("sinistri.fase1_approfondita", "regenerate",     "cloud_only"),
    # parse denuncia/giustificativi — solo testo
    ("sinistri.parse_denuncia", "user_initiated", "prefer_local"),
    ("sinistri.parse_denuncia", "background",     "prefer_local"),
    ("sinistri.parse_denuncia", "regenerate",     "cloud_only"),
    # raggruppamento beni — solo testo
    ("sinistri.raggruppamento", "user_initiated", "prefer_local"),
    ("sinistri.raggruppamento", "background",     "prefer_local"),
    ("sinistri.raggruppamento", "regenerate",     "cloud_only"),
    # relazione finale — solo testo, output critico ma con template strutturato
    ("sinistri.relazione", "user_initiated", "prefer_cloud"),
    ("sinistri.relazione", "background",     "prefer_local"),
    ("sinistri.relazione", "regenerate",     "cloud_only"),
]


def _short_version_id(template_id: str, body: str) -> str:
    h = hashlib.sha1(f"{template_id}\x00{body}".encode("utf-8")).hexdigest()
    return h[:8]


def upgrade() -> None:
    bind = op.get_bind()

    # --- prompt 'sinistri.tagging' ---
    template_id = str(uuid.uuid4())
    bind.execute(
        sa.text(
            """
            INSERT INTO ai_prompt_templates
              (id, tenant_id, key, title, description, body, variables_json, version)
            VALUES
              (:id, NULL, :key, :title, :description, :body, CAST(:variables AS JSON), 1)
            ON CONFLICT (tenant_id, key) DO NOTHING
            """
        ),
        {
            "id": template_id,
            "key": _TAGGING_KEY,
            "title": _TAGGING_TITLE,
            "description": _TAGGING_DESCRIPTION,
            "body": _TAGGING_BODY,
            "variables": json.dumps(_TAGGING_VARIABLES),
        },
    )

    # Se il template esisteva gia (ON CONFLICT DO NOTHING ha skippato), recupera
    # l'id reale per la version. Altrimenti usa quello generato sopra.
    real_id = bind.execute(
        sa.text(
            "SELECT id, body FROM ai_prompt_templates "
            "WHERE tenant_id IS NULL AND key = :key"
        ),
        {"key": _TAGGING_KEY},
    ).fetchone()
    if real_id is None:
        # Edge: insert riuscito ma race; abort senza errore
        return
    template_id_real, body_real = real_id[0], real_id[1]
    version_id = _short_version_id(template_id_real, body_real or "")

    bind.execute(
        sa.text(
            """
            INSERT INTO ai_prompt_template_versions
              (id, template_id, version_id, body, variables_json, changelog)
            VALUES
              (:id, :template_id, :version_id, :body, CAST(:variables AS JSON), :changelog)
            ON CONFLICT (template_id, version_id) DO NOTHING
            """
        ),
        {
            "id": str(uuid.uuid4()),
            "template_id": template_id_real,
            "version_id": version_id,
            "body": body_real or "",
            "variables": json.dumps(_TAGGING_VARIABLES),
            "changelog": "seed migration 031 (porting da AutoTaggingService.swift)",
        },
    )
    bind.execute(
        sa.text(
            "UPDATE ai_prompt_templates SET current_version_id = :v WHERE id = :id"
        ),
        {"v": version_id, "id": template_id_real},
    )

    # --- routing policy default globale ---
    for phase, trigger, mode in _ROUTING_SEED:
        bind.execute(
            sa.text(
                """
                INSERT INTO ai_routing_policy
                  (id, tenant_id, phase, trigger, mode)
                VALUES
                  (:id, NULL, :phase, :trigger, :mode)
                ON CONFLICT (tenant_id, phase, trigger) DO NOTHING
                """
            ),
            {
                "id": str(uuid.uuid4()),
                "phase": phase,
                "trigger": trigger,
                "mode": mode,
            },
        )


def downgrade() -> None:
    bind = op.get_bind()
    # routing
    bind.execute(
        sa.text(
            "DELETE FROM ai_routing_policy "
            "WHERE tenant_id IS NULL AND phase = ANY(:phases)"
        ),
        {"phases": list({p for p, _, _ in _ROUTING_SEED})},
    )
    # template (cascade su versions)
    bind.execute(
        sa.text(
            "DELETE FROM ai_prompt_templates WHERE tenant_id IS NULL AND key = :key"
        ),
        {"key": _TAGGING_KEY},
    )
