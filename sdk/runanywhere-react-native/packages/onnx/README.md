# @runanywhere/onnx

ONNX Runtime backend for the RunAnywhere React Native SDK. Provides on-device Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) powered by Sherpa-ONNX.

---

## Overview

`@runanywhere/onnx` provides the ONNX Runtime backend for on-device voice AI capabilities:

### Speech-to-Text (STT)
- **Whisper Models** — Multi-language speech recognition
- **Batch Transcription** — Transcribe audio files
- **Real-time Streaming** — Live transcription support
- **Word Timestamps** — Precise timing information
- **Confidence Scores** — Per-segment reliability metrics

### Text-to-Speech (TTS)
- **Piper TTS** — Natural neural voice synthesis
- **Multiple Voices** — Various languages and accents
- **Customizable** — Speed, pitch, and volume control
- **Streaming Output** — Chunked audio generation

### Voice Activity Detection (VAD)
- **Silero VAD** — High-accuracy speech detection
- **Real-time Processing** — Low-latency audio analysis
- **Configurable Sensitivity** — Adjustable thresholds

---

## Requirements

- `@runanywhere/core` (peer dependency)
- React Native 0.71+
- iOS 15.1+ / Android API 24+
- Microphone permission (for live recording)

---

## Installation

```bash
npm install @runanywhere/core @runanywhere/onnx
# or
yarn add @runanywhere/core @runanywhere/onnx
```

### iOS Setup

```bash
cd ios && pod install && cd ..
```

Add microphone permission to `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for speech recognition</string>
```

### Android Setup

Add microphone permission to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## Quick Start

```typescript
import { RunAnywhere, SDKEnvironment, ModelCategory } from '@runanywhere/core';
import { ONNX, ModelArtifactType } from '@runanywhere/onnx';

// 1. Initialize SDK
await RunAnywhere.initialize({
  environment: SDKEnvironment.Development,
});

// 2. Register ONNX backend
ONNX.register();

// 3. Add STT model (Whisper)
await ONNX.addModel({
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (English)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.SpeechRecognition,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 75_000_000,
});

// 4. Add TTS model (Piper)
await ONNX.addModel({
  id: 'vits-piper-en_US-lessac-medium',
  name: 'Piper TTS (US English)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
  modality: ModelCategory.SpeechSynthesis,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 65_000_000,
});

// 5. Download models
await RunAnywhere.downloadModel('sherpa-onnx-whisper-tiny.en');
await RunAnywhere.downloadModel('vits-piper-en_US-lessac-medium');

// 6. Load STT model
const sttModel = await RunAnywhere.getModelInfo('sherpa-onnx-whisper-tiny.en');
await RunAnywhere.loadSTTModel(sttModel.localPath, 'whisper');

// 7. Transcribe audio
const result = await RunAnywhere.transcribeFile(audioFilePath, {
  language: 'en',
});
console.log('Transcription:', result.text);

// 8. Load TTS model
const ttsModel = await RunAnywhere.getModelInfo('vits-piper-en_US-lessac-medium');
await RunAnywhere.loadTTSModel(ttsModel.localPath, 'piper');

// 9. Synthesize speech
const audio = await RunAnywhere.synthesize('Hello world.', {
  rate: 1.0,
  pitch: 1.0,
});
console.log('Audio duration:', audio.duration, 'seconds');
```

---

## API Reference

### ONNX Module

```typescript
import { ONNX, ModelArtifactType } from '@runanywhere/onnx';
```

#### `ONNX.register()`

Register the ONNX backend with the SDK. Must be called before using STT/TTS features.

```typescript
ONNX.register(): void
```

**Example:**

```typescript
await RunAnywhere.initialize({ ... });
ONNX.register();  // Now STT/TTS features are available
```

---

#### `ONNX.addModel(options)`

Add an ONNX model (STT or TTS) to the model registry.

```typescript
await ONNX.addModel(options: ONNXModelOptions): Promise<ModelInfo>
```

**Parameters:**

```typescript
interface ONNXModelOptions {
  /**
   * Unique model ID.
   * If not provided, generated from the URL filename.
   */
  id?: string;

  /** Display name for the model */
  name: string;

  /** Download URL for the model */
  url: string;

  /**
   * Model category.
   * Required: ModelCategory.SpeechRecognition or ModelCategory.SpeechSynthesis
   */
  modality: ModelCategory;

  /**
   * How the model is packaged.
   * If not provided, inferred from URL extension.
   */
  artifactType?: ModelArtifactType;

  /** Memory requirement in bytes */
  memoryRequirement?: number;
}

enum ModelArtifactType {
  SingleFile = 'singleFile',      // Single .onnx file
  TarGzArchive = 'tarGzArchive',  // .tar.gz archive
  TarBz2Archive = 'tarBz2Archive', // .tar.bz2 archive
  ZipArchive = 'zipArchive',      // .zip archive
}
```

