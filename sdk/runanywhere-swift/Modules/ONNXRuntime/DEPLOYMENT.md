# ONNXRuntime Module Deployment

This document explains how to deploy the `RunAnywhereONNX.xcframework` binary to this module.

## Overview

The `RunAnywhereONNX.xcframework` is a **235MB static library** that must be built from the `runanywhere-core` repository and manually copied here. It is **excluded from git** to avoid bloating the repository.

## Quick Start

### 1. Build the XCFramework

In the `runanywhere-core` repository:

```bash
cd /path/to/runanywhere-core
./scripts/build-ios-onnx.sh
```

This will create: `dist/RunAnywhereONNX.xcframework/`

### 2. Copy to This Module

From the `runanywhere-core` directory:

```bash
# Absolute path
cp -r dist/RunAnywhereONNX.xcframework \
  /path/to/runanywhere-swift/Modules/ONNXRuntime/Sources/

# Or relative path (if repos are in same parent directory)
cp -r dist/RunAnywhereONNX.xcframework \
  ../sdks/sdk/runanywhere-swift/Modules/ONNXRuntime/Sources/
```

### 3. Verify Deployment

Check that the XCFramework is in place:

```bash
ls -lh Modules/ONNXRuntime/Sources/RunAnywhereONNX.xcframework/
```

You should see:
```
Info.plist
ios-arm64/
ios-arm64_x86_64-simulator/
```

## Directory Structure

```
Modules/ONNXRuntime/
├── Package.swift                      # Swift Package manifest
├── DEPLOYMENT.md                      # This file
├── README.md                          # Module documentation
└── Sources/
    ├── ONNXRuntime/                   # Swift source code
    │   ├── ONNXSTTService.swift
    │   ├── ONNXAdapter.swift
    │   ├── ONNXServiceProvider.swift
    │   ├── ONNXDownloadStrategy.swift
    │   └── ONNXError.swift
    ├── CRunAnywhereONNX/              # C bridge headers
    │   ├── dummy.c
    │   └── include/
    │       ├── onnx_bridge.h
    │       ├── modality_types.h
    │       └── module.modulemap
    └── RunAnywhereONNX.xcframework/   # 👈 Binary (gitignored, must be copied)
        ├── Info.plist
        ├── ios-arm64/
        │   ├── Headers/
        │   │   ├── onnx_bridge.h
        │   │   ├── modality_types.h
        │   │   └── types.h
        │   └── librunanywhere_onnx_combined.a
        └── ios-arm64_x86_64-simulator/
            ├── Headers/
            └── librunanywhere_onnx_combined.a
```

## Git Configuration

The XCFramework is excluded from git via `.gitignore`:

```gitignore
# In runanywhere-swift/.gitignore:
*.xcframework/
Modules/ONNXRuntime/Sources/RunAnywhereONNX.xcframework/
```

This means:
- ✅ Swift source code IS committed
- ✅ C bridge headers ARE committed
- ❌ XCFramework binary is NOT committed (too large)

## Updating the XCFramework

When you need to update the binary (e.g., after changes to C++ code):

1. **Rebuild in runanywhere-core**:
   ```bash
   cd /path/to/runanywhere-core
   ./scripts/build-ios-onnx.sh
   ```

2. **Remove old binary** (if exists):
   ```bash
   rm -rf /path/to/runanywhere-swift/Modules/ONNXRuntime/Sources/RunAnywhereONNX.xcframework
   ```

3. **Copy new binary**:
   ```bash
   cp -r dist/RunAnywhereONNX.xcframework \
     /path/to/runanywhere-swift/Modules/ONNXRuntime/Sources/
   ```

4. **Clear Xcode caches**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   rm -rf ~/Library/Caches/org.swift.swiftpm
   ```

5. **Rebuild iOS app**:
   ```bash
   cd /path/to/ios/app
   xcodebuild clean -workspace RunAnywhereAI.xcworkspace -scheme RunAnywhereAI
   xcodebuild build -workspace RunAnywhereAI.xcworkspace -scheme RunAnywhereAI \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
   ```

## Troubleshooting

### Error: XCFramework not found

**Symptom**: Build fails with "module 'RunAnywhereONNX' not found"

**Solution**: The XCFramework hasn't been copied yet. Follow steps 1-2 above.

### Error: Undefined symbols from ONNX Runtime

**Symptom**: Linker errors about missing ONNX symbols

**Solution**: XCFramework is outdated. Rebuild and recopy (steps 1-3 above).

### Error: Module signature mismatch

**Symptom**: "Module compiled with Swift X.Y but loaded with Swift X.Z"

**Solution**:
1. Rebuild XCFramework with current Xcode version
2. Clear all caches (step 4 above)
3. Rebuild app

### Binary not being used after update

**Symptom**: Changes in C++ code not reflected in app

**Solution**:
1. Verify XCFramework was copied correctly
2. Check modification timestamp:
   ```bash
   stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" \
     Modules/ONNXRuntime/Sources/RunAnywhereONNX.xcframework/ios-arm64/librunanywhere_onnx_combined.a
   ```
3. Clear all caches thoroughly (step 4 above)
4. Clean rebuild (step 5 above)

## CI/CD Considerations

For continuous integration, you have two options:

### Option 1: Build as part of CI
```yaml
steps:
  - name: Build XCFramework
    run: |
      cd runanywhere-core
      ./scripts/build-ios-onnx.sh
      cp -r dist/RunAnywhereONNX.xcframework ../sdks/sdk/runanywhere-swift/Modules/ONNXRuntime/Sources/

  - name: Build iOS App
    run: |
      cd sdks/examples/ios/RunAnywhereAI
      xcodebuild build ...
```

### Option 2: Use pre-built binary from release
```yaml
steps:
  - name: Download XCFramework
    run: |
      wget https://github.com/.../releases/.../RunAnywhereONNX.xcframework.zip
      unzip RunAnywhereONNX.xcframework.zip -d sdks/sdk/runanywhere-swift/Modules/ONNXRuntime/Sources/

  - name: Build iOS App
    run: |
      cd sdks/examples/ios/RunAnywhereAI
      xcodebuild build ...
```

## Future: SPM Binary Target

Currently using manual copy. Future plan is to distribute via SPM binary targets:

```swift
// Future Package.swift
.binaryTarget(
    name: "RunAnywhereONNX",
    url: "https://github.com/runanywhere/releases/download/v1.0.0/RunAnywhereONNX.xcframework.zip",
    checksum: "abc123..."
)
```

This would eliminate the need for manual copying.

## Related Documentation

- **Build Guide**: See `runanywhere-core/docs/building-xcframework-ios.md`
- **Sherpa-ONNX Integration**: See `runanywhere-core/docs/sherpa-onnx-integration.md`
- **Module Architecture**: See `README.md` in this directory

## Support

For deployment issues:
1. Check troubleshooting section above
2. Verify build script output for errors
3. Check git status to ensure XCFramework is properly gitignored
4. Open an issue on GitHub with build logs
