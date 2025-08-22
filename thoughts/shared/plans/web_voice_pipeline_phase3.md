# RunAnywhere Web Voice Pipeline - Phase 3 Implementation Plan

## Overview
Phase 3 completes the voice pipeline implementation by connecting real models, adding TTS capabilities, implementing Web Workers for performance, and creating framework adapters for React, Vue, and Angular.

## Prerequisites
- ✅ Phase 1: Core foundation and VAD implementation
- ✅ Phase 2: Whisper transcription and LLM service structure
- Current state: Services implemented but not connected to actual models

## Phase 3 Objectives

### Primary Goals
1. **Complete Model Integration**: Connect Whisper and LLM to actual models/APIs
2. **Add TTS Capability**: Implement text-to-speech synthesis
3. **Performance Optimization**: Implement Web Workers for audio processing
4. **Framework Adapters**: Create React, Vue, and Angular components
5. **Production Readiness**: Bundle optimization, caching, and testing

### Deferred Items from Phase 2
- Actual Whisper model loading and inference
- Real LLM API endpoint integration
- Web Worker implementation for audio processing
- Model caching and management system
- Integration tests with actual models

## Technical Architecture

### 3.1 Model Integration Layer

```
┌─────────────────────────────────────────────────────────────────┐
│                     Model Management System                      │
├─────────────────────────────────────────────────────────────────┤
│  Model Loader │ Cache Manager │ Version Control │ Auto-Update   │
├─────────────────────────────────────────────────────────────────┤
│          IndexedDB Storage     │     Cache API                  │
└─────────────────────────────────────────────────────────────────┘
                                 │
┌─────────────────────────────────────────────────────────────────┐
│                      Model Inference Layer                       │
├──────────────────┬────────────────────┬────────────────────────┤
│   Whisper ONNX   │    LLM Client     │    TTS Engine          │
│  (Transformers)  │   (Streaming)     │   (ONNX/Native)        │
└──────────────────┴────────────────────┴────────────────────────┘
```

### 3.2 Web Worker Architecture

```
Main Thread                          Worker Thread
────────────                         ──────────────

Audio Input ──────────────────────> Audio Processor
     │                                      │
     v                                      v
Event Manager <─────────────────── Processing Queue
     │                                      │
     v                                      v
UI Updates <──────────────────────── Result Stream
```

## Implementation Tasks

### Stage 1: Model Integration (Week 1-2)

#### 1.1 Whisper Model Setup
**Package**: `@runanywhere/transcription`

```typescript
// src/models/whisper-loader.ts
export class WhisperModelLoader {
  private modelCache: Map<string, Pipeline>

  async loadModel(modelId: string): Promise<Pipeline> {
    // Check cache first
    if (this.modelCache.has(modelId)) {
      return this.modelCache.get(modelId)!
    }

    // Load from Transformers.js
    const pipeline = await pipeline(
      'automatic-speech-recognition',
      modelId,
      {
        quantized: true,
        progress_callback: this.onProgress
      }
    )

    this.modelCache.set(modelId, pipeline)
    return pipeline
  }

  async preloadModels(): Promise<void> {
    // Preload common models
    await this.loadModel('Xenova/whisper-tiny')
    await this.loadModel('Xenova/whisper-base')
  }
}
```

**Tasks**:
- [ ] Implement WhisperModelLoader with caching
- [ ] Add model download progress tracking
- [ ] Implement model size selection (tiny, base, small)
- [ ] Add language detection capability
- [ ] Create model fallback mechanism

#### 1.2 LLM API Integration
**Package**: `@runanywhere/llm`

```typescript
// src/clients/llm-api-client.ts
export class LLMAPIClient {
  constructor(
    private config: {
      apiKey: string
      baseUrl: string
      model: string
      maxRetries: number
    }
  ) {}

  async streamCompletion(
    messages: Message[],
    options: CompletionOptions
  ): AsyncGenerator<string> {
    const response = await fetch(`${this.baseUrl}/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: this.model,
        messages,
        stream: true,
        ...options
      })
    })

    const reader = response.body?.getReader()
    const decoder = new TextDecoder()

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      const chunk = decoder.decode(value)
      const lines = chunk.split('\n')

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = JSON.parse(line.slice(6))
          if (data.choices?.[0]?.delta?.content) {
            yield data.choices[0].delta.content
          }
        }
      }
    }
  }
}
```

**Tasks**:
- [ ] Implement OpenAI-compatible API client
- [ ] Add Anthropic Claude API support
- [ ] Implement retry logic with exponential backoff
- [ ] Add request/response caching
- [ ] Create API key validation
- [ ] Add usage tracking and cost estimation

#### 1.3 Model Caching System
**Package**: `@runanywhere/models`

```typescript
// src/cache/model-cache-manager.ts
export class ModelCacheManager {
  private db: IDBDatabase

