# VoiceFlow SDK - Complete Implementation Plan for High-Performance Browser Voice Processing

## Project Overview

**Name**: `@runanywhere/voice-sdk`
**Goal**: Production-ready TypeScript SDK for ultra-low latency voice AI in browsers
**Target Latency**: <500ms end-to-end
**Distribution**: NPM package with TypeScript support
**Architecture**: Adapted from RunAnywhere Swift SDK's 5-layer architecture

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

## Phase 1: Project Setup and Foundation (iOS SDK Inspired)

### 1.1 Repository Structure (Monorepo with Clean Architecture)

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

### 1.2 Development Environment Setup (Production-Ready)

**Required Tools**:
- **Node.js 20+** (LTS version with latest features)
- **PNPM 8+** (preferred for monorepo management and performance)
- **TypeScript 5.3+** (latest with improved performance and features)
- **Vite 5.0+** (for building and dev server with HMR)
- **Vitest 1.0+** (for testing with native TypeScript support)

**Root package.json**:
```json
{
  "name": "@runanywhere/voice-sdk",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "engines": {
    "node": ">=20.0.0",
    "pnpm": ">=8.0.0"
  },
  "packageManager": "pnpm@8.15.0",
  "scripts": {
    "dev": "pnpm -r dev",
    "build": "pnpm -r build",
    "test": "pnpm -r test",
    "test:coverage": "pnpm -r test:coverage",
    "lint": "pnpm -r lint",
    "format": "prettier --write .",
    "typecheck": "pnpm -r typecheck",
    "clean": "pnpm -r clean",
    "setup": "./scripts/setup-dev.sh"
  },
  "devDependencies": {
    "@typescript-eslint/eslint-plugin": "^7.0.0",
    "@typescript-eslint/parser": "^7.0.0",
    "eslint": "^8.57.0",
    "eslint-config-prettier": "^9.1.0",
    "eslint-plugin-import": "^2.29.0",
    "prettier": "^3.2.0",
    "typescript": "^5.3.0",
    "vitest": "^1.3.0"
  }
}
```

**Core Package Dependencies** (`packages/core/package.json`):
```json
{
  "name": "@runanywhere/voice-sdk",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.js",
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "types": "./dist/index.d.ts"
    },
    "./workers/*": "./dist/workers/*",
    "./package.json": "./package.json"
  },
  "files": [
    "dist",
    "README.md",
    "LICENSE"
  ],
  "sideEffects": false,
  "engines": {
    "node": ">=18.0.0"
  },
  "dependencies": {
    "@ricky0123/vad-web": "^0.0.15",
    "@xenova/transformers": "^2.17.0",
    "onnxruntime-web": "^1.16.0",
    "comlink": "^4.4.1",
    "idb": "^8.0.0",
    "eventemitter3": "^5.0.1",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "@types/node": "^20.11.0",
    "@types/web": "^0.0.138",
    "typescript": "^5.3.0",
    "vite": "^5.1.0",
    "vitest": "^1.3.0",
    "vite-plugin-dts": "^3.7.0",
    "vite-plugin-node-polyfills": "^0.21.0"
  },
  "peerDependencies": {
    "typescript": ">=5.0.0"
  },
  "keywords": [
    "voice",
    "speech",
    "ai",
    "transcription",
    "tts",
    "vad",
    "browser",
    "webgpu",
    "webassembly"
  ]
}
```

**Framework Integration Dependencies**:
```json
// React integration
{
  "peerDependencies": {
    "react": ">=16.8.0",
    "react-dom": ">=16.8.0"
  }
}

// Vue integration
{
  "peerDependencies": {
    "vue": ">=3.0.0"
  }
}

// Angular integration
{
  "peerDependencies": {
    "@angular/core": ">=15.0.0",
    "@angular/common": ">=15.0.0"
  }
}
```

### 1.3 TypeScript Configuration (Strict & Modern)

