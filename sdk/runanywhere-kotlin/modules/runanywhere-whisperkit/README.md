# WhisperKit Module for RunAnywhere SDK

This module provides Whisper-based speech-to-text implementation that extends the generic STT interfaces defined in the main RunAnywhere SDK.

## Architecture

The WhisperKit module follows the established pattern where:

1. **Generic STT interfaces** are defined in the main SDK's `commonMain` module
2. **WhisperKit module** extends these generic interfaces with Whisper-specific implementations
3. **Provider pattern** allows the module to be registered and used seamlessly with the SDK

## Key Components

### Generic SDK Interfaces (Main SDK)
- `STTService` - Generic speech-to-text service interface
- `STTConfiguration` - Generic STT configuration
- `STTOptions` - Generic transcription options
- `STTTranscriptionResult` - Generic transcription result
- `STTServiceProvider` - Provider interface for STT services

### WhisperKit Extensions (This Module)
- `WhisperKitService` - Abstract class extending `STTService` with Whisper-specific features
- `WhisperModelType` - Whisper-specific model types (TINY, BASE, SMALL, etc.)
- `WhisperTranscriptionOptions` - Extended options for Whisper
- `WhisperTranscriptionResult` - Extended result with Whisper metadata
- `WhisperKitProvider` - Adapter implementing `STTServiceProvider`

## Usage

### 1. Initialize the Module

```kotlin
// In your application initialization
import com.runanywhere.whisperkit.WhisperKitModule

WhisperKitModule.initialize()
```

### 2. Use with Generic STT Interface

```kotlin
// Using generic STT configuration
val sttConfig = STTConfiguration(
    modelId = "whisper-base",  // Generic model ID
    language = "en-US"
)

// Create STT component (uses WhisperKit internally)
val sttComponent = STTComponent(sttConfig)
sttComponent.initialize()

// Use generic STT options
val options = STTOptions(
    language = "en",
    enableTimestamps = true,
    sensitivityMode = STTSensitivityMode.HIGH
)

// Transcribe using generic interface
val result = sttComponent.transcribe(audioData, options)
println("Transcript: ${result.transcript}")
```

### 3. Use Whisper-Specific Features

```kotlin
// Get the WhisperKit service directly for advanced features
val whisperService = WhisperKitFactory.createService()

// Use Whisper-specific model types
whisperService.initializeWithWhisperModel(WhisperModelType.LARGE_V3)

// Use Whisper-specific options
val whisperOptions = WhisperTranscriptionOptions(
    language = "auto",
    temperature = 0.3f,
    initialPrompt = "Technical discussion about AI"
)

// Get Whisper-specific result with segments
val whisperResult = whisperService.transcribeWithWhisperOptions(
    audioData,
    whisperOptions
)

// Access Whisper-specific metadata
whisperResult.segments.forEach { segment ->
    println("${segment.start}s - ${segment.end}s: ${segment.text}")
}
```

## Platform Implementations

- **JVM**: Uses WhisperJNI for desktop/server applications
- **Android**: Uses WhisperJNI with Android-specific context
- **iOS**: (Future) Will bridge to native WhisperKit

## Design Principles

1. **Generic First**: Always extend generic interfaces from the main SDK
2. **Type Safety**: Use strongly-typed models for Whisper-specific features
3. **Seamless Integration**: Works transparently with SDK's STT components
4. **Extensibility**: Other STT providers can follow the same pattern

## Adding New STT Providers

To add a new STT provider (e.g., OpenAI Whisper API, Google Speech-to-Text), follow this pattern:

1. Create a new module (e.g., `runanywhere-googlest`)
2. Implement `STTService` interface
3. Create a provider implementing `STTServiceProvider`
4. Register with `ModuleRegistry`

This ensures all STT solutions work seamlessly with the SDK's generic interfaces while allowing provider-specific extensions.
