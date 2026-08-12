#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate shared TypeScript bindings via ts-proto for React Native and Web.
#
# Requirements: pinned ts-proto version sourced from
#   core/VERSIONS::TS_PROTO_VERSION
# Install via: scripts/setup/setup-toolchain.sh (or `npm install -g ts-proto@${TS_PROTO_VERSION}`).
#
# Output:
#   bindings/proto-ts/src/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
TS_OUT_DIR="${REPO_ROOT}/bindings/proto-ts/src"

# Load TS_PROTO_VERSION from the centralized VERSIONS file so the install hint
# below matches what setup-toolchain.sh actually installs.
VERSIONS_FILE="${REPO_ROOT}/core/VERSIONS"
if [ -f "${VERSIONS_FILE}" ]; then
    set -a
    eval "$(grep -E '^[A-Z_][A-Z0-9_]*=' "${VERSIONS_FILE}")"
    set +a
fi
TS_PROTO_VERSION="${TS_PROTO_VERSION:-1.181.1}"

mkdir -p "${TS_OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup/setup-toolchain.sh." >&2
    exit 127
fi

# Resolve the ts-proto plugin. `npm install -g ts-proto` leaves it in two
# places — an executable shim on PATH at <prefix>/bin/protoc-gen-ts_proto, and
# the package itself under `npm root -g` — and those two can name different
# prefixes on the same machine. A host with more than one Node (a CI tool-cache
# Node from actions/setup-node plus a Homebrew one, nvm, asdf) resolves `npm`
# to whichever is first on PATH *at that moment*, so the prefix that received
# `npm install -g` is not necessarily the prefix `npm root -g` reports here.
# Try every legitimate location instead of betting on one.
#
# So resolve the PACKAGE DIRECTORY, which is unambiguous, rather than a shim.
ts_proto_pkg_dirs() {
    npm_root="$(npm root -g 2>/dev/null || true)"
    [ -n "${npm_root}" ] && printf '%s\n' "${npm_root}/ts-proto"
    # npm root -g answers <prefix>/lib/node_modules on POSIX and
    # <prefix>/node_modules on Windows; list both anyway for a broken npm.
    npm_prefix="$(npm prefix -g 2>/dev/null || true)"
    if [ -n "${npm_prefix}" ]; then
        printf '%s\n' "${npm_prefix}/lib/node_modules/ts-proto"
        printf '%s\n' "${npm_prefix}/node_modules/ts-proto"
    fi
    # A repo-local install is a first-class answer too: `npm install` in
    # bindings/proto-ts, or a hoisted root install, both put it here.
    printf '%s\n' "${REPO_ROOT}/bindings/proto-ts/node_modules/ts-proto"
    printf '%s\n' "${REPO_ROOT}/node_modules/ts-proto"
}

TS_PROTO_PKG=""
while IFS= read -r candidate_dir; do
    [ -n "${candidate_dir}" ] || continue
    if [ -f "${candidate_dir}/protoc-gen-ts_proto" ]; then
        TS_PROTO_PKG="${candidate_dir}"
        break
    fi
done <<< "$(ts_proto_pkg_dirs)"