**Base tsconfig.json** (strict configuration):
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "lib": ["ES2022", "DOM", "DOM.Iterable", "WebWorker"],
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": false,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": false,
    "jsx": "react-jsx",

    // Strict type checking
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedSideEffectImports": true,

    // Module system
    "allowSyntheticDefaultImports": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,

    // Output
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "./dist",
    "removeComments": false,
    "importHelpers": true,

    // Advanced
    "skipLibCheck": true,
    "exactOptionalPropertyTypes": true,
    "useDefineForClassFields": true,

    // Paths for monorepo
    "baseUrl": ".",
    "paths": {
      "@runanywhere/voice-sdk": ["packages/core/src"],
      "@runanywhere/voice-sdk/*": ["packages/core/src/*"],
      "@runanywhere/voice-sdk-react": ["packages/integrations/react/src"],
      "@runanywhere/voice-sdk-vue": ["packages/integrations/vue/src"],
      "@runanywhere/voice-sdk-angular": ["packages/integrations/angular/src"]
    }
  },
  "include": ["src/**/*", "tests/**/*", "**/*.config.*"],
  "exclude": ["node_modules", "dist", "**/*.js"]
}
```

**Core Package tsconfig.json**:
```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "composite": true,
    "declaration": true,
    "declarationMap": true,
    "emitDeclarationOnly": false,
    "lib": ["ES2022", "DOM", "DOM.Iterable", "WebWorker", "WebWorker.ImportScripts"]
  },
  "include": [
    "src/**/*",
    "src/workers/*.worker.ts"
  ],
  "exclude": [
    "tests/**/*",
    "dist/**/*",
    "node_modules/**/*"
  ],
  "references": []
}
```

### 1.4 Build Configuration (Vite + TypeScript)

**Core Package Vite Config** (`packages/core/vite.config.ts`):
```typescript
import { defineConfig } from 'vite'
import dts from 'vite-plugin-dts'
import { resolve } from 'path'

export default defineConfig({
  plugins: [
    dts({
      include: ['src/**/*'],
      exclude: ['src/**/*.test.ts', 'src/**/*.spec.ts'],
      rollupTypes: true,
      tsconfigPath: './tsconfig.json'
    })
  ],

  build: {
    lib: {
      entry: {
        index: resolve(__dirname, 'src/index.ts'),
        'workers/vad': resolve(__dirname, 'src/workers/vad.worker.ts'),
        'workers/stt': resolve(__dirname, 'src/workers/stt.worker.ts'),
        'workers/tts': resolve(__dirname, 'src/workers/tts.worker.ts'),
        'workers/model': resolve(__dirname, 'src/workers/model.worker.ts')
      },
      formats: ['es'],
      fileName: (format, name) => `${name}.js`
    },

    rollupOptions: {
      external: [
        '@ricky0123/vad-web',
        '@xenova/transformers',
        'onnxruntime-web',
        'comlink',
        'idb',
        'eventemitter3'
      ],
      output: {
        globals: {
          '@ricky0123/vad-web': 'VadWeb',
          '@xenova/transformers': 'Transformers',
          'onnxruntime-web': 'OnnxruntimeWeb',
          'comlink': 'Comlink',
          'idb': 'idb',
          'eventemitter3': 'EventEmitter3'
        },
        preserveModules: false,
        // Ensure workers are separate chunks
        manualChunks: (id) => {
          if (id.includes('worker')) {
            return `workers/${id.split('/').pop()?.replace('.worker.ts', '')}`
          }
        }
      }
    },

    target: 'es2022',
    minify: 'terser',
    sourcemap: true,

    // Ensure workers are built properly
    worker: {
      format: 'es',
      plugins: () => []
    }
  },

  optimizeDeps: {
    include: ['eventemitter3', 'comlink'],
    exclude: ['@ricky0123/vad-web', '@xenova/transformers', 'onnxruntime-web']
  },

  define: {
    'process.env.NODE_ENV': '"production"'
  }
})
```

### 1.5 Testing Configuration (Vitest)

**Core Package Vitest Config** (`packages/core/vitest.config.ts`):
```typescript
import { defineConfig } from 'vitest/config'
import { resolve } from 'path'

export default defineConfig({
  test: {
    // Environment
    environment: 'happy-dom', // Lightweight DOM for testing
    globals: true,

    // Files
    include: ['tests/**/*.{test,spec}.{js,ts}'],
    exclude: ['tests/fixtures/**/*', 'tests/mocks/**/*'],

    // Coverage
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      reportsDirectory: './coverage',
      include: ['src/**/*'],
      exclude: [
        'src/**/*.test.ts',
        'src/**/*.spec.ts',
        'src/workers/*.worker.ts', // Workers tested separately
        'src/**/*.d.ts'
      ],
      thresholds: {
        global: {
          branches: 80,
          functions: 80,
          lines: 80,
          statements: 80
        }
      }
    },

    // Timeouts
    testTimeout: 30000,
    hookTimeout: 30000,

    // Setup
    setupFiles: ['./tests/setup.ts'],

    // Reporters
    reporter: ['verbose', 'junit'],
    outputFile: './test-results.xml',

    // Pool options for worker testing
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
        isolate: true
      }
    }
  },

  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
      '@tests': resolve(__dirname, 'tests')
    }
  }
})
```

### 1.6 Linting & Formatting Configuration

**ESLint Config** (`config/eslint.config.js`):
```javascript
import js from '@eslint/js'
import tsPlugin from '@typescript-eslint/eslint-plugin'
import tsParser from '@typescript-eslint/parser'
import importPlugin from 'eslint-plugin-import'
import prettierConfig from 'eslint-config-prettier'

