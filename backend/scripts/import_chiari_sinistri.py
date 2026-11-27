"""Importa le pratiche del JSON Chiari. Di default è una prova a vuoto.

    python scripts/import_chiari_sinistri.py
    python scripts/import_chiari_sinistri.py --apply

Non copia i file del dossier: conta solo i record. Le prove a vuoto non stampano nomi.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domain.chiari_import import map_claim, summarize
from scripts.bootstrap_chiari import TENANT_ID, _connection_params

DEFAULT_SOURCE = Path.home() / "Downloads" / "sinistri chiari" / "db" / "sinistri.json"


def load_mapped(path: Path, tenant_id: str) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("sinistri") if isinstance(payload, dict) else payload
    if not isinstance(rows, list):
        raise SystemExit("Il file non contiene l'elenco sinistri.")
    return [map_claim(tenant_id, row) for row in rows if isinstance(row, dict)]


def _when(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    if len(text) == 10:
        text = text + "T00:00:00+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


async def apply(mapped: list[dict], tenant_id: str) -> None:
    import asyncpg

    dsn, kwargs = _connection_params()
    conn = await asyncpg.connect(dsn, **kwargs)
    now = datetime.now(timezone.utc)
    claims = []
    workflows = []
    events = []
    revisions = []
    atti = []
    groups = []
    members = []
    seen_groups: set[str] = set()
    by_ref = {item["external_ref"]: item for item in mapped}
    try:
        for claim in mapped:
            claims.append((
                claim["id"], tenant_id, claim["external_ref"], claim["numero_sinistro"], claim["compagnia"],
                claim["stato_corrente"], claim["nome_assicurato"], claim["numero_polizza"], claim["agenzia"],
                claim["garanzia"], claim["richiesta"], claim["liquidato"], claim["danno_accertato"],
                _when(claim["data_sinistro"]), _when(claim["data_incarico"]), _when(claim["closed_at"]), now,
            ))
            workflow = claim["workflow"]
            workflows.append((
                claim["id"], tenant_id, workflow["salesforce_id"], workflow["company_claim_number"],
                workflow["ispettorato"], workflow["liquidatore"], workflow["salesforce_status"],
                workflow["closed_on"], workflow["outcome"], workflow["expected_close_on"],
                json.dumps(workflow["passages"]) if workflow["passages"] is not None else None,
                json.dumps(workflow["checks"]) if workflow["checks"] is not None else None,
                workflow["reclaim_model"],
            ))
            for index, event in enumerate(claim["events"]):
                events.append((
                    str(uuid.uuid5(uuid.NAMESPACE_URL, f"{claim['id']}:evento:{index}")),
                    tenant_id, claim["id"], event["event_type"], _when(event["event_time"]) or now,
                    json.dumps({"descrizione": event["description"]}),
                ))
            for revision in claim["revisions"]:
                revisions.append((
                    str(uuid.uuid5(uuid.NAMESPACE_URL, f"{claim['id']}:revisione:{revision['revision_number']}")),
                    tenant_id, claim["id"], revision["revision_number"],
                    json.dumps(revision["input_json"]), json.dumps(revision["calculation_json"]),
                    revision["calculation_hash"], revision["economic_hash"], revision["liquidabile"],
                    _when(revision["approved_at"]), _when(revision["updated_at"]) or now,
                ))
            for index, atto in enumerate(claim["atti"]):
                atti.append((
                    str(uuid.uuid5(uuid.NAMESPACE_URL, f"{claim['id']}:atto:{atto['kind']}:{index}")),
                    tenant_id, claim["id"], atto["kind"], atto.get("amount"),
                    _when(atto.get("sent_at")), _when(atto.get("signed_at")), atto.get("fingerprint"), now,
                ))
            for group in claim["groups"]:
                key = f"{group['kind']}:{group['external_key']}"
                if key in seen_groups:
                    continue
                seen_groups.add(key)
                group_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{tenant_id}:{key}"))
                groups.append((group_id, tenant_id, group["kind"], group["external_key"], group["reason"], now))
                for member_ref in group["members"]:
                    member = by_ref.get(member_ref)
                    if member is None:
                        continue
                    members.append((
                        str(uuid.uuid5(uuid.NAMESPACE_URL, f"{group_id}:{member['id']}")),
                        tenant_id, group_id, member["id"],
                    ))
        async with conn.transaction():
            await conn.executemany(
                """
                INSERT INTO claims (
                    id, tenant_id, external_ref, numero_sinistro, compagnia, stato_corrente,
                    nome_assicurato, numero_polizza, agenzia, garanzia, richiesta, liquidato,
                    danno_accertato, data_sinistro, data_incarico, closed_at, created_at, updated_at,
                    priority, version, iban, sinistro_collegato, sopralluogo, giustificativi,
                    foto, oltre_dieci_beni, concordata, negativa, ubicazione_validata
                )
                VALUES (
                    $1, $2, $3, $4, $5, $6,
                    $7, $8, $9, $10, $11, $12,
                    $13, $14, $15, $16, $17, $17,
                    0, 1, false, false, false, false,
                    false, false, false, false, false
                )
                ON CONFLICT (id) DO UPDATE SET
                    stato_corrente = EXCLUDED.stato_corrente,
                    nome_assicurato = EXCLUDED.nome_assicurato,
                    numero_sinistro = EXCLUDED.numero_sinistro,
                    numero_polizza = EXCLUDED.numero_polizza,
                    liquidato = EXCLUDED.liquidato,
                    danno_accertato = EXCLUDED.danno_accertato,
                    closed_at = EXCLUDED.closed_at,
                    updated_at = EXCLUDED.updated_at
                """,
                claims,
            )
            await conn.executemany(
                """
                INSERT INTO claim_workflows (
                    claim_id, tenant_id, salesforce_id, company_claim_number, ispettorato,
                    liquidatore, salesforce_status, closed_on, outcome, expected_close_on,
                    passages_json, checks_json, reclaim_model
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::json, $12::json, $13)
                ON CONFLICT (claim_id) DO UPDATE SET
                    salesforce_id = EXCLUDED.salesforce_id,
                    salesforce_status = EXCLUDED.salesforce_status,
                    closed_on = EXCLUDED.closed_on,
                    outcome = EXCLUDED.outcome,
                    reclaim_model = EXCLUDED.reclaim_model,
                    passages_json = EXCLUDED.passages_json,
                    checks_json = EXCLUDED.checks_json
                """,
                workflows,
            )
            await conn.executemany(
                """
                INSERT INTO claim_events (id, tenant_id, claim_id, event_type, event_time, data_json, source)
                VALUES ($1, $2, $3, $4, $5, $6::json, 'import_chiari')
                ON CONFLICT (id) DO NOTHING
                """,
                events,
            )
            await conn.executemany(
                """
                INSERT INTO claim_estimate_revisions (
                    id, tenant_id, claim_id, revision_number, input_json, calculation_json,
                    calculation_hash, economic_hash, liquidabile, approved_at, created_at
                )
                VALUES ($1, $2, $3, $4, $5::json, $6::json, $7, $8, $9, $10, $11)
                ON CONFLICT (claim_id, revision_number) DO UPDATE SET
                    economic_hash = EXCLUDED.economic_hash,
                    liquidabile = EXCLUDED.liquidabile,
                    approved_at = COALESCE(claim_estimate_revisions.approved_at, EXCLUDED.approved_at)
                """,
                revisions,
            )
            await conn.executemany(
                """
                INSERT INTO claim_atti (
                    id, tenant_id, claim_id, kind, amount, sent_at, signed_at, fingerprint, created_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                ON CONFLICT (id) DO NOTHING
                """,
                atti,
            )
            if groups:
                await conn.executemany(
                    """
                    INSERT INTO claim_groups (id, tenant_id, kind, external_key, reason, created_at)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (tenant_id, kind, external_key) DO UPDATE SET reason = EXCLUDED.reason
                    """,
                    groups,
                )
            if members:
                await conn.executemany(
                    """
                    INSERT INTO claim_group_members (id, tenant_id, group_id, claim_id)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (group_id, claim_id) DO NOTHING
                    """,
                    members,
                )
    finally:
        await conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Import pratiche Chiari")
    parser.add_argument("--source", default=str(DEFAULT_SOURCE))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    path = Path(args.source)
    if not path.is_file():
        raise SystemExit(f"File non trovato: {path}")
    mapped = load_mapped(path, TENANT_ID)
    print(json.dumps(summarize(mapped), ensure_ascii=False, indent=2))
    if not args.apply:
        print("Prova a vuoto: nessuna scrittura. I documenti restano nella cartella locale.")
        return
    asyncio.run(apply(mapped, TENANT_ID))
    print("Import scritto sul tenant chiari. I file del dossier non sono stati copiati.")


if __name__ == "__main__":
    main()
