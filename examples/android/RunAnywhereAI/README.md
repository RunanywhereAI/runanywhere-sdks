# RunAnywhere AI - Android Example

A sample Android app demonstrating the [RunAnywhere Kotlin SDK](../../../sdk/runanywhere-kotlin/).

## Setup

```bash
# 1. Build the SDK's native libraries (first time only, ~10-15 min)
cd runanywhere-sdks/sdk/runanywhere-kotlin
./scripts/build-kotlin.sh --setup

# 2. Open in Android Studio
#    File > Open > examples/android/RunAnywhereAI

# 3. Run on device or emulator
./gradlew installDebug
```

## Build

```bash
./gradlew assembleDebug       # Debug APK
./gradlew assembleRelease     # Release APK (requires signing env vars)
./gradlew test                # Unit tests
./gradlew lint                # Android lint
```

## Requirements

- Android Studio Hedgehog (2023.1.1)+
- Android SDK 24+ (Android 7.0)
- JDK 17+
- arm64-v8a device recommended

## License

Apache License 2.0 - see [LICENSE](../../../LICENSE).
