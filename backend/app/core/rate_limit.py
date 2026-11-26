"""
In-memory sliding-window rate limiting for authentication endpoints.

Scope and limits of this implementation:
- state lives in the process memory, so limits are per instance. This is
  adequate for the current single-instance Render deployment; scaling out
  horizontally requires a shared store (e.g. Redis) behind the same API;
- the client address comes from ``CF-Connecting-IP`` when present (Render
  serves the API through Cloudflare, which always overwrites that header),
  otherwise from the right-most ``X-Forwarded-For`` entry, i.e. the hop
  appended by the platform proxy, which a client cannot spoof by sending its
  own header. Without either header the socket peer is used.
"""
from __future__ import annotations

import hashlib
import math
import time
from collections import deque
from dataclasses import dataclass

from fastapi import HTTPException, Request, status

_MAX_TRACKED_KEYS = 50_000


@dataclass(frozen=True)
class RateLimitRule:
    limit: int
    window_seconds: int


class SlidingWindowRateLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = {}

    def hit(self, key: str, rule: RateLimitRule, now: float | None = None) -> float | None:
        """Register a hit for ``key``; return seconds to wait when the limit is exceeded."""
        current = time.monotonic() if now is None else now
        window_start = current - rule.window_seconds
        bucket = self._hits.get(key)
        if bucket is None:
            if len(self._hits) >= _MAX_TRACKED_KEYS:
                self._prune(current)
            bucket = deque()
            self._hits[key] = bucket
        while bucket and bucket[0] <= window_start:
            bucket.popleft()
        if len(bucket) >= rule.limit:
            return max(bucket[0] + rule.window_seconds - current, 0.0)
        bucket.append(current)
        return None

    def reset(self) -> None:
        self._hits.clear()

    def _prune(self, now: float, max_window_seconds: int = 24 * 3600) -> None:
        cutoff = now - max_window_seconds
        stale = [key for key, bucket in self._hits.items() if not bucket or bucket[-1] <= cutoff]
        for key in stale:
            del self._hits[key]
        if len(self._hits) >= _MAX_TRACKED_KEYS:
            # Still saturated: drop the oldest half instead of growing without bound.
            oldest = sorted(self._hits, key=lambda k: self._hits[k][-1] if self._hits[k] else 0.0)
            for key in oldest[: len(oldest) // 2]:
                del self._hits[key]


limiter = SlidingWindowRateLimiter()


def client_ip(request: Request) -> str:
    cloudflare_ip = request.headers.get("cf-connecting-ip", "").strip()
    if cloudflare_ip:
        return cloudflare_ip
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        hops = [hop.strip() for hop in forwarded.split(",") if hop.strip()]
        if hops:
            return hops[-1]
    return request.client.host if request.client else "unknown"


def _fingerprint(value: str) -> str:
    # Identifiers (e-mail, claim numbers, phone numbers) are hashed so that the
    # limiter never keeps personal data in memory in clear text.
    return hashlib.sha256(value.strip().lower().encode("utf-8")).hexdigest()[:32]


def enforce_rate_limit(
    request: Request,
    scope: str,
    *,
    per_ip: RateLimitRule,
    identifier: str | None = None,
    per_identifier: RateLimitRule | None = None,
) -> None:
    """Raise HTTP 429 when the caller exceeds the limits configured for ``scope``."""
    checks: list[tuple[str, RateLimitRule]] = [(f"{scope}:ip:{client_ip(request)}", per_ip)]
    if identifier and per_identifier:
        checks.append((f"{scope}:id:{_fingerprint(identifier)}", per_identifier))

    for key, rule in checks:
        retry_after = limiter.hit(key, rule)
        if retry_after is not None:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Troppi tentativi. Riprova più tardi.",
                headers={"Retry-After": str(max(1, math.ceil(retry_after)))},
            )
