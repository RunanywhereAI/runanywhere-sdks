#!/usr/bin/env bash
# Fetch a private engine pack (NeuRT / QHexRT) from the neurun GitHub release
# that core/VERSIONS pins. Public C++ desktop kits never include these.
#
#   NEURUN_TOKEN=... scripts/build/fetch-private-engine-pack.sh neurt macos-arm64
#   NEURUN_TOKEN=... scripts/build/fetch-private-engine-pack.sh qhexrt windows-arm64
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE="${1:?engine: neurt|qhexrt}"
SLICE="${2:?slice e.g. macos-arm64|windows-arm64}"
# shellcheck source=/dev/null
source "$ROOT/core/scripts/load-versions.sh"
TOKEN="${NEURUN_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "NEURUN_TOKEN (or GH_TOKEN) is required to fetch private engine packs." >&2
  exit 3
fi
case "$ENGINE" in
  neurt)
    exec "$ROOT/scripts/build/download-neurt.sh" --slice "$SLICE"
    ;;
  qhexrt)
    exec "$ROOT/scripts/build/download-qhexrt.sh" --abi "$SLICE"
    ;;
  *)
    echo "unknown engine $ENGINE" >&2
    exit 2
    ;;
esac