  async initialize(): Promise<void> {
    this.db = await this.openDatabase()
  }

  async cacheModel(
    modelId: string,
    modelData: ArrayBuffer,
    metadata: ModelMetadata
  ): Promise<void> {
    const transaction = this.db.transaction(['models'], 'readwrite')
    const store = transaction.objectStore('models')

    await store.put({
      id: modelId,
      data: modelData,
      metadata,
      timestamp: Date.now()
    })
  }

  async getCachedModel(modelId: string): Promise<CachedModel | null> {
    const transaction = this.db.transaction(['models'], 'readonly')
    const store = transaction.objectStore('models')
    return await store.get(modelId)
  }

  async cleanupOldModels(maxAge: number): Promise<void> {
    // Remove models older than maxAge
  }
}
```

**Tasks**:
- [ ] Implement IndexedDB storage for models
- [ ] Add Cache API integration for faster access
- [ ] Create LRU eviction policy
- [ ] Add model versioning support
- [ ] Implement storage quota management

### Stage 2: TTS Implementation (Week 3)

#### 2.1 TTS Service
**Package**: `@runanywhere/tts` (new)

```typescript
// src/services/tts-service.ts
export class TTSService extends EventEmitter {
  private synthesizer: SpeechSynthesizer | null = null
  private audioContext: AudioContext

  async initialize(config?: TTSConfig): Promise<Result<void, Error>> {
    try {
      // Option 1: Use native Web Speech API
      if ('speechSynthesis' in window) {
        this.useNativeTTS = true
      }

      // Option 2: Use ONNX model
      else {
        this.synthesizer = await this.loadONNXModel(config.modelPath)
      }

      this.audioContext = new AudioContext()
      return Result.ok(undefined)
    } catch (error) {
      return Result.err(error)
    }
  }

  async synthesize(
    text: string,
    options?: TTSOptions
  ): Promise<Result<AudioBuffer, Error>> {
    if (this.useNativeTTS) {
      return this.synthesizeNative(text, options)
    } else {
      return this.synthesizeONNX(text, options)
    }
  }
}
```

**Tasks**:
- [ ] Create TTS package structure
- [ ] Implement native Web Speech API wrapper
- [ ] Add ONNX TTS model support (Piper, Coqui)
- [ ] Implement voice selection
- [ ] Add SSML support
- [ ] Create audio streaming capability

### Stage 3: Web Worker Implementation (Week 4)

#### 3.1 Audio Processing Worker
**File**: `packages/web-audio/src/workers/audio-processor.worker.ts`

```typescript
// audio-processor.worker.ts
class AudioProcessorWorker {
  private vad: VADProcessor
  private bufferSize = 4096
  private sampleRate = 16000

  constructor() {
    self.addEventListener('message', this.handleMessage.bind(this))
  }

  private handleMessage(event: MessageEvent) {
    const { type, data } = event.data

    switch (type) {
      case 'initialize':
        this.initialize(data)
        break
      case 'process':
        this.processAudio(data)
        break
      case 'stop':
        this.cleanup()
        break
    }
  }

  private async processAudio(audioData: Float32Array) {
    // Resample if needed
    const resampled = this.resample(audioData, this.sampleRate)

    // Run VAD
    const isSpeech = await this.vad.process(resampled)

    // Send results back to main thread
    self.postMessage({
      type: 'result',
      data: {
        isSpeech,
        audio: resampled,
        energy: this.calculateEnergy(resampled)
      }
    })
  }
}

new AudioProcessorWorker()
```

**Tasks**:
- [ ] Create Web Worker infrastructure
- [ ] Implement audio resampling in worker
- [ ] Add ring buffer for continuous processing
- [ ] Implement worker pool for parallel processing
- [ ] Add SharedArrayBuffer support where available
- [ ] Create fallback for non-worker environments

#### 3.2 Model Inference Worker
**File**: `packages/models/src/workers/inference.worker.ts`

```typescript
// inference.worker.ts
class InferenceWorker {
  private whisperModel: Pipeline | null = null

  async loadModel(modelPath: string) {
    this.whisperModel = await pipeline(
      'automatic-speech-recognition',
      modelPath
    )

    self.postMessage({ type: 'model-loaded' })
  }

