#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run every codegen for every language. Called from CI (idl-drift-check.yml)
# and from local workflows after edits to any *.proto file under idl/.
#
# Flags:
#   --skip-dart   Skip Dart codegen (use when Dart 3.0+ is unavailable
#                 locally; CI regenerates Dart bindings on the pinned toolchain).
#   --only LIST   Comma-separated subset of swift,kotlin,dart,ts,cpp,python.
#                 Default: all six.
#
#                 Exists because the bindings are no longer committed, so a CI
#                 job that compiles one SDK has to generate that SDK's code
#                 first — and a Linux Web job should not have to install
#                 protoc-gen-swift and wire-compiler to do it. Every generator
#                 reads the same idl/*.proto and writes to a disjoint tree, so
#                 the subsets are independent.
#
#                 The two cross-cutting post-processors (the C defaults header
#                 and the default-pool constants) run whenever their language is
#                 selected; the default pool emits all seven targets in one pass
#                 by design, so it writes the same bytes regardless of subset.
set -euo pipefail

# Deterministic environment. Every generator below must emit the same bytes on
# a developer laptop and on a CI runner, so the few ambient inputs that can
# reorder or reformat output are pinned here rather than inherited:
#   LC_ALL/LANG  — collation for every `sort` in this pipeline (glibc's
#                  en_US.UTF-8 ignores punctuation at the primary level, so
#                  `rac_options.proto` vs `rag.proto` can order differently
#                  than under C).
#   TZ           — any generator that formats a date would otherwise embed the
#                  runner's local time.
#   PYTHONHASHSEED — the convenience generators walk descriptor sets; a stray
#                  set/frozenset iteration would otherwise be seed-dependent.
export LC_ALL=C
export LANG=C
export TZ=UTC
export PYTHONHASHSEED=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IDL_DIR="${REPO_ROOT}/idl"

SKIP_DART=0
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-dart) SKIP_DART=1; shift ;;
        --only) ONLY="${2:-}"; shift 2 ;;
        --only=*) ONLY="${1#--only=}"; shift ;;
        -h|--help)
            sed -n '1,30p' "$0" | sed 's/^#//'
            exit 0
            ;;
        *) echo "generate_all.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

ALL_LANGS="swift kotlin dart ts cpp python"
if [ -z "${ONLY}" ]; then
    SELECTED="${ALL_LANGS}"
else
    SELECTED="$(printf '%s' "${ONLY}" | tr ',' ' ')"
    for l in ${SELECTED}; do
        case " ${ALL_LANGS} " in
            *" ${l} "*) ;;
            *) echo "generate_all.sh: --only: unknown language '${l}' (want: ${ALL_LANGS// /, })" >&2; exit 2 ;;
        esac
    done