**Returns:** `Promise<ModelInfo>` — The registered model info

**Example:**

```typescript
// STT Model (Whisper)
await ONNX.addModel({
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (English)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.SpeechRecognition,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 75_000_000,
});

// Larger STT Model
await ONNX.addModel({
  id: 'sherpa-onnx-whisper-small.en',
  name: 'Sherpa Whisper Small (English)',
  url: 'https://github.com/k2-fsa/sherpa-onnx/releases/.../sherpa-onnx-whisper-small.en.tar.bz2',
  modality: ModelCategory.SpeechRecognition,
  artifactType: ModelArtifactType.TarBz2Archive,
  memoryRequirement: 250_000_000,
});

// TTS Model (Piper)
await ONNX.addModel({
  id: 'vits-piper-en_US-lessac-medium',
  name: 'Piper TTS (US English - Lessac)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../vits-piper-en_US-lessac-medium.tar.gz',
  modality: ModelCategory.SpeechSynthesis,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 65_000_000,
});
```

---

#### Module Properties

```typescript
ONNX.moduleId        // 'onnx'
ONNX.moduleName      // 'ONNX Runtime'
ONNX.inferenceFramework  // LLMFramework.ONNX
ONNX.capabilities    // ['stt', 'tts']
ONNX.defaultPriority // 100
```

---

### Speech-to-Text API

Use the `RunAnywhere` API for STT operations:

#### Load STT Model

```typescript
await RunAnywhere.loadSTTModel(
  modelPath: string,
  modelType?: string  // 'whisper' (default)
): Promise<boolean>
```

#### Check Model Status

```typescript
const isLoaded = await RunAnywhere.isSTTModelLoaded(): Promise<boolean>
```

#### Unload Model

```typescript
await RunAnywhere.unloadSTTModel(): Promise<void>
```

#### Transcribe Audio File

```typescript
const result = await RunAnywhere.transcribeFile(
  audioPath: string,
  options?: STTOptions
): Promise<STTResult>
```

**STT Options:**

```typescript
interface STTOptions {
  language?: string;        // e.g., 'en', 'es', 'fr'
  punctuation?: boolean;    // Enable punctuation
  diarization?: boolean;    // Enable speaker diarization
  wordTimestamps?: boolean; // Enable word-level timestamps
  sampleRate?: number;      // Audio sample rate
}
```

**STT Result:**

```typescript
interface STTResult {
  text: string;              // Full transcription
  segments: STTSegment[];    // Segments with timing
  language?: string;         // Detected language
  confidence: number;        // Overall confidence (0-1)
  duration: number;          // Audio duration in seconds
  alternatives: STTAlternative[];
}

interface STTSegment {
  text: string;
  startTime: number;  // seconds
  endTime: number;    // seconds
  confidence: number;
}
```

#### Transcribe Raw Audio

```typescript
// From base64-encoded audio
const result = await RunAnywhere.transcribe(
  audioData: string,  // base64 float32 PCM
  options?: STTOptions
): Promise<STTResult>

// From float32 samples
const result = await RunAnywhere.transcribeBuffer(
  samples: number[],
  sampleRate: number,
  options?: STTOptions
): Promise<STTResult>
```

---

### Text-to-Speech API

Use the `RunAnywhere` API for TTS operations:

#### Load TTS Model

```typescript
await RunAnywhere.loadTTSModel(
  modelPath: string,
  modelType?: string  // 'piper' (default)
): Promise<boolean>
```

#### Check Model Status

```typescript
const isLoaded = await RunAnywhere.isTTSModelLoaded(): Promise<boolean>
```

#### Unload Model

```typescript
await RunAnywhere.unloadTTSModel(): Promise<void>
```

#### Synthesize Speech

```typescript
const result = await RunAnywhere.synthesize(
  text: string,
  options?: TTSConfiguration
): Promise<TTSResult>
```

**TTS Configuration:**

```typescript
interface TTSConfiguration {
  voice?: string;   // Voice identifier
  rate?: number;    // Speed (0.5-2.0, default: 1.0)
  pitch?: number;   // Pitch (0.5-2.0, default: 1.0)
  volume?: number;  // Volume (0.0-1.0, default: 1.0)
}
```

**TTS Result:**

```typescript
interface TTSResult {
  audio: string;      // Base64-encoded float32 PCM
  sampleRate: number; // Audio sample rate (typically 22050)
  numSamples: number; // Total sample count
  duration: number;   // Duration in seconds
}
```

#### Streaming Synthesis

