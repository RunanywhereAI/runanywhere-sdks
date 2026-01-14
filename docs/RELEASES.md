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

All SDKs are released as a **single unified release** with all assets attached:

| Tag | Example |
|-----|---------|
| `v1.0.0` | [v1.0.0 Release](https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/v1.0.0) |

### Assets in Each Release

Every unified release (`v*`) includes assets split by platform and ABI for smaller downloads.

#### Core Libraries (always needed)
| Asset | Platform | Size |
|-------|----------|------|
| `RACommons-ios-v*.zip` | iOS/macOS | ~2 MB |
| `RACommons-android-arm64-v8a-v*.zip` | Android arm64 | ~61 MB |
| `RACommons-android-armeabi-v7a-v*.zip` | Android armv7 | ~57 MB |
| `RACommons-android-x86_64-v*.zip` | Android x86_64 (emulator) | ~64 MB |

#### Backend Libraries (pick what you need)
| Asset | Platform | Use Case |
|-------|----------|----------|
| `RABackendLLAMACPP-ios-v*.zip` | iOS/macOS | LLM text generation |
| `RABackendLLAMACPP-android-{abi}-v*.zip` | Android | LLM text generation |
| `RABackendONNX-ios-v*.zip` | iOS/macOS | STT / TTS / VAD |
| `RABackendONNX-android-{abi}-v*.zip` | Android | STT / TTS / VAD |

> 💡 **Tip:** Most Android apps only need `arm64-v8a` (85% of devices). Only add other ABIs if you need legacy device support (`armeabi-v7a`) or emulator support (`x86_64`).

#### SDK Packages
| Asset | Platform | Description |
|-------|----------|-------------|
| `RunAnywhere-Swift-SDK-v*.zip` | iOS/macOS | Swift SDK |
| `RunAnywhere-Kotlin-SDK-v*.aar` | Android | Kotlin SDK (AAR) |
| `RunAnywhere-Flutter-SDK-v*.zip` | Cross-platform | Flutter SDK |
| `RunAnywhere-ReactNative-SDK-v*.zip` | Cross-platform | React Native SDK |
| `checksums.sha256` | All | SHA256 checksums |

### Native Libraries

For advanced users who want to integrate at the C/C++ level:

| File | Platforms | Contents |
|------|-----------|----------|
| `RABackendLLAMACPP-ios-*.zip` | iOS | XCFramework with llama.cpp |
| `RABackendONNX-ios-*.zip` | iOS | XCFramework with Sherpa-ONNX |
| `RABackends-android-*.zip` | Android | LlamaCPP + ONNX .so files for all ABIs |
| `RACommons-ios-*.zip` | iOS | Core XCFramework |
| `RACommons-android-*.zip` | Android | Core native libs |

---

## CI/CD Workflows

### Unified Release (Recommended)

The primary release workflow creates a **single release** with all SDK assets:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `release-all.yml` | Tag `v*` or Manual | Creates unified release with all SDKs |

**To create a unified release:**
```bash
git tag v1.0.0
git push origin v1.0.0
```

This creates ONE release (`v1.0.0`) with all assets attached.

### Individual SDK Releases (Optional)

For standalone releases of individual SDKs:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `commons-release.yml` | Tag `commons-v*` | Release RACommons only |
| `backends-release.yml` | Tag `backends-v*` | Release backend libraries |
| `swift-sdk-release.yml` | Tag `swift-v*` | Release Swift SDK |
| `kotlin-sdk-release.yml` | Tag `kotlin-v*` | Release Kotlin SDK |
| `flutter-sdk-release.yml` | Tag `flutter-v*` | Release Flutter SDK |
| `react-native-sdk-release.yml` | Tag `react-native-v*` | Release RN SDK |

### Manual Release

All workflows support `workflow_dispatch` for manual releases from the GitHub Actions UI:

1. Go to **Actions** tab
2. Select **Release All SDKs**
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

When pushing a unified tag (`v1.0.0`), all SDKs are built and combined into a **single release**:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This creates:
- **One release page** at `https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/v1.0.0`
- **All SDK assets** attached to that single release
- **Comprehensive release notes** with build status and quick start guides

### Independent Releases

Individual SDKs can still be released independently by pushing their specific tag:
```bash
git tag swift-v1.0.1
git push origin swift-v1.0.1
```

This creates a separate release for just that SDK.

---

## Verifying Downloads

All unified releases include a `checksums.sha256` file:

```bash
# Download artifact and checksums
wget https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v1.0.0/RABackends-android-v1.0.0.zip
wget https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v1.0.0/checksums.sha256

# Verify
shasum -a 256 -c checksums.sha256
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

