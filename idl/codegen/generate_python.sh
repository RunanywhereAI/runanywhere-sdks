#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Python protobuf bindings for the runanywhere-python SDK's native RAG binding.
#
# Requirements:
#   pip install "grpcio-tools==1.71.*"   # bundles a protoc that emits protobuf 5.x gencode
#
# Output:
#   sdk/runanywhere-python/runanywhere/_proto/{rac_options_pb2.py, rag_pb2.py}
#
# Only the RAG surface is bound in Python today (the rest of the SDK uses the flat C ABI), so we
# generate just rag.proto + its one import (rac_options.proto). protoc emits a BARE
# `import rac_options_pb2`, which only resolves if that module is on sys.path — the classic
# protobuf gotcha. We rewrite it to a package-relative import so the vendored files import each
# other correctly from inside the `runanywhere._proto` package.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="$(cd "${IDL_DIR}/.." && pwd)/sdk/runanywhere-python/runanywhere/_proto"

mkdir -p "${OUT_DIR}"
# Prefer python3 (CI installs grpcio-tools into the python3 environment). Fall
# back to python only when python3 is absent (some local pyenv/venv layouts).
PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  else
    echo "error: python3/python not found — install Python and grpcio-tools" >&2
    exit 1
  fi
fi
if ! "${PYTHON_BIN}" -c 'import grpc_tools.protoc' >/dev/null 2>&1; then
  echo "error: ${PYTHON_BIN} is missing grpc_tools.protoc — run: ${PYTHON_BIN} -m pip install 'grpcio-tools==1.71.*'" >&2
  exit 1
fi
"${PYTHON_BIN}" -m grpc_tools.protoc \
    --proto_path="${IDL_DIR}" \
    --python_out="${OUT_DIR}" \
    rac_options.proto rag.proto

# Rewrite the bare cross-file import to a package-relative one, and insert
# `from __future__ import annotations` after the module docstring. Use Python
# (not GNU-only `sed -i … a`) so this is portable on macOS BSD sed in CI.
OUT_DIR="${OUT_DIR}" "${PYTHON_BIN}" - <<'PY'
from pathlib import Path
import os

out = Path(os.environ["OUT_DIR"])
rag = out / "rag_pb2.py"
text = rag.read_text()
text = text.replace(
    "import rac_options_pb2 as",
    "from runanywhere._proto import rac_options_pb2 as",
    1,
)
rag.write_text(text)

future = "from __future__ import annotations\n"
doc = '"""Generated protocol buffer code."""\n'
for name in ("rag_pb2.py", "rac_options_pb2.py"):
    path = out / name
    body = path.read_text()
    if future.strip() in body.splitlines()[:5]:
        continue
    if doc not in body:
        raise SystemExit(f"unexpected protoc output in {path}: missing module docstring")
    path.write_text(body.replace(doc, doc + future, 1))
PY

cat > "${OUT_DIR}/__init__.py" <<'EOF'
"""Generated protobuf modules (do not edit; run idl/codegen/generate_python.sh)."""
from __future__ import annotations
EOF

echo "[OK] wrote ${OUT_DIR}/{rac_options_pb2.py, rag_pb2.py, __init__.py}"
