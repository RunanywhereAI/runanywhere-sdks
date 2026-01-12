# Android Support Scripts

Support scripts for Android. The main build is handled by `../build-android.sh`.

## Scripts

| Script | Purpose |
|--------|---------|
| `download-sherpa-onnx.sh` | Download Sherpa-ONNX .so files |
| `generate-maven-package.sh` | Generate versions.json for releases |

## Quick Start

**Recommended:** Use the main build script which handles everything:

```bash
cd runanywhere-commons
./scripts/build-android.sh
```

## Manual Dependency Download

```bash
# Download Sherpa-ONNX (for ONNX backend)
./download-sherpa-onnx.sh
```

## Output Locations

```
runanywhere-commons/
└── third_party/
    └── sherpa-onnx-android/
        └── jniLibs/
            └── arm64-v8a/
                ├── libonnxruntime.so
                └── libsherpa-onnx-*.so
```

## Generate Release Manifest

```bash
# After building, generate versions.json
./generate-maven-package.sh 1.0.0 ../../dist/android/packages
```

## Versions

Versions are defined in `VERSIONS` file at repo root:

```bash
SHERPA_ONNX_VERSION_ANDROID=1.10.32
ANDROID_MIN_SDK=24
```
