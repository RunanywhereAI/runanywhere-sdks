# Building RunAnywhere Kotlin SDK

## Quick Start

### Using Android Studio

1. Open the project in Android Studio
2. Wait for Gradle sync to complete
3. Build the project

### Using Command Line

Navigate to the root folder and run:

```bash
# Check environment and dependencies
./gradlew checkEnvironment

# Create required configuration files
./gradlew setupLocalProperties

# Build SDK and all examples
./gradlew buildAll
```

## Prerequisites

- Android Studio Arctic Fox or later
- JDK 17 or higher
- Android SDK with Build Tools
- Android NDK 27.0.12077973 (or compatible version)

Set environment variables (recommended):

```bash
export ANDROID_HOME=/path/to/android/sdk
export ANDROID_NDK_HOME=/path/to/android/ndk/27.0.12077973
```

## Build Configuration

### Remote Mode (Default)

Downloads pre-built native libraries from GitHub releases.

```properties
# gradle.properties
runanywhere.testLocal=false
```

Recommended for most development work.

### Local Mode

Builds native libraries from source. Only needed when modifying C++ code.

```properties
# gradle.properties
runanywhere.testLocal=true
```

## Available Commands

### Build Commands

```bash
# Build SDK only
./gradlew buildSdk

# Build SDK release variant
./gradlew buildSdkRelease

# Build Android example app
./gradlew buildAndroidApp

# Build and run Android app
./gradlew runAndroidApp

# Build IntelliJ plugin
./gradlew buildIntellijPlugin

# Build and run IntelliJ plugin
./gradlew runIntellijPlugin
```

### Utility Commands

```bash
# Check development environment
./gradlew checkEnvironment

# Setup configuration files
./gradlew setupLocalProperties

# Clean all projects
./gradlew cleanAll
```

## Troubleshooting

### Missing local.properties

Run `./gradlew setupLocalProperties` to create required files.

### JNI Libraries Not Found

For remote mode:
```bash
./gradlew downloadJniLibs
```

For local mode:
```bash
./scripts/build-kotlin.sh --setup
```

### Clean Build

```bash
./gradlew cleanAll
./gradlew buildAll
```

## Project Structure

```
runanywhere-sdks/
│── sdk/
│    └──── runanywhere-kotlin/
└── examples/
    ├── android/              
    └── intellij-plugin-demo/ 
```

## Output Locations

After successful build:

- SDK AAR: `RunAnywhereAI/sdk/runanywhere-kotlin/build/outputs/aar/`
- Android APK: `examples/android/RunAnywhereAI/app/build/outputs/apk/`
- IntelliJ Plugin: `examples/intellij-plugin-demo/plugin/build/distributions/`
- Maven Local: `~/.m2/repository/com/runanywhere/runanywhere-sdk/`

## Support

For issues or questions:
- GitHub Issues: https://github.com/RunanywhereAI/runanywhere-sdks/issues
- Documentation: https://docs.runanywhere.ai