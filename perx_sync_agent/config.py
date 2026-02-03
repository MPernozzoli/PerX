from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict, Optional

from pydantic import BaseModel, Field, validator
from dotenv import load_dotenv


def _parse_user_mapping(value):  # noqa: ANN001
    """
    Supporta:
    - dict (già parseato)
    - JSON (es. {"user":"Subfolder"})
    - formato legacy: "user1=Utenti\\A;user2=Utenti\\B"
    """
    if value is None:
        return {}
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return {}
        if raw.startswith("{"):
            try:
                parsed = json.loads(raw)
                if isinstance(parsed, dict):
                    return {str(k): str(v) for k, v in parsed.items()}
            except Exception:
                pass
        out: Dict[str, str] = {}
        for part in raw.split(";"):
            part = part.strip()
            if not part or "=" not in part:
                continue
            k, v = part.split("=", 1)
            k, v = k.strip(), v.strip()
            if k:
                out[k] = v
        return out
    return {}


class Settings(BaseModel):
    """Configurazione centralizzata dell'agente (solo Pydantic 1)."""

    api_token: str
    gestionale_root_path: Path
    port: int = 8000
    log_level: str = "INFO"
    log_dir: Path = Field(default_factory=lambda: Path("logs"))
    monitoring_store: Path = Field(default_factory=lambda: Path("logs/monitoring_registry.json"))
    user_mapping: Dict[str, str] = Field(default_factory=dict)
    hub_url: str = "https://mac-mini-di-massimo.tailca58be.ts.net"
    agent_install_path: Optional[Path] = None

    class Config:
        arbitrary_types_allowed = True

    @validator("user_mapping", pre=True)
    def parse_user_mapping(cls, value):  # noqa: ANN001
        return _parse_user_mapping(value)

    @validator("gestionale_root_path", pre=True)
    def expand_root(cls, value: str) -> Path:
        return Path(value).expanduser().resolve()

    @validator("log_dir", pre=True)
    def expand_log(cls, value) -> Path:  # noqa: ANN001
        return Path(value).expanduser().resolve() if value else Path("logs").resolve()

    @validator("monitoring_store", pre=True)
    def expand_store(cls, value) -> Path:  # noqa: ANN001
        if value is None:
            return Path("logs/monitoring_registry.json").resolve()
        return Path(value).expanduser().resolve()


def load_settings() -> Settings:
    """
    Carica le impostazioni leggendo .env se presente (solo Pydantic 1).
    Preferisce variabili d'ambiente per l'override.
    """
    load_dotenv(".env", encoding="utf-8")

    api_token = os.getenv("API_TOKEN")
    if not api_token:
        raise ValueError("API_TOKEN non impostato in .env o variabili d'ambiente")

    gestionale_root_path = os.getenv("GESTIONALE_ROOT_PATH")
    if not gestionale_root_path:
        raise ValueError("GESTIONALE_ROOT_PATH non impostato in .env o variabili d'ambiente")

    port = int(os.getenv("PORT", "8000"))
    log_level = os.getenv("LOG_LEVEL", "INFO")
    log_dir = os.getenv("LOG_DIR", "logs")
    monitoring_store = os.getenv("MONITORING_STORE", "logs/monitoring_registry.json")
    user_mapping_raw = os.getenv("USER_MAPPING", "")
    hub_url = os.getenv("HUB_URL", "https://mac-mini-di-massimo.tailca58be.ts.net")
    agent_install_path = os.getenv("AGENT_INSTALL_PATH") or None

    settings = Settings(
        api_token=api_token,
        gestionale_root_path=gestionale_root_path,
        port=port,
        log_level=log_level,
        log_dir=log_dir,
        monitoring_store=monitoring_store,
        user_mapping=_parse_user_mapping(user_mapping_raw) if user_mapping_raw else {},
        hub_url=hub_url.rstrip("/"),
        agent_install_path=Path(agent_install_path).resolve() if agent_install_path else None,
    )

    os.makedirs(settings.log_dir, exist_ok=True)
    settings.monitoring_store.parent.mkdir(parents=True, exist_ok=True)
    return settings
