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

THE ENGINE THAT HAS NO CARRIER: QHEXRT
--------------------------------------
QHexRT is the exception, and an ops name cannot be its evidence. It keeps its
entry and its six op vtables in the SAME binary (engines/qhexrt/CMakeLists.txt
explains why: MSVC cannot resolve an imported data symbol whose declaration is
the plain `extern "C" const` shared with the ELF/Mach-O builds). A single-DLL
engine references those tables internally, so on a PE they are neither exported
nor imported and vanish from the file entirely — `g_qhexrt_llm_ops` scores zero
against a perfectly healthy win-arm64 NPU build that demonstrably generates
tokens.

Its evidence is instead the marker `qhexrt_backend_build_info()` returns, which
flips with the very same `RAC_QHEXRT_ROUTABLE` switch that admits the op tables,
and is a string literal so it survives on every object format. That marker is
already how scripts/build/build-core-android.sh and
scripts/release/prepublish_check.py answer this question; this gate now agrees
with them. It only survives MSVC because the declaration is exported — see
engines/qhexrt/qhexrt_backend.h.

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
    # Not an ops name: QHexRT has no carrier, so its tables are internal and a PE
    # keeps none of them. See "THE ENGINE THAT HAS NO CARRIER" above.
    "qhexrt": ("qhexrt:engine-available",),
}

# A token whose PRESENCE disproves routability, per backend. Requiring the
# positive marker above is already sufficient — these exist so the failure reads
# as the diagnosis it is ("you shipped the public shell") rather than as an
# absence, which is the difference between an actionable gate and a puzzling one.
# Mirrors check_qhexrt() in scripts/release/prepublish_check.py.
DISPROOF: dict[str, tuple[str, ...]] = {
    "qhexrt": ("qhexrt:engine-unavailable", "g_qhexrt_unavailable_vtable"),
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
    def __init__(self, path: Path, display: str, backend: str, missing: list[str],
                 disproved: list[str], method: str):
        self.path = path
        # Where the caller can find this plugin: the path they passed, or
        # "<tarball>:<archive-relative path>" for a tarball member. The basename
        # alone is ambiguous — one tarball ships the same file name once per
        # platform-arch — so every message uses this instead.
        self.display = display
        self.backend = backend
        self.missing = missing
        self.disproved = disproved
        self.method = method

    @property
    def failed(self) -> bool:
        return bool(self.missing or self.disproved)

    @property
    def reason(self) -> str:
        # A positive disproof is the more specific diagnosis, so lead with it.
        if self.disproved:
            return (f"shipped the NON-ROUTABLE shell — carries "
                    f"{', '.join(self.disproved)}")
        return f"does not reference {', '.join(self.missing)}"


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


def check_plugin(path: Path, display: str) -> Finding | None:
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
    disproved = [sym for sym in DISPROOF.get(backend, ()) if sym in text]
    return Finding(path, display, backend, missing, disproved, method)


def collect(paths: list[Path]) -> list[tuple[Path, str]]:
    found: list[tuple[Path, str]] = []
    for path in paths:
        if path.is_dir():
            for child in sorted(path.rglob("*")):
                if child.is_file() and PLUGIN_NAME_RE.match(child.name):
                    found.append((child, str(child)))
        elif path.is_file():
            found.append((path, str(path)))
    return found


def member_dest(root: Path, member_name: str) -> Path | None:
    """Where a tarball member extracts to, KEEPING its archive-relative path.

    One tarball ships the same plugin file name once per platform-arch:

        package/prebuilds/darwin-arm64/librunanywhere_sherpa.dylib
        package/prebuilds/darwin-x64/librunanywhere_sherpa.dylib

    Extracting both to the basename made the second overwrite the first while
    BOTH queued targets pointed at the survivor. The first member's bytes were
    then never read, so a stub in any target but the last one passed this gate
    unexamined — the exact defect the gate exists to stop. Preserve the path so
    every member is its own file.

    Returns None when the member path escapes `root` (absolute, or `..`), which
    is a malformed/hostile archive trying to make this gate write outside its
    temporary directory.
    """
    resolved_root = root.resolve()
    out = (root / member_name).resolve()
    return out if resolved_root in out.parents else None


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
    unsafe_members: list[str] = []
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
                        out = member_dest(dest, member.name)
                        if out is None:
                            print(f"  FAIL  {archive.name}  member escapes the "
                                  f"archive root: {member.name}")
                            unsafe_members.append(
                                f"{archive.name}: member {member.name!r} escapes "
                                f"the archive root"
                            )
                            continue
                        out.parent.mkdir(parents=True, exist_ok=True)
                        out.write_bytes(payload)
                        targets.append((out, f"{archive.name}:{member.name}"))
                        plugin_count += 1
                    elif args.expect_version and COMMONS_NAME_RE.match(leaf):
                        if args.expect_version.encode("ascii") not in payload:
                            version_mismatches.append(
                                f"{archive.name}: {member.name} does not embed "
                                f"{args.expect_version!r}"
                            )
                        else:
                            print(f"  ok    version  {member.name}  "
                                  f"embeds {args.expect_version}")
            required_id = tarball_backend_id(archive.name)
            if required_id is not None and plugin_count == 0:
                print(f"  FAIL  {archive.name}  no runanywhere_{required_id} native in tarball")
                empty_backends.append(
                    f"{archive.name}: backend package '{required_id}' ships no plugin native"
                )

        for target, display in targets:
            finding = check_plugin(target, display)
            if finding is None:
                continue
            checked += 1
            label = f"{finding.backend:<9} {finding.display}"
            if finding.failed:
                print(f"  FAIL  {label}  [{finding.method}]  {finding.reason}")
                findings.append(finding)
            else:
                print(f"  ok    {label}  [{finding.method}]  satisfies its "
                      f"routability contract: {', '.join(REQUIRED_OPS[finding.backend])}")

    failed = bool(findings or empty_backends or version_mismatches or unsafe_members)
    if not failed and checked == 0:
        print("  no backend plugin natives found (nothing to verify)")
        return 0

    if failed:
        print("\nERROR: these plugins must not be published:")
        for finding in findings:
            print(f"  - {finding.display}")
            print(f"      backend '{finding.backend}' {finding.reason}")
        for line in empty_backends:
            print(f"  - {line}")
        for line in version_mismatches:
            print(f"  - {line}")
        for line in unsafe_members:
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