export default [
  js.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
        project: ['./tsconfig.json', './packages/*/tsconfig.json']
      }
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
      import: importPlugin
    },
    rules: {
      // TypeScript specific
      '@typescript-eslint/no-unused-vars': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
      '@typescript-eslint/prefer-optional-chain': 'error',
      '@typescript-eslint/no-non-null-assertion': 'error',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/await-thenable': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/prefer-readonly': 'error',
      '@typescript-eslint/prefer-as-const': 'error',

      // Import rules
      'import/order': ['error', {
        'groups': [
          'builtin',
          'external',
          'internal',
          'parent',
          'sibling',
          'index'
        ],
        'newlines-between': 'always',
        'alphabetize': { order: 'asc', caseInsensitive: true }
      }],
      'import/no-default-export': 'error',
      'import/prefer-default-export': 'off',

      // General
      'no-console': 'warn',
      'prefer-const': 'error',
      'no-var': 'error',
      'object-shorthand': 'error',
      'prefer-template': 'error'
    }
  },
  {
    files: ['**/*.worker.ts'],
    rules: {
      'no-restricted-globals': 'off' // Allow worker globals
    }
  },
  prettierConfig
]
```

**Prettier Config** (`config/prettier.config.js`):
```javascript
export default {
  printWidth: 100,
  tabWidth: 2,
  useTabs: false,
  semi: false,
  singleQuote: true,
  quoteProps: 'as-needed',
  trailingComma: 'es5',
  bracketSpacing: true,
  bracketSameLine: false,
  arrowParens: 'avoid',
  endOfLine: 'lf',

  // Plugin specific
  plugins: [],

  overrides: [
    {
      files: '*.json',
      options: {
        parser: 'json'
      }
    },
    {
      files: '*.md',
      options: {
        parser: 'markdown',
        proseWrap: 'preserve'
      }
    }
  ]
}
```

### 1.7 Development Scripts

**Setup Script** (`scripts/setup-dev.sh`):
```bash
#!/bin/bash
set -e

echo "🚀 Setting up development environment..."

# Check Node.js version
node_version=$(node -v | cut -c2-)
required_version="20.0.0"

if ! node -pe "require('semver').gte('$node_version', '$required_version')" 2>/dev/null; then
    echo "❌ Node.js $required_version or higher is required. Current: $node_version"
    exit 1
fi

# Check PNPM
if ! command -v pnpm &> /dev/null; then
    echo "📦 Installing PNPM..."
    corepack enable
    corepack prepare pnpm@8.15.0 --activate
fi

# Install dependencies
echo "📦 Installing dependencies..."
pnpm install --frozen-lockfile

# Setup git hooks
echo "🔧 Setting up git hooks..."
pnpm dlx husky install
pnpm dlx husky add .husky/pre-commit "pnpm lint && pnpm test"
pnpm dlx husky add .husky/commit-msg "pnpm dlx commitlint --edit"

# Build packages
echo "🏗️  Building packages..."
pnpm build

# Setup HTTPS certificates for local development
echo "🔒 Setting up HTTPS certificates..."
mkdir -p .certificates
if [ ! -f .certificates/key.pem ]; then
    openssl req -x509 -newkey rsa:4096 -keyout .certificates/key.pem -out .certificates/cert.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=Dev/CN=localhost"
fi

echo "✅ Development environment setup complete!"
echo ""
echo "🎯 Next steps:"
echo "  pnpm dev          # Start development servers"
echo "  pnpm test         # Run tests"
echo "  pnpm lint         # Lint code"
echo "  pnpm build        # Build all packages"
```

**Build Script** (`scripts/build.sh`):
```bash
#!/bin/bash
set -e

echo "🏗️  Building all packages..."

# Clean previous builds
pnpm clean

# Type check all packages
echo "🔍 Type checking..."
pnpm typecheck

# Build packages in dependency order
echo "📦 Building core package..."
cd packages/core && pnpm build && cd ../..

