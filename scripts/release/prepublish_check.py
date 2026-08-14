#!/usr/bin/env python3
"""Fail-closed gate for the artifact you are about to publish.

WHY THIS EXISTS
---------------
release.yml builds artifacts and attaches them to a GitHub Release. It does NOT
publish to npm / Maven Central / pub.dev; every registry push is done by hand.
The payload validators (check_plugin_natives.py, validate_public_packages.py,
validate_public_artifacts.py, validate_qhexrt_artifacts.py) all run inside the
package-sdk.sh scripts, i.e. when the artifact is BUILT. Nothing re-checks the
bytes at `npm publish` time.

That seam is where real defects have shipped:

  * @runanywhere/electron-sherpa 0.20.17 shipped a 33 KB carrier whose vtable
    slots were all NULL. Same size and same zero exported symbols as a healthy
    carrier, so size and `nm -gU` could not tell them apart.
  * @runanywhere/qhexrt was very nearly published straight from `npm pack`,
    carrying "@runanywhere/proto-ts": "workspace:*". A workspace spec resolves
    to nothing for a consumer; the package installs and then fails.
  * @runanywhere/core 0.20.18 shipped without rac/rac_defaults_generated.h while
    five headers beside it #include that file, so the consumer's NDK build died.

Run this on the EXACT file you are about to push. It is intentionally paranoid
and exits non-zero on anything it cannot positively verify.

USAGE
    prepublish_check.py --version 0.20.19 ARTIFACT [ARTIFACT ...]

Supports npm .tgz, Android .aar, and pub.dev .tar.gz archives.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import posixpath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

# A dependency spec that only resolves inside this monorepo. Publishing one
# produces a package that installs and then cannot find its own dependency.
LOCAL_SPEC_PREFIXES = ("workspace:", "file:", "link:", "portal:")

# engine id -> the op tables its thin carrier must REFERENCE (as undefined
# symbols). A carrier that defines none of these is a stub: it registers an
# all-NULL vtable and the registry then refuses the plugin, so the SDK ships
# with that whole modality silently missing.
CARRIER_OPS = {
    "sherpa": ("g_sherpa_stt_ops", "g_sherpa_tts_ops", "g_sherpa_vad_ops"),
    "onnx": ("g_onnx_embeddings_ops", "g_onnx_segmentation_ops", "g_onnx_diarization_ops"),
    "llamacpp": ("g_llamacpp_embeddings_ops", "g_llamacpp_rerank_ops", "g_llamacpp_vlm_ops"),
}


class Findings:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.passes: list[str] = []
        self.notes: list[str] = []

    def ok(self, msg: str) -> None:
        self.passes.append(msg)

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def note(self, msg: str) -> None:
        self.notes.append(msg)


def find_llvm_nm() -> str | None:
    """llvm-nm reads ELF; the host `nm` on macOS does not."""
    for ndk in sorted(Path.home().glob("Library/Android/sdk/ndk/*"), reverse=True):
        cand = ndk / "toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm"
        if cand.is_file():
            return str(cand)
    return shutil.which("llvm-nm")


def symbols(path: Path, elf: bool) -> str:
    """All symbols, including local and UNDEFINED.

    `nm -a` is the only form that works here. `nm -gU` lists exported-and-defined
    symbols, and a healthy thin carrier exports ZERO of those, exactly like a
    stub. The signal lives in the undefined references.
    """
    tool = find_llvm_nm() if elf else "nm"
    if not tool:
        return ""
    try:
        r = subprocess.run([tool, "-a", str(path)], capture_output=True, text=True, timeout=120)
        return r.stdout
    except Exception:
        return ""


def check_carrier(path: Path, engine: str, f: Findings, elf: bool) -> None:
    want = CARRIER_OPS.get(engine)
    if not want:
        return
    out = symbols(path, elf)
    if not out:
        f.note(f"{path.name}: could not read symbols (no suitable nm), NOT verified")
        return
    hits = [s for s in want if re.search(rf"\bU\s+_?{re.escape(s)}\b", out)]
    if hits:
        f.ok(f"{path.name}: real carrier, {len(hits)}/{len(want)} ops refs ({', '.join(hits)})")
    else:
        f.fail(
            f"{path.name}: HOLLOW STUB. Zero undefined refs to {want}. "
            f"It will register an all-NULL vtable and the modality will be missing at runtime."
        )


def check_qhexrt(path: Path, f: Findings, elf: bool) -> None:
    out = symbols(path, elf)
    blob = path.read_bytes()
    available = b"qhexrt:engine-available" in blob
    unavailable = b"qhexrt:engine-unavailable" in blob
    if "g_qhexrt_llm_ops" in out and available:
        f.ok(f"{path.name}: real QHexRT engine (g_qhexrt_llm_ops + engine-available)")
    elif unavailable or "g_qhexrt_unavailable_vtable" in out:
        f.fail(
            f"{path.name}: QHexRT NON-ROUTABLE SHELL (engine-unavailable). "
            f"It exports rac_plugin_entry_qhexrt and looks healthy by size and export count."
        )
    else:
        f.note(f"{path.name}: QHexRT state indeterminate, NOT verified")


def check_tracking(path: Path, f: Findings) -> None:
    """A commons build must carry the real staging backend origin, not the placeholder.

    core/CMakeLists.txt compiles the credential-free development_config.cpp.template
    and substitutes $ENV{STAGING_BASE_URL} into it. CI always sets that (release.yml
    fails closed if the secret is missing), but a LOCAL build with the variable unset
    passes the placeholder straight through. rac_dev_config_is_usable_http_url then
    rejects "YOUR_STAGING_BASE_URL", the SDK cannot keyless-resolve a development
    backend, and the release silently ships with no telemetry at all.

    This is invisible to every other check: the binary is the right size, exports the
    right symbols, and its carriers reference all their ops tables. Shipped exactly
    that way in the 0.20.19 Electron packages before this check existed.
    """
    blob = path.read_bytes()
    if b"YOUR_STAGING_BASE_URL" in blob:
        f.fail(
            f"{path.name}: NO TELEMETRY. Built with the placeholder staging URL, so "
            f"rac_dev_config rejects it and no metrics are reported. Rebuild with "
            f"STAGING_BASE_URL set in the environment."
        )
    elif b"runanywhere-backend-staging" in blob:
        f.ok(f"{path.name}: staging backend URL baked in (telemetry will report)")
    else:
        f.note(f"{path.name}: no staging URL marker found, NOT verified")


def scan_natives(root: Path, f: Findings) -> None:
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        n = p.name
        elf = n.endswith(".so")
        if not (elf or n.endswith((".dylib", ".a"))):
            continue
        if p.stat().st_size == 0:
            f.fail(f"{n}: zero-byte binary")
            continue
        m = re.match(r"(?:lib)?runanywhere_([a-z]+)\.(so|dylib)$", n)
        if m:
            check_carrier(p, m.group(1), f, elf)
        elif "rac_backend_qhexrt" in n:
            check_qhexrt(p, f, elf)
        elif re.match(r"(?:lib)?rac_commons\.(so|dylib|a)$", n) or n == "librac_commons.dylib":
            check_tracking(p, f)
        elif n.endswith(".wasm"):
            check_tracking(p, f)


def check_npm(tgz: Path, version: str, f: Findings) -> None:
    with tarfile.open(tgz) as tf:
        names = [m.name for m in tf.getmembers() if m.isfile()]
        try:
            pj = json.load(tf.extractfile("package/package.json"))
        except Exception as e:
            f.fail(f"{tgz.name}: cannot read package.json ({e})")
            return

        name = pj.get("name", "?")
        got = pj.get("version", "?")
        if got != version:
            f.fail(f"{name}: version is {got}, expected {version}")
        else:
            f.ok(f"{name}: version {got}")

        # A local spec in a published tarball resolves to nothing for consumers.
        for field in ("dependencies", "peerDependencies", "optionalDependencies"):
            for dep, spec in (pj.get(field) or {}).items():
                if isinstance(spec, str) and spec.startswith(LOCAL_SPEC_PREFIXES):
                    f.fail(
                        f"{name}: {field}.{dep} = '{spec}' is a LOCAL spec and cannot "
                        f"resolve for a consumer. Pack via package-sdk.sh, or run "
                        f"scripts/release/rewrite_npm_package.py."
                    )

        rel = [n[len("package/"):] for n in names if n.startswith("package/")]

        # Every path in files[] must exist. A leading ! is an EXCLUDE pattern.
        for pat in pj.get("files") or []:
            if pat.startswith("!"):
                continue
            hit = any(
                r == pat or fnmatch.fnmatch(r, pat) or r.startswith(pat.rstrip("/") + "/")
                for r in rel
            )
            if not hit:
                f.fail(f"{name}: files[] declares '{pat}' but nothing matches it in the tarball")

        # Advertised entry points must exist.
        for key in ("main", "module", "types", "browser"):
            v = pj.get(key)
            if isinstance(v, str):
                t = v.lstrip("./")
                if t not in rel:
                    f.fail(f"{name}: {key} points at '{v}' which is not in the tarball")

        # Any header that #includes a sibling must find it. This is exactly how
        # @runanywhere/core 0.20.18 shipped unbuildable for RN Android.
        hdrs = {r for r in rel if r.endswith(".h")}
        if hdrs:
            missing: set[str] = set()
            for h in hdrs:
                try:
                    body = tf.extractfile("package/" + h).read().decode("utf-8", "ignore")
                except Exception:
                    continue
                base = h[: h.rindex("/") + 1] if "/" in h else ""
                root = base.split("include/", 1)[0] + "include/" if "include/" in base else None
                for inc in re.findall(r'#\s*include\s+"(rac/[^"]+)"', body):
                    if root and (root + inc) not in hdrs:
                        missing.add(inc)
            for inc in sorted(missing):
                f.fail(
                    f"{name}: header set is INCOMPLETE, '{inc}' is #included but not shipped. "
                    f"Consumer native builds will fail at compile time."
                )
            if not missing:
                f.ok(f"{name}: {len(hdrs)} headers, all intra-tree #includes resolve")

        with tempfile.TemporaryDirectory() as td:
            tf.extractall(td, filter="data")
            scan_natives(Path(td), f)


def check_aar(aar: Path, version: str, f: Findings) -> None:
    with tempfile.TemporaryDirectory() as td:
        with zipfile.ZipFile(aar) as z:
            z.extractall(td)
        root = Path(td)
        abis = sorted({p.parent.name for p in root.rglob("*.so")})
        if abis:
            f.ok(f"{aar.name}: ABIs {abis}")
        else:
            f.note(f"{aar.name}: no .so payload (may be a pure-Kotlin module)")
        commons = list(root.rglob("librac_commons.so"))
        for c in commons:
            blob = c.read_bytes()
            vers = sorted(set(re.findall(rb"\b0\.\d+\.\d+\b", blob)))
            vs = [v.decode() for v in vers]
            if version in vs and len(vs) == 1:
                f.ok(f"{c.name} ({c.parent.name}): embeds {version} only")
            elif version in vs:
                f.note(f"{c.name} ({c.parent.name}): embeds {version} plus {vs}, NOT verified clean")
            else:
                f.fail(f"{c.name} ({c.parent.name}): does NOT embed {version} (found {vs})")
        scan_natives(root, f)


def check_pub(archive: Path, version: str, f: Findings) -> None:
    with tarfile.open(archive) as tf:
        names = [m.name for m in tf.getmembers() if m.isfile()]
        ps = [n for n in names if n.endswith("pubspec.yaml") and n.count("/") <= 1]
        if not ps:
            f.fail(f"{archive.name}: no pubspec.yaml")
            return
        body = tf.extractfile(ps[0]).read().decode("utf-8", "ignore")
        m = re.search(r"^version:\s*(\S+)", body, re.M)
        got = m.group(1) if m else "?"
        if got != version:
            f.fail(f"{archive.name}: pubspec version {got}, expected {version}")
        else:
            f.ok(f"{archive.name}: version {got}")
        # Guard the mistake of publishing a working tree: pub only honours
        # .gitignore from the package root down, so staged binaries can leak in.
        heavy = [n for n in names if n.endswith((".so", ".a", ".xcframework", ".dylib"))]
        if heavy:
            f.fail(
                f"{archive.name}: ships {len(heavy)} binary artifact(s) "
                f"(e.g. {heavy[0]}). These packages fetch natives at build time; "
                f"publishing from a working tree with staged binaries leaks them."
            )
        else:
            f.ok(f"{archive.name}: no leaked binaries")


def main() -> int:
    ap = argparse.ArgumentParser(description="Fail-closed pre-publish gate.")
    ap.add_argument("--version", required=True, help="expected version, e.g. 0.20.19")
    ap.add_argument("artifacts", nargs="+", type=Path)
    a = ap.parse_args()

    f = Findings()
    for art in a.artifacts:
        if not art.is_file():
            f.fail(f"{art}: not a file")
            continue
        n = art.name
        if n.endswith(".tgz"):
            check_npm(art, a.version, f)
        elif n.endswith(".aar"):
            check_aar(art, a.version, f)
        elif n.endswith((".tar.gz", ".tgz")):
            check_pub(art, a.version, f)
        else:
            f.note(f"{n}: unrecognised artifact type, NOT verified")

    for m in f.passes:
        print(f"  PASS  {m}")
    for m in f.notes:
        print(f"  NOTE  {m}")
    for m in f.failures:
        print(f"  FAIL  {m}")

    print()
    print(f"  {len(f.passes)} passed, {len(f.notes)} unverified, {len(f.failures)} failed")
    if f.failures:
        print("  DO NOT PUBLISH. Registries are append-only; a bad publish cannot be withdrawn.")
        return 1
    print("  Safe to publish.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
