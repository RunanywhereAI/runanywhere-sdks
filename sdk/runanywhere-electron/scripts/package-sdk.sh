#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-electron/scripts/package-sdk.sh
# =============================================================================
# Public Electron SDK packaging contract, mirroring
# sdk/runanywhere-web/scripts/package-sdk.sh.
#
# Why this exists: the workspace manifest declares
#   "@runanywhere/proto-ts": "file:../shared/proto-ts"
# as a RUNTIME dependency, which is correct for local development (the SDK sets
# `install-links=true` so the dep is copied rather than symlinked) but resolves
# to nothing on a consumer machine. `npm publish` straight from the workspace
# would ship that dead path. rewrite_npm_package.py rewrites `file:` and
# `workspace:` specs inside the packed tarball, so the published manifest
# carries an exact registry version while the workspace stays dev-friendly.
#
# OUTPUTS: dist/sdk-electron/*.tgz -- publish-ready, in dependency order.
# =============================================================================

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ELECTRON_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ELECTRON_ROOT}/../.." && pwd)"
DIST_DIR="${ELECTRON_ROOT}/dist/sdk-electron"

cd "${ELECTRON_ROOT}"

PACKAGE_VERSION="$(node -p "require('./package.json').version")"
[ -n "${PACKAGE_VERSION}" ] || { echo "ERROR: Electron package version is empty" >&2; exit 1; }

echo ">> Electron SDK packaging (version=${PACKAGE_VERSION})"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# proto-ts is packed first so it can be vendored into the entry tarball, the
# same way the Web SDK does it: installing @runanywhere/electron then never
# asks npm for a proto-ts version that may not be published yet.
echo ">> npm pack ../shared/proto-ts"
(cd "${REPO_ROOT}/sdk/shared/proto-ts" && npm pack --silent --pack-destination "${DIST_DIR}" >/dev/null)
PROTO_ARCHIVE="${DIST_DIR}/runanywhere-proto-ts-${PACKAGE_VERSION}.tgz"
[ -f "${PROTO_ARCHIVE}" ] || { echo "ERROR: npm pack did not produce ${PROTO_ARCHIVE}" >&2; exit 1; }
python3 "${REPO_ROOT}/scripts/release/rewrite_npm_package.py" \
    --archive "${PROTO_ARCHIVE}" \
    --exact-version "${PACKAGE_VERSION}"

echo ">> npm pack @runanywhere/electron"
npm pack --silent --pack-destination "${DIST_DIR}" >/dev/null
ENTRY_ARCHIVE="${DIST_DIR}/runanywhere-electron-${PACKAGE_VERSION}.tgz"
[ -f "${ENTRY_ARCHIVE}" ] || { echo "ERROR: npm pack did not produce ${ENTRY_ARCHIVE}" >&2; exit 1; }
python3 "${REPO_ROOT}/scripts/release/rewrite_npm_package.py" \
    --archive "${ENTRY_ARCHIVE}" \
    --exact-version "${PACKAGE_VERSION}" \
    --bundle "@runanywhere/proto-ts=${PROTO_ARCHIVE}"

# native/ is intentionally absent: it is a private build-only CMake target with
# no runtime dependents. Its output is bundled into the entry package's
# prebuilds/ by the prepack hook.
for pkg in llamacpp onnx qhexrt sherpa; do
    pkg_dir="${ELECTRON_ROOT}/packages/${pkg}"
    [ -d "${pkg_dir}" ] || { echo "ERROR: missing package dir ${pkg_dir}" >&2; exit 1; }
    echo ">> npm pack packages/${pkg}"
    (cd "${pkg_dir}" && npm pack --silent --pack-destination "${DIST_DIR}" >/dev/null)
    artifact="${DIST_DIR}/runanywhere-electron-${pkg}-${PACKAGE_VERSION}.tgz"
    [ -f "${artifact}" ] || { echo "ERROR: npm pack did not produce ${artifact}" >&2; exit 1; }
    python3 "${REPO_ROOT}/scripts/release/rewrite_npm_package.py" \
        --archive "${artifact}" \
        --exact-version "${PACKAGE_VERSION}"
done

# Fail closed: a `file:` or `workspace:` spec surviving into a published
# manifest is the exact defect this script exists to prevent.
echo ">> Auditing packed manifests"
python3 - "${DIST_DIR}" "${PACKAGE_VERSION}" <<'PY'
import json, sys, tarfile
from pathlib import Path

dist, version = Path(sys.argv[1]), sys.argv[2]
failures = []
archives = sorted(dist.glob("*.tgz"))
if not archives:
    sys.exit("ERROR: no tarballs produced")

for archive in archives:
    with tarfile.open(archive, "r:gz") as bundle:
        member = bundle.extractfile("package/package.json")
        if member is None:
            failures.append(f"{archive.name}: no package/package.json")
            continue
        manifest = json.load(member)
    if manifest.get("version") != version:
        failures.append(f"{archive.name}: version {manifest.get('version')!r} != {version!r}")
    if manifest.get("private"):
        failures.append(f"{archive.name}: still marked private")
    for field in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        for name, spec in (manifest.get(field) or {}).items():
            if isinstance(spec, str) and spec.startswith(("file:", "workspace:")):
                failures.append(f"{archive.name}: {field}.{name} = {spec!r} is monorepo-local")
    license_field = manifest.get("license", "")
    if ".." in license_field:
        failures.append(f"{archive.name}: license {license_field!r} escapes the package")
    print(f"  ok  {archive.name}  ({manifest['name']}@{manifest['version']})")

if failures:
    print("\nERROR: packaged manifests are not publishable:")
    for line in failures:
        print(f"  - {line}")
    sys.exit(1)
print("\nAll Electron tarballs are publishable.")
PY

echo ""
echo ">> Artifacts in ${DIST_DIR}:"
ls -1 "${DIST_DIR}"
echo ""
echo ">> Publish in this order:"
echo "     runanywhere-proto-ts-${PACKAGE_VERSION}.tgz"
echo "     runanywhere-electron-${PACKAGE_VERSION}.tgz"
echo "     runanywhere-electron-{llamacpp,onnx,qhexrt,sherpa}-${PACKAGE_VERSION}.tgz"
