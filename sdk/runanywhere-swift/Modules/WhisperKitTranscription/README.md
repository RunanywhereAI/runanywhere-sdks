# WhisperKitTranscription Module

Swift Package module providing WhisperKit speech-to-text integration for RunAnywhere SDK.

## Features

- Automatic speech recognition using WhisperKit
- Support for multiple Whisper model sizes (tiny, base, small, medium, large)
- Streaming transcription support
- Garbled output detection and filtering
- Smart caching with 5-minute timeout
- Custom download strategy for multi-file CoreML models
- Memory-efficient audio processing

## Installation

Add this module as a Swift Package dependency:

```swift
dependencies: [
    .package(path: "sdk/runanywhere-swift/Modules/WhisperKitTranscription")
]
```

## Usage

```swift
import WhisperKitTranscription
import RunAnywhereSDK

// Register the adapter (handles transcription)
RunAnywhereSDK.shared.registerFrameworkAdapter(WhisperKitAdapter.shared)

// Register the download strategy (handles model downloads)
RunAnywhereSDK.shared.registerDownloadStrategy(WhisperKitDownloadStrategy())

// That's it! The SDK will automatically use WhisperKit for transcription
```

## Components

### WhisperKitService
Core transcription service implementing the `VoiceService` protocol from RunAnywhereSDK.

Features:
- Audio sample processing and validation
- Adaptive noise threshold for different audio lengths
- Garbled output detection (lines 435-477)
- Audio padding for short samples
- Streaming transcription with context overlap

### WhisperKitAdapter
Framework adapter implementing the `UnifiedFrameworkAdapter` protocol.

Features:
- Singleton pattern for service caching
- 5-minute cache timeout for memory efficiency
- Automatic cleanup of stale services
- Force cleanup on memory warnings

### WhisperKitDownloadStrategy
Custom download strategy for WhisperKit models from HuggingFace.

Features:
- Multi-file CoreML model download support
- Progress tracking for all model files
- Automatic directory structure creation
- 404 handling for optional model files

### VoiceError
Error types for voice service operations:
- `serviceNotInitialized`: Service not ready for transcription
- `modelNotFound`: Requested model not available
- `transcriptionFailed`: Transcription operation failed
- `insufficientMemory`: Not enough memory for operation
- `unsupportedAudioFormat`: Audio format not supported

## Model Support

Supported WhisperKit models:
- `whisper-tiny` (39MB) - Fastest, least accurate
- `whisper-base` (74MB) - Good balance
- `whisper-small` (244MB) - Better accuracy
- `whisper-medium` - High accuracy
- `whisper-large` - Best accuracy

## Requirements

- iOS 13.0+ / macOS 11.0+ / tvOS 13.0+ / watchOS 6.0+
- WhisperKit 0.10.2+
- RunAnywhereSDK

## Memory Management

The module includes smart memory management:
- Automatic cache cleanup after 5 minutes of inactivity
- Force cleanup available via `WhisperKitAdapter.shared.forceCleanup()`
- Efficient audio buffer management for streaming

## Integration Notes

- The adapter uses a singleton pattern to ensure proper caching
- Download strategy must be registered separately for model downloads
- Service initialization is lazy and happens on first use
- Logger uses subsystem: `com.runanywhere.whisperkit`
