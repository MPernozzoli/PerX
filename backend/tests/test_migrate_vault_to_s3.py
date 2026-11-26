"""Test della logica core dello script di migrazione vault -> S3 (moto + sorgente finta)."""
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

from app.services.vault_storage_service import S3ObjectStore

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "migrate_vault_to_s3.py"
spec = importlib.util.spec_from_file_location("migrate_vault_to_s3", SCRIPT)
mig = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mig
spec.loader.exec_module(mig)

BUCKET = "mig-test"


class FakeSource:
    def __init__(self, files):
        self.files = files
        self.reads = []

    def read(self, path):
        self.reads.append(path)
        if path not in self.files:
            raise FileNotFoundError(path)
        return self.files[path]


@pytest.fixture
def dest(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    with mock_aws():
        client = boto3.client("s3", region_name="eu-south-1")
        client.create_bucket(Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": "eu-south-1"})
        yield S3ObjectStore(bucket=BUCKET, region="eu-south-1", prefix="vault")


def entry(path, content):
    return mig.FileEntry(path, len(content), hashlib.sha256(content).hexdigest())


def test_dry_run_copies_nothing(dest):
    src = FakeSource({"a.pdf": b"A"})
    report = mig.run_migration([entry("a.pdf", b"A")], src, dest, execute=False)
    assert report.would_copy == ["a.pdf"] and not report.copied
    assert dest.head("a.pdf") is None and src.reads == []


def test_execute_copy_verify_and_idempotent(dest):
    files = {"a.pdf": b"A", "dir/b.pdf": b"BB"}
    src = FakeSource(files)
    entries = [entry(p, c) for p, c in files.items()]
    r1 = mig.run_migration(entries, src, dest, execute=True, concurrency=2)
    assert sorted(r1.copied) == sorted(files) and not r1.failed
    assert dest.get("dir/b.pdf") == b"BB"
    head = dest.head("a.pdf")
    assert head["ServerSideEncryption"] == "AES256"
    assert head["Metadata"]["sha256"] == hashlib.sha256(b"A").hexdigest()
    assert dest.client.list_objects_v2(Bucket=BUCKET)["Contents"][0]["Key"].startswith("vault/")

    src.reads.clear()
    r2 = mig.run_migration(entries, src, dest, execute=True)
    assert sorted(r2.skipped) == sorted(files) and not r2.copied
    assert src.reads == []  # skip senza rileggere la sorgente


def test_skip_without_db_checksum_reads_source_but_does_not_rewrite(dest):
    src = FakeSource({"a.pdf": b"A"})
    mig.run_migration([entry("a.pdf", b"A")], src, dest, execute=True)
    r = mig.run_migration([mig.FileEntry("a.pdf")], src, dest, execute=True)
    assert r.skipped == ["a.pdf"] and not r.copied


def test_changed_content_is_recopied(dest):
    src = FakeSource({"a.pdf": b"A"})
    mig.run_migration([entry("a.pdf", b"A")], src, dest, execute=True)
    src.files["a.pdf"] = b"A2"
    r = mig.run_migration([entry("a.pdf", b"A2")], src, dest, execute=True)
    assert r.copied == ["a.pdf"] and dest.get("a.pdf") == b"A2"


def test_missing_at_source_and_db_checksum_warning(dest):
    src = FakeSource({"b.pdf": b"real"})
    bad = mig.FileEntry("b.pdf", 4, "0" * 64)
    r = mig.run_migration([mig.FileEntry("gone.pdf"), bad], src, dest, execute=True)
    assert r.missing_at_source == ["gone.pdf"]
    assert r.copied == ["b.pdf"] and r.warnings


def test_failures_reported_and_source_untouched(dest, monkeypatch):
    src = FakeSource({"a.pdf": b"A"})
    monkeypatch.setattr(dest, "put", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")))
    r = mig.run_migration([entry("a.pdf", b"A")], src, dest, execute=True)
    assert r.failed and r.failed[0]["path"] == "a.pdf"
    assert src.files == {"a.pdf": b"A"}


def test_verification_failure_detected(dest, monkeypatch):
    src = FakeSource({"a.pdf": b"A"})
    monkeypatch.setattr(dest, "get", lambda p: b"corrupted")
    r = mig.run_migration([entry("a.pdf", b"A")], src, dest, execute=True)
    assert r.failed and "SHA-256" in r.failed[0]["error"]


def test_state_file_resume_and_dedupe(dest, tmp_path):
    state = str(tmp_path / "state.txt")
    src = FakeSource({"a.pdf": b"A", "b.pdf": b"B"})
    entries = [entry("a.pdf", b"A"), entry("a.pdf", b"A"), entry("b.pdf", b"B")]
    r1 = mig.run_migration(entries, src, dest, execute=True, state_file=state)
    assert r1.total == 2 and len(r1.copied) == 2
    src.reads.clear()
    r2 = mig.run_migration(entries, src, dest, execute=True, state_file=state)
    assert not r2.copied and len(r2.skipped) == 2 and src.reads == []


def test_local_source_blocks_traversal(tmp_path):
    root = tmp_path / "vault"
    root.mkdir()
    (root / "a.txt").write_bytes(b"x")
    (tmp_path / "secret.txt").write_bytes(b"s")
    s = mig.LocalSource(str(root))
    assert s.read("a.txt") == b"x"
    with pytest.raises(FileNotFoundError):
        s.read("../secret.txt")


def test_cli_execute_requires_explicit_config(capsys, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "VAULT_S3_BUCKET", None)
    monkeypatch.setattr(settings, "MAC_MINI_STORAGE_URL", None)
    monkeypatch.setattr(settings, "MAC_MINI_STORAGE_TOKEN", None)
    called = []
    lister = lambda providers: called.append(providers) or []  # noqa: E731
    assert mig.main(["--execute"], list_entries=lister) == 2
    assert mig.main(["--execute", "--source", "local", "--bucket", "b"], list_entries=lister) == 2
    assert mig.main(["--execute", "--source", "mac_mini", "--bucket", "b"], list_entries=lister) == 2
    assert mig.main(["--execute", "--source", "local", "--source-root", "/x"], list_entries=lister) == 2
    assert called == []


def test_cli_dry_run_default_and_report(dest, tmp_path):
    out = tmp_path / "r.json"
    entries = [entry("a.pdf", b"A")]
    code = mig.main(
        ["--bucket", BUCKET, "--report", str(out)],
        list_entries=lambda providers: entries,
        dest_factory=lambda a: dest,
    )
    data = json.loads(out.read_text())
    assert code == 0 and data["dry_run"] is True and data["counts"]["would_copy"] == 1


def test_cli_execute_end_to_end(dest, tmp_path):
    root = tmp_path / "vault"
    root.mkdir()
    (root / "a.pdf").write_bytes(b"A")
    out = tmp_path / "r.json"
    code = mig.main(
        ["--execute", "--source", "local", "--source-root", str(root), "--bucket", BUCKET, "--report", str(out)],
        list_entries=lambda providers: [entry("a.pdf", b"A"), mig.FileEntry("nope.pdf")],
        dest_factory=lambda a: dest,
    )
    data = json.loads(out.read_text())
    assert code == 0
    assert data["counts"]["copied"] == 1 and data["counts"]["missing_at_source"] == 1
    assert (root / "a.pdf").read_bytes() == b"A"
