#!/bin/bash
set -e

echo "=========================================="
echo "Rebuilding Android with NDK 26.3.11579264"
echo "=========================================="
echo ""

# Set NDK 26 environment
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/26.3.11579264
export ANDROID_NDK=$ANDROID_NDK_HOME
export NDK_ROOT=$ANDROID_NDK_HOME

echo "✓ NDK set to: $ANDROID_NDK_HOME"
echo ""

# Verify NDK exists
if [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "❌ ERROR: NDK 26.3.11579264 not found at $ANDROID_NDK_HOME"
    exit 1
fi

echo "Step 1: Clean build directories"
echo "--------------------------------"
cd sdk/runanywhere-commons
rm -rf build-android
echo "✓ Cleaned build-android/"
echo ""

echo "Step 2: Rebuild ONNX+RAG+LlamaCPP backends with NDK 26"
echo "------------------------------------------------------"
if ./scripts/build-android.sh all arm64-v8a; then
    echo "✓ Native libraries rebuilt"
else
    echo "❌ Build failed!"
    exit 1
fi
echo ""

echo "Step 3: Copy libraries to React Native packages"
echo "------------------------------------------------"
cd ../runanywhere-react-native/packages

DIST_ONNX=../../runanywhere-commons/dist/android/onnx/arm64-v8a
DIST_RAG=../../runanywhere-commons/dist/android/rag/arm64-v8a
DIST_LLAMACPP=../../runanywhere-commons/dist/android/llamacpp/arm64-v8a

if [ ! -d "$DIST_ONNX" ] || [ ! -d "$DIST_RAG" ] || [ ! -d "$DIST_LLAMACPP" ]; then
    echo "❌ ERROR: dist output not found. Expected:"
    echo "  $DIST_ONNX"
    echo "  $DIST_RAG"
    echo "  $DIST_LLAMACPP"
    exit 1
fi

PKG_ONNX=onnx/android/src/main/jniLibs/arm64-v8a
PKG_RAG=rag/android/src/main/jniLibs/arm64-v8a
PKG_LLAMACPP=llamacpp/android/src/main/jniLibs/arm64-v8a

RN_NODE_MODULES=../../../examples/react-native/RunAnywhereAI/node_modules/@runanywhere
RN_ONNX=$RN_NODE_MODULES/onnx/android/src/main/jniLibs/arm64-v8a
RN_RAG=$RN_NODE_MODULES/rag/android/src/main/jniLibs/arm64-v8a
RN_LLAMACPP=$RN_NODE_MODULES/llamacpp/android/src/main/jniLibs/arm64-v8a

mkdir -p "$PKG_ONNX" "$PKG_RAG" "$PKG_LLAMACPP" "$RN_ONNX" "$RN_RAG" "$RN_LLAMACPP"

copy_if_exists() {
    local src="$1"
    local dest="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dest/"
        echo "✓ Copied $(basename "$src") -> $dest"
    else
        echo "⚠️  Missing: $src"
    fi
}

# ONNX package + RN node_modules
copy_if_exists "$DIST_ONNX/libonnxruntime.so" "$PKG_ONNX"
copy_if_exists "$DIST_ONNX/librac_backend_onnx.so" "$PKG_ONNX"
copy_if_exists "$DIST_ONNX/librac_backend_onnx_jni.so" "$PKG_ONNX"
copy_if_exists "$DIST_ONNX/librac_commons.so" "$PKG_ONNX"
copy_if_exists "$DIST_ONNX/libsherpa-onnx-c-api.so" "$PKG_ONNX"
copy_if_exists "$DIST_ONNX/libsherpa-onnx-cxx-api.so" "$PKG_ONNX"
copy_if_exists "$DIST_ONNX/libsherpa-onnx-jni.so" "$PKG_ONNX"

copy_if_exists "$DIST_ONNX/libonnxruntime.so" "$RN_ONNX"
copy_if_exists "$DIST_ONNX/librac_backend_onnx.so" "$RN_ONNX"
copy_if_exists "$DIST_ONNX/librac_backend_onnx_jni.so" "$RN_ONNX"
copy_if_exists "$DIST_ONNX/librac_commons.so" "$RN_ONNX"
copy_if_exists "$DIST_ONNX/libsherpa-onnx-c-api.so" "$RN_ONNX"
copy_if_exists "$DIST_ONNX/libsherpa-onnx-cxx-api.so" "$RN_ONNX"
copy_if_exists "$DIST_ONNX/libsherpa-onnx-jni.so" "$RN_ONNX"

# RAG package + RN node_modules
copy_if_exists "$DIST_RAG/librac_backend_rag.so" "$PKG_RAG"
copy_if_exists "$DIST_ONNX/librac_backend_onnx.so" "$PKG_RAG"
copy_if_exists "$DIST_ONNX/librac_backend_onnx_jni.so" "$PKG_RAG"
copy_if_exists "$DIST_ONNX/libonnxruntime.so" "$PKG_RAG"

copy_if_exists "$DIST_RAG/librac_backend_rag.so" "$RN_RAG"
copy_if_exists "$DIST_ONNX/librac_backend_onnx.so" "$RN_RAG"
copy_if_exists "$DIST_ONNX/librac_backend_onnx_jni.so" "$RN_RAG"
copy_if_exists "$DIST_ONNX/libonnxruntime.so" "$RN_RAG"

# LlamaCPP package + RN node_modules
copy_if_exists "$DIST_LLAMACPP/librac_backend_llamacpp.so" "$PKG_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/librac_backend_llamacpp_jni.so" "$PKG_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/librac_commons.so" "$PKG_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/libc++_shared.so" "$PKG_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/libomp.so" "$PKG_LLAMACPP"

copy_if_exists "$DIST_LLAMACPP/librac_backend_llamacpp.so" "$RN_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/librac_backend_llamacpp_jni.so" "$RN_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/librac_commons.so" "$RN_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/libc++_shared.so" "$RN_LLAMACPP"
copy_if_exists "$DIST_LLAMACPP/libomp.so" "$RN_LLAMACPP"

echo ""

echo "Step 4: Rebuild React Native Android APK"
echo "-----------------------------------------"
cd ../../../examples/react-native/RunAnywhereAI/android

# Clean build cache
rm -rf app/build/.cxx app/.cxx
rm -rf .gradle/*/
echo "✓ Cleaned build cache"

# Ensure local.properties has SDK (avoid ndk.dir to prevent version mismatches)
cat > local.properties << EOF
sdk.dir=$HOME/Library/Android/sdk
EOF
echo "✓ Updated local.properties (sdk.dir only)"

# Build APK
echo ""
echo "Building APK with NDK 26..."
./gradlew :app:assembleRelease

echo ""
echo "=========================================="
echo "✅ Build complete!"
echo "=========================================="
echo ""
echo "APK location:"
ls -lh app/build/outputs/apk/release/app-release.apk
echo ""
echo "Next steps:"
echo "1. adb install -r app/build/outputs/apk/release/app-release.apk"
echo "2. Test RAG initialization in the app"
echo ""
