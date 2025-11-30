# Flutter SDK Integration TODOs

This document tracks all placeholder/TODO items in the Flutter example app that need to be connected to the actual RunAnywhere Flutter SDK when those features become available.

## Overview

The Flutter example app UI is complete and mirrors the iOS example app. The Flutter SDK now has **full API parity** with the iOS SDK for LLM, STT, and TTS components. However, native inference requires FFI bindings from `runanywhere-core`.

---

## SDK API Status (Updated)

### Now Available in Flutter SDK

| API | Status | Notes |
|-----|--------|-------|
| `RunAnywhere.initialize()` | ✅ Available | Full initialization with apiKey, baseURL, environment |
| `RunAnywhere.isSDKInitialized` | ✅ Available | Check initialization state |
| `RunAnywhere.loadModel()` | ✅ Available | Load LLM model by ID |
| `RunAnywhere.loadSTTModel()` | ✅ Available | Load STT model and get component |
| `RunAnywhere.loadTTSModel()` | ✅ Available | Load TTS model and get component |
| `RunAnywhere.loadedSTTComponent` | ✅ Available | Get loaded STT component |
| `RunAnywhere.loadedTTSComponent` | ✅ Available | Get loaded TTS component |
| `RunAnywhere.generate()` | ✅ Available | Text generation with options |
| `RunAnywhere.generateStream()` | ✅ Available | Streaming text generation |
| `RunAnywhere.transcribe()` | ✅ Available | Simple transcription |
| `RunAnywhere.currentModel` | ✅ Available | Get current loaded model |
| `RunAnywhere.availableModels()` | ✅ Available | List available models |
| `RunAnywhere.conversation()` | ✅ Available | Create conversation manager |
| `STTComponent` | ✅ Available | Full STT component with batch & stream |
| `TTSComponent` | ✅ Available | Full TTS component with SystemTTS fallback |
| `LLMComponent` | ✅ Available | Full LLM component |
| `Message`, `Context` | ✅ Available | Conversation models |
| `STTMode` | ✅ Available | batch / live transcription modes |

### Pending (Requires FFI Bindings)

| Feature | Status | Notes |
|---------|--------|-------|
| Native LLM inference | ⏳ Pending | Needs llama.cpp FFI bindings |
| Native STT inference | ⏳ Pending | Needs Whisper FFI bindings |
| Native TTS inference | ⏳ Optional | SystemTTS fallback available |

See [FFI_BINDINGS.md](../../../sdk/runanywhere-flutter/FFI_BINDINGS.md) for FFI requirements.

---

## Chat Feature

### [chat_interface_view.dart](lib/features/chat/chat_interface_view.dart)

| Line | TODO | Priority | SDK Status |
|------|------|----------|------------|
| 143 | Use RunAnywhere.generateStream with thinking support | High | ✅ API Available |
| 314 | Load model via RunAnywhere SDK | High | ✅ Use `RunAnywhere.loadModel()` |
| 325 | Get actual framework from ModelManager when SDK provides it | Medium | ✅ Available via `LLMConfiguration.preferredFramework` |

**Integration Example:**
```dart
// Load model
await RunAnywhere.loadModel('llama-3.2-1b');

// Generate with streaming
await for (final token in RunAnywhere.generateStream(prompt)) {
  // Handle each token
}
```

---

## Speech-to-Text (STT) Feature

### [speech_to_text_view.dart](lib/features/voice/speech_to_text_view.dart)

| Line | TODO | Priority | SDK Status |
|------|------|----------|------------|
| 120 | Load STT model via RunAnywhere SDK | High | ✅ Use `RunAnywhere.loadSTTModel()` |
| 127 | Check if model supports live mode via SDK | Medium | ✅ Use `sttComponent.supportsStreaming` |
| 170 | Implement live transcription via RunAnywhere SDK | High | ✅ Use `sttComponent.liveTranscribe()` |
| 174 | Implement batch recording | High | ✅ Use `sttComponent.transcribe()` |
| 194 | Transcribe recorded audio via RunAnywhere SDK | High | ✅ Use `sttComponent.transcribe()` |
| 268 | Implement clipboard copy | Low | Flutter platform code |
| 530 | Add metadata display when SDK provides it | Low | ✅ Available via `STTOutput.metadata` |

**Integration Example:**
```dart
// Load STT model
await RunAnywhere.loadSTTModel('whisper-base');
final sttComponent = RunAnywhere.loadedSTTComponent!;

// Check mode support
final mode = sttComponent.supportsStreaming ? STTMode.live : STTMode.batch;

// Batch transcription
final result = await sttComponent.transcribe(audioData);
print('Transcript: ${result.text}');
print('Confidence: ${result.confidence}');
print('Processing time: ${result.metadata.processingTime}s');

// Live transcription
await for (final text in sttComponent.liveTranscribe(audioStream)) {
  print('Partial: $text');
}
```

---

## Text-to-Speech (TTS) Feature

### [text_to_speech_view.dart](lib/features/voice/text_to_speech_view.dart)

| Line | TODO | Priority | SDK Status |
|------|------|----------|------------|
| 100 | Load TTS model via RunAnywhere SDK | High | ✅ Use `RunAnywhere.loadTTSModel()` |
| 134 | Generate speech via RunAnywhere SDK | High | ✅ Use `ttsComponent.synthesize()` |