echo "📦 Building integration packages..."
cd packages/integrations/react && pnpm build && cd ../../..
cd packages/integrations/vue && pnpm build && cd ../../..
cd packages/integrations/angular && pnpm build && cd ../../..

# Build demo apps
echo "📦 Building demo apps..."
cd packages/demo-apps/vanilla && pnpm build && cd ../../..
cd packages/demo-apps/react-demo && pnpm build && cd ../../..

echo "✅ All packages built successfully!"
```

## Phase 2: Core Components Implementation (iOS SDK Inspired)

### 2.1 Foundation Layer Implementation

#### DIContainer (Service Container)
**File**: `src/foundation/di/container.ts`
```typescript
import { EventEmitter } from 'eventemitter3'

interface ServiceDefinition<T = unknown> {
  factory: () => T | Promise<T>
  singleton: boolean
  dependencies?: string[]
}

interface ServiceHealth {
  healthy: boolean
  lastCheck: Date
  error?: Error
}

export class DIContainer extends EventEmitter {
  private services = new Map<string, ServiceDefinition>()
  private instances = new Map<string, unknown>()
  private health = new Map<string, ServiceHealth>()
  private healthCheckInterval?: number

  constructor() {
    super()
    this.startHealthMonitoring()
  }

  register<T>(name: string, factory: () => T | Promise<T>, options: {
    singleton?: boolean
    dependencies?: string[]
  } = {}): void {
    this.services.set(name, {
      factory,
      singleton: options.singleton ?? true,
      dependencies: options.dependencies ?? []
    })
  }

  async get<T>(name: string): Promise<T> {
    const service = this.services.get(name)
    if (!service) {
      throw new Error(`Service '${name}' not found`)
    }

    // Check for circular dependencies
    await this.checkDependencies(name, new Set())

    // Return existing singleton instance
    if (service.singleton && this.instances.has(name)) {
      return this.instances.get(name) as T
    }

    // Create new instance
    const instance = await service.factory()

    if (service.singleton) {
      this.instances.set(name, instance)
    }

    this.emit('serviceCreated', { name, instance })
    return instance as T
  }

  async bootstrap(): Promise<void> {
    // Initialize core services in order
    const coreServices = [
      'logger',
      'configService',
      'deviceCapability',
      'memoryService',
      'modelRegistry',
      'voiceCapability'
    ]

    for (const service of coreServices) {
      await this.get(service)
    }

    this.emit('bootstrapped')
  }

  private async checkDependencies(serviceName: string, visited: Set<string>): Promise<void> {
    if (visited.has(serviceName)) {
      throw new Error(`Circular dependency detected: ${Array.from(visited).join(' -> ')} -> ${serviceName}`)
    }

    visited.add(serviceName)
    const service = this.services.get(serviceName)

    if (service?.dependencies) {
      for (const dep of service.dependencies) {
        await this.checkDependencies(dep, new Set(visited))
      }
    }
  }

  private startHealthMonitoring(): void {
    this.healthCheckInterval = window.setInterval(async () => {
      for (const [name] of this.instances) {
        await this.checkServiceHealth(name)
      }
    }, 30000) // Every 30 seconds like iOS SDK
  }

  private async checkServiceHealth(serviceName: string): Promise<void> {
    try {
      const instance = this.instances.get(serviceName) as any
      const healthy = typeof instance.isHealthy === 'function'
        ? await instance.isHealthy()
        : true

      this.health.set(serviceName, {
        healthy,
        lastCheck: new Date()
      })

      if (!healthy) {
        this.emit('unhealthyService', serviceName)
      }
    } catch (error) {
      this.health.set(serviceName, {
        healthy: false,
        lastCheck: new Date(),
        error: error as Error
      })
      this.emit('serviceError', { serviceName, error })
    }
  }

  destroy(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval)
    }
    this.instances.clear()
    this.services.clear()
    this.removeAllListeners()
  }
}

// Singleton instance
export const container = new DIContainer()
```

#### WebLogger (Foundation Logging)
**File**: `src/foundation/logging/logger.ts`
```typescript
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  FATAL = 4
}

export interface LogEntry {
  level: LogLevel
  message: string
  timestamp: Date
  category?: string
  metadata?: Record<string, unknown>
  error?: Error
}

export interface LogTarget {
  write(entry: LogEntry): Promise<void>
  flush?(): Promise<void>
  close?(): Promise<void>
}

export class WebLogger {
  private targets: LogTarget[] = []
  private minLevel = LogLevel.INFO
  private buffer: LogEntry[] = []
  private flushInterval?: number

