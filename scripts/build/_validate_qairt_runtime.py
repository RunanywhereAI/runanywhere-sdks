#!/usr/bin/env python3
"""Validate an extracted QAIRT runtime payload against its own receipt.

Used for BOTH a freshly downloaded tree and an already-cached one. A cached tree
must be re-checked rather than trusted because its receipt file exists: if a
library were removed or modified while qairt-runtime.json survived, selecting it
would produce an engine that loads its runtime and fails on device, and the
pairing gate would not catch it (that only compares the QAIRT identity hash).

Usage: _validate_qairt_runtime.py <root> <platform> <version>
"""

from __future__ import annotations

import hashlib
import json
import os
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root, plat, version = sys.argv[1:4]

    receipt_path = os.path.join(root, "qairt-runtime.json")
    if not os.path.isfile(receipt_path):
        print(f"[ERROR] no qairt-runtime.json under {root}", file=sys.stderr)
        return 1
    with open(receipt_path, encoding="utf-8") as fh:
        r = json.load(fh)

    if r.get("schema") != "qairt-runtime/v1":
        print(f"[ERROR] unexpected receipt schema: {r.get('schema')}", file=sys.stderr)
        return 1
    for key, want in (("platform", plat), ("qairt_version", version)):
        if r.get(key) != want:
            print(f"[ERROR] receipt {key}={r.get(key)!r}, expected {want!r}", file=sys.stderr)
            return 1

    ident = os.path.join(root, r["identity_file"])
    if not os.path.isfile(ident):
        print(f"[ERROR] missing identity file {r['identity_file']}", file=sys.stderr)
        return 1
    with open(ident, "rb") as fh:
        if hashlib.sha256(fh.read()).hexdigest() != r["identity_sha256"]:
            print("[ERROR] identity file does not match the receipt", file=sys.stderr)
            return 1

    # Hash every recorded file, not merely check it exists: a truncated or edited
    # library is exactly the case a presence check waves through.
    bad = []
    for rel, want_sha in sorted(r["files"].items()):
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            bad.append(f"missing {rel}")
            continue
        with open(path, "rb") as fh:
            if hashlib.sha256(fh.read()).hexdigest() != want_sha:
                bad.append(f"modified {rel}")
    if bad:
        print("[ERROR] payload does not match its receipt:", file=sys.stderr)
        for b in bad:
            print(f"        {b}", file=sys.stderr)
        return 1

    print(f"[OK] receipt validates: {len(r['files'])} runtime files, QAIRT {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
