#!/usr/bin/env bash
# =============================================================================
# detect-mode.sh
# =============================================================================
# Sets RAC_BUILD_MODE to "local" or "ci" based on the environment, unless the
# caller already set it. Other build scripts can `source` this to share the
# same detection logic:
#
#   source "$(dirname "$0")/../../../scripts/detect-mode.sh"
#
# Contract:
#   RAC_BUILD_MODE=ci    ← running in GitHub Actions (or any CI environment
#                           that sets $CI=true)
#   RAC_BUILD_MODE=local ← developer machine
#
# Behavior that should differ between modes:
#   local: tolerant of missing deps, uses cache, prints hints
#   ci:    strict toolchain checks, no cache warmup, fail fast
#
# Callers can force a mode by setting RAC_BUILD_MODE before sourcing this.
# =============================================================================

if [ -n "${RAC_BUILD_MODE:-}" ]; then
    # Respect explicit override
    :
elif [ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    RAC_BUILD_MODE="ci"
else
    RAC_BUILD_MODE="local"
fi

export RAC_BUILD_MODE

if [ "${VERBOSE:-}" = "1" ]; then
    echo "RAC_BUILD_MODE=${RAC_BUILD_MODE}"
fi
