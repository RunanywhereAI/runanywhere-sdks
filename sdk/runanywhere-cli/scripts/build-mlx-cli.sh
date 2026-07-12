#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

# The CLI is a local developer target and consumes the staged XCFrameworks.
export RUNANYWHERE_USE_LOCAL_NATIVES=1

SWIFT_BUILD_JOBS="${SWIFT_BUILD_JOBS:-2}"
CONFIGURATION="${CONFIGURATION:-debug}"
PRODUCT="RunAnywhereMLXCLI"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "CONFIGURATION must be debug or release" >&2
  exit 2
fi

swift_args=(--product "$PRODUCT" --jobs "$SWIFT_BUILD_JOBS")
if [[ "$CONFIGURATION" == "release" ]]; then
  swift_args=(-c release "${swift_args[@]}")
fi

echo "building $PRODUCT ($CONFIGURATION, jobs=$SWIFT_BUILD_JOBS)"
swift build "${swift_args[@]}"

if [[ "$CONFIGURATION" == "release" ]]; then
  BIN_DIR="$(swift build -c release --show-bin-path)"
else
  BIN_DIR="$(swift build --show-bin-path)"
fi
EXE="$BIN_DIR/$PRODUCT"
if [[ ! -x "$EXE" ]]; then
  echo "expected executable not found: $EXE" >&2
  exit 1
fi

MLX_KERNEL_DIR="$REPO_ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels"
MLX_CPP_ROOT="$REPO_ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx"
if [[ ! -d "$MLX_KERNEL_DIR" ]]; then
  echo "mlx-swift checkout missing; run swift package resolve first" >&2
  exit 1
fi

AIR_DIR="${RUNANYWHERE_MLX_AIR_DIR:-$REPO_ROOT/.build/mlx-metallib/$CONFIGURATION}"
rm -rf "$AIR_DIR"
mkdir -p "$AIR_DIR"

metal_flags=(
  -x metal
  -Wall
  -Wextra
  -fno-fast-math
  -Wno-c++17-extensions
  -Wno-c++20-extensions
)

airs=()
while IFS= read -r metal_file; do
  rel="${metal_file#"$MLX_KERNEL_DIR"/}"
  air_file="$AIR_DIR/${rel%.metal}.air"
  mkdir -p "$(dirname "$air_file")"
  echo "metal $rel"
  xcrun -sdk macosx metal "${metal_flags[@]}" -c "$metal_file" -I"$MLX_CPP_ROOT" -o "$air_file"
  airs+=("$air_file")
done < <(find "$MLX_KERNEL_DIR" -name '*.metal' -type f | sort)

if [[ "${#airs[@]}" -eq 0 ]]; then
  echo "no MLX metal kernels found under $MLX_KERNEL_DIR" >&2
  exit 1
fi

echo "linking mlx.metallib (${#airs[@]} kernels)"
xcrun -sdk macosx metallib "${airs[@]}" -o "$BIN_DIR/mlx.metallib"

echo "ready: $EXE"
echo "metallib: $BIN_DIR/mlx.metallib"
