"""Profilo di accesso di un tenant.

Lo studio completo ha tutto PerX. Il profilo ``chiari`` è un solo perito: niente
portale assicurati, niente Cat Dispatcher, niente funzioni che mostrano PerX a
colleghi o assicurati. La posta operativa della pratica resta disponibile.
"""
from __future__ import annotations

WORKFLOW_STUDIO = "studio"
WORKFLOW_CHIARI = "chiari"

CAPABILITIES: tuple[str, ...] = (
    "sinistri",
    "stima",
    "documenti",
    "posta",
    "sala_regia",
    "consuntivo",
    "rubrica",
    "bignami_privato",
    "portal_assicurati",
    "cat_dispatcher",
    "videoperizia",
    "inviti_utenti",
    "directory_colleghi",
    "chat_colleghi",
    "whatsapp",
    "telegram",
    "chiamate_perx",
    "messaggi_esterni",
    "link_pubblici",
    "programmazione_rete",
    "studio_condiviso",
)

# Funzioni che fanno uscire il prodotto dallo studio.
OUTWARD_CAPABILITIES: frozenset[str] = frozenset(
    {
        "portal_assicurati",
        "cat_dispatcher",
        "videoperizia",
        "inviti_utenti",
        "directory_colleghi",
        "chat_colleghi",
        "whatsapp",
        "telegram",
        "chiamate_perx",
        "messaggi_esterni",
        "link_pubblici",
        "programmazione_rete",
        "studio_condiviso",
    }
)


def _studio_capabilities() -> dict[str, bool]:
    values = {name: True for name in CAPABILITIES}
    values["sala_regia"] = False
    return values


def _chiari_capabilities() -> dict[str, bool]:
    values = {name: True for name in CAPABILITIES}
    for name in OUTWARD_CAPABILITIES:
        values[name] = False
    values["sala_regia"] = True
    values["posta"] = True
    values["bignami_privato"] = True
    return values


def workflow_profile(settings: dict | None) -> str:
    raw = (settings or {}).get("workflow_profile")
    if isinstance(raw, str) and raw.strip().lower() == WORKFLOW_CHIARI:
        return WORKFLOW_CHIARI
    return WORKFLOW_STUDIO


def capabilities_for(settings: dict | None) -> dict[str, bool]:
    """Capacità effettive. Sul profilo Chiari le funzioni esterne restano spente."""
    settings = settings or {}
    profile = workflow_profile(settings)
    base = _chiari_capabilities() if profile == WORKFLOW_CHIARI else _studio_capabilities()
    overrides = settings.get("capabilities")
    if isinstance(overrides, dict):
        for key, value in overrides.items():
            if key not in base or not isinstance(value, bool):
                continue
            if profile == WORKFLOW_CHIARI and key in OUTWARD_CAPABILITIES:
                continue
            base[key] = value
    if profile == WORKFLOW_CHIARI:
        for key in OUTWARD_CAPABILITIES:
            base[key] = False
        base["sala_regia"] = True
    return base


def allows(settings: dict | None, capability: str) -> bool:
    return bool(capabilities_for(settings).get(capability, False))


def email_domain_allowed(email: str | None, allowed_domains: list[str] | None) -> bool:
    domains = {item.strip().lower() for item in (allowed_domains or []) if isinstance(item, str) and item.strip()}
    if not domains:
        return True
    if not email or "@" not in email:
        return False
    return email.rsplit("@", 1)[-1].strip().lower() in domains


def apply_profile_locks(settings: dict | None) -> dict:
    """Allinea i flag storici (portale, CAT, videoperizia) al profilo.

    Un salvataggio delle impostazioni non può riaccendere il portale o il
    dispatcher su Chiari.
    """
    current = dict(settings or {})
    profile = workflow_profile(current)
    if profile == WORKFLOW_CHIARI:
        current["workflow_profile"] = WORKFLOW_CHIARI
        current["single_operator"] = True
        current["portal_domains"] = []
        cat_settings = dict(current.get("cat_settings") or {})
        cat_settings["enabled"] = False
        current["cat_settings"] = cat_settings
        video_settings = dict(current.get("video_inspection_settings") or {})
        video_settings["enabled"] = False
        current["video_inspection_settings"] = video_settings
        access = dict(current.get("access") or {})
        methods = access.get("methods")
        if not isinstance(methods, list) or not methods:
            access["methods"] = ["google", "password"]
        current["access"] = access
    current["capabilities"] = capabilities_for(current)
    return current


def chiari_settings(*, allowed_domains: list[str], internal_emails: list[str]) -> dict:
    domains = [item.strip().lower() for item in allowed_domains if item and item.strip()]
    return apply_profile_locks(
        {
            "workflow_profile": WORKFLOW_CHIARI,
            "single_operator": True,
            "access": {
                "methods": ["google", "password"],
                "allowed_domains": domains,
            },
            "portal_domains": [],
            "internal_domains": domains,
            "internal_emails": internal_emails,
            "system_emails": internal_emails,
            "secretariat_emails": [],
            "claim_garanzie": ["Fenomeno Elettrico"],
            "default_claim_garanzia": "Fenomeno Elettrico",
            "cat_settings": {
                "enabled": False,
                "planner": {
                    "route_generation_hour": 9,
                    "route_review_window_minutes": 60,
                    "availability_slot_minutes": 120,
                    "availability_tolerance_percent": 50,
                    "max_outside_zone_kilometers": 50,
                },
                "technicians": [],
                "municipalities": [],
            },
            "video_inspection_settings": {
                "enabled": False,
                "assignment_run_hour": 9,
                "first_slot_time": "10:00",
                "slot_minutes": 30,
            },
            "branding": {"primary_color": "#08275d"},
            "regia": {
                "soglia_scostamento": "0.10",
                "soglia_over": "5000.00",
                "solleciti_ora": 9,
                "solleciti_giorni": ["lun", "mar", "mer", "gio", "ven"],
                "tentativi_prima_questione": 3,
            },
        }
    )
