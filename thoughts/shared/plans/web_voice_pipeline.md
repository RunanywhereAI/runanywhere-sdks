# Web Voice Pipeline SDK - Architecture & Future Phases

## Project Overview

**Name**: `@runanywhere/voice-sdk`
**Goal**: Production-ready TypeScript SDK for ultra-low latency voice AI in browsers
**Target Latency**: <500ms end-to-end
**Architecture**: 5-layer architecture adapted from RunAnywhere iOS SDK

## Current Status

### ✅ Phase 1: Foundation (Complete)
- Core infrastructure with DI container, logging, error handling
- Basic voice pipeline with VAD integration
- Demo application
- [Details: web_voice_pipeline_phase1_completed.md]

### ✅ Phase 2: Transcription & LLM (Complete)
- Whisper integration via Transformers.js
- LLM streaming support
- Enhanced pipeline with full voice chain
- [Details: web_voice_pipeline_phase2.md]

### ✅ Phase 3: TTS & Framework Integration (Complete)
- Complete text-to-speech implementation with Web Speech API
- React framework adapter with hooks and components
- Full voice conversation pipeline (VAD → STT → LLM → TTS)
- TypeScript build system fixed and all packages compiled
- [Details: web_voice_pipeline_phase3.md]

### ✅ Phase 4: Production Optimization (Complete)
- Web Workers for performance optimization (VAD, STT, LLM processing)
- Advanced caching system (models, responses) with IndexedDB persistence
- Comprehensive monitoring and error tracking with automatic recovery
- Bundle optimization tools with analysis and recommendations
- Production-ready architecture with 50%+ performance improvements
- [Details: web_voice_pipeline_phase4.md, Progress: web_voice_pipeline_phase4_progress.md]

### 🚧 Phase 5: Framework Completion & Advanced Features (Next)
- Complete Vue and Angular framework adapters
- Advanced offline support with service workers
- Edge optimization and CDN integration
- Comprehensive testing suite and performance benchmarks
- Community adoption and plugin ecosystem

## Architecture Overview - 5-Layer Web Adaptation

Based on the iOS SDK's proven 5-layer architecture, adapted for web:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PUBLIC API LAYER                               │
│    VoiceSDK • Configuration • VoiceOptions • ProcessingResult              │
│    Voice Pipeline Events • Error Types • Framework Availability            │
│    React/Vue/Angular Integration • TypeScript Definitions                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CAPABILITIES LAYER                                │
│  VoiceProcessing • ModelLoading • Routing • Memory • Downloading          │
│  Validation • Storage • Monitoring • Analytics • Configuration            │
│  ErrorRecovery • Progress • Performance • DeviceCapability                │
│  VAD (SileroVAD/EnergyVAD) • STT (Whisper) • TTS (ONNX) • LLM            │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                        ┌───────────────┴───────────────┐
                        ▼                               ▼
┌─────────────────────────────────────┐ ┌─────────────────────────────────┐
│              CORE LAYER             │ │           DATA LAYER            │
│  Domain Models • Service Protocols │ │  IndexedDB • Cache API          │
│  Voice Pipeline • Audio Processing │ │  Model Storage • Config Storage │
│  Configuration Types • Error Types │ │  Analytics Storage • Sync       │
│  Service Interfaces • Adapters     │ │                                │
└─────────────────────────────────────┘ └─────────────────────────────────┘
                        │                               │
                        └───────────────┬───────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────┐
│                          INFRASTRUCTURE LAYER                               │
│  Web Workers • WebGPU • WebAssembly • Audio Context                       │
│  Service Workers • Browser APIs • Platform Adapters                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────┐
│                            FOUNDATION LAYER                                 │
│  DI Container • Logging • Error Handling • Utilities                       │
│  EventEmitter • TypeScript Utils • Browser Detection                       │
│  Memory Management • Performance Monitoring • Constants                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## iOS SDK Architecture Mapping to Web

### Foundation Layer Mapping
| iOS Component | Web Equivalent | Implementation |
|---------------|----------------|----------------|
| ServiceContainer | DIContainer | Service registration & dependency injection |
| SDKConstants | WebSDKConstants | Browser-specific constants & defaults |
| Logging | WebLogger | Console + remote logging with privacy |
| Error Types | WebErrorTypes | Browser-specific error handling |
| Utilities (AsyncQueue) | WebUtilities | Promise queues & async utilities |

### Core Layer Mapping
| iOS Component | Web Equivalent | Implementation |
|---------------|----------------|----------------|
| VoiceService Protocol | VoiceServiceProtocol | Web Audio API integration |
| LLMService Protocol | LLMServiceProtocol | HTTP/WebSocket LLM clients |
| Model Management | WebModelManager | IndexedDB + Cache API |
| Configuration System | WebConfigurationSystem | LocalStorage + session management |

### Capabilities Layer Mapping
| iOS Component | Web Equivalent | Implementation |
|---------------|----------------|----------------|
| VoiceCapabilityService | VoiceCapabilityService | Main voice orchestrator |
| VoicePipelineManager | WebVoicePipelineManager | Pipeline coordination |
| VADHandler | WebVADHandler | @ricky0123/vad-web integration |
| STTHandler | WebSTTHandler | Transformers.js Whisper |
| TTSHandler | WebTTSHandler | ONNX Runtime Web TTS |
| LLMHandler | WebLLMHandler | API client with streaming |
| MemoryService | WebMemoryService | Browser memory management |
| DeviceCapability | WebDeviceCapability | Browser capability detection |

## TypeScript & Web SDK Best Practices

### Code Quality Standards
- **TypeScript 5.3+** with strict mode enabled
- **ESLint + Prettier** with custom rules for SDK development
- **Zero `any` types** - strict typing throughout
- **Branded types** for type safety (e.g., `ModelId`, `SessionId`)
- **Error-first design** - all async operations return Result types
- **Immutable data structures** using readonly types and Record types
- **Tree-shakeable exports** - named exports only, no default exports
- **Bundle size optimization** - dynamic imports for optional features

### Modern TypeScript Patterns
```typescript
// Branded types for type safety
type ModelId = string & { readonly __brand: 'ModelId' }
type SessionId = string & { readonly __brand: 'SessionId' }

// Result types for error handling
type Result<T, E = Error> =
  | { success: true; data: T }
  | { success: false; error: E }

// Strict configuration with readonly types
interface VoiceConfig {
  readonly models: {
    readonly vad: Readonly<VADConfig>
    readonly stt: Readonly<STTConfig>
    readonly tts: Readonly<TTSConfig>
    readonly llm: Readonly<LLMConfig>
  }
  readonly performance: Readonly<PerformanceConfig>
  readonly privacy: Readonly<PrivacyConfig>
}

// Event types with discriminated unions
type VoicePipelineEvent =
  | { type: 'vad.speech_start'; timestamp: number }
  | { type: 'vad.speech_end'; timestamp: number; duration: number }
  | { type: 'stt.partial'; text: string; confidence: number }
  | { type: 'stt.final'; text: string; segments: TranscriptionSegment[] }
  | { type: 'llm.token'; token: string; position: number }
  | { type: 'llm.complete'; text: string; metadata: LLMMetadata }
  | { type: 'tts.audio_chunk'; chunk: Uint8Array; sequence: number }
  | { type: 'pipeline.error'; error: VoiceError; stage: PipelineStage }
```

## Repository Structure

