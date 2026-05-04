#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# CI drift check — regenerates every language binding from the committed .proto
# schemas and fails if `git diff --exit-code` shows any change. This is the
# single mechanism that prevents hand-written enum drift across SDKs.
#
# Run locally:
#   ./idl/codegen/ci-drift-check.sh
#
# Run in CI:
#   .github/workflows/idl-drift-check.yml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${REPO_ROOT}"

# Regenerate every language.
"${SCRIPT_DIR}/generate_all.sh"

# Fail loud on any drift.
if ! git diff --exit-code --stat; then
    echo "" >&2
    echo "::error::IDL-generated code is out of sync with .proto sources." >&2
    echo "" >&2
    echo "Run ./idl/codegen/generate_all.sh locally, commit the result," >&2
    echo "and push again. The diff above lists the affected files." >&2
    exit 1
fi

echo "✓ No drift detected — committed generated files match fresh output."
