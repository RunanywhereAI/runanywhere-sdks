#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# schema_lock.sh — the tracked fingerprint of the .proto surface
# =============================================================================
# WHY THIS EXISTS
#   The language bindings are no longer committed (see .gitignore), so the old
#   drift signal — "regenerate, then `git status` must be empty" — cannot work
#   for them: regenerating untracked files always leaves a clean tree. Something
#   tracked has to change when the schema changes, or a .proto edit can land
#   with nobody having run codegen even once.
#
#   idl/SCHEMA_LOCK is that tracked something. It records a digest of every
#   idl/*.proto, and `generate_all.sh` refreshes it on every run. So:
#
#     - Edit a .proto, run codegen, commit  ->  SCHEMA_LOCK moves with it.
#     - Edit a .proto, DON'T run codegen    ->  CI's `--check` fails, because
#                                               the committed lock no longer
#                                               matches the .proto bytes.
#
#   It also answers "which IDL is this build from?" — IDL_VERSION plus the
#   digest identify the schema exactly, independent of the SDK release version.
#
# THE DIGEST
#   sha256 over, for each idl/*.proto in LC_ALL=C basename order:
#       "<basename>\n<sha256-of-contents>\n"
#   Basenames only, so the value is identical no matter where the repo is
#   checked out. Adding, removing, renaming, or editing any .proto moves it.
#
# IDL_VERSION (idl/VERSION) is hand-maintained semver for the schema surface:
#   patch = comments/docs only · minor = additive (new field/message/enum
#   value) · major = wire-breaking. `--check --require-bump BASE_LOCK` enforces
#   that it moved whenever the digest did.
#
# Usage:
#   idl/codegen/schema_lock.sh --update              rewrite idl/SCHEMA_LOCK
#   idl/codegen/schema_lock.sh --check               fail if the lock is stale
#   idl/codegen/schema_lock.sh --check --require-bump FILE
#                                                    ...and fail if the digest
#                                                    moved vs FILE (a base-ref
#                                                    copy of SCHEMA_LOCK)
#                                                    without IDL_VERSION moving
#   idl/codegen/schema_lock.sh --print                emit the resolved id
# =============================================================================
set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IDL_DIR="${REPO_ROOT}/idl"
LOCK_FILE="${IDL_DIR}/SCHEMA_LOCK"
VERSION_FILE="${IDL_DIR}/VERSION"

MODE="print"
REQUIRE_BUMP_AGAINST=""
while [ $# -gt 0 ]; do
    case "$1" in
        --update) MODE="update"; shift ;;
        --check)  MODE="check"; shift ;;
        --print)  MODE="print"; shift ;;
        --require-bump) REQUIRE_BUMP_AGAINST="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "schema_lock.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

sha256_of() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$@" | awk '{print $1}'
    else
        sha256sum "$@" | awk '{print $1}'
    fi
}