```
@runanywhere/voice-sdk/
├── packages/
│   ├── core/                           # Main SDK package
│   │   ├── src/
│   │   │   ├── foundation/             # Foundation Layer
│   │   │   │   ├── di/                 # Dependency Injection
│   │   │   │   │   ├── container.ts    # DIContainer (like iOS ServiceContainer)
│   │   │   │   │   ├── registry.ts     # Service registry
│   │   │   │   │   └── lifecycle.ts    # Service lifecycle management
│   │   │   │   ├── logging/            # Logging system
│   │   │   │   │   ├── logger.ts       # WebLogger with levels
│   │   │   │   │   ├── remote.ts       # Remote logging (optional)
│   │   │   │   │   └── console.ts      # Console logger
│   │   │   │   ├── errors/             # Error handling
│   │   │   │   │   ├── types.ts        # VoiceError, SDKError types
│   │   │   │   │   ├── recovery.ts     # Error recovery strategies
│   │   │   │   │   └── codes.ts        # Error codes and messages
│   │   │   │   ├── utils/              # Utilities
│   │   │   │   │   ├── async-queue.ts  # Promise-based async queue
│   │   │   │   │   ├── event-emitter.ts # Type-safe event emitter
│   │   │   │   │   ├── memory.ts       # Memory monitoring
│   │   │   │   │   └── browser.ts      # Browser capability detection
│   │   │   │   └── constants/          # SDK constants
│   │   │   │       ├── defaults.ts     # Default configurations
│   │   │   │       ├── limits.ts       # Performance limits
│   │   │   │       └── urls.ts         # Model URLs and endpoints
│   │   │   │
│   │   │   ├── infrastructure/         # Infrastructure Layer
│   │   │   │   ├── workers/            # Web Workers
│   │   │   │   │   ├── vad-worker.ts   # VAD processing worker
│   │   │   │   │   ├── stt-worker.ts   # STT processing worker
│   │   │   │   │   ├── tts-worker.ts   # TTS synthesis worker
│   │   │   │   │   └── model-worker.ts # Model loading worker
│   │   │   │   ├── adapters/           # Platform adapters
│   │   │   │   │   ├── audio-context.ts # Web Audio API adapter
│   │   │   │   │   ├── webgpu.ts       # WebGPU adapter
│   │   │   │   │   ├── wasm.ts         # WebAssembly adapter
│   │   │   │   │   └── storage.ts      # Storage adapter (IndexedDB)
│   │   │   │   └── platform/           # Platform-specific code
│   │   │   │       ├── permissions.ts  # Microphone permissions
│   │   │   │       ├── audio-session.ts # Audio session management
│   │   │   │       └── capabilities.ts # Browser capability detection
│   │   │   │
│   │   │   ├── data/                   # Data Layer
│   │   │   │   ├── repositories/       # Data repositories
│   │   │   │   │   ├── model-repo.ts   # Model metadata storage
│   │   │   │   │   ├── config-repo.ts  # Configuration storage
│   │   │   │   │   ├── analytics-repo.ts # Analytics storage
│   │   │   │   │   └── cache-repo.ts   # Cache management
│   │   │   │   ├── storage/            # Storage implementations
│   │   │   │   │   ├── indexeddb.ts    # IndexedDB implementation
│   │   │   │   │   ├── cache-api.ts    # Cache API implementation
│   │   │   │   │   ├── memory.ts       # In-memory storage
│   │   │   │   │   └── service-worker.ts # Service worker cache
│   │   │   │   ├── models/             # Data models/DTOs
│   │   │   │   │   ├── stored-model.ts # Stored model information
│   │   │   │   │   ├── config-data.ts  # Configuration data
│   │   │   │   │   ├── analytics-data.ts # Analytics data
│   │   │   │   │   └── session-data.ts # Session data
│   │   │   │   └── sync/               # Data synchronization
│   │   │   │       ├── sync-service.ts # Data sync coordination
│   │   │   │       └── conflict-resolver.ts # Conflict resolution
│   │   │   │
│   │   │   ├── core/                   # Core Layer
│   │   │   │   ├── protocols/          # Service protocols/interfaces
│   │   │   │   │   ├── voice-service.ts # VoiceService protocol
│   │   │   │   │   ├── llm-service.ts  # LLMService protocol
│   │   │   │   │   ├── model-manager.ts # ModelManager protocol
│   │   │   │   │   ├── pipeline.ts     # Pipeline protocols
│   │   │   │   │   └── analytics.ts    # Analytics protocols
│   │   │   │   ├── models/             # Domain models
│   │   │   │   │   ├── voice-session.ts # Voice session model
│   │   │   │   │   ├── transcription.ts # Transcription models
│   │   │   │   │   ├── generation.ts   # LLM generation models
│   │   │   │   │   ├── audio.ts        # Audio data models
│   │   │   │   │   └── performance.ts  # Performance metrics
│   │   │   │   ├── services/           # Core services
│   │   │   │   │   ├── pipeline-orchestrator.ts # Main orchestrator
│   │   │   │   │   ├── audio-processor.ts # Audio processing
│   │   │   │   │   ├── event-bus.ts    # Event coordination
│   │   │   │   │   └── context-manager.ts # Context management
│   │   │   │   └── types/              # Core type definitions
│   │   │   │       ├── events.ts       # Event type definitions
│   │   │   │       ├── config.ts       # Configuration types
│   │   │   │       ├── errors.ts       # Error type definitions
│   │   │   │       └── results.ts      # Result type definitions
│   │   │   │
│   │   │   ├── capabilities/           # Capabilities Layer (iOS inspired)
│   │   │   │   ├── voice-processing/   # Voice processing capability
│   │   │   │   │   ├── services/       # Main services
│   │   │   │   │   │   ├── voice-capability.ts # Main orchestrator
│   │   │   │   │   │   ├── pipeline-manager.ts # Pipeline management
│   │   │   │   │   │   ├── session-manager.ts # Session management
│   │   │   │   │   │   └── analytics.ts # Voice analytics
│   │   │   │   │   ├── handlers/       # Processing handlers
│   │   │   │   │   │   ├── vad-handler.ts # VAD processing
│   │   │   │   │   │   ├── stt-handler.ts # STT processing
│   │   │   │   │   │   ├── llm-handler.ts # LLM processing
│   │   │   │   │   │   └── tts-handler.ts # TTS processing
│   │   │   │   │   ├── strategies/     # Processing strategies
│   │   │   │   │   │   ├── vad/        # VAD strategies
│   │   │   │   │   │   │   ├── silero-vad.ts # Silero VAD
│   │   │   │   │   │   │   └── energy-vad.ts # Energy VAD
│   │   │   │   │   │   ├── stt/        # STT strategies
│   │   │   │   │   │   │   ├── whisper-transformers.ts
│   │   │   │   │   │   │   └── whisper-cpp.ts
│   │   │   │   │   │   └── tts/        # TTS strategies
│   │   │   │   │   │       ├── onnx-tts.ts
│   │   │   │   │   │       └── sherpa-onnx.ts
│   │   │   │   │   └── operations/     # Specialized operations
│   │   │   │   │       ├── streaming-tts.ts # Streaming TTS
│   │   │   │   │       └── audio-segmentation.ts
│   │   │   │   │
│   │   │   │   ├── model-management/   # Model management capability
│   │   │   │   │   ├── services/
│   │   │   │   │   │   ├── model-loading.ts # Model loading service
│   │   │   │   │   │   ├── model-validation.ts # Model validation
│   │   │   │   │   │   ├── model-registry.ts # Model registry
│   │   │   │   │   │   └── download.ts  # Download service
│   │   │   │   │   ├── strategies/
│   │   │   │   │   │   ├── validators/  # Format validators
│   │   │   │   │   │   └── loaders/     # Format loaders
│   │   │   │   │   └── models/
│   │   │   │   │       ├── model-info.ts # Model information
│   │   │   │   │       └── validation-result.ts
│   │   │   │   │
│   │   │   │   ├── device-capability/  # Device capability detection
│   │   │   │   │   ├── services/
│   │   │   │   │   │   ├── capability-detector.ts
│   │   │   │   │   │   ├── performance-monitor.ts
│   │   │   │   │   │   └── memory-monitor.ts
│   │   │   │   │   └── models/
│   │   │   │   │       ├── device-info.ts
│   │   │   │   │       └── capabilities.ts
│   │   │   │   │
│   │   │   │   ├── memory/             # Memory management
│   │   │   │   │   ├── services/
│   │   │   │   │   │   ├── memory-service.ts
│   │   │   │   │   │   ├── allocation-manager.ts
│   │   │   │   │   │   └── pressure-handler.ts
│   │   │   │   │   └── strategies/
│   │   │   │   │       └── lru-eviction.ts
│   │   │   │   │
│   │   │   │   ├── analytics/          # Analytics capability
│   │   │   │   │   ├── services/
│   │   │   │   │   │   ├── analytics-service.ts
│   │   │   │   │   │   ├── metrics-collector.ts
│   │   │   │   │   │   └── performance-tracker.ts
│   │   │   │   │   └── models/
│   │   │   │   │       ├── metrics.ts
│   │   │   │   │       └── performance.ts
│   │   │   │   │
│   │   │   │   ├── configuration/      # Configuration management
│   │   │   │   │   ├── services/
│   │   │   │   │   │   ├── config-service.ts
│   │   │   │   │   │   └── config-validator.ts
│   │   │   │   │   └── models/
│   │   │   │   │       └── config-models.ts
│   │   │   │   │
│   │   │   │   └── error-recovery/     # Error recovery capability
│   │   │   │       ├── services/
│   │   │   │       │   ├── recovery-service.ts
│   │   │   │       │   └── strategy-selector.ts
│   │   │   │       └── strategies/
│   │   │   │           ├── retry-strategy.ts
│   │   │   │           └── fallback-strategy.ts
│   │   │   │
│   │   │   ├── public/                 # Public API Layer
│   │   │   │   ├── sdk/                # Main SDK class
│   │   │   │   │   ├── voice-sdk.ts    # Main SDK entry point
│   │   │   │   │   ├── config-builder.ts # Configuration builder
│   │   │   │   │   └── extensions/     # SDK extensions
│   │   │   │   │       ├── react.ts    # React integration
│   │   │   │   │       ├── vue.ts      # Vue integration
│   │   │   │   │       └── angular.ts  # Angular integration
│   │   │   │   ├── types/              # Public type exports
│   │   │   │   │   ├── config.ts       # Configuration types
│   │   │   │   │   ├── events.ts       # Event types
│   │   │   │   │   ├── results.ts      # Result types
│   │   │   │   │   ├── errors.ts       # Error types
│   │   │   │   │   └── models.ts       # Model types
│   │   │   │   └── index.ts            # Main export file
│   │   │   │
│   │   │   └── workers/                # Web Worker implementations
│   │   │       ├── vad.worker.ts       # VAD worker
│   │   │       ├── stt.worker.ts       # STT worker
│   │   │       ├── tts.worker.ts       # TTS worker
│   │   │       └── model.worker.ts     # Model worker
│   │   │
│   │   ├── tests/                      # Comprehensive test suite
│   │   │   ├── unit/                   # Unit tests
│   │   │   │   ├── foundation/         # Foundation layer tests
│   │   │   │   ├── core/               # Core layer tests
│   │   │   │   ├── capabilities/       # Capabilities layer tests
│   │   │   │   └── public/             # Public API tests
│   │   │   ├── integration/            # Integration tests
│   │   │   │   ├── pipeline/           # Pipeline integration tests
│   │   │   │   ├── workers/            # Worker integration tests
│   │   │   │   └── end-to-end/         # E2E tests
│   │   │   ├── performance/            # Performance tests
│   │   │   │   ├── latency.test.ts     # Latency benchmarks
│   │   │   │   ├── memory.test.ts      # Memory usage tests
│   │   │   │   └── throughput.test.ts  # Throughput tests
│   │   │   ├── fixtures/               # Test fixtures
│   │   │   │   ├── audio/              # Audio test files
│   │   │   │   ├── models/             # Mock models
│   │   │   │   └── configs/            # Test configurations
│   │   │   ├── mocks/                  # Mock implementations
│   │   │   │   ├── services/           # Mock services
│   │   │   │   ├── workers/            # Mock workers
│   │   │   │   └── apis/               # Mock APIs
│   │   │   └── utils/                  # Test utilities
│   │   │       ├── test-helpers.ts     # Common test helpers
│   │   │       ├── mock-factory.ts     # Mock factory
│   │   │       └── assertion-utils.ts  # Custom assertions
│   │   │
│   │   ├── docs/                       # Package documentation
│   │   │   ├── api/                    # API documentation
│   │   │   ├── guides/                 # Usage guides
│   │   │   ├── examples/               # Code examples
│   │   │   └── architecture/           # Architecture docs
│   │   │
│   │   ├── package.json                # Package configuration
│   │   ├── tsconfig.json               # TypeScript config
│   │   ├── vite.config.ts              # Vite build config
│   │   ├── vitest.config.ts            # Vitest test config
│   │   └── README.md                   # Package README
│   │
│   ├── integrations/                   # Framework integrations
│   │   ├── react/                      # React integration package
│   │   │   ├── src/
│   │   │   │   ├── hooks/              # React hooks
│   │   │   │   │   ├── useVoiceSDK.ts  # Main voice SDK hook
│   │   │   │   │   ├── useVoicePipeline.ts # Pipeline hook
│   │   │   │   │   ├── useTranscription.ts # Transcription hook
│   │   │   │   │   └── useVoiceRecording.ts # Recording hook
│   │   │   │   ├── components/         # React components
│   │   │   │   │   ├── VoiceRecorder.tsx # Voice recorder component
│   │   │   │   │   ├── TranscriptDisplay.tsx # Transcript display
│   │   │   │   │   └── VoiceVisualizer.tsx # Audio visualizer
│   │   │   │   ├── providers/          # Context providers
│   │   │   │   │   └── VoiceProvider.tsx # Voice context provider
│   │   │   │   └── index.ts            # React exports
│   │   │   ├── tests/                  # React-specific tests
│   │   │   └── package.json
│   │   │
│   │   ├── vue/                        # Vue integration package
│   │   │   ├── src/
│   │   │   │   ├── composables/        # Vue composables
│   │   │   │   │   ├── useVoiceSDK.ts  # Main SDK composable
│   │   │   │   │   └── useVoicePipeline.ts
│   │   │   │   ├── components/         # Vue components
│   │   │   │   └── index.ts
│   │   │   └── package.json
│   │   │
│   │   └── angular/                    # Angular integration package
│   │       ├── src/
│   │       │   ├── services/           # Angular services
│   │       │   ├── components/         # Angular components
│   │       │   └── index.ts
│   │       └── package.json
│   │
│   ├── demo-apps/                      # Demo applications
│   │   ├── vanilla/                    # Vanilla JavaScript demo
│   │   │   ├── src/
│   │   │   │   ├── index.html
│   │   │   │   ├── main.ts
│   │   │   │   ├── components/
│   │   │   │   └── styles/
│   │   │   ├── public/
│   │   │   ├── vite.config.ts
│   │   │   └── package.json
│   │   │
│   │   ├── react-demo/                 # React demo app
│   │   │   ├── src/
│   │   │   │   ├── App.tsx
│   │   │   │   ├── components/
│   │   │   │   │   ├── VoiceChat.tsx
│   │   │   │   │   ├── SettingsPanel.tsx
│   │   │   │   │   └── MetricsDashboard.tsx
│   │   │   │   └── hooks/
│   │   │   ├── public/
│   │   │   └── package.json
│   │   │
│   │   └── vue-demo/                   # Vue demo app
│   │       └── [similar structure]
│   │
│   └── tools/                          # Development tools
│       ├── build-scripts/              # Build scripts
│       │   ├── build-workers.ts        # Worker build script
│       │   ├── copy-wasm.ts            # WASM file copying
│       │   └── generate-types.ts       # Type generation
│       ├── dev-server/                 # Development server
│       │   ├── server.ts               # Dev server with HTTPS
│       │   └── middleware.ts           # Custom middleware
│       └── testing/                    # Testing utilities
│           ├── setup.ts                # Test setup
│           └── browser-env.ts          # Browser environment setup
│
├── scripts/                            # Root-level scripts
│   ├── build.sh                        # Build all packages
│   ├── test.sh                         # Run all tests
│   ├── lint.sh                         # Lint all packages
│   ├── setup-dev.sh                    # Development setup
│   └── release.sh                      # Release preparation
│
├── docs/                               # Root documentation
│   ├── architecture/                   # Architecture documentation
│   │   ├── overview.md                 # Overall architecture
│   │   ├── layer-details.md            # Layer-by-layer details
│   │   ├── data-flow.md                # Data flow diagrams
│   │   └── design-decisions.md         # Design decision records
│   ├── api/                            # API documentation
│   ├── guides/                         # User guides
│   │   ├── getting-started.md          # Getting started guide
│   │   ├── configuration.md            # Configuration guide
│   │   ├── customization.md            # Customization guide
│   │   └── troubleshooting.md          # Troubleshooting guide
│   └── examples/                       # Example code
│
├── .github/                            # GitHub workflows
│   ├── workflows/
│   │   ├── ci.yml                      # Continuous integration
│   │   ├── release.yml                 # Release workflow
│   │   ├── docs.yml                    # Documentation deployment
│   │   └── security.yml                # Security scanning
│   └── ISSUE_TEMPLATE/                 # Issue templates
│
├── .vscode/                            # VS Code configuration
│   ├── settings.json                   # Workspace settings
│   ├── extensions.json                 # Recommended extensions
│   └── launch.json                     # Debug configuration
│
├── config/                             # Configuration files
│   ├── eslint.config.js                # ESLint configuration
│   ├── prettier.config.js              # Prettier configuration
│   ├── tsconfig.base.json              # Base TypeScript config
│   ├── vitest.config.ts                # Vitest base config
│   └── vite.config.base.ts             # Vite base config
│
├── pnpm-workspace.yaml                 # PNPM workspace config
├── package.json                        # Root package.json
├── tsconfig.json                       # Root TypeScript config
├── .gitignore                          # Git ignore rules
├── .npmignore                          # NPM ignore rules
├── LICENSE                             # License file
└── README.md                           # Root README
```


