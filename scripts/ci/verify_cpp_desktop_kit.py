#!/usr/bin/env python3
"""Assert a packaged C++ desktop kit or private overlay tarball.

Public kits:
  - every checked-in generated *.pb.h is in include/runanywhere/proto/
  - share/runanywhere/SCHEMA_LOCK is present
  - on Windows, zlibstatic.lib / bz2_bundled.lib / onnxruntime.lib + DLL
  - --forbid-private-engines: no neurt/qhexrt paths
  - if a sherpa backend archive is present, rac_plugin_entry_sherpa must
    reference g_sherpa_stt_ops (RAC_SHERPA_ROUTABLE=1). Ops symbols in a
    sibling TU are not enough — that is how 0.20.26/0.20.28 kits looked
    complete while capability_check returned BACKEND_UNAVAILABLE.

Private overlays (--require-overlay neurt|qhexrt):
  - ENGINE + RECEIPT.json + backend archive + prebuilt core
"""
from __future__ import annotations

import argparse
import sys
import tarfile
from pathlib import Path


def _ar_members(data: bytes) -> list[tuple[str, bytes]]:
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("not an ar archive")
    off = 8
    longnames = b""
    out: list[tuple[str, bytes]] = []
    while off + 60 <= len(data):
        hdr = data[off : off + 60]
        raw_name = hdr[:16].decode("latin1")
        try:
            size = int(hdr[48:58].strip() or b"0")
        except ValueError:
            break
        off += 60
        body = data[off : off + size]
        off += size + (size % 2)
        name = raw_name.strip()
        if name.startswith("//"):
            longnames = body
            continue
        if name.startswith("#1/"):
            namelen = int(name[3:])
            name = body[:namelen].split(b"\0", 1)[0].decode("latin1")
            body = body[namelen:]
        elif name.startswith("/") and name[1:2].isdigit():
            idx = int(name[1:])
            end = longnames.find(b"\0", idx)
            if end < 0:
                end = longnames.find(b"\n", idx)
            if end < 0:
                end = len(longnames)
            name = longnames[idx:end].decode("latin1").strip().rstrip("/")
        out.append((name, body))
    return out