```typescript
await RunAnywhere.synthesizeStream(
  text: string,
  options?: TTSConfiguration,
  onChunk?: (chunk: TTSOutput) => void
): Promise<TTSResult>
```

#### System TTS (Platform Native)

```typescript
// Speak using AVSpeechSynthesizer (iOS) or Android TTS
await RunAnywhere.speak(text: string, options?: TTSConfiguration): Promise<void>

// Control playback
const isSpeaking = await RunAnywhere.isSpeaking(): Promise<boolean>
await RunAnywhere.stopSpeaking(): Promise<void>

// List available voices
const voices = await RunAnywhere.availableTTSVoices(): Promise<TTSVoiceInfo[]>
```

---

### Voice Activity Detection API

#### Initialize VAD

```typescript
await RunAnywhere.initializeVAD(config?: VADConfiguration): Promise<boolean>
```

**VAD Configuration:**

```typescript
interface VADConfiguration {
  energyThreshold?: number;   // Speech detection threshold
  sampleRate?: number;        // Audio sample rate
  frameLength?: number;       // Frame length in ms
  autoCalibration?: boolean;  // Enable auto-calibration
}
```

#### Load VAD Model

```typescript
await RunAnywhere.loadVADModel(modelPath: string): Promise<boolean>
```

#### Process Audio

```typescript
const result = await RunAnywhere.processVAD(
  audioSamples: number[]
): Promise<VADResult>
```

**VAD Result:**

```typescript
interface VADResult {
  isSpeech: boolean;    // Whether speech is detected
  confidence: number;   // Confidence score (0-1)
  startTime?: number;   // Speech segment start
  endTime?: number;     // Speech segment end
}
```

#### Continuous VAD

```typescript
// Start/stop continuous processing
await RunAnywhere.startVAD(): Promise<void>
await RunAnywhere.stopVAD(): Promise<void>

// Set callbacks
RunAnywhere.setVADSpeechActivityCallback((event) => {
  if (event.type === 'speechStarted') {
    console.log('Speech started');
  } else if (event.type === 'speechEnded') {
    console.log('Speech ended');
  }
});
```

---

## Supported Models

### Speech-to-Text (Whisper)

| Model | Size | Memory | Languages | Description |
|-------|------|--------|-----------|-------------|
| whisper-tiny.en | ~75MB | 100MB | English | Fastest, English-only |
| whisper-base.en | ~150MB | 200MB | English | Better accuracy |
| whisper-small.en | ~250MB | 350MB | English | High quality |
| whisper-tiny | ~75MB | 100MB | 99+ | Multilingual |

### Text-to-Speech (Piper)

| Voice | Size | Language | Description |
|-------|------|----------|-------------|
| en_US-lessac-medium | ~65MB | English (US) | Natural, clear |
| en_US-amy-medium | ~65MB | English (US) | Female voice |
| en_GB-alba-medium | ~65MB | English (UK) | British accent |
| de_DE-thorsten-medium | ~65MB | German | German voice |
| es_ES-mls-medium | ~65MB | Spanish | Spanish voice |
| fr_FR-siwis-medium | ~65MB | French | French voice |

### Voice Activity Detection

| Model | Size | Description |
|-------|------|-------------|
| silero-vad | ~2MB | High accuracy, real-time |

---

## Usage Examples

### Complete STT Example

```typescript
import { RunAnywhere, SDKEnvironment, ModelCategory } from '@runanywhere/core';
import { ONNX, ModelArtifactType } from '@runanywhere/onnx';

async function transcribeAudio(audioPath: string): Promise<string> {
  // Initialize
  await RunAnywhere.initialize({ environment: SDKEnvironment.Development });
  ONNX.register();

  // Add model
  await ONNX.addModel({
    id: 'whisper-tiny-en',
    name: 'Whisper Tiny English',
    url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../sherpa-onnx-whisper-tiny.en.tar.gz',
    modality: ModelCategory.SpeechRecognition,
    artifactType: ModelArtifactType.TarGzArchive,
  });

  // Download if needed
  if (!(await RunAnywhere.isModelDownloaded('whisper-tiny-en'))) {
    await RunAnywhere.downloadModel('whisper-tiny-en', (p) => {
      console.log(`Download: ${(p.progress * 100).toFixed(1)}%`);
    });
  }

  // Load and transcribe
  const model = await RunAnywhere.getModelInfo('whisper-tiny-en');
  await RunAnywhere.loadSTTModel(model.localPath, 'whisper');

  const result = await RunAnywhere.transcribeFile(audioPath, {
    language: 'en',
    wordTimestamps: true,
  });

  console.log('Transcription:', result.text);
  console.log('Confidence:', result.confidence);
  console.log('Duration:', result.duration, 'seconds');

  return result.text;
}
```