compute_digest() {
    local f
    {
        for f in $(ls "${IDL_DIR}"/*.proto | sort); do
            printf '%s\n' "$(basename "$f")"
            sha256_of "$f"
        done
    } | { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi; } | awk '{print $1}'
}

proto_count() { ls "${IDL_DIR}"/*.proto | wc -l | tr -d ' '; }

read_key() {  # read_key <file> <KEY>
    [ -f "$1" ] || return 0
    grep -E "^$2=" "$1" | head -1 | cut -d= -f2- | tr -d '[:space:]'
}

if [ ! -f "${VERSION_FILE}" ]; then
    echo "schema_lock.sh: missing ${VERSION_FILE}" >&2
    exit 1
fi
IDL_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
if ! [[ "${IDL_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "schema_lock.sh: idl/VERSION must be bare semver, got '${IDL_VERSION}'" >&2
    exit 1
fi

DIGEST="$(compute_digest)"
COUNT="$(proto_count)"

# protoc's exact release is part of the identity of the generated code (it is
# stamped into the C++ headers and every ts-proto file), so record it next to
# the schema digest rather than making a consumer go dig it out of core/VERSIONS.
PROTOC_PIN="$(read_key "${REPO_ROOT}/core/VERSIONS" PROTOC_VERSION)"

write_lock() {
    cat > "${LOCK_FILE}" <<EOF
# =============================================================================
# idl/SCHEMA_LOCK — machine-written. Do not hand-edit.
# =============================================================================
# Refreshed by idl/codegen/generate_all.sh (via idl/codegen/schema_lock.sh
# --update). This file is the TRACKED proof that codegen was run against the
# current .proto surface: the generated bindings themselves are gitignored, so
# this lock — not \`git status\` — is what makes schema drift detectable.
#
# IDL_SCHEMA_SHA256 is sha256 over "<basename>\\n<sha256-of-contents>\\n" for
# every idl/*.proto in LC_ALL=C basename order. Path-independent by
# construction, so it is identical in every checkout.
#
# Verify:  idl/codegen/schema_lock.sh --check
# =============================================================================
IDL_VERSION=${IDL_VERSION}
IDL_PROTO_COUNT=${COUNT}
IDL_SCHEMA_SHA256=${DIGEST}
IDL_PROTOC_VERSION=${PROTOC_PIN}
EOF
}

case "${MODE}" in
    print)
        echo "idl ${IDL_VERSION} (${COUNT} protos, sha256 ${DIGEST})"
        ;;

    update)
        if [ -f "${LOCK_FILE}" ] \
           && [ "$(read_key "${LOCK_FILE}" IDL_SCHEMA_SHA256)" = "${DIGEST}" ] \
           && [ "$(read_key "${LOCK_FILE}" IDL_VERSION)" = "${IDL_VERSION}" ] \
           && [ "$(read_key "${LOCK_FILE}" IDL_PROTOC_VERSION)" = "${PROTOC_PIN}" ]; then
            echo "  idl/SCHEMA_LOCK already current: ${IDL_VERSION} / ${DIGEST}"
        else
            write_lock
            echo "  idl/SCHEMA_LOCK -> ${IDL_VERSION} / ${DIGEST}"
        fi
        ;;

    check)
        rc=0
        if [ ! -f "${LOCK_FILE}" ]; then
            echo "::error::idl/SCHEMA_LOCK is missing. Run ./idl/codegen/generate_all.sh and commit it." >&2
            exit 1
        fi
        locked_digest="$(read_key "${LOCK_FILE}" IDL_SCHEMA_SHA256)"
        locked_version="$(read_key "${LOCK_FILE}" IDL_VERSION)"
        locked_protoc="$(read_key "${LOCK_FILE}" IDL_PROTOC_VERSION)"

        if [ "${locked_digest}" != "${DIGEST}" ]; then
            echo "::error::idl/SCHEMA_LOCK is stale — the .proto surface changed but codegen was not re-run." >&2
            echo "  committed: ${locked_digest}" >&2
            echo "  actual:    ${DIGEST}" >&2
            echo "  Fix: ./idl/codegen/generate_all.sh && git add idl/SCHEMA_LOCK" >&2
            rc=1
        fi
        if [ "${locked_version}" != "${IDL_VERSION}" ]; then
            echo "::error::idl/SCHEMA_LOCK records IDL_VERSION=${locked_version} but idl/VERSION says ${IDL_VERSION}." >&2
            echo "  Fix: ./idl/codegen/generate_all.sh && git add idl/SCHEMA_LOCK" >&2
            rc=1
        fi
        if [ -n "${PROTOC_PIN}" ] && [ "${locked_protoc}" != "${PROTOC_PIN}" ]; then
            echo "::error::idl/SCHEMA_LOCK records protoc ${locked_protoc} but core/VERSIONS pins ${PROTOC_PIN}." >&2
            echo "  protoc stamps its version into the generated C++ and TypeScript, so a" >&2
            echo "  changed pin means every binding must be regenerated in the same commit." >&2
            rc=1
        fi

        # A caller that names a base lock and then hands over a path that is not
        # there gets an error, not a silent pass. The old `&& [ -f ... ]` made
        # the whole bump check vanish on a typo or a failed `git show`, which is
        # precisely when it is most needed. Callers that have no base to compare
        # against pass an empty string (the workflow guards on that).
        if [ -n "${REQUIRE_BUMP_AGAINST}" ] && [ ! -f "${REQUIRE_BUMP_AGAINST}" ]; then
            echo "::error::--require-bump ${REQUIRE_BUMP_AGAINST}: no such file." >&2
            echo "  The base copy of idl/SCHEMA_LOCK could not be read, so the" >&2
            echo "  'did idl/VERSION move with the schema?' check cannot run." >&2
            rc=1
        fi

        if [ -n "${REQUIRE_BUMP_AGAINST}" ] && [ -f "${REQUIRE_BUMP_AGAINST}" ]; then
            base_digest="$(read_key "${REQUIRE_BUMP_AGAINST}" IDL_SCHEMA_SHA256)"
            base_version="$(read_key "${REQUIRE_BUMP_AGAINST}" IDL_VERSION)"
            if [ -n "${base_digest}" ] && [ "${base_digest}" != "${DIGEST}" ] \
               && [ "${base_version}" = "${IDL_VERSION}" ]; then
                echo "::error::the .proto surface changed but idl/VERSION is still ${IDL_VERSION}." >&2
                echo "  base digest: ${base_digest}" >&2
                echo "  this digest: ${DIGEST}" >&2
                echo "  Bump idl/VERSION — patch for comments only, minor for additive" >&2
                echo "  changes, major for anything wire-breaking — then re-run" >&2
                echo "  ./idl/codegen/generate_all.sh so SCHEMA_LOCK follows." >&2
                rc=1
            fi
        fi

        if [ "${rc}" -eq 0 ]; then
            echo "✓ idl/SCHEMA_LOCK current: ${IDL_VERSION} / ${DIGEST} (${COUNT} protos)"
        fi
        exit "${rc}"
        ;;
esac
