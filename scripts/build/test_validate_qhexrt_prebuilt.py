import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
VALIDATOR = HERE / "validate-qhexrt-prebuilt.py"


def _run(prebuilt, check=False):
    return subprocess.run(
        [sys.executable, os.fspath(VALIDATOR), "--prebuilt", os.fspath(prebuilt),
         "--android-abi", "arm64-v8a"],
        check=check,
        capture_output=True,
        text=True,
    )


def _tree(tmp_path):
    prebuilt = tmp_path / "prebuilt"
    payloads = {
        "include/qhexrt/qhexrt_c.h": b"header",
        "lib/arm64-v8a/libqhexrt_core.a": b"!<arch>\ncore",
        "lib/arm64-v8a/libqhexrt_host.a": b"!<arch>\nhost",
    }
    files = {
        relative: {"sha256": hashlib.sha256(payload).hexdigest(), "size_bytes": len(payload)}
        for relative, payload in payloads.items()
    }
    source = {"git_sha": "b" * 40, "git_dirty": False, "state_sha256": "c" * 64}
    build = {
                "android_abi": "arm64-v8a",
                "build_type": "Release",
                "cmake_cache_sha256": "d" * 64,
                "cmake_system": {
                    "name": "Android", "processor": "aarch64", "crosscompiling": "TRUE",
                    "state_file_sha256": "e" * 64,
                },
                "compiler": {
                    "id": "Clang", "version": "18.0.4",
                    "state_file_sha256": "1" * 64, "sha256": "2" * 64,
                    "version_output_sha256": "3" * 64,
                },
                "ndk": {"metadata_file": "source.properties", "metadata_sha256": "4" * 64},
                "qnn_sdk": {"metadata_file": "sdk.yaml", "metadata_sha256": "5" * 64},
                "archive_evidence": {
                    "llvm_ar_sha256": "6" * 64, "llvm_readelf_sha256": "7" * 64,
                    "core": {"member_count": 1}, "host": {"member_count": 1},
                },
            }
    receipt = {
        "schema": "qhexrt-build-receipt/v1",
        "qhexrt_version": "1.0.0",
        "c_abi": {"major": 1, "minor": 0},
        "source": source,
        "build": build,
        "artifacts": files,
    }
    receipt_bytes = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode()
    receipt_sha = hashlib.sha256(receipt_bytes).hexdigest()
    version = prebuilt / f"versions/{receipt_sha}"
    for relative, payload in payloads.items():
        path = version / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
    (version / "qhexrt-build-receipt.json").write_bytes(receipt_bytes)
    (version / "qhexrt-prebuilt.json").write_text(
        json.dumps({
            "schema": "qhexrt-prebuilt/v2",
            "build_receipt_sha256": receipt_sha,
            "qhexrt_version": receipt["qhexrt_version"],
            "c_abi": receipt["c_abi"],
            "android_abi": "arm64-v8a",
            "source": source,
            "build": build,
            "files": files,
        }),
        encoding="utf-8",
    )
    (prebuilt / "current").symlink_to(f"versions/{receipt_sha}")
    return prebuilt, version


def test_absent_selection_is_public_stub_status(tmp_path):
    result = _run(tmp_path / "prebuilt")
    assert result.returncode == 3
    assert result.stderr == ""


def test_legacy_payload_without_current_requires_restage(tmp_path):
    prebuilt = tmp_path / "prebuilt"
    (prebuilt / "include").mkdir(parents=True)
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "legacy QHexRT prebuilt" in result.stderr
    assert "stage_prebuilt_for_sdk.sh" in result.stderr


def test_valid_current_prints_immutable_version(tmp_path):
    prebuilt, version = _tree(tmp_path)
    result = _run(prebuilt, check=True)
    assert Path(result.stdout.strip()) == version.resolve()