### Complete TTS Example

```typescript
async function synthesizeSpeech(text: string): Promise<string> {
  // Initialize
  await RunAnywhere.initialize({ environment: SDKEnvironment.Development });
  ONNX.register();

  // Add model
  await ONNX.addModel({
    id: 'piper-lessac',
    name: 'Piper Lessac Voice',
    url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../vits-piper-en_US-lessac-medium.tar.gz',
    modality: ModelCategory.SpeechSynthesis,
    artifactType: ModelArtifactType.TarGzArchive,
  });

  // Download if needed
  if (!(await RunAnywhere.isModelDownloaded('piper-lessac'))) {
    await RunAnywhere.downloadModel('piper-lessac');
  }

  // Load and synthesize
  const model = await RunAnywhere.getModelInfo('piper-lessac');
  await RunAnywhere.loadTTSModel(model.localPath, 'piper');

  const result = await RunAnywhere.synthesize(text, {
    rate: 1.0,
    pitch: 1.0,
    volume: 0.8,
  });

  console.log('Duration:', result.duration, 'seconds');
  console.log('Sample rate:', result.sampleRate);

  // result.audio is base64-encoded float32 PCM
  return result.audio;
}
```

### Voice Pipeline (STT → TTS)

```typescript
async function voiceEcho(audioPath: string): Promise<string> {
  // Transcribe input audio
  const transcription = await RunAnywhere.transcribeFile(audioPath);
  console.log('You said:', transcription.text);

  // Synthesize echo
  const audio = await RunAnywhere.synthesize(
    `You said: ${transcription.text}`
  );

  return audio.audio;
}
```

---

## Native Integration

### iOS

This package uses `RABackendONNX.xcframework` which includes:
- ONNX Runtime compiled for iOS
- Sherpa-ONNX (Whisper, Piper, Silero VAD)
- Optimized for Apple Silicon

Dependencies:
- `onnxruntime.xcframework` — ONNX Runtime core

### Android

Native libraries include:
- `librunanywhere_onnx.so` — ONNX backend
- `libonnxruntime.so` — ONNX Runtime
- `libsherpa-onnx-*.so` — Sherpa-ONNX libraries

---

## Package Structure

```
packages/onnx/
├── src/
│   ├── index.ts                # Package exports
│   ├── ONNX.ts                 # Module API (register, addModel)
│   ├── ONNXProvider.ts         # Service provider
│   ├── native/
│   │   └── NativeRunAnywhereONNX.ts
│   └── specs/
│       └── RunAnywhereONNX.nitro.ts
├── cpp/
│   ├── HybridRunAnywhereONNX.cpp
│   ├── HybridRunAnywhereONNX.hpp
│   └── bridges/
├── ios/
│   ├── RunAnywhereONNX.podspec
│   └── Frameworks/
│       ├── RABackendONNX.xcframework
│       └── onnxruntime.xcframework
├── android/
│   ├── build.gradle
│   └── src/main/jniLibs/
│       └── arm64-v8a/
│           ├── librunanywhere_onnx.so
│           ├── libonnxruntime.so
│           └── libsherpa-onnx-*.so
└── nitrogen/
    └── generated/
```

---

## Troubleshooting

### STT model fails to load

**Symptoms:** `modelLoadFailed` error when loading STT model

**Solutions:**
1. Verify the model directory contains all required files
2. Check that archive extraction completed successfully
3. Ensure the correct model type is specified ('whisper')

### Poor transcription quality

**Symptoms:** Transcription has many errors

**Solutions:**
1. Use a larger model (small instead of tiny)
2. Ensure audio is clear with minimal background noise
3. Check audio sample rate matches model expectations
4. Try specifying the language explicitly

### TTS audio is silent or distorted

**Symptoms:** No sound or garbled audio

**Solutions:**
1. Verify audio data is being decoded correctly
2. Check sample rate matches playback device
3. Ensure volume is not zero
4. Try a different TTS voice

### Permission denied (microphone)

**Symptoms:** Audio recording fails

**Solutions:**
1. Add microphone permission to Info.plist (iOS)
2. Add RECORD_AUDIO permission to AndroidManifest.xml
3. Request runtime permission before recording

---

## See Also

- [Main SDK README](../../README.md) — Full SDK documentation
- [API Reference](../../Docs/Documentation.md) — Complete API docs
- [@runanywhere/core](../core/README.md) — Core SDK
- [@runanywhere/llamacpp](../llamacpp/README.md) — LLM backend
- [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) — Underlying engine
- [ONNX Runtime](https://onnxruntime.ai/) — ONNX inference engine

---

## License

MIT License
