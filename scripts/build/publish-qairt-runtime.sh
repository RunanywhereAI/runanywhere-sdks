#!/usr/bin/env bash
# Curate the QAIRT/QNN runtime redistributables from a licensed QAIRT install and
# publish them as public, versioned, SHA-256-pinned release assets.
#
# WHY
# ---
# The QHexRT engine payload is headers-only by design (compile against QAIRT
# headers, dlopen the runtime), so it carries no QNN libraries. But a consumer
# that links the engine MUST ship the runtime, or the plugin registers at
# priority 150 and then fails at model load. Until now the only source was a
# licensed QAIRT install on the build machine, which no hosted runner has -- so
# the Android release lane could not produce a routable engine at all, and the
# Windows lane depended on a hand-copied directory of machine state that has
# already gone stale once.
#
# RunAnywhere is an authorized Qualcomm partner and already distributes these
# exact binaries publicly: @runanywhere/electron-qhexrt on npm ships QnnHtp.dll,
# libQnnHtpV81Skel.so and libqnnhtpv81.cat with no authentication. This does not
# expose anything new -- it makes an existing distribution named, versioned and
# verifiable instead of implicit.
#
# The assets are published under their OWN tag (qairt-runtime-v<qairt-version>),
# not the SDK release tag, because the QAIRT SDK version and the SDK release
# version are independent axes. Asset names deliberately contain no "qhexrt"
# substring so release.yml's private-leak guard (which hard-fails on any
# *qhexrt* file reaching the public asset set) is unaffected.
#
# Usage:
#   publish-qairt-runtime.sh --qnn <QAIRT_ROOT> [--platform arm64-v8a|win-arm64|all]
#                            [--out <dir>] [--upload]
#
# Without --upload it only stages and hashes locally, which is what you want when
# checking what a publish would produce.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${REPO_ROOT}/scripts/build/qairt-runtime-manifest.json"
PUBLISH_REPO="RunanywhereAI/runanywhere-sdks"

QNN_ROOT="${QNN_SDK_ROOT:-}"
PLATFORM="all"
OUT_DIR="${REPO_ROOT}/dist/qairt-runtime"
UPLOAD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --qnn)      QNN_ROOT="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --out)      OUT_DIR="$2"; shift 2 ;;
        --upload)   UPLOAD=1; shift ;;
        -h|--help)  sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "[ERROR] unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$QNN_ROOT" ]] || { echo "[ERROR] --qnn (or QNN_SDK_ROOT) is required" >&2; exit 2; }
QNN_ROOT="$(cd "$QNN_ROOT" && pwd)"
[[ -f "${QNN_ROOT}/sdk.yaml" ]] || {
    echo "[ERROR] ${QNN_ROOT}/sdk.yaml is missing." >&2
    echo "        --qnn must point at a QAIRT SDK root (the dir containing sdk.yaml)." >&2
    exit 2
}

PY_BIN="${PYTHON_BIN:-python3}"
command -v "$PY_BIN" >/dev/null 2>&1 || PY_BIN=python

# The QAIRT version is the install's own directory name; never invent one.
QAIRT_VERSION="$(basename "$QNN_ROOT")"
TAG="qairt-runtime-v${QAIRT_VERSION}"

case "$PLATFORM" in arm64-v8a|win-arm64|all) ;; *)
    echo "[ERROR] --platform must be arm64-v8a, win-arm64 or all" >&2; exit 2 ;;
esac
if [[ "$PLATFORM" == "all" ]]; then PLATFORMS=(arm64-v8a win-arm64); else PLATFORMS=("$PLATFORM"); fi

mkdir -p "$OUT_DIR"
STAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT"' EXIT

echo "==> QAIRT ${QAIRT_VERSION}   (tag: ${TAG})"
"$PY_BIN" -c "
import hashlib,sys
print('    sdk.yaml sha256:', hashlib.sha256(open('${QNN_ROOT}/sdk.yaml','rb').read()).hexdigest())
"
echo

for plat in "${PLATFORMS[@]}"; do
    stage="${STAGE_ROOT}/${plat}"
    mkdir -p "$stage"

    # Curate from the manifest. Missing files are fatal: a silently short payload
    # is exactly the failure this whole pipeline exists to prevent.
    "$PY_BIN" - "$MANIFEST" "$QNN_ROOT" "$stage" "$plat" "$QAIRT_VERSION" <<'PY'
import hashlib, json, os, shutil, sys
manifest_path, qnn_root, stage, plat, version = sys.argv[1:6]
m = json.loads(open(manifest_path, encoding="utf-8").read())
spec = m["platforms"][plat]
flat = spec["layout"] == "flat"

