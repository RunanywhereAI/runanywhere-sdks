#!/usr/bin/env bash
# Package a PRIVATE C++ desktop overlay (NeuRT or QHexRT).
#
# Public kits never include these engines. This tarball is a workflow artifact
# only — never a GitHub Release asset. Drop its lib/ (and bin/) onto a public
# kit prefix; find_package(RunAnywhere) discovers the extra archives.
#
#   package-private-engine-overlay.sh --engine neurt  --build-dir build/cpp-desktop-macos-arm64-neurt
#   package-private-engine-overlay.sh --engine qhexrt --build-dir build/cpp-desktop-windows-arm64-qhexrt
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/core/scripts/load-versions.sh"

ENGINE=""
BUILD_DIR=""
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)    ENGINE="${2:?}"; shift 2 ;;
    --build-dir) BUILD_DIR="${2:?}"; shift 2 ;;
    --out)       OUT="${2:?}"; shift 2 ;;
    -h|--help)   sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$ENGINE" && -n "$BUILD_DIR" ]] || {
  echo "usage: $0 --engine neurt|qhexrt --build-dir DIR [--out FILE]" >&2
  exit 2
}
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/core/VERSION")"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/lib" "$stage/bin" "$stage/share/runanywhere/private"

copy_one() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || { echo "missing $src" >&2; exit 1; }
  cp -R "$src" "$dest"
}

find_backend_archive() {
  local name="$1"
  local hit
  hit="$(find "$BUILD_DIR" \( -name "lib${name}.a" -o -name "${name}.lib" \) ! -path '*/CMakeFiles/*' | head -1)"
  [[ -n "$hit" ]] || { echo "built archive not found for $name under $BUILD_DIR" >&2; exit 1; }
  echo "$hit"
}

min_bytes() {
  local f="$1" n="$2"
  local sz
  sz="$(wc -c < "$f" | tr -d ' ')"
  if [[ "$sz" -lt "$n" ]]; then
    echo "stub refused: $f is ${sz} bytes (want >= $n)" >&2
    exit 1
  fi
}

case "$ENGINE" in
  neurt)
    SLICE="macos-arm64"
    PRE="$ROOT/core/third_party/neurt/${SLICE}"
    [[ -f "$PRE/RECEIPT.json" ]] || {
      echo "NeuRT prebuilt missing at $PRE — run download-neurt.sh --slice $SLICE" >&2
      exit 1
    }
    backend="$(find_backend_archive rac_backend_neurt)"
    min_bytes "$backend" 1000
    copy_one "$backend" "$stage/lib/"
    for lib in libneurt_core.a libneurt_rac_llm_ops.a libneurt_rac_stt_ops.a libneurt_rac_diffusion.a; do
      copy_one "$PRE/lib/$lib" "$stage/lib/"
      min_bytes "$stage/lib/$lib" 8000
    done
    min_bytes "$stage/lib/libneurt_core.a" 100000
    copy_one "$PRE/RECEIPT.json" "$stage/share/runanywhere/private/RECEIPT.json"
    printf 'neurt\n' > "$stage/share/runanywhere/private/ENGINE"
    OS_ARCH="macos-arm64"
    ;;
  qhexrt)
    PRE="$ROOT/engines/qhexrt/prebuilt/current"
    [[ -e "$PRE" ]] || {
      echo "QHexRT prebuilt missing at $PRE — run download-qhexrt.sh --abi win-arm64" >&2
      exit 1
    }
    backend="$(find_backend_archive rac_backend_qhexrt)"
    min_bytes "$backend" 1000
    copy_one "$backend" "$stage/lib/"
    core_lib="$PRE/lib/win-arm64/qhexrt_core.lib"
    host_lib="$PRE/lib/win-arm64/qhexrt_host.lib"
    if [[ ! -f "$core_lib" ]]; then
      core_lib="$PRE/lib/win-arm64/libqhexrt_core.a"
      host_lib="$PRE/lib/win-arm64/libqhexrt_host.a"
    fi
    copy_one "$core_lib" "$stage/lib/"
    copy_one "$host_lib" "$stage/lib/"
    min_bytes "$stage/lib/$(basename "$core_lib")" 8000
    if [[ -f "$PRE/qhexrt-build-receipt.json" ]]; then
      copy_one "$PRE/qhexrt-build-receipt.json" "$stage/share/runanywhere/private/RECEIPT.json"
    elif [[ -f "$PRE/qhexrt-prebuilt.json" ]]; then
      copy_one "$PRE/qhexrt-prebuilt.json" "$stage/share/runanywhere/private/RECEIPT.json"
    else
      echo "QHexRT receipt missing under $PRE" >&2
      exit 1
    fi
    qairt="$ROOT/engines/qhexrt/prebuilt/qairt-runtime/win-arm64/current"
    if [[ ! -d "$qairt" ]]; then
      echo "QAIRT runtime missing at $qairt — run download-qairt-runtime.sh --platform win-arm64" >&2
      exit 1
    fi
    find "$qairt" -type f \( -name '*.dll' -o -name '*.lib' \) -exec cp {} "$stage/bin/" \;
    shopt -s nullglob
    dlls=("$stage/bin"/*.dll)
    shopt -u nullglob
    if [[ ${#dlls[@]} -eq 0 ]]; then
      echo "QAIRT runtime at $qairt produced no DLLs; refusing a stub overlay" >&2
      exit 1
    fi
    printf 'qhexrt\n' > "$stage/share/runanywhere/private/ENGINE"
    OS_ARCH="windows-arm64"
    ;;
  *)
    echo "engine must be neurt or qhexrt" >&2
    exit 2
    ;;
esac

# Fail closed: the overlay must never look like the non-routable shell.
if grep -RqiE 'non-routable shell|BACKEND_UNAVAILABLE stub' "$stage/lib" 2>/dev/null; then
  echo "overlay looks like a stub; refusing to package" >&2
  exit 1
fi

mkdir -p "$ROOT/dist"
if [[ -z "$OUT" ]]; then
  OUT="$ROOT/dist/RunAnywhere-cpp-desktop-${OS_ARCH}-${ENGINE}-private-v${VERSION}.tar.gz"
fi
tar -C "$stage" -czf "$OUT" lib bin share
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$OUT" | tee "${OUT}.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT" | tee "${OUT}.sha256"
fi
echo "private overlay: $OUT"
ls -la "$stage/lib" "$stage/bin"
