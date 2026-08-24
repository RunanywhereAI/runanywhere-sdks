#!/usr/bin/env python3
"""Assert a packaged C++ desktop kit tarball is consumable by RCLI.

Checks:
  - every checked-in generated *.pb.h is in include/runanywhere/proto/
  - share/runanywhere/SCHEMA_LOCK (idl/SCHEMA_LOCK) is present
  - on Windows, zlibstatic.lib and bz2_bundled.lib are in lib/
    (rac_commons PUBLIC-links those archives by name)
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
    args = parser.parse_args()

    tar_path = Path(args.tarball)
    if not tar_path.is_file():
        print(f"error: tarball not found: {tar_path}", file=sys.stderr)
        return 1

    root = Path(args.source_root)
    proto_dir = root / "core" / "src" / "generated" / "proto"
    headers = sorted(p.name for p in proto_dir.glob("*.pb.h"))
    if not headers:
        print(f"error: no generated proto headers in {proto_dir}", file=sys.stderr)
        return 1

    names = tarfile.open(tar_path, "r:gz").getnames()
    missing: list[str] = []

    canon = [n.replace("\\", "/") for n in names]
    for hdr in headers:
        if not any(n.endswith("/" + hdr) for n in canon):
            missing.append(f"include/runanywhere/proto/{hdr}")

    schema_ok = any(n.lower().endswith("share/runanywhere/schema_lock") for n in canon)
    if not schema_ok:
        missing.append("share/runanywhere/SCHEMA_LOCK")

    if args.windows:
        for lib in ("zlibstatic.lib", "bz2_bundled.lib"):
            if not any(n.endswith(lib) for n in names):
                missing.append(f"lib/{lib}")

    if missing:
        print("kit tarball missing:", file=sys.stderr)
        for item in missing:
            print(f"  {item}", file=sys.stderr)
        return 1

    print(f"kit ok: {len(names)} entries, {len(headers)} proto headers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