fi
want() { case " ${SELECTED} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Dart is opt-out as well as opt-in: --skip-dart predates --only and is still
# how a machine without Dart 3 runs everything else.
[ "${SKIP_DART}" -eq 1 ] && SELECTED="${SELECTED//dart/}"

# --- serialize concurrent runs ----------------------------------------------
# Three build systems now invoke this script on their own schedule — a CMake
# configure (core/CMakeLists.txt), a Gradle preBuild, and a developer in a
# terminal — and they can overlap. Two runs interleaving inside the same
# generated tree, or inside the shared bootstrap caches under
# ~/.cache/runanywhere, produce a tree that is neither run's output.
#
# mkdir is the only atomic create-if-absent primitive available on every host
# this repo builds on; flock(1) exists on Linux but not on macOS or Git Bash.
# The wait is BOUNDED and then proceeds with a warning: a codegen that is
# merely racy is a much better failure than a build that blocks forever, which
# is what an unbounded lock would introduce.
LOCK_DIR="${SCRIPT_DIR}/.codegen.lock.d"
LOCK_TIMEOUT="${RAC_CODEGEN_LOCK_TIMEOUT:-900}"
LOCK_HELD=0
release_lock() {
    if [ "${LOCK_HELD}" -eq 1 ]; then
        LOCK_HELD=0
        rm -rf "${LOCK_DIR}" 2>/dev/null || true
    fi
}
waited=0
while :; do
    if mkdir "${LOCK_DIR}" 2>/dev/null; then
        LOCK_HELD=1
        trap release_lock EXIT INT TERM
        break
    fi
    if [ "${waited}" -ge "${LOCK_TIMEOUT}" ]; then
        # Either a genuinely long run, or a lock orphaned by a killed build.
        # Break it rather than fail: the next run must not inherit the jam.
        echo "warning: codegen lock ${LOCK_DIR} held for >${LOCK_TIMEOUT}s; breaking it and proceeding" >&2
        rm -rf "${LOCK_DIR}" 2>/dev/null || true
        break
    fi
    [ "${waited}" -eq 0 ] && echo "▶ another codegen run holds ${LOCK_DIR}; waiting" >&2
    sleep 2
    waited=$((waited + 2))
done

# protoc is not "install it however you like": it bakes its own
# major.minor.patch into the C++ headers ("#if PROTOBUF_VERSION != 7035001")
# and into every ts-proto file header ("//   protoc  v7.35.1"), so the output
# is a function of the compiler patch level as much as of the schemas. Neither
# Homebrew nor apt can pin a patch level, and nothing generated here is
# committed any more, so every consumer — a laptop, twenty CI jobs, a CMake
# configure, a Gradle build — has to be able to obtain exactly
# core/VERSIONS::PROTOC_VERSION on its own.
#
# bootstrap_protoc.sh is that guarantee: it returns the pinned protoc, using
# one already on PATH when it matches and otherwise downloading + checksum-
# verifying the official prebuilt release asset into a per-user cache. Its
# stdout is the executable path and nothing else.
if ! PROTOC_BIN="$("${SCRIPT_DIR}/bootstrap_protoc.sh")"; then
    echo "error: could not obtain the pinned protoc (see above)." >&2
    echo "       Set RAC_PROTOC=/path/to/protoc to use an existing install," >&2
    echo "       or run scripts/setup/setup-toolchain.sh." >&2
    exit 127
fi
# Put it on PATH for the generators below — but ONLY when that changes the
# answer. `dirname "${PROTOC_BIN}"` is frequently a general-purpose bin
# directory: bootstrap_protoc.sh accepts a protoc already on PATH, and on a
# macOS CI runner `brew install swift-protobuf` drags in protobuf, so that
# directory is /opt/homebrew/bin. Prepending it unconditionally re-orders the
# whole toolchain — Homebrew's node/npm then shadow the tool-cache Node that
# actions/setup-node put first, `npm root -g` starts answering
# /opt/homebrew/lib/node_modules, and generate_ts.sh cannot find the
# protoc-gen-ts_proto that `npm install -g` placed under the *other* prefix.
# If protoc already resolves to exactly this binary, PATH is already correct.
CURRENT_PROTOC="$(command -v protoc 2>/dev/null || true)"
if [ "${CURRENT_PROTOC}" != "${PROTOC_BIN}" ]; then
    PATH="$(dirname "${PROTOC_BIN}"):${PATH}"
    export PATH
fi
# Nested resolutions (generate_cpp.sh, the CMake hook re-entering) then agree
# with this one by construction instead of re-deriving it.
export RAC_PROTOC="${PROTOC_BIN}"

# The Python half of the toolchain, obtained the same way and for the same
# reason. Every driver below that turns rac_* annotations into code imports
# google.protobuf. These used to soft-skip with a warning, which was survivable
# only because the C header they produce was committed: the tracked copy carried
# the build when the generator did not run. Nothing is tracked now, so a skipped
# generator is a missing build input — fail here, where the cause is visible,
# instead of at `#include "rac/rac_defaults_generated.h"` an hour later.
if ! RA_PYTHON="$("${SCRIPT_DIR}/bootstrap_pyproto.sh")"; then
    echo "error: could not obtain a Python with the protobuf runtime (see above)." >&2
    echo "       Set RAC_PYTHON=/path/to/python3 that has protobuf + pyyaml." >&2
    exit 127
fi
export RA_PYTHON

VERSIONS_FILE="${REPO_ROOT}/core/VERSIONS"
if [ -f "${VERSIONS_FILE}" ]; then
    set -a
    eval "$(grep -E '^[A-Z_][A-Z0-9_]*=' "${VERSIONS_FILE}")"
    set +a
fi

PROTOC_ACTUAL="$(protoc --version | awk '{print $2}')"
echo "▶ protoc version: ${PROTOC_ACTUAL} (pinned ${PROTOC_VERSION:-${PROTOC_VERSION_MAJOR:-any}})"
if [ -n "${PROTOC_VERSION:-}" ] && [ "${PROTOC_ACTUAL}" != "${PROTOC_VERSION}" ]; then
    echo "error: protoc ${PROTOC_ACTUAL} does not match the pinned ${PROTOC_VERSION}" >&2
    echo "       (core/VERSIONS::PROTOC_VERSION). Generated C++ and TypeScript" >&2
    echo "       embed the compiler version, so a different protoc silently" >&2
    echo "       produces different bytes for identical schemas." >&2
    echo "       bootstrap_protoc.sh should have resolved this — check that it" >&2
    echo "       is not being bypassed by RAC_PROTOC or a stale PATH entry." >&2
    exit 1
fi

# Canonical proto-file list shared with every per-language codegen
# script via the RAC_PROTO_FILES env var (absolute paths, newline-separated,
# sorted). Discovery via `ls` prevents drift when a new .proto is added — the
# full list is derived from the filesystem, and each per-language script
# applies its own documented exclusion filter (RAC_PROTO_EXCLUDES_<lang>)
# rather than duplicating the positive list. Per-language scripts fall back
# to the same `ls "$IDL_DIR"/*.proto` discovery when invoked standalone, so
# behavior is identical whether run via generate_all.sh or individually.
RAC_PROTO_FILES="$(ls "${IDL_DIR}"/*.proto | LC_ALL=C sort)"
export RAC_PROTO_FILES
echo "▶ canonical proto file list:"
echo "${RAC_PROTO_FILES}" | sed 's|^.*/|    - |'
echo "▶ schema: $("${SCRIPT_DIR}/schema_lock.sh" --print)"

if want swift; then
    echo "▶ Swift proto codegen"
    "${SCRIPT_DIR}/generate_swift.sh"
fi

if want kotlin; then
echo "▶ Kotlin proto codegen"
"${SCRIPT_DIR}/generate_kotlin.sh"

# Emit RAConvenience.kt from rac_options.proto annotations on top of the
# Wire-generated message/enum types. Must run AFTER generate_kotlin.sh so the
# referenced types (ai.runanywhere.proto.v1.*) exist on disk; Wire emits a
# `companion object` on every message/enum, which the convenience extensions
# bind to. RA_PYTHON is resolved above and is not optional: RAConvenience.kt is
# compiled into the AAR, so skipping it produces a Kotlin SDK that does not
# build rather than one that merely lacks helpers.
"${RA_PYTHON}" "${SCRIPT_DIR}/generate_kotlin_convenience.py"
fi  # want kotlin

if ! want dart; then
    echo "▶ Dart proto codegen (skipped)"
else
    echo "▶ Dart proto codegen"
    "${SCRIPT_DIR}/generate_dart.sh"
    # Convenience post-processor (rac_* annotations -> defaults() / validate()
    # / wireString helpers).
    echo "▶ Dart convenience post-processor"
    "${RA_PYTHON}" "${SCRIPT_DIR}/generate_dart_convenience.py"
        # ra_result_codes.dart is codegen output (ErrorCode -> user-facing
        # message table derived from idl/errors.proto), but nothing used to
        # invoke its generator, so the file was committed once and then aged
        # out of the drift gate: an errors.proto edit could not make it stale
        # in CI because CI never regenerated it. Run it here so the one gate
    # that guards generated code actually covers it.
    echo "▶ Dart result-code messages"
    "${RA_PYTHON}" "${SCRIPT_DIR}/generate_dart_result_codes.py"
fi

if want ts; then
echo "▶ TypeScript proto codegen (RN + Web)"
"${SCRIPT_DIR}/generate_ts.sh"
# TypeScript convenience helpers (defaults / validate / wireString) derived
# from rac_* annotations. Part of the published proto-ts package, so its
# absence is a broken npm tarball, not a degraded developer experience.
"${RA_PYTHON}" "${SCRIPT_DIR}/generate_ts_convenience.py"
fi  # want ts

if want cpp; then
echo "▶ C++ proto codegen"
"${SCRIPT_DIR}/generate_cpp.sh"

# C macros for every rac_default annotation. commons composes its default
# structs (RAC_LLM_OPTIONS_DEFAULT and friends) from these, so the C layer that
# actually runs inference reads the same annotations the SDKs generate against.
# Unlike the four convenience post-processors this emits a plain header and
# needs no language toolchain beyond protoc + the python protobuf runtime.
echo "▶ C defaults header"
"${RA_PYTHON}" "${SCRIPT_DIR}/generate_cpp_defaults.py"
fi  # want cpp

# Swift / Kotlin / Dart / TypeScript constants for the central default pool.
# sdk_defaults.proto is excluded from the four message generators above, so its
# values reach the SDKs as plain constants rather than as a generated message
# type nobody puts on a wire.
echo "▶ Default pool constants (Swift/Kotlin/Dart/TS)"
"${RA_PYTHON}" "${SCRIPT_DIR}/generate_defaults_pool.py"

# AsyncIterable<T> stream wrappers for RN + Web. The
# template-based renderer is intentionally separate from generate_ts.sh
# (which uses ts-proto for messages) — different tools, different outputs.
#
# A single shared script renders the streams once into
# bindings/proto-ts/src/streams. Both RN and Web consume the result via
# @runanywhere/proto-ts; the previous generate_rn_streams.sh /
# generate_web_streams.sh pair was byte-identical and overwrote each
# other's output, masking unilateral edits.
if want ts; then
    echo "▶ Shared TS AsyncIterable streams"
    "${SCRIPT_DIR}/generate_streams.sh"
fi

# Python protobuf for the RAG surface (optional — needs grpcio-tools). Soft-skip
# when the package is missing so a non-Python developer environment still
# completes the upstream codegen; CI installs grpcio-tools and fails on drift.
if want python; then
echo "▶ Python proto codegen (RAG)"
if python3 -c 'import grpc_tools.protoc' >/dev/null 2>&1; then
    "${SCRIPT_DIR}/generate_python.sh"
else
    echo "warning: grpcio-tools not installed; skipping generate_python.sh" >&2
fi

# Python's ErrorCode / ErrorCategory. The Python SDK has no convenience
# post-processor because it reaches the C ABI directly for everything but RAG,
# so these 139 enum members were transcribed by hand under a "keep in sync"
# docstring. Only protoc + the python protobuf runtime are needed here, not
# grpcio-tools.
echo "▶ Python error enums"
"${RA_PYTHON}" "${SCRIPT_DIR}/generate_python_errors.py"
fi  # want python

# idl/SCHEMA_LOCK is refreshed LAST, and it is the only tracked artifact of a
# codegen run now that the language bindings are gitignored. That ordering is
# what gives it meaning: the lock moves only after every generator above has
# succeeded, so a committed lock that matches the .proto digest is proof that a
# full run happened against exactly these schemas. CI checks it with
# `schema_lock.sh --check` in place of the old "git status must be empty" gate.
# Only a FULL run may move the lock. A scoped run (--only ts, --skip-dart) is a
# partial regeneration; stamping the lock from one would assert "every binding
# matches these schemas" on the strength of having regenerated one of them.
if [ "${SELECTED// /}" = "${ALL_LANGS// /}" ]; then
    echo "▶ Schema lock"
    "${SCRIPT_DIR}/schema_lock.sh" --update
else
    echo "▶ Schema lock: not updated (partial run: ${SELECTED})"
fi

echo "✓ Proto codegen complete (${SELECTED})."
