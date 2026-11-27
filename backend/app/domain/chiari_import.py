"""Mappatura pura di una pratica del JSON Chiari verso i record PerX.

Non legge file e non scrive sul database: l'importatore e i test la usano.
"""
from __future__ import annotations

import uuid
from decimal import Decimal, InvalidOperation
from typing import Any

from app.domain.chiari_stima import hash_calcolo, hash_economico, liquidabile_di


def _decimal(value: Any) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def _text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def claim_id_for(tenant_id: str, riferimento: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"perx:{tenant_id}:chiari:{riferimento}"))


def map_claim(tenant_id: str, raw: dict) -> dict[str, Any]:
    riferimento = _text(raw.get("rif_chiari")) or _text(raw.get("rif"))
    if not riferimento:
        raise ValueError("Pratica senza riferimento Chiari")
    assicurato = raw.get("assicurato")
    nome = assicurato if isinstance(assicurato, str) else None
    if isinstance(assicurato, dict):
        nome = assicurato.get("nome") or assicurato.get("denominazione")
    stato = _text(raw.get("stato")) or "DA_LAVORARE"
    return {
        "id": claim_id_for(tenant_id, riferimento),
        "tenant_id": tenant_id,
        "external_ref": riferimento,
        "numero_sinistro": _text(raw.get("numero")) or _text(raw.get("numero_sinistro")) or _text(raw.get("n_compagnia")),
        "compagnia": _text(raw.get("compagnia")) or "Vittoria",
        "stato_corrente": stato,
        "nome_assicurato": _text(nome),
        "numero_polizza": _text(raw.get("polizza")) or _text(raw.get("numero_polizza")) or _text(raw.get("polizza_n")),
        "agenzia": _text(raw.get("agenzia")),
        "garanzia": "Fenomeno Elettrico",
        "richiesta": _importo(raw, ("importo_richiesto", "richiesta"), ("richiesta", "richiesta_sinistro")),
        "liquidato": _importo(raw, ("danno_liquidato", "importo_atto"), ("liquidabile",)),
        "danno_accertato": _importo(raw, ("danno_accertato", "importo_danno_accertato"), ("danno_accertato",)),
        "data_sinistro": _text(raw.get("data_evento") or raw.get("data_sinistro")),
        "data_incarico": _text(raw.get("data_incarico")),
        "closed_at": _text(raw.get("data_chiusura")) if stato == "CHIUSO" else None,
        "workflow": {
            "salesforce_id": _text(raw.get("id_salesforce") or raw.get("sf_id")),
            "company_claim_number": _text(raw.get("numero") or raw.get("numero_compagnia") or raw.get("n_compagnia")),
            "ispettorato": _text(raw.get("ispettorato")),
            "liquidatore": _text(raw.get("liquidatore")),
            "salesforce_status": _text(raw.get("stato_sf")),
            "closed_on": _text(raw.get("chiuso_su")),
            "outcome": _text(raw.get("esito_chiusura") or raw.get("esito")),
            "expected_close_on": _text(raw.get("chiusura_prevista")),
            "passages": raw.get("passaggi") if isinstance(raw.get("passaggi"), (dict, list)) else None,
            "checks": raw.get("controlli") if isinstance(raw.get("controlli"), (dict, list)) else None,
            "reclaim_model": _text(raw.get("modello_reclaim")),
        },
        "events": _events(raw),
        "revisions": _revisions(raw),
        "atti": _atti(raw),
        "groups": _groups(riferimento, raw),
    }


def _totali(raw: dict) -> dict:
    stima = raw.get("stima_deterministica")
    calcolo = stima.get("calcolo") if isinstance(stima, dict) else None
    totali = calcolo.get("totali") if isinstance(calcolo, dict) else None
    return totali if isinstance(totali, dict) else {}


def _importo(raw: dict, fields: tuple[str, ...], totali_keys: tuple[str, ...]) -> Decimal | None:
    for field in fields:
        amount = _decimal(raw.get(field))
        if amount is not None:
            return amount
    totali = _totali(raw)
    for key in totali_keys:
        amount = _decimal(totali.get(key))
        if amount is not None:
            return amount
    calcolo = raw.get("stima_deterministica")
    calcolo = calcolo.get("calcolo") if isinstance(calcolo, dict) else None
    if isinstance(calcolo, dict) and "richiesta_sinistro" in totali_keys:
        return _decimal(calcolo.get("richiesta_sinistro"))
    return None


