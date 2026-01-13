# RunAnywhere SDKs - Release & Distribution Guide

This document explains how to consume RunAnywhere SDKs from GitHub releases, without cloning the repository.

## Quick Start by Platform

### Swift (iOS/macOS)

**Via Swift Package Manager:**
```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/RunanywhereAI/runanywhere-sdks",
        from: "1.0.0"
    )
]

// In your target:
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "RunAnywhere", package: "runanywhere-sdks"),
        .product(name: "LlamaCPPRuntime", package: "runanywhere-sdks"),  // LLM
        .product(name: "ONNXRuntime", package: "runanywhere-sdks"),      // STT/TTS/VAD
    ]
)
```

### Kotlin (Android)

**Via Gradle:**
```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        maven { url = uri("https://maven.pkg.github.com/RunanywhereAI/runanywhere-sdks") }
    }
}

// app/build.gradle.kts
dependencies {
    implementation("ai.runanywhere:runanywhere-kotlin:1.0.0")
}
```

**Direct AAR Download:**
1. Go to [Releases](https://github.com/RunanywhereAI/runanywhere-sdks/releases)
2. Find `kotlin-v1.0.0` release
3. Download `runanywhere-kotlin-1.0.0.aar`
4. Add to your project's `libs/` folder

### Flutter

**Via Git Dependency:**
```yaml
# pubspec.yaml
dependencies:
  runanywhere:
    git:
      url: https://github.com/RunanywhereAI/runanywhere-sdks
      path: sdk/runanywhere-flutter/packages/runanywhere
      ref: flutter-v1.0.0
  
  # Add backends you need:
  runanywhere_llamacpp:  # LLM text generation
    git:
      url: https://github.com/RunanywhereAI/runanywhere-sdks
      path: sdk/runanywhere-flutter/packages/runanywhere_llamacpp
      ref: flutter-v1.0.0
  
  runanywhere_onnx:  # STT/TTS/VAD
    git:
      url: https://github.com/RunanywhereAI/runanywhere-sdks
      path: sdk/runanywhere-flutter/packages/runanywhere_onnx
      ref: flutter-v1.0.0
```

### React Native

**Via package.json:**
```json
{
  "dependencies": {
    "@runanywhere/core": "github:RunanywhereAI/runanywhere-sdks#react-native-v1.0.0",
    "@runanywhere/llamacpp": "github:RunanywhereAI/runanywhere-sdks#react-native-v1.0.0",
    "@runanywhere/onnx": "github:RunanywhereAI/runanywhere-sdks#react-native-v1.0.0"
  }
}
```

**Post-install setup:**
```bash
# iOS
cd ios && pod install

# Android
cp android/gradle.properties.example android/gradle.properties
```

---

## Release Components

The repository produces several release artifacts:

| Tag Pattern | Component | Contents |
|-------------|-----------|----------|
| `v1.0.0` | Unified Release | All SDKs at same version |
| `commons-v1.0.0` | RACommons | Core infrastructure library |
| `backends-v1.0.0` | Backends | LlamaCPP + ONNX native libs |
| `swift-v1.0.0` | Swift SDK | iOS/macOS SDK |
| `kotlin-v1.0.0` | Kotlin SDK | Android AAR + JVM JAR |
| `flutter-v1.0.0` | Flutter SDK | Dart packages with natives |
| `react-native-v1.0.0` | React Native SDK | npm packages with natives |

### Native Libraries

For advanced users who want to integrate at the C/C++ level:

| Release | File | Platforms |
|---------|------|-----------|
| `backends-v*` | `RABackendLLAMACPP-ios-*.zip` | iOS (XCFramework) |
| `backends-v*` | `RABackendONNX-ios-*.zip` | iOS (XCFramework) |
| `backends-v*` | `RABackends-android-*.zip` | Android (arm64-v8a, armeabi-v7a, x86_64) |
| `commons-v*` | `RACommons-ios-*.zip` | iOS (XCFramework) |
| `commons-v*` | `RACommons-android-*.zip` | Android (all ABIs) |

---

## CI/CD Workflows

### Release Triggers

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `release-all.yml` | Tag `v*` | Release all SDKs at once |
| `commons-release.yml` | Tag `commons-v*` | Release RACommons only |
| `backends-release.yml` | Tag `backends-v*` | Release backend libraries |
| `swift-sdk-release.yml` | Tag `swift-v*` | Release Swift SDK |
| `kotlin-sdk-release.yml` | Tag `kotlin-v*` | Release Kotlin SDK |
| `flutter-sdk-release.yml` | Tag `flutter-v*` | Release Flutter SDK |
| `react-native-sdk-release.yml` | Tag `react-native-v*` | Release RN SDK |

### Manual Release

All workflows support `workflow_dispatch` for manual releases from the GitHub Actions UI:

1. Go to **Actions** tab
2. Select a release workflow
3. Click **Run workflow**
4. Enter version and options
5. Click **Run workflow**

### Dry Run

All workflows support a `dry_run` option that builds artifacts without publishing. Use this to verify builds before actual releases.

---

## Version Strategy

We use [Semantic Versioning](https://semver.org/):

- **Major** (`1.0.0` → `2.0.0`): Breaking API changes
- **Minor** (`1.0.0` → `1.1.0`): New features, backwards compatible
- **Patch** (`1.0.0` → `1.0.1`): Bug fixes only

### Coordinated Releases

When pushing a unified tag (`v1.0.0`), all SDKs are released with the same version:
- `commons-v1.0.0`
- `backends-v1.0.0`
- `swift-v1.0.0`
- `kotlin-v1.0.0`
- `flutter-v1.0.0`
- `react-native-v1.0.0`

### Independent Releases

Individual SDKs can be released independently by pushing their specific tag:
```bash
git tag swift-v1.0.1
git push origin swift-v1.0.1
```

---

## Verifying Downloads

All release artifacts include SHA256 checksums:

```bash
# Download artifact and checksum
wget https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/backends-v1.0.0/RABackends-android-v1.0.0.zip
wget https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/backends-v1.0.0/RABackends-android-v1.0.0.zip.sha256

# Verify
shasum -a 256 -c RABackends-android-v1.0.0.zip.sha256
```

---

## Android ABI Support

| ABI | Architecture | Coverage | Notes |
|-----|--------------|----------|-------|
| `arm64-v8a` | 64-bit ARM | ~85% | Modern devices, recommended |
| `armeabi-v7a` | 32-bit ARM | ~12% | Legacy device support |
| `x86_64` | 64-bit Intel | ~2% | Emulators (Intel Macs) |
| `x86` | 32-bit Intel | ~1% | Very old emulators |

**Recommended for production:** `arm64-v8a` + `armeabi-v7a` (~97% coverage)

**16KB Page Alignment:** All Android libraries are 16KB aligned for Google Play Store compliance (November 2025 deadline).

---

## iOS/macOS Requirements

- **Deployment Target:** iOS 13.0+ / macOS 10.15+
- **Swift:** 5.9+
- **Xcode:** 15.0+

XCFrameworks include:
- `ios-arm64` (devices)
- `ios-arm64_x86_64-simulator` (simulators)

---

## Troubleshooting

### Swift: XCFramework not found

Ensure you're using Xcode 15+ and your Package.swift specifies a valid version:
```swift
.package(url: "...", from: "1.0.0")  // ✅
.package(url: "...", branch: "main")  // ⚠️ May be unstable
```

### Android: Missing ABIs

Check your `build.gradle.kts` ABI filters match what's in the release:
```kotlin
android {
    defaultConfig {
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }
}
```

### Flutter: Pod install fails

Run from the `ios/` directory:
```bash
cd ios
pod deintegrate
pod install --repo-update
```

### React Native: Metro bundler connection

For physical Android devices:
```bash
adb reverse tcp:8081 tcp:8081
```

---

## Support

- **Issues:** [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Discussions:** [GitHub Discussions](https://github.com/RunanywhereAI/runanywhere-sdks/discussions)
- **Documentation:** See individual SDK READMEs in `sdk/` folder

