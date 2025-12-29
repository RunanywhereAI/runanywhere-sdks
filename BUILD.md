# RunAnywhere SDK Build System

This document describes how to build the RunAnywhere SDK locally and how the release/publishing system works.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Build Pipeline                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  runanywhere-core/          runanywhere-commons/                │
│  ├── src/                   ├── src/                            │
│  │   └── backends/          │   ├── core/                       │
│  │       ├── llamacpp/      │   ├── features/                   │
│  │       └── onnx/          │   └── backends/                   │
│  └── third_party/           │       ├── llamacpp/               │
│      └── sherpa-onnx/       │       └── onnx/                   │
│                             └── scripts/                        │
│                                 └── build-ios.sh                │
│                                                                  │
│                         ↓ Builds ↓                               │
│                                                                  │
│  runanywhere-commons/dist/                                       │
│  ├── RACommons.xcframework                                       │
│  ├── RABackendLlamaCPP.xcframework                              │
│  └── RABackendONNX.xcframework                                  │
│                                                                  │
│                    ↓ Copy/Publish ↓                              │
│                                                                  │
│  ┌──────────────────┐         ┌─────────────────────┐          │
│  │ LOCAL MODE       │         │ REMOTE MODE         │          │
│  │                  │         │                     │          │
│  │ runanywhere-     │         │ runanywhere-        │          │
│  │ swift/Binaries/  │         │ binaries/releases/  │          │
│  │ *.xcframework    │         │ *.xcframework.zip   │          │
│  └──────────────────┘         └─────────────────────┘          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Two Build Modes

### 1. Local Mode (Development)

For active development, build everything locally:

```bash
# Full build: core + commons + copy to Swift SDK
./sdks/scripts/build-local.sh

# Build commons only (assumes core hasn't changed)
./sdks/scripts/build-local.sh --commons

# Copy frameworks only (no rebuild)
./sdks/scripts/build-local.sh --copy

# Full build + rebuild iOS sample app
./sdks/scripts/build-local.sh --ios-app

# Clean build
./sdks/scripts/build-local.sh --clean
```

**Package.swift Configuration:**
```swift
// Set to true for local development
let testLocal = true
```

### 2. Remote Mode (Production)

For production releases, download pre-built binaries from GitHub:

**Package.swift Configuration:**
```swift
// Set to false for production (downloads from releases)
let testLocal = false
```

## Quick Start

### Local Development

```bash
# 1. Build everything locally
cd runanywhere-all
./sdks/scripts/build-local.sh

# 2. Ensure Package.swift has testLocal = true
# (Edit sdks/sdk/runanywhere-swift/Package.swift)

# 3. Open iOS sample app in Xcode
open sdks/examples/ios/RunAnywhereAI/RunAnywhereAI.xcodeproj

# 4. Build and run on your device
```

### Publishing a Release

```bash
# 1. Build and test locally first
./sdks/scripts/build-local.sh --ios-app

# 2. Tag a new version
git tag v3.0.0
git push origin v3.0.0

# 3. GitHub Actions will automatically:
#    - Build iOS XCFrameworks
#    - Build Android libraries
#    - Publish to runanywhere-binaries releases

# 4. Update Package.swift with new checksums
./sdks/scripts/update-package-checksums.sh v3.0.0

# 5. Commit and push
git add sdks/sdk/runanywhere-swift/Package.swift
git commit -m "Update binaries to v3.0.0"
git push
```

## Build Scripts

| Script | Description |
|--------|-------------|
| `sdks/scripts/build-local.sh` | One-command local build |
| `sdks/scripts/update-package-checksums.sh` | Update Package.swift with release checksums |
| `sdks/sdk/runanywhere-commons/scripts/build-ios.sh` | Build iOS XCFrameworks |
| `sdks/sdk/runanywhere-commons/scripts/build-android.sh` | Build Android libraries |
| `sdks/sdk/runanywhere-commons/scripts/package-release.sh` | Package for release |

## Framework Output

After building, frameworks are in `sdks/sdk/runanywhere-commons/dist/`:

| Framework | Size | Description |
|-----------|------|-------------|
| `RACommons.xcframework` | ~3MB | Core commons library |
| `RABackendLlamaCPP.xcframework` | ~32MB | LlamaCPP backend (includes llama.cpp) |
| `RABackendONNX.xcframework` | ~47MB | ONNX backend (includes Sherpa-ONNX) |

## CI/CD Workflow

The GitHub Actions workflow (`.github/workflows/publish-binaries.yml`) handles:

1. **Build iOS**: Builds XCFrameworks on macOS runner
2. **Build Android**: Builds .so libraries on Ubuntu runner
3. **Publish**: Uploads artifacts to runanywhere-binaries releases

### Required Secrets

- `BINARIES_REPO_TOKEN`: GitHub token with write access to runanywhere-binaries

## Troubleshooting

### Build fails with "Sherpa-ONNX not found"
```bash
cd runanywhere-core/third_party
./download-sherpa-onnx.sh ios
```

### Xcode can't find frameworks
```bash
# Ensure frameworks are copied
ls sdks/sdk/runanywhere-swift/Binaries/

# Should show:
# RACommons.xcframework
# RABackendLlamaCPP.xcframework
# RABackendONNX.xcframework
# onnxruntime.xcframework
```

### Clean rebuild
```bash
./sdks/scripts/build-local.sh --clean --ios-app
```

### Package resolution fails
```bash
# Clear SPM cache
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData/RunAnywhereAI-*
```
