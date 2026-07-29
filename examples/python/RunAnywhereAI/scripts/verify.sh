#!/usr/bin/env bash
# Local verification gate: venv present, example compiles, SDK imports.
# Needs no model download and no network.
set -euo pipefail

cd "$(dirname "$0")/.."
PYTHON=".venv/bin/python"

[ -x "$PYTHON" ] || { echo "FAIL: .venv missing — create it per README.md" >&2; exit 1; }

"$PYTHON" -m compileall -q chat.py rag.py
"$PYTHON" - <<'EOF'
import runanywhere

client = runanywhere.RunAnywhere()
print(f"runanywhere {runanywhere.__version__} imports OK ({len(runanywhere.__all__)} public names)")
EOF

echo "verify.sh: OK"
