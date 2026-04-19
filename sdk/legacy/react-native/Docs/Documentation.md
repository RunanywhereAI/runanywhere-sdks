# RunAnywhere React Native SDK - API Reference

API documentation for the RunAnywhere React Native SDK.

---

## Table of Contents

- [Core API](#core-api)
  - [RunAnywhere](#runanywhere)
  - [Initialization](#initialization)
  - [Text Generation](#text-generation)
  - [Speech-to-Text](#speech-to-text)
  - [Text-to-Speech](#text-to-speech)
  - [Voice Activity Detection](#voice-activity-detection)
  - [Voice Agent](#voice-agent)
  - [Model Management](#model-management)
  - [Storage Management](#storage-management)
  - [Events](#events)
- [LlamaCPP Module](#llamacpp-module)
- [ONNX Module](#onnx-module)
- [Types Reference](#types-reference)
- [Error Reference](#error-reference)

---

## Core API

### RunAnywhere

The main SDK singleton providing all public methods.

```typescript
import { RunAnywhere } from '@runanywhere/core';
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isSDKInitialized` | `boolean` | Whether SDK core is initialized |
| `areServicesReady` | `boolean` | Whether all services are ready |
| `currentEnvironment` | `SDKEnvironment \| null` | Current SDK environment |
| `version` | `string` | SDK version string |
| `deviceId` | `string` | Cached device ID (sync) |
| `events` | `EventBus` | Event subscription system |

---

### Initialization

#### `RunAnywhere.initialize(options)`

Initialize the SDK. Must be called before any other API.

```typescript
await RunAnywhere.initialize(options: SDKInitOptions): Promise<void>
```

**Parameters:**

```typescript
interface SDKInitOptions {
  /** API key for authentication (production/staging) */
  apiKey?: string;

  /** Base URL for API requests */
  baseURL?: string;

  /** SDK environment */
  environment?: SDKEnvironment;

  /** Supabase project URL (development mode only) */
  supabaseURL?: string;

  /** Supabase anon key (development mode only) */
  supabaseKey?: string;

  /** Enable debug logging */
  debug?: boolean;
}

enum SDKEnvironment {
  Development = 'development',
  Staging = 'staging',
  Production = 'production',
}
```

**Returns:** `Promise<void>` - Resolves when initialization is complete

**Throws:** `SDKError` with codes:
- `alreadyInitialized` - SDK already initialized
- `nativeModuleNotAvailable` - Native module not linked
- `authenticationFailed` - Invalid API key (production)

**Example:**

```typescript
// Development mode (no API key needed)
await RunAnywhere.initialize({
  environment: SDKEnvironment.Development,
});

// Production mode
await RunAnywhere.initialize({
  apiKey: 'your-api-key',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.Production,
});
```

---

#### `RunAnywhere.isInitialized()`

Check if the SDK is initialized.

```typescript
await RunAnywhere.isInitialized(): Promise<boolean>
```

**Returns:** `Promise<boolean>` - `true` if SDK is initialized

**Example:**

```typescript
const isReady = await RunAnywhere.isInitialized();
if (!isReady) {
  await RunAnywhere.initialize({ ... });
}
```

---

#### `RunAnywhere.reset()`

Reset the SDK to uninitialized state. Unloads all models and clears state.

```typescript
await RunAnywhere.reset(): Promise<void>
```

**Example:**

```typescript
await RunAnywhere.reset();
// SDK can now be reinitialized with different options
```

---

#### `RunAnywhere.destroy()`

Destroy the SDK instance. Same as `reset()`.

```typescript
await RunAnywhere.destroy(): Promise<void>
```

---

### Text Generation

#### `RunAnywhere.loadModel(modelPath)`

Load an LLM model into memory.

```typescript
await RunAnywhere.loadModel(modelPath: string): Promise<boolean>
```

**Parameters:**
- `modelPath` - Absolute path to the model file (.gguf)

**Returns:** `Promise<boolean>` - `true` if model loaded successfully

**Throws:** `SDKError` with codes:
- `notInitialized` - SDK not initialized
- `modelNotFound` - Model file not found at path
- `modelLoadFailed` - Failed to load model (memory, format, etc.)

**Example:**

```typescript
const modelInfo = await RunAnywhere.getModelInfo('smollm2-360m-q8_0');
if (modelInfo?.localPath) {
  await RunAnywhere.loadModel(modelInfo.localPath);
}
```

---

#### `RunAnywhere.isModelLoaded()`

Check if an LLM model is currently loaded.

```typescript
await RunAnywhere.isModelLoaded(): Promise<boolean>
```

**Returns:** `Promise<boolean>` - `true` if a model is loaded

---

#### `RunAnywhere.unloadModel()`

Unload the currently loaded LLM model from memory.

```typescript
await RunAnywhere.unloadModel(): Promise<void>
```

**Example:**

```typescript
// Free memory when done
await RunAnywhere.unloadModel();
```

---

#### `RunAnywhere.chat(prompt)`

Simple chat interface. Returns just the response text.

```typescript
await RunAnywhere.chat(prompt: string): Promise<string>
```

**Parameters:**
- `prompt` - The user's message

**Returns:** `Promise<string>` - The generated response text

**Throws:** `SDKError` with codes:
- `notInitialized` - SDK not initialized
- `modelNotLoaded` - No model loaded
- `generationFailed` - Generation failed

**Example:**

```typescript
const response = await RunAnywhere.chat('What is the capital of France?');
console.log(response);
```

---

#### `RunAnywhere.generate(prompt, options?)`

Generate text with full options and metrics.

```typescript
await RunAnywhere.generate(
  prompt: string,
  options?: GenerationOptions
): Promise<GenerationResult>
```

**Parameters:**

```typescript
interface GenerationOptions {
  /** Maximum number of tokens to generate (default: 256) */
  maxTokens?: number;

  /** Temperature for sampling (0.0 - 2.0, default: 0.7) */
  temperature?: number;

  /** Top-p sampling parameter (default: 0.95) */
  topP?: number;

  /** Stop sequences - stop generation when encountered */
  stopSequences?: string[];

  /** System prompt to define AI behavior */
  systemPrompt?: string;

  /** Preferred execution target */
  preferredExecutionTarget?: ExecutionTarget;

  /** Preferred framework for generation */
  preferredFramework?: LLMFramework;
}
```

**Returns:**

```typescript
interface GenerationResult {
  /** Generated text (with thinking content removed if extracted) */
  text: string;

  /** Thinking/reasoning content extracted from the response */
  thinkingContent?: string;

  /** Number of tokens used */
  tokensUsed: number;

  /** Model used for generation */
  modelUsed: string;

  /** Latency in milliseconds */
  latencyMs: number;

  /** Execution target (device/cloud/hybrid) */
  executionTarget: ExecutionTarget;

  /** Framework used for generation */
  framework?: LLMFramework;

  /** Hardware acceleration used */
  hardwareUsed: HardwareAcceleration;

  /** Memory used during generation (bytes) */
  memoryUsed: number;

  /** Detailed performance metrics */
  performanceMetrics: PerformanceMetrics;

  /** Number of tokens in the response content */
  responseTokens: number;
}

interface PerformanceMetrics {
  /** Time to first token in milliseconds */
  timeToFirstTokenMs?: number;

  /** Tokens generated per second */
  tokensPerSecond?: number;

  /** Total inference time in milliseconds */
  inferenceTimeMs: number;
}
```

**Example:**

```typescript
const result = await RunAnywhere.generate(
  'Explain quantum computing in simple terms',
  {
    maxTokens: 200,
    temperature: 0.7,
    systemPrompt: 'You are a helpful science teacher.',
  }
);

console.log('Response:', result.text);
console.log('Tokens:', result.tokensUsed);
console.log('Speed:', result.performanceMetrics.tokensPerSecond, 'tok/s');
console.log('TTFT:', result.performanceMetrics.timeToFirstTokenMs, 'ms');
```

---

#### `RunAnywhere.generateStream(prompt, options?)`

Generate text with token-by-token streaming.

```typescript
await RunAnywhere.generateStream(
  prompt: string,
  options?: GenerationOptions
): Promise<LLMStreamingResult>
```

**Returns:**

```typescript
interface LLMStreamingResult {
  /** Async iterator for tokens */
  stream: AsyncIterable<string>;

  /** Promise resolving to final result with metrics */
  result: Promise<GenerationResult>;
}
```

**Example:**

```typescript
const streamResult = await RunAnywhere.generateStream(
  'Write a poem about AI',
  { maxTokens: 150 }
);

// Display tokens in real-time
let fullText = '';
for await (const token of streamResult.stream) {
  fullText += token;
  console.log(token);  // Each token as it's generated
}

// Get final metrics
const finalResult = await streamResult.result;
console.log('Speed:', finalResult.performanceMetrics.tokensPerSecond, 'tok/s');
```

---

#### `RunAnywhere.cancelGeneration()`

Cancel an ongoing generation.

```typescript
await RunAnywhere.cancelGeneration(): Promise<void>
```

---

### Speech-to-Text

#### `RunAnywhere.loadSTTModel(modelPath, modelType?)`

Load a Speech-to-Text model.

```typescript
await RunAnywhere.loadSTTModel(
  modelPath: string,
  modelType?: string
): Promise<boolean>
```

**Parameters:**
- `modelPath` - Path to the STT model directory
- `modelType` - Model type identifier (default: 'whisper')

**Returns:** `Promise<boolean>` - `true` if loaded successfully

**Example:**

```typescript
const sttModel = await RunAnywhere.getModelInfo('sherpa-onnx-whisper-tiny.en');
await RunAnywhere.loadSTTModel(sttModel.localPath, 'whisper');
```

---

#### `RunAnywhere.isSTTModelLoaded()`

Check if an STT model is loaded.

```typescript
await RunAnywhere.isSTTModelLoaded(): Promise<boolean>
```

---

#### `RunAnywhere.unloadSTTModel()`

Unload the currently loaded STT model.

```typescript
await RunAnywhere.unloadSTTModel(): Promise<void>
```

---

#### `RunAnywhere.transcribeFile(audioPath, options?)`

Transcribe an audio file.

```typescript
await RunAnywhere.transcribeFile(
  audioPath: string,
  options?: STTOptions
): Promise<STTResult>
```

**Parameters:**

```typescript
interface STTOptions {
  /** Language code (e.g., 'en', 'es') */
  language?: string;

  /** Enable punctuation */
  punctuation?: boolean;

  /** Enable speaker diarization */
  diarization?: boolean;

  /** Enable word timestamps */
  wordTimestamps?: boolean;

  /** Sample rate */
  sampleRate?: number;
}
```

**Returns:**

```typescript
interface STTResult {
  /** Main transcription text */
  text: string;

  /** Segments with timing */
  segments: STTSegment[];

  /** Detected language */
  language?: string;

  /** Overall confidence (0.0 - 1.0) */
  confidence: number;

  /** Duration in seconds */
  duration: number;

  /** Alternative transcriptions */
  alternatives: STTAlternative[];
}

interface STTSegment {
  text: string;
  startTime: number;
  endTime: number;
  speakerId?: string;
  confidence: number;
}
```

**Example:**

```typescript
const result = await RunAnywhere.transcribeFile(audioFilePath, {
  language: 'en',
  wordTimestamps: true,
});

console.log('Text:', result.text);
console.log('Confidence:', result.confidence);
console.log('Duration:', result.duration, 'seconds');
```

---

#### `RunAnywhere.transcribe(audioData, options?)`

Transcribe raw audio data (base64-encoded).

```typescript
await RunAnywhere.transcribe(
  audioData: string,
  options?: STTOptions
): Promise<STTResult>
```

**Parameters:**
- `audioData` - Base64-encoded audio data (float32 PCM)

---

#### `RunAnywhere.transcribeBuffer(samples, sampleRate, options?)`

Transcribe float32 audio samples.

```typescript
await RunAnywhere.transcribeBuffer(
  samples: number[],
  sampleRate: number,
  options?: STTOptions
): Promise<STTResult>
```

---

### Text-to-Speech

#### `RunAnywhere.loadTTSModel(modelPath, modelType?)`

Load a Text-to-Speech model.

```typescript
await RunAnywhere.loadTTSModel(
  modelPath: string,
  modelType?: string
): Promise<boolean>
```

**Parameters:**
- `modelPath` - Path to the TTS model directory
- `modelType` - Model type identifier (default: 'piper')

**Example:**

```typescript
const ttsModel = await RunAnywhere.getModelInfo('vits-piper-en_US-lessac-medium');
await RunAnywhere.loadTTSModel(ttsModel.localPath, 'piper');
```

---

#### `RunAnywhere.loadTTSVoice(voiceId)`

Load a specific TTS voice.

```typescript
await RunAnywhere.loadTTSVoice(voiceId: string): Promise<boolean>
```

---

#### `RunAnywhere.isTTSModelLoaded()`

Check if a TTS model is loaded.

```typescript
await RunAnywhere.isTTSModelLoaded(): Promise<boolean>
```

---

#### `RunAnywhere.unloadTTSModel()`

Unload the currently loaded TTS model.

```typescript
await RunAnywhere.unloadTTSModel(): Promise<void>
```

---

#### `RunAnywhere.synthesize(text, options?)`

Synthesize speech from text.

```typescript
await RunAnywhere.synthesize(
  text: string,
  options?: TTSConfiguration
): Promise<TTSResult>
```

**Parameters:**

```typescript
interface TTSConfiguration {
  /** Voice identifier */
  voice?: string;

  /** Speech rate (0.5 - 2.0, default: 1.0) */
  rate?: number;

  /** Pitch (0.5 - 2.0, default: 1.0) */
  pitch?: number;

  /** Volume (0.0 - 1.0, default: 1.0) */
  volume?: number;
}
```

**Returns:**

```typescript
interface TTSResult {
  /** Base64-encoded audio data (float32 PCM) */
  audio: string;

  /** Sample rate of the audio */
  sampleRate: number;

  /** Number of samples */
  numSamples: number;

  /** Duration in seconds */
  duration: number;
}
```

**Example:**

```typescript
const result = await RunAnywhere.synthesize(
  'Hello from the SDK.',
  { rate: 1.0, pitch: 1.0, volume: 0.8 }
);

console.log('Duration:', result.duration, 'seconds');
console.log('Sample rate:', result.sampleRate);
// result.audio contains base64-encoded float32 PCM
```

---

#### `RunAnywhere.synthesizeStream(text, options?, callback?)`

Synthesize speech with streaming chunks.

```typescript
await RunAnywhere.synthesizeStream(
  text: string,
  options?: TTSConfiguration,
  callback?: (chunk: TTSOutput) => void
): Promise<TTSResult>
```

---

#### `RunAnywhere.speak(text, options?)`

Speak text using system TTS (AVSpeechSynthesizer / Android TTS).

```typescript
await RunAnywhere.speak(
  text: string,
  options?: TTSConfiguration
): Promise<TTSSpeakResult>
```

---

#### `RunAnywhere.stopSpeaking()`

Stop current speech synthesis.

```typescript
await RunAnywhere.stopSpeaking(): Promise<void>
```

---

#### `RunAnywhere.isSpeaking()`

Check if currently speaking.

```typescript
await RunAnywhere.isSpeaking(): Promise<boolean>
```

---

#### `RunAnywhere.availableTTSVoices()`

Get list of available TTS voices.

```typescript
await RunAnywhere.availableTTSVoices(): Promise<TTSVoiceInfo[]>
```

---

### Voice Activity Detection

#### `RunAnywhere.initializeVAD(config?)`

Initialize Voice Activity Detection.

```typescript
await RunAnywhere.initializeVAD(
  config?: VADConfiguration
): Promise<boolean>
```

**Parameters:**

```typescript
interface VADConfiguration {
  /** Energy threshold for speech detection */
  energyThreshold?: number;

  /** Sample rate */
  sampleRate?: number;

  /** Frame length in milliseconds */
  frameLength?: number;

  /** Enable auto calibration */
  autoCalibration?: boolean;
}
```

---

#### `RunAnywhere.loadVADModel(modelPath)`

Load a VAD model.

```typescript
await RunAnywhere.loadVADModel(modelPath: string): Promise<boolean>
```

---

#### `RunAnywhere.isVADModelLoaded()`

Check if VAD model is loaded.

```typescript
await RunAnywhere.isVADModelLoaded(): Promise<boolean>
```

---

#### `RunAnywhere.processVAD(audioSamples)`

Process audio samples for voice activity.

```typescript
await RunAnywhere.processVAD(
  audioSamples: number[]
): Promise<VADResult>
```

**Returns:**

```typescript
interface VADResult {
  /** Whether speech is detected */
  isSpeech: boolean;

  /** Confidence score (0.0 - 1.0) */
  confidence: number;

  /** Start time of speech segment */
  startTime?: number;

  /** End time of speech segment */
  endTime?: number;
}
```

---

#### `RunAnywhere.startVAD()`

Start continuous VAD processing.

```typescript
await RunAnywhere.startVAD(): Promise<void>
```

---

#### `RunAnywhere.stopVAD()`

Stop continuous VAD processing.

```typescript
await RunAnywhere.stopVAD(): Promise<void>
```

---

#### `RunAnywhere.setVADSpeechActivityCallback(callback)`

Set callback for speech activity events.

```typescript
RunAnywhere.setVADSpeechActivityCallback(
  callback: (event: SpeechActivityEvent) => void
): void
```

---

### Voice Agent

#### `RunAnywhere.initializeVoiceAgent(config)`

Initialize the voice agent pipeline (VAD → STT → LLM → TTS).

```typescript
await RunAnywhere.initializeVoiceAgent(
  config: VoiceAgentConfig
): Promise<boolean>
```

**Parameters:**

```typescript
interface VoiceAgentConfig {
  /** LLM model ID */
  llmModelId: string;

  /** STT model ID */
  sttModelId: string;

  /** TTS model ID */
  ttsModelId: string;

  /** System prompt for LLM */
  systemPrompt?: string;

  /** Generation options */
  generationOptions?: GenerationOptions;
}
```

---

#### `RunAnywhere.processVoiceTurn(audioData)`

Process a complete voice turn (STT → LLM → TTS).

```typescript
await RunAnywhere.processVoiceTurn(
  audioData: string
): Promise<VoiceTurnResult>
```

**Returns:**

```typescript
interface VoiceTurnResult {
  /** Transcribed user speech */
  userTranscript: string;

  /** LLM response text */
  assistantResponse: string;

  /** Synthesized audio (base64) */
  audio: string;

  /** Performance metrics */
  metrics: VoiceAgentMetrics;
}
```

---

#### `RunAnywhere.startVoiceSession(config, callback)`

Start an interactive voice session.

```typescript
await RunAnywhere.startVoiceSession(
  config: VoiceSessionConfig,
  callback: (event: VoiceSessionEvent) => void
): Promise<VoiceSessionHandle>
```

---

### Model Management

#### `RunAnywhere.getAvailableModels()`

Get list of all available models (registered + downloaded).

```typescript
await RunAnywhere.getAvailableModels(): Promise<ModelInfo[]>
```

**Returns:** Array of `ModelInfo` objects

**Example:**

```typescript
const models = await RunAnywhere.getAvailableModels();
const llmModels = models.filter(m => m.category === ModelCategory.Language);
const downloadedModels = models.filter(m => m.isDownloaded);
```

---

#### `RunAnywhere.getModelInfo(modelId)`

Get information about a specific model.

```typescript
await RunAnywhere.getModelInfo(modelId: string): Promise<ModelInfo | null>
```

**Returns:** `ModelInfo` or `null` if not found

---

#### `RunAnywhere.getDownloadedModels()`

Get list of downloaded model IDs.

```typescript
await RunAnywhere.getDownloadedModels(): Promise<string[]>
```

---

#### `RunAnywhere.isModelDownloaded(modelId)`

Check if a model is downloaded.

```typescript
await RunAnywhere.isModelDownloaded(modelId: string): Promise<boolean>
```

---

#### `RunAnywhere.downloadModel(modelId, onProgress?)`

Download a model with progress tracking.

```typescript
await RunAnywhere.downloadModel(
  modelId: string,
  onProgress?: (progress: DownloadProgress) => void
): Promise<void>
```

**Parameters:**

```typescript
interface DownloadProgress {
  /** Model ID */
  modelId: string;

  /** Progress (0.0 - 1.0) */
  progress: number;

  /** Bytes downloaded */
  bytesDownloaded: number;

  /** Total bytes */
  bytesTotal: number;

  /** Download state */
  state: DownloadState;
}

enum DownloadState {
  Queued = 'queued',
  Downloading = 'downloading',
  Extracting = 'extracting',
  Completed = 'completed',
  Failed = 'failed',
  Cancelled = 'cancelled',
}
```

**Example:**

```typescript
await RunAnywhere.downloadModel('smollm2-360m-q8_0', (progress) => {
  const percent = (progress.progress * 100).toFixed(1);
  console.log(`Downloading: ${percent}%`);

  if (progress.state === DownloadState.Extracting) {
    console.log('Extracting archive...');
  }
});
```

---

#### `RunAnywhere.cancelDownload(modelId)`

Cancel an ongoing download.

```typescript
await RunAnywhere.cancelDownload(modelId: string): Promise<void>
```

---

#### `RunAnywhere.deleteModel(modelId)`

Delete a downloaded model from disk.

```typescript
await RunAnywhere.deleteModel(modelId: string): Promise<void>
```

---

### Storage Management

#### `RunAnywhere.getStorageInfo()`

Get storage usage information.

```typescript
await RunAnywhere.getStorageInfo(): Promise<StorageInfo>
```

**Returns:**

```typescript
interface StorageInfo {
  /** Total storage available (bytes) */
  totalSpace: number;

  /** Storage used by SDK (bytes) */
  usedSpace: number;

  /** Free space available (bytes) */
  freeSpace: number;

  /** Models storage path */
  modelsPath: string;
}
```

---

#### `RunAnywhere.clearCache()`

Clear SDK cache files.

```typescript
await RunAnywhere.clearCache(): Promise<void>
```

---

#### `RunAnywhere.cleanTempFiles()`

Clean temporary files.

```typescript
await RunAnywhere.cleanTempFiles(): Promise<boolean>
```

---

### Events

#### `EventBus`

The SDK event system for subscribing to SDK events.

```typescript
import { EventBus } from '@runanywhere/core';

// Or via RunAnywhere
RunAnywhere.events
```

#### Event Subscription Methods

```typescript
// Subscribe to all events
const unsubscribe = EventBus.on(
  category: EventCategory,
  callback: (event: SDKEvent) => void
): () => void

// Shorthand methods
EventBus.onInitialization(callback)
EventBus.onGeneration(callback)
EventBus.onModel(callback)
EventBus.onVoice(callback)
EventBus.onStorage(callback)
EventBus.onError(callback)
```

#### Event Types

```typescript
// Initialization Events
interface SDKInitializationEvent {
  type: 'started' | 'completed' | 'failed';
  error?: string;
}

// Generation Events
interface SDKGenerationEvent {
  type: 'started' | 'tokenGenerated' | 'completed' | 'failed' | 'cancelled';
  token?: string;
  response?: GenerationResult;
  error?: string;
}

// Model Events
interface SDKModelEvent {
  type: 'downloadStarted' | 'downloadProgress' | 'downloadCompleted' |
        'downloadFailed' | 'loadStarted' | 'loadCompleted' | 'unloaded';
  modelId: string;
  progress?: number;
  error?: string;
}

// Voice Events
interface SDKVoiceEvent {
  type: 'sttStarted' | 'sttCompleted' | 'ttsStarted' | 'ttsCompleted' |
        'vadSpeechStarted' | 'vadSpeechEnded';
  result?: STTResult | TTSResult;
}
```

**Example:**

```typescript
// Subscribe to generation events
const unsubscribe = RunAnywhere.events.onGeneration((event) => {
  switch (event.type) {
    case 'started':
      console.log('Generation started');
      break;
    case 'tokenGenerated':
      process.stdout.write(event.token);
      break;
    case 'completed':
      console.log('\nDone!', event.response.tokensUsed, 'tokens');
      break;
    case 'failed':
      console.error('Error:', event.error);
      break;
  }
});

// Later: unsubscribe
unsubscribe();
```

---

## LlamaCPP Module

```typescript
import { LlamaCPP, LlamaCppProvider } from '@runanywhere/llamacpp';
```

### `LlamaCPP.register()`

Register the LlamaCPP backend with the SDK.

```typescript
LlamaCPP.register(): void
```

**Example:**

```typescript
// Register after SDK initialization
await RunAnywhere.initialize({ ... });
LlamaCPP.register();
```

---

### `LlamaCPP.addModel(options)`

Add a GGUF model to the registry.

```typescript
await LlamaCPP.addModel(options: LlamaCPPModelOptions): Promise<ModelInfo>
```

**Parameters:**

```typescript
interface LlamaCPPModelOptions {
  /** Unique model ID. If not provided, generated from URL filename */
  id?: string;

  /** Display name for the model */
  name: string;

  /** Download URL for the model */
  url: string;

  /** Model category (defaults to Language) */
  modality?: ModelCategory;

  /** Memory requirement in bytes */
  memoryRequirement?: number;

  /** Whether model supports reasoning/thinking tokens */
  supportsThinking?: boolean;
}
```

**Example:**

```typescript
await LlamaCPP.addModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500_000_000,
});

// Model with thinking support
await LlamaCPP.addModel({
  id: 'qwen2.5-0.5b-instruct',
  name: 'Qwen 2.5 0.5B Instruct',
  url: 'https://huggingface.co/.../qwen2.5-0.5b-instruct-q6_k.gguf',
  memoryRequirement: 600_000_000,
  supportsThinking: true,
});
```

---

### `LlamaCppProvider.register()`

Lower-level registration with ServiceRegistry.

```typescript
LlamaCppProvider.register(): void
```

---

## ONNX Module

```typescript
import { ONNX, ONNXProvider, ModelArtifactType } from '@runanywhere/onnx';
```

### `ONNX.register()`

Register the ONNX backend with the SDK.

```typescript
ONNX.register(): void
```

---

### `ONNX.addModel(options)`

Add an ONNX model (STT or TTS) to the registry.

```typescript
await ONNX.addModel(options: ONNXModelOptions): Promise<ModelInfo>
```

**Parameters:**

```typescript
interface ONNXModelOptions {
  /** Unique model ID. If not provided, generated from URL filename */
  id?: string;

  /** Display name for the model */
  name: string;

  /** Download URL for the model */
  url: string;

  /** Model category (SpeechRecognition or SpeechSynthesis) */
  modality: ModelCategory;

  /** How the model is packaged */
  artifactType?: ModelArtifactType;

  /** Memory requirement in bytes */
  memoryRequirement?: number;
}

enum ModelArtifactType {
  SingleFile = 'singleFile',
  TarGzArchive = 'tarGzArchive',
  TarBz2Archive = 'tarBz2Archive',
  ZipArchive = 'zipArchive',
}
```

**Example:**

```typescript
// STT Model
await ONNX.addModel({
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (English)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.SpeechRecognition,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 75_000_000,
});

// TTS Model
await ONNX.addModel({
  id: 'vits-piper-en_US-lessac-medium',
  name: 'Piper TTS (US English)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../vits-piper-en_US-lessac-medium.tar.gz',
  modality: ModelCategory.SpeechSynthesis,
  artifactType: ModelArtifactType.TarGzArchive,
  memoryRequirement: 65_000_000,
});
```

---

## Types Reference

### Enums

```typescript
enum SDKEnvironment {
  Development = 'development',
  Staging = 'staging',
  Production = 'production',
}

enum ExecutionTarget {
  OnDevice = 'onDevice',
  Cloud = 'cloud',
  Hybrid = 'hybrid',
}

enum LLMFramework {
  CoreML = 'CoreML',
  TensorFlowLite = 'TFLite',
  MLX = 'MLX',
  ONNX = 'ONNX',
  LlamaCpp = 'LlamaCpp',
  FoundationModels = 'FoundationModels',
  WhisperKit = 'WhisperKit',
  SystemTTS = 'SystemTTS',
  PiperTTS = 'PiperTTS',
}

enum ModelCategory {
  Language = 'language',
  SpeechRecognition = 'speech-recognition',
  SpeechSynthesis = 'speech-synthesis',
  Vision = 'vision',
  ImageGeneration = 'image-generation',
  Multimodal = 'multimodal',
  Audio = 'audio',
}

enum ModelFormat {
  GGUF = 'gguf',
  GGML = 'ggml',
  ONNX = 'onnx',
  MLModel = 'mlmodel',
  SafeTensors = 'safetensors',
}

enum HardwareAcceleration {
  CPU = 'cpu',
  GPU = 'gpu',
  NeuralEngine = 'neuralEngine',
  NPU = 'npu',
}

enum ComponentState {
  NotInitialized = 'notInitialized',
  Initializing = 'initializing',
  Ready = 'ready',
  Error = 'error',
  CleaningUp = 'cleaningUp',
}
```

### Core Interfaces

```typescript
interface ModelInfo {
  id: string;
  name: string;
  category: ModelCategory;
  format: ModelFormat;
  downloadURL?: string;
  localPath?: string;
  downloadSize?: number;
  memoryRequired?: number;
  compatibleFrameworks: LLMFramework[];
  preferredFramework?: LLMFramework;
  supportsThinking: boolean;
  isDownloaded: boolean;
  isAvailable: boolean;
}

interface GenerationResult {
  text: string;
  thinkingContent?: string;
  tokensUsed: number;
  modelUsed: string;
  latencyMs: number;
  executionTarget: ExecutionTarget;
  framework?: LLMFramework;
  hardwareUsed: HardwareAcceleration;
  memoryUsed: number;
  performanceMetrics: PerformanceMetrics;
  responseTokens: number;
}

interface STTResult {
  text: string;
  segments: STTSegment[];
  language?: string;
  confidence: number;
  duration: number;
  alternatives: STTAlternative[];
}

interface TTSResult {
  audio: string;
  sampleRate: number;
  numSamples: number;
  duration: number;
}
```

---

## Error Reference

### SDKError

```typescript
import { SDKError, SDKErrorCode, isSDKError, ErrorCategory } from '@runanywhere/core';

interface SDKError extends Error {
  code: SDKErrorCode;
  category: ErrorCategory;
  underlyingError?: Error;
  recoverySuggestion?: string;
}

function isSDKError(error: unknown): error is SDKError
```

### Error Codes

| Code | Category | Description |
|------|----------|-------------|
| `notInitialized` | General | SDK not initialized |
| `alreadyInitialized` | General | SDK already initialized |
| `invalidInput` | General | Invalid input parameters |
| `modelNotFound` | Model | Model not in registry |
| `modelLoadFailed` | Model | Failed to load model |
| `modelNotLoaded` | Model | No model currently loaded |
| `downloadFailed` | Download | Model download failed |
| `downloadCancelled` | Download | Download was cancelled |
| `insufficientStorage` | Storage | Not enough disk space |
| `insufficientMemory` | Memory | Not enough RAM |
| `generationFailed` | LLM | Text generation failed |
| `generationCancelled` | LLM | Generation was cancelled |
| `sttFailed` | STT | Transcription failed |
| `ttsFailed` | TTS | Synthesis failed |
| `vadFailed` | VAD | Voice detection failed |
| `networkUnavailable` | Network | No network connection |
| `authenticationFailed` | Auth | Invalid API key |
| `permissionDenied` | Permission | Missing required permission |

### Error Helper Functions

```typescript
// Create common errors
import {
  notInitializedError,
  modelNotFoundError,
  modelLoadError,
  generationError,
  networkError,
} from '@runanywhere/core';

// Example
throw notInitializedError();
throw modelNotFoundError('model-id');
throw generationError('Generation timed out');
```

---

## See Also

- [README.md](../README.md) — Quick start guide
- [React Native Sample App](../../../examples/react-native/RunAnywhereAI/) — Working demo