def _events(raw: dict) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for item in raw.get("eventi") or []:
        if not isinstance(item, dict):
            continue
        events.append(
            {
                "event_type": _text(item.get("tipo")) or "nota",
                "event_time": _text(item.get("data")),
                "description": _text(item.get("descrizione")),
            }
        )
    when = _text(raw.get("data_chiusura")) or _text(raw.get("stato_da"))
    for key in ("note", "note_sf"):
        text = _text(raw.get(key))
        if text:
            events.append({"event_type": "nota", "event_time": when, "description": text})
    for revision in _revisions(raw):
        if revision["liquidabile"] is None:
            continue
        events.append(
            {
                "event_type": "stima",
                "event_time": revision["updated_at"] or revision["approved_at"] or when,
                "description": (
                    f"Revisione {revision['revision_number']}: "
                    f"liquidabile {revision['liquidabile']}"
                ),
            }
        )
    return events


def _revision_record(item: dict) -> dict[str, Any] | None:
    calcolo = item.get("calcolo") if isinstance(item.get("calcolo"), dict) else {}
    approvazione = item.get("approvazione") if isinstance(item.get("approvazione"), dict) else {}
    number = item.get("revisione")
    if not isinstance(number, int):
        return None
    approved_revision = approvazione.get("revisione")
    return {
        "revision_number": number,
        "input_json": item.get("input") if isinstance(item.get("input"), dict) else {},
        "calculation_json": calcolo,
        "calculation_hash": hash_calcolo(calcolo) or _text(approvazione.get("hash_calcolo")),
        "economic_hash": _text(approvazione.get("hash_economico")) or hash_economico(calcolo),
        "liquidabile": liquidabile_di(calcolo),
        "approved": approved_revision == number and bool(approvazione.get("data")),
        "approved_at": _text(approvazione.get("data")) if approved_revision == number else None,
        "approved_by_label": _text(approvazione.get("da")) if approved_revision == number else None,
        "updated_at": _text(item.get("aggiornata_il")),
    }


def _revisions(raw: dict) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for item in raw.get("stime_precedenti") or []:
        if isinstance(item, dict):
            mapped = _revision_record(item)
            if mapped:
                records.append(mapped)
    current = raw.get("stima_deterministica")
    if isinstance(current, dict):
        mapped = _revision_record(current)
        if mapped:
            records.append(mapped)
    records.sort(key=lambda row: row["revision_number"])
    return records


def _atti(raw: dict) -> list[dict[str, Any]]:
    atti: list[dict[str, Any]] = []
    for item in raw.get("atti_inviati") or []:
        if not isinstance(item, dict):
            continue
        atti.append(
            {
                "kind": "inviato",
                "amount": _decimal(item.get("importo")),
                "sent_at": _text(item.get("ora")),
                "fingerprint": _text(item.get("impronta")),
            }
        )
    firmato = raw.get("atto_firmato")
    if isinstance(firmato, dict):
        atti.append(
            {
                "kind": "firmato",
                "amount": _decimal(firmato.get("importo")),
                "signed_at": _text(firmato.get("data")),
                "outcome": _text(firmato.get("esito")),
                "revision_number": firmato.get("revisione") if isinstance(firmato.get("revisione"), int) else None,
            }
        )
    return atti


def _groups(riferimento: str, raw: dict) -> list[dict[str, Any]]:
    groups: list[dict[str, Any]] = []
    for key, kind in (("collegati", "collegati"), ("riapertura", "riapertura")):
        block = raw.get(key)
        if not isinstance(block, dict):
            continue
        members = [item for item in (block.get("sinistri") or []) if isinstance(item, str) and item.strip()]
        if riferimento not in members:
            members.append(riferimento)
        groups.append(
            {
                "kind": kind,
                "external_key": _text(block.get("gruppo")) or f"{kind}:{riferimento}",
                "reason": _text(block.get("motivo")),
                "members": members,
            }
        )
    return groups


def summarize(mapped: list[dict[str, Any]]) -> dict[str, Any]:
    by_state: dict[str, int] = {}
    revisions = 0
    atti = 0
    groups = 0
    for claim in mapped:
        state = claim["stato_corrente"]
        by_state[state] = by_state.get(state, 0) + 1
        revisions += len(claim["revisions"])
        atti += len(claim["atti"])
        groups += len(claim["groups"])
    return {
        "pratiche": len(mapped),
        "per_stato": dict(sorted(by_state.items())),
        "revisioni": revisions,
        "atti": atti,
        "gruppi": groups,
    }