def sherpa_plugin_entry_is_routable(archive: bytes) -> bool:
    """True when rac_plugin_entry_sherpa.cpp was compiled with RAC_SHERPA_ROUTABLE=1."""
    for name, body in _ar_members(archive):
        n = name.replace("\\", "/").lower()
        if "rac_plugin_entry_sherpa" in n:
            return b"g_sherpa_stt_ops" in body
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tarball")
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--windows", action="store_true")
    parser.add_argument(
        "--allow-missing-onnxruntime",
        action="store_true",
        help="Windows arm64 OSS kit has no ONNX Runtime (llamacpp/onnx are off)",
    )
    parser.add_argument(
        "--forbid-private-engines",
        action="store_true",
        help="Public kits must not contain neurt or qhexrt archives",
    )
    parser.add_argument(
        "--require-overlay",
        choices=("neurt", "qhexrt"),
        help="Private overlay tarball must contain this engine's archives + receipt",
    )
    args = parser.parse_args()

    tar_path = Path(args.tarball)
    if not tar_path.is_file():
        print(f"error: tarball not found: {tar_path}", file=sys.stderr)
        return 1

    names = tarfile.open(tar_path, "r:gz").getnames()
    canon = [n.replace("\\", "/") for n in names]
    missing: list[str] = []

    if args.require_overlay:
        engine = args.require_overlay
        for item in (
            "share/runanywhere/private/ENGINE",
            "share/runanywhere/private/RECEIPT.json",
        ):
            if not any(n.endswith(item) for n in canon):
                missing.append(item)
        if engine == "neurt":
            if not any(n.endswith("librac_backend_neurt.a") for n in canon):
                missing.append("lib/librac_backend_neurt.a")
            if not any(n.endswith("libneurt_core.a") for n in canon):
                missing.append("lib/libneurt_core.a")
        else:
            if not any(
                n.endswith("rac_backend_qhexrt.lib") or n.endswith("librac_backend_qhexrt.a")
                for n in canon
            ):
                missing.append("lib/rac_backend_qhexrt.lib")
            if not any("qhexrt_core" in n for n in canon):
                missing.append("lib/qhexrt_core.lib")
        if missing:
            print("overlay tarball missing:", file=sys.stderr)
            for item in missing:
                print(f"  {item}", file=sys.stderr)
            return 1
        print(f"overlay ok ({engine}): {len(names)} entries")
        return 0

    root = Path(args.source_root)
    proto_dir = root / "core" / "src" / "generated" / "proto"
    headers = sorted(p.name for p in proto_dir.glob("*.pb.h"))
    if not headers:
        print(f"error: no generated proto headers in {proto_dir}", file=sys.stderr)
        return 1

    for hdr in headers:
        if not any(n.endswith("/" + hdr) for n in canon):
            missing.append(f"include/runanywhere/proto/{hdr}")

    if not any(n.lower().endswith("share/runanywhere/schema_lock") for n in canon):
        missing.append("share/runanywhere/SCHEMA_LOCK")

    if args.windows:
        for lib in ("zlibstatic.lib", "bz2_bundled.lib"):
            if not any(n.endswith(lib) for n in names):
                missing.append(f"lib/{lib}")
        if not args.allow_missing_onnxruntime:
            if not any(n.endswith("onnxruntime.lib") for n in names):
                missing.append("lib/onnxruntime.lib")
            if not any(
                n.replace("\\", "/").endswith("third_party/onnxruntime.dll") for n in names
            ):
                missing.append("third_party/onnxruntime.dll")

    sherpa_member = next(
        (
            n
            for n in names
            if n.replace("\\", "/").endswith("librac_backend_sherpa.a")
            or n.replace("\\", "/").endswith("rac_backend_sherpa.lib")
        ),
        None,
    )
    if sherpa_member:
        with tarfile.open(tar_path, "r:gz") as tf:
            extracted = tf.extractfile(sherpa_member)
            if extracted is None:
                missing.append("sherpa backend archive unreadable")
            else:
                archive = extracted.read()
                try:
                    routable = sherpa_plugin_entry_is_routable(archive)
                except ValueError as exc:
                    print(f"error: sherpa archive: {exc}", file=sys.stderr)
                    return 1
                if not routable:
                    print(
                        "sherpa backend is a non-routable stub: "
                        "rac_plugin_entry_sherpa does not reference g_sherpa_stt_ops "
                        "(RAC_SHERPA_ROUTABLE=0). Prefetch Sherpa-ONNX before "
                        "configuring the desktop kit.",
                        file=sys.stderr,
                    )
                    return 1
        if args.windows:
            if not any("sherpa-onnx-c-api.dll" in n.replace("\\", "/") for n in canon):
                missing.append("third_party/sherpa-onnx-c-api.dll")
        elif not any(n.replace("\\", "/").endswith("libsherpa-onnx-c-api.a") for n in canon):
            missing.append("lib/libsherpa-onnx-c-api.a")
        if not any(
            n.replace("\\", "/").endswith("libonnxruntime.a")
            or n.replace("\\", "/").endswith("third_party/libonnxruntime.dylib")
            for n in canon
        ):
            missing.append("lib/libonnxruntime.a (or third_party/libonnxruntime.dylib)")

    private_hits = [n for n in canon if "neurt" in n.lower() or "qhexrt" in n.lower()]
    if args.forbid_private_engines and private_hits:
        print("public kit contains private engine files:", file=sys.stderr)
        for item in private_hits:
            print(f"  {item}", file=sys.stderr)
        return 1

    if missing:
        print("kit tarball missing:", file=sys.stderr)
        for item in missing:
            print(f"  {item}", file=sys.stderr)
        return 1

    print(f"kit ok: {len(names)} entries, {len(headers)} proto headers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