## Phase 1 & 2 Completion Summary

### ✅ Phase 1: Foundation (Completed)
**Timeline**: Weeks 1-3
**Status**: Successfully completed with all deliverables met

#### Achievements:
1. **Project Infrastructure**
   - Established PNPM monorepo structure with TypeScript 5.7.2
   - Configured Vite build system with watch mode and HMR
   - Set up Vitest for testing with 80%+ coverage
   - Implemented ESLint + Prettier with strict TypeScript rules

2. **Core Package (`@runanywhere/core`)**
   - Result<T,E> type for functional error handling
   - Branded types (SessionId, ModelId, etc.) for type safety
   - Comprehensive error system with custom error classes
   - Logger with configurable levels and multiple handlers
   - DIContainer with dependency injection and circular dependency detection

3. **Voice Package (`@runanywhere/voice`)**
   - VAD service using @ricky0123/vad-web v0.0.24
   - Basic VoicePipelineManager with event system
   - Real-time speech detection with configurable thresholds
   - Audio buffer management and processing

4. **Demo Application**
   - Fully functional vanilla JavaScript demo
   - Real-time VAD visualization with metrics
   - Event logging and speech segment tracking
   - Professional UI with status indicators

### ✅ Phase 2: Transcription & LLM (Completed)
**Timeline**: Weeks 4-6
**Status**: Successfully integrated STT and LLM capabilities

#### Achievements:
1. **Transcription Package (`@runanywhere/transcription`)**
   - Whisper integration via Transformers.js
   - Support for tiny/base/small models
   - Real-time transcription with partial results
   - Web Worker for non-blocking audio processing
   - Model download progress tracking

2. **LLM Package (`@runanywhere/llm`)**
   - Streaming LLM responses with SSE parsing
   - OpenAI/Anthropic API compatibility
   - Conversation history management
   - Token-by-token streaming with latency tracking
   - Configurable generation parameters

3. **Enhanced Pipeline Manager**
   - Full VAD → STT → LLM → Response pipeline
   - Audio buffering during processing
   - Event-driven architecture with comprehensive events
   - Performance monitoring with detailed metrics

4. **Performance Optimizations**
   - PerformanceMonitor utility for metrics collection
   - P95/P99 latency tracking
   - Memory pressure handling
   - Worker-based processing for UI responsiveness

#### Performance Metrics Achieved:
| Metric | Target | Achieved |
|--------|--------|----------|
| VAD Latency | <50ms | ✅ 30ms |
| STT First Token | <200ms | ✅ 150ms |
| LLM First Token | <300ms | ✅ 250ms |
| End-to-End | <500ms | ✅ 430ms |

## Phase 3: Voice Pipeline Implementation (Complete End-to-End)

### 3.1 Voice Pipeline Manager (iOS SDK Inspired)

**File**: `src/capabilities/voice-processing/services/pipeline-manager.ts`
```typescript
import { EventEmitter } from 'eventemitter3'
import type { VoicePipelineEvent, VoicePipelineConfig, VoicePipelineResult } from '../../../public/types/events'
import type { VADService } from '../../../core/protocols/voice-service'
import type { STTService } from '../../../core/protocols/voice-service'
import type { TTSService } from '../../../core/protocols/voice-service'
import type { LLMService } from '../../../core/protocols/llm-service'

export class WebVoicePipelineManager extends EventEmitter {
  private vadService?: VADService
  private sttService?: STTService
  private ttsService?: TTSService
  private llmService?: LLMService

  private isActive = false
  private currentSession?: VoiceSession
  private audioContext?: AudioContext
  private mediaStream?: MediaStream

  constructor(
    private config: VoicePipelineConfig,
    private serviceContainer: DIContainer
  ) {
    super()
  }

  async initialize(): Promise<void> {
    // Initialize services based on configuration
    if (this.config.enableVAD) {
      this.vadService = await this.serviceContainer.get<VADService>('vadService')
      await this.vadService.initialize(this.config.vad)
    }

    if (this.config.enableSTT) {
      this.sttService = await this.serviceContainer.get<STTService>('sttService')
      await this.sttService.initialize(this.config.stt)
    }

    if (this.config.enableTTS) {
      this.ttsService = await this.serviceContainer.get<TTSService>('ttsService')
      await this.ttsService.initialize(this.config.tts)
    }

    if (this.config.enableLLM) {
      this.llmService = await this.serviceContainer.get<LLMService>('llmService')
    }

    // Setup audio context
    this.audioContext = new AudioContext({
      sampleRate: 16000,
      latencyHint: 'interactive'
    })
  }

  async startPipeline(): Promise<VoiceSession> {
    if (this.isActive) {
      throw new Error('Pipeline already active')
    }

    // Request microphone permission
    this.mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: 16000,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true
      }
    })

    const sessionId = crypto.randomUUID()
    this.currentSession = new VoiceSession(sessionId, this.config)

    this.isActive = true

    // Setup audio processing chain
    await this.setupAudioProcessing()

    this.emit('started', { sessionId })

    return this.currentSession
  }

  async stopPipeline(): Promise<VoicePipelineResult> {
    if (!this.isActive || !this.currentSession) {
      throw new Error('Pipeline not active')
    }

    this.isActive = false

    // Stop all services
    this.vadService?.stop()
    this.sttService?.stop?.()

    // Close media stream
    this.mediaStream?.getTracks().forEach(track => track.stop())

    const result: VoicePipelineResult = {
      sessionId: this.currentSession.id,
      transcript: this.currentSession.transcript,
      response: this.currentSession.response,
      duration: Date.now() - this.currentSession.startTime,
      performance: this.currentSession.getPerformanceMetrics()
    }

    this.emit('completed', result)

    return result
  }

  async processAudioChunk(audioData: Float32Array): Promise<void> {
    if (!this.isActive) return

    // VAD Processing
    if (this.vadService) {
      const vadResult = await this.vadService.processAudio(audioData)

      if (vadResult.speechDetected && !this.currentSession?.isSpeaking) {
        this.currentSession?.setSpeaking(true)
        this.emit('speechStart', { timestamp: Date.now() })
      } else if (!vadResult.speechDetected && this.currentSession?.isSpeaking) {
        this.currentSession?.setSpeaking(false)
        this.emit('speechEnd', {
          timestamp: Date.now(),
          duration: this.currentSession.getSpeechDuration()
        })

        // Process accumulated audio
        await this.processAccumulatedAudio()
      }
    }

    // Accumulate audio while speaking
    if (this.currentSession?.isSpeaking) {
      this.currentSession.addAudioChunk(audioData)
    }
  }

  private async setupAudioProcessing(): Promise<void> {
    if (!this.mediaStream || !this.audioContext) return

    const source = this.audioContext.createMediaStreamSource(this.mediaStream)

    // Create processor for real-time audio chunks
    await this.audioContext.audioWorklet.addModule('/workers/audio-processor.js')
    const processor = new AudioWorkletNode(this.audioContext, 'audio-processor', {
      processorOptions: {
        frameSize: 1024,
        sampleRate: 16000
      }
    })

    processor.port.onmessage = (event) => {
      const { audioData } = event.data
      this.processAudioChunk(new Float32Array(audioData))
    }

    source.connect(processor)
    processor.connect(this.audioContext.destination)
  }

  private async processAccumulatedAudio(): Promise<void> {
    if (!this.currentSession) return

    const audioBuffer = this.currentSession.getAccumulatedAudio()
    if (audioBuffer.length === 0) return

    try {
      // STT Processing
      if (this.sttService) {
        const transcription = await this.sttService.transcribe(audioBuffer, {
          language: this.config.stt.language
        })

        this.currentSession.addTranscript(transcription.text)
        this.emit('transcriptionComplete', {
          text: transcription.text,
          confidence: transcription.confidence,
          segments: transcription.segments
        })

        // LLM Processing
        if (this.llmService && transcription.text.trim()) {
          await this.processWithLLM(transcription.text)
        }
      }
    } catch (error) {
      this.emit('error', {
        stage: 'stt',
        error: error as Error,
        sessionId: this.currentSession.id
      })
    }

    // Clear accumulated audio
    this.currentSession.clearAudio()
  }

  private async processWithLLM(text: string): Promise<void> {
    if (!this.llmService || !this.currentSession) return

    try {
      const response = await this.llmService.generateStream(text, {
        maxTokens: this.config.llm.maxTokens,
        temperature: this.config.llm.temperature
      })

      let fullResponse = ''

      for await (const token of response) {
        fullResponse += token

        this.emit('llmToken', {
          token,
          position: fullResponse.length - token.length
        })

        // Start TTS as soon as we have enough text
        if (this.ttsService && fullResponse.length > 50 && !this.currentSession.isTTSActive) {
          this.startTTS(fullResponse)
        }
      }

      this.currentSession.setResponse(fullResponse)

      this.emit('llmComplete', {
        text: fullResponse,
        sessionId: this.currentSession.id
      })

      // Final TTS if not started
      if (this.ttsService && !this.currentSession.isTTSActive) {
        await this.synthesizeAndPlay(fullResponse)
      }

    } catch (error) {
      this.emit('error', {
        stage: 'llm',
        error: error as Error,
        sessionId: this.currentSession.id
      })
    }
  }

  private async startTTS(text: string): Promise<void> {
    if (!this.ttsService || !this.currentSession) return

    this.currentSession.setTTSActive(true)

    try {
      await this.synthesizeAndPlay(text)
    } catch (error) {
      this.emit('error', {
        stage: 'tts',
        error: error as Error,
        sessionId: this.currentSession.id
      })
    } finally {
      this.currentSession.setTTSActive(false)
    }
  }

  private async synthesizeAndPlay(text: string): Promise<void> {
    if (!this.ttsService || !this.audioContext) return

    const audioBuffer = await this.ttsService.synthesize(text, {
      voice: this.config.tts.voice,
      rate: this.config.tts.rate,
      pitch: this.config.tts.pitch
    })

    // Play audio
    const source = this.audioContext.createBufferSource()
    source.buffer = audioBuffer
    source.connect(this.audioContext.destination)

    this.emit('ttsStart', { text })

    source.onended = () => {
      this.emit('ttsComplete', { text })
    }

    source.start()
  }

  isHealthy(): boolean {
    return this.audioContext?.state === 'running'
  }

  destroy(): void {
    this.stopPipeline()
    this.audioContext?.close()
    this.removeAllListeners()
  }
}

// Voice session management
class VoiceSession {
  public readonly startTime = Date.now()
  public transcript = ''
  public response = ''
  public isSpeaking = false
  public isTTSActive = false

  private audioChunks: Float32Array[] = []
  private speechStartTime?: number
  private sttStartTime?: number
  private llmStartTime?: number
  private ttsStartTime?: number

  constructor(
    public readonly id: string,
    private config: VoicePipelineConfig
  ) {}

  setSpeaking(speaking: boolean): void {
    this.isSpeaking = speaking

    if (speaking) {
      this.speechStartTime = Date.now()
    }
  }

  setTTSActive(active: boolean): void {
    this.isTTSActive = active

    if (active) {
      this.ttsStartTime = Date.now()
    }
  }

  addAudioChunk(chunk: Float32Array): void {
    this.audioChunks.push(chunk)
  }

  addTranscript(text: string): void {
    this.transcript += (this.transcript ? ' ' : '') + text
    this.sttStartTime = this.sttStartTime ?? Date.now()
  }

  setResponse(text: string): void {
    this.response = text
    this.llmStartTime = this.llmStartTime ?? Date.now()
  }

  getAccumulatedAudio(): Float32Array {
    if (this.audioChunks.length === 0) return new Float32Array(0)

    const totalLength = this.audioChunks.reduce((sum, chunk) => sum + chunk.length, 0)
    const combined = new Float32Array(totalLength)

    let offset = 0
    for (const chunk of this.audioChunks) {
      combined.set(chunk, offset)
      offset += chunk.length
    }

    return combined
  }

  clearAudio(): void {
    this.audioChunks = []
  }

  getSpeechDuration(): number {
    return this.speechStartTime ? Date.now() - this.speechStartTime : 0
  }

  getPerformanceMetrics(): VoicePerformanceMetrics {
    const now = Date.now()

    return {
      totalDuration: now - this.startTime,
      sttLatency: this.sttStartTime ? this.sttStartTime - this.startTime : 0,
      llmLatency: this.llmStartTime ? this.llmStartTime - (this.sttStartTime ?? this.startTime) : 0,
      ttsLatency: this.ttsStartTime ? this.ttsStartTime - (this.llmStartTime ?? this.startTime) : 0,
      speechDuration: this.getSpeechDuration()
    }
  }
}

export interface VoicePerformanceMetrics {
  totalDuration: number
  sttLatency: number
  llmLatency: number
  ttsLatency: number
  speechDuration: number
}
```

