"""
022 - seed dei prompt AI default globali

Popola `ai_prompt_templates` (tenant_id NULL = default globale) con le chiavi
note che le pipeline server useranno. I body sono placeholder che documentano
le variabili attese: vanno completati dagli admin o dai prossimi round di
porting da `PerxiaService.swift`.

Idempotente: usa INSERT ... ON CONFLICT DO NOTHING così girare la migration
più volte (o riapplicarla dopo aver editato i prompt da UI) non sovrascrive
nulla.
"""
from __future__ import annotations

import json
import uuid

from alembic import op
import sqlalchemy as sa


revision = "027"
down_revision = "026"
branch_labels = None
depends_on = None


# (key, title, description, body, variables)
_SEED: list[tuple[str, str, str, str, list[str]]] = [
    (
        "perizia.beni",
        "Perizia — estrazione beni",
        "Estrae l'elenco strutturato dei beni dal contesto del sinistro.",
        (
            "Sinistro: {ref}\n"
            "Dati strutturati: {beni_list}\n\n"
            "Estrai un elenco JSON dei beni danneggiati. Per ogni bene "
            "indica: descrizione, categoria, valore stimato.\n"
        ),
        ["ref", "beni_list"],
    ),
    (
        "perizia.danni",
        "Perizia — analisi danni",
        "Analizza i danni a partire da beni, foto e descrizione.",
        (
            "Sinistro: {ref}\n"
            "Beni: {beni}\n"
            "Descrizione danni dal perito: {descrizione}\n\n"
            "Produci un'analisi sintetica per ogni bene, indicando "
            "entità, causa, eventuale recuperabilità.\n"
        ),
        ["ref", "beni", "descrizione"],
    ),
    (
        "perizia.relazione",
        "Perizia — relazione finale",
        "Genera la relazione peritale finale per il sinistro.",
        (
            "Sinistro: {ref}\n"
            "Assicurato: {assicurato}\n"
            "Compagnia: {compagnia}\n"
            "Beni: {beni}\n"
            "Analisi danni: {analisi}\n\n"
            "Redigi la relazione peritale in italiano formale, sezioni: "
            "Premessa, Accertamenti, Quantificazione del danno, Conclusioni.\n"
        ),
        ["ref", "assicurato", "compagnia", "beni", "analisi"],
    ),
    (
        "perizia.descrizione_foto",
        "Perizia — descrizione foto",
        "Genera una descrizione testuale di una foto del sinistro.",
        (
            "Foto: {path}\n"
            "Bene associato: {bene}\n"
            "Componente: {componente}\n\n"
            "Descrivi sinteticamente cosa mostra la foto in relazione "
            "al danno, in italiano peritale.\n"
        ),
        ["path", "bene", "componente"],
    ),
    (
        "diario.summary",
        "Diario — riassunto entry",
        "Riassume una entry del diario in una frase.",
        (
            "Tipo entry: {entry_type}\n"
            "Titolo: {title}\n"
            "Corpo: {body}\n\n"
            "Riassumi in una sola frase utile per l'attività del perito.\n"
        ),
        ["entry_type", "title", "body"],
    ),
    (
        "diario.classification",
        "Diario — classificazione entry",
        "Classifica una entry del diario (categoria + sentiment).",
        (
            "Titolo: {title}\nCorpo: {body}\n\n"
            "Restituisci JSON: {{\"category\": ..., \"sentiment\": ..., \"urgency\": ...}}\n"
        ),
        ["title", "body"],
    ),
    (
        "diario.suggested_state",
        "Diario — stato suggerito",
        "Suggerisce la transizione di stato da applicare al sinistro.",
        (
            "Stato attuale: {stato_corrente}\n"
            "Entry: {title}\n{body}\n\n"
            "Suggerisci uno slug stato target tra quelli validi oppure null.\n"
        ),
        ["stato_corrente", "title", "body"],
    ),
    (
        "diario.suggested_tasks",
        "Diario — task suggerite",
        "Suggerisce task da creare in base al contenuto della entry.",
        (
            "Sinistro: {ref}\n"
            "Entry: {title}\n{body}\n\n"
            "Restituisci JSON lista di task: [{{\"title\": ..., \"description\": ..., \"priority\": ...}}]\n"
        ),
        ["ref", "title", "body"],
    ),
]


def upgrade() -> None:
    bind = op.get_bind()
    for key, title, description, body, variables in _SEED:
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
                "id": str(uuid.uuid4()),
                "key": key,
                "title": title,
                "description": description,
                "body": body,
                "variables": json.dumps(variables),
            },
        )


def downgrade() -> None:
    bind = op.get_bind()
    keys = [row[0] for row in _SEED]
    bind.execute(
        sa.text(
            "DELETE FROM ai_prompt_templates WHERE tenant_id IS NULL AND key = ANY(:keys)"
        ),
        {"keys": keys},
    )
