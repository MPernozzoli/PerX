from datetime import datetime, timezone
from types import SimpleNamespace

from app.services.video_inspection_workflow_service import VideoInspectionWorkflowService


def test_expert_supports_matching_company_and_policy():
    user = SimpleNamespace(
        settings_json={
            "video_inspection": {
                "enabled": True,
                "companies": ["Compagnia Demo"],
                "excluded_policy_numbers": ["POL-EXCLUDED"],
            }
        }
    )
    compatible_claim = SimpleNamespace(compagnia="Compagnia Demo", numero_polizza="POL-OK")
    excluded_claim = SimpleNamespace(compagnia="Compagnia Demo", numero_polizza="POL-EXCLUDED")
    other_company_claim = SimpleNamespace(compagnia="Altra Compagnia", numero_polizza="POL-OK")

    assert VideoInspectionWorkflowService._expert_supports_claim(user, compatible_claim)
    assert not VideoInspectionWorkflowService._expert_supports_claim(user, excluded_claim)
    assert not VideoInspectionWorkflowService._expert_supports_claim(user, other_company_claim)


def test_interval_requires_work_schedule_and_no_overlap():
    start = datetime(2026, 6, 2, 10, 0, tzinfo=timezone.utc)
    end = datetime(2026, 6, 2, 10, 30, tzinfo=timezone.utc)
    working = [(datetime(2026, 6, 2, 9, 0, tzinfo=timezone.utc), datetime(2026, 6, 2, 18, 0, tzinfo=timezone.utc))]

    assert VideoInspectionWorkflowService._interval_is_available(start, end, working, [])
    assert not VideoInspectionWorkflowService._interval_is_available(
        start,
        end,
        working,
        [(datetime(2026, 6, 2, 10, 15, tzinfo=timezone.utc), datetime(2026, 6, 2, 10, 45, tzinfo=timezone.utc))],
    )


def test_existing_assigned_expert_is_the_only_scheduling_candidate():
    retained = SimpleNamespace(id="retained")
    eligible = [SimpleNamespace(id="eligible-1"), SimpleNamespace(id="eligible-2")]

    experts, is_retained = VideoInspectionWorkflowService._scheduling_experts(retained, eligible)

    assert experts == [retained]
    assert is_retained