## Phase 4: Main SDK Class (iOS SDK Inspired)

### 4.1 Main VoiceSDK Class

**File**: `src/public/sdk/voice-sdk.ts`
```typescript
import { EventEmitter } from 'eventemitter3'
import { DIContainer } from '../../foundation/di/container'
import { logger } from '../../foundation/logging/logger'
import type { VoiceConfig, VoicePipelineConfig, VoicePipelineEvent, VoicePipelineResult } from '../types/config'

export interface VoiceSDKEvents {
  initialized: void
  pipelineEvent: VoicePipelineEvent
  pipelineComplete: VoicePipelineResult
  error: { error: Error; context?: string }
}

export class VoiceSDK extends EventEmitter<VoiceSDKEvents> {
  private static instance?: VoiceSDK
  private container?: DIContainer
  private pipelineManager?: WebVoicePipelineManager
  private isInitialized = false

  private constructor() {
    super()
  }

  static getInstance(): VoiceSDK {
    if (!VoiceSDK.instance) {
      VoiceSDK.instance = new VoiceSDK()
    }
    return VoiceSDK.instance
  }

  async initialize(config: VoiceConfig): Promise<void> {
    if (this.isInitialized) {
      logger.warn('SDK already initialized')
      return
    }

    try {
      // Validate configuration
      this.validateConfig(config)

      // Initialize dependency injection container
      this.container = new DIContainer()

      // Register all services (similar to iOS ServiceContainer)
      await this.registerServices(config)

      // Bootstrap core services
      await this.container.bootstrap()

      this.isInitialized = true

      logger.info('VoiceSDK initialized successfully', {
        category: 'VoiceSDK',
        metadata: { version: '1.0.0' }
      })

      this.emit('initialized')

    } catch (error) {
      logger.error('Failed to initialize SDK', error as Error, {
        category: 'VoiceSDK'
      })
      throw error
    }
  }

  async createPipeline(config: VoicePipelineConfig): Promise<VoiceSession> {
    this.ensureInitialized()

    if (this.pipelineManager) {
      throw new Error('Pipeline already active')
    }

    this.pipelineManager = new WebVoicePipelineManager(config, this.container!)

    // Forward pipeline events
    this.pipelineManager.on('*', (eventName: string, ...args: any[]) => {
      this.emit('pipelineEvent', {
        type: eventName,
        data: args[0],
        timestamp: Date.now()
      } as VoicePipelineEvent)
    })

    await this.pipelineManager.initialize()
    return this.pipelineManager.startPipeline()
  }

  async stopPipeline(): Promise<VoicePipelineResult> {
    if (!this.pipelineManager) {
      throw new Error('No active pipeline')
    }

    const result = await this.pipelineManager.stopPipeline()
    this.pipelineManager.destroy()
    this.pipelineManager = undefined

    this.emit('pipelineComplete', result)

    return result
  }

  // Convenience methods for common use cases
  async quickTranscribe(audioData: Float32Array, options?: {
    language?: string
    modelSize?: 'tiny' | 'base' | 'small'
  }): Promise<TranscriptionResult> {
    const config = VoicePipelineConfig.transcriptionOnly({
      language: options?.language ?? 'en',
      modelSize: options?.modelSize ?? 'base'
    })

    const session = await this.createPipeline(config)

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Transcription timeout'))
      }, 30000)

      this.once('pipelineEvent', (event) => {
        if (event.type === 'transcriptionComplete') {
          clearTimeout(timeout)
          this.stopPipeline()
          resolve(event.data)
        } else if (event.type === 'error') {
          clearTimeout(timeout)
          this.stopPipeline()
          reject(event.data.error)
        }
      })

      // Process the audio
      this.pipelineManager?.processAudioChunk(audioData)
    })
  }

  async startConversation(config?: Partial<VoicePipelineConfig>): Promise<VoiceSession> {
    const fullConfig = VoicePipelineConfig.conversational(config)
    return this.createPipeline(fullConfig)
  }

  // Configuration management
  async updateConfig(updates: Partial<VoiceConfig>): Promise<void> {
    this.ensureInitialized()

    // Update services with new configuration
    if (updates.performance) {
      const memoryService = await this.container!.get('memoryService')
      await memoryService.updateConfig(updates.performance)
    }

    if (updates.models) {
      const modelRegistry = await this.container!.get('modelRegistry')
      await modelRegistry.updateConfig(updates.models)
    }
  }

  // Analytics and monitoring
  async getAnalytics(): Promise<VoiceAnalytics> {
    this.ensureInitialized()

    const analyticsService = await this.container!.get('analyticsService')
    return analyticsService.getAnalytics()
  }

  async getPerformanceMetrics(): Promise<PerformanceMetrics> {
    this.ensureInitialized()

    const performanceService = await this.container!.get('performanceService')
    return performanceService.getMetrics()
  }

  // Model management
  async downloadModel(modelId: string): Promise<void> {
    this.ensureInitialized()

    const downloadService = await this.container!.get('downloadService')
    await downloadService.downloadModel(modelId)
  }

  async getAvailableModels(): Promise<ModelInfo[]> {
    this.ensureInitialized()

    const modelRegistry = await this.container!.get('modelRegistry')
    return modelRegistry.getAvailableModels()
  }

  // Health and diagnostics
  isHealthy(): boolean {
    if (!this.isInitialized || !this.container) return false

    // Check if all core services are healthy
    return this.container.isHealthy()
  }

  async runDiagnostics(): Promise<DiagnosticsReport> {
    this.ensureInitialized()

    const diagnostics = await this.container!.get('diagnosticsService')
    return diagnostics.runDiagnostics()
  }

  // Cleanup
  destroy(): void {
    if (this.pipelineManager) {
      this.pipelineManager.destroy()
      this.pipelineManager = undefined
    }

    if (this.container) {
      this.container.destroy()
      this.container = undefined
    }

    this.isInitialized = false
    this.removeAllListeners()

    logger.info('VoiceSDK destroyed', { category: 'VoiceSDK' })
  }

  private ensureInitialized(): void {
    if (!this.isInitialized) {
      throw new Error('SDK not initialized. Call initialize() first.')
    }
  }

  private validateConfig(config: VoiceConfig): void {
    if (!config.models?.stt?.modelId && config.features?.transcription) {
      throw new Error('STT model required when transcription is enabled')
    }

    if (!config.models?.llm?.apiKey && config.features?.llm) {
      throw new Error('LLM API key required when LLM is enabled')
    }

    if (config.performance?.maxMemoryMB && config.performance.maxMemoryMB < 100) {
      throw new Error('Minimum memory requirement is 100MB')
    }
  }

  private async registerServices(config: VoiceConfig): Promise<void> {
    // Register all services similar to iOS ServiceContainer
    const services = [
      // Foundation services
      { name: 'logger', factory: () => logger },
      { name: 'configService', factory: () => new WebConfigurationService(config) },

      // Core services
      { name: 'deviceCapability', factory: () => new WebDeviceCapability() },
      { name: 'memoryService', factory: () => new WebMemoryService(config.performance) },
      { name: 'modelRegistry', factory: () => new WebModelRegistry(config.models) },
      { name: 'downloadService', factory: () => new WebDownloadService() },

      // Voice services
      { name: 'vadService', factory: () => new SileroVADService() },
      { name: 'sttService', factory: () => new WhisperSTTService() },
      { name: 'ttsService', factory: () => new ONNXTTSService() },
      { name: 'llmService', factory: () => new OpenAILLMService(config.models.llm) },

      // Analytics services
      { name: 'analyticsService', factory: () => new WebAnalyticsService() },
      { name: 'performanceService', factory: () => new WebPerformanceService() },
      { name: 'diagnosticsService', factory: () => new WebDiagnosticsService() }
    ]

    for (const service of services) {
      this.container!.register(service.name, service.factory)
    }
  }
}

// Export singleton instance
export const voiceSDK = VoiceSDK.getInstance()
```

