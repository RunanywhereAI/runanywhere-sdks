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
python -m grpc_tools.protoc \
    --proto_path="${IDL_DIR}" \
    --python_out="${OUT_DIR}" \
    rac_options.proto rag.proto

# Rewrite the bare cross-file import to a package-relative one.
sed -i.bak 's/^import rac_options_pb2 as/from runanywhere._proto import rac_options_pb2 as/' \
    "${OUT_DIR}/rag_pb2.py"
rm -f "${OUT_DIR}/rag_pb2.py.bak"

# Emit the repo-standard module preamble: protoc's generated modules carry a docstring but not
# `from __future__ import annotations`. Insert it right after the module docstring (so it stays
# the first statement, before the protobuf imports) in each generated module.
for _f in rag_pb2.py rac_options_pb2.py; do
    sed -i.bak '/^"""Generated protocol buffer code."""$/a from __future__ import annotations' \
        "${OUT_DIR}/${_f}"
    rm -f "${OUT_DIR}/${_f}.bak"
done

cat > "${OUT_DIR}/__init__.py" <<'EOF'
"""Generated protobuf modules (do not edit; run idl/codegen/generate_python.sh)."""
from __future__ import annotations
EOF

echo "[OK] wrote ${OUT_DIR}/{rac_options_pb2.py, rag_pb2.py, __init__.py}"