  constructor(options: { minLevel?: LogLevel; autoFlush?: boolean } = {}) {
    this.minLevel = options.minLevel ?? LogLevel.INFO

    if (options.autoFlush !== false) {
      this.flushInterval = window.setInterval(() => this.flush(), 5000)
    }
  }

  addTarget(target: LogTarget): void {
    this.targets.push(target)
  }

  async log(level: LogLevel, message: string, options: {
    category?: string
    metadata?: Record<string, unknown>
    error?: Error
  } = {}): Promise<void> {
    if (level < this.minLevel) return

    const entry: LogEntry = {
      level,
      message,
      timestamp: new Date(),
      category: options.category,
      metadata: options.metadata,
      error: options.error
    }

    this.buffer.push(entry)

    // Immediate flush for errors
    if (level >= LogLevel.ERROR) {
      await this.flush()
    }
  }

  debug(message: string, options?: { category?: string; metadata?: Record<string, unknown> }): void {
    this.log(LogLevel.DEBUG, message, options)
  }

  info(message: string, options?: { category?: string; metadata?: Record<string, unknown> }): void {
    this.log(LogLevel.INFO, message, options)
  }

  warn(message: string, options?: { category?: string; metadata?: Record<string, unknown> }): void {
    this.log(LogLevel.WARN, message, options)
  }

  error(message: string, error?: Error, options?: { category?: string; metadata?: Record<string, unknown> }): void {
    this.log(LogLevel.ERROR, message, { ...options, error })
  }

  fatal(message: string, error?: Error, options?: { category?: string; metadata?: Record<string, unknown> }): void {
    this.log(LogLevel.FATAL, message, { ...options, error })
  }

  private async flush(): Promise<void> {
    if (this.buffer.length === 0) return

    const entries = this.buffer.splice(0)

    await Promise.all(
      this.targets.map(async target => {
        try {
          await Promise.all(entries.map(entry => target.write(entry)))
          if (target.flush) {
            await target.flush()
          }
        } catch (error) {
          console.error('Log target error:', error)
        }
      })
    )
  }

  async destroy(): Promise<void> {
    if (this.flushInterval) {
      clearInterval(this.flushInterval)
    }

    await this.flush()

    await Promise.all(
      this.targets.map(async target => {
        if (target.close) {
          await target.close()
        }
      })
    )
  }
}

// Console target implementation
export class ConsoleLogTarget implements LogTarget {
  async write(entry: LogEntry): Promise<void> {
    const prefix = `[${entry.timestamp.toISOString()}] [${LogLevel[entry.level]}]`
    const message = entry.category ? `${prefix} [${entry.category}] ${entry.message}` : `${prefix} ${entry.message}`

    switch (entry.level) {
      case LogLevel.DEBUG:
        console.debug(message, entry.metadata, entry.error)
        break
      case LogLevel.INFO:
        console.info(message, entry.metadata, entry.error)
        break
      case LogLevel.WARN:
        console.warn(message, entry.metadata, entry.error)
        break
      case LogLevel.ERROR:
      case LogLevel.FATAL:
        console.error(message, entry.metadata, entry.error)
        break
    }
  }
}

// Singleton logger instance
export const logger = new WebLogger()
logger.addTarget(new ConsoleLogTarget())
```

### 2.2 Model Manager Component (iOS SDK Inspired)

#### ModelRegistry Implementation
**File**: `src/capabilities/model-management/services/model-registry.ts`
```typescript
import { logger } from '../../../foundation/logging/logger'
import type { ModelInfo, ModelSearchCriteria, ModelCompatibility } from '../../../core/models/model-info'

export interface ModelRegistry {
  searchModels(criteria: ModelSearchCriteria): Promise<ModelInfo[]>
  getModel(id: string): Promise<ModelInfo | null>
  registerModel(model: ModelInfo): Promise<void>
  updateModel(model: ModelInfo): Promise<void>
  removeModel(id: string): Promise<void>
  getCompatibleModels(requirements: ModelCompatibility): Promise<ModelInfo[]>
  refreshRegistry(): Promise<void>
  isHealthy(): boolean
}

export class WebModelRegistry implements ModelRegistry {
  private models = new Map<string, ModelInfo>()
  private lastUpdate = new Date(0)
  private updateInterval: number
  private isUpdating = false

  constructor(private options: {
    autoRefresh?: boolean
    refreshInterval?: number
    registryUrl?: string
  } = {}) {
    this.updateInterval = options.refreshInterval ?? 3600000 // 1 hour

    if (options.autoRefresh !== false) {
      setInterval(() => this.refreshRegistry(), this.updateInterval)
    }
  }

