"""Abbinamento mail → sinistro.

Ordine fisso: riferimento interno `YY-NNNNNN`, poi numero sinistro compagnia,
poi nome assicurato. Il primo livello che trova una pratica chiude la scelta.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

REF_RE = re.compile(r"\b\d{2}-\d{6}\b")
COMPANY_RE = re.compile(
    r"(?<![0-9A-Za-z])(?:(\d)\.)?([0-9A-Za-z]{3})[.\s](\d{2})[.\s](\d{5})(?![0-9A-Za-z])",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class ClaimMailKey:
    id: str
    external_ref: str | None
    numero_sinistro: str | None
    nome_assicurato: str | None


@dataclass(frozen=True)
class MailClaimMatch:
    claims: tuple[ClaimMailKey, ...]
    source: str | None

    @property
    def sinistro_ref(self) -> str | None:
        if not self.claims:
            return None
        return self.claims[0].external_ref


def match_mail_to_claims(claims: list[ClaimMailKey], subject: str, body: str) -> MailClaimMatch:
    subject = subject or ""
    body = body or ""
    by_ref: dict[str, list[ClaimMailKey]] = {}
    for claim in claims:
        if claim.external_ref:
            by_ref.setdefault(claim.external_ref, []).append(claim)

    seen: set[str] = set()
    matched: list[ClaimMailKey] = []
    for ref in _ordered(REF_RE, subject) + [item for item in _ordered(REF_RE, body) if item not in subject]:
        for claim in by_ref.get(ref, []):
            if claim.id in seen:
                continue
            seen.add(claim.id)
            matched.append(claim)
    if matched:
        return MailClaimMatch(tuple(matched), "riferimento")

    numbers = _company_compacts(f"{subject}\n{body}")
    if numbers:
        by_number = [claim for claim in claims if _number_matches(claim.numero_sinistro, numbers)]
        if by_number:
            return MailClaimMatch(tuple(by_number), "numero_compagnia")

    by_name = _match_name(claims, f"{subject}\n{body}")
    if by_name:
        return MailClaimMatch(tuple(by_name), "nome_assicurato")
    return MailClaimMatch((), None)


def plain_mail_text(body_text: str | None, body_html: str | None) -> str:
    if body_text and body_text.strip():
        return body_text
    if not body_html:
        return ""
    return re.sub(r"<[^>]+>", " ", body_html)


def _ordered(pattern: re.Pattern[str], text: str) -> list[str]:
    found: list[str] = []
    for match in pattern.finditer(text):
        value = match.group(0)
        if value not in found:
            found.append(value)
    return found


def _company_compacts(text: str) -> set[str]:
    found: set[str] = set()
    for match in COMPANY_RE.finditer(text):
        prefix = (match.group(1) or "").lower()
        body = f"{match.group(2)}{match.group(3)}{match.group(4)}".lower()
        found.add(body)
        if prefix:
            found.add(prefix + body)
    return found


def _number_matches(stored: str | None, found: set[str]) -> bool:
    if not stored:
        return False
    compact = re.sub(r"[^0-9a-z]", "", stored.lower())
    if len(compact) < 10:
        return False
    tail = compact[1:] if compact.startswith("1") else compact
    return compact in found or tail in found


def _match_name(claims: list[ClaimMailKey], text: str) -> list[ClaimMailKey]:
    folded = " ".join(text.casefold().split())
    hits: list[tuple[int, str, ClaimMailKey]] = []
    for claim in claims:
        name = " ".join((claim.nome_assicurato or "").casefold().split())
        if len(name) < 3:
            continue
        pattern = r"(?<!\w)" + re.escape(name) + r"(?!\w)"
        if re.search(pattern, folded):
            hits.append((len(name), name, claim))
    if not hits:
        return []
    best = max(item[0] for item in hits)
    winners = [(name, claim) for length, name, claim in hits if length == best]
    names = {name for name, _ in winners}
    if len(names) != 1:
        return []
    return [claim for _, claim in winners]