**Integration Example:**
```dart
// Load TTS (uses system TTS by default)
await RunAnywhere.loadTTSModel('system');
final ttsComponent = RunAnywhere.loadedTTSComponent!;

// Synthesize speech
final output = await ttsComponent.synthesize(
  'Hello, world!',
  language: 'en-US',
);

// Play audio
final audioData = output.audioData;
print('Duration: ${output.duration}s');

// Stream synthesis for long text
await for (final chunk in ttsComponent.streamSynthesize(longText)) {
  // Play each chunk
}
```

---

## Voice Assistant Feature

### [voice_assistant_view.dart](lib/features/voice/voice_assistant_view.dart)

| Line | TODO | Priority | SDK Status |
|------|------|----------|------------|
| 74 | Subscribe to model lifecycle via RunAnywhere SDK | Medium | ✅ Use `RunAnywhere.events` |
| 92 | Create ModularVoicePipeline via RunAnywhere SDK | High | ✅ `VoiceAgentComponent` available |

**Integration Example:**
```dart
// Subscribe to events
RunAnywhere.events.modelEvents.listen((event) {
  if (event is SDKModelLoadCompleted) {
    print('Model loaded: ${event.modelId}');
  }
});

// Voice Agent (VAD → STT → LLM → TTS pipeline)
// Available in SDK - VoiceAgentComponent orchestrates the full pipeline
```

---

## Settings & Storage

### [combined_settings_view.dart](lib/features/settings/combined_settings_view.dart)

| Line | TODO | Priority | SDK Status |
|------|------|----------|------------|
| 81 | Get storage info via RunAnywhere SDK | Medium | ⏳ Pending |
| 116 | Clear cache via RunAnywhere SDK | Medium | ⏳ Pending |
| 127 | Clean temp files via RunAnywhere SDK | Medium | ⏳ Pending |

**Notes:**
- Storage APIs not yet implemented in SDK
- Can use platform file system APIs as workaround

---

## Model Manager

### [model_manager.dart](lib/core/services/model_manager.dart)

| Line | TODO | Priority | SDK Status |
|------|------|----------|------------|
| 52 | Implement unload in SDK | Medium | ⏳ Pending |
| 84 | Implement proper model loaded check via SDK | High | ✅ Use `RunAnywhere.currentModel != null` |

---

## App Initialization

### [runanywhere_ai_app.dart](lib/app/runanywhere_ai_app.dart)

| Line | TODO | Priority | SDK Status |
|------|------|----------|------------|
| 57 | Load actual API key from secure storage | Medium | ✅ SDK handles via KeychainManager |

**Integration Example:**
```dart
await RunAnywhere.initialize(
  apiKey: 'your-api-key',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.development,
);
```

---

## SDK Data Models (Now Available)

### Conversation Models
```dart
// Message with role
final message = Message(
  role: MessageRole.user,
  content: 'Hello!',
);

// Or use convenience constructors
final userMsg = Message.user('Hello!');
final assistantMsg = Message.assistant('Hi there!');
final systemMsg = Message.system('You are a helpful assistant.');

// Context for conversation
final context = Context(
  systemPrompt: 'You are helpful.',
  messages: [userMsg],
  maxMessages: 100,
);
```

### Generation Models
```dart
// LLM Output
final output = await llmComponent.generate('Hello');
print('Text: ${output.text}');
print('Tokens: ${output.tokenUsage.totalTokens}');
print('Generation time: ${output.metadata.generationTime}s');
print('Finish reason: ${output.finishReason}');
```

### STT Models
```dart
// STT Output
final sttOutput = await sttComponent.transcribe(audioData);
print('Text: ${sttOutput.text}');
print('Confidence: ${sttOutput.confidence}');
print('Word timestamps: ${sttOutput.wordTimestamps}');
print('Real-time factor: ${sttOutput.metadata.realTimeFactor}');
```

### TTS Models
```dart
// TTS Output
final ttsOutput = await ttsComponent.synthesize('Hello');
print('Audio data: ${ttsOutput.audioData.length} bytes');
print('Duration: ${ttsOutput.duration}s');
print('Voice: ${ttsOutput.metadata.voice}');
```

---

## Implementation Priority (Updated)

### Ready to Integrate
1. **LLM Generation** - `RunAnywhere.generate()`, `generateStream()`
2. **STT Transcription** - `RunAnywhere.loadSTTModel()`, `sttComponent.transcribe()`
3. **TTS Synthesis** - `RunAnywhere.loadTTSModel()`, `ttsComponent.synthesize()`
4. **Model Loading** - `RunAnywhere.loadModel()`
5. **Event Subscription** - `RunAnywhere.events`

### Pending FFI Bindings
1. Native LLM inference (llama.cpp)
2. Native STT inference (Whisper)
3. Native TTS inference (ONNX)

### Future Enhancements
1. Storage management APIs
2. Model download progress
3. Model unloading

---

## Notes

- All UI components are complete and match iOS parity
- Flutter SDK now has **full API parity** with iOS SDK
- Native inference requires FFI bindings from `runanywhere-core`
- SystemTTS fallback available for TTS (no FFI needed)
- Energy-based VAD available (no FFI needed)
- State management uses Provider + ChangeNotifier pattern
