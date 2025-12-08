# Capabilities Module - Complete File Analysis

**Analysis Date:** December 7, 2025
**SDK Version:** 0.15.8
**Total Files Analyzed:** 47

---

## Overview

The Capabilities module provides the core functionality of the RunAnywhere Swift SDK, organized into 8 subdirectories:

| Subdirectory | Files | Description |
|--------------|-------|-------------|
| Analytics/ | 4 | Analytics services for tracking usage and performance |
| DeviceCapability/ | 14 | Hardware detection, thermal monitoring, device profiling |
| ModelLoading/ | 2 | Model loading and management |
| Registry/ | 4 | Model discovery, registration, caching |
| Routing/ | 4 | Intelligent routing between on-device and cloud |
| StructuredOutput/ | 1 | JSON schema-based structured output generation |
| TextGeneration/ | 7 | Text generation, streaming, token management |
| Voice/ | 14 | Complete voice pipeline (VAD, STT, LLM, TTS) |

---

## Analytics/ (4 files)

### \`Analytics/Generation/GenerationAnalyticsService.swift\`

**Role / Responsibility**
- Tracks text generation events and performance metrics
- Monitors streaming updates, first token latency, and token throughput
- Collects model loading/unloading events
- Provides aggregated generation metrics for optimization

**Key Types**
- \`GenerationAnalyticsService\` (actor) – Thread-safe analytics service
- \`GenerationEvent\` (struct) – Analytics event for generation operations
- \`GenerationMetrics\` (struct) – Aggregated metrics (avg TTFT, tokens/sec)
- \`GenerationEventType\` (enum) – Event types: sessionStarted, generationStarted, firstTokenGenerated, etc.

**Key Public APIs**
- \`func track(event: GenerationEvent) async\` – Records generation event
- \`func startGeneration(generationId:modelId:executionTarget:) async -> String\` – Begin tracking
- \`func trackFirstToken(generationId:) async\` – Records time to first token
- \`func completeGeneration(generationId:inputTokens:outputTokens:) async\` – Records completion
- \`func getMetrics() async -> GenerationMetrics\` – Returns aggregated metrics

**Dependencies**
- Internal: AnalyticsQueueManager, SDKLogger, SessionMetadata
- External: Foundation

**Potential Issues / Smells**
- Active generation tracking could leak memory if generations never complete
- No limit on number of tracked events in memory

**Unused / Dead Code**
- \`processEvent(_ event: GenerationEvent)\` is empty placeholder

---

### \`Analytics/STT/STTAnalyticsService.swift\`

**Role / Responsibility**
- Tracks speech-to-text transcription events and performance
- Monitors transcription accuracy (confidence scores) and latency
- Provides both local analytics and enterprise telemetry integration

**Key Types**
- \`STTAnalyticsService\` (actor) – Thread-safe STT analytics
- \`STTEvent\` (struct) – STT-specific analytics event
- \`STTMetrics\` (struct) – Aggregated metrics (avg confidence, latency)
- \`STTEventType\` (enum) – transcriptionStarted, partialTranscript, finalTranscript, etc.

**Key Public APIs**
- \`func trackTranscription(text:confidence:duration:audioLength:speaker:) async\`
- \`func trackModelLoad(modelId:modelName:framework:loadTimeMs:) async\`
- \`func trackTranscriptionCompleted(sessionId:confidence:) async\`

**Potential Issues / Smells**
- Duplicate tracking between local analytics and enterprise telemetry
- Error handling logs errors but doesn't propagate (silent failures)

---

### \`Analytics/TTS/TTSAnalyticsService.swift\`

**Role / Responsibility**
- Tracks text-to-speech synthesis events and performance
- Monitors synthesis speed (characters per second) and audio quality
- Provides enterprise-grade telemetry for TTS operations

**Key Types**
- \`TTSAnalyticsService\` (actor) – Thread-safe TTS analytics
- \`TTSEvent\` (struct) – TTS-specific analytics event
- \`TTSMetrics\` (struct) – Aggregated metrics (avg processing time, chars/sec)

**Potential Issues / Smells**
- Heavy logging (info level) on every operation - should use debug level
- No batching of telemetry events

---

### \`Analytics/Voice/VoiceAnalyticsService.swift\`

**Role / Responsibility**
- Tracks complete voice pipeline execution and performance
- Monitors multi-stage voice processing (VAD → STT → LLM → TTS)
- Measures end-to-end latency and real-time factors

**Key Types**
- \`VoiceAnalyticsService\` (actor) – Voice pipeline analytics
- \`VoiceEvent\` (struct) – Voice pipeline event
- \`VoiceMetrics\` (struct) – Aggregated pipeline metrics

---

## DeviceCapability/ (14 files)

### \`DeviceCapability/Models/BatteryInfo.swift\`

**Key Types**
- \`BatteryInfo\` (struct) – Battery level, state, low power mode
- \`BatteryState\` (enum) – unknown, unplugged, charging, full

**Key Public APIs**
- \`var isLowBattery: Bool\` – True if level < 20%
- \`var isCriticalBattery: Bool\` – True if level < 10%

---

### \`DeviceCapability/Models/DeviceCapabilities.swift\`

**Key Types**
- \`DeviceCapabilities\` (struct) – Complete hardware profile
- \`MemoryPressureLevel\` (enum) – low, medium, high, warning, critical
- \`ProcessorType\` (enum) – A14-A18, M1-M4, Intel, ARM, unknown

**Key Public APIs**
- \`var memoryPressureLevel: MemoryPressureLevel\` – Based on available/total ratio
- \`func canRun(model: ModelInfo) -> Bool\` – Memory check

---

### \`DeviceCapability/Models/ProcessorInfo.swift\`

**Key Types**
- \`ProcessorInfo\` (struct) – Chip details with performance metrics
- \`ProcessorGeneration\` (enum) – gen1 through gen5
- \`PerformanceTier\` (enum) – flagship, high, medium, entry

**Key Public APIs**
- \`var performanceTier: PerformanceTier\` – Based on estimated TOPS
- \`var recommendedBatchSize: Int\` – Optimal batch size
- \`var supportsConcurrentInference: Bool\` – ≥4 P-cores and ≥16 NE cores

---

### \`DeviceCapability/Services/CapabilityAnalyzer.swift\`

**Role / Responsibility**
- Analyzes and aggregates hardware capabilities
- Provides optimal hardware configuration for models
- Selects appropriate accelerators and memory modes

**Key Public APIs**
- \`func analyzeCapabilities() -> DeviceCapabilities\`
- \`func getOptimalConfiguration(for model: ModelInfo) -> HardwareConfiguration\`

**Important Internal Logic**
- Accelerator selection: Neural Engine → GPU → framework-specific → Auto
- Memory mode: Conservative/Balanced/Aggressive based on available memory
- Thread count: Full/Half/75% based on model size

---

### \`DeviceCapability/Services/DeviceKitAdapter.swift\`

**Role / Responsibility**
- Bridges DeviceKit library to SDK types
- Provides accurate device model detection and chip identification
- Maps device identifiers to processor specs

**Key Types**
- \`DeviceKitAdapter\` (class) – DeviceKit integration
- \`OptimizationProfile\` (enum) – highPerformance, balanced, powerEfficient
- \`CPUType\` (enum) – a14Bionic through a18Pro, m1 through m4

**Potential Issues / Smells**
- **Large file** (545 lines) with embedded chip spec database
- Chip database requires manual updates for new devices
- macOS fallback detection by core count is unreliable

---

### \`DeviceCapability/Services/HardwareDetectionService.swift\`

**Key Types**
- \`HardwareCapabilityManager\` (class) – Singleton hardware manager with caching

**Key Public APIs**
- \`static let shared\` – Global singleton
- \`var capabilities: DeviceCapabilities\` – Cached (auto-refreshes after 60s)
- \`func checkResourceAvailability() -> ResourceAvailability\`

---

### \`DeviceCapability/Services/ThermalMonitorService.swift\`

**Key Types**
- \`ThermalMonitorService\` (actor) – Thermal monitoring
- \`ThermalState\` (enum) – nominal, fair, serious, critical

**Unused / Dead Code**
- **Entire observer system** - observers registered but never notified (broken feature)

---

## ModelLoading/ (2 files)

### \`ModelLoading/Services/ModelLoadingService.swift\`

**Role / Responsibility**
- Loads models by ID with adapter selection
- Prevents duplicate concurrent loads via task deduplication
- Tries primary adapter, then fallbacks if loading fails

**Key Public APIs**
- \`func loadModel(_ modelId: String) async throws -> LoadedModel\`
- \`func unloadModel(_ modelId: String) async throws\`
- \`func getLoadedModel(_ modelId: String) -> LoadedModel?\`

**Important Internal Logic**
- Deduplication via inflightLoads dictionary
- Multi-adapter fallback: tries all compatible adapters
- STT model rejection (must use STTComponent)

---

## Registry/ (4 files)

### \`Registry/Services/RegistryService.swift\`

**Role / Responsibility**
- Implements ModelRegistry protocol
- Manages model registration, filtering, and persistence
- Coordinates model discovery and configuration loading

**Key Public APIs**
- \`func initialize(with apiKey: String) async\`
- \`func discoverModels() async -> [ModelInfo]\`
- \`func registerModel(_ model: ModelInfo)\`
- \`func filterModels(by criteria: ModelCriteria) -> [ModelInfo]\`

---

### \`Registry/Storage/RegistryCache.swift\`

**Unused / Dead Code**
- **Entire class appears unused** - RegistryService has its own storage

---

### \`Registry/Storage/RegistryStorage.swift\`

**Unused / Dead Code**
- **Completely unimplemented** - all methods are stubs

---

## Routing/ (4 files)

### \`Routing/Services/RoutingService.swift\`

**Role / Responsibility**
- Makes intelligent routing decisions between on-device and cloud
- **Currently forces all executions on-device**

**Key Public APIs**
- \`func determineRouting(prompt:context:options:) async throws -> RoutingDecision\`

**Important Internal Logic**
- **FORCED LOCAL-ONLY**: All requests routed on-device with privacy reason
- Stubbed logic for privacy detection, complexity analysis, user preferences

**Unused / Dead Code**
- Most private methods never called due to forced local routing

---

## StructuredOutput/ (1 file)

### \`StructuredOutput/Services/StructuredOutputHandler.swift\`

**Role / Responsibility**
- Generates and validates structured JSON outputs from LLMs
- Provides schema-based prompts and parsing
- Extracts JSON from mixed-content responses

**Key Public APIs**
- \`func getSystemPrompt<T: Generatable>(for type: T.Type) -> String\`
- \`func parseStructuredOutput<T: Generatable>(from text: String, type: T.Type) throws -> T\`

---

## TextGeneration/ (7 files)

### \`TextGeneration/Services/GenerationService.swift\`

**Role / Responsibility**
- Main service for non-streaming text generation
- Routes requests between on-device, cloud, and hybrid execution
- Tracks performance metrics and analytics

**Key Public APIs**
- \`func generate(prompt:options:) async throws -> GenerationResult\`
- \`func setCurrentModel(_ model: LoadedModel?)\`

**Important Internal Logic**
- Generation flow: Get config → Resolve options → Prepare prompt → Route → Execute → Parse thinking → Calculate metrics
- On-device: Uses current model's service, parses thinking tags

**Unused / Dead Code**
- \`generateInCloud()\` and \`generateHybrid()\` are stubs

---

### \`TextGeneration/Services/StreamingService.swift\`

**Role / Responsibility**
- Provides streaming text generation with real-time token delivery
- Tracks comprehensive metrics (TTFT, tokens/sec)
- Supports streaming TTS integration

**Key Types**
- \`StreamingService\` (class) – Streaming generation
- \`TokenType\` (enum) – thinking, content
- \`StreamingToken\` (struct) – Individual token with metadata

**Key Public APIs**
- \`func generateStreamWithMetrics(prompt:options:) -> StreamingResult\`
- \`func generateTokenStream(prompt:options:) -> AsyncThrowingStream<StreamingToken, Error>\`

---

### \`TextGeneration/Services/TokenCounter.swift\`

**Role / Responsibility**
- Estimates token counts from text (heuristic-based)

**Important Internal Logic**
- Formula: characters/4 + punctuation*0.7 + newlines
- **Rough heuristic** - should use actual tokenizers

---

## Voice/ (14 files)

### \`Voice/AudioPipelineState.swift\`

**Key Types**
- \`AudioPipelineState\` (enum) – idle, listening, processingSpeech, generatingResponse, playingTTS, cooldown, error
- \`AudioPipelineStateManager\` (actor) – State machine with transition validation

**Important Internal Logic**
- Cooldown duration: 800ms (prevents feedback after TTS)
- Valid transition enforcement

---

### \`Voice/Handlers/LLMHandler.swift\`, \`STTHandler.swift\`, \`TTSHandler.swift\`, \`VADHandler.swift\`

Voice pipeline handlers for processing transcripts through LLM, handling STT, TTS, and VAD.

---

### \`Voice/Services/VoiceCapabilityService.swift\`

**Role / Responsibility**
- Main coordinator for voice processing capabilities
- Creates and manages voice agents (full voice pipelines)

**Key Public APIs**
- \`func createVoiceAgent(vadParams:sttParams:llmParams:ttsParams:) async throws -> VoiceAgentComponent\`
- \`func processVoice(audioStream:) -> AsyncThrowingStream<VoiceAgentEvent, Error>\`

---

### \`Voice/Strategies/VAD/SimpleEnergyVAD.swift\`

**Role / Responsibility**
- Energy-based Voice Activity Detection
- Real-time speech detection with calibration
- TTS feedback prevention

**Important Internal Logic**
- Energy calculation: RMS via vDSP_rmsqv
- Hysteresis: Voice start 1 frame, Voice end 12 frames
- TTS mode: Blocks processing during TTS playback
- Calibration: 90th percentile ambient, threshold = ambient * 2.0

---

## Summary

### Key Patterns
1. **Actor-based concurrency** for thread safety
2. **Service composition** with clear separation of concerns
3. **Event-driven architecture** via AsyncThrowingStream
4. **Dual analytics** (local + enterprise telemetry)
5. **Thinking content support** throughout

### Major Issues Identified
1. **Incomplete implementations**: RegistryStorage, ThermalMonitor observers, cloud routing
2. **Heavy heuristics**: Token counting, speaker embeddings, Neural Engine detection
3. **Hardcoded thresholds**: Battery levels, memory pressure, VAD energy
4. **Large files**: DeviceKitAdapter (545 lines), StreamingService (493 lines)

### Candidates for Removal
- \`RegistryCache\` class (not integrated)
- \`RegistryStorage\` class (stubbed)
- \`InferenceRequest\` struct (never used)
- \`ThermalMonitorService\` observer system (broken)

---
*This document is part of the RunAnywhere Swift SDK current-state documentation.*
