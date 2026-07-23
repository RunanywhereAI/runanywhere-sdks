#!/usr/bin/env python3
"""Build the immutable Sherpa-ONNX bundle for NVIDIA Parakeet CTC 1.1B.

The reviewed OpenVoiceOS INT8 export has the graph contract Sherpa expects, but
its ONNX ModelProto omits three custom-metadata entries read by Sherpa's NeMo
CTC loader. This tool verifies the exact pinned inputs, copies them without
deserializing the 1.11 GB graph, appends the missing protobuf metadata, renames
the already-Sherpa-formatted vocabulary to ``tokens.txt``, and emits a receipt.

It intentionally does not upload or register the derived artifact. Publication
must preserve the source revision, source hashes, generated hashes, and license
recorded in ``bundle-manifest.json``.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
from typing import Iterable


SOURCE_REPOSITORY = "OpenVoiceOS/nvidia-parakeet-ctc-1.1b-onnx"
SOURCE_REVISION = "3ca664a2f106622d599052b4e4ecee5fdfc7e2e5"
SOURCE_LICENSE = "CC-BY-4.0"


@dataclass(frozen=True)
class SourceFile:
    filename: str
    size_bytes: int
    sha256: str


@dataclass(frozen=True)
class BundleSpec:
    repository: str
    revision: str
    license: str
    model: SourceFile
    tokens: SourceFile
    metadata: tuple[tuple[str, str], ...]


PARAKEET_CTC_1_1B = BundleSpec(
    repository=SOURCE_REPOSITORY,
    revision=SOURCE_REVISION,
    license=SOURCE_LICENSE,
    model=SourceFile(
        filename="model.int8.onnx",
        size_bytes=1_110_014_069,
        sha256="a16056c0a0d8df38c7b57cb019062df116e9e565203c6f25d6ea0c0c1122c84d",
    ),
    tokens=SourceFile(
        filename="vocab.txt",
        size_bytes=10_374,
        sha256="ed16e1a4e3a3aa379138c0b1888e5d49f993c9d512b2be4d46e90a87afd54921",
    ),
    metadata=(
        ("vocab_size", "1025"),
        ("subsampling_factor", "8"),
        ("normalize_type", "per_feature"),
    ),
)


def _encode_varint(value: int) -> bytes:
    if value < 0:
        raise ValueError("protobuf varints must be non-negative")
    encoded = bytearray()
    while value >= 0x80:
        encoded.append((value & 0x7F) | 0x80)
        value >>= 7
    encoded.append(value)
    return bytes(encoded)


def _length_delimited(field_number: int, payload: bytes) -> bytes:
    if field_number <= 0:
        raise ValueError("protobuf field numbers must be positive")
    key = (field_number << 3) | 2
    return _encode_varint(key) + _encode_varint(len(payload)) + payload


def metadata_suffix(entries: Iterable[tuple[str, str]]) -> bytes:
    """Serialize ONNX ModelProto.metadata_props entries (field 14).

    Protobuf fields may be serialized in any order, so appending repeated field
    14 entries is equivalent to a full parse-and-reserialize while avoiding a
    second in-memory copy of the 1.11 GB tensor payload.
    """

    suffix = bytearray()
    seen: set[str] = set()
    for key, value in entries:
        if not key or key in seen:
            raise ValueError(f"metadata key must be non-empty and unique: {key!r}")
        seen.add(key)
        entry = _length_delimited(1, key.encode("utf-8"))
        entry += _length_delimited(2, value.encode("utf-8"))
        suffix += _length_delimited(14, entry)
    return bytes(suffix)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_source(path: Path, expected: SourceFile) -> None:
    if not path.is_file():
        raise ValueError(f"missing source file: {path}")
    actual_size = path.stat().st_size
    if actual_size != expected.size_bytes:
        raise ValueError(
            f"source size mismatch for {path.name}: "
            f"expected {expected.size_bytes}, got {actual_size}"
        )
    actual_sha256 = _sha256(path)
    if actual_sha256 != expected.sha256:
        raise ValueError(
            f"source SHA-256 mismatch for {path.name}: "
            f"expected {expected.sha256}, got {actual_sha256}"
        )


def _source_url(spec: BundleSpec, filename: str) -> str:
    return f"https://huggingface.co/{spec.repository}/resolve/{spec.revision}/{filename}"


def prepare_bundle(
    source_dir: Path,
    output_dir: Path,
    spec: BundleSpec = PARAKEET_CTC_1_1B,
) -> dict:
    source_dir = source_dir.resolve()
    output_dir = output_dir.resolve()
    source_model = source_dir / spec.model.filename
    source_tokens = source_dir / spec.tokens.filename

    _verify_source(source_model, spec.model)
    _verify_source(source_tokens, spec.tokens)

    output_dir.mkdir(parents=True, exist_ok=True)
    output_model = output_dir / "model.int8.onnx"
    output_tokens = output_dir / "tokens.txt"
    output_manifest = output_dir / "bundle-manifest.json"
    destinations = (output_model, output_tokens, output_manifest)
    existing = [str(path) for path in destinations if path.exists()]
    if existing:
        raise ValueError("refusing to overwrite existing bundle output: " + ", ".join(existing))

    suffix = metadata_suffix(spec.metadata)
    model_partial = output_dir / ".model.int8.onnx.partial"
    tokens_partial = output_dir / ".tokens.txt.partial"
    manifest_partial = output_dir / ".bundle-manifest.json.partial"
    partials = (model_partial, tokens_partial, manifest_partial)
    if any(path.exists() for path in partials):
        raise ValueError("refusing to reuse an existing partial bundle output")

    try:
        with source_model.open("rb") as source, model_partial.open("xb") as target:
            shutil.copyfileobj(source, target, length=8 * 1024 * 1024)
            target.write(suffix)
            target.flush()
            os.fsync(target.fileno())

        with source_tokens.open("rb") as source, tokens_partial.open("xb") as target:
            shutil.copyfileobj(source, target, length=1024 * 1024)
            target.flush()
            os.fsync(target.fileno())

        output_model_sha256 = _sha256(model_partial)
        output_tokens_sha256 = _sha256(tokens_partial)
        manifest = {
            "schema": "runanywhere-sherpa-derived-bundle/v1",
            "model": "nvidia/parakeet-ctc-1.1b",
            "runtime": "sherpa-onnx offline NeMo CTC",
            "license": spec.license,
            "source": {
                "repository": spec.repository,
                "revision": spec.revision,
                "files": [
                    {
                        "filename": spec.model.filename,
                        "url": _source_url(spec, spec.model.filename),
                        "size_bytes": spec.model.size_bytes,
                        "sha256": spec.model.sha256,
                    },
                    {
                        "filename": spec.tokens.filename,
                        "url": _source_url(spec, spec.tokens.filename),
                        "size_bytes": spec.tokens.size_bytes,
                        "sha256": spec.tokens.sha256,
                    },
                ],
            },
            "transform": {
                "onnx_model_proto_field": 14,
                "metadata_props": dict(spec.metadata),
                "vocabulary_rename": f"{spec.tokens.filename} -> tokens.txt",
                "appended_bytes": len(suffix),
            },
            "files": [
                {
                    "filename": output_model.name,
                    "size_bytes": model_partial.stat().st_size,
                    "sha256": output_model_sha256,
                },
                {
                    "filename": output_tokens.name,
                    "size_bytes": tokens_partial.stat().st_size,
                    "sha256": output_tokens_sha256,
                },
            ],
        }
        manifest_partial.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

        os.replace(model_partial, output_model)
        os.replace(tokens_partial, output_tokens)
        os.replace(manifest_partial, output_manifest)
        return manifest
    except BaseException:
        for partial in partials:
            partial.unlink(missing_ok=True)
        raise


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-dir",
        required=True,
        type=Path,
        help="Directory containing the exact pinned model.int8.onnx and vocab.txt inputs",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="New/empty directory that will receive the derived immutable bundle",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        manifest = prepare_bundle(args.source_dir, args.output_dir)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    files = {entry["filename"]: entry for entry in manifest["files"]}
    print(
        "Prepared provenance-pinned Sherpa bundle: "
        f"model={files['model.int8.onnx']['sha256']} "
        f"tokens={files['tokens.txt']['sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
