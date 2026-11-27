import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.api.v1 import routes_communications
from app.core.config import Settings
from app.core.rate_limit import RateLimitRule, SlidingWindowRateLimiter, client_ip, enforce_rate_limit

STRONG_SECRET = "s" * 48


def _settings(**overrides) -> Settings:
    return Settings(_env_file=None, **overrides)


def _request(headers: dict[str, str] | None = None, client: tuple[str, int] = ("10.0.0.9", 50000)) -> Request:
    raw_headers = [(key.lower().encode(), value.encode()) for key, value in (headers or {}).items()]
    return Request({"type": "http", "method": "POST", "path": "/", "headers": raw_headers, "client": client})


# --- Production safety of settings -------------------------------------------------


def test_dev_shortcuts_are_off_by_default():
    settings = _settings(ENV="dev")
    assert settings.DEBUG is False
    assert settings.PORTAL_DEBUG_PREVIEW_LINKS is False
    assert settings.PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH is False


@pytest.mark.parametrize("secret", ["change-me-in-production", "replace-with-a-random-secret", "too-short"])
def test_production_refuses_placeholder_or_short_secret_key(secret):
    settings = _settings(ENV="prod", SECRET_KEY=secret)
    with pytest.raises(RuntimeError, match="SECRET_KEY") as exc_info:
        settings.assert_production_secrets()
    # The error must never echo the configured secret back into the logs.
    assert secret not in str(exc_info.value)


def test_non_production_accepts_development_secret_key():
    _settings(ENV="dev", SECRET_KEY="change-me-in-production").assert_production_secrets()
    _settings(ENV="prod", SECRET_KEY=STRONG_SECRET).assert_production_secrets()


def test_production_forces_dev_shortcuts_off():
    settings = _settings(
        ENV="prod",
        SECRET_KEY=STRONG_SECRET,
        DEBUG=True,
        PORTAL_DEBUG_PREVIEW_LINKS=True,
        PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH=True,
    )
    assert settings.DEBUG is False
    assert settings.PORTAL_DEBUG_PREVIEW_LINKS is False
    assert settings.PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH is False


def test_development_keeps_explicit_dev_shortcuts():
    settings = _settings(ENV="dev", PORTAL_DEBUG_PREVIEW_LINKS=True, PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH=True)
    assert settings.PORTAL_DEBUG_PREVIEW_LINKS is True
    assert settings.PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH is True


def test_api_docs_hidden_in_production_unless_enabled():
    assert _settings(ENV="dev").api_docs_enabled is True
    assert _settings(ENV="prod", SECRET_KEY=STRONG_SECRET).api_docs_enabled is False
    assert _settings(ENV="prod", SECRET_KEY=STRONG_SECRET, API_DOCS_ENABLED=True).api_docs_enabled is True


# --- Rate limiting -----------------------------------------------------------------


def test_sliding_window_blocks_after_limit_and_recovers():
    limiter = SlidingWindowRateLimiter()
    rule = RateLimitRule(limit=2, window_seconds=60)
    assert limiter.hit("k", rule, now=0.0) is None
    assert limiter.hit("k", rule, now=1.0) is None
    retry_after = limiter.hit("k", rule, now=2.0)
    assert retry_after == pytest.approx(58.0)
    assert limiter.hit("k", rule, now=61.0) is None


def test_client_ip_prefers_cloudflare_then_last_forwarded_hop():
    assert client_ip(_request({"CF-Connecting-IP": "203.0.113.7", "X-Forwarded-For": "1.1.1.1"})) == "203.0.113.7"
    assert client_ip(_request({"X-Forwarded-For": "6.6.6.6, 198.51.100.4"})) == "198.51.100.4"
    assert client_ip(_request()) == "10.0.0.9"


def test_enforce_rate_limit_counts_identifier_across_ips():
    rule_ip = RateLimitRule(limit=100, window_seconds=60)
    rule_id = RateLimitRule(limit=2, window_seconds=60)
    for ip in ("192.0.2.1", "192.0.2.2"):
        enforce_rate_limit(
            _request({"CF-Connecting-IP": ip}),
            "test-identifier",
            per_ip=rule_ip,
            identifier="SIN-2026-0001",
            per_identifier=rule_id,
        )
    with pytest.raises(HTTPException) as exc_info:
        enforce_rate_limit(
            _request({"CF-Connecting-IP": "192.0.2.3"}),
            "test-identifier",
            per_ip=rule_ip,
            identifier="sin-2026-0001 ",
            per_identifier=rule_id,
        )
    assert exc_info.value.status_code == 429
    assert int(exc_info.value.headers["Retry-After"]) >= 1


# --- Provider webhook gate ---------------------------------------------------------


def test_provider_webhook_disabled_without_configured_secret(monkeypatch):
    monkeypatch.setattr(routes_communications.settings, "COMMUNICATIONS_WEBHOOK_SECRET", None)
    with pytest.raises(HTTPException) as exc_info:
        routes_communications._require_webhook_secret("anything")
    assert exc_info.value.status_code == 404


def test_provider_webhook_requires_matching_secret(monkeypatch):
    monkeypatch.setattr(routes_communications.settings, "COMMUNICATIONS_WEBHOOK_SECRET", "hook-secret")
    with pytest.raises(HTTPException) as exc_info:
        routes_communications._require_webhook_secret("wrong")
    assert exc_info.value.status_code == 401
    routes_communications._require_webhook_secret("hook-secret")
