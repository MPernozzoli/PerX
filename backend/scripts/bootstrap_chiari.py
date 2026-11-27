"""Crea o aggiorna il tenant Chiari, un solo perito, senza portale e senza dispatcher.

Esempio, prova a vuoto:
    python scripts/bootstrap_chiari.py --perito-email perito@chiarisrl.it --perito-name "Nome Cognome" --dry-run

Scrittura sul database configurato in DATABASE_URL:
    python scripts/bootstrap_chiari.py --perito-email perito@chiarisrl.it --perito-name "Nome Cognome" --apply
"""
from __future__ import annotations

import argparse
import asyncio
import json
import ssl
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import asyncpg

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import settings
from app.core.security import get_password_hash
from app.domain.chiari_rules import extract_dated_rules
from app.domain.chiari_states import CHIARI_STATES
from app.domain.tenant_capabilities import chiari_settings

TENANT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, "perx:tenant:chiari"))
DEFAULT_RULES = Path.home() / "Downloads" / "sinistri chiari" / "CLAUDE.md"

CODED_RULES = (
    ("L'approvazione di una revisione la fa solo il perito.", "approvazione"),
    ("Una revisione con la stessa impronta economica eredita l'approvazione.", "impronta"),
    ("Nessun liquidabile sotto un importo già proposto, salvo eccezione del perito.", "importo"),
    ("Un cambio di IBAN o un beneficiario terzo apre una questione.", "iban"),
    ("Un solo lavoro aperto per pratica e un solo lavoro alla volta su Chrome.", "lavoro"),
    ("I sinistri collegati non si eseguono finché tutte le stime del gruppo non sono approvate.", "collegati"),
    ("Lo stato scelto dal perito durante un lavoro non viene sovrascritto.", "stato"),
)


def _connection_params() -> tuple[str, dict]:
    url = settings.DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://", 1)
    parsed = urlsplit(url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    ssl_mode = query.pop("ssl", None) or query.pop("sslmode", None)
    normalized = urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(query), parsed.fragment))
    if not ssl_mode or ssl_mode.lower() in {"false", "disable"}:
        return normalized, {}
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return normalized, {"ssl": context}


def _rules(path: Path | None) -> list[dict[str, str]]:
    rules = [
        {
            "body": body,
            "rule_type": "codificata",
            "author": "perito",
            "origin_label": label,
        }
        for body, label in CODED_RULES
    ]
    if path and path.is_file():
        rules.extend(extract_dated_rules(path.read_text(encoding="utf-8")))
    return rules


