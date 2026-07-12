#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Canonical llama.cpp WASM entry point used by the repository-level runner.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../wasm/scripts/build.sh" --llamacpp "$@"
