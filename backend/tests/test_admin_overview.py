import asyncio

from app.api.v1.routes_admin import _admin_capabilities, get_admin_overview
from app.core.security import PLATFORM_BRIDGE_USER


class _FakeMappings:
    def one(self):
        return {
            "tenants": 2,
            "users": 11,
            "active_users": 9,
            "domain_routes": 6,
            "active_domain_routes": 5,
            "unresolved_errors": 3,
            "unresolved_critical_errors": 1,
        }


class _FakeResult:
    def mappings(self):
        return _FakeMappings()


class _FakeDb:
    async def execute(self, _query):
        return _FakeResult()


def test_admin_capabilities_expose_users_as_read_only():
    capabilities = {item.resource: item for item in _admin_capabilities()}

    assert capabilities["users"].read is True
    assert capabilities["users"].create is False
    assert capabilities["users"].update is False
    assert capabilities["domain_routes"].delete is True


def test_admin_overview_returns_one_control_plane_snapshot():
    overview = asyncio.run(get_admin_overview(db=_FakeDb(), _=PLATFORM_BRIDGE_USER))

    assert overview.service == "perx"
    assert overview.api_version == "v1"
    assert overview.counts.tenants == 2
    assert overview.counts.active_users == 9
    assert overview.counts.unresolved_critical_errors == 1
