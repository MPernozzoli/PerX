"""Test del provider S3 del vault (moto, nessuna rete/Docker)."""
import boto3
import pytest
from moto import mock_aws

from app.core.config import settings
from app.services.vault_storage_service import VaultStorageService

BUCKET = "perx-vault-test"
PATH = "tenants/t1/sinistri/S-1/documenti/a.pdf"


@pytest.fixture
def s3(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setattr(settings, "VAULT_STORAGE_PROVIDER", "s3")
    monkeypatch.setattr(settings, "VAULT_S3_BUCKET", BUCKET)
    monkeypatch.setattr(settings, "VAULT_S3_REGION", "eu-south-1")
    monkeypatch.setattr(settings, "VAULT_S3_ENDPOINT_URL", None)
    monkeypatch.setattr(settings, "VAULT_S3_PREFIX", "")
    with mock_aws():
        VaultStorageService.reset_s3_store()
        client = boto3.client("s3", region_name="eu-south-1")
        client.create_bucket(
            Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": "eu-south-1"}
        )
        yield client
        VaultStorageService.reset_s3_store()


async def _upload(path=PATH, content=b"hello"):
    return await VaultStorageService.upload_bytes(
        tenant_id="t1", claim_ref="S-1", relative_path=path, content=content, mime_type="application/pdf"
    )


def test_default_provider_is_unchanged():
    assert settings.VAULT_STORAGE_PROVIDER == "local"
    assert VaultStorageService.provider_name() == "local"
    assert settings.VAULT_S3_PRESIGNED_DOWNLOADS is False
    assert settings.VAULT_S3_REGION == "eu-south-1"
    assert VaultStorageService.supports_presigned_downloads() is False


@pytest.mark.asyncio
async def test_roundtrip_and_sse(s3):
    blob = await _upload()
    assert blob.size_bytes == 5
    assert await VaultStorageService.download_bytes(PATH) == b"hello"
    head = s3.head_object(Bucket=BUCKET, Key=PATH)
    assert head["ServerSideEncryption"] == "AES256"
    assert head["ContentType"] == "application/pdf"
    assert head["Metadata"]["sha256"] == blob.checksum_sha256


@pytest.mark.asyncio
async def test_download_missing_raises(s3):
    with pytest.raises(FileNotFoundError):
        await VaultStorageService.download_bytes("nope/x.pdf")


@pytest.mark.asyncio
async def test_ensure_claim_folder_is_noop(s3):
    await VaultStorageService.ensure_claim_folder("t1", "S-1")
    assert "Contents" not in s3.list_objects_v2(Bucket=BUCKET)


@pytest.mark.asyncio
async def test_copy_overwrite_protection(s3):
    await _upload(content=b"one")
    dst = "tenants/t1/sinistri/S-1/atti/b.pdf"
    await VaultStorageService.copy_file(PATH, dst)
    assert await VaultStorageService.download_bytes(dst) == b"one"
    await _upload(content=b"two")
    with pytest.raises(FileExistsError):
        await VaultStorageService.copy_file(PATH, dst)
    await VaultStorageService.copy_file(PATH, dst, overwrite=True)
    assert await VaultStorageService.download_bytes(dst) == b"two"
    assert s3.head_object(Bucket=BUCKET, Key=dst)["ServerSideEncryption"] == "AES256"
    with pytest.raises(FileNotFoundError):
        await VaultStorageService.copy_file("missing", "other")


@pytest.mark.asyncio
async def test_move(s3):
    await _upload()
    dst = "tenants/t1/sinistri/S-1/PerX-cache/cestino/1_a.pdf"
    await VaultStorageService.move_file(PATH, dst)
    assert await VaultStorageService.download_bytes(dst) == b"hello"
    with pytest.raises(FileNotFoundError):
        await VaultStorageService.download_bytes(PATH)
    with pytest.raises(FileNotFoundError):
        await VaultStorageService.move_file(PATH, "x/y")


@pytest.mark.asyncio
async def test_move_overwrite_protection(s3):
    await _upload()
    other = "tenants/t1/sinistri/S-1/atti/b.pdf"
    await _upload(other, b"other")
    with pytest.raises(FileExistsError):
        await VaultStorageService.move_file(PATH, other)
    assert await VaultStorageService.download_bytes(PATH) == b"hello"
    await VaultStorageService.move_file(PATH, other, overwrite=True)
    assert await VaultStorageService.download_bytes(other) == b"hello"


@pytest.mark.asyncio
async def test_delete_missing_ok(s3):
    await _upload()
    await VaultStorageService.delete_file(PATH)
    with pytest.raises(FileNotFoundError):
        await VaultStorageService.download_bytes(PATH)
    await VaultStorageService.delete_file(PATH, missing_ok=True)
    with pytest.raises(FileNotFoundError):
        await VaultStorageService.delete_file(PATH, missing_ok=False)


@pytest.mark.asyncio
async def test_prefix_handling(s3, monkeypatch):
    monkeypatch.setattr(settings, "VAULT_S3_PREFIX", "/vault/prod/")
    VaultStorageService.reset_s3_store()
    await _upload()
    keys = [o["Key"] for o in s3.list_objects_v2(Bucket=BUCKET)["Contents"]]
    assert keys == [f"vault/prod/{PATH}"]
    assert await VaultStorageService.download_bytes(PATH) == b"hello"
    await VaultStorageService.move_file(PATH, "a/b.pdf")
    keys = [o["Key"] for o in s3.list_objects_v2(Bucket=BUCKET)["Contents"]]
    assert keys == ["vault/prod/a/b.pdf"]


@pytest.mark.asyncio
async def test_presigned_url(s3):
    await _upload()
    url = await VaultStorageService.generate_download_url(PATH, 120, file_name="a.pdf", mime_type="application/pdf")
    assert url and BUCKET in url and "X-Amz-Signature" in url and "X-Amz-Expires=120" in url
    assert "response-content-disposition" in url


@pytest.mark.asyncio
async def test_presigned_none_for_other_providers():
    assert await VaultStorageService.generate_download_url(PATH) is None


@pytest.mark.asyncio
async def test_s3_without_bucket_fails_clearly(monkeypatch):
    monkeypatch.setattr(settings, "VAULT_STORAGE_PROVIDER", "s3")
    monkeypatch.setattr(settings, "VAULT_S3_BUCKET", None)
    VaultStorageService.reset_s3_store()
    with pytest.raises(RuntimeError, match="VAULT_S3_BUCKET"):
        await VaultStorageService.download_bytes(PATH)
    VaultStorageService.reset_s3_store()