### 4.2 Configuration Builder Pattern

**File**: `src/public/sdk/config-builder.ts`
```typescript
import type { VoiceConfig, VoicePipelineConfig } from '../types/config'

export class VoiceConfigBuilder {
  private config: Partial<VoiceConfig> = {}

  static create(): VoiceConfigBuilder {
    return new VoiceConfigBuilder()
  }

  // Model configuration
  withSTTModel(modelId: string, options?: {
    language?: string
    modelSize?: 'tiny' | 'base' | 'small'
  }): this {
    this.config.models = {
      ...this.config.models,
      stt: {
        modelId,
        language: options?.language ?? 'en',
        modelSize: options?.modelSize ?? 'base'
      }
    }
    return this
  }

  withLLMProvider(provider: 'openai' | 'anthropic' | 'custom', options: {
    apiKey: string
    model?: string
    baseUrl?: string
  }): this {
    this.config.models = {
      ...this.config.models,
      llm: {
        provider,
        apiKey: options.apiKey,
        model: options.model,
        baseUrl: options.baseUrl
      }
    }
    return this
  }

  withTTSVoice(voice: string, options?: {
    rate?: number
    pitch?: number
  }): this {
    this.config.models = {
      ...this.config.models,
      tts: {
        voice,
        rate: options?.rate ?? 1.0,
        pitch: options?.pitch ?? 1.0
      }
    }
    return this
  }

  // Performance configuration
  withPerformance(options: {
    targetLatency?: number
    maxMemoryMB?: number
    enableGPU?: boolean
  }): this {
    this.config.performance = {
      ...this.config.performance,
      ...options
    }
    return this
  }

  // Feature toggles
  withFeatures(features: {
    transcription?: boolean
    llm?: boolean
    tts?: boolean
    analytics?: boolean
    caching?: boolean
  }): this {
    this.config.features = {
      ...this.config.features,
      ...features
    }
    return this
  }

  // Privacy configuration
  withPrivacy(options: {
    enableAnalytics?: boolean
    enableRemoteLogging?: boolean
    dataPersistence?: 'memory' | 'local' | 'none'
  }): this {
    this.config.privacy = {
      ...this.config.privacy,
      ...options
    }
    return this
  }

  build(): VoiceConfig {
    // Apply defaults
    const defaultConfig: VoiceConfig = {
      models: {
        stt: { modelId: 'whisper-base', language: 'en', modelSize: 'base' },
        llm: { provider: 'openai', apiKey: '', model: 'gpt-3.5-turbo' },
        tts: { voice: 'default', rate: 1.0, pitch: 1.0 }
      },
      performance: {
        targetLatency: 500,
        maxMemoryMB: 1024,
        enableGPU: true
      },
      features: {
        transcription: true,
        llm: true,
        tts: false,
        analytics: true,
        caching: true
      },
      privacy: {
        enableAnalytics: true,
        enableRemoteLogging: false,
        dataPersistence: 'local'
      }
    }

    return { ...defaultConfig, ...this.config } as VoiceConfig
  }
}

export class VoicePipelineConfigBuilder {
  private config: Partial<VoicePipelineConfig> = {}

  static create(): VoicePipelineConfigBuilder {
    return new VoicePipelineConfigBuilder()
  }

  static transcriptionOnly(options?: {
    language?: string
    modelSize?: 'tiny' | 'base' | 'small'
  }): VoicePipelineConfig {
    return new VoicePipelineConfigBuilder()
      .enableVAD()
      .enableSTT(options?.language, options?.modelSize)
      .build()
  }

  static conversational(options?: Partial<VoicePipelineConfig>): VoicePipelineConfig {
    return new VoicePipelineConfigBuilder()
      .enableVAD()
      .enableSTT()
      .enableLLM()
      .enableTTS()
      .withStreaming(true)
      .withInterruption(true)
      .merge(options)
      .build()
  }

  enableVAD(sensitivity?: number): this {
    this.config.enableVAD = true
    this.config.vad = {
      ...this.config.vad,
      sensitivity: sensitivity ?? 0.5
    }
    return this
  }

  enableSTT(language?: string, modelSize?: 'tiny' | 'base' | 'small'): this {
    this.config.enableSTT = true
    this.config.stt = {
      ...this.config.stt,
      language: language ?? 'en',
      modelSize: modelSize ?? 'base'
    }
    return this
  }

  enableLLM(model?: string): this {
    this.config.enableLLM = true
    this.config.llm = {
      ...this.config.llm,
      model: model ?? 'gpt-3.5-turbo',
      maxTokens: 150,
      temperature: 0.7
    }
    return this
  }

  enableTTS(voice?: string): this {
    this.config.enableTTS = true
    this.config.tts = {
      ...this.config.tts,
      voice: voice ?? 'default',
      rate: 1.0,
      pitch: 1.0
    }
    return this
  }

  withStreaming(enabled: boolean): this {
    this.config.streaming = enabled
    return this
  }

  withInterruption(enabled: boolean): this {
    this.config.interruption = enabled
    return this
  }

  withTimeouts(timeouts: {
    stt?: number
    llm?: number
    tts?: number
  }): this {
    this.config.timeouts = {
      ...this.config.timeouts,
      ...timeouts
    }
    return this
  }

  merge(options?: Partial<VoicePipelineConfig>): this {
    if (options) {
      this.config = { ...this.config, ...options }
    }
    return this
  }

  build(): VoicePipelineConfig {
    const defaults: VoicePipelineConfig = {
      enableVAD: false,
      enableSTT: false,
      enableLLM: false,
      enableTTS: false,
      streaming: false,
      interruption: false,
      vad: { sensitivity: 0.5 },
      stt: { language: 'en', modelSize: 'base' },
      llm: { model: 'gpt-3.5-turbo', maxTokens: 150, temperature: 0.7 },
      tts: { voice: 'default', rate: 1.0, pitch: 1.0 },
      timeouts: { stt: 30000, llm: 60000, tts: 30000 }
    }

    return { ...defaults, ...this.config } as VoicePipelineConfig
  }
}
```

## Phase 5: Framework Integrations

### 5.1 React Integration

**File**: `packages/integrations/react/src/hooks/useVoiceSDK.ts`
```typescript
import { useEffect, useRef, useState, useCallback } from 'react'
import { voiceSDK, VoiceSDK } from '@runanywhere/voice-sdk'
import type { VoiceConfig, VoicePipelineConfig, VoicePipelineEvent, VoicePipelineResult } from '@runanywhere/voice-sdk'

export interface UseVoiceSDKOptions {
  config: VoiceConfig
  autoInitialize?: boolean
}

export interface UseVoiceSDKReturn {
  // State
  isInitialized: boolean
  isActive: boolean
  isListening: boolean
  isProcessing: boolean
  transcript: string
  response: string
  error: Error | null

  // Actions
  initialize: () => Promise<void>
  startConversation: (config?: Partial<VoicePipelineConfig>) => Promise<void>
  stopConversation: () => Promise<void>
  transcribe: (audio: Float32Array) => Promise<string>

  // Metrics
  latency: number | null
  performance: VoicePerformanceMetrics | null
}

export function useVoiceSDK(options: UseVoiceSDKOptions): UseVoiceSDKReturn {
  const [isInitialized, setIsInitialized] = useState(false)
  const [isActive, setIsActive] = useState(false)
  const [isListening, setIsListening] = useState(false)
  const [isProcessing, setIsProcessing] = useState(false)
  const [transcript, setTranscript] = useState('')
  const [response, setResponse] = useState('')
  const [error, setError] = useState<Error | null>(null)
  const [latency, setLatency] = useState<number | null>(null)
  const [performance, setPerformance] = useState<VoicePerformanceMetrics | null>(null)

  const sdkRef = useRef<VoiceSDK>(voiceSDK)
  const sessionRef = useRef<VoiceSession | null>(null)

  const initialize = useCallback(async () => {
    try {
      setError(null)
      await sdkRef.current.initialize(options.config)
      setIsInitialized(true)
    } catch (err) {
      setError(err as Error)
    }
  }, [options.config])

  const startConversation = useCallback(async (config?: Partial<VoicePipelineConfig>) => {
    if (!isInitialized) {
      throw new Error('SDK not initialized')
    }

    try {
      setError(null)
      setIsActive(true)
      setTranscript('')
      setResponse('')

      sessionRef.current = await sdkRef.current.startConversation(config)

    } catch (err) {
      setError(err as Error)
      setIsActive(false)
    }
  }, [isInitialized])

  const stopConversation = useCallback(async () => {
    if (!isActive) return

    try {
      const result = await sdkRef.current.stopPipeline()
      setPerformance(result.performance)
      setIsActive(false)
      setIsListening(false)
      setIsProcessing(false)
      sessionRef.current = null
    } catch (err) {
      setError(err as Error)
    }
  }, [isActive])

  const transcribe = useCallback(async (audio: Float32Array): Promise<string> => {
    if (!isInitialized) {
      throw new Error('SDK not initialized')
    }

    const result = await sdkRef.current.quickTranscribe(audio)
    return result.text
  }, [isInitialized])

  // Event handlers
  useEffect(() => {
    const handlePipelineEvent = (event: VoicePipelineEvent) => {
      switch (event.type) {
        case 'speechStart':
          setIsListening(true)
          break
        case 'speechEnd':
          setIsListening(false)
          setIsProcessing(true)
          break
        case 'transcriptionComplete':
          setTranscript(event.data.text)
          setIsProcessing(true)
          break
        case 'llmToken':
          setResponse(prev => prev + event.data.token)
          break
        case 'llmComplete':
          setIsProcessing(false)
          break
        case 'error':
          setError(event.data.error)
          setIsProcessing(false)
          break
      }
    }

    const handlePipelineComplete = (result: VoicePipelineResult) => {
      setPerformance(result.performance)
      setLatency(result.performance.totalDuration)
      setIsActive(false)
      setIsListening(false)
      setIsProcessing(false)
    }

    sdkRef.current.on('pipelineEvent', handlePipelineEvent)
    sdkRef.current.on('pipelineComplete', handlePipelineComplete)

    return () => {
      sdkRef.current.off('pipelineEvent', handlePipelineEvent)
      sdkRef.current.off('pipelineComplete', handlePipelineComplete)
    }
  }, [])

  // Auto-initialize
  useEffect(() => {
    if (options.autoInitialize !== false && !isInitialized) {
      initialize()
    }
  }, [options.autoInitialize, initialize, isInitialized])

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (isActive) {
        stopConversation()
      }
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return {
    isInitialized,
    isActive,
    isListening,
    isProcessing,
    transcript,
    response,
    error,
    initialize,
    startConversation,
    stopConversation,
    transcribe,
    latency,
    performance
  }
}
```

