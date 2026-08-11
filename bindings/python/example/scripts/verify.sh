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

# Every namespace the v3 surface promises must be importable without a native build.
namespaces = [
    "llm", "vlm", "stt", "tts", "vad", "embeddings", "rerank", "images",
    "diarization", "segmentation", "voice", "rag", "models", "lora",
]
missing = [name for name in namespaces if not hasattr(runanywhere, name)]
assert not missing, f"missing namespaces: {missing}"
assert callable(runanywhere.initialize)
print(
    f"runanywhere {runanywhere.__version__} imports OK "
    f"({len(runanywhere.__all__)} public names, {len(namespaces)} namespaces)"
)
EOF

echo "verify.sh: OK"