  async transcribe(audio: Float32Array) {
    if (!this.whisperModel) {
      throw new Error('Model not loaded')
    }

    const result = await this.whisperModel(audio, {
      return_timestamps: true,
      chunk_length_s: 30,
      stride_length_s: 5
    })

    self.postMessage({
      type: 'transcription',
      data: result
    })
  }
}
```

**Tasks**:
- [ ] Create inference worker for Whisper
- [ ] Add batch processing capability
- [ ] Implement progress reporting
- [ ] Add memory management
- [ ] Create worker termination handling

### Stage 4: Framework Adapters (Week 5-6)

#### 4.1 React Adapter
**Package**: `@runanywhere/react`

```typescript
// src/hooks/useVoicePipeline.ts
export function useVoicePipeline(config?: VoiceConfig) {
  const [isListening, setIsListening] = useState(false)
  const [transcript, setTranscript] = useState('')
  const [isProcessing, setIsProcessing] = useState(false)

  const pipelineRef = useRef<VoicePipelineManager>()

  useEffect(() => {
    const pipeline = new VoicePipelineManager(config)

    pipeline.on('transcription', (result) => {
      setTranscript(result.text)
    })

    pipeline.on('processing', (state) => {
      setIsProcessing(state)
    })

    pipelineRef.current = pipeline

    return () => {
      pipeline.destroy()
    }
  }, [])

  const startListening = useCallback(async () => {
    await pipelineRef.current?.start()
    setIsListening(true)
  }, [])

  const stopListening = useCallback(() => {
    pipelineRef.current?.stop()
    setIsListening(false)
  }, [])

  return {
    isListening,
    transcript,
    isProcessing,
    startListening,
    stopListening
  }
}
```

**Components**:
```typescript
// src/components/VoiceButton.tsx
export function VoiceButton({ onTranscript, ...props }) {
  const { isListening, transcript, startListening, stopListening } = useVoicePipeline()

  useEffect(() => {
    if (transcript) {
      onTranscript(transcript)
    }
  }, [transcript, onTranscript])

  return (
    <button
      onClick={isListening ? stopListening : startListening}
      className={isListening ? 'listening' : ''}
      {...props}
    >
      {isListening ? '🔴 Stop' : '🎤 Start'}
    </button>
  )
}
```

**Tasks**:
- [ ] Create React package with TypeScript
- [ ] Implement core hooks (useVoicePipeline, useWhisper, useTTS)
- [ ] Create UI components (VoiceButton, TranscriptDisplay, AudioVisualizer)
- [ ] Add context provider for global configuration
- [ ] Create demo React app
- [ ] Write tests with React Testing Library

#### 4.2 Vue Adapter
**Package**: `@runanywhere/vue`

```typescript
// src/composables/useVoicePipeline.ts
export function useVoicePipeline(config?: VoiceConfig) {
  const isListening = ref(false)
  const transcript = ref('')
  const isProcessing = ref(false)

  let pipeline: VoicePipelineManager | null = null

  onMounted(async () => {
    pipeline = new VoicePipelineManager(config)

    pipeline.on('transcription', (result) => {
      transcript.value = result.text
    })

    pipeline.on('processing', (state) => {
      isProcessing.value = state
    })
  })

  onUnmounted(() => {
    pipeline?.destroy()
  })

  const startListening = async () => {
    await pipeline?.start()
    isListening.value = true
  }

  const stopListening = () => {
    pipeline?.stop()
    isListening.value = false
  }

  return {
    isListening: readonly(isListening),
    transcript: readonly(transcript),
    isProcessing: readonly(isProcessing),
    startListening,
    stopListening
  }
}
```

**Tasks**:
- [ ] Create Vue package with TypeScript
- [ ] Implement composables for Vue 3
- [ ] Create Vue components with slots
- [ ] Add Pinia store integration
- [ ] Create demo Vue app
- [ ] Write tests with Vitest

#### 4.3 Angular Adapter
**Package**: `@runanywhere/angular`

```typescript
// src/services/voice-pipeline.service.ts
@Injectable({
  providedIn: 'root'
})
export class VoicePipelineService {
  private pipeline: VoicePipelineManager
  private transcriptSubject = new BehaviorSubject<string>('')
  private listeningSubject = new BehaviorSubject<boolean>(false)

  transcript$ = this.transcriptSubject.asObservable()
  isListening$ = this.listeningSubject.asObservable()

  constructor(@Inject(VOICE_CONFIG) private config: VoiceConfig) {
    this.pipeline = new VoicePipelineManager(config)
    this.setupEventListeners()
  }

  async startListening(): Promise<void> {
    await this.pipeline.start()
    this.listeningSubject.next(true)
  }

