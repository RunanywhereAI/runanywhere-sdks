#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-react-native/scripts/package-sdk.sh
# =============================================================================
# Unified SDK packaging contract for the React Native SDK. Consumes pre-built
# iOS XCFrameworks + Android .so files, stages each native binary only into the
# RN package that owns it, and produces npm tarballs with checksums.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory with iOS xcframeworks + Android .so files.
#                        iOS uses the Swift-shaped binary names:
#                        core=RACommons, llamacpp=RABackendLLAMACPP,
#                        onnx=RABackendONNX+RABackendSherpa.
#
# OUTPUTS:
#   dist/sdk-rn/*.tgz     + .sha256    (one per npm workspace)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/setup/detect-mode.sh"

NATIVES_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --help|-h) head -20 "$0" | tail -16; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

echo ">> React Native SDK packaging (mode=${RAC_BUILD_MODE})"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || { echo "ERROR: --natives-from not found: $NATIVES_FROM" >&2; exit 1; }
    echo ">> Staging natives from $NATIVES_FROM with explicit package ownership"

    stage_ios() {
        local pkg_dir="$1"
        shift
        local ios_bin="$pkg_dir/ios/Binaries"
        rm -rf "$ios_bin" "$pkg_dir/ios/Frameworks"
        mkdir -p "$ios_bin"
        for framework in "$@"; do
            local src="$NATIVES_FROM/${framework}.xcframework"
            if [ -d "$src" ]; then
                cp -R "$src" "$ios_bin/"
            else
                echo "::warning::missing iOS framework for $(basename "$pkg_dir"): ${framework}.xcframework"
            fi
        done
    }

    stage_android() {
        local pkg_dir="$1"
        shift
        local android_jni="$pkg_dir/android/src/main/jniLibs"
        rm -rf "$android_jni"
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            if [ -d "$NATIVES_FROM/$abi" ]; then
                mkdir -p "$android_jni/$abi"
                for lib in "$@"; do
                    if [ -f "$NATIVES_FROM/$abi/$lib" ]; then
                        cp -f "$NATIVES_FROM/$abi/$lib" "$android_jni/$abi/"
                    fi
                done
            fi
        done
    }

    if ls "$NATIVES_FROM"/*.xcframework >/dev/null 2>&1; then
        stage_ios "$RN_ROOT/packages/core" RACommons
        stage_ios "$RN_ROOT/packages/llamacpp" RABackendLLAMACPP
        stage_ios "$RN_ROOT/packages/onnx" RABackendONNX RABackendSherpa
    fi

    if find "$NATIVES_FROM" -maxdepth 1 -type d \( -name "arm64-v8a" -o -name "armeabi-v7a" -o -name "x86_64" -o -name "x86" \) -print -quit | grep -q .; then
        stage_android "$RN_ROOT/packages/core" \
            librac_commons.so librunanywhere_jni.so libomp.so libc++_shared.so
        stage_android "$RN_ROOT/packages/llamacpp" \
            librac_backend_llamacpp.so librac_backend_llamacpp_jni.so libc++_shared.so
        stage_android "$RN_ROOT/packages/onnx" \
            librac_backend_onnx.so librac_backend_onnx_jni.so librac_backend_sherpa.so \
            libonnxruntime.so libsherpa-onnx-c-api.so libsherpa-onnx-cxx-api.so \
            libsherpa-onnx-jni.so libc++_shared.so
        # QHexRT (Qualcomm Hexagon NPU) is private + arm64-only: the backend .so
        # plus the QAIRT runtime/skel set (libQnn*) are bundled directly in the
        # package, not fetched from a public release. They are copied only when
        # present in --natives-from (otherwise silently skipped by stage_android).
        stage_android "$RN_ROOT/packages/qhexrt" \
            librac_backend_qhexrt.so libc++_shared.so \
            libQnnHtp.so libQnnHtpNetRunExtensions.so libQnnHtpPrepare.so libQnnSystem.so \
            libQnnHtpV75CalculatorStub.so libQnnHtpV75Skel.so libQnnHtpV75Stub.so \
            libQnnHtpV79CalculatorStub.so libQnnHtpV79Skel.so libQnnHtpV79Stub.so \
            libQnnHtpV81CalculatorStub.so libQnnHtpV81Skel.so libQnnHtpV81Stub.so
    fi
fi

cd "$RN_ROOT"

# The RN SDK declares `packageManager: "yarn@3.6.1"` and is a workspace under
# the repo-root yarn.lock. Enable Corepack and run yarn install from the repo
# root so the committed workspace lock is honoured; fall back to npm only as
# an explicit escape hatch when Yarn/Corepack are genuinely unavailable.
WANTS_YARN=0
if grep -q '"packageManager": "yarn@' package.json 2>/dev/null; then
    WANTS_YARN=1
fi

if [ -f "yarn.lock" ] || [ -f "${REPO_ROOT}/yarn.lock" ] || [ "$WANTS_YARN" = "1" ]; then
    if command -v corepack >/dev/null 2>&1; then
        corepack enable >/dev/null 2>&1 || true
    fi
fi

YARN_CWD=""
if [ -f "yarn.lock" ]; then
    YARN_CWD="$RN_ROOT"
elif [ -f "${REPO_ROOT}/yarn.lock" ]; then
    YARN_CWD="$REPO_ROOT"
fi

if [ -n "$YARN_CWD" ] && command -v yarn >/dev/null 2>&1; then
    echo ">> yarn install (cwd=$YARN_CWD)"
    (cd "$YARN_CWD" && (yarn install --immutable 2>/dev/null || yarn install))
    HAS_YARN=1
elif [ "${RAC_ALLOW_NPM_FALLBACK:-0}" = "1" ]; then
    # RELEASE REPRODUCIBILITY TRADEOFF (see pass3-syn-079):
    # RAC_ALLOW_NPM_FALLBACK=1 lets the release packager fall back to
    # `npm install` when Yarn Berry / Corepack are unavailable. This is
    # intentionally an explicit opt-in because:
    #   - Yarn Berry resolves @runanywhere/proto-ts via the workspace:*
    #     protocol against the repo-root yarn.lock; npm install does not
    #     honour the yarn-locked workspace pins and instead resolves
    #     `react-native-nitro-modules` (and other transitive peers) from
    #     the npm registry at packaging time.
    #   - A release .tgz built via npm fallback may therefore ship with
    #     a different nitro-modules ABI than the workspace's yarn.lock
    #     was tested against, surfacing as HybridObject ABI mismatches
    #     at consumer runtime.
    # The sentinel log line below is intentionally distinctive so release
    # publish gates / manifest assertions can grep for it (e.g.
    # `grep -q RAC_ALLOW_NPM_FALLBACK_USED=true` over the job log) and
    # refuse to ship a release when the npm fallback path was taken.
    echo ">> npm install --legacy-peer-deps (RAC_ALLOW_NPM_FALLBACK=1)"
    echo "::warning::RAC_ALLOW_NPM_FALLBACK_USED=true — release reproducibility weakened (npm-resolved deps instead of yarn workspace lock)"
    npm install --legacy-peer-deps
    HAS_YARN=0
else
    echo "ERROR: Yarn workspace install required but yarn/corepack is unavailable." >&2
    echo "       Install Node 18+ with Corepack (or 'npm i -g corepack') so 'yarn@3.6.1'" >&2
    echo "       can be activated, or set RAC_ALLOW_NPM_FALLBACK=1 to opt into the" >&2
    echo "       legacy npm install path explicitly (NOT recommended for release builds — see comment above)." >&2
    exit 1
fi

# Generate Nitro bindings if nitrogen is wired up
if [ "$HAS_YARN" = "1" ] && yarn run 2>/dev/null | grep -q "nitrogen"; then
    echo ">> yarn core:nitrogen (if defined)"
    yarn core:nitrogen 2>/dev/null || echo "::warning::nitrogen task failed — continuing"
fi

# Typecheck each package
for pkg_dir in "$RN_ROOT/packages"/*/; do
    pkg=$(basename "$pkg_dir")
    if [ -f "$pkg_dir/tsconfig.json" ]; then
        echo ">> typecheck $pkg"
        (cd "$pkg_dir" && npx tsc --noEmit) || echo "::warning::tsc failed in $pkg"
    fi
done

DIST_DIR="${RN_ROOT}/dist/sdk-rn"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for pkg_dir in "$RN_ROOT/packages"/*/; do
    pkg=$(basename "$pkg_dir")
    if [ -f "$pkg_dir/package.json" ]; then
        echo ">> npm pack $pkg"
        (cd "$pkg_dir" && npm pack --pack-destination "$DIST_DIR" >/dev/null) || echo "::warning::npm pack failed for $pkg"
    fi
done

echo ""
echo ">> Artifacts in $DIST_DIR:"
for f in "$DIST_DIR"/*.tgz; do
    [ -f "$f" ] || continue
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" > "$f.sha256"
    else
        sha256sum "$f" > "$f.sha256"
    fi
    echo "  $(basename "$f")"
done

if [ -x "${REPO_ROOT}/scripts/release/validate-artifact.sh" ]; then
    echo ""
    if [ "$RAC_BUILD_MODE" = "ci" ]; then
        "${REPO_ROOT}/scripts/release/validate-artifact.sh" "$DIST_DIR"/*.tgz 2>/dev/null
    else
        "${REPO_ROOT}/scripts/release/validate-artifact.sh" "$DIST_DIR"/*.tgz 2>/dev/null || true
    fi
fi