### 5.2 Vue Integration

**File**: `packages/integrations/vue/src/composables/useVoiceSDK.ts`
```typescript
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { voiceSDK } from '@runanywhere/voice-sdk'
import type { VoiceConfig, VoicePipelineConfig, VoicePipelineEvent, VoicePipelineResult } from '@runanywhere/voice-sdk'

export interface UseVoiceSDKOptions {
  config: VoiceConfig
  autoInitialize?: boolean
}

export function useVoiceSDK(options: UseVoiceSDKOptions) {
  // Reactive state
  const isInitialized = ref(false)
  const isActive = ref(false)
  const isListening = ref(false)
  const isProcessing = ref(false)
  const transcript = ref('')
  const response = ref('')
  const error = ref<Error | null>(null)
  const latency = ref<number | null>(null)
  const performance = ref<VoicePerformanceMetrics | null>(null)

  let currentSession: VoiceSession | null = null

  // Computed
  const isReady = computed(() => isInitialized.value && !error.value)
  const hasActivity = computed(() => isListening.value || isProcessing.value)

  // Methods
  const initialize = async () => {
    try {
      error.value = null
      await voiceSDK.initialize(options.config)
      isInitialized.value = true
    } catch (err) {
      error.value = err as Error
    }
  }

  const startConversation = async (config?: Partial<VoicePipelineConfig>) => {
    if (!isInitialized.value) {
      throw new Error('SDK not initialized')
    }

    try {
      error.value = null
      isActive.value = true
      transcript.value = ''
      response.value = ''

      currentSession = await voiceSDK.startConversation(config)

    } catch (err) {
      error.value = err as Error
      isActive.value = false
    }
  }

  const stopConversation = async () => {
    if (!isActive.value) return

    try {
      const result = await voiceSDK.stopPipeline()
      performance.value = result.performance
      isActive.value = false
      isListening.value = false
      isProcessing.value = false
      currentSession = null
    } catch (err) {
      error.value = err as Error
    }
  }

  const transcribe = async (audio: Float32Array): Promise<string> => {
    if (!isInitialized.value) {
      throw new Error('SDK not initialized')
    }

    const result = await voiceSDK.quickTranscribe(audio)
    return result.text
  }

  // Event handlers
  const handlePipelineEvent = (event: VoicePipelineEvent) => {
    switch (event.type) {
      case 'speechStart':
        isListening.value = true
        break
      case 'speechEnd':
        isListening.value = false
        isProcessing.value = true
        break
      case 'transcriptionComplete':
        transcript.value = event.data.text
        isProcessing.value = true
        break
      case 'llmToken':
        response.value += event.data.token
        break
      case 'llmComplete':
        isProcessing.value = false
        break
      case 'error':
        error.value = event.data.error
        isProcessing.value = false
        break
    }
  }

  const handlePipelineComplete = (result: VoicePipelineResult) => {
    performance.value = result.performance
    latency.value = result.performance.totalDuration
    isActive.value = false
    isListening.value = false
    isProcessing.value = false
  }

  // Lifecycle
  onMounted(() => {
    voiceSDK.on('pipelineEvent', handlePipelineEvent)
    voiceSDK.on('pipelineComplete', handlePipelineComplete)

    if (options.autoInitialize !== false) {
      initialize()
    }
  })

  onUnmounted(() => {
    voiceSDK.off('pipelineEvent', handlePipelineEvent)
    voiceSDK.off('pipelineComplete', handlePipelineComplete)

    if (isActive.value) {
      stopConversation()
    }
  })

  return {
    // State
    isInitialized: readonly(isInitialized),
    isActive: readonly(isActive),
    isListening: readonly(isListening),
    isProcessing: readonly(isProcessing),
    transcript: readonly(transcript),
    response: readonly(response),
    error: readonly(error),
    latency: readonly(latency),
    performance: readonly(performance),

    // Computed
    isReady,
    hasActivity,

    // Actions
    initialize,
    startConversation,
    stopConversation,
    transcribe
  }
}
```

## Phase 6: Testing Strategy (Comprehensive)

### 6.1 Test Setup

**File**: `packages/core/tests/setup.ts`
```typescript
import { vi } from 'vitest'
import 'happy-dom/global-registrator'

// Mock Web APIs not available in test environment
global.AudioContext = vi.fn(() => ({
  createMediaStreamSource: vi.fn(),
  createBufferSource: vi.fn(),
  createBuffer: vi.fn(),
  destination: {},
  close: vi.fn(),
  resume: vi.fn(),
  state: 'running'
})) as any

global.navigator.mediaDevices = {
  getUserMedia: vi.fn(() => Promise.resolve({
    getTracks: () => [{ stop: vi.fn() }]
  } as any))
} as any

global.MediaRecorder = vi.fn() as any
global.crypto.randomUUID = vi.fn(() => 'test-uuid')

// Mock IndexedDB
global.indexedDB = {
  open: vi.fn(),
  deleteDatabase: vi.fn()
} as any

// Setup global test utilities
global.createMockAudioBuffer = (length: number = 1024) => {
  return new Float32Array(length).fill(0.1)
}

global.createMockModelInfo = (overrides = {}) => ({
  id: 'test-model',
  name: 'Test Model',
  version: '1.0.0',
  framework: 'transformers.js',
  modality: 'voice-to-text',
  sizeBytes: 1000000,
  compatibleFrameworks: ['transformers.js'],
  downloadUrls: ['http://example.com/model'],
  memoryRequirements: {
    minMemoryMB: 100,
    recommendedMemoryMB: 200,
    requiresGPU: false
  },
  ...overrides
})
```

### 6.2 Unit Tests Examples

**File**: `packages/core/tests/unit/foundation/di/container.test.ts`
```typescript
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { DIContainer } from '../../../../src/foundation/di/container'

describe('DIContainer', () => {
  let container: DIContainer

  beforeEach(() => {
    container = new DIContainer()
  })

  it('should register and resolve services', async () => {
    const mockService = { test: true }
    container.register('testService', () => mockService)

    const resolved = await container.get('testService')
    expect(resolved).toBe(mockService)
  })

  it('should handle singleton services correctly', async () => {
    let createCount = 0
    container.register('singleton', () => {
      createCount++
      return { count: createCount }
    }, { singleton: true })

    const first = await container.get('singleton')
    const second = await container.get('singleton')

    expect(first).toBe(second)
    expect(createCount).toBe(1)
  })

  it('should detect circular dependencies', async () => {
    container.register('a', () => ({}), { dependencies: ['b'] })
    container.register('b', () => ({}), { dependencies: ['a'] })

    await expect(container.get('a')).rejects.toThrow('Circular dependency detected')
  })

  it('should emit service creation events', async () => {
    const listener = vi.fn()
    container.on('serviceCreated', listener)

    container.register('test', () => ({ value: 42 }))
    await container.get('test')

    expect(listener).toHaveBeenCalledWith({
      name: 'test',
      instance: { value: 42 }
    })
  })
})
```

**File**: `packages/core/tests/unit/capabilities/voice-processing/pipeline-manager.test.ts`
```typescript
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { WebVoicePipelineManager } from '../../../../src/capabilities/voice-processing/services/pipeline-manager'
import { DIContainer } from '../../../../src/foundation/di/container'

describe('WebVoicePipelineManager', () => {
  let pipelineManager: WebVoicePipelineManager
  let mockContainer: DIContainer
  let mockConfig: VoicePipelineConfig

  beforeEach(() => {
    mockContainer = new DIContainer()
    mockConfig = {
      enableVAD: true,
      enableSTT: true,
      enableLLM: false,
      enableTTS: false,
      vad: { sensitivity: 0.5 },
      stt: { language: 'en', modelSize: 'base' }
    }

    // Mock services
    mockContainer.register('vadService', () => ({
      initialize: vi.fn(),
      processAudio: vi.fn(() => ({ speechDetected: true })),
      stop: vi.fn()
    }))

    mockContainer.register('sttService', () => ({
      initialize: vi.fn(),
      transcribe: vi.fn(() => ({ text: 'Hello world', confidence: 0.95 })),
      stop: vi.fn()
    }))

    pipelineManager = new WebVoicePipelineManager(mockConfig, mockContainer)
  })

  it('should initialize all configured services', async () => {
    await pipelineManager.initialize()

    const vadService = await mockContainer.get('vadService')
    const sttService = await mockContainer.get('sttService')

    expect(vadService.initialize).toHaveBeenCalledWith(mockConfig.vad)
    expect(sttService.initialize).toHaveBeenCalledWith(mockConfig.stt)
  })

  it('should emit speech events on VAD detection', async () => {
    await pipelineManager.initialize()
    const session = await pipelineManager.startPipeline()

    const speechStartSpy = vi.fn()
    pipelineManager.on('speechStart', speechStartSpy)

    const audioData = createMockAudioBuffer()
    await pipelineManager.processAudioChunk(audioData)

    expect(speechStartSpy).toHaveBeenCalledWith({ timestamp: expect.any(Number) })
  })

  it('should process accumulated audio on speech end', async () => {
    const mockSTTService = {
      initialize: vi.fn(),
      transcribe: vi.fn(() => ({
        text: 'Test transcription',
        confidence: 0.9,
        segments: []
      }))
    }

    mockContainer.register('sttService', () => mockSTTService, { singleton: true })

    await pipelineManager.initialize()
    await pipelineManager.startPipeline()

    const transcriptionSpy = vi.fn()
    pipelineManager.on('transcriptionComplete', transcriptionSpy)

    // Simulate speech detection cycle
    const audioData = createMockAudioBuffer()
    await pipelineManager.processAudioChunk(audioData)

    // Mock VAD returning false (speech end)
    const vadService = await mockContainer.get('vadService')
    vadService.processAudio.mockReturnValue({ speechDetected: false })

    await pipelineManager.processAudioChunk(audioData)

    expect(mockSTTService.transcribe).toHaveBeenCalled()
    expect(transcriptionSpy).toHaveBeenCalledWith({
      text: 'Test transcription',
      confidence: 0.9,
      segments: []
    })
  })
})
```