def copy(rel, dest_rel):
    src = os.path.join(qnn_root, rel)
    if not os.path.isfile(src):
        sys.exit(f"[ERROR] required QAIRT file is missing: {src}")
    dest = os.path.join(stage, dest_rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(src, dest)
    return dest

recorded = {}
for rel in spec["files"]:
    dest_rel = os.path.basename(rel) if flat else rel
    dest = copy(rel, dest_rel)
    with open(dest, "rb") as fh:
        recorded[dest_rel] = hashlib.sha256(fh.read()).hexdigest()

# Identity + notices always travel with the binaries. The identity file is what
# lets a consumer prove this runtime is the SDK the engine was built against;
# the notices are required by our own packagers.
ident = m["identity_file"]
copy(ident, ident)
for n in m["notices"]:
    copy(n, n)

# Its OWN schema, deliberately not qhexrt-prebuilt/v2: the engine receipt and the
# runtime receipt must stay two independent artifacts that can be compared, never
# one check that ends up hashing a file against a copy of itself.
with open(os.path.join(qnn_root, ident), "rb") as fh:
    identity_sha = hashlib.sha256(fh.read()).hexdigest()
receipt = {
    "schema": "qairt-runtime/v1",
    "qairt_version": version,
    "platform": plat,
    "layout": spec["layout"],
    "identity_file": ident,
    "identity_sha256": identity_sha,
    "files": recorded,
}
with open(os.path.join(stage, "qairt-runtime.json"), "w", encoding="utf-8") as fh:
    json.dump(receipt, fh, indent=2, sort_keys=True)
    fh.write("\n")
print(f"    {plat}: {len(recorded)} runtime files + identity + {len(m['notices'])} notices")
PY

    # A QAIRT staging dir built for the qhx_* tools carries .exe files that are not
    # part of the runtime. Assert rather than filter, so a surprise is loud.
    if find "$stage" -iname '*.exe' | grep -q .; then
        echo "[ERROR] ${plat} staged an .exe; the runtime set must not include tools" >&2
        exit 1
    fi
    if [[ "$(python3 -c "import json;print(json.load(open('$MANIFEST'))['platforms']['$plat']['layout'])")" == "flat" ]]; then
        # Flat means flat: any nesting breaks the Windows loader at runtime, and it
        # would do so silently at model load rather than here.
        if find "$stage" -mindepth 2 -type f | grep -q .; then
            echo "[ERROR] ${plat} must be FLAT; nested files found" >&2
            find "$stage" -mindepth 2 -type f | sed 's/^/        /' >&2
            exit 1
        fi
    fi

    name="qairt-runtime-${plat}-v${QAIRT_VERSION}"
    # Built in Python, DETERMINISTICALLY: sorted entries, fixed mtime/uid/gid, and
    # gzip mtime=0. `tar -czf` is not reproducible here -- gzip stamps the current
    # time into its header AND the staging dir's own mtimes change every run, so
    # two runs over identical bytes produce different checksums. That bit for real:
    # the hash computed while staging did not match the asset that was uploaded.
    # Reproducible means anyone can rebuild this asset and verify the pin.
    "$PY_BIN" - "$stage" "${OUT_DIR}/${name}.tar.gz" <<'PYTAR'
import gzip, os, sys, tarfile
stage, out = sys.argv[1], sys.argv[2]
entries = []
for root, dirs, files in os.walk(stage):
    dirs.sort()
    for f in sorted(files):
        full = os.path.join(root, f)
        entries.append((os.path.relpath(full, stage).replace(os.sep, "/"), full))
entries.sort()
with open(out, "wb") as raw:
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as tar:
            for name, full in entries:
                info = tar.gettarinfo(full, arcname="./" + name)
                info.mtime = 0
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mode = 0o644
                with open(full, "rb") as fh:
                    tar.addfile(info, fh)
PYTAR
    (cd "$OUT_DIR" && shasum -a 256 "${name}.tar.gz" > "${name}.tar.gz.sha256")
    sha="$(cut -d' ' -f1 < "${OUT_DIR}/${name}.tar.gz.sha256")"
    bytes="$(wc -c < "${OUT_DIR}/${name}.tar.gz" | tr -d ' ')"
    echo "    -> ${name}.tar.gz  ($((bytes / 1048576)) MB)"
    echo "       ${sha}"
done

echo
if [[ "$UPLOAD" -eq 1 ]]; then
    if ! gh release view "$TAG" --repo "$PUBLISH_REPO" >/dev/null 2>&1; then
        gh release create "$TAG" --repo "$PUBLISH_REPO" \
            --title "QAIRT runtime ${QAIRT_VERSION}" \
            --notes "Qualcomm AI Runtime (QAIRT) ${QAIRT_VERSION} redistributables for the QHexRT Hexagon NPU engine, redistributed by RunAnywhere as an authorized Qualcomm partner.

Pinned by SHA-256 in \`core/VERSIONS\` (\`QAIRT_RUNTIME_*\`) and fetched by \`scripts/build/download-qairt-runtime.sh\`. See \`THIRD-PARTY-NOTICES.md\`.

Tagged separately from SDK releases because the QAIRT SDK version and the SDK release version are independent axes."
    fi
    gh release upload "$TAG" --repo "$PUBLISH_REPO" --clobber "${OUT_DIR}"/qairt-runtime-*.tar.gz*
    echo "==> uploaded to ${PUBLISH_REPO} @ ${TAG}"
else
    echo "==> staged in ${OUT_DIR} (pass --upload to publish to ${PUBLISH_REPO} @ ${TAG})"
fi
echo
echo "    Pin these in core/VERSIONS:"
echo "      QAIRT_RUNTIME_VERSION=${QAIRT_VERSION}"
echo "      QAIRT_RUNTIME_RELEASE_TAG=${TAG}"
for plat in "${PLATFORMS[@]}"; do
    n="qairt-runtime-${plat}-v${QAIRT_VERSION}"
    key="$(echo "$plat" | tr 'a-z-' 'A-Z_')"
    echo "      QAIRT_RUNTIME_${key}_SHA256=$(cut -d' ' -f1 < "${OUT_DIR}/${n}.tar.gz.sha256")"
done
