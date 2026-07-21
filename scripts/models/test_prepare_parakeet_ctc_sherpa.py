import hashlib
import importlib.util
import json
from pathlib import Path
import sys


SCRIPT = Path(__file__).with_name("prepare_parakeet_ctc_sherpa.py")
SPEC = importlib.util.spec_from_file_location("prepare_parakeet_ctc_sherpa", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _fixture_spec(model: bytes, tokens: bytes):
    return MODULE.BundleSpec(
        repository="example/source",
        revision="a" * 40,
        license="CC-BY-4.0",
        model=MODULE.SourceFile("model.int8.onnx", len(model), _sha256(model)),
        tokens=MODULE.SourceFile("vocab.txt", len(tokens), _sha256(tokens)),
        metadata=(
            ("vocab_size", "1025"),
            ("subsampling_factor", "8"),
            ("normalize_type", "per_feature"),
        ),
    )


def test_metadata_suffix_is_exact_modelproto_field_14_encoding():
    suffix = MODULE.metadata_suffix((("vocab_size", "1025"),))
    assert suffix == b"\x72\x12\x0a\x0avocab_size\x12\x041025"


def test_prepare_bundle_verifies_sources_and_emits_receipt(tmp_path):
    source = tmp_path / "source"
    output = tmp_path / "output"
    source.mkdir()
    # Empty ONNX ModelProto.graph field; sufficient for byte-level transform testing.
    model = b"\x3a\x00"
    tokens = b"<unk> 0\n<blk> 1024\n"
    (source / "model.int8.onnx").write_bytes(model)
    (source / "vocab.txt").write_bytes(tokens)
    spec = _fixture_spec(model, tokens)

    manifest = MODULE.prepare_bundle(source, output, spec)
    expected_model = model + MODULE.metadata_suffix(spec.metadata)
    assert (output / "model.int8.onnx").read_bytes() == expected_model
    assert (output / "tokens.txt").read_bytes() == tokens
    assert manifest["transform"]["appended_bytes"] == len(expected_model) - len(model)
    assert manifest["files"][0] == {
        "filename": "model.int8.onnx",
        "size_bytes": len(expected_model),
        "sha256": _sha256(expected_model),
    }
    receipt = json.loads((output / "bundle-manifest.json").read_text(encoding="utf-8"))
    assert receipt == manifest
    assert receipt["source"]["files"][0]["url"].endswith(
        f"/{spec.revision}/model.int8.onnx"
    )


def test_prepare_bundle_fails_closed_on_source_mismatch(tmp_path):
    source = tmp_path / "source"
    output = tmp_path / "output"
    source.mkdir()
    model = b"source model"
    tokens = b"tokens"
    (source / "model.int8.onnx").write_bytes(model + b"tampered")
    (source / "vocab.txt").write_bytes(tokens)

    try:
        MODULE.prepare_bundle(source, output, _fixture_spec(model, tokens))
    except ValueError as error:
        assert "size mismatch" in str(error)
    else:
        raise AssertionError("tampered source should fail")
    assert not output.exists()


def test_prepare_bundle_refuses_to_overwrite_outputs(tmp_path):
    source = tmp_path / "source"
    output = tmp_path / "output"
    source.mkdir()
    output.mkdir()
    model = b"source model"
    tokens = b"tokens"
    (source / "model.int8.onnx").write_bytes(model)
    (source / "vocab.txt").write_bytes(tokens)
    (output / "tokens.txt").write_bytes(b"keep me")

    try:
        MODULE.prepare_bundle(source, output, _fixture_spec(model, tokens))
    except ValueError as error:
        assert "refusing to overwrite" in str(error)
    else:
        raise AssertionError("existing output should fail")
    assert (output / "tokens.txt").read_bytes() == b"keep me"


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
    print(f"{len(tests)} Parakeet CTC bundle-preparation tests passed")