async def _apply(args: argparse.Namespace, tenant_settings: dict, rules: list[dict[str, str]]) -> None:
    email = args.perito_email.lower()
    password_hash = get_password_hash(args.password) if args.password else None
    now = datetime.now(timezone.utc)
    dsn, connect_kwargs = _connection_params()
    conn = await asyncpg.connect(dsn, **connect_kwargs)
    try:
        async with conn.transaction():
            existing_tenant = await conn.fetchval(
                "SELECT id FROM tenants WHERE slug = 'chiari' OR id = $1",
                TENANT_ID,
            )
            tenant_id = existing_tenant or TENANT_ID
            if existing_tenant:
                await conn.execute(
                    "UPDATE tenants SET name = $2, slug = 'chiari', settings_json = $3::json WHERE id = $1",
                    tenant_id,
                    "Chiari S.r.l.",
                    json.dumps(tenant_settings),
                )
            else:
                await conn.execute(
                    """
                    INSERT INTO tenants (id, name, slug, settings_json, created_at)
                    VALUES ($1, $2, 'chiari', $3::json, $4)
                    """,
                    tenant_id,
                    "Chiari S.r.l.",
                    json.dumps(tenant_settings),
                    now,
                )
            role_id = await conn.fetchval(
                "SELECT id FROM roles WHERE tenant_id = $1 AND name = 'perito' LIMIT 1",
                tenant_id,
            )
            if not role_id:
                role_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "perx:role:chiari:perito"))
                await conn.execute(
                    "INSERT INTO roles (id, tenant_id, name, description) VALUES ($1, $2, 'perito', 'Perito')",
                    role_id,
                    tenant_id,
                )
            user_id = await conn.fetchval(
                "SELECT id FROM users WHERE email = $1 OR personal_email = $1 LIMIT 1",
                email,
            )
            parts = args.perito_name.strip().split(None, 1)
            first_name = parts[0]
            last_name = parts[1] if len(parts) > 1 else ""
            if user_id:
                await conn.execute(
                    """
                    UPDATE users
                    SET tenant_id = $2, email = $3, personal_email = $3, full_name = $4,
                        first_name = $5, last_name = $6,
                        password_hash = COALESCE($7, password_hash),
                        is_active = true, is_platform_admin = false
                    WHERE id = $1
                    """,
                    user_id,
                    tenant_id,
                    email,
                    args.perito_name.strip(),
                    first_name,
                    last_name,
                    password_hash,
                )
            else:
                user_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"perx:user:chiari:{email}"))
                await conn.execute(
                    """
                    INSERT INTO users (
                        id, tenant_id, email, personal_email, full_name, first_name, last_name,
                        password_hash, is_active, is_platform_admin, settings_json, created_at
                    )
                    VALUES ($1, $2, $3, $3, $4, $5, $6, $7, true, false, CAST('{}' AS json), $8)
                    """,
                    user_id,
                    tenant_id,
                    email,
                    args.perito_name.strip(),
                    first_name,
                    last_name,
                    password_hash,
                    now,
                )
            await conn.execute(
                """
                INSERT INTO user_roles (user_id, role_id)
                VALUES ($1, $2)
                ON CONFLICT DO NOTHING
                """,
                user_id,
                role_id,
            )
            for state in CHIARI_STATES:
                await conn.execute(
                    """
                    INSERT INTO tenant_claim_states (
                        id, tenant_id, code, label, description, actor, is_meta, sort_order, active
                    )
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true)
                    ON CONFLICT (tenant_id, code) DO UPDATE
                    SET label = EXCLUDED.label,
                        description = EXCLUDED.description,
                        actor = EXCLUDED.actor,
                        is_meta = EXCLUDED.is_meta,
                        sort_order = EXCLUDED.sort_order,
                        active = true
                    """,
                    str(uuid.uuid5(uuid.NAMESPACE_URL, f"perx:chiari:stato:{state['code']}")),
                    tenant_id,
                    state["code"],
                    state["label"],
                    state["description"],
                    state["actor"],
                    state["is_meta"],
                    state["sort_order"],
                )
            for index, rule in enumerate(rules):
                await conn.execute(
                    """
                    INSERT INTO tenant_rules (
                        id, tenant_id, body, rule_type, author, origin_label, status, version, created_at
                    )
                    VALUES ($1, $2, $3, $4, $5, $6, 'attiva', 1, $7)
                    ON CONFLICT (id) DO UPDATE
                    SET body = EXCLUDED.body, status = 'attiva'
                    """,
                    str(uuid.uuid5(uuid.NAMESPACE_URL, f"perx:chiari:regola:{index}:{rule['origin_label']}")),
                    tenant_id,
                    rule["body"],
                    rule["rule_type"],
                    rule.get("author"),
                    rule.get("origin_label"),
                    now,
                )
    finally:
        await conn.close()
    print(f"Tenant chiari pronto ({tenant_id}), perito {email}, regole {len(rules)}.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Bootstrap del tenant Chiari")
    parser.add_argument("--perito-email", required=True)
    parser.add_argument("--perito-name", required=True)
    parser.add_argument("--allowed-domain", action="append", default=[])
    parser.add_argument("--password", default="")
    parser.add_argument("--rules-file", default=str(DEFAULT_RULES))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    email = args.perito_email.strip().lower()
    if "@" not in email:
        raise SystemExit("L'email del perito non è valida.")
    domains = [item.strip().lower() for item in args.allowed_domain if item.strip()]
    email_domain = email.rsplit("@", 1)[-1]
    if email_domain not in domains:
        domains.append(email_domain)
    if "chiarisrl.it" not in domains:
        domains.append("chiarisrl.it")
    tenant_settings = chiari_settings(allowed_domains=domains, internal_emails=[email])
    rules_path = Path(args.rules_file) if args.rules_file else None
    rules = _rules(rules_path)
    print(json.dumps({"tenant_id": TENANT_ID, "slug": "chiari", "domini": domains, "regole": len(rules), "capacita_esterne": False}, ensure_ascii=False))
    if not args.apply:
        print("Prova a vuoto: nessuna scrittura. Per scrivere aggiungi --apply.")
        return
    asyncio.run(_apply(args, tenant_settings, rules))


if __name__ == "__main__":
    main()
