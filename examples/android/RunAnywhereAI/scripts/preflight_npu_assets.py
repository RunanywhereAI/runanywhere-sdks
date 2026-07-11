#!/usr/bin/env python3
"""Fail-fast validation for QHexRT suites/fixtures packaged in androidTest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys


SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def _strict_json(path: Path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise RuntimeError(f"duplicate JSON key in {path}: {key}")
            result[key] = value
        return result

    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs)


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_managed_path(raw: str) -> PurePosixPath:
    if not isinstance(raw, str) or not raw or "\\" in raw:
        raise RuntimeError(f"unsafe managed asset path: {raw!r}")
    path = PurePosixPath(raw)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise RuntimeError(f"unsafe managed asset path: {raw!r}")
    return path


def _asset_names(suite: dict) -> set[str]:
    names: set[str] = set()
    for case in suite.get("cases", []):
        if not isinstance(case, dict):
            raise RuntimeError("suite cases must be objects")
        inputs = case.get("input", {})
        if not isinstance(inputs, dict):
            raise RuntimeError("suite case input must be an object")
        for key, value in inputs.items():
            if key.endswith("_asset"):
                if not isinstance(value, str) or not value:
                    raise RuntimeError(f"suite asset field {key} must be a non-empty string")
                _safe_managed_path(value)
                names.add(value)
    return names


def _select_suite(assets: Path, model_id: str, arch: str) -> Path:
    suite_root = assets / "npu_suites"
    candidates = [suite_root / f"{model_id}.json", suite_root / f"{model_id}_{arch}.json"]
    selected = [path for path in candidates if path.is_file() and not path.is_symlink()]
    if not selected:
        raise RuntimeError(
            f"requested model {model_id!r} has no synced suite "
            f"({candidates[0].name} or {candidates[1].name})"
        )
    return selected[0]


def _select_ad_hoc_suite(assets: Path, repo: str, arch: str, modality: str) -> Path:
    modality_aliases = {
        "stt": {"asr", "asr_aed"},
        "asr": {"asr", "asr_aed"},
        "vlm": {"vlm", "vlm_image"},
        "embedding": {"embedding"},
        "embed": {"embedding"},
        "inpaint": {"inpaint"},
        "llm": {"llm"},
        "tts": {"tts"},
    }
    accepted_modalities = modality_aliases.get(modality, {modality})
    matches = []
    for path in sorted((assets / "npu_suites").glob("*.json")):
        if path.is_symlink() or not path.is_file():
            continue
        suite = _strict_json(path)
        if (
            suite.get("hf_repo") == repo
            and suite.get("arch") == arch
            and suite.get("modality") in accepted_modalities
        ):
            matches.append(path)
    if len(matches) != 1:
        raise RuntimeError(
            f"ad-hoc request repo={repo!r} arch={arch!r} modality={modality!r} "
            f"matched {len(matches)} synced suites; expected exactly one"
        )
    return matches[0]


def validate(
    assets: Path,
    model_ids: list[str],
    arch: str,
    hf_repo: str | None,
    modality: str | None,
) -> list[str]:
    if assets.is_symlink() or not assets.is_dir():
        raise RuntimeError(f"androidTest assets root is missing/not regular: {assets}")
    legacy_lama = sorted(path for path in assets.rglob("lama_hold_*") if path.is_file() or path.is_symlink())
    if legacy_lama:
        raise RuntimeError(
            "restricted legacy LaMa holdout assets must be deleted: "
            + ", ".join(path.relative_to(assets).as_posix() for path in legacy_lama)
        )
    manifest_path = assets / ".qhexrt_device_assets.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise RuntimeError("missing generated .qhexrt_device_assets.json")
    manifest = _strict_json(manifest_path)
    if set(manifest) != {"schema", "files"} or manifest.get("schema") != "qhexrt_android_asset_mirror/v1":
        raise RuntimeError("unsupported QHexRT Android asset-mirror manifest")
    managed = manifest.get("files")
    if not isinstance(managed, dict):
        raise RuntimeError("QHexRT Android asset-mirror files must be an object")
    for raw_name, digest in managed.items():
        path = _safe_managed_path(raw_name)
        if path.parts[0] not in {"npu_suites", "qhexrt_fixtures"}:
            raise RuntimeError(f"managed asset escapes QHexRT namespaces: {raw_name}")
        if not isinstance(digest, str) or not SHA256.fullmatch(digest):
            raise RuntimeError(f"managed asset has invalid SHA-256: {raw_name}")

    if hf_repo:
        if not modality:
            raise RuntimeError("ad-hoc asset preflight requires modality")
        suite_paths = [_select_ad_hoc_suite(assets, hf_repo, arch, modality)]
    else:
        suite_paths = [_select_suite(assets, model_id, arch) for model_id in model_ids]

    selected_ids = []
    for suite_path in suite_paths:
        suite_relative = suite_path.relative_to(assets).as_posix()
        suite = _strict_json(suite_path)
        if suite.get("schema") != "npu_suite/v1":
            raise RuntimeError(f"invalid suite schema: {suite_relative}")
        if suite.get("arch") != arch or not str(suite.get("model_id", "")).endswith(f"_{arch}"):
            raise RuntimeError(
                f"suite architecture does not match requested arch={arch}: {suite_relative} "
                f"payload_arch={suite.get('arch')!r}"
            )
        if managed.get(suite_relative) != _digest(suite_path):
            raise RuntimeError(f"suite is absent from/mismatched with mirror manifest: {suite_relative}")
        for asset_name in sorted(_asset_names(suite)):
            relative = f"qhexrt_fixtures/{asset_name}"
            path = assets / relative
            if path.is_symlink() or not path.is_file():
                raise RuntimeError(f"suite fixture is missing/not regular: {relative}")
            if managed.get(relative) != _digest(path):
                raise RuntimeError(f"suite fixture is absent from/mismatched with mirror manifest: {relative}")
        selected_ids.append(str(suite.get("model_id")))
    return selected_ids


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--arch", required=True)
    parser.add_argument("--model", action="append", default=[])
    parser.add_argument("--hf-repo")
    parser.add_argument("--modality")
    args = parser.parse_args()
    try:
        selected = validate(args.assets, args.model, args.arch, args.hf_repo, args.modality)
    except Exception as error:
        print(f"error: QHexRT Android asset preflight failed: {error}", file=sys.stderr)
        print(
            "Run QHexRT/device_suites/sync_android_assets.sh <runanywhere-sdks> "
            "or rerun this harness with --qhexrt-root <QHexRT checkout>.",
            file=sys.stderr,
        )
        return 1
    print("asset preflight: " + ", ".join(selected))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
