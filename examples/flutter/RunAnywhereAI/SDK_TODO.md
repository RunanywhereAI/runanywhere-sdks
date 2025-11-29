# Flutter SDK Integration TODOs

This document tracks all placeholder/TODO items in the Flutter example app that need to be connected to the actual RunAnywhere Flutter SDK when those features become available.

## Overview

The Flutter example app UI is complete and mirrors the iOS example app. However, many SDK features are simulated with placeholders until the Flutter SDK implements them.

---

## Chat Feature

### [chat_interface_view.dart](lib/features/chat/chat_interface_view.dart)

| Line | TODO | Priority |
|------|------|----------|
| 143 | Use RunAnywhere.generateStream with thinking support | High |
| 314 | Load model via RunAnywhere SDK | High |
| 325 | Get actual framework from ModelManager when SDK provides it | Medium |

**Notes:**
- Chat streaming is currently functional via `RunAnywhere.generateStream()`
- Model loading needs proper SDK integration for framework detection
- Thinking content support needs streaming API updates

---

## Speech-to-Text (STT) Feature

### [speech_to_text_view.dart](lib/features/voice/speech_to_text_view.dart)

| Line | TODO | Priority |
|------|------|----------|
| 120 | Load STT model via RunAnywhere SDK | High |
| 127 | Check if model supports live mode via SDK | Medium |
| 170 | Implement live transcription via RunAnywhere SDK | High |
| 174 | Implement batch recording | High |
| 194 | Transcribe recorded audio via RunAnywhere SDK | High |
| 268 | Implement clipboard copy | Low |
| 530 | Add metadata display when SDK provides it | Low |

**Notes:**
- STT component needs: `STTComponent`, `TranscriptionService`
- Audio recording is available via `record` package - needs connection to SDK
- Live mode requires streaming transcription API
- Batch mode needs audio buffer + transcribe method

---

## Text-to-Speech (TTS) Feature

### [text_to_speech_view.dart](lib/features/voice/text_to_speech_view.dart)

| Line | TODO | Priority |
|------|------|----------|
| 100 | Load TTS model via RunAnywhere SDK | High |
| 134 | Generate speech via RunAnywhere SDK | High |

**Notes:**
- TTS component needs: `TTSComponent`, `TTSConfiguration`
- Expected API: `await ttsComponent.synthesize(text, language: 'en-US')`
- Audio playback can use `audioplayers` or `just_audio` package

---

## Voice Assistant Feature

### [voice_assistant_view.dart](lib/features/voice/voice_assistant_view.dart)

| Line | TODO | Priority |
|------|------|----------|
| 74 | Subscribe to model lifecycle via RunAnywhere SDK | Medium |
| 92 | Create ModularVoicePipeline via RunAnywhere SDK | High |

**Notes:**
- Needs: `ModularVoicePipeline`, `VoicePipelineConfiguration`
- Pipeline orchestrates: VAD → STT → LLM → TTS
- Model lifecycle subscription for state tracking

---

## Settings & Storage

### [combined_settings_view.dart](lib/features/settings/combined_settings_view.dart)

| Line | TODO | Priority |
|------|------|----------|
| 81 | Get storage info via RunAnywhere SDK | Medium |
| 116 | Clear cache via RunAnywhere SDK | Medium |
| 127 | Clean temp files via RunAnywhere SDK | Medium |

**Notes:**
- Storage API: `RunAnywhere.getStorageInfo()`, `clearCache()`, `cleanTempFiles()`
- Need to query downloaded models, cache sizes

---

## Model Manager

### [model_manager.dart](lib/core/services/model_manager.dart)

| Line | TODO | Priority |
|------|------|----------|
| 52 | Implement unload in SDK | Medium |
| 84 | Implement proper model loaded check via SDK | High |

**Notes:**
- Need: `RunAnywhere.unloadModel()`, `RunAnywhere.isModelLoaded`
- Current implementation uses stub values

---

## App Initialization

### [runanywhere_ai_app.dart](lib/app/runanywhere_ai_app.dart)

| Line | TODO | Priority |
|------|------|----------|
| 57 | Load actual API key from secure storage | Medium |

**Notes:**
- API key is stored via `flutter_secure_storage`
- Need to load and pass to `RunAnywhere.initialize()`

---

## SDK API Wishlist

Based on the TODOs above, the Flutter SDK needs these APIs:

### Core
```dart
// Initialization
RunAnywhere.initialize(apiKey: String, baseURL: String, environment: Environment)
RunAnywhere.isInitialized: bool

// Model Management
RunAnywhere.loadModel(modelId: String): Future<void>
RunAnywhere.unloadModel(modelId: String): Future<void>
RunAnywhere.isModelLoaded: bool
RunAnywhere.currentModel: ModelInfo?
RunAnywhere.availableModels(): Future<List<ModelInfo>>
RunAnywhere.downloadModel(modelId: String, onProgress: (double)): Future<void>
```

### STT Component
```dart
class STTComponent {
  Future<void> initialize()
  Future<TranscriptionResult> transcribe(Uint8List audioData)
  Stream<TranscriptionUpdate> transcribeStream(Stream<Uint8List> audioStream)
  bool get supportsLiveMode
}
```

### TTS Component
```dart
class TTSComponent {
  Future<void> initialize()
  Future<TTSOutput> synthesize(String text, {String language, double rate, double pitch})
}
```

### Voice Pipeline
```dart
class ModularVoicePipeline {
  Future<void> initialize(VoicePipelineConfiguration config)
  Future<void> startListening()
  Future<void> stopListening()
  Stream<VoicePipelineEvent> get events
}
```

### Storage
```dart
RunAnywhere.getStorageInfo(): Future<StorageInfo>
RunAnywhere.clearCache(): Future<void>
RunAnywhere.cleanTempFiles(): Future<void>
```

---

## Implementation Priority

1. **High Priority** - Core functionality
   - Model loading/unloading
   - STT transcription (batch + live)
   - TTS synthesis
   - Voice pipeline

2. **Medium Priority** - Enhanced features
   - Model lifecycle subscription
   - Framework detection
   - Storage management

3. **Low Priority** - Polish
   - Metadata display
   - Clipboard utilities
   - Analytics integration

---

## Notes

- All UI components are complete and match iOS parity
- Simulated behaviors use `Future.delayed()` and `Timer.periodic()`
- Audio recording infrastructure exists via `record` package
- State management uses Provider + ChangeNotifier pattern
