# RunAnywhere React Native SDK

> ⚠️ **DOC DRIFT NOTICE**: Version numbers in examples reflect a
> pre-v2.x snapshot; current version is `3.1.0` (see
> `sdk/runanywhere-react-native/packages/core/package.json`). Voice
> APIs now use `VoiceAgentStreamAdapter(handle).stream()` returning
> `AsyncIterable<VoiceEvent>` (proto). See
> [`../STATE_AND_ROADMAP.md`](../STATE_AND_ROADMAP.md) and
> [`../migrations/VoiceSessionEvent.md`](../migrations/VoiceSessionEvent.md).
> Refresh tracked in Active Backlog #4.

React Native SDK for on-device AI inference. Uses Nitrogen/Nitro for high-performance TypeScript-to-C++ bridging.

## Installation

```bash
# Core SDK (required)
yarn add @runanywhere/core

# Backend modules (pick what you need)
yarn add @runanywhere/llamacpp    # LLM text generation (GGUF models)
yarn add @runanywhere/onnx        # STT, TTS, VAD (ONNX Runtime)
yarn add @runanywhere/genie       # Qualcomm NPU inference
```

### Peer Dependencies

```bash
yarn add react-native-nitro-modules react-native-fs
```

### iOS Setup

```bash
cd ios && pod install
```

### Android Setup

No extra steps — native libraries are bundled with the npm packages. Gradle downloads missing ABIs automatically.

## Platform Requirements

| Platform | Requirement |
|----------|-------------|
| React Native | 0.83.1+ |
| iOS | 15.1+ |
| Android Min SDK | 24 |
| Node.js | 18+ |

## Quick Start

```typescript
import { RunAnywhere, LLMFramework, ModelCategory } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';
import { ONNX } from '@runanywhere/onnx';

// 1. Initialize SDK
await RunAnywhere.initialize({
  environment: SDKEnvironment.Development,
});

// 2. Register backends
LlamaCPP.register();
await ONNX.register();

// 3. Register a model
await RunAnywhere.registerModel({
  id: 'qwen3-4b-q4_k_m',
  name: 'Qwen3 4B',
  url: 'https://huggingface.co/.../Qwen3-4B-Q4_K_M.gguf',
  framework: LLMFramework.LlamaCpp,
  memoryRequirement: 2_800_000_000,
});

// 4. Download and load
await RunAnywhere.downloadModel('qwen3-4b-q4_k_m', (progress) => {
  console.log(`${Math.round(progress.progress * 100)}%`);
});
await RunAnywhere.loadModel('qwen3-4b-q4_k_m');

// 5. Generate text
const response = await RunAnywhere.chat('Hello!');
console.log(response);
```

## Architecture

### Package Structure

```
runanywhere-react-native/
├── packages/
│   ├── core/                    # Core SDK
│   │   ├── src/                 # TypeScript source
│   │   │   ├── Public/          # RunAnywhere class + extensions
│   │   │   ├── services/        # FileSystem, ModelRegistry, HTTP
│   │   │   ├── types/           # All type definitions
│   │   │   └── native/          # Nitro module bindings
│   │   ├── cpp/                 # C++ implementation (HybridRunAnywhereCore)
│   │   │   └── bridges/         # Feature-specific C++ bridges
│   │   ├── android/             # Kotlin + CMake + JNI libs
│   │   ├── ios/                 # Swift + XCFrameworks
│   │   └── nitrogen/generated/  # Auto-generated bindings (do not edit)
│   ├── llamacpp/                # llama.cpp backend
│   │   ├── cpp/                 # HybridRunAnywhereLlama.cpp
│   │   ├── android/             # librac_backend_llamacpp.so
│   │   └── ios/                 # RABackendLLAMACPP.xcframework
│   └── onnx/                   # ONNX Runtime backend
│       ├── cpp/                 # HybridRunAnywhereONNX.cpp
│       ├── android/             # librac_backend_onnx.so + libonnxruntime.so
│       └── ios/                 # RABackendONNX.xcframework
```

### Nitrogen/Nitro Bridge