  async searchModels(criteria: ModelSearchCriteria): Promise<ModelInfo[]> {
    await this.ensureInitialized()

    const models = Array.from(this.models.values())

    return models.filter(model => {
      if (criteria.framework && !model.compatibleFrameworks.includes(criteria.framework)) {
        return false
      }

      if (criteria.modality && model.modality !== criteria.modality) {
        return false
      }

      if (criteria.maxSize && model.sizeBytes > criteria.maxSize) {
        return false
      }

      if (criteria.languages && !criteria.languages.some(lang => model.languages?.includes(lang))) {
        return false
      }

      return true
    })
  }

  async getModel(id: string): Promise<ModelInfo | null> {
    await this.ensureInitialized()
    return this.models.get(id) ?? null
  }

  async registerModel(model: ModelInfo): Promise<void> {
    this.models.set(model.id, model)
    logger.info(`Model registered: ${model.id}`, { category: 'ModelRegistry' })
  }

  async updateModel(model: ModelInfo): Promise<void> {
    if (!this.models.has(model.id)) {
      throw new Error(`Model ${model.id} not found`)
    }

    this.models.set(model.id, model)
    logger.info(`Model updated: ${model.id}`, { category: 'ModelRegistry' })
  }

  async removeModel(id: string): Promise<void> {
    if (!this.models.delete(id)) {
      throw new Error(`Model ${id} not found`)
    }

    logger.info(`Model removed: ${id}`, { category: 'ModelRegistry' })
  }

  async getCompatibleModels(requirements: ModelCompatibility): Promise<ModelInfo[]> {
    await this.ensureInitialized()

    const models = Array.from(this.models.values())

    return models.filter(model => {
      // Check framework compatibility
      if (requirements.frameworks &&
          !requirements.frameworks.some(f => model.compatibleFrameworks.includes(f))) {
        return false
      }

      // Check hardware requirements
      if (requirements.minMemoryMB && model.memoryRequirements.minMemoryMB > requirements.minMemoryMB) {
        return false
      }

      if (requirements.requiresGPU && !model.memoryRequirements.requiresGPU) {
        return false
      }

      return true
    })
  }

  async refreshRegistry(): Promise<void> {
    if (this.isUpdating) return

    this.isUpdating = true

    try {
      logger.info('Refreshing model registry...', { category: 'ModelRegistry' })

      if (this.options.registryUrl) {
        await this.fetchRemoteModels()
      } else {
        await this.loadDefaultModels()
      }

      this.lastUpdate = new Date()
      logger.info(`Model registry refreshed. ${this.models.size} models available`, {
        category: 'ModelRegistry'
      })
    } catch (error) {
      logger.error('Failed to refresh model registry', error as Error, {
        category: 'ModelRegistry'
      })
    } finally {
      this.isUpdating = false
    }
  }

  isHealthy(): boolean {
    const age = Date.now() - this.lastUpdate.getTime()
    return age < this.updateInterval * 2 && this.models.size > 0
  }

  private async ensureInitialized(): Promise<void> {
    if (this.models.size === 0 && !this.isUpdating) {
      await this.refreshRegistry()
    }
  }

  private async fetchRemoteModels(): Promise<void> {
    if (!this.options.registryUrl) return

    const response = await fetch(this.options.registryUrl)
    if (!response.ok) {
      throw new Error(`Failed to fetch registry: ${response.status}`)
    }

    const data = await response.json() as { models: ModelInfo[] }

    for (const model of data.models) {
      this.models.set(model.id, model)
    }
  }

