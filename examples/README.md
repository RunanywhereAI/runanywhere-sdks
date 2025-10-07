# RunAnywhere SDK Examples

This directory contains sample applications demonstrating the usage of the RunAnywhere SDK.

## Sample Applications

### 1. Android STT Demo

Location: `android-stt-demo/`

A sample Android application demonstrating:

- Real-time speech transcription
- Voice activity detection
- Model management
- Audio recording and playback
- Offline transcription with Whisper models

### 2. IntelliJ Plugin Demo

Location: `intellij-plugin-demo/`

A sample IntelliJ IDEA plugin demonstrating:

- Voice commands for IDE actions
- Voice dictation for code
- Real-time transcription in editor
- Custom voice shortcuts

## Getting Started

Each example has its own README with specific setup instructions.

### Prerequisites

- Android Studio (for Android demo)
- IntelliJ IDEA (for plugin demo)
- JDK 11 or higher

### Running the Examples

1. Clone the repository
2. Navigate to the example directory
3. Follow the README instructions in each example

## SDK Integration

All examples use the RunAnywhere SDK from the local Maven repository. Make sure to build and publish
the SDK locally first:

```bash
cd sdk/runanywhere-android
./gradlew publishToMavenLocal
```

## Documentation

For detailed SDK documentation, see the [main README](../sdk/runanywhere-android/README.md).
