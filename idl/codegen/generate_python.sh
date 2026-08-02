#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Python protobuf bindings for the runanywhere-python SDK's native RAG binding.
#
# Requirements:
#   pip install "grpcio-tools==1.71.*"   # bundles a protoc that emits protobuf 5.x gencode
#
# Output:
#   sdk/runanywhere-python/runanywhere/_proto/*_pb2.py
#
# Only the RAG surface is bound in Python today (the rest of the SDK uses the flat C ABI), so we
# generate rag.proto plus its transitive imports (llm_options.proto pulls in model_types,
# structured_output, thinking_tag_pattern, tool_calling, hardware_profile, storage_types; several
# of those now import errors.proto for the embedded SDKError payload).
# protoc emits BARE `import x_pb2` lines, which only resolve if those modules are on sys.path —
# the classic protobuf gotcha. We rewrite every one to a package-relative import so the vendored
# files import each other correctly from inside the `runanywhere._proto` package.
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
# rag.proto and its transitive import closure.
PROTOS=(
  rag.proto
  rac_options.proto
  errors.proto
  llm_options.proto
  model_types.proto
  hardware_profile.proto
  storage_types.proto
  structured_output.proto
  thinking_tag_pattern.proto
  token_usage.proto
  tool_calling.proto
)

"${PYTHON_BIN}" -m grpc_tools.protoc \
    --proto_path="${IDL_DIR}" \
    --python_out="${OUT_DIR}" \
    "${PROTOS[@]}"

# Rewrite every bare cross-file import to a package-relative one, and insert
# `from __future__ import annotations` after the module docstring. Use Python
# (not GNU-only `sed -i … a`) so this is portable on macOS BSD sed in CI.
OUT_DIR="${OUT_DIR}" "${PYTHON_BIN}" - <<'PY'
from pathlib import Path
import os
import re

out = Path(os.environ["OUT_DIR"])
future = "from __future__ import annotations\n"
doc = '"""Generated protocol buffer code."""\n'
for path in sorted(out.glob("*_pb2.py")):
    body = path.read_text()
    body = re.sub(
        r"^import (\w+_pb2) as",
        r"from runanywhere._proto import \1 as",
        body,
        flags=re.M,
    )
    if future.strip() not in body.splitlines()[:8]:
        if doc not in body:
            raise SystemExit(f"unexpected protoc output in {path}: missing module docstring")
        body = body.replace(doc, doc + future, 1)
    path.write_text(body)
PY

cat > "${OUT_DIR}/__init__.py" <<'EOF'
"""Generated protobuf modules (do not edit; run idl/codegen/generate_python.sh)."""
from __future__ import annotations
EOF

echo "[OK] wrote ${OUT_DIR}/*_pb2.py + __init__.py"
