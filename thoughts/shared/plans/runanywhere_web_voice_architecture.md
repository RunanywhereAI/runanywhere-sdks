# RunAnywhere Web Voice SDK - Complete Architecture Documentation

## Executive Summary

This document provides a comprehensive technical architecture overview of the **RunAnywhere Web Voice SDK**, a sophisticated browser-based voice AI pipeline that enables real-time speech-to-text, language model processing, and text-to-speech capabilities. The implementation follows modern web development patterns with TypeScript, event-driven architecture, and modular design principles.

The SDK is built as a monorepo with multiple packages, providing both framework-agnostic core functionality and specific integrations for React, Vue, and Angular. It demonstrates sophisticated dependency injection, result-based error handling, and progressive enhancement patterns optimized for web environments.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Package Structure & Dependencies](#package-structure--dependencies)
3. [Core Foundation Layer](#core-foundation-layer)
4. [Voice Pipeline Architecture](#voice-pipeline-architecture)
5. [Service Integration Patterns](#service-integration-patterns)
6. [Framework Integration Architecture](#framework-integration-architecture)
7. [Build System & TypeScript Configuration](#build-system--typescript-configuration)
8. [Error Handling & Result Patterns](#error-handling--result-patterns)
9. [Performance & Optimization](#performance--optimization)
10. [Integration Examples](#integration-examples)
11. [Technical Implementation Details](#technical-implementation-details)

---

## Architecture Overview

### High-Level System Design

The RunAnywhere Web Voice SDK implements a **layered architecture** inspired by the iOS RunAnywhere SDK, adapted for modern web environments:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FRAMEWORK LAYER                             │
│  React Components • Vue Composables • Angular Services              │
│  Hooks: useVoicePipeline, useVoiceDemo                             │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                       VOICE PIPELINE LAYER                         │
│  VoicePipelineManager • EnhancedVoicePipelineManager               │
│  Pipeline Orchestration • Event Management • State Machine         │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                        SERVICES LAYER                              │
│  VAD Service • Whisper Service • LLM Service • TTS Service         │
│  Web Audio API • Transformers.js • Web Speech API                  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                       CORE FOUNDATION                               │
│  DI Container • Result Types • Error Handling • Logging            │
│  Event System • Performance Monitoring • TypeScript Types          │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Architectural Principles

1. **Modern TypeScript-First Design**: Leverages TypeScript 5.7+ with strict compiler settings
2. **Event-Driven Architecture**: Uses EventEmitter3 for real-time communication
3. **Dependency Injection**: Symbol-based DI container with health checks
4. **Result Pattern**: Rust-inspired error handling without exceptions
5. **Modular Package Design**: Each capability is a separate npm package
6. **Progressive Enhancement**: Graceful degradation across browser capabilities
7. **Performance Optimization**: WebGPU acceleration, Web Workers, streaming

---

## Package Structure & Dependencies

### Monorepo Organization

```
@runanywhere/web-voice-sdk/
├── packages/
│   ├── core/                    # Foundation utilities & types
│   ├── voice/                   # Voice pipeline orchestration
│   ├── transcription/           # Speech-to-text (Whisper)
│   ├── llm/                    # Language model integration
│   ├── tts/                    # Text-to-speech synthesis
│   ├── cache/                  # Model caching & storage
│   ├── monitoring/             # Performance monitoring
│   ├── workers/                # Web Worker utilities
│   ├── optimization/           # Bundle optimization
│   ├── react/                  # React integration
│   ├── vue/                    # Vue.js integration
│   └── angular/                # Angular integration
└── examples/
    └── react-demo/             # Complete React demonstration
```

### Package Dependencies Matrix

| Package | Core | Voice | Transcription | LLM | TTS | External |
|---------|------|-------|---------------|-----|-----|----------|
| **core** | - | - | - | - | - | `eventemitter3` |
| **voice** | ✓ | - | - | - | - | `@ricky0123/vad-web` |
| **transcription** | ✓ | - | - | - | - | `@xenova/transformers` |
| **llm** | ✓ | - | - | - | - | `eventsource-parser` |
| **tts** | ✓ | - | - | - | - | Web Speech API |
| **react** | ✓ | ✓ | ✓ | ✓ | ✓ | `react@18` |

### Build System

The project uses **pnpm workspaces** with **Vite** for building and **TypeScript** for type checking:

```json
{
  "scripts": {
    "build": "pnpm build:core && pnpm build:packages",
    "build:core": "pnpm --filter '@runanywhere/core' build",
    "build:packages": "sequential package building with dependency order"
  }
}
```

Each package follows a consistent build pattern:
1. **TypeScript compilation** for declaration files
2. **Vite bundling** for optimized JavaScript
3. **ESM modules** for modern browsers
4. **Source maps** for debugging

---

## Core Foundation Layer

### Dependency Injection Container

The DI system uses **Symbol-based tokens** for type safety and modern async patterns:

```typescript
// Modern service token creation
export const ServiceToken = (name: string): symbol => Symbol.for(name);

// Service registration with lifecycle management
container.register(VAD_SERVICE_TOKEN, {
  factory: async (container) => {
    const vad = new WebVADService();
    await vad.initialize(config.vadConfig);
    return vad;
  },
  lifecycle: 'singleton',
  healthCheck: async () => vad.isHealthy()
});
```

**Key Features:**
- **Async service resolution** with `Promise<T>`
- **Health monitoring** for all services
- **Circular dependency detection**
- **Event-driven lifecycle** notifications
- **Scoped containers** for isolation

### Result Pattern Implementation

Inspired by Rust's `Result<T, E>`, providing explicit error handling:

```typescript
export type Result<T, E = Error> =
  | { success: true; value: T }
  | { success: false; error: E };

// Usage in service methods
async transcribe(audio: Float32Array): Promise<Result<TranscriptionResult, Error>> {
  try {
    const result = await this.processAudio(audio);
    return Result.ok(result);
  } catch (error) {
    return Result.err(error instanceof Error ? error : new Error(String(error)));
  }
}
```

### Error Hierarchy

Structured error system with context preservation:

```typescript
export abstract class BaseError extends Error {
  public readonly timestamp: Date;
  public readonly context?: Record<string, unknown>;

  constructor(message: string, public readonly code: string, context?: Record<string, unknown>) {
    super(message);
    this.timestamp = new Date();
    this.context = context;
    Error.captureStackTrace(this, this.constructor);
  }
}

// Specialized error types
export class AudioError extends SDKError { /* */ }
export class ModelError extends SDKError { /* */ }
export class NetworkError extends SDKError { /* */ }
```

---

## Voice Pipeline Architecture

### Pipeline Manager Design

The voice pipeline orchestrates multiple AI services through a **state machine** with comprehensive **event system**:

```typescript
export enum PipelineState {
  IDLE = 'idle',
  INITIALIZING = 'initializing',
  READY = 'ready',
  RUNNING = 'running',
  PAUSED = 'paused',
  ERROR = 'error',
  DESTROYED = 'destroyed'
}
```

### Two-Tier Pipeline Design

**1. Basic Pipeline Manager** (`VoicePipelineManager`):
- **Component-based configuration** (VAD, STT, LLM, TTS)
- **Lifecycle management** with state tracking
- **Metrics collection** and health monitoring
- **Error recovery** and graceful degradation

**2. Enhanced Pipeline Manager** (`EnhancedVoicePipelineManager`):
- **End-to-end workflow** automation
- **Conversation management** with history
- **Streaming support** for real-time processing
- **Auto-play capabilities** for TTS output

### Event-Driven Communication

The pipeline uses **discriminated unions** for type-safe event handling:

```typescript
export type PipelineEvent =
  // Lifecycle events
  | { type: 'initialized'; components: PipelineComponent[] }
  | { type: 'started'; timestamp: number }
  | { type: 'error'; error: Error; component?: PipelineComponent }

  // Processing events
  | { type: 'vad:speech_start'; timestamp: number }
  | { type: 'vad:speech_end'; audio: Float32Array; duration: number }
  | { type: 'stt:transcription'; text: string; confidence?: number }
  | { type: 'llm:streaming'; token: string }
  | { type: 'tts:audio_chunk'; chunk: ArrayBuffer };
```

### Pipeline Workflow

```
Audio Input → VAD Detection → Speech Extraction → STT Processing → LLM Generation → TTS Synthesis → Audio Output
     ↓              ↓                ↓               ↓              ↓               ↓
Event: 'audio_level' 'speech_start'  'speech_end'   'transcription' 'llm:streaming' 'tts:audio_chunk'
```

---

## Service Integration Patterns

### Voice Activity Detection (VAD)

**Integration**: `@ricky0123/vad-web` with Web Audio API

```typescript
export class WebVADService extends EventEmitter implements VADService {
  private vad: MicVAD | null = null;

  async initialize(config: Partial<VADConfig> = {}): Promise<void> {
    this.vad = await MicVAD.new({
      positiveSpeechThreshold: config.positiveSpeechThreshold || 0.9,
      onSpeechStart: () => this.handleSpeechStart(),
      onSpeechEnd: (audio: Float32Array) => this.handleSpeechEnd(audio)
    });
  }
}
```

**Features:**
- **Browser compatibility checks** for required APIs
- **Real-time audio level monitoring** at 10Hz
- **Speech energy calculation** with moving averages
- **Configurable thresholds** for sensitivity tuning
- **Performance metrics** tracking

### Speech-to-Text (Whisper)

**Integration**: `@xenova/transformers` with ONNX Runtime

```typescript
export class WhisperService extends EventEmitter {
  private transcriber: Pipeline | null = null;

  async initialize(): Promise<Result<void, Error>> {
    this.transcriber = await pipeline(
      'automatic-speech-recognition',
      `Xenova/${this.config.model}.en`,
      {
        progress_callback: (progress) => this.emit('downloadProgress', progress)
      }
    );
  }
}
```

**Features:**
- **Multiple Whisper model sizes** (tiny, base, small)
- **Progressive model downloading** with progress tracking
- **Browser caching** using Transformers.js cache
- **Streaming transcription** with partial results
- **WebGPU acceleration** when available

### Language Model Integration

**Architecture**: OpenAI-compatible API with streaming support

```typescript
export class LLMService extends EventEmitter {
  async complete(prompt: string): Promise<Result<CompletionResult, Error>> {
    const response = await fetch(`${config.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: config.model,
        messages: this.conversationHistory.slice(-10),
        stream: config.streamingEnabled
      })
    });

    // Handle streaming responses with Server-Sent Events
    if (config.streamingEnabled) {
      return this.handleStreamingResponse(response);
    }
  }
}
```

**Features:**
- **Conversation history management** (last 10 messages)
- **Server-Sent Events** for token streaming
- **Configurable parameters** (temperature, max tokens)
- **System prompt injection** with conversation context
- **Timeout handling** with abort controllers

### Text-to-Speech (TTS)

**Integration**: Web Speech API with AudioContext

```typescript
export class TTSService extends EventEmitter {
  private synthesizer?: SpeechSynthesis;
  private audioContext?: AudioContext;

  async synthesize(text: string): Promise<Result<SynthesisResult, Error>> {
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.voice = this.selectOptimalVoice();
    utterance.rate = config.rate;

    const audioBuffer = await this.synthesizeToBuffer(utterance);
    return Result.ok({ audioBuffer, duration: audioBuffer.duration });
  }
}
```

**Features:**
- **Voice selection algorithm** (local > language > default)
- **Audio buffer capture** for advanced processing
- **Streaming synthesis** by sentence segmentation
- **Playback control** with AudioContext
- **Gender detection** from voice names

---

## Framework Integration Architecture

### React Integration Pattern

**Hook-based approach** with TypeScript generics:

```typescript
export function useVoicePipeline(
  options: UseVoicePipelineOptions = {}
): [VoicePipelineState, VoicePipelineActions] {
  const pipelineRef = useRef<EnhancedVoicePipelineManager | null>(null);
  const containerRef = useRef<DIContainer | null>(null);

  const [state, setState] = useState<VoicePipelineState>({
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    error: null,
    transcription: '',
    llmResponse: '',
    isPlaying: false
  });

  // Event handler setup with proper cleanup
  useEffect(() => {
    const pipeline = pipelineRef.current;
    if (!pipeline) return;

    const handlers = {
      started: () => setState(prev => ({ ...prev, isListening: true })),
      transcription: (result) => setState(prev => ({ ...prev, transcription: result.text })),
      error: (error) => setState(prev => ({ ...prev, error }))
    };

    Object.entries(handlers).forEach(([event, handler]) => {
      pipeline.on(event, handler);
    });

    return () => {
      Object.entries(handlers).forEach(([event, handler]) => {
        pipeline.off(event, handler);
      });
    };
  }, []);
}
```

### Vue Integration (Composables)

**Composition API** with reactive state management:

```typescript
export function useVoicePipeline(options: VoicePipelineOptions) {
  const pipeline = ref<VoicePipeline | null>(null);
  const isInitialized = ref(false);

  onMounted(async () => {
    const sdk = WebVoiceSDK.getInstance();
    await sdk.initialize(config);
    pipeline.value = await sdk.createVoicePipeline(options);
    isInitialized.value = true;
  });

  return {
    pipeline: readonly(pipeline),
    isInitialized: readonly(isInitialized)
  };
}
```

### Angular Integration (Services)

**Injectable services** with RxJS observables:

```typescript
@Injectable({ providedIn: 'root' })
export class VoicePipelineService {
  private pipelineSubject = new BehaviorSubject<VoicePipeline | null>(null);
  public pipeline$ = this.pipelineSubject.asObservable();

  processVoiceStream(audioStream: ReadableStream<AudioChunk>): Observable<PipelineEvent> {
    return new Observable(subscriber => {
      const pipeline = this.pipelineSubject.value;
      if (!pipeline) return;

      const eventStream = pipeline.processStream(audioStream);
      // Convert ReadableStream to Observable
      this.streamToObservable(eventStream, subscriber);
    });
  }
}
```

---

## Build System & TypeScript Configuration

### TypeScript Configuration Strategy

**Base configuration** (`tsconfig.base.json`) with strict settings:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "moduleResolution": "bundler",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "declaration": true,
    "declarationMap": true,
    "composite": true,
    "incremental": true
  }
}
```

### Build Pipeline Architecture

**Sequential build process** respecting dependency graph:

```bash
#!/bin/bash
# Build order ensures proper dependency resolution

echo "📦 Building @runanywhere/core..."
cd packages/core && npx tsc --emitDeclarationOnly && npx vite build

echo "📦 Building service packages..."
for pkg in cache monitoring workers transcription llm tts; do
  cd packages/$pkg && npx tsc --emitDeclarationOnly && npx vite build && cd ../..
done

echo "📦 Building @runanywhere/voice..."
cd packages/voice && npx tsc --emitDeclarationOnly && npx vite build

echo "📦 Building framework adapters..."
for framework in react vue angular; do
  cd packages/$framework && pnpm build && cd ../..
done
```

### Vite Configuration

**Modern bundling** with ESM output:

```typescript
export default defineConfig({
  build: {
    lib: {
      entry: 'src/index.ts',
      formats: ['es'],
      fileName: 'index'
    },
    rollupOptions: {
      external: ['eventemitter3', '@xenova/transformers']
    },
    sourcemap: true,
    minify: 'terser'
  }
});
```

---

## Error Handling & Result Patterns

### Comprehensive Error Strategy

**1. Error Classification Hierarchy**:
```typescript
BaseError
├── SDKError
│   ├── ConfigurationError
│   ├── InitializationError
│   ├── AudioError
│   ├── ModelError
│   └── NetworkError
└── ValidationError
```

**2. Result Pattern Usage**:
```typescript
// Service methods return Results instead of throwing
const transcribeResult = await whisperService.transcribe(audio);
if (Result.isErr(transcribeResult)) {
  logger.error(`Transcription failed: ${transcribeResult.error.message}`);
  return this.handleTranscriptionError(transcribeResult.error);
}

const transcription = transcribeResult.value;
```

**3. Error Recovery Strategies**:
- **Service fallbacks** (WebGPU → WASM → Cloud)
- **Automatic retries** with exponential backoff
- **Graceful degradation** when components fail
- **User-friendly error messages** with context

### Pipeline Error Handling

**Error propagation** through the pipeline with recovery:

```typescript
private async processAudio(audio: Float32Array): Promise<void> {
  try {
    // Process through pipeline stages
    const transcription = await this.whisperService.transcribe(audio);
    if (Result.isErr(transcription)) {
      throw transcription.error;
    }

    // Continue pipeline...
  } catch (error) {
    // Emit error event with context
    this.emitEvent({
      type: 'error',
      error: error instanceof Error ? error : new Error(String(error)),
      component: 'stt'
    });

    // Attempt recovery
    await this.recoverFromError(error, 'stt');
  }
}
```

---

## Performance & Optimization

### Model Loading & Caching

**Intelligent caching strategy**:
- **IndexedDB storage** for large models
- **Browser cache API** for smaller assets
- **Progressive loading** with streaming
- **LRU eviction** for memory management

### Web Worker Integration

**Offloading heavy processing**:

```typescript
export class AudioProcessingWorker {
  async processAudio(audioData: Float32Array): Promise<ProcessedAudio> {
    // Perform heavy audio processing in worker thread
    const processed = await this.applyFilters(audioData);
    return { processed, metadata: this.extractMetadata(audioData) };
  }
}
```

### WebGPU Acceleration

**GPU-accelerated inference** when available:

```typescript
// Transformers.js with WebGPU backend
env.backends.onnx.wasm.numThreads = navigator.hardwareConcurrency || 1;
env.backends.onnx.webgpu.preferredAdapter = 'high-performance';

const transcriber = await pipeline('automatic-speech-recognition', model, {
  executionProviders: ['webgpu', 'wasm']
});
```

### Memory Management

**Resource optimization patterns**:
- **WeakRef collections** for cached resources
- **Automatic cleanup** on component destruction
- **Memory pressure monitoring** with thresholds
- **Streaming processing** to minimize memory usage

---

## Integration Examples

### Complete React Integration

**Real-world usage** with the demo application:

```typescript
// useVoiceDemo.ts - Main application hook
export function useVoiceDemo() {
  const [settings, setSettings] = useState<DemoSettings>(() =>
    demoConfig.loadSettings()
  );

  // Convert demo settings to pipeline options
  const pipelineOptions: UseVoicePipelineOptions = useMemo(() => ({
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: settings.autoPlayTTS,
    whisperConfig: { model: settings.whisperModel },
    llmConfig: {
      apiKey: settings.apiKey,
      baseUrl: settings.llmEndpoint,
      systemPrompt: settings.systemPrompt
    }
  }), [settings]);

  // Use the actual voice pipeline
  const [pipelineState, pipelineActions] = useVoicePipeline(pipelineOptions);

  // Handle conversation flow
  useEffect(() => {
    if (pipelineState.llmResponse) {
      // Add complete interaction to history
      setConversationHistory(prev => [...prev, {
        user: pipelineState.transcription,
        assistant: pipelineState.llmResponse,
        timestamp: Date.now()
      }]);
    }
  }, [pipelineState.llmResponse]);
}
```

### Voice Assistant Component

**Production-ready UI component**:

```typescript
export function VoiceAssistant({ onShowSettings, ...props }: VoiceAssistantProps) {
  const handleToggleConversation = useCallback(async () => {
    if (props.isActive) {
      await props.stopConversation();
    } else {
      await props.startConversation();
    }
  }, [props.isActive, props.startConversation, props.stopConversation]);

  // Render with error boundaries and loading states
  if (props.error) return <ErrorDisplay error={props.error} />;
  if (!props.isInitialized) return <LoadingState />;

  return (
    <div className="voice-assistant">
      <VoiceControls
        onToggle={handleToggleConversation}
        isActive={props.isActive}
        isListening={props.isListening}
      />
      <ConversationHistory messages={props.conversationHistory} />
      <AudioVisualizer level={props.audioLevel} />
    </div>
  );
}
```

---

## Technical Implementation Details

### DI Container Patterns

**Advanced service registration** with health monitoring:

```typescript
export class DIContainer extends EventEmitter {
  async resolve<T>(token: symbol): Promise<T> {
    const options = this.services.get(token);

    switch (options.lifecycle) {
      case 'singleton':
        return this.resolveSingleton<T>(token, options);
      case 'transient':
        return this.createInstance<T>(options);
      case 'scoped':
        return this.createScopedInstance<T>(options);
    }
  }

  async checkHealth(): Promise<Map<symbol, ServiceHealth>> {
    const healthChecks = Array.from(this.services.entries())
      .filter(([_, options]) => options.healthCheck)
      .map(([token, options]) => this.runHealthCheck(token, options.healthCheck));

    return new Map(await Promise.all(healthChecks));
  }
}
```

### Event System Architecture

**Type-safe event handling** with discrimination:

```typescript
export interface PipelineEvents {
  'initialized': { components: PipelineComponent[] };
  'vad:speech_start': { timestamp: number };
  'stt:transcription': { text: string; confidence?: number };
  'llm:streaming': { token: string; position: number };
  'error': { error: Error; component?: PipelineComponent };
}

class TypedEventEmitter<T extends Record<string, any>> extends EventEmitter {
  emit<K extends keyof T>(eventName: K, ...args: T[K] extends undefined ? [] : [T[K]]): boolean {
    return super.emit(eventName as string, ...args);
  }

  on<K extends keyof T>(eventName: K, listener: (args: T[K]) => void): this {
    return super.on(eventName as string, listener);
  }
}
```

### Streaming Data Processing

**Real-time audio processing** with backpressure handling:

```typescript
export class VoicePipelineManager {
  async processStream(audioStream: ReadableStream<AudioChunk>): Promise<ReadableStream<PipelineEvent>> {
    return new ReadableStream({
      start: async (controller) => {
        const reader = audioStream.getReader();

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            // Process audio chunk through pipeline
            const events = await this.processAudioChunk(value);
            events.forEach(event => controller.enqueue(event));
          }
        } finally {
          reader.releaseLock();
          controller.close();
        }
      }
    });
  }
}
```

### Performance Monitoring

**Comprehensive metrics collection**:

```typescript
export interface PipelineMetrics {
  sessionsProcessed: number;
  totalProcessingTime: number;
  averageLatency: number;
  componentMetrics: Map<PipelineComponent, {
    invocations: number;
    totalTime: number;
    errors: number;
  }>;
}

private trackComponentPerformance<T>(
  component: PipelineComponent,
  operation: () => Promise<T>
): Promise<T> {
  const startTime = performance.now();
  const metrics = this.metrics.componentMetrics.get(component);

  metrics.invocations++;

  return operation().finally(() => {
    metrics.totalTime += performance.now() - startTime;
  });
}
```

---

## Conclusion

The RunAnywhere Web Voice SDK demonstrates **sophisticated architectural patterns** adapted for modern web development:

### Key Achievements

1. **Modern Web Standards**: Leverages cutting-edge browser APIs (WebGPU, Web Audio, Speech Synthesis)
2. **Type Safety**: Comprehensive TypeScript implementation with strict compiler settings
3. **Performance Optimization**: WebGPU acceleration, Web Workers, streaming processing
4. **Developer Experience**: Intuitive APIs, comprehensive error handling, extensive documentation
5. **Framework Flexibility**: Supports React, Vue, Angular with consistent patterns
6. **Production Ready**: Error recovery, health monitoring, performance tracking

### Architectural Strengths

- **Modular Design**: Each package has clear boundaries and responsibilities
- **Event-Driven Communication**: Real-time updates through type-safe event system
- **Dependency Injection**: Modern Symbol-based DI with async resolution
- **Result Pattern**: Explicit error handling without exceptions
- **Progressive Enhancement**: Graceful degradation across browser capabilities

### Innovation Highlights

- **Enhanced Pipeline Manager**: End-to-end voice conversation automation
- **Streaming Integration**: Real-time token streaming from LLM services
- **Health Monitoring**: Comprehensive service health checks and recovery
- **Multi-Framework Support**: Consistent APIs across React, Vue, and Angular
- **Performance Metrics**: Detailed tracking of pipeline performance and latency

This implementation serves as a **reference architecture** for building sophisticated voice AI applications in the browser, demonstrating how to combine multiple AI services into a cohesive, performant, and maintainable system.
