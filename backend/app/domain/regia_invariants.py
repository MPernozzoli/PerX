"""Invarianti della Regia, imposte dal backend e non dal prompt."""
from __future__ import annotations

import re
from decimal import Decimal

_IBAN_SPACE = re.compile(r"\s+")


def same_economy(previous_hash: str | None, new_hash: str | None) -> bool:
    return bool(previous_hash) and previous_hash == new_hash


def liquidabile_consentito(
    nuovo: Decimal,
    gia_proposto: Decimal | None,
    eccezione: str | None,
) -> bool:
    """Nessun atto sotto un importo già proposto, salvo eccezione del perito."""
    if gia_proposto is None or nuovo >= gia_proposto:
        return True
    return bool(eccezione and eccezione.strip())


def iban_mod97_ok(iban: str | None) -> bool:
    if not iban:
        return False
    compact = _IBAN_SPACE.sub("", iban).upper()
    if len(compact) < 15 or not compact[:2].isalpha() or not compact[2:4].isdigit():
        return False
    rearranged = compact[4:] + compact[:4]
    digits: list[str] = []
    for char in rearranged:
        if char.isdigit():
            digits.append(char)
        elif "A" <= char <= "Z":
            digits.append(str(ord(char) - 55))
        else:
            return False
    remainder = 0
    for chunk_start in range(0, len(digits), 9):
        remainder = int(str(remainder) + "".join(digits[chunk_start : chunk_start + 9])) % 97
    return remainder == 1


def _nome(value: str | None) -> str:
    return " ".join((value or "").upper().split())


def beneficiario_e_contraente(beneficiario: str | None, contraente: str | None) -> bool | None:
    left = _nome(beneficiario)
    right = _nome(contraente)
    if not left or not right:
        return None
    return left == right


def iban_richiede_questione(
    *,
    iban_precedente: str | None,
    iban_nuovo: str | None,
    beneficiario_e_intestatario: bool | None,
) -> str | None:
    """Ritorna il tipo di questione, oppure None se l'IBAN si può registrare.

    Un IBAN che non passa il mod-97 non entra. Un cambio di IBAN o un
    beneficiario che non è l'intestatario di polizza si ferma dal perito.
    """
    if not iban_mod97_ok(iban_nuovo):
        return "iban_non_valido"
    precedente = _IBAN_SPACE.sub("", iban_precedente or "").upper()
    nuovo = _IBAN_SPACE.sub("", iban_nuovo or "").upper()
    if precedente and precedente != nuovo:
        return "cambio_iban"
    if beneficiario_e_intestatario is not True:
        return "beneficiario_terzo"
    return None


EXECUTION_PHASES = frozenset(
    {
        "compila_documentale",
        "compila_reclaim",
        "compila_salesforce",
        "chiusura",
        "esegui",
    }
)

OPEN_JOB_STATUSES = frozenset({"pending", "processing", "retry"})
META_STATES = frozenset({"IN_LAVORAZIONE", "IN_CHIUSURA"})
