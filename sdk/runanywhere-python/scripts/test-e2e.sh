#!/usr/bin/env bash
#
# End-to-end test for the RunAnywhere Python SDK.
#
# Phases:
#   1. Create an isolated venv.
#   2. Build + install the package with the native _core extension (scikit-build-core
#      -> CMake, backends on) plus the test extras.
#   3. Sanity-check that the compiled _core loads (real native, not the test fake).
#   4. Run the full pytest suite — every modality facade (llm, stt/tts audio, vad,
#      rag, embeddings, generation, streaming, structured, thinking, events,
#      download, catalog, server) exercised against the recording fake core, plus
#      test_smoke against the real core when a model is cached.
#
# Env:
#   PY_E2E_NATIVE=0   Skip the native build; install test deps only and run the
#                     pure-Python suite (fast; every facade test still runs via
#                     the recording fake). Default 1 (build native).
#   PY_E2E_VENV=path  venv location (default .venv-e2e next to pyproject.toml).
#
# Usage:
#   sdk/runanywhere-python/scripts/test-e2e.sh
#   PY_E2E_NATIVE=0 sdk/runanywhere-python/scripts/test-e2e.sh
#
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PKG_DIR"

VENV="${PY_E2E_VENV:-$PKG_DIR/.venv-e2e}"
BUILD_NATIVE="${PY_E2E_NATIVE:-1}"
PY="${PYTHON:-python3}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Creating venv: $VENV"
"$PY" -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install -U pip wheel >/dev/null

if [ "$BUILD_NATIVE" = "1" ]; then
  step "Building + installing package with native _core (scikit-build-core -> CMake, backends on)"
  # This compiles the runanywhere_core extension from commons source; first run is slow.
  pip install -e ".[test]"
else
  step "Installing test deps only (skipping native build; pure-Python suite)"
  pip install pytest "httpx>=0.24" "protobuf>=5.29,<7"
fi

step "Sanity: import the pure-Python package"
python -c "import runanywhere; print('runanywhere', getattr(runanywhere, '__version__', '?'))"

if [ "$BUILD_NATIVE" = "1" ]; then
  step "Sanity: load the real compiled _core"
  if python -c "from runanywhere._native import get_core; c=get_core(); print('native _core loaded:', bool(c))"; then
    echo "  native extension loads."
  else
    echo "  WARNING: native _core did not load; test_smoke will skip. Facade tests still run on the fake."
  fi
fi

step "Running full pytest suite (all modality facades)"
# -rs surfaces skips (e.g. test_smoke when no cached model) so coverage is visible.
python -m pytest tests -q -rs
rc=$?

step "Done (pytest exit=$rc)"
exit "$rc"
