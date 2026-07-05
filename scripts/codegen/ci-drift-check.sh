#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/codegen/ci-drift-check.sh

Regenerate every language binding from the committed .proto schemas and fail
if 'git diff --exit-code' shows any change. This is the single mechanism that
prevents hand-written enum drift across SDKs.

Run in CI via .github/workflows/idl-drift-check.yml.
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

cd "${RAC_ROOT}"

"${SCRIPT_DIR}/generate_all.sh"

DRIFT=0
if ! git diff --exit-code --stat; then
    DRIFT=1
fi

# Also catch newly created files that codegen may produce (e.g., a new .proto
# added without committing the generated output).
UNTRACKED="$(git ls-files --others --exclude-standard -- .)"
if [[ -n "${UNTRACKED}" ]]; then
    log ""
    log "New untracked files after codegen:"
    echo "${UNTRACKED}" | sed 's/^/  ?? /' >&2
    DRIFT=1
fi

if [[ "${DRIFT}" -ne 0 ]]; then
    log ""
    log "::error::IDL-generated code is out of sync with .proto sources."
    log ""
    log "Run ./scripts/codegen/generate_all.sh locally, commit the result,"
    log "and push again. The diff above lists the affected files."
    exit 1
fi

ok "No drift detected — committed generated files match fresh output."
