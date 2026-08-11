# Flutter SDK — Development Guide

This guide covers platform setup, building from source, and contributor workflows. For integration instructions, see the [consumer README](../README.md).

---

## Prerequisites

| Tool | Version |
|------|---------|
| **Flutter** | 3.44+ (workspace constraint is `>=3.44.0`; validated on 3.44.6) |
| **Dart** | Matches workspace `pubspec.yaml` (`>=3.12.0 <4.0.0`) |
| **Xcode** | 26+ (iOS builds) |
| **Android Studio** | with NDK 28.2.13676358 |
| **CMake** | 3.24+ |

---

## Platform Setup

### iOS Setup (Required)

After adding the packages, update your iOS Podfile:

**1. Update `ios/Podfile`:**

```ruby
platform :ios, '17.5'

target 'Runner' do
  use_frameworks! :linkage => :static

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.5'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

> **Important:** Without `use_frameworks! :linkage => :static`, you will see "symbol not found" errors at runtime.

**2. Update `ios/Runner/Info.plist`:**

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for speech recognition</string>
```

**3. Run pod install:**

```bash
cd ios && pod install && cd ..
```

### Android Setup

Add microphone permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## First-Time Setup (Build from Source)

The SDK depends on native C++ libraries from `runanywhere-commons`.

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks

# 2. Build native artifacts (from repo root)
./bindings/swift/scripts/build-core-xcframework.sh
./scripts/build/build-core-android.sh arm64-v8a

# 3. Bootstrap the Flutter workspace
cd bindings/flutter
melos bootstrap
```

**What the build scripts do:**

- `build-core-xcframework.sh` builds and stages XCFrameworks into each package's `ios/<package>/Frameworks/` directory.
- `build-core-android.sh <ABI>` builds `.so` libraries and stages them into `android/src/main/jniLibs/<ABI>/`.

---

## Local vs Remote Natives

| Mode | Description |
|------|-------------|
| **Source checkout** | Android uses staged JNI when `runanywhere.useLocalNatives=true`; Apple packages prefer staged `Frameworks/`. |
| **Published package** | Pub archives omit native payloads. Android Gradle downloads per-ABI archives with SHA-256 verification. CocoaPods/SwiftPM download pinned checksums for Apple plugins. |

---

## Testing with the Sample App

```bash
cd ../../bindings/flutter/example
flutter pub get
cd ios && pod install && cd ..
flutter run
```

The sample app's `pubspec.yaml` uses path dependencies to reference the local SDK packages.

---

## Development Workflow

**After modifying Dart SDK code:** changes are picked up automatically when you run `flutter run`.

**After modifying `runanywhere-commons` (C++ code):**

```bash
# From repo root
./bindings/swift/scripts/build-core-xcframework.sh
./scripts/build/build-core-android.sh arm64-v8a
```

---

## Build Script Reference

| Script | Description |
|--------|-------------|
| `bindings/swift/scripts/build-core-xcframework.sh` | iOS: builds/stages package-owned XCFrameworks |
| `scripts/build/build-core-android.sh <ABI>` | Android: builds backend `.so` files into Flutter packages |
| `bindings/flutter/scripts/package-sdk.sh` | Validate all packages via `pub publish --dry-run` |

---

## Architecture Overview

The RunAnywhere Flutter SDK uses a modular architecture with a C++ commons layer accessed via FFI:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Your Flutter Application                     │
├─────────────────────────────────────────────────────────────────┤
│  RunAnywhere (llm, stt, tts, vad, vlm, voice, models, ...)     │
├─────────────────────────────────────────────────────────────────┤
│                    Native Bridge Layer (FFI)                      │
├───────────┬───────────┬───────────┬─────────────────────────────┤
│ LlamaCpp  │ Apple MLX │   ONNX    │ QHexRT (optional NPU)       │
└───────────┴───────────┴───────────┴─────────────────────────────┘
```

See also [Documentation.md](./Documentation.md) and [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## Code Style

```bash
dart format lib/ test/
flutter analyze
dart fix --apply
```

---

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes with tests
4. Ensure all tests pass: `flutter test`
5. Run analyzer: `flutter analyze`
6. Commit with a descriptive message
7. Push and open a Pull Request

---

## Troubleshooting (Development)

### iOS: Symbol Not Found

1. Ensure `use_frameworks! :linkage => :static` in Podfile
2. Run `cd ios && pod install --repo-update`
3. Clean and rebuild: `flutter clean && flutter run`

### Android: Library Load Failed

1. Ensure NDK is properly installed
2. Check that `jniLibs` folder contains `.so` files
3. Rebuild native libraries with `./scripts/build/build-core-android.sh <ABI>` from the repo root

---

## Reporting Issues

Open an issue on GitHub with:

- SDK version: `RunAnywhere.version`
- Flutter version: `flutter --version`
- Platform and OS version
- Device model
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (with sensitive info redacted)
