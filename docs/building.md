# Building the Project

## Prerequisites

- Android Studio Arctic Fox or later
- JDK 17+
- Android SDK with Build Tools
- Android NDK 27.0.12077973 (or compatible)

Set environment variables (recommended):

```bash
export ANDROID_HOME=/path/to/android/sdk
export ANDROID_NDK_HOME=/path/to/android/ndk/27.0.12077973
```

## Quick Start

```bash
# Check environment and create local.properties
./gradlew setup

# Build SDK and all examples
./gradlew buildAll
```

Or open the project in Android Studio and wait for Gradle sync.

## Gradle Project Structure

```
RunAnywhere (root)
├── :runanywhere-kotlin           # KMP SDK (JVM + Android)
├── :runanywhere-core-llamacpp    # LLM backend (optional)
├── :runanywhere-core-onnx        # STT/TTS/VAD backend (optional)
├── RunAnywhereAI (composite)     # Android example app
└── plugin (composite)            # IntelliJ plugin example
```

## Commands

### Setup

```bash
./gradlew setup              # Check environment + create local.properties
```

### SDK

```bash
./gradlew buildSdk           # Build debug AAR + JVM JAR
./gradlew buildSdkRelease    # Build release AAR
./gradlew publishSdkToMavenLocal  # Publish to ~/.m2/repository
```

### Android Example App

```bash
./gradlew buildAndroidApp    # Build debug APK
./gradlew runAndroidApp      # Build, install, and launch on device
```

### IntelliJ Plugin

```bash
./gradlew buildIntellijPlugin  # Publish SDK + build plugin
./gradlew runIntellijPlugin    # Publish SDK + run plugin in sandbox
```

### Everything

```bash
./gradlew buildAll           # Setup + build SDK + all examples
./gradlew cleanAll           # Clean all projects
```

## JNI Library Modes

Native libraries can be sourced in two ways, controlled by `gradle.properties`:

### Remote mode (default for CI)

Downloads pre-built `.so` files from GitHub releases. No NDK required.

```properties
runanywhere.testLocal=false
```

### Local mode (for C++ development)

Builds native libraries from `runanywhere-commons` source. Requires NDK.

```properties
runanywhere.testLocal=true
```

First-time local setup:

```bash
cd sdk/runanywhere-kotlin
./scripts/build-kotlin.sh --setup
```

To rebuild after C++ changes:

```bash
./gradlew :runanywhere-kotlin:rebuildCommons
```

## Output Locations

| Artifact | Path |
|----------|------|
| SDK AAR | `sdk/runanywhere-kotlin/build/outputs/aar/` |
| SDK JVM JAR | `sdk/runanywhere-kotlin/build/libs/` |
| Android APK | `examples/android/RunAnywhereAI/app/build/outputs/apk/` |
| IntelliJ Plugin | `examples/intellij-plugin-demo/plugin/build/distributions/` |
| Maven Local | `~/.m2/repository/com/runanywhere/runanywhere-sdk/` |

## Troubleshooting

### Missing local.properties

```bash
./gradlew setup
```

### JNI libraries not found

Remote mode:
```bash
./gradlew :runanywhere-kotlin:downloadJniLibs
```

Local mode:
```bash
cd sdk/runanywhere-kotlin && ./scripts/build-kotlin.sh --setup
```

### Clean rebuild

```bash
./gradlew cleanAll && ./gradlew buildAll
```
