#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# ensure_generated.sh — the one call every publish path makes
# =============================================================================
# The language bindings are gitignored (idl/codegen/generated_trees.txt), and
# five of those trees ship inside a published artifact. A packaging script that
# packs before generating produces a tarball that installs fine and then fails
# in the consumer's build. This script is the single prerequisite that closes
# that hole, so each packaging script gains one line instead of its own copy of
# the logic:
#
#     "${REPO_ROOT}/idl/codegen/ensure_generated.sh"
#
# It runs generate_all.sh, optionally builds bindings/proto-ts/dist, and then
# asserts (check_generated_trees.sh) that the output is actually there. The
# assertion is the point: a soft-skipped generator inside generate_all.sh exits
# 0 with a warning, so "generate_all.sh succeeded" is not by itself proof that
# anything was written.
#
# Options:
#   --only LIST      restrict to a comma-separated subset of
#                    swift,kotlin,dart,ts,cpp,python — both the generation and
#                    the verification. A Web packaging run on a Linux runner
#                    must not need protoc-gen-swift, wire-compiler and a Dart
#                    SDK to produce TypeScript, and must not be failed by the
#                    absence of bindings it does not ship.
#   --with-ts-dist   also `npm ci` + `npm run build` in bindings/proto-ts, so
#                    dist/ (the only thing the npm package ships) exists. Use
#                    this from packaging paths that `npm pack` proto-ts without
#                    building it themselves.
#   --skip-dart      forwarded to generate_all.sh (no Dart 3 toolchain here).
#   --verify-only    skip generation, run the assertions only.
#
# Environment:
#   RAC_SKIP_CODEGEN=1   skip generation (still verifies). For a caller that has
#                        already generated in the same session — e.g. a release
#                        job that runs codegen once and then packages five SDKs.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

WITH_TS_DIST=0
VERIFY_ONLY=0
SKIP_DART=0
ONLY=""
GEN_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --with-ts-dist) WITH_TS_DIST=1; shift ;;
        --verify-only)  VERIFY_ONLY=1; shift ;;
        --skip-dart)    SKIP_DART=1; GEN_ARGS+=("--skip-dart"); shift ;;
        --only)
            [ $# -ge 2 ] && [ -n "${2:-}" ] || {
                echo "ensure_generated.sh: --only requires a value (e.g. --only ts)" >&2
                exit 2
            }
            ONLY="$2"; shift 2 ;;
        --only=*)       ONLY="${1#--only=}"; shift ;;
        -h|--help)      sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "ensure_generated.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

# Validate the EFFECTIVE selection, not the requested one. --skip-dart removes
# Dart from generation, so validating the unmodified set made
# `ensure_generated.sh --skip-dart` on a fresh checkout generate no Dart tree
# and then fail its own check. Same for `--only ...,dart --skip-dart`.
CHECK_ONLY="${ONLY}"
if [ "${SKIP_DART}" -eq 1 ]; then
    if [ -z "${CHECK_ONLY}" ]; then
        CHECK_ONLY="swift,kotlin,ts,cpp,python"
    else
        CHECK_ONLY="$(printf '%s' "${CHECK_ONLY}" | tr ',' '\n' \
            | grep -vx 'dart' | paste -sd, -)"
    fi
fi

CHECK_ARGS=()
if [ -n "${ONLY}" ]; then
    GEN_ARGS+=("--only" "${ONLY}")
fi
SKIP_CHECK=0
if [ -n "${CHECK_ONLY}" ]; then
    CHECK_ARGS+=("--only" "${CHECK_ONLY}")
elif [ -n "${ONLY}" ]; then
    # `--only dart --skip-dart` asks for nothing at all. An empty --only means
    # "every language" to check_generated_trees.sh, so passing it through would
    # validate trees this run never intended to produce.
    SKIP_CHECK=1
fi

if [ "${RAC_SKIP_CODEGEN:-0}" = "1" ]; then
    VERIFY_ONLY=1
fi

if [ "${VERIFY_ONLY}" -eq 0 ]; then
    echo ">> generating IDL bindings (prerequisite for packaging)"
    "${SCRIPT_DIR}/generate_all.sh" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"}
else
    echo ">> skipping generation (verify only)"
fi

if [ "${WITH_TS_DIST}" -eq 1 ]; then
    PROTO_TS="${REPO_ROOT}/bindings/proto-ts"
    echo ">> building ${PROTO_TS#"${REPO_ROOT}/"}/dist (tsc)"
    # --workspaces=false: proto-ts sits inside the repo-root Yarn workspace,
    # whose `workspace:*` specifiers npm cannot parse (EUNSUPPORTEDPROTOCOL).
    if [ -f "${PROTO_TS}/package-lock.json" ]; then
        (cd "${PROTO_TS}" && npm ci --workspaces=false --no-audit --no-fund)
    else
        (cd "${PROTO_TS}" && npm install --package-lock=false --workspaces=false --no-audit --no-fund)
    fi
    (cd "${PROTO_TS}" && npm run build)
    CHECK_ARGS+=(--with-built)
fi

if [ "${SKIP_CHECK}" -eq 1 ]; then
    echo ">> nothing selected to verify (every requested language was skipped)"
else
    "${SCRIPT_DIR}/check_generated_trees.sh" ${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"}
fi
