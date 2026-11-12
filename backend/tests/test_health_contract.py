import asyncio

from app.main import health, root


def test_root_contract_exposes_service_name_and_version():
    assert asyncio.run(root()) == {"message": "PerX Cloud API", "version": "1.0.0"}


def test_health_contract_is_stable():
    assert asyncio.run(health()) == {"status": "healthy"}
