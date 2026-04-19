#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/verify-versions.sh
#
# Reads the top-level VERSIONS file and cross-checks every per-artifact
# manifest (Package.swift, build.gradle.kts, pubspec.yaml, package.json,
# vcpkg.json) agrees with its recorded version.
#
# Fails with a descriptive diff when an artifact drifts — the release
# pipeline refuses to proceed if versions don't agree.
#
# Usage:
#   scripts/verify-versions.sh            — verify all
#   scripts/verify-versions.sh --tag vX   — also assert VERSIONS matches tag

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS="${ROOT}/VERSIONS"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 required" >&2
    exit 2
fi

if [ ! -f "${VERSIONS}" ]; then
    echo "ERROR: ${VERSIONS} not found" >&2
    exit 2
fi

violations=$(python3 - "${ROOT}" "$@" <<'PY'
import json, os, re, sys, pathlib

root = pathlib.Path(sys.argv[1])
args = sys.argv[2:]
tag_arg = None
if len(args) >= 2 and args[0] == "--tag":
    tag_arg = args[1]

with open(root / "VERSIONS") as f:
    v = json.load(f)

commons = v["commons"]
swift   = v["runanywhere-swift"]
kotlin  = v["runanywhere-kotlin"]
flutter = v["runanywhere-flutter"]
rn      = v["runanywhere-rn"]
web     = v["runanywhere-web"]

def check(label: str, path: pathlib.Path, pattern: str, expect: str):
    if not path.exists():
        print(f"SKIP  {label} — {path} not present")
        return None
    content = path.read_text()
    m = re.search(pattern, content)
    if not m:
        return f"{label}: pattern not found in {path}"
    got = m.group(1)
    if got != expect:
        return f"{label}: {path} has {got!r}, VERSIONS says {expect!r}"
    print(f"OK    {label}  {got}")
    return None

violations = []
def add(v):
    if v is not None:
        violations.append(v)

# vcpkg.json — canonical version for the C++ core.
add(check("commons (vcpkg.json)",
          root / "vcpkg.json",
          r'"version"\s*:\s*"([^"]+)"',
          commons))

# frontends/swift — the adapter package. Its version lives inside the
# Package.swift comments (placeholder) — the real SwiftPM version comes
# from the git tag. So we only assert that `frontends/swift/Package.swift`
# exists; tag alignment is handled by release.yml.
sp = root / "frontends/swift/Package.swift"
if sp.exists():
    print(f"OK    runanywhere-swift  (Package.swift present; tag-pinned at release)")

# frontends/kotlin — gradle project with `v2Version` property.
kp = root / "frontends/kotlin/build.gradle.kts"
if kp.exists():
    add(check("runanywhere-kotlin (build.gradle.kts)", kp,
              r'version\s*=\s*project\.findProperty\([^\)]*\)\s*as\?\s*String\s*\?:\s*"([^"]+)"',
              kotlin))

# frontends/dart — pubspec.yaml.
add(check("runanywhere-flutter (pubspec.yaml)",
          root / "frontends/dart/pubspec.yaml",
          r'(?m)^version:\s*([^\s]+)',
          flutter))

# frontends/ts — package.json.
add(check("runanywhere-rn (package.json)",
          root / "frontends/ts/package.json",
          r'"version"\s*:\s*"([^"]+)"',
          rn))

# frontends/web — package.json.
add(check("runanywhere-web (package.json)",
          root / "frontends/web/package.json",
          r'"version"\s*:\s*"([^"]+)"',
          web))

# Optional: --tag cross-check.
if tag_arg is not None:
    expected_tag = f"v{commons}"
    if tag_arg != expected_tag:
        add(f"tag mismatch: got {tag_arg}, VERSIONS.commons={commons} → expected {expected_tag}")

for v in violations:
    print(f"FAIL  {v}")

sys.exit(1 if violations else 0)
PY
)
rc=$?
echo "${violations}"
exit "${rc}"
