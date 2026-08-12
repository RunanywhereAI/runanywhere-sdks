#!/usr/bin/env python3
"""Refuse to publish a backend plugin that cannot serve its primitives.

WHY THIS GATE EXISTS
--------------------
`@runanywhere/electron-sherpa` 0.20.17 shipped a 33 KB `librunanywhere_sherpa.dylib`
that referenced none of `g_sherpa_{stt,tts,vad}_ops`. It had been compiled with
`RAC_SHERPA_ROUTABLE=0`, so its `sherpa_capability_check()` returned
`RAC_ERROR_BACKEND_UNAVAILABLE` unconditionally and the plugin registry
correctly refused it with -811 every single time. The package installed
cleanly, imported cleanly, registered a plugin path cleanly, and delivered no
STT, no TTS and no VAD. Nothing in packaging noticed, because packaging only
ever checked that FILES existed.

A file existing is not the contract. The contract is that the shipped plugin
references the ops tables its engine's primitives are dispatched through. This
script checks that, and it is the reason a stub cannot be published again.

WHAT "REFERENCES" MEANS, AND WHY IT IS NOT "EXPORTS"
---------------------------------------------------
The in-tree plugins are thin CARRIERS: `librunanywhere_sherpa` compiles only
the entry TU and links the real engine from a sibling
`librac_backend_sherpa.dylib`. So the ops tables are UNDEFINED (imported)
symbols in the carrier, not defined ones — a healthy carrier and a stub carrier
are both ~33 KB, and `nm -gU | grep g_sherpa` returns 0 for BOTH. Size and
exported-symbol counts are therefore useless signals. What separates them is
whether the ops names appear at all:

    healthy: nm -u librunanywhere_sherpa.dylib | grep g_sherpa_ -> 3
    stub:    nm -u librunanywhere_sherpa.dylib | grep g_sherpa_ -> 0

That is what this script measures: defined OR undefined, either counts, because
either proves the entry TU compiled its routable branch.

USAGE
    check_plugin_natives.py <path> [<path> ...]     # files and/or directories
    check_plugin_natives.py --tarball <pkg.tgz>     # an npm tarball
    check_plugin_natives.py --tarball <pkg.tgz> --expect-version 0.20.18
Exit 0 when every plugin found is routable, 1 otherwise. A tarball whose name
is a known backend package (electron-llamacpp/onnx/sherpa/qhexrt) with ZERO
plugin natives is a failure — that is how @runanywhere/electron-qhexrt 0.20.17
shipped as JS-only. Core / proto-ts tarballs with no plugins still pass.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# The contract, per backend.
#
# Each entry lists ops tables the plugin's entry TU references on its ROUTABLE
# branch and drops on its stub branch — i.e. exactly the symbols whose absence
# means "this plugin will decline every primitive it advertises".
#
# `g_llamacpp_{vlm,rerank,embeddings}_ops` vary by build, so requiring them
# would fail honest builds. One required symbol per backend is enough to
# separate routable from stub; this is a stub detector, not a feature
# inventory.
#
# ONNX embeddings are the exception: Electron packaging (the only caller of
# this gate) always builds with RAC_BACKEND_RAG=ON, and the carrier recompiles
# rac_plugin_entry_onnx.cpp. If RAC_BACKEND_RAG does not reach that TU, the
# plugin still loads and still serves segment/diarize — it just silently
# drops EMBED. Segmentation+diarization alone cannot catch that. Require
# g_onnx_embeddings_ops so a RAG-dropped carrier cannot ship.
# ---------------------------------------------------------------------------
REQUIRED_OPS: dict[str, tuple[str, ...]] = {
    "sherpa": ("g_sherpa_stt_ops", "g_sherpa_tts_ops", "g_sherpa_vad_ops"),
    "llamacpp": ("g_llamacpp_ops",),
    "onnx": ("g_onnx_segmentation_ops", "g_onnx_diarization_ops", "g_onnx_embeddings_ops"),
    "qhexrt": ("g_qhexrt_llm_ops",),
}

# Shared-library file name -> backend id. Mirrors entry_symbol_from_path() in
# core/src/plugin/plugin_loader.cpp: strip `lib`, strip `runanywhere_`, strip
# the extension. The plugin FILE NAME is a load-bearing contract (the loader
# derives `rac_plugin_entry_<id>` from it), so parsing it here is legitimate.
PLUGIN_NAME_RE = re.compile(r"^(?:lib)?runanywhere_(?P<id>[A-Za-z0-9_]+)\.(?:so|dylib|dll)$")
COMMONS_NAME_RE = re.compile(r"^(?:lib)?rac_commons\.(?:so|dylib|dll)$")
# npm pack names: runanywhere-electron-sherpa-0.20.17.tgz
BACKEND_TARBALL_RE = re.compile(
    r"electron-(?P<id>llamacpp|onnx|sherpa|qhexrt)-"
)

# QHexRT has no carrier: the engine IS the plugin, renamed via OUTPUT_NAME on
# shared builds, so it matches the pattern above. Its Android/JNI form keeps the
# target name, which is not a plugin and is not gated here.


class Finding:
    def __init__(self, path: Path, backend: str, missing: list[str], method: str):
        self.path = path
        self.backend = backend
        self.missing = missing
        self.method = method


def _run(cmd: list[str]) -> str | None:
    """Run a symbol dumper, returning stdout or None if it is unusable here."""
    if shutil.which(cmd[0]) is None:
        return None
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0 or not out.stdout.strip():
        return None
    return out.stdout


def symbol_text(path: Path) -> tuple[str, str]:
    """Everything the platform's tooling will tell us about `path`'s symbols.

    Returns (text, method). Tries real symbol dumpers first for precision, then
    falls back to reading the file as bytes: a symbol's NAME lives in the string
    table of Mach-O, ELF and PE alike, whether it is exported or imported, so a
    byte scan answers "is this name referenced at all" on every platform even
    when no toolchain is installed (a release runner, a Windows box without the
    VS command prompt). Same technique scripts/build/build-core-android.sh
    already uses for the `qhexrt:engine-available` marker.
    """
    for cmd, method in (
        (["nm", "-a", str(path)], "nm -a"),
        (["nm", "-D", "--undefined-only", str(path)], "nm -D"),
        (["llvm-nm", "-a", str(path)], "llvm-nm -a"),
        (["dumpbin", "/imports", "/exports", str(path)], "dumpbin"),
    ):
        text = _run(cmd)
        if text:
            return text, method
    return path.read_bytes().decode("latin-1"), "byte scan"


def check_plugin(path: Path) -> Finding | None:
    match = PLUGIN_NAME_RE.match(path.name)
    if match is None:
        return None
    backend = match.group("id")
    required = REQUIRED_OPS.get(backend)
    if required is None:
        # An out-of-tree plugin we have no contract for. Not our call to fail.
        return None
    text, method = symbol_text(path)
    missing = [sym for sym in required if sym not in text]
    return Finding(path, backend, missing, method)


def collect(paths: list[Path]) -> list[Path]:
    found: list[Path] = []
    for path in paths:
        if path.is_dir():
            for child in sorted(path.rglob("*")):
                if child.is_file() and PLUGIN_NAME_RE.match(child.name):
                    found.append(child)
        elif path.is_file():
            found.append(path)
    return found


def tarball_backend_id(name: str) -> str | None:
    match = BACKEND_TARBALL_RE.search(name)
    return match.group("id") if match else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="plugin files or directories")
    parser.add_argument("--tarball", type=Path, action="append", default=[],
                        help="npm tarball to inspect (repeatable)")
    parser.add_argument("--expect-version", default="",
                        help="RAC_VERSION_STRING that every bundled rac_commons must embed")
    args = parser.parse_args()

    if not args.paths and not args.tarball:
        parser.error("nothing to check: pass paths and/or --tarball")

    findings: list[Finding] = []
    empty_backends: list[str] = []
    version_mismatches: list[str] = []
    checked = 0

    with tempfile.TemporaryDirectory() as tmp:
        targets = collect(args.paths)
        for archive in args.tarball:
            if not archive.is_file():
                print(f"ERROR: no such tarball: {archive}", file=sys.stderr)
                return 1
            dest = Path(tmp) / archive.name.replace(".", "_")
            plugin_count = 0
            with tarfile.open(archive, "r:gz") as bundle:
                for member in bundle.getmembers():
                    if not member.isfile():
                        continue
                    leaf = Path(member.name).name
                    src = bundle.extractfile(member)
                    if src is None:
                        continue
                    payload = src.read()
                    if PLUGIN_NAME_RE.match(leaf):
                        out = dest / leaf
                        out.parent.mkdir(parents=True, exist_ok=True)
                        out.write_bytes(payload)
                        targets.append(out)
                        plugin_count += 1
                    elif args.expect_version and COMMONS_NAME_RE.match(leaf):
                        if args.expect_version.encode("ascii") not in payload:
                            version_mismatches.append(
                                f"{archive.name}: {leaf} does not embed "
                                f"{args.expect_version!r}"
                            )
                        else:
                            print(f"  ok    version  {leaf}  embeds {args.expect_version}")
            required_id = tarball_backend_id(archive.name)
            if required_id is not None and plugin_count == 0:
                print(f"  FAIL  {archive.name}  no runanywhere_{required_id} native in tarball")
                empty_backends.append(
                    f"{archive.name}: backend package '{required_id}' ships no plugin native"
                )

        for target in targets:
            finding = check_plugin(target)
            if finding is None:
                continue
            checked += 1
            label = f"{finding.backend:<9} {finding.path.name}"
            if finding.missing:
                print(f"  FAIL  {label}  [{finding.method}]  missing: "
                      f"{', '.join(finding.missing)}")
                findings.append(finding)
            else:
                print(f"  ok    {label}  [{finding.method}]  "
                      f"references all {len(REQUIRED_OPS[finding.backend])} ops tables")

    failed = bool(findings or empty_backends or version_mismatches)
    if not failed and checked == 0:
        print("  no backend plugin natives found (nothing to verify)")
        return 0

    if failed:
        print("\nERROR: these plugins must not be published:")
        for finding in findings:
            print(f"  - {finding.path}")
            print(f"      backend '{finding.backend}' does not reference "
                  f"{', '.join(finding.missing)}")
        for line in empty_backends:
            print(f"  - {line}")
        for line in version_mismatches:
            print(f"  - {line}")
        print(
            "\nA plugin missing its ops tables was compiled with its engine\n"
            "unavailable: capability_check() will decline registration and the\n"
            "backend will serve nothing. Rebuild it with the engine present\n"
            "(check the *_AVAILABLE compile definitions actually reach the\n"
            "carrier target that compiles rac_plugin_entry_<id>.cpp) before\n"
            "packaging. A backend tarball with no plugin native at all is the\n"
            "same class of defect — JS that cannot load an engine."
        )
        return 1

    print(f"\nAll {checked} backend plugin native(s) are routable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
