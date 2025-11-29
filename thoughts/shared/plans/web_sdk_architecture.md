# RunAnywhere Web Voice SDK - Architecture Document

## Table of Contents

1. [High-Level Architecture Overview](#high-level-architecture-overview)
2. [Package-by-Package Breakdown](#package-by-package-breakdown)
3. [Core Technical Architecture](#core-technical-architecture)
4. [Integration Patterns](#integration-patterns)
5. [Performance Architecture](#performance-architecture)
6. [Design Philosophy & Principles](#design-philosophy--principles)

---

## High-Level Architecture Overview

### System Design Philosophy and Principles

The RunAnywhere Web Voice SDK is built on modern web development principles with a focus on:

1. **Modular Architecture**: 11 discrete packages with clear separation of concerns
2. **Type Safety**: Full TypeScript implementation with strict compiler options
3. **Performance First**: Web Workers, caching, and streaming for optimal UX
4. **Framework Agnostic Core**: Universal services with dedicated UI adapters
5. **Functional Programming**: Result types, immutable patterns, and pure functions
6. **Event-Driven Design**: EventEmitter-based communication between components
7. **Dependency Injection**: Modern DI container with Symbol-based tokens

### Core Architectural Patterns Used

```
┌─────────────────────────────────────────────────────────┐
│                    Framework Layer                       │
├─────────────┬─────────────┬─────────────┬──────────────┤
│   React     │     Vue     │   Angular   │ Pure Web API │
├─────────────┴─────────────┴─────────────┴──────────────┤
│                   Service Layer                         │
├─────────────┬─────────────┬─────────────┬──────────────┤
│    Voice    │    LLM      │    TTS      │ Transcription│
├─────────────┴─────────────┴─────────────┴──────────────┤
│              Infrastructure Layer                       │
├─────────────┬─────────────┬─────────────┬──────────────┤
│   Workers   │   Cache     │  Monitoring │  Optimization│
├─────────────┴─────────────┴─────────────┴──────────────┤
│                    Core Layer                          │
├────────────────────────────────────────────────────────┤
│      DI Container │ Error Handling │ Result Types       │
└────────────────────────────────────────────────────────┘
```

### Package Structure and Organization

The SDK follows a **layered monorepo architecture** using PNPM workspaces:

- **11 Core Packages**: Each with single responsibility
- **Framework-Specific Adapters**: React, Vue, Angular integrations
- **Infrastructure Services**: Workers, caching, monitoring
- **Business Logic**: Voice pipeline, transcription, LLM, TTS

---

## Package-by-Package Breakdown

### 1. `@runanywhere/core` - Foundation Package

**Responsibilities:**
- Dependency Injection container
- Result type system for error handling
- Base error classes and logging
- Performance monitoring utilities
- Type-safe branded types

**Key Components:**

```typescript
// Modern DI Container with Symbol-based tokens
export class DIContainer extends EventEmitter {
  private readonly services = new Map<symbol, ServiceOptions>();
  private readonly singletons = new Map<symbol, any>();
  private readonly health = new Map<symbol, ServiceHealth>();

  async resolve<T>(token: symbol): Promise<T>
  async tryResolve<T>(token: symbol): Promise<Result<T, Error>>
  register<T>(token: symbol, options: ServiceOptions<T>): this
}

// Functional Result Type Pattern
export type Result<T, E = Error> =
  | { success: true; value: T }
  | { success: false; error: E };
```

**Dependencies:** eventemitter3

---

### 2. `@runanywhere/voice` - Core Voice Pipeline

**Responsibilities:**
- Voice Activity Detection (VAD)
- Pipeline orchestration and state management
- Event-driven audio processing flow
- Integration with transcription, LLM, and TTS services

**Key Components:**

```typescript
export class EnhancedVoicePipelineManager extends EventEmitter {
  private vadService?: WebVADService;
  private whisperService?: WhisperService;
  private llmService?: LLMService;
  private ttsService?: TTSService;

  async initialize(): Promise<Result<void, Error>>
  private async processAudio(audio: Float32Array): Promise<void>
}
```

**Architecture Pattern:**
- **Event-Driven Pipeline**: Audio → VAD → Transcription → LLM → TTS
- **Buffered Processing**: Handles concurrent audio input
- **Service Composition**: Lazy-loaded dependent services

**Dependencies:** @runanywhere/core, @runanywhere/transcription, @runanywhere/llm, @runanywhere/tts, @ricky0123/vad-web

---

### 3. `@runanywhere/workers` - Web Worker Management

**Responsibilities:**
- Audio processing in background threads
- LLM inference worker management
- Cross-thread communication protocols
- Fallback strategies for non-worker environments

**Key Components:**

```typescript
export class WorkerManager {
  private audioWorker: Worker | null = null;
  private llmWorker: Worker | null = null;
  private pendingRequests = new Map<string, PendingRequest>();

  async processAudio(audioData: Float32Array): Promise<Result<void, Error>>
  async processLLM(prompt: string, context: Context[]): Promise<Result<void, Error>>
}
```

**Performance Benefits:**
- **Non-blocking UI**: Heavy computations in workers
- **Parallel Processing**: Audio and LLM workers run simultaneously
- **Message Queue**: Handles high-frequency audio data

---

### 4. `@runanywhere/transcription` - Speech-to-Text

**Responsibilities:**
- Whisper model integration
- Audio format conversion
- Streaming transcription support
- Confidence scoring

**Architecture:**
- **Model Loading**: Progressive download and caching
- **Audio Processing**: Float32Array → text conversion
- **Result Streaming**: Partial and final transcription events

---

### 5. `@runanywhere/llm` - Large Language Model Integration

**Responsibilities:**
- OpenAI-compatible API integration
- Streaming response handling
- Context management
- Token counting and rate limiting

**Pattern:**
- **Streaming First**: Server-sent events for real-time responses
- **Context Window Management**: Automatic truncation
- **Response Caching**: Semantic similarity matching

---

### 6. `@runanywhere/tts` - Text-to-Speech

**Responsibilities:**
- Multi-provider TTS support (OpenAI, ElevenLabs, Browser API)
- Audio synthesis and playback
- Voice selection and customization
- Streaming synthesis support

**Features:**
- **Provider Abstraction**: Unified interface across TTS services
- **Audio Buffer Management**: Efficient memory usage
- **Quality Optimization**: Format selection and compression

---

### 7. `@runanywhere/cache` - Intelligent Caching

**Responsibilities:**
- ML model caching (Whisper, VAD models)
- Response caching with semantic similarity
- Storage quota management
- Cache invalidation strategies

**Storage Strategy:**

```
Cache Hierarchy:
┌──────────────────┐
│   Memory Cache   │ <- Hot data, immediate access
├──────────────────┤
│  IndexedDB Cache │ <- Persistent, model storage
├──────────────────┤
│ Network Storage  │ <- CDN, remote models
└──────────────────┘
```

---

### 8. `@runanywhere/monitoring` - Observability

**Responsibilities:**
- Performance metrics collection
- Error tracking and recovery
- Health monitoring for services
- Real-time performance reporting

**Monitoring Stack:**

```typescript
export function createMonitoringStack(config) {
  const performanceMonitor = new PerformanceMonitor(config.performanceThresholds);
  const errorTracker = new ErrorTracker(config.errorTracking);

  return { performanceMonitor, errorTracker };
}
```

---

### 9. `@runanywhere/optimization` - Bundle Optimization

**Responsibilities:**
- Bundle size analysis
- Code splitting optimization
- Tree-shaking reports
- Performance recommendations

---

### 10. `@runanywhere/react` - React Integration

**Responsibilities:**
- React Hooks for voice pipeline
- Pre-built UI components
- State management integration
- TypeScript definitions

**Key Hook:**

```typescript
export function useVoicePipeline(options: UseVoicePipelineOptions):
  [VoicePipelineState, VoicePipelineActions] {

  const [state, setState] = useState<VoicePipelineState>({
    isInitialized: false,
    isListening: false,
    isProcessing: false,
    error: null,
    transcription: '',
    llmResponse: '',
    isPlaying: false
  });

  // Pipeline management logic
}
```

---

### 11. `@runanywhere/vue` & `@runanywhere/angular` - Framework Adapters

**Responsibilities:**
- Framework-specific composables/services
- Component library integration
- Reactive state management
- Plugin/module registration

---

## Core Technical Architecture

### Voice Pipeline Flow and Data Processing

```
Audio Input Flow:
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Microphone     │───▶│   Web Worker    │───▶│   VAD Service   │
│  getUserMedia() │    │  Audio Thread   │    │  Speech/Silence │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                       ┌─────────────────┐              ▼
                       │   Main Thread   │◀─────┌─────────────────┐
                       │   Pipeline      │      │  Speech Detected│
                       │   Manager       │      │  Float32Array   │
                       └─────────────────┘      └─────────────────┘
                              │
Processing Pipeline:           ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Transcription  │───▶│   LLM Service   │───▶│   TTS Service   │───▶│  Audio Playback │
│  (Whisper)      │    │  (OpenAI/etc)   │    │ (Multi-provider)│    │  (Web Audio)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Service Layer Architecture with DI Container

The DI container follows modern patterns with Symbol-based tokens:

```typescript
// Service Registration
const VAD_SERVICE_TOKEN = Symbol.for('VADService');
const WHISPER_SERVICE_TOKEN = Symbol.for('WhisperService');

container.register(VAD_SERVICE_TOKEN, {
  factory: async (container) => {
    const config = await container.resolve(CONFIG_TOKEN);
    return new WebVADService(config.vad);
  },
  lifecycle: 'singleton',
  healthCheck: () => vadService.isHealthy()
});

// Service Resolution with Type Safety
const vadService = await container.resolve<WebVADService>(VAD_SERVICE_TOKEN);
```

**Benefits:**
- **Type Safety**: Compile-time checking of service types
- **Lazy Loading**: Services initialized only when needed
- **Health Monitoring**: Built-in service health checks
- **Circular Dependency Detection**: Prevents initialization deadlocks

### Event-Driven Communication Patterns

All components use EventEmitter3 for loose coupling:

```typescript
// Pipeline events flow
pipeline.on('vadSpeechStart', () => {
  ui.showListening();
});

pipeline.on('transcription', (result: TranscriptionResult) => {
  ui.displayTranscription(result.text);
  analytics.trackTranscription(result);
});

pipeline.on('llmResponse', (result: CompletionResult) => {
  ui.displayResponse(result.text);
  if (autoTTS) pipeline.synthesize(result.text);
});
```

### Error Handling and Result Patterns

**Functional Error Handling** using Result types:

```typescript
// Instead of throwing exceptions
async function transcribeAudio(audio: Float32Array): Promise<Result<TranscriptionResult, Error>> {
  try {
    const result = await whisper.transcribe(audio);
    return Result.ok(result);
  } catch (error) {
    return Result.err(new AudioError('Transcription failed', { cause: error }));
  }
}

// Usage with safe unwrapping
const result = await transcribeAudio(audioData);
if (Result.isOk(result)) {
  console.log('Transcription:', result.value.text);
} else {
  errorTracker.track(result.error);
  showUserFriendlyError(result.error);
}
```

**Benefits:**
- **Explicit Error Handling**: Forces error consideration
- **Composability**: Result types chain naturally
- **Type Safety**: Compiler ensures error handling

### TypeScript Design Patterns Used

**1. Branded Types for Domain Safety:**

```typescript
export type PipelineId = string & { readonly _brand: 'PipelineId' };
export type SessionId = string & { readonly _brand: 'SessionId' };

// Prevents mixing up different ID types
function getPipeline(id: PipelineId): VoicePipeline { /* */ }
```

**2. Discriminated Unions for State Management:**

```typescript
type VoicePipelineState =
  | { status: 'idle' }
  | { status: 'listening' }
  | { status: 'processing'; audio: Float32Array }
  | { status: 'error'; error: Error };
```

**3. Generic Constraints for Service Types:**

```typescript
interface ServiceWithHealth {
  isHealthy(): boolean;
}

class ServiceManager<T extends ServiceWithHealth> {
  async checkHealth(service: T): Promise<boolean> {
    return service.isHealthy();
  }
}
```

---

## Integration Patterns

### How React/Vue/Angular Packages Integrate

**React Integration Pattern:**

```typescript
// Hook-based integration
function VoiceApp() {
  const [state, actions] = useVoicePipeline({
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: true
  });

  return (
    <div>
      <VoicePipelineButton
        isListening={state.isListening}
        onToggle={state.isListening ? actions.stop : actions.start}
      />
      <VoiceChat
        transcription={state.transcription}
        response={state.llmResponse}
        isPlaying={state.isPlaying}
      />
    </div>
  );
}
```

**Vue Integration Pattern:**

```vue
<template>
  <div>
    <VoicePipelineButton
      :is-listening="isListening"
      @toggle="togglePipeline"
    />
    <VoiceChat
      :conversation="conversation"
      :is-processing="isProcessing"
    />
  </div>
</template>

<script setup>
import { useVoicePipeline } from '@runanywhere/vue';

const { state, actions } = useVoicePipeline({
  enableLLM: true,
  enableTTS: true
});

const { isListening, isProcessing, conversation } = toRefs(state);
</script>
```

**Angular Integration Pattern:**

```typescript
@Component({
  template: `
    <voice-pipeline-button
      [isListening]="voiceService.isListening$ | async"
      (toggle)="toggleVoice()">
    </voice-pipeline-button>
  `
})
export class VoiceComponent {
  constructor(public voiceService: VoicePipelineService) {}

  toggleVoice() {
    this.voiceService.toggle();
  }
}
```

### Service Registration and Resolution

**Centralized Service Configuration:**

```typescript
// services.config.ts
export function configureServices(container: DIContainer, config: AppConfig) {
  // Core services
  container.register(LOGGER_TOKEN, {
    factory: () => new Logger(config.logging),
    lifecycle: 'singleton'
  });

  // Audio services
  container.register(VAD_SERVICE_TOKEN, {
    factory: async (c) => {
      const logger = await c.resolve(LOGGER_TOKEN);
      return new WebVADService(config.vad, logger);
    },
    lifecycle: 'singleton',
    eager: true,
    healthCheck: () => vadInstance.isHealthy()
  });

  // Framework integration
  if (config.framework === 'react') {
    container.register(REACT_HOOKS_TOKEN, {
      factory: (c) => new ReactHooksProvider(c),
      lifecycle: 'singleton'
    });
  }
}
```

### Configuration Management

**Hierarchical Configuration System:**

```typescript
interface SDKConfig {
  // Core configuration
  apiKey?: string;
  baseUrl?: string;
  logLevel?: 'debug' | 'info' | 'warn' | 'error';

  // Service configurations
  vad?: VADConfig;
  whisper?: WhisperConfig;
  llm?: LLMConfig;
  tts?: TTSConfig;

  // Performance settings
  enableWorkers?: boolean;
  cacheConfig?: CacheConfig;
  monitoringConfig?: MonitoringConfig;

  // Framework-specific settings
  react?: ReactConfig;
  vue?: VueConfig;
  angular?: AngularConfig;
}

// Configuration merging with defaults
function mergeConfig(userConfig: Partial<SDKConfig>): SDKConfig {
  return {
    ...defaultConfig,
    ...userConfig,
    vad: { ...defaultConfig.vad, ...userConfig.vad },
    whisper: { ...defaultConfig.whisper, ...userConfig.whisper }
  };
}
```

### Health Monitoring System

**Service Health Monitoring:**

```typescript
class HealthMonitor extends EventEmitter {
  async checkSystemHealth(): Promise<SystemHealth> {
    const services = await container.checkHealth();
    const unhealthy = Array.from(services.entries())
      .filter(([, health]) => !health.healthy);

    if (unhealthy.length > 0) {
      this.emit('health:degraded', { unhealthyServices: unhealthy });
    }

    return {
      overall: unhealthy.length === 0 ? 'healthy' : 'degraded',
      services: Object.fromEntries(services),
      timestamp: new Date()
    };
  }
}
```

---

## Performance Architecture

### Web Workers Usage

**Audio Processing Worker:**

```typescript
// audio-processor.worker.ts
import { VADModel } from '@ricky0123/vad-web';
import { WhisperModel } from './whisper-model';

class AudioProcessorWorker {
  private vadModel?: VADModel;
  private whisperModel?: WhisperModel;

  async initialize(config: WorkerConfig): Promise<void> {
    // Load models in worker thread
    this.vadModel = await VADModel.load(config.vadModelUrl);
    this.whisperModel = await WhisperModel.load(config.whisperModelUrl);
  }

  async processAudio(audioData: Float32Array): Promise<ProcessingResult> {
    // VAD processing
    const vadResult = await this.vadModel.predict(audioData);

    if (vadResult.speechDetected) {
      // Transcription in worker
      const transcription = await this.whisperModel.transcribe(audioData);
      return { vadResult, transcription };
    }

    return { vadResult };
  }
}
```

**Benefits:**
- **Non-blocking UI**: Audio processing doesn't freeze interface
- **Parallel Processing**: Multiple workers handle different tasks
- **Model Isolation**: Heavy models loaded in separate contexts

### Model Loading and Caching Strategies

**Progressive Model Loading:**

```typescript
class ModelCache {
  private cache = new Map<string, CachedModel>();

  async loadModel(modelUrl: string, options: LoadOptions): Promise<ArrayBuffer> {
    const cacheKey = this.generateCacheKey(modelUrl, options);

    // Check memory cache first
    if (this.cache.has(cacheKey)) {
      return this.cache.get(cacheKey)!.data;
    }

    // Check IndexedDB cache
    const cached = await this.loadFromIndexedDB(cacheKey);
    if (cached) {
      this.cache.set(cacheKey, cached);
      return cached.data;
    }

    // Download with progress tracking
    const model = await this.downloadWithProgress(modelUrl, (progress) => {
      this.emit('loadProgress', { modelUrl, progress });
    });

    // Cache in both memory and IndexedDB
    await this.saveToIndexedDB(cacheKey, model);
    this.cache.set(cacheKey, model);

    return model.data;
  }
}
```

**Caching Hierarchy:**

1. **Memory Cache**: Immediate access for hot models
2. **IndexedDB Cache**: Persistent storage for downloaded models
3. **Service Worker Cache**: Network-level caching for repeated requests
4. **CDN Cache**: Global edge caching for model distribution

### Streaming Implementations

**LLM Response Streaming:**

```typescript
class LLMService extends EventEmitter {
  async *streamCompletion(prompt: string): AsyncGenerator<string> {
    const response = await fetch('/api/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messages: [{ role: 'user', content: prompt }],
        stream: true
      })
    });

    const reader = response.body!.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const chunk = decoder.decode(value);
      const lines = chunk.split('\n').filter(line => line.startsWith('data: '));

      for (const line of lines) {
        const data = JSON.parse(line.slice(6));
        if (data.choices?.[0]?.delta?.content) {
          const token = data.choices[0].delta.content;
          this.emit('token', { token });
          yield token;
        }
      }
    }
  }
}
```

**TTS Streaming:**

```typescript
class TTSService extends EventEmitter {
  async synthesizeStreaming(text: string): Promise<void> {
    const chunks = this.splitTextIntoChunks(text);
    const audioBuffers: ArrayBuffer[] = [];

    // Parallel synthesis of text chunks
    const synthesisPromises = chunks.map(async (chunk, index) => {
      const audio = await this.synthesizeChunk(chunk);
      audioBuffers[index] = audio;
      this.emit('chunkSynthesized', { index, totalChunks: chunks.length });
    });

    await Promise.all(synthesisPromises);

    // Concatenate and play
    const fullAudio = this.concatenateAudio(audioBuffers);
    this.playAudio(fullAudio);
  }
}
```

### Memory Management Patterns

**Automatic Resource Cleanup:**

```typescript
class VoicePipelineManager {
  private resources = new Set<Disposable>();

  private addResource<T extends Disposable>(resource: T): T {
    this.resources.add(resource);
    return resource;
  }

  destroy(): void {
    // Cleanup all tracked resources
    for (const resource of this.resources) {
      try {
        resource.dispose();
      } catch (error) {
        logger.warn('Error disposing resource', error);
      }
    }
    this.resources.clear();

    // Clear event listeners
    this.removeAllListeners();

    // Cleanup workers
    this.workerManager?.destroy();
  }
}
```

**Memory Pressure Handling:**

```typescript
class MemoryManager {
  constructor() {
    // Monitor memory pressure
    if ('memory' in performance) {
      this.monitorMemoryUsage();
    }
  }

  private monitorMemoryUsage(): void {
    setInterval(() => {
      const memInfo = (performance as any).memory;
      const usage = memInfo.usedJSHeapSize / memInfo.jsHeapSizeLimit;

      if (usage > 0.8) {
        this.emit('memoryPressure', { usage });
        this.freeMemory();
      }
    }, 5000);
  }

  private freeMemory(): void {
    // Clear non-essential caches
    modelCache.clearOldEntries();
    responseCache.clearLRU();

    // Force garbage collection if available
    if ('gc' in window && typeof window.gc === 'function') {
      window.gc();
    }
  }
}
```

---

## Design Philosophy & Principles

### 1. **Progressive Enhancement**
- Core functionality works without advanced features
- Web Workers enhance but don't block basic operation
- Graceful degradation for older browsers

### 2. **Developer Experience First**
- TypeScript for comprehensive type safety
- Clear API boundaries with Result types
- Extensive documentation and examples
- Framework adapters reduce integration complexity

### 3. **Performance by Design**
- Web Workers prevent UI blocking
- Intelligent caching reduces redundant operations
- Streaming implementations for real-time experience
- Memory management prevents leaks

### 4. **Modularity and Extensibility**
- Each package has single responsibility
- Symbol-based DI prevents naming conflicts
- Event-driven architecture allows loose coupling
- Plugin architecture for extending functionality

### 5. **Production Ready**
- Comprehensive error handling and recovery
- Health monitoring and observability
- Performance metrics and optimization
- Automated testing and quality gates

This architecture provides a solid foundation for building sophisticated voice-enabled web applications while maintaining developer productivity and user experience excellence.
