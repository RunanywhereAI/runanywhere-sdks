# RunAnywhere Commons - Build Scripts

Build scripts for iOS (xcframeworks) and Android (.so files).

## Quick Start

### iOS Build

```bash
# Build everything (RACommons + all backends)
./scripts/build-ios.sh

# Options
./scripts/build-ios.sh --clean              # Clean build first
./scripts/build-ios.sh --skip-download      # Use cached dependencies
./scripts/build-ios.sh --backend llamacpp   # Build only LlamaCPP backend
./scripts/build-ios.sh --package            # Create release ZIPs
```

**Output:**

```text
dist/
├── RACommons.xcframework           # Core infrastructure
├── RABackendLLAMACPP.xcframework   # LLM text generation
└── RABackendONNX.xcframework       # STT/TTS/VAD (Sherpa-ONNX)
```

### Android Build

```bash
# Build everything
./scripts/build-android.sh

# Options
./scripts/build-android.sh llamacpp         # Only LlamaCPP backend
./scripts/build-android.sh onnx arm64-v8a   # ONNX for arm64 only
./scripts/build-android.sh --check          # Verify 16KB alignment
```

**Output:**

```text
dist/android/
├── jni/arm64-v8a/              # JNI bridge
├── onnx/arm64-v8a/             # ONNX backend + runtime
├── llamacpp/arm64-v8a/         # LlamaCPP backend
└── packages/                   # Release ZIPs
```

## Directory Structure

```text
scripts/
├── build-ios.sh              # iOS entry point
├── build-android.sh          # Android entry point
├── load-versions.sh          # Loads versions from VERSIONS file
├── ios/
│   ├── download-onnx.sh      # Download ONNX Runtime xcframework
│   └── download-sherpa-onnx.sh
└── android/
    └── download-sherpa-onnx.sh
```

## Version Management

All versions are centralized in `VERSIONS` file at the repo root. Scripts load versions via `source scripts/load-versions.sh`.
