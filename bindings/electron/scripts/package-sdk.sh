#!/usr/bin/env bash
# =============================================================================
# bindings/electron/scripts/package-sdk.sh
# =============================================================================
# Public Electron SDK packaging contract, mirroring
# bindings/web/scripts/package-sdk.sh.
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
(cd "${REPO_ROOT}/bindings/shared/proto-ts" && npm pack --silent --pack-destination "${DIST_DIR}" >/dev/null)
PROTO_ARCHIVE="${DIST_DIR}/runanywhere-proto-ts-${PACKAGE_VERSION}.tgz"
[ -f "${PROTO_ARCHIVE}" ] || { echo "ERROR: npm pack did not produce ${PROTO_ARCHIVE}" >&2; exit 1; }
python3 "${REPO_ROOT}/scripts/release/rewrite_npm_package.py" \
    --archive "${PROTO_ARCHIVE}" \
    --exact-version "${PACKAGE_VERSION}"

# Build the entry package BEFORE the backends. Each backend imports types from
# `@runanywhere/electron/backend`, which resolves through the workspace link to
# the entry package's dist/ -- so building a backend first fails with TS2307.
echo ">> build @runanywhere/electron"
npm run build --silent

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
    # Build, don't assume. These packages have no `prepack` hook, so `npm pack`
    # ships whatever dist/ happens to be on disk -- which for a package that has
    # never been built locally is nothing at all. @runanywhere/electron-qhexrt
    # 0.20.16 was published that way: a manifest whose main/types point into
    # dist/, and no dist/ in the tarball. The post-pack audit below now makes
    # that unpublishable rather than merely unlikely.
    # Each backend imports types from `@runanywhere/electron/backend`, resolved
    # through a hand-made symlink in its own node_modules -- this package set
    # declares no npm `workspaces`, so nothing recreates it. node_modules is
    # gitignored, so a fresh clone (or a package added later, as qhexrt was in
    # #664) simply has no link and fails with TS2307. Guarantee it here instead
    # of depending on whatever the local tree happens to have.
    link_dir="${pkg_dir}/node_modules/@runanywhere"
    if [ ! -e "${link_dir}/electron" ]; then
        echo ">> linking @runanywhere/electron into packages/${pkg}"
        mkdir -p "${link_dir}"
        ln -sfn ../../../.. "${link_dir}/electron"
    fi

    echo ">> build packages/${pkg}"
    (cd "${pkg_dir}" && npm run build --silent)
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
import fnmatch, json, sys, tarfile
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

    # Every entry point the manifest advertises must actually be in the tarball.
    # npm silently drops `files` entries that do not exist on disk, so a package
    # whose dist/ was never built packs cleanly and then fails at import time in
    # every consumer -- which is exactly how electron-qhexrt 0.20.16 shipped.
    with tarfile.open(archive, "r:gz") as bundle:
        present = {n[len("package/"):] for n in bundle.getnames() if n.startswith("package/")}

    def entry_points(node):
        if isinstance(node, str):
            yield node
        elif isinstance(node, dict):
            for nested in node.values():
                yield from entry_points(nested)

    advertised = set()
    for field in ("main", "module", "types", "typings", "bin"):
        advertised.update(entry_points(manifest.get(field)))
    advertised.update(entry_points(manifest.get("exports")))

    for entry in sorted(advertised):
        rel = entry.lstrip("./")
        if not rel:
            continue
        if "*" in rel:
            # A subpath pattern like "./dist/*.js" is satisfied by any match,
            # not by a file literally named with an asterisk.
            if not fnmatch.filter(present, rel):
                failures.append(f"{archive.name}: pattern {entry!r} matches nothing in the tarball")
        elif rel not in present:
            failures.append(f"{archive.name}: advertises {entry!r} but it is not in the tarball")

    print(f"  ok  {archive.name}  ({manifest['name']}@{manifest['version']}, {len(present)} files)")

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
