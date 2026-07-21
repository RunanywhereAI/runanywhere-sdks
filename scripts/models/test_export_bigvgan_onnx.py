import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys


SCRIPT = Path(__file__).with_name("export_bigvgan_onnx.py")
SPEC = importlib.util.spec_from_file_location("export_bigvgan_onnx", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def test_model_source_verification_checks_size_and_hash(tmp_path):
    payloads = {
        "bigvgan_generator.pt": b"checkpoint",
        "config.json": b"{}\n",
        "LICENSE": b"MIT\n",
    }
    original = MODULE.MODEL_FILES
    MODULE.MODEL_FILES = tuple(
        MODULE.SourceFile(name, len(payload), _sha256(payload))
        for name, payload in payloads.items()
    )
    try:
        for name, payload in payloads.items():
            (tmp_path / name).write_bytes(payload)
        MODULE.verify_model_sources(tmp_path)

        (tmp_path / "config.json").write_bytes(b"tampered")
        try:
            MODULE.verify_model_sources(tmp_path)
        except ValueError as error:
            assert "size mismatch" in str(error) or "SHA-256 mismatch" in str(error)
        else:
            raise AssertionError("tampered model source should fail closed")
    finally:
        MODULE.MODEL_FILES = original


def test_code_checkout_requires_exact_clean_revision(tmp_path):
    git = shutil.which("git")
    if not git:
        return
    subprocess.run([git, "init", "-q", str(tmp_path)], check=True)
    subprocess.run([git, "-C", str(tmp_path), "config", "user.email", "test@example.com"], check=True)
    subprocess.run([git, "-C", str(tmp_path), "config", "user.name", "Test"], check=True)
    (tmp_path / "bigvgan.py").write_text("# fixture\n", encoding="utf-8")
    (tmp_path / "env.py").write_text("# fixture\n", encoding="utf-8")
    (tmp_path / "LICENSE").write_text("MIT\n", encoding="utf-8")
    (tmp_path / "incl_licenses").mkdir()
    (tmp_path / "incl_licenses" / "LICENSE_1").write_text("notice\n", encoding="utf-8")
    subprocess.run([git, "-C", str(tmp_path), "add", "."], check=True)
    subprocess.run([git, "-C", str(tmp_path), "commit", "-qm", "fixture"], check=True)
    revision = subprocess.run(
        [git, "-C", str(tmp_path), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()

    original = MODULE.CODE_REVISION
    MODULE.CODE_REVISION = revision
    try:
        MODULE.verify_code_checkout(tmp_path)
        (tmp_path / "bigvgan.py").write_text("# modified\n", encoding="utf-8")
        try:
            MODULE.verify_code_checkout(tmp_path)
        except ValueError as error:
            assert "modified tracked files" in str(error)
        else:
            raise AssertionError("modified source checkout should fail closed")
    finally:
        MODULE.CODE_REVISION = original


def test_metrics_enforces_expected_parity_fields():
    import numpy

    reference = numpy.asarray([[[0.0, 0.25, -0.5]]], dtype=numpy.float32)
    candidate = reference + numpy.asarray([[[1e-6, -2e-6, 3e-6]]], dtype=numpy.float32)
    result = MODULE._metrics(numpy, reference, candidate)
    assert result["reference_shape"] == [1, 1, 3]
    assert result["candidate_shape"] == [1, 1, 3]
    assert result["allclose_rtol_atol_1e-4"] is True
    assert 0.0 < result["max_abs"] < 1e-4


def test_parser_rejects_more_than_two_threads():
    parser = MODULE._parser()
    try:
        parser.parse_args(
            [
                "--model-dir",
                "model",
                "--code-dir",
                "code",
                "--output-dir",
                "output",
                "--threads",
                "3",
            ]
        )
    except SystemExit as error:
        assert error.code == 2
    else:
        raise AssertionError("thread cap should be enforced")


if __name__ == "__main__":
    tests = sorted(
        (name, value)
        for name, value in globals().items()
        if name.startswith("test_") and callable(value)
    )
    import tempfile

    for name, test in tests:
        if "tmp_path" in test.__code__.co_varnames:
            with tempfile.TemporaryDirectory(prefix=f"{name}-") as temporary:
                test(Path(temporary))
        else:
            test()
    print(f"{len(tests)} BigVGAN export tests passed")