TypeScript ↔ C++ bridge via [Nitrogen](https://nitro.margelo.com/):

```
TypeScript (RunAnywhere.ts)
    ↓ Nitro HybridObject
C++ (HybridRunAnywhereCore.cpp)
    ↓ rac_* C API
Native Libraries (librac_commons.so / RACommons.xcframework)
```

---

## API Reference

### SDK Lifecycle

```typescript
// Initialize
await RunAnywhere.initialize(options: SDKInitOptions): Promise<void>

interface SDKInitOptions {
  apiKey?: string;
  baseURL?: string;
  environment?: SDKEnvironment;
  debug?: boolean;
}

// State
RunAnywhere.isSDKInitialized: boolean
RunAnywhere.areServicesReady: boolean
RunAnywhere.version: string

// Cleanup
await RunAnywhere.destroy(): Promise<void>
await RunAnywhere.reset(): Promise<void>
```

### Text Generation (LLM)

```typescript
// Simple chat
await RunAnywhere.chat(prompt: string): Promise<string>

// Full generation
await RunAnywhere.generate(prompt: string, options?: GenerationOptions): Promise<GenerationResult>

// Streaming
await RunAnywhere.generateStream(prompt: string, options?: GenerationOptions): Promise<LLMStreamingResult>

// Control
RunAnywhere.cancelGeneration(): void

// Model management
await RunAnywhere.loadModel(modelPathOrId: string): Promise<boolean>
await RunAnywhere.isModelLoaded(): Promise<boolean>
await RunAnywhere.unloadModel(): Promise<boolean>
```

**Generation Options:**
```typescript
interface GenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  stopSequences?: string[];
  streamingEnabled?: boolean;
  preferredFramework?: LLMFramework;
  systemPrompt?: string;
  structuredOutput?: StructuredOutputConfig;
}
```

**Generation Result:**
```typescript
interface GenerationResult {
  text: string;
  thinkingContent?: string;
  tokensUsed: number;
  modelUsed: string;
  latencyMs: number;
  framework?: LLMFramework;
  tokensPerSecond: number;
  timeToFirstTokenMs?: number;
  thinkingTokens?: number;
  responseTokens: number;
}
```

**Streaming Result:**
```typescript
interface LLMStreamingResult {
  stream: AsyncIterable<string>;
  result: Promise<GenerationResult>;
  cancel: () => void;
}
```

### Speech-to-Text (STT)

```typescript
await RunAnywhere.transcribe(audioData: string | ArrayBuffer, options?: STTOptions): Promise<STTResult>
await RunAnywhere.transcribeSimple(audioData: string | ArrayBuffer): Promise<string>
await RunAnywhere.transcribeFile(filePath: string, options?: STTOptions): Promise<STTResult>

// Model management
await RunAnywhere.loadSTTModel(modelPath: string): Promise<boolean>
await RunAnywhere.isSTTModelLoaded(): Promise<boolean>
await RunAnywhere.unloadSTTModel(): Promise<boolean>
```

### Text-to-Speech (TTS)

```typescript
await RunAnywhere.synthesize(text: string, options?: TTSConfiguration): Promise<TTSResult>
await RunAnywhere.speak(text: string, options?: TTSConfiguration): Promise<TTSSpeakResult>
await RunAnywhere.isSpeaking(): Promise<boolean>
await RunAnywhere.stopSpeaking(): Promise<void>

// Voice management
await RunAnywhere.loadTTSVoice(voiceId: string): Promise<void>
await RunAnywhere.availableTTSVoices(): Promise<TTSVoiceInfo[]>
```

### Voice Activity Detection (VAD)

```typescript
await RunAnywhere.initializeVAD(config?: VADConfiguration): Promise<void>
await RunAnywhere.detectSpeech(audioData: Float32Array): Promise<VADResult>
await RunAnywhere.startVAD(): Promise<boolean>
await RunAnywhere.stopVAD(): Promise<boolean>
await RunAnywhere.resetVAD(): Promise<void>

RunAnywhere.setVADSpeechActivityCallback(callback: (result: VADResult) => void): void
```

### Vision Language Models (VLM)

```typescript
// Simple
await RunAnywhere.describeImage(image: VLMImage, options?: VLMGenerationOptions): Promise<VLMResult>
await RunAnywhere.askAboutImage(image: VLMImage, question: string): Promise<VLMResult>

// Full with metrics
await RunAnywhere.processImage(image: VLMImage, prompt: string, options?: VLMGenerationOptions): Promise<VLMResult>

// Streaming
await RunAnywhere.processImageStream(image: VLMImage, prompt: string): Promise<VLMStreamingResult>

// Model management
await RunAnywhere.registerVLMBackend(): Promise<boolean>
await RunAnywhere.loadVLMModel(modelPath: string, mmprojPath?: string): Promise<boolean>
await RunAnywhere.loadVLMModelById(modelId: string): Promise<boolean>
```

**VLM Image:**
```typescript
type VLMImage =
  | { format: VLMImageFormat.FilePath; filePath: string }
  | { format: VLMImageFormat.RGBPixels; data: Uint8Array; width: number; height: number }
  | { format: VLMImageFormat.Base64; base64: string };
```

### Voice Agent

```typescript
// Initialize full voice pipeline
await RunAnywhere.initializeVoiceAgent(config: VoiceAgentConfig): Promise<boolean>
await RunAnywhere.isVoiceAgentReady(): Promise<boolean>

// Process a voice turn
await RunAnywhere.processVoiceTurn(audioData: string | ArrayBuffer): Promise<VoiceTurnResult>

// Interactive session
await RunAnywhere.startVoiceSession(config: VoiceSessionConfig): Promise<VoiceSessionHandle>

// Cleanup
await RunAnywhere.cleanupVoiceAgent(): Promise<void>
```

### Structured Output

```typescript
await RunAnywhere.generateStructured(
  prompt: string,
  schema: Record<string, unknown>,
  options?: GenerationOptions
): Promise<GenerationResult>

await RunAnywhere.extractEntities(text: string, entityTypes: string[]): Promise<Record<string, unknown>>
await RunAnywhere.classify(text: string, categories: string[]): Promise<string>
```

### Tool Calling

```typescript
// Register tools
RunAnywhere.registerTool(tool: ToolDefinition): void
RunAnywhere.unregisterTool(toolName: string): void
RunAnywhere.getRegisteredTools(): ToolDefinition[]

// Generate with tools
await RunAnywhere.generateWithTools(prompt: string, options?: GenerationOptions): Promise<GenerationResult>
await RunAnywhere.continueWithToolResult(toolName: string, result: unknown): Promise<GenerationResult>
```

### RAG (Retrieval-Augmented Generation)

```typescript
await RunAnywhere.ragCreatePipeline(config: RAGConfiguration): Promise<string>
await RunAnywhere.ragIngest(pipelineId: string, documents: string[]): Promise<void>
await RunAnywhere.ragQuery(pipelineId: string, options: RAGQueryOptions): Promise<RAGResult>
await RunAnywhere.ragClearDocuments(pipelineId: string): Promise<void>
await RunAnywhere.ragDestroyPipeline(pipelineId: string): Promise<void>
```

### Model Management

```typescript
// Registration
await RunAnywhere.registerModel(modelInfo: ModelRegistration): Promise<void>
await RunAnywhere.registerMultiFileModel(modelId: string, files: ModelFileDescriptor[]): Promise<void>

interface ModelRegistration {
  id: string;
  name: string;
  url: string;
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
}

// Discovery
await RunAnywhere.getAvailableModels(): Promise<ModelInfo[]>
await RunAnywhere.getModelInfo(modelId: string): Promise<ModelInfo | null>
await RunAnywhere.isModelDownloaded(modelId: string): Promise<boolean>
await RunAnywhere.getDownloadedModels(): Promise<ModelInfo[]>

// Download
await RunAnywhere.downloadModel(modelId: string, onProgress?: ProgressCallback): Promise<void>
await RunAnywhere.cancelDownload(modelId: string): Promise<boolean>

// Lifecycle
await RunAnywhere.deleteModel(modelId: string): Promise<boolean>
await RunAnywhere.checkCompatibility(modelId: string): Promise<ModelCompatibilityResult>
```

### NPU Chip Detection

```typescript
import { getChip, getNPUDownloadUrl, NPU_CHIPS } from '@runanywhere/core';

const chip = await getChip();  // null if no supported NPU

if (chip) {
  const url = getNPUDownloadUrl(chip, 'qwen3-4b');                  // default w4a16
  const url2 = getNPUDownloadUrl(chip, 'qwen2.5-7b-instruct', 'w8a16');
}
```

**NPUChip Interface:**
```typescript
interface NPUChip {
  identifier: string;      // '8elite' or '8elite-gen5'
  displayName: string;     // 'Snapdragon 8 Elite'
  socModel: string;        // 'SM8750'
  npuSuffix: string;       // URL construction
}

// Supported chips
const NPU_CHIPS: readonly NPUChip[] = [
  { identifier: '8elite', displayName: 'Snapdragon 8 Elite', socModel: 'SM8750', npuSuffix: '8elite' },
  { identifier: '8elite-gen5', displayName: 'Snapdragon 8 Elite Gen 5', socModel: 'SM8850', npuSuffix: '8elite-gen5' },
];

function getNPUDownloadUrl(chip: NPUChip, modelSlug: string, quant?: string): string
function npuChipFromSocModel(socModel: string): NPUChip | undefined
```

### Audio Utilities

```typescript
// Recording
await RunAnywhere.Audio.requestPermission(): Promise<boolean>
await RunAnywhere.Audio.startRecording(config?: AudioCaptureConfig): Promise<boolean>
await RunAnywhere.Audio.stopRecording(): Promise<Uint8Array | null>

// Playback
await RunAnywhere.Audio.playAudio(audioData: Uint8Array | string, sampleRate?: number): Promise<void>
await RunAnywhere.Audio.stopPlayback(): Promise<void>

// Conversion
RunAnywhere.Audio.createWavFromPCMFloat32(samples: Float32Array, sampleRate?: number): Uint8Array

// Constants
RunAnywhere.Audio.SAMPLE_RATE     // 16000
RunAnywhere.Audio.TTS_SAMPLE_RATE // 22050
```

### Storage

```typescript
await RunAnywhere.getStorageInfo(): Promise<StorageInfo>
await RunAnywhere.getModelsDirectory(): Promise<string>
await RunAnywhere.clearCache(): Promise<void>
```

### Logging

```typescript
await RunAnywhere.setLogLevel(level: LogLevel): Promise<void>

enum LogLevel { NONE, ERROR, WARNING, INFO, DEBUG, VERBOSE }
```

### Conversation Helper

```typescript
const conv = RunAnywhere.conversation();
const r1 = await conv.send('What is AI?');
const r2 = await conv.send('Tell me more');
conv.clear();
```

---

## Core Types

### Enums

```typescript
enum SDKEnvironment { Development, Staging, Production }

enum LLMFramework {
  ONNX, LlamaCpp, Genie, FoundationModels, SystemTTS, // ...
}

enum ModelCategory {
  Language, SpeechRecognition, SpeechSynthesis, Vision,
  ImageGeneration, Multimodal, Audio, Embedding,
}

enum ModelFormat {
  GGUF, ONNX, MLModel, SafeTensors, Bin, Zip, Unknown, // ...
}

enum ExecutionTarget { OnDevice, Cloud, Hybrid }
enum HardwareAcceleration { CPU, GPU, NeuralEngine, NPU }
enum AudioFormat { PCM, WAV, MP3, FLAC, OPUS, AAC }
```

---

## Build System

### Workspace Commands

```bash
cd sdk/runanywhere-react-native

yarn install          # Install all workspace deps
yarn build            # Build all packages (TypeScript)
yarn typecheck        # TypeScript type checking
yarn lint             # ESLint
yarn nitrogen:all     # Regenerate all Nitrogen bindings
```

### Running the Example App

```bash
cd examples/react-native/RunAnywhereAI
yarn install

# Android
yarn android

# iOS
cd ios && pod install && cd ..
yarn ios
```

### Native Library Management

Native `.so` / `.xcframework` files are bundled with the npm packages. Missing ABIs are downloaded automatically:

- **Android**: Gradle `downloadNativeLibs` task downloads from GitHub releases
- **iOS**: XCFrameworks vendored in podspecs

### Package Manager

Uses **Yarn 3.6.1** (Berry). Enable via:
```bash
corepack enable
```

---

## Genie NPU Models

Available on HuggingFace (`runanywhere/genie-npu-models`):

| Model | Slug | Quant | Chips | Size |
|-------|------|-------|-------|------|
| Qwen3 4B | `qwen3-4b` | w4a16 | Gen 5 | 2.5 GB |
| Llama 3.2 1B | `llama3.2-1b-instruct` | w4a16 | Both | 1.3 GB |
| SEA-LION v3.5 8B | `sea-lion3.5-8b-instruct` | w4a16 | Both | 4.5 GB |
| Qwen 2.5 7B | `qwen2.5-7b-instruct` | w8a16 | 8 Elite | 3.9 GB |

**Registering Genie models:**
```typescript
import { Genie } from '@runanywhere/genie';
import { getChip, getNPUDownloadUrl, LLMFramework } from '@runanywhere/core';

if (Platform.OS === 'android' && Genie?.isAvailable) {
  Genie.register();
  const chip = await getChip();
  if (chip) {
    await RunAnywhere.registerModel({
      id: `qwen3-4b-npu-${chip.identifier}`,
      name: `Qwen3 4B (NPU - ${chip.displayName})`,
      url: getNPUDownloadUrl(chip, 'qwen3-4b'),
      framework: LLMFramework.Genie,
      memoryRequirement: 2_800_000_000,
    });
  }
}
```
