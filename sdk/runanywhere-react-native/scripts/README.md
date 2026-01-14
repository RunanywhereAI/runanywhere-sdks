# React Native SDK Scripts

Build scripts for the RunAnywhere React Native SDK.

---

## 🚀 Fresh Clone to Running App

If you just cloned the repository and want to test the React Native SDK end-to-end:

```bash
# 1. Build SDK with native libraries (~15-20 min for both platforms)
cd sdk/runanywhere-react-native
./scripts/build-react-native.sh --setup

# 2. Navigate to sample app
cd ../../examples/react-native/RunAnywhereAI
yarn install

# 3. Setup Android (one-time)
cp android/gradle.properties.example android/gradle.properties

# 4. Run on iOS
cd ios && pod install && cd ..
npx react-native run-ios --simulator="iPhone 16 Pro"

# 5. Run on Android
npx react-native run-android
```

**That's it!** The sample app will launch with:
- ✅ LlamaCPP backend (LLM text generation)
- ✅ ONNX backend (STT/TTS)
- ✅ All features working (Chat, Voice, etc.)

---

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
5. Create `.testlocal` marker files
6. Set local mode for development (`RA_TEST_LOCAL=1`)

**Output:**
- iOS: 3 XCFrameworks (RACommons, RABackendLLAMACPP, RABackendONNX)
- Android: 13 .so libraries (for arm64-v8a by default)

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
npx react-native run-ios --simulator="iPhone 16 Pro"

# Android
# First time: Copy gradle.properties template
cp android/gradle.properties.example android/gradle.properties

# Make sure device/emulator is connected
adb devices

# Run app
npx react-native run-android
```

### Verify Sample App Works

The app should launch and show 5 tabs:
- **Chat**: Send messages to LLM, stream responses
- **STT**: Record and transcribe speech
- **TTS**: Synthesize text to speech
- **Voice**: Full voice conversation (VAD → STT → LLM → TTS)
- **Settings**: Model management, downloads, storage

### Testing Checklist

After app launches:
- [ ] SDK initializes without errors (check Metro logs)
- [ ] Can navigate between tabs
- [ ] Settings shows LlamaCPP and ONNX backends available
- [ ] Can register and download models
- [ ] Chat functionality works with LLM
- [ ] STT/TTS features work

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
