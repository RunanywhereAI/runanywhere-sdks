# Flutter SDK Scripts

Build scripts for the RunAnywhere Flutter SDK.

## build-flutter.sh

Single entry point for building the Flutter SDK and its native dependencies.

### First Time Setup

```bash
cd sdk/runanywhere-flutter
./scripts/build-flutter.sh --setup
```

This will:
1. Install Flutter dependencies (using melos or flutter pub get)
2. Build `runanywhere-commons` for iOS and Android
3. Copy XCFrameworks to iOS package directories
4. Copy JNI libraries to Android package directories
5. Set local mode for development

### Commands

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup: install deps, build commons, copy frameworks/libs |
| `--local` | Use locally built native libs (sets `testLocal=true`) |
| `--remote` | Use remote libs from GitHub releases |
| `--rebuild-commons` | Force rebuild of runanywhere-commons |
| `--ios` | Build for iOS only |
| `--android` | Build for Android only |
| `--clean` | Clean build directories before building |
| `--skip-build` | Skip native build (only setup frameworks/libs) |

### Examples

```bash
# First-time setup (downloads + builds + copies everything)
./scripts/build-flutter.sh --setup

# Rebuild only commons (after C++ code changes)
./scripts/build-flutter.sh --local --rebuild-commons

# Just switch to local mode (uses cached libs)
./scripts/build-flutter.sh --local --skip-build

# iOS only setup
./scripts/build-flutter.sh --setup --ios

# Android only with clean
./scripts/build-flutter.sh --setup --android --clean
```

## Running the Example App

After setup, run the example app:

```bash
cd examples/flutter/RunAnywhereAI

# Install dependencies
flutter pub get

# iOS
cd ios && pod install && cd ..
flutter run

# Android
flutter run
```

## Package Structure

The SDK uses a monorepo structure with three packages:

```
packages/
├── runanywhere/            # Core SDK - RACommons bindings
│   ├── ios/
│   │   └── Frameworks/     # RACommons.xcframework
│   ├── android/
│   │   └── src/main/jniLibs/  # Core JNI libraries:
│   │       └── arm64-v8a/
│   │           ├── librunanywhere_jni.so
│   │           ├── librac_commons.so
│   │           ├── libc++_shared.so
│   │           └── libomp.so
│   └── lib/                # Dart code
│
├── runanywhere_llamacpp/   # LLM backend
│   ├── ios/
│   │   └── Frameworks/     # RABackendLLAMACPP.xcframework
│   ├── android/
│   │   └── src/main/jniLibs/  # LlamaCPP JNI libraries:
│   │       └── arm64-v8a/
│   │           ├── librac_backend_llamacpp.so
│   │           ├── librac_backend_llamacpp_jni.so
│   │           ├── libc++_shared.so
│   │           └── libomp.so
│   └── lib/                # Dart code
│
└── runanywhere_onnx/       # ONNX backend
    ├── ios/
    │   └── Frameworks/
    │       ├── RABackendONNX.xcframework
    │       └── onnxruntime.xcframework
    ├── android/
    │   └── src/main/jniLibs/  # ONNX JNI libraries:
    │       └── arm64-v8a/
    │           ├── librac_backend_onnx.so
    │           ├── librac_backend_onnx_jni.so
    │           ├── libonnxruntime.so
    │           ├── libsherpa-onnx-c-api.so
    │           ├── libsherpa-onnx-cxx-api.so
    │           └── libsherpa-onnx-jni.so
    └── lib/                # Dart code
```

## Local vs Remote Mode

### Local Mode

- **iOS**: Uses XCFrameworks from `Frameworks/` directories
  - Indicated by `.testlocal` marker files
  - Set `RA_TEST_LOCAL=1` environment variable
- **Android**: Uses JNI libraries from `src/main/jniLibs/` directories
  - Set `testLocal = true` in `binary_config.gradle`

### Remote Mode (default for consumers)

- **iOS**: Downloads XCFrameworks from GitHub releases during `pod install`
- **Android**: Downloads JNI libraries from GitHub releases during Gradle sync
- Uses version numbers from podspecs and build.gradle files

## Rebuilding After C++ Changes

When you modify C++ code in `runanywhere-commons`:

```bash
# Rebuild everything
./scripts/build-flutter.sh --local --rebuild-commons

# iOS only
./scripts/build-flutter.sh --local --rebuild-commons --ios

# Android only
./scripts/build-flutter.sh --local --rebuild-commons --android
```

## Melos Integration

The SDK uses [melos](https://melos.invertase.dev/) for monorepo management:

```bash
# Install melos
dart pub global activate melos

# Bootstrap all packages
melos bootstrap

# Run analyze across all packages
melos run analyze

# Run tests across all packages
melos run test

# Clean all packages
melos run clean
```