def test_broken_partial_or_tampered_current_fails_closed(tmp_path):
    prebuilt, version = _tree(tmp_path)
    (version / "lib/arm64-v8a/libqhexrt_core.a").write_bytes(b"tampered")
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "identity mismatch" in result.stderr

    (prebuilt / "current").unlink()
    (prebuilt / "current").symlink_to(f"versions/{'f' * 64}")
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "broken" in result.stderr


def test_current_must_be_atomic_symlink_not_legacy_directory(tmp_path):
    current = tmp_path / "prebuilt/current"
    current.mkdir(parents=True)
    result = _run(tmp_path / "prebuilt")
    assert result.returncode == 1
    assert "must be an atomic symlink" in result.stderr


def test_prebuilt_root_must_not_redirect_through_symlink(tmp_path):
    real = tmp_path / "real-prebuilt"
    real.mkdir()
    redirected = tmp_path / "prebuilt"
    redirected.symlink_to(real, target_is_directory=True)
    result = _run(redirected)
    assert result.returncode == 1
    assert "root must not be a symlink" in result.stderr


def test_version_directory_must_match_receipt_and_payload_paths_must_not_symlink(tmp_path):
    prebuilt, version = _tree(tmp_path)
    renamed = version.with_name("f" * 64)
    version.rename(renamed)
    (prebuilt / "current").unlink()
    (prebuilt / "current").symlink_to(f"versions/{renamed.name}")
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "version name" in result.stderr

    renamed.rename(version)
    (prebuilt / "current").unlink()
    (prebuilt / "current").symlink_to(f"versions/{version.name}")
    include = version / "include"
    real_include = version / "real-include"
    include.rename(real_include)
    include.symlink_to("real-include")
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "traverses a symlink" in result.stderr


def test_selected_version_entry_must_not_be_a_symlink(tmp_path):
    prebuilt, version = _tree(tmp_path)
    alias = version.with_name("f" * 64)
    alias.symlink_to(version.name, target_is_directory=True)
    (prebuilt / "current").unlink()
    (prebuilt / "current").symlink_to(f"versions/{alias.name}")
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "immutable version must not be a symlink" in result.stderr


def test_sdk_metadata_identity_filename_cannot_escape_selected_root(tmp_path):
    prebuilt, version = _tree(tmp_path)
    receipt_path = version / "qhexrt-build-receipt.json"
    receipt = json.loads(receipt_path.read_text())
    receipt["build"]["qnn_sdk"]["metadata_file"] = "../sdk.yaml"
    receipt_bytes = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode()
    receipt_path.write_bytes(receipt_bytes)
    new_sha = hashlib.sha256(receipt_bytes).hexdigest()
    manifest_path = version / "qhexrt-prebuilt.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["build"] = receipt["build"]
    manifest["build_receipt_sha256"] = new_sha
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    renamed = version.with_name(new_sha)
    version.rename(renamed)
    (prebuilt / "current").unlink()
    (prebuilt / "current").symlink_to(f"versions/{new_sha}")
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "incomplete qnn_sdk identity" in result.stderr


def test_coordinated_payload_and_manifest_mutation_cannot_impersonate_receipt(tmp_path):
    prebuilt, version = _tree(tmp_path)
    header = version / "include/qhexrt/qhexrt_c.h"
    header.write_bytes(b"changed header")
    manifest_path = version / "qhexrt-prebuilt.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["files"]["include/qhexrt/qhexrt_c.h"] = {
        "sha256": hashlib.sha256(header.read_bytes()).hexdigest(),
        "size_bytes": header.stat().st_size,
    }
    manifest["source"]["state_sha256"] = "9" * 64
    manifest["build"]["qnn_sdk"]["metadata_sha256"] = "8" * 64
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    result = _run(prebuilt)
    assert result.returncode == 1
    assert "does not exactly derive" in result.stderr


if __name__ == "__main__":
    tests = sorted((name, value) for name, value in globals().items() if name.startswith("test_") and callable(value))
    for name, test in tests:
        with tempfile.TemporaryDirectory(prefix=f"{name}-") as temporary:
            test(Path(temporary))
    print(f"{len(tests)} QHexRT prebuilt validator tests passed")
