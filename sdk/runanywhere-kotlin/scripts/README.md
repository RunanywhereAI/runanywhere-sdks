# RunAnywhere Kotlin SDK - Scripts

Build and management scripts for the Kotlin SDK.

## Scripts

| Script | Purpose |
|--------|---------|
| `build-kotlin.sh` | **Main build script** - handles setup, build, and mode switching |
| `build-local.sh` | Low-level script to distribute JNI libs to module directories |
| `sdk.sh` | Comprehensive SDK management (build, test, publish, etc.) |

## Quick Start

### First-Time Local Development Setup

```bash
# From sdk/runanywhere-kotlin/
./scripts/build-kotlin.sh --setup
```

This will:
1. Download dependencies (Sherpa-ONNX for Android)
2. Build runanywhere-commons for Android
3. Copy JNI libraries to module directories
4. Set `testLocal=true` in gradle.properties

**Time:** ~10-15 minutes on first run

### After Making C++ Changes

```bash
# Rebuild commons and copy new libraries
./scripts/build-kotlin.sh --local --rebuild-commons
```

### Switch Between Local and Remote

```bash
# Use locally built libraries
./scripts/build-kotlin.sh --local --skip-build

# Use GitHub releases
./scripts/build-kotlin.sh --remote --skip-build
```

## build-kotlin.sh Options

```
./scripts/build-kotlin.sh [options]

OPTIONS:
  --setup             First-time setup: download deps, build commons, copy libs
  --local             Use locally built libs (sets testLocal=true)
  --remote            Use remote libs from GitHub releases (sets testLocal=false)
  --rebuild-commons   Force rebuild of runanywhere-commons (even if cached)
  --clean             Clean build directories before building
  --skip-build        Skip Gradle build (only setup native libs)
  --abis=ABIS         ABIs to build (default: arm64-v8a)
  --help              Show help
```

## Gradle Tasks

The SDK also provides Gradle tasks for convenience:

```bash
# First-time setup (same as build-kotlin.sh --setup)
./gradlew setupLocalDevelopment

# Rebuild commons (same as build-kotlin.sh --rebuild-commons)
./gradlew rebuildCommons

# Build with local libs
./gradlew -Prunanywhere.testLocal=true assembleDebug

# Build with remote libs (GitHub releases)
./gradlew -Prunanywhere.testLocal=false assembleDebug

# Force rebuild of commons during build
./gradlew -Prunanywhere.rebuildCommons=true assembleDebug
```

## gradle.properties Flags

| Property | Default | Description |
|----------|---------|-------------|
| `runanywhere.testLocal` | `false` | Use local JNI libs vs download from GitHub |
| `runanywhere.rebuildCommons` | `false` | Force rebuild of C++ code |
| `runanywhere.coreVersion` | `0.1.4` | Version for remote backend downloads |
| `runanywhere.commonsVersion` | `0.1.4` | Version for remote commons downloads |

## Output Directories

When `testLocal=true`, JNI libraries are placed in:

```
runanywhere-kotlin/
├── src/androidMain/jniLibs/arm64-v8a/     # Main SDK (Commons)
│   ├── libc++_shared.so
│   ├── librunanywhere_jni.so
│   └── librac_commons.so
├── modules/
│   ├── runanywhere-core-llamacpp/
│   │   └── src/androidMain/jniLibs/arm64-v8a/
│   │       └── librac_backend_llamacpp_jni.so
│   └── runanywhere-core-onnx/
│       └── src/androidMain/jniLibs/arm64-v8a/
│           ├── librac_backend_onnx_jni.so
│           ├── libonnxruntime.so
│           └── libsherpa-onnx-*.so
```

## Workflow Comparison: iOS vs Android

| Step | iOS (Swift) | Android (Kotlin) |
|------|-------------|------------------|
| First-time setup | `./scripts/build-swift.sh --setup` | `./scripts/build-kotlin.sh --setup` |
| Rebuild C++ | `./scripts/build-swift.sh --local --build-commons` | `./scripts/build-kotlin.sh --local --rebuild-commons` |
| Local mode flag | `testLocal = true` in Package.swift | `runanywhere.testLocal=true` in gradle.properties |
| Output location | `Binaries/*.xcframework` | `src/androidMain/jniLibs/` |
