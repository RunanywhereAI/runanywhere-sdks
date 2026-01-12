# React Native SDK Scripts

Build scripts for the RunAnywhere React Native SDK.

## build-react-native.sh

Single entry point for building the React Native SDK and its native dependencies.

### First Time Setup

```bash
cd sdk/runanywhere-react-native
./scripts/build-react-native.sh --setup
```

This will:
1. Install yarn dependencies
2. Build `runanywhere-commons` for iOS and Android
3. Copy XCFrameworks to iOS packages
4. Copy JNI libraries to Android packages
5. Set local mode for development

### Commands

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup: install deps, build commons, copy frameworks/libs |
| `--local` | Use locally built native libs (sets `RA_TEST_LOCAL=1`) |
| `--remote` | Use remote libs from GitHub releases |
| `--rebuild-commons` | Force rebuild of runanywhere-commons |
| `--ios` | Build for iOS only |
| `--android` | Build for Android only |
| `--clean` | Clean build directories before building |
| `--skip-build` | Skip native build (only setup frameworks/libs) |

### Examples

```bash
# First-time setup (downloads + builds + copies everything)
./scripts/build-react-native.sh --setup

# Rebuild only commons (after C++ code changes)
./scripts/build-react-native.sh --local --rebuild-commons

# Just switch to local mode (uses cached libs)
./scripts/build-react-native.sh --local --skip-build

# iOS only setup
./scripts/build-react-native.sh --setup --ios

# Android only with clean
./scripts/build-react-native.sh --setup --android --clean
```

## Running the Example App

After setup, run the example app:

```bash
cd examples/react-native/RunAnywhereAI

# Install dependencies
yarn install

# iOS
cd ios && pod install && cd ..
npx react-native run-ios

# Android
npx react-native run-android
```

## Package Structure

The SDK uses a monorepo structure with three packages:

```
packages/
├── core/           # @runanywhere/core - RACommons bindings
│   ├── ios/
│   │   ├── Binaries/      # Local XCFrameworks (testLocal mode)
│   │   └── Frameworks/    # Downloaded XCFrameworks (remote mode)
│   └── android/
│       └── src/main/jniLibs/   # JNI libraries
│
├── llamacpp/       # @runanywhere/llamacpp - LLM backend
│   ├── ios/
│   │   └── Frameworks/    # RABackendLLAMACPP.xcframework
│   └── android/
│       └── src/main/jniLibs/   # LlamaCPP JNI libraries
│
└── onnx/           # @runanywhere/onnx - ONNX backend
    ├── ios/
    │   └── Frameworks/    # RABackendONNX.xcframework
    └── android/
        └── src/main/jniLibs/   # ONNX JNI libraries
```

## Local vs Remote Mode

### Local Mode (`RA_TEST_LOCAL=1`)

- iOS: Uses XCFrameworks from `Binaries/` or `Frameworks/` directories
- Android: Uses JNI libraries from `src/main/jniLibs/` directories
- Created by `--setup` or `--local` flags
- Indicated by `.testlocal` marker files

### Remote Mode (default for consumers)

- iOS: Downloads XCFrameworks from GitHub releases during `pod install`
- Android: Downloads JNI libraries from GitHub releases during Gradle sync
- Uses version numbers from podspecs and build.gradle files

## Rebuilding After C++ Changes

When you modify C++ code in `runanywhere-commons`:

```bash
# Rebuild everything
./scripts/build-react-native.sh --local --rebuild-commons

# iOS only
./scripts/build-react-native.sh --local --rebuild-commons --ios

# Android only
./scripts/build-react-native.sh --local --rebuild-commons --android
```