if [ -z "${TS_PROTO_PKG}" ]; then
    echo "error: the ts-proto package is not installed anywhere this script looks." >&2
    echo "       Tried, in order:" >&2
    ts_proto_pkg_dirs | sed 's/^/         /' >&2
    echo "       Install via: npm install -g ts-proto@${TS_PROTO_VERSION}" >&2
    echo "       If you just ran that and still see this, the npm that installed it and" >&2
    echo "       the npm on PATH here have different global prefixes." >&2
    exit 127
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        # Windows cannot execute the package's `protoc-gen-ts_proto`: it is an
        # extensionless `#!/usr/bin/env node` script, and protoc spawns plugins
        # through CreateProcess, which fails with "%1 is not a valid Win32
        # application". npm's own .cmd shim would do, but where npm puts it
        # depends on the prefix layout and on which Node is first on PATH — the
        # thing that already went wrong once here. Write our own instead: two
        # lines, no discovery, correct by construction.
        #
        # Into a per-run temp dir, NOT into the package: a global npm prefix can
        # be read-only (C:\Program Files\nodejs\...) or a restored CI cache, and
        # a failed redirect there would abort codegen with a bare shell error.
        # Mutating an installed dependency tree that other tools checksum is its
        # own problem.
        RAC_TS_SHIM_DIR="$(mktemp -d)"
        trap 'rm -rf "${RAC_TS_SHIM_DIR}"' EXIT
        TS_PROTO_PLUGIN="${RAC_TS_SHIM_DIR}/protoc-gen-ts_proto.cmd"
        entry="${TS_PROTO_PKG}/protoc-gen-ts_proto"
        shim_out="${TS_PROTO_PLUGIN}"
        if command -v cygpath >/dev/null 2>&1; then
            entry="$(cygpath -w "${entry}")"
            # protoc is a native binary, so the --plugin path it receives must
            # be native too.
            TS_PROTO_PLUGIN="$(cygpath -w "${TS_PROTO_PLUGIN}")"
        fi
        printf '@echo off\r\nnode "%s" %%*\r\n' "${entry}" > "${shim_out}"
        ;;
    *)
        TS_PROTO_PLUGIN="${TS_PROTO_PKG}/protoc-gen-ts_proto"
        if [ ! -x "${TS_PROTO_PLUGIN}" ]; then
            # Present but not +x (a tarball unpacked without exec bits): fall
            # back to whatever `npm install -g` put on PATH.
            on_path="$(command -v protoc-gen-ts_proto 2>/dev/null || true)"
            if [ -n "${on_path}" ] && [ -x "${on_path}" ]; then
                TS_PROTO_PLUGIN="${on_path}"
            else
                echo "error: ${TS_PROTO_PLUGIN} exists but is not executable, and no" >&2
                echo "       protoc-gen-ts_proto is on PATH." >&2
                exit 127
            fi
        fi
        ;;
esac
echo "  ts-proto plugin: ${TS_PROTO_PLUGIN}" >&2

# Canonical proto-file list from generate_all.sh, with fallback to
# filesystem discovery when invoked standalone.
# component_types.proto is included explicitly. ts-proto
# does transitively emit component_types.ts via dependent imports, but the
# positive list is made explicit here so behaviour stays aligned with Kotlin
# (which requires the explicit entry — Wire does not transitively emit
# enum-only dependencies).
# router.proto is now included (empty exclusion list) so RN + Web
# have future-proof parity with Kotlin / C++; no active TS consumer today,
# but generated router.ts exists for symmetry.
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | LC_ALL=C sort)"
fi

# sdk_defaults.proto is the central default pool: it carries rac_default
# annotations and nothing sends its messages over a wire, so no message types
# are emitted for it. idl/codegen/generate_defaults_pool.py turns it into plain
# per-language constants instead. Mirrors DECLARATION_ONLY_FILES in
# idl/codegen/_convenience_common.py.
RAC_PROTO_EXCLUDES_TS=(sdk_defaults.proto)

TS_PROTO_BASENAMES=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    if [ "${#RAC_PROTO_EXCLUDES_TS[@]}" -gt 0 ]; then
        for excluded in "${RAC_PROTO_EXCLUDES_TS[@]}"; do
            if [ "${proto_base}" = "${excluded}" ]; then
                skip=1
                break
            fi
        done
    fi
    [ "${skip}" -eq 1 ] && continue
    TS_PROTO_BASENAMES+=("${proto_base}")
done <<< "${RAC_PROTO_FILES}"

# Shared target: env=browser keeps bytes as Uint8Array, which works in Web and
# React Native without coupling generated code to global Buffer.
protoc \
    --plugin=protoc-gen-ts_proto="${TS_PROTO_PLUGIN}" \
    --proto_path="${PROTO_DIR}" \
    --ts_proto_out="${TS_OUT_DIR}" \
    --ts_proto_opt=esModuleInterop=true,outputServices=false,env=browser,useOptionals=messages \
    "${TS_PROTO_BASENAMES[@]}"

echo "✓ TS proto codegen → ${TS_OUT_DIR}"