### 6.3 Integration Tests

**File**: `packages/core/tests/integration/voice-pipeline.test.ts`
```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { voiceSDK } from '../../src/public/sdk/voice-sdk'
import { VoiceConfigBuilder, VoicePipelineConfigBuilder } from '../../src/public/sdk/config-builder'

describe('Voice Pipeline Integration', () => {
  beforeEach(async () => {
    // Reset SDK between tests
    voiceSDK.destroy()

    const config = VoiceConfigBuilder.create()
      .withSTTModel('whisper-tiny', { language: 'en' })
      .withFeatures({ transcription: true, llm: false, tts: false })
      .build()

    await voiceSDK.initialize(config)
  })

  it('should complete transcription-only pipeline', async () => {
    const audioData = createMockAudioBuffer(16000) // 1 second at 16kHz

    const result = await voiceSDK.quickTranscribe(audioData, {
      language: 'en',
      modelSize: 'tiny'
    })

    expect(result).toBeDefined()
    expect(typeof result).toBe('string')
  })

  it('should handle conversational pipeline with events', async () => {
    const config = VoicePipelineConfigBuilder.conversational({
      enableTTS: false // Disable TTS for testing
    })

    const events: any[] = []
    voiceSDK.on('pipelineEvent', (event) => {
      events.push(event)
    })

    const session = await voiceSDK.createPipeline(config)
    expect(session).toBeDefined()

    // Simulate audio processing
    const audioData = createMockAudioBuffer()
    // This would normally trigger through audio processing
    // For tests, we'll verify the pipeline can be created and destroyed

    const result = await voiceSDK.stopPipeline()
    expect(result).toBeDefined()
    expect(result.sessionId).toBe(session.id)
  })

  it('should handle errors gracefully', async () => {
    const config = VoicePipelineConfigBuilder.create()
      .enableSTT('invalid-language') // Invalid configuration
      .build()

    await expect(voiceSDK.createPipeline(config))
      .rejects.toThrow()
  })
})
```

### 6.4 Performance Tests

**File**: `packages/core/tests/performance/latency.test.ts`
```typescript
import { describe, it, expect } from 'vitest'
import { voiceSDK } from '../../src/public/sdk/voice-sdk'
import { VoiceConfigBuilder } from '../../src/public/sdk/config-builder'

describe('Performance Tests', () => {
  it('should meet latency targets for transcription', async () => {
    const config = VoiceConfigBuilder.create()
      .withSTTModel('whisper-tiny') // Fastest model
      .withPerformance({ targetLatency: 200 })
      .build()

    await voiceSDK.initialize(config)

    const audioData = createMockAudioBuffer(8000) // 0.5 seconds

    const startTime = performance.now()
    const result = await voiceSDK.quickTranscribe(audioData)
    const endTime = performance.now()

    const latency = endTime - startTime

    expect(latency).toBeLessThan(200) // Target latency
    expect(result).toBeDefined()
  }, { timeout: 10000 })

  it('should handle memory pressure gracefully', async () => {
    const config = VoiceConfigBuilder.create()
      .withPerformance({ maxMemoryMB: 100 }) // Low memory limit
      .build()

    await voiceSDK.initialize(config)

    // This should not throw even with low memory
    const metrics = await voiceSDK.getPerformanceMetrics()
    expect(metrics.memoryUsage).toBeLessThan(100 * 1024 * 1024) // 100MB
  })
})
```

## Phase 7: Sample Applications

### 7.1 Vanilla JavaScript Demo

**File**: `packages/demo-apps/vanilla/src/main.ts`
```typescript
import { voiceSDK, VoiceConfigBuilder, VoicePipelineConfigBuilder } from '@runanywhere/voice-sdk'
import type { VoicePipelineEvent } from '@runanywhere/voice-sdk'

class VoiceDemo {
  private isInitialized = false
  private isRecording = false

  private initButton = document.getElementById('init-btn') as HTMLButtonElement
  private recordButton = document.getElementById('record-btn') as HTMLButtonElement
  private transcriptDiv = document.getElementById('transcript') as HTMLDivElement
  private responseDiv = document.getElementById('response') as HTMLDivElement
  private statusDiv = document.getElementById('status') as HTMLDivElement

  constructor() {
    this.setupEventListeners()
    this.setupVoiceSDKEvents()
  }

  private setupEventListeners() {
    this.initButton.addEventListener('click', () => this.initialize())
    this.recordButton.addEventListener('click', () => this.toggleRecording())
  }

  private setupVoiceSDKEvents() {
    voiceSDK.on('pipelineEvent', (event: VoicePipelineEvent) => {
      this.handlePipelineEvent(event)
    })

    voiceSDK.on('error', ({ error }) => {
      this.updateStatus(`Error: ${error.message}`, 'error')
    })
  }

  private async initialize() {
    if (this.isInitialized) return

    try {
      this.updateStatus('Initializing...', 'info')

      const config = VoiceConfigBuilder.create()
        .withSTTModel('whisper-base', { language: 'en' })
        .withLLMProvider('openai', {
          apiKey: (document.getElementById('api-key') as HTMLInputElement).value,
          model: 'gpt-3.5-turbo'
        })
        .withFeatures({
          transcription: true,
          llm: true,
          tts: false,
          analytics: true
        })
        .build()

      await voiceSDK.initialize(config)

      this.isInitialized = true
      this.initButton.disabled = true
      this.recordButton.disabled = false

      this.updateStatus('Ready! Click "Start Recording" to begin.', 'success')

    } catch (error) {
      this.updateStatus(`Initialization failed: ${(error as Error).message}`, 'error')
    }
  }

  private async toggleRecording() {
    if (!this.isInitialized) return

    try {
      if (this.isRecording) {
        await this.stopRecording()
      } else {
        await this.startRecording()
      }
    } catch (error) {
      this.updateStatus(`Recording error: ${(error as Error).message}`, 'error')
    }
  }

  private async startRecording() {
    const config = VoicePipelineConfigBuilder.conversational({
      enableTTS: false,
      streaming: true,
      interruption: false
    })

    await voiceSDK.createPipeline(config)

    this.isRecording = true
    this.recordButton.textContent = 'Stop Recording'
    this.recordButton.classList.add('recording')

    this.transcriptDiv.textContent = ''
    this.responseDiv.textContent = ''

    this.updateStatus('Listening...', 'info')
  }

  private async stopRecording() {
    const result = await voiceSDK.stopPipeline()

    this.isRecording = false
    this.recordButton.textContent = 'Start Recording'
    this.recordButton.classList.remove('recording')

    this.updateStatus(
      `Completed in ${Math.round(result.duration / 1000)}s (STT: ${Math.round(result.performance.sttLatency)}ms, LLM: ${Math.round(result.performance.llmLatency)}ms)`,
      'success'
    )
  }

  private handlePipelineEvent(event: VoicePipelineEvent) {
    switch (event.type) {
      case 'speechStart':
        this.updateStatus('Speech detected...', 'info')
        break

      case 'speechEnd':
        this.updateStatus('Processing...', 'info')
        break

      case 'transcriptionComplete':
        this.transcriptDiv.textContent = event.data.text
        this.updateStatus('Generating response...', 'info')
        break

      case 'llmToken':
        this.responseDiv.textContent += event.data.token
        break

      case 'llmComplete':
        this.updateStatus('Response complete!', 'success')
        break

      case 'error':
        this.updateStatus(`Pipeline error: ${event.data.error.message}`, 'error')
        break
    }
  }

  private updateStatus(message: string, type: 'info' | 'success' | 'error') {
    this.statusDiv.textContent = message
    this.statusDiv.className = `status ${type}`
  }
}

// Initialize the demo when the page loads
document.addEventListener('DOMContentLoaded', () => {
  new VoiceDemo()
})
```

### 7.2 React Demo Application

**File**: `packages/demo-apps/react-demo/src/components/VoiceChat.tsx`
```typescript
import React, { useState } from 'react'
import { useVoiceSDK } from '@runanywhere/voice-sdk-react'
import { VoiceConfigBuilder, VoicePipelineConfigBuilder } from '@runanywhere/voice-sdk'
import { Microphone, MicrophoneSlash, Cog6Tooth } from '@heroicons/react/24/outline'

interface VoiceChatProps {
  apiKey: string
}

export function VoiceChat({ apiKey }: VoiceChatProps) {
  const [showSettings, setShowSettings] = useState(false)

  const config = VoiceConfigBuilder.create()
    .withSTTModel('whisper-base', { language: 'en' })
    .withLLMProvider('openai', { apiKey, model: 'gpt-3.5-turbo' })
    .withFeatures({ transcription: true, llm: true, analytics: true })
    .build()

  const {
    isInitialized,
    isActive,
    isListening,
    isProcessing,
    transcript,
    response,
    error,
    initialize,
    startConversation,
    stopConversation,
    performance
  } = useVoiceSDK({ config, autoInitialize: true })

  const handleToggleConversation = async () => {
    if (isActive) {
      await stopConversation()
    } else {
      const pipelineConfig = VoicePipelineConfigBuilder.conversational({
        enableTTS: false,
        streaming: true
      })
      await startConversation(pipelineConfig)
    }
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4">
        <h3 className="text-red-800 font-medium">Error</h3>
        <p className="text-red-600 mt-1">{error.message}</p>
        <button
          onClick={() => window.location.reload()}
          className="mt-3 bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700"
        >
          Reload
        </button>
      </div>
    )
  }

  if (!isInitialized) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="animate-spin h-8 w-8 border-2 border-blue-500 border-t-transparent rounded-full mr-3" />
        <span>Initializing Voice SDK...</span>
      </div>
    )
  }

  return (
    <div className="max-w-4xl mx-auto p-6">
      <div className="bg-white rounded-lg shadow-lg">
        <div className="border-b px-6 py-4 flex items-center justify-between">
          <h2 className="text-xl font-semibold">Voice Assistant</h2>
          <button
            onClick={() => setShowSettings(!showSettings)}
            className="text-gray-400 hover:text-gray-600"
          >
            <Cog6Tooth className="h-5 w-5" />
          </button>
        </div>

        <div className="p-6">
          <div className="text-center mb-8">
            <button
              onClick={handleToggleConversation}
              disabled={!isInitialized}
              className={`
                w-20 h-20 rounded-full flex items-center justify-center transition-all
                ${isActive
                  ? 'bg-red-500 hover:bg-red-600 text-white'
                  : 'bg-blue-500 hover:bg-blue-600 text-white'
                }
                ${isListening ? 'animate-pulse' : ''}
                disabled:opacity-50 disabled:cursor-not-allowed
              `}
            >
              {isActive ? (
                <MicrophoneSlash className="h-8 w-8" />
              ) : (
                <Microphone className="h-8 w-8" />
              )}
            </button>

            <div className="mt-4">
              <div className="text-sm font-medium text-gray-600 mb-1">
                Status: {
                  isListening ? 'Listening...' :
                  isProcessing ? 'Processing...' :
                  isActive ? 'Ready' : 'Stopped'
                }
              </div>
              {performance && (
                <div className="text-xs text-gray-400">
                  Total: {Math.round(performance.totalDuration / 1000)}s |
                  STT: {Math.round(performance.sttLatency)}ms |
                  LLM: {Math.round(performance.llmLatency)}ms
                </div>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <h3 className="font-medium text-gray-900 mb-3">Transcript</h3>
              <div className="bg-gray-50 rounded-lg p-4 min-h-32">
                <p className="text-gray-700 whitespace-pre-wrap">
                  {transcript || 'Speak to see transcription...'}
                </p>
              </div>
            </div>

            <div>
              <h3 className="font-medium text-gray-900 mb-3">AI Response</h3>
              <div className="bg-blue-50 rounded-lg p-4 min-h-32">
                <p className="text-gray-700 whitespace-pre-wrap">
                  {response || 'AI response will appear here...'}
                  {isProcessing && response && (
                    <span className="inline-block w-2 h-5 bg-blue-500 ml-1 animate-pulse" />
                  )}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {showSettings && (
        <div className="mt-6 bg-white rounded-lg shadow-lg p-6">
          <h3 className="font-medium text-gray-900 mb-4">Settings</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
            <div>
              <label className="text-gray-600">STT Model</label>
              <p className="font-medium">Whisper Base</p>
            </div>
            <div>
              <label className="text-gray-600">Language</label>
              <p className="font-medium">English</p>
            </div>
            <div>
              <label className="text-gray-600">LLM Provider</label>
              <p className="font-medium">OpenAI GPT-3.5</p>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
```

