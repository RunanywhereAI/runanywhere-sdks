#!/usr/bin/env python3
"""Assert a packaged C++ desktop kit or private overlay tarball.

Public kits:
  - every checked-in generated *.pb.h is in include/runanywhere/proto/
  - share/runanywhere/SCHEMA_LOCK is present
  - on Windows, zlibstatic.lib / bz2_bundled.lib / onnxruntime.lib + DLL
  - --forbid-private-engines: no neurt/qhexrt paths

Private overlays (--require-overlay neurt|qhexrt):
  - ENGINE + RECEIPT.json + backend archive + prebuilt core
"""
from __future__ import annotations

import argparse
import sys
import tarfile
from pathlib import Path


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
