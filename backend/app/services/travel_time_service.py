"""
Stima tempi di viaggio per il route planner.

Ordine di risoluzione per ogni coppia (origin, dest, departure_time):
1. cache `route_travel_estimates` (chiave: grid lat/lon arrotondato +
   day-of-week + bucket di 6 ore);
2. Google Routes API v2 `computeRouteMatrix` traffic-aware, se il tenant
   ha `routing_enabled` e una `routing_api_key`;
3. fallback haversine a 35 km/h (stesso comportamento storico del planner).

La cache è condivisa fra tutti i tenant — il tempo di percorrenza
non dipende dal tenant — e la API key serve solo per autorizzare la
chiamata. Hit della cache risparmiano la chiamata API anche per tenant
diversi da quello che l'ha riempita.
"""
from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Iterable, Optional

import httpx
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.route_planning import RouteTravelEstimate

logger = logging.getLogger(__name__)

GOOGLE_ROUTES_ENDPOINT = "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix"
GRID_DECIMALS = 1  # ~11 km grid
HOUR_BUCKET_HOURS = 6  # 0,6,12,18 buckets
HAVERSINE_AVERAGE_KMH = 35.0
FALLBACK_MIN_MINUTES = 5
GOOGLE_REQUEST_TIMEOUT_SECONDS = 8.0


@dataclass(frozen=True)
class Coordinate:
    latitude: float
    longitude: float

    def grid(self) -> str:
        return f"{round(self.latitude, GRID_DECIMALS)},{round(self.longitude, GRID_DECIMALS)}"


@dataclass
class TravelEstimate:
    minutes: int
    source: str  # 'cache' | 'google' | 'haversine'


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(a))


def _haversine_minutes(origin: Coordinate, dest: Coordinate) -> int:
    km = haversine_km(origin.latitude, origin.longitude, dest.latitude, dest.longitude)
    if km <= 0.5:
        return FALLBACK_MIN_MINUTES
    return max(FALLBACK_MIN_MINUTES, math.ceil((km / HAVERSINE_AVERAGE_KMH) * 60))


