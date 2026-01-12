# iOS Dependency Scripts

Download scripts for iOS dependencies. The main build is handled by `../build-ios.sh`.

## Scripts

| Script | Purpose |
|--------|---------|
| `download-onnx.sh` | Download ONNX Runtime xcframework |
| `download-sherpa-onnx.sh` | Download Sherpa-ONNX xcframework |

## Quick Start

**Recommended:** Use the main build script which handles everything:

```bash
cd runanywhere-commons
./scripts/build-ios.sh
```

## Manual Dependency Download

```bash
# Download ONNX Runtime (required for ONNX backend)
./download-onnx.sh

# Download Sherpa-ONNX (required for STT/TTS/VAD)
./download-sherpa-onnx.sh
```

## Output Locations

```
runanywhere-commons/
└── third_party/
    ├── onnxruntime-ios/
    │   └── onnxruntime.xcframework
    └── sherpa-onnx-ios/
        └── sherpa-onnx.xcframework
```

## Versions

Versions are defined in `VERSIONS` file at repo root:

```bash
ONNX_VERSION_IOS=1.16.3
SHERPA_ONNX_VERSION_IOS=1.10.32
```