  stopListening(): void {
    this.pipeline.stop()
    this.listeningSubject.next(false)
  }
}
```

**Tasks**:
- [ ] Create Angular package
- [ ] Implement services and injection tokens
- [ ] Create Angular components and directives
- [ ] Add RxJS integration
- [ ] Create demo Angular app
- [ ] Write tests with Karma/Jasmine

### Stage 5: Production Optimization (Week 7)

#### 5.1 Bundle Optimization
**Tasks**:
- [ ] Implement tree-shaking for unused code
- [ ] Create separate bundles for each model size
- [ ] Add dynamic imports for lazy loading
- [ ] Optimize WASM module loading
- [ ] Create CDN distribution

#### 5.2 Performance Optimization
**Tasks**:
- [ ] Implement audio buffering strategies
- [ ] Add request batching for API calls
- [ ] Create connection pooling
- [ ] Optimize memory usage
- [ ] Add performance profiling

#### 5.3 Testing Suite
**Tasks**:
- [ ] Unit tests for all services (>90% coverage)
- [ ] Integration tests with model mocks
- [ ] E2E tests for demo apps
- [ ] Performance benchmarks
- [ ] Browser compatibility tests

### Stage 6: Advanced Features (Week 8)

#### 6.1 Speaker Diarization
**Package**: `@runanywhere/diarization`

**Tasks**:
- [ ] Implement speaker embedding extraction
- [ ] Add voice clustering algorithm
- [ ] Create speaker change detection
- [ ] Add speaker profile management

#### 6.2 Emotion Detection
**Package**: `@runanywhere/emotion`

**Tasks**:
- [ ] Integrate emotion recognition model
- [ ] Add sentiment analysis
- [ ] Create emotion visualization
- [ ] Add emotion history tracking

#### 6.3 Custom Model Support
**Tasks**:
- [ ] Add custom model loading API
- [ ] Create model conversion utilities
- [ ] Add fine-tuning support
- [ ] Create model marketplace integration

## Success Metrics

### Performance Targets
- Model loading: <3s for tiny model
- First transcription: <500ms
- LLM response start: <1s
- TTS synthesis: <200ms
- Bundle size: <5MB core, <20MB with models

### Quality Targets
- Transcription accuracy: >95% for clear speech
- Test coverage: >90%
- Browser support: Chrome 90+, Firefox 88+, Safari 14+, Edge 90+
- Memory usage: <200MB active, <500MB with models

## Dependencies

### External Libraries
- @xenova/transformers: ^2.17.0
- onnxruntime-web: ^1.14.0
- eventsource-parser: ^1.1.2
- idb: ^7.1.1 (IndexedDB wrapper)

### Development Tools
- Vite: ^6.0.3
- TypeScript: ^5.7.2
- Vitest: ^2.1.8
- Playwright: ^1.40.0 (E2E testing)

## Risk Mitigation

### Technical Risks
1. **Model Size**: Provide multiple model sizes and lazy loading
2. **Browser Compatibility**: Use feature detection and polyfills
3. **Performance**: Implement Web Workers and optimize algorithms
4. **API Costs**: Add caching and rate limiting

### Mitigation Strategies
- Progressive enhancement for unsupported browsers
- Fallback to cloud services when local models fail
- Implement circuit breakers for API calls
- Add comprehensive error recovery

## Timeline

### Week 1-2: Model Integration
- Connect Whisper and LLM services
- Implement model caching

### Week 3: TTS Implementation
- Create TTS service
- Integrate with pipeline

### Week 4: Web Workers
- Implement audio processing worker
- Add inference worker

### Week 5-6: Framework Adapters
- Create React, Vue, Angular packages
- Build demo apps

### Week 7: Production Optimization
- Bundle optimization
- Performance tuning
- Testing suite

### Week 8: Advanced Features
- Speaker diarization
- Emotion detection
- Custom model support

## Deliverables

### Core Packages
1. `@runanywhere/transcription` - Enhanced with real model loading
2. `@runanywhere/llm` - Connected to API endpoints
3. `@runanywhere/tts` - New TTS service
4. `@runanywhere/web-audio` - Web Worker audio processing
5. `@runanywhere/models` - Model management system

### Framework Packages
1. `@runanywhere/react` - React hooks and components
2. `@runanywhere/vue` - Vue composables and components
3. `@runanywhere/angular` - Angular services and modules

### Demo Applications
1. Vanilla JS demo with all features
2. React conversational AI demo
3. Vue voice-controlled app
4. Angular enterprise dashboard

### Documentation
1. API reference for all packages
2. Integration guides for each framework
3. Performance optimization guide
4. Model selection guide
5. Deployment best practices

## Success Criteria

✅ Phase 3 is complete when:
1. All models are connected and functional
2. TTS is implemented and integrated
3. Web Workers optimize performance
4. Framework adapters are published
5. Demo apps showcase all features
6. Tests pass with >90% coverage
7. Bundle size meets targets
8. Documentation is complete