## Phase 8: Implementation Timeline & Next Steps

### Implementation Phases

#### Phase 1: Foundation (Weeks 1-3)
- [x] Project setup with monorepo structure
- [x] TypeScript configuration with strict mode
- [x] Build system with Vite and worker support
- [x] Testing framework with Vitest
- [x] Linting and formatting with ESLint/Prettier
- [x] Foundation layer (DI, logging, error handling)

#### Phase 2: Core Infrastructure (Weeks 4-6)
- [x] Model management system (registry, download, validation)
- [x] Storage adapters (IndexedDB, Cache API)
- [x] Memory management with pressure handling
- [x] Device capability detection
- [x] Service container with health monitoring

#### Phase 3: Voice Pipeline (Weeks 7-10)
- [ ] VAD integration with @ricky0123/vad-web
- [ ] STT integration with Transformers.js Whisper
- [ ] TTS integration with ONNX Runtime Web
- [ ] LLM integration with OpenAI/Anthropic APIs
- [ ] Pipeline orchestrator with event system
- [ ] Web Workers for audio processing

#### Phase 4: SDK API (Weeks 11-12)
- [ ] Main VoiceSDK class with iOS-inspired API
- [ ] Configuration builders with fluent interface
- [ ] Error handling with recovery suggestions
- [ ] Performance monitoring and analytics

#### Phase 5: Framework Integrations (Weeks 13-15)
- [ ] React hooks and components
- [ ] Vue composables and components
- [ ] Angular services and components
- [ ] Framework-agnostic vanilla JS API

#### Phase 6: Demo Applications (Weeks 16-18)
- [ ] Vanilla JavaScript demo with live transcription
- [ ] React demo with conversational AI
- [ ] Vue demo with voice controls
- [ ] Performance benchmarking tools

#### Phase 7: Production Ready (Weeks 19-20)
- [ ] Comprehensive test suite (90%+ coverage)
- [ ] Performance optimization and profiling
- [ ] Bundle size optimization (<5MB core)
- [ ] Browser compatibility testing
- [ ] Security audit and fixes

### Success Metrics

**Performance Targets**:
- VAD Latency: <10ms (browser constraints)
- STT Latency: <300ms for Whisper Tiny, <500ms for Base
- LLM Latency: Depends on API (target <2s for simple queries)
- Memory Usage: <512MB for full pipeline
- Bundle Size: <5MB (excluding models)
- Browser Support: Chrome 90+, Firefox 90+, Safari 15+

**Quality Targets**:
- Test Coverage: >90% for core functionality
- TypeScript: Strict mode with zero `any` types
- Documentation: Complete API docs and guides
- Examples: Working demos for all major frameworks

### Deployment Strategy

**NPM Packages**:
```bash
@runanywhere/voice-sdk              # Core SDK
@runanywhere/voice-sdk-react        # React integration
@runanywhere/voice-sdk-vue          # Vue integration
@runanywhere/voice-sdk-angular      # Angular integration
```

**CDN Distribution**:
```html
<!-- UMD build for script tags -->
<script src="https://cdn.jsdelivr.net/npm/@runanywhere/voice-sdk@1.0.0/dist/umd/voice-sdk.min.js"></script>
```

**Model Hosting**:
- Hugging Face Hub for Whisper models
- Custom CDN for optimized TTS models
- Progressive download with resume capability
- Edge caching for global performance

This comprehensive plan provides a complete roadmap for implementing a production-ready voice AI SDK for the web, following the same architectural patterns as the iOS SDK while being optimized for web development best practices. The plan includes detailed TypeScript implementations, testing strategies, framework integrations, and a clear path to deployment.

## Phase 4: SDK API Design

### 4.1 Initialization API

```typescript
interface VoiceFlowConfig {
  performance: {
    targetLatency: number
    modelQuality: 'fastest' | 'balanced' | 'best'
    enableGPU: boolean
    maxMemoryMB: number
  }
  models: {
    vad: { provider: 'silero' | 'energy' }
    stt: { provider: 'transformers' | 'whisper-cpp', size: 'tiny' | 'base' }
    tts: { provider: 'onnx' | 'sherpa', voice: string }
    llm: { provider: 'openai' | 'anthropic', apiKey: string }
  }
  features: {
    streaming: boolean
    interruption: boolean
    caching: boolean
    analytics: boolean
  }
}
```

### 4.2 Main SDK Class

```typescript
class VoiceFlowSDK {
  // Lifecycle
  static create(config: VoiceFlowConfig): Promise<VoiceFlowSDK>
  initialize(): Promise<void>
  destroy(): void

  // Pipeline Control
  startListening(): Promise<void>
  stopListening(): void
  process(audio: AudioBuffer): Promise<string>

  // Events
  on(event: 'speech-start' | 'speech-end' | 'transcription' | 'response' | 'audio', callback: Function): void

  // Configuration
  updateConfig(config: Partial<VoiceFlowConfig>): void

  // Utilities
  preloadModels(): Promise<void>
  getMetrics(): PerformanceMetrics
  clearCache(): Promise<void>
}
```

### 4.3 React Hooks (Optional Package)

```typescript
// @voiceflow/react
export function useVoiceFlow(config?: VoiceFlowConfig) {
  // State
  const [isListening, setIsListening] = useState(false)
  const [transcript, setTranscript] = useState('')
  const [response, setResponse] = useState('')
  const [isProcessing, setIsProcessing] = useState(false)

  // Methods
  const start = useCallback(() => {}, [])
  const stop = useCallback(() => {}, [])
  const reset = useCallback(() => {}, [])

  return { isListening, transcript, response, isProcessing, start, stop, reset }
}
```

## Phase 5: Build and Distribution

### 5.1 Build Pipeline

**Webpack Configuration**:
- Multiple entry points (main, workers)
- Code splitting for lazy loading
- Tree shaking for minimal bundle
- WASM module handling
- Source map generation

**Bundle Outputs**:
- ESM for modern bundlers
- UMD for script tags
- Separate worker bundles
- TypeScript declarations

### 5.2 NPM Package Structure

```
dist/
├── esm/           # ES modules
├── cjs/           # CommonJS
├── umd/           # UMD bundle
├── workers/       # Worker scripts
├── wasm/          # WASM modules
├── types/         # TypeScript definitions
└── models/        # Model configs
```

### 5.3 CDN Distribution

**Model Hosting**:
- Cloudflare R2 for model storage
- CDN distribution with edge caching
- Compression (Brotli for models)
- Range requests for progressive download

## Phase 6: Testing Strategy

### 6.1 Unit Tests

- Model manager functions
- Provider adapters
- Utility functions
- Cache operations
- Worker communication

### 6.2 Integration Tests

- End-to-end pipeline
- Provider switching
- Error recovery
- Performance benchmarks
- Memory leak detection

### 6.3 Performance Tests

- Latency measurements
- Memory usage tracking
- CPU utilization
- Real-time factor calculation
- Stress testing

## Phase 7: Demo Application

### 7.1 Features

**Core Functionality**:
- Real-time voice conversation
- Visual latency metrics
- Configuration playground
- Model comparison tool
- Performance dashboard

**UI Components**:
- Waveform visualizer
- Transcript display
- Response streaming
- Settings panel
- Metrics graphs

### 7.2 Technology Stack

- **Framework**: React 18 with TypeScript
- **Build Tool**: Vite
- **Styling**: Tailwind CSS
- **State**: Zustand
- **Charts**: Recharts
- **Audio Viz**: WaveSurfer.js

### 7.3 Deployment

- GitHub Pages for demo
- Vercel/Netlify for production
- Docker container option
- PWA configuration

## Phase 8: Documentation

### 8.1 API Documentation

- TypeDoc generation
- Interactive examples
- Code snippets
- Migration guides

### 8.2 Guides

- Quick start guide
- Performance tuning
- Model selection
- Deployment guide
- Troubleshooting

### 8.3 Examples

- Basic usage
- React integration
- Vue integration
- Advanced configuration
- Custom providers

## Implementation Timeline

### Week 1-2: Foundation
- Project setup
- TypeScript configuration
- Basic architecture
- Worker setup

### Week 3-4: Core Components
- Model manager
- VAD integration
- Basic pipeline

### Week 5-6: Providers
- STT implementation
- TTS implementation
- LLM integration

### Week 7-8: Optimization
- Performance tuning
- Caching system
- Memory management

### Week 9-10: SDK Polish
- API finalization
- Error handling
- Testing suite

### Week 11-12: Demo & Docs
- Demo application
- Documentation
- Examples
- Release preparation

## Success Metrics

### Performance Targets
- **VAD Latency**: <5ms
- **STT Latency**: <200ms
- **TTS Latency**: <250ms
- **End-to-End**: <500ms
- **Memory Usage**: <500MB
- **Bundle Size**: <5MB (excluding models)

### Quality Targets
- **Test Coverage**: >80%
- **Documentation**: 100% public API
- **Browser Support**: Chrome 90+, Firefox 90+, Safari 15+
- **TypeScript**: Strict mode, no any

## Deployment Checklist

### Pre-Release
- [ ] All tests passing+
- [ ] Performance benchmarks met
- [ ] Documentation complete
- [ ] Security audit
- [ ] License verification
- [ ] Demo app working

### Release
- [ ] NPM publication
- [ ] GitHub release
- [ ] CDN deployment
- [ ] Documentation site
- [ ] Announcement blog post
- [ ] Community outreach

## Maintenance Plan

### Ongoing Tasks
- Weekly dependency updates
- Monthly performance audits
- Model version updates
- Security patches
- Community support

### Future Enhancements
- WebGPU optimization
- More model providers
- Voice cloning
- Multi-language support
- Emotion detection
- Speaker diarization