def _hour_bucket(at: datetime) -> int:
    return (at.hour // HOUR_BUCKET_HOURS) * HOUR_BUCKET_HOURS


class TravelTimeService:
    """Coordina cache + API + fallback per le stime di viaggio."""

    def __init__(
        self,
        db: AsyncSession,
        *,
        api_key: Optional[str],
        cache_ttl_days: int,
        enabled: bool,
        http_client: Optional[httpx.AsyncClient] = None,
    ) -> None:
        self._db = db
        self._api_key = api_key.strip() if api_key else None
        self._cache_ttl_days = max(1, cache_ttl_days)
        self._enabled = bool(enabled and self._api_key)
        self._http_client = http_client

    async def estimate_matrix(
        self,
        pairs: Iterable[tuple[Coordinate, Coordinate, datetime]],
    ) -> dict[tuple[str, str, int, int], TravelEstimate]:
        """Restituisce una stima per ogni coppia (origine, destinazione, partenza).

        La chiave del dict è (origin_grid, dest_grid, dow, hour_bucket).
        Coppie identiche per chiave vengono accorpate automaticamente.
        """
        normalized: dict[tuple[str, str, int, int], tuple[Coordinate, Coordinate, datetime]] = {}
        for origin, dest, departure in pairs:
            key = (origin.grid(), dest.grid(), departure.weekday(), _hour_bucket(departure))
            normalized.setdefault(key, (origin, dest, departure))

        if not normalized:
            return {}

        cache_hits = await self._lookup_cache(normalized.keys())
        results: dict[tuple[str, str, int, int], TravelEstimate] = {}
        for key, minutes in cache_hits.items():
            results[key] = TravelEstimate(minutes=minutes, source="cache")

        missing = [key for key in normalized if key not in results]
        if missing and self._enabled:
            google_results = await self._fetch_google(
                [(key, normalized[key]) for key in missing]
            )
            for key, minutes in google_results.items():
                results[key] = TravelEstimate(minutes=minutes, source="google")
            if google_results:
                await self._persist_cache(google_results)

        for key in normalized:
            if key in results:
                continue
            origin, dest, _ = normalized[key]
            results[key] = TravelEstimate(
                minutes=_haversine_minutes(origin, dest),
                source="haversine",
            )
        return results

    async def lookup(
        self,
        origin: Coordinate,
        dest: Coordinate,
        departure: datetime,
        precomputed: Optional[dict[tuple[str, str, int, int], TravelEstimate]] = None,
    ) -> TravelEstimate:
        key = (origin.grid(), dest.grid(), departure.weekday(), _hour_bucket(departure))
        if precomputed and key in precomputed:
            return precomputed[key]
        result = await self.estimate_matrix([(origin, dest, departure)])
        return result[key]

    async def _lookup_cache(
        self,
        keys: Iterable[tuple[str, str, int, int]],
    ) -> dict[tuple[str, str, int, int], int]:
        keys_list = list(keys)
        if not keys_list:
            return {}
        fresh_after = datetime.now(timezone.utc) - timedelta(days=self._cache_ttl_days)
        origins = {key[0] for key in keys_list}
        dests = {key[1] for key in keys_list}
        stmt = select(RouteTravelEstimate).where(
            RouteTravelEstimate.origin_grid.in_(origins),
            RouteTravelEstimate.dest_grid.in_(dests),
            RouteTravelEstimate.fetched_at >= fresh_after,
        )
        rows = (await self._db.execute(stmt)).scalars().all()
        index = {
            (row.origin_grid, row.dest_grid, row.dow, row.hour_bucket): row.minutes
            for row in rows
        }
        return {key: index[key] for key in keys_list if key in index}

    async def _persist_cache(
        self,
        results: dict[tuple[str, str, int, int], int],
    ) -> None:
        now = datetime.now(timezone.utc)
        rows = [
            {
                "origin_grid": origin,
                "dest_grid": dest,
                "dow": dow,
                "hour_bucket": bucket,
                "minutes": minutes,
                "source": "google",
                "fetched_at": now,
            }
            for (origin, dest, dow, bucket), minutes in results.items()
        ]
        stmt = pg_insert(RouteTravelEstimate.__table__).values(rows)
        stmt = stmt.on_conflict_do_update(
            index_elements=["origin_grid", "dest_grid", "dow", "hour_bucket"],
            set_={
                "minutes": stmt.excluded.minutes,
                "source": stmt.excluded.source,
                "fetched_at": stmt.excluded.fetched_at,
            },
        )
        await self._db.execute(stmt)

    async def _fetch_google(
        self,
        entries: list[tuple[tuple[str, str, int, int], tuple[Coordinate, Coordinate, datetime]]],
    ) -> dict[tuple[str, str, int, int], int]:
        if not entries or not self._api_key:
            return {}

        origin_index: dict[str, Coordinate] = {}
        dest_index: dict[str, Coordinate] = {}
        for _, (origin, dest, _) in entries:
            origin_index[origin.grid()] = origin
            dest_index[dest.grid()] = dest

        origins_payload = [
            {
                "waypoint": {
                    "location": {
                        "latLng": {"latitude": coord.latitude, "longitude": coord.longitude},
                    },
                },
            }
            for coord in origin_index.values()
        ]
        destinations_payload = [
            {
                "waypoint": {
                    "location": {
                        "latLng": {"latitude": coord.latitude, "longitude": coord.longitude},
                    },
                },
            }
            for coord in dest_index.values()
        ]
        departure = max(entry[1][2] for entry in entries)
        if departure < datetime.now(timezone.utc) + timedelta(minutes=2):
            departure = datetime.now(timezone.utc) + timedelta(minutes=2)

        body = {
            "origins": origins_payload,
            "destinations": destinations_payload,
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
            "departureTime": departure.astimezone(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z"),
        }
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._api_key,
            "X-Goog-FieldMask": "originIndex,destinationIndex,duration,condition",
        }

        try:
            client = self._http_client or httpx.AsyncClient(timeout=GOOGLE_REQUEST_TIMEOUT_SECONDS)
            owned = self._http_client is None
            try:
                response = await client.post(GOOGLE_ROUTES_ENDPOINT, json=body, headers=headers)
            finally:
                if owned:
                    await client.aclose()
        except httpx.HTTPError:
            logger.exception("Google Routes computeRouteMatrix request failed")
            return {}

        if response.status_code != 200:
            logger.warning(
                "Google Routes computeRouteMatrix non-OK status=%s body=%s",
                response.status_code,
                response.text[:500],
            )
            return {}

        origins_list = list(origin_index.keys())
        dests_list = list(dest_index.keys())
        try:
            matrix = response.json()
        except ValueError:
            logger.exception("Google Routes response is not JSON")
            return {}

        per_pair: dict[tuple[str, str], int] = {}
        for item in matrix if isinstance(matrix, list) else []:
            if not isinstance(item, dict) or item.get("condition") != "ROUTE_EXISTS":
                continue
            origin_idx = item.get("originIndex")
            dest_idx = item.get("destinationIndex")
            duration = item.get("duration")
            if not isinstance(origin_idx, int) or not isinstance(dest_idx, int):
                continue
            if not (0 <= origin_idx < len(origins_list)) or not (0 <= dest_idx < len(dests_list)):
                continue
            seconds = _parse_duration_seconds(duration)
            if seconds is None:
                continue
            per_pair[(origins_list[origin_idx], dests_list[dest_idx])] = max(
                FALLBACK_MIN_MINUTES,
                math.ceil(seconds / 60),
            )

        result: dict[tuple[str, str, int, int], int] = {}
        for key, _ in entries:
            origin_grid, dest_grid, _, _ = key
            minutes = per_pair.get((origin_grid, dest_grid))
            if minutes is not None:
                result[key] = minutes
        return result


def _parse_duration_seconds(value: object) -> Optional[int]:
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        candidate = value.strip()
        if candidate.endswith("s"):
            candidate = candidate[:-1]
        try:
            return int(float(candidate))
        except ValueError:
            return None
    return None
