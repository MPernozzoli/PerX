"""Scala dei modelli e arbitraggio delle risorse. Vale per ogni tenant."""
from __future__ import annotations

from app.domain.regia_invariants import iban_mod97_ok

MAX_TENTATIVI = 3
LEASE_SECONDS = 120

CLASSI_MAIL = frozenset({"atto_firmato", "sollecito", "incarico", "contestazione", "iban", "altro"})

# Compito → livello di partenza, dove sale, risorsa.
COMPITI: dict[str, dict] = {
    "classifica_mail": {"start": "L1", "climb": ("L3",), "resource": "modello_locale"},
    "estrai_iban": {"start": "L1", "climb": ("L2", "L4"), "resource": "modello_locale"},
    "tipo_foto": {"start": "L1", "climb": ("L2",), "resource": "modello_locale"},
    "leggi_polizza": {"start": "L2", "climb": ("L3",), "resource": "modello_locale"},
    "input_stima": {"start": "L2", "climb": ("L3",), "resource": "modello_locale"},
    "importi": {"start": "L0", "climb": (), "resource": "nessuna"},
    "giudizio": {"start": "L3", "climb": ("L4",), "resource": "cloud"},
    "compila_portale": {"start": "L0", "climb": (), "resource": "chrome"},
    "approvazione": {"start": "L4", "climb": (), "resource": "perito"},
}

# Prima dell'invio dell'atto, dopo l'invio, in chiusura. Stesse uscite della coda.
ESITI_FASE = {
    "nuovo_incarico": "DAL_PERITO",
    "atto_inviato": "STIMA_DA_RIVEDERE",
    "chiusura": "CHIUSURA_DA_RIVEDERE",
}

CAPACITA = {"chrome": 1, "modello_locale": 1}


def catena(compito: str) -> list[str]:
    spec = COMPITI[compito]
    return [spec["start"], *spec["climb"]]


def livello(compito: str, tentativi: int, *, sale: bool) -> str | None:
    """Livello da usare. None: il passo va al perito come Questione."""
    if compito not in COMPITI or tentativi >= MAX_TENTATIVI:
        return None
    chain = catena(compito)
    index = min(tentativi, len(chain) - 1) if sale else 0
    chosen = chain[index]
    if chosen == "L4":
        return None
    return chosen


def esito_fase(phase: str | None) -> str:
    return ESITI_FASE.get(phase or "", "DAL_PERITO")


def risorsa_libera(resource: str | None, occupati: int, *, mac_libero: bool) -> bool:
    if resource == "perito":
        return False
    if resource == "modello_locale" and not mac_libero:
        return False
    cap = CAPACITA.get(resource or "")
    if cap is None:
        return True
    return occupati < cap


def controllo_l0(compito: str, output: dict) -> bool:
    if compito == "classifica_mail":
        return output.get("classe") in CLASSI_MAIL
    if compito == "estrai_iban":
        return iban_mod97_ok(str(output.get("iban") or ""))
    if compito == "importi":
        return output.get("liquidabile") is not None
    return bool(output)


def istruzioni(regole: list[str]) -> str:
    lines = [rule.strip() for rule in regole if rule and rule.strip()]
    if not lines:
        return ""
    body = "\n".join(f"- {line}" for line in lines)
    return f"Regole del perito, da rispettare:\n{body}"