  private async loadDefaultModels(): Promise<void> {
    // Default models configuration
    const defaultModels: ModelInfo[] = [
      {
        id: 'whisper-tiny',
        name: 'Whisper Tiny',
        version: '1.0.0',
        framework: 'transformers.js',
        modality: 'voice-to-text',
        sizeBytes: 39 * 1024 * 1024, // 39MB
        compatibleFrameworks: ['transformers.js'],
        downloadUrls: [
          'https://huggingface.co/Xenova/whisper-tiny/resolve/main/onnx/decoder_model_merged.onnx'
        ],
        memoryRequirements: {
          minMemoryMB: 100,
          recommendedMemoryMB: 200,
          requiresGPU: false
        },
        languages: ['en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', 'zh'],
        checksum: 'sha256:...',
        metadata: {
          accuracy: 0.85,
          latency: 150,
          rtf: 0.1
        }
      },
      {
        id: 'whisper-base',
        name: 'Whisper Base',
        version: '1.0.0',
        framework: 'transformers.js',
        modality: 'voice-to-text',
        sizeBytes: 74 * 1024 * 1024, // 74MB
        compatibleFrameworks: ['transformers.js'],
        downloadUrls: [
          'https://huggingface.co/Xenova/whisper-base/resolve/main/onnx/decoder_model_merged.onnx'
        ],
        memoryRequirements: {
          minMemoryMB: 150,
          recommendedMemoryMB: 300,
          requiresGPU: false
        },
        languages: ['en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', 'zh'],
        checksum: 'sha256:...',
        metadata: {
          accuracy: 0.90,
          latency: 200,
          rtf: 0.15
        }
      }
    ]

    for (const model of defaultModels) {
      this.models.set(model.id, model)
    }
  }
}
```

#### ModelDownloader Implementation
**File**: `src/capabilities/model-management/services/download.ts`
```typescript
import { EventEmitter } from 'eventemitter3'

import { logger } from '../../../foundation/logging/logger'
import type { ModelInfo } from '../../../core/models/model-info'

export interface DownloadProgress {
  readonly modelId: string
  readonly bytesLoaded: number
  readonly bytesTotal: number
  readonly percentage: number
  readonly speed: number // bytes per second
  readonly estimatedTimeRemaining: number // seconds
}

export interface DownloadTask {
  readonly id: string
  readonly modelId: string
  readonly status: 'pending' | 'downloading' | 'completed' | 'failed' | 'cancelled'
  readonly progress?: DownloadProgress
  readonly error?: Error
  cancel(): void
}

export interface DownloadService {
  downloadModel(model: ModelInfo): Promise<string> // Returns local path
  downloadModelAsync(model: ModelInfo): DownloadTask
  resumeDownload(taskId: string): Promise<void>
  cancelDownload(taskId: string): void
  getActiveDownloads(): DownloadTask[]
  on(event: 'progress', listener: (progress: DownloadProgress) => void): this
  on(event: 'completed', listener: (modelId: string, path: string) => void): this
  on(event: 'failed', listener: (modelId: string, error: Error) => void): this
}

class WebDownloadTask implements DownloadTask {
  public status: DownloadTask['status'] = 'pending'
  public progress?: DownloadProgress
  public error?: Error

  private abortController = new AbortController()

  constructor(
    public readonly id: string,
    public readonly modelId: string
  ) {}

  cancel(): void {
    this.abortController.abort()
    this.status = 'cancelled'
  }

  get signal(): AbortSignal {
    return this.abortController.signal
  }
}

export class WebDownloadService extends EventEmitter implements DownloadService {
  private tasks = new Map<string, WebDownloadTask>()
  private concurrent = 0
  private readonly maxConcurrent = 3

  constructor(private options: {
    storageAdapter: StorageAdapter
    maxConcurrent?: number
    chunkSize?: number
  }) {
    super()
    this.maxConcurrent = options.maxConcurrent ?? 3
  }

  async downloadModel(model: ModelInfo): Promise<string> {
    const task = this.downloadModelAsync(model)

    return new Promise((resolve, reject) => {
      const onCompleted = (modelId: string, path: string) => {
        if (modelId === model.id) {
          this.off('completed', onCompleted)
          this.off('failed', onFailed)
          resolve(path)
        }
      }

      const onFailed = (modelId: string, error: Error) => {
        if (modelId === model.id) {
          this.off('completed', onCompleted)
          this.off('failed', onFailed)
          reject(error)
        }
      }

      this.on('completed', onCompleted)
      this.on('failed', onFailed)
    })
  }

  downloadModelAsync(model: ModelInfo): DownloadTask {
    const taskId = `${model.id}-${Date.now()}`
    const task = new WebDownloadTask(taskId, model.id)

    this.tasks.set(taskId, task)
    this.processQueue()

    return task
  }

  async resumeDownload(taskId: string): Promise<void> {
    const task = this.tasks.get(taskId)
    if (!task || task.status !== 'failed') {
      throw new Error(`Cannot resume task ${taskId}`)
    }

    task.status = 'pending'
    this.processQueue()
  }

  cancelDownload(taskId: string): void {
    const task = this.tasks.get(taskId)
    if (task) {
      task.cancel()
      this.tasks.delete(taskId)
    }
  }

  getActiveDownloads(): DownloadTask[] {
    return Array.from(this.tasks.values()).filter(
      task => task.status === 'downloading' || task.status === 'pending'
    )
  }

