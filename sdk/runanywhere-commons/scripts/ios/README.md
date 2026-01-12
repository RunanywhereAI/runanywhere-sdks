# iOS Build Scripts

Scripts for building RunAnywhere Core as XCFrameworks for iOS.

## Quick Start

```bash
# Download dependencies first
./download-onnx.sh
./download-sherpa-onnx.sh  # Optional, for STT/TTS

# Build unified xcframework with all backends (recommended)
./build.sh --all

# Build specific backend only
./build.sh --onnx
./build.sh --llamacpp
```

## Scripts

| Script | Purpose |
|--------|---------|
| `build.sh` | Build unified XCFramework with selected backends |
| `download-onnx.sh` | Download ONNX Runtime for iOS |
| `download-sherpa-onnx.sh` | Download Sherpa-ONNX for streaming STT/TTS |
| `build-sherpa-onnx.sh` | Build Sherpa-ONNX from source (if download fails) |
| `generate-spm-package.sh` | Generate Swift Package Manager package |

## build.sh

Builds a unified `RunAnywhereCore.xcframework` containing selected backends in a single static library.

### Usage

```bash
./build.sh [OPTIONS]

Options:
  --onnx        Include ONNX Runtime backend
  --llamacpp    Include LlamaCPP backend
  --all         Include all backends (default)
```

### Examples

```bash
# Build with all backends (default)
./build.sh
./build.sh --all

# Build with ONNX only (for STT, TTS, VAD, Embeddings)
./build.sh --onnx

# Build with LlamaCPP only (for Text Generation with Metal GPU)
./build.sh --llamacpp

# Build with specific backends
./build.sh --onnx --llamacpp
```

### Output

```
dist/RunAnywhereCore.xcframework/
├── Info.plist
├── ios-arm64/                          # Device (arm64)
│   ├── libRunAnywhereCore.a
│   └── Headers/
│       ├── module.modulemap
│       └── RunAnywhereCore/
│           ├── ra_core.h               # Umbrella header
│           ├── ra_types.h              # Shared types
│           ├── ra_onnx_bridge.h        # ONNX API (if included)
│           └── ra_llamacpp_bridge.h    # LlamaCPP API (if included)
└── ios-arm64_x86_64-simulator/         # Simulator (arm64 + x86_64)
    └── [same structure]
```

### Size Reference

| Configuration | Device | Simulator | Total |
|---------------|--------|-----------|-------|
| ONNX only | ~78 MB | ~157 MB | ~235 MB |
| LlamaCPP only | ~3.7 MB | ~7 MB | ~11 MB |
| All backends | ~81 MB | ~164 MB | ~246 MB |

## Prerequisites

1. **Xcode** with command line tools
   ```bash
   xcode-select --install
   ```

2. **CMake** (3.22+)
   ```bash
   brew install cmake
   ```

3. **ONNX Runtime** (for ONNX backend)
   ```bash
   ./download-onnx.sh
   ```

4. **Sherpa-ONNX** (optional, for streaming STT/TTS)
   ```bash
   ./download-sherpa-onnx.sh
   ```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IOS_DEPLOYMENT_TARGET` | 14.0 | Minimum iOS version |

## Linking in Your App

Add these frameworks to your Xcode project:

**Required:**
- `Foundation.framework`
- `Accelerate.framework`

**For ONNX backend:**
- `CoreML.framework`

**For LlamaCPP backend:**
- `Metal.framework`
- `MetalKit.framework`

## Swift Usage

```swift
import RunAnywhereCore

// Initialize backend
let handle = ra_create_backend("llamacpp")
ra_initialize(handle, nil)

// Load model
ra_text_load_model(handle, modelPath, nil)

// Generate text
var result = ra_text_result()
ra_text_generate(handle, prompt, &result)
print(String(cString: result.text))
ra_free_text_result(&result)

// Cleanup
ra_destroy(handle)
```

## Troubleshooting

### "Module not found" error
Ensure the xcframework is added to your target's "Frameworks, Libraries, and Embedded Content".

### Simulator build fails
Make sure you have the iOS simulator SDK installed via Xcode.

### Large binary size
Use `--llamacpp` only if you don't need ONNX features. LlamaCPP is ~30x smaller.
