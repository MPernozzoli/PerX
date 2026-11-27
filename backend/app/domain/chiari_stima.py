"""Profilo Chiari del motore di stima.

Selezione del modello ReClaim e impronta economica, portate da ``stima.py``.
Gli importi restano nel motore deterministico; qui si decide solo il modello e
se due revisioni sono la stessa economia.
"""
from __future__ import annotations

import hashlib
import json
from decimal import Decimal
from typing import Any

SOGLIA_OVER = Decimal("5000")

_VOCE_ECO = (
    "quantita",
    "importo_unitario",
    "valore_complessivo",
    "miglioria_deprezzamento_percentuale",
    "miglioria_deprezzamento_importo",
    "richiesta",
    "ammessa",
    "iva_riconosciuta",
    "aliquota_iva",
    "imponibile",
    "iva",
    "totale_ammesso",
)
_LIQ_ECO = (
    "garanzia_id",
    "danno_accertato",
    "tipo_trattenuta",
    "trattenuta",
    "dopo_trattenuta",
    "massimale",
    "liquidabile",
    "totale_voci",
    "arrotondamento",
)


def workflow_reclaim(
    liquidabile: Decimal,
    *,
    esito: str = "",
    reclaim_over: bool = False,
    reclaim_assente: bool = False,
) -> dict[str, Any]:
    """Light fino a 5.000,00. Over da 5.000,01 e per le non concordate.

    Liquidabile zero o esito negativo: Sopralluogo Senza stima, anche se
    l'esito sarebbe stato Over. Il sinistro assente su ReClaim non si compila,
    e la relazione Salesforce si genera comunque.
    """
    esito_norm = (esito or "").strip().upper()
    negativa = esito_norm == "NEGATIVO"
    non_concordata = esito_norm == "NON_CONCORDATO"
    over = liquidabile > SOGLIA_OVER or non_concordata or bool(reclaim_over)
    senza_stima = negativa or liquidabile == 0
    if senza_stima:
        over = False
    relazione_sf = over or negativa or non_concordata or bool(reclaim_assente) or senza_stima
    if senza_stima:
        modello = "Sopralluogo Senza stima"
    elif over:
        modello = "Over"
    else:
        modello = "Light"
    return {
        "soglia_over": float(SOGLIA_OVER),
        "reclaim": {"modello": modello, "compilare": not bool(reclaim_assente)},
        "salesforce": {"genera_relazione": relazione_sf, "allega_relazione": relazione_sf},
    }


def _liq_economica(row: dict) -> dict:
    out = {key: row.get(key) for key in _LIQ_ECO}
    partite = row.get("partite") or []
    if any(isinstance(item, dict) and item.get("limitata") for item in partite):
        out["partite"] = [
            {
                key: item.get(key)
                for key in ("partita_id", "danno_accertato", "somma_assicurata", "limitata", "liquidabile")
            }
            for item in partite
            if isinstance(item, dict)
        ]
        out["limite_partite"] = row.get("limite_partite")
    return out


def impronta_economica(calcolo: dict | None) -> dict:
    calcolo = calcolo or {}
    selezione = calcolo.get("selezione_allegati") or {}
    esito = selezione.get("esito") or ""
    impronta: dict[str, Any] = {
        "esito": esito if esito in ("NEGATIVO", "NON_CONCORDATO") else "POSITIVO",
        "danno_non_accertato": bool(selezione.get("danno_non_accertato")),
        "modello_reclaim": ((calcolo.get("workflow") or {}).get("reclaim") or {}).get("modello"),
        "richiesta_sinistro": calcolo.get("richiesta_sinistro"),
        "totali": calcolo.get("totali"),
        "arrotondamento": calcolo.get("arrotondamento"),
        "garanzie": [
            {
                key: row.get(key)
                for key in (
                    "id",
                    "massimale",
                    "franchigia",
                    "scoperto_percentuale",
                    "scoperto_minimo",
                    "scoperto_massimo",
                )
            }
            for row in calcolo.get("garanzie") or []
            if isinstance(row, dict)
        ],
        "liquidazioni": [_liq_economica(row) for row in calcolo.get("liquidazioni") or [] if isinstance(row, dict)],
        "beni": [
            {
                "partita_id": bene.get("partita_id"),
                "garanzia_id": bene.get("garanzia_id"),
                "richiesta": bene.get("richiesta"),
                "richiesta_effettiva": bene.get("richiesta_effettiva"),
                "totale_ammesso": bene.get("totale_ammesso"),
                "comune": bene.get("comune"),
                "voci": [
                    {key: voce.get(key) for key in _VOCE_ECO}
                    for voce in (bene.get("componenti") or [])
                    if isinstance(voce, dict)
                ],
            }
            for bene in calcolo.get("beni") or []
            if isinstance(bene, dict)
        ],
    }
    if calcolo.get("riparto_1910"):
        impronta["riparto_1910"] = calcolo.get("riparto_1910")
    return impronta


def hash_economico(calcolo: dict | None) -> str:
    payload = json.dumps(
        impronta_economica(calcolo),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def hash_calcolo(calcolo: dict | None) -> str | None:
    if not isinstance(calcolo, dict):
        return None
    stored = calcolo.get("hash_calcolo")
    return stored if isinstance(stored, str) and stored else None


def liquidabile_di(calcolo: dict | None) -> Decimal | None:
    totali = (calcolo or {}).get("totali") if isinstance(calcolo, dict) else None
    if not isinstance(totali, dict) or totali.get("liquidabile") is None:
        return None
    return Decimal(str(totali["liquidabile"]))