  private async processQueue(): Promise<void> {
    if (this.concurrent >= this.maxConcurrent) return

    const pendingTask = Array.from(this.tasks.values())
      .find(task => task.status === 'pending')

    if (!pendingTask) return

    this.concurrent++
    try {
      await this.executeDownload(pendingTask)
    } finally {
      this.concurrent--
      this.processQueue() // Process next task
    }
  }

  private async executeDownload(task: WebDownloadTask): Promise<void> {
    try {
      task.status = 'downloading'

      // Get model info from registry
      const model = await this.getModelInfo(task.modelId)
      if (!model) {
        throw new Error(`Model ${task.modelId} not found`)
      }

      // Try each download URL
      let lastError: Error | null = null

      for (const url of model.downloadUrls) {
        try {
          const path = await this.downloadFromUrl(url, model, task)

          task.status = 'completed'
          this.emit('completed', task.modelId, path)
          return
        } catch (error) {
          lastError = error as Error
          logger.warn(`Download failed from ${url}:`, error as Error, {
            category: 'DownloadService'
          })
        }
      }

      throw lastError ?? new Error('All download URLs failed')

    } catch (error) {
      task.status = 'failed'
      task.error = error as Error
      this.emit('failed', task.modelId, error as Error)
      logger.error(`Download failed for ${task.modelId}:`, error as Error, {
        category: 'DownloadService'
      })
    }
  }

  private async downloadFromUrl(
    url: string,
    model: ModelInfo,
    task: WebDownloadTask
  ): Promise<string> {
    const response = await fetch(url, {
      signal: task.signal
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }

    const totalBytes = parseInt(response.headers.get('content-length') ?? '0', 10)
    const reader = response.body?.getReader()

    if (!reader) {
      throw new Error('Response body is not readable')
    }

    const chunks: Uint8Array[] = []
    let loadedBytes = 0
    const startTime = Date.now()

    while (true) {
      const { done, value } = await reader.read()

      if (done) break
      if (task.signal.aborted) {
        throw new Error('Download cancelled')
      }

      chunks.push(value)
      loadedBytes += value.length

      // Update progress
      const elapsed = (Date.now() - startTime) / 1000
      const speed = loadedBytes / elapsed
      const estimatedTimeRemaining = totalBytes > 0
        ? (totalBytes - loadedBytes) / speed
        : 0

      task.progress = {
        modelId: model.id,
        bytesLoaded: loadedBytes,
        bytesTotal: totalBytes,
        percentage: totalBytes > 0 ? (loadedBytes / totalBytes) * 100 : 0,
        speed,
        estimatedTimeRemaining
      }

      this.emit('progress', task.progress)
    }

    // Combine chunks
    const fullData = new Uint8Array(loadedBytes)
    let offset = 0
    for (const chunk of chunks) {
      fullData.set(chunk, offset)
      offset += chunk.length
    }

    // Verify checksum if provided
    if (model.checksum) {
      await this.verifyChecksum(fullData, model.checksum)
    }

    // Store in persistent storage
    const path = await this.options.storageAdapter.store(model.id, fullData)

    logger.info(`Model downloaded successfully: ${model.id}`, {
      category: 'DownloadService',
      metadata: { size: loadedBytes, url }
    })

    return path
  }

  private async getModelInfo(modelId: string): Promise<ModelInfo | null> {
    // This would integrate with the ModelRegistry
    // For now, return null - implement based on your registry
    return null
  }

  private async verifyChecksum(data: Uint8Array, expectedChecksum: string): Promise<void> {
    const [algorithm, expected] = expectedChecksum.split(':')

    let hashBuffer: ArrayBuffer

    switch (algorithm.toLowerCase()) {
      case 'sha256':
        hashBuffer = await crypto.subtle.digest('SHA-256', data)
        break
      default:
        throw new Error(`Unsupported checksum algorithm: ${algorithm}`)
    }

    const hashArray = new Uint8Array(hashBuffer)
    const hashHex = Array.from(hashArray)
      .map(b => b.toString(16).padStart(2, '0'))
      .join('')

    if (hashHex !== expected) {
      throw new Error(`Checksum verification failed. Expected: ${expected}, got: ${hashHex}`)
    }
  }
}

// Storage adapter interface
export interface StorageAdapter {
  store(modelId: string, data: Uint8Array): Promise<string>
  retrieve(modelId: string): Promise<Uint8Array | null>
  delete(modelId: string): Promise<void>
  exists(modelId: string): Promise<boolean>
  getSize(modelId: string): Promise<number>
}
```

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
