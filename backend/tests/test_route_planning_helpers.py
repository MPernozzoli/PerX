"""
Test puri (no DB) sugli helper introdotti per il route planner.
Eseguire con: `pytest backend/tests/test_route_planning_helpers.py`
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.services.cat_duration_stats_service import bucket_for_asset_count
from app.services.inspection_workflow_service import InspectionWorkflowService
from app.services.travel_time_service import (
    Coordinate,
    haversine_km,
    _haversine_minutes,
    _hour_bucket,
)


def _utc(year: int, month: int, day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=timezone.utc)


# --- duration estimator ------------------------------------------------

def test_default_duration_minimum_assets():
    assert InspectionWorkflowService._estimate_default_duration_minutes(1) == 25  # 20 + 0 + 5
    assert InspectionWorkflowService._estimate_default_duration_minutes(3) == 25  # cap at 3 free


def test_default_duration_adds_per_extra_asset():
    # 4 beni → 1 extra → 20 + 5 + 5 margin = 30
    assert InspectionWorkflowService._estimate_default_duration_minutes(4) == 30
    # 6 beni → 3 extra → 20 + 15 + 5 = 40
    assert InspectionWorkflowService._estimate_default_duration_minutes(6) == 40


def test_default_duration_capped_at_60():
    # 20 beni → 17 extra × 5 = 85 + 20 + 5 margin = 110 → cap 60
    assert InspectionWorkflowService._estimate_default_duration_minutes(20) == 60


def test_cat_stats_override_replaces_default():
    cat_map = {("user-1", bucket_for_asset_count(5)): 35}
    minutes = InspectionWorkflowService._resolve_inspection_duration_minutes(
        asset_count=5, cat_stats_map=cat_map, cat_user_id="user-1"
    )
    # 35 (storico) + 5 (margine) = 40
    assert minutes == 40


def test_cat_stats_for_other_cat_falls_back_to_default():
    cat_map = {("user-OTHER", bucket_for_asset_count(5)): 35}
    minutes = InspectionWorkflowService._resolve_inspection_duration_minutes(
        asset_count=5, cat_stats_map=cat_map, cat_user_id="user-ME"
    )
    # default per 5 beni: 20 + 2*5 + 5 = 35
    assert minutes == 35


def test_cat_stats_capped_at_60():
    cat_map = {("u", bucket_for_asset_count(8)): 200}
    minutes = InspectionWorkflowService._resolve_inspection_duration_minutes(
        asset_count=8, cat_stats_map=cat_map, cat_user_id="u"
    )
    assert minutes == 60


# --- contiguous slot merge --------------------------------------------

def _window(start: datetime, end: datetime, label: str | None = None) -> dict:
    return {
        "label": label,
        "preferred_start": start,
        "preferred_end": end,
        "allowed_start": start,
        "allowed_end": end,
        "slot_minutes": int((end - start).total_seconds() / 60),
        "tolerance_minutes": 0,
    }


def test_merge_contiguous_two_slots_into_one():
    a = _window(_utc(2026, 6, 1, 9), _utc(2026, 6, 1, 11), "09-11")
    b = _window(_utc(2026, 6, 1, 11), _utc(2026, 6, 1, 13), "11-13")
    merged = InspectionWorkflowService._merge_contiguous_windows([a, b])
    assert len(merged) == 1
    assert merged[0]["preferred_start"] == _utc(2026, 6, 1, 9)
    assert merged[0]["preferred_end"] == _utc(2026, 6, 1, 13)
    assert merged[0]["slot_minutes"] == 240
    assert "09-11" in merged[0]["label"] and "11-13" in merged[0]["label"]


def test_merge_keeps_non_contiguous_separate():
    a = _window(_utc(2026, 6, 1, 9), _utc(2026, 6, 1, 11))
    b = _window(_utc(2026, 6, 1, 14), _utc(2026, 6, 1, 16))
    merged = InspectionWorkflowService._merge_contiguous_windows([a, b])
    assert len(merged) == 2


def test_merge_within_60s_tolerance():
    a = _window(_utc(2026, 6, 1, 9), _utc(2026, 6, 1, 11))
    # gap di 30 secondi (es. arrotondamento timestamp): merge
    b = _window(_utc(2026, 6, 1, 11, 0) + timedelta(seconds=30), _utc(2026, 6, 1, 13))
    merged = InspectionWorkflowService._merge_contiguous_windows([a, b])
    assert len(merged) == 1


def test_merge_empty_returns_empty():
    assert InspectionWorkflowService._merge_contiguous_windows([]) == []


# --- travel time helpers ----------------------------------------------

def test_coordinate_grid_groups_nearby_points():
    a = Coordinate(45.123, 9.421)
    b = Coordinate(45.149, 9.444)  # ~3 km away, stesso bucket arrotondato
    assert a.grid() == b.grid()


def test_coordinate_grid_distinguishes_far_points():
    a = Coordinate(45.0, 9.0)
    b = Coordinate(45.5, 9.5)  # ~70 km away
    assert a.grid() != b.grid()


def test_hour_bucket_is_6h_aligned():
    assert _hour_bucket(_utc(2026, 6, 1, 8)) == 6
    assert _hour_bucket(_utc(2026, 6, 1, 13)) == 12
    assert _hour_bucket(_utc(2026, 6, 1, 23)) == 18
    assert _hour_bucket(_utc(2026, 6, 1, 0)) == 0


def test_haversine_minutes_min_floor():
    origin = Coordinate(45.0, 9.0)
    dest = Coordinate(45.0, 9.0)
    assert _haversine_minutes(origin, dest) == 5  # FALLBACK_MIN_MINUTES


def test_haversine_km_known_distance():
    # Milano → Roma ≈ 477 km
    km = haversine_km(45.4642, 9.1900, 41.9028, 12.4964)
    assert 470 <= km <= 485
