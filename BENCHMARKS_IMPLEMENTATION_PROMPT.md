# In-App Benchmarking — Implementation Prompt

You are implementing a **complete in-app benchmarking experience** for the RunAnywhere AI sample apps. Users tap a "Benchmarks" button on the Settings screen, navigate to a Benchmarks screen, run benchmarks across all AI components (LLM, STT, TTS, VLM, Diffusion), and export/share a detailed report.

> **Scope**: Both iOS and Android sections are fully detailed and ready for implementation.

---

## Table of Contents

1. [Cross-Platform Shared Spec](#1-cross-platform-shared-spec)
2. [iOS Implementation (Detailed)](#2-ios-implementation-detailed)
3. [Android Implementation (Detailed)](#3-android-implementation-detailed)
4. [Acceptance Criteria](#4-acceptance-criteria)
5. [Manual Test Plan](#5-manual-test-plan)

---

## 1. Cross-Platform Shared Spec

### 1.1 Data Model

Both platforms MUST use structurally equivalent types (same field names, same JSON keys).

```
BenchmarkCategory: enum
  - llm
  - stt
  - tts
  - vlm
  - diffusion

BenchmarkRunStatus: enum
  - running
  - completed
  - failed
  - cancelled

ComponentModelInfo:
  modelId: String              // e.g. "smollm2-360m-instruct-q8"
  modelName: String            // e.g. "SmolLM2-360M"
  framework: String            // e.g. "LlamaCpp", "ONNX"
  category: BenchmarkCategory
  formatOrQuantization: String? // e.g. "gguf", "onnx"; from ModelInfo.format.rawValue
  downloadSizeBytes: Int64?    // from ModelInfo.downloadSize

DeviceInfo:
  modelName: String            // e.g. "iPhone16,2"
  chipName: String             // e.g. "Apple Silicon"
  totalMemoryBytes: Int64
  availableMemoryBytes: Int64
  osVersion: String            // e.g. "18.2"
  appVersion: String           // e.g. "1.0.0"
  sdkVersion: String           // e.g. "0.1"

BenchmarkMetrics:
  loadTimeMs: Double?                // model load wall-clock
  warmupTimeMs: Double?              // first inference (JIT/cache priming)
  timeToFirstTokenMs: Double?        // LLM streaming: time to first token
  tokensPerSecond: Double?           // LLM/VLM: output tokens / total generation time
  endToEndLatencyMs: Double          // total wall-clock for one inference call
  inputTokens: Int?                  // LLM/VLM: prompt tokens
  outputTokens: Int?                 // LLM/VLM: completion tokens
  peakMemoryDeltaBytes: Int64?       // memory consumed during load (best-effort)
  sttTranscriptionTimeMs: Double?    // STT: from STTOutput.metadata.processingTime * 1000
  ttsSynthesisTimeMs: Double?        // TTS: from TTSOutput.metadata.processingTime * 1000
  vlmDescriptionTimeMs: Double?      // VLM: from VLMResult.totalTimeMs
  imageGenerationTimeMs: Double?     // Diffusion: from DiffusionResult.generationTimeMs
  error: String?                     // null on success; error message on failure

BenchmarkResult:
  id: String (UUID)
  timestamp: Date
  category: BenchmarkCategory
  scenarioName: String               // e.g. "Short generation"
  componentModelInfo: ComponentModelInfo
  deviceInfo: DeviceInfo
  metrics: BenchmarkMetrics

BenchmarkRun:
  id: String (UUID)
  startedAt: Date
  completedAt: Date?
  results: [BenchmarkResult]
  deviceInfo: DeviceInfo
  status: BenchmarkRunStatus
```

### 1.2 Metrics Per Component

| Component | Metrics to Capture | SDK Source |
|-----------|-------------------|------------|
| **LLM** | loadTimeMs, warmupTimeMs, timeToFirstTokenMs, tokensPerSecond, endToEndLatencyMs, inputTokens, outputTokens, peakMemoryDeltaBytes | `LLMGenerationResult.{tokensPerSecond, timeToFirstTokenMs, inputTokens, tokensUsed, latencyMs}` |
| **STT** | loadTimeMs, endToEndLatencyMs, sttTranscriptionTimeMs, peakMemoryDeltaBytes | `STTOutput.metadata.{processingTime, audioLength, realTimeFactor}` |
| **TTS** | loadTimeMs, endToEndLatencyMs, ttsSynthesisTimeMs, peakMemoryDeltaBytes | `TTSOutput.metadata.{processingTime, characterCount, charactersPerSecond}` |
| **VLM** | loadTimeMs, warmupTimeMs, endToEndLatencyMs, vlmDescriptionTimeMs, tokensPerSecond, inputTokens, outputTokens, peakMemoryDeltaBytes | `VLMResult.{totalTimeMs, tokensPerSecond, promptTokens, completionTokens}` |
| **Diffusion** | loadTimeMs, endToEndLatencyMs, imageGenerationTimeMs, peakMemoryDeltaBytes | `DiffusionResult.generationTimeMs` |

### 1.3 Benchmark Scenarios (Standard Suite)

Use deterministic, synthetic inputs so results are reproducible and require NO user interaction (no microphone, no camera).

```
LLM Scenarios:
  1. "Short generation"
     prompt: "What is 2+2? Answer briefly."
     maxTokens: 50, temperature: 0.0
  2. "Medium generation"
     prompt: "Explain how photosynthesis works in 3 paragraphs."
     maxTokens: 256, temperature: 0.0
  3. "Long generation"
     prompt: "Write a short story about a robot learning to paint."
     maxTokens: 512, temperature: 0.7

STT Scenarios:
  1. "Silent audio (2s)"
     input: 2 seconds of zeroed PCM buffer (16kHz mono Int16 = 64,000 bytes)
  2. "Synthetic tone (3s)"
     input: 3 seconds of a 440Hz sine wave, 16kHz mono Int16

TTS Scenarios:
  1. "Short text"
     text: "Hello, world."
  2. "Medium text"
     text: "The quick brown fox jumps over the lazy dog. This is a benchmark test for text to speech synthesis quality and speed."

VLM Scenarios:
  1. "Solid color image"
     input: Programmatically generated 224x224 red UIImage
     prompt: "Describe what you see in this image."
     maxTokens: 100, temperature: 0.0
  2. "Gradient image"
     input: Programmatically generated 224x224 gradient UIImage (red→blue)
     prompt: "What colors and patterns do you see?"
     maxTokens: 100, temperature: 0.0

Diffusion Scenarios:
  1. "Simple prompt (fast)"
     prompt: "A red circle on a white background"
     steps: 10, width: 512, height: 512, seed: 42, guidanceScale: 7.5
```

### 1.4 Report / Export Format

The report MUST include:
- Device info block at the top
- Per-result: component, model info (modelId, modelName, framework, quantization), scenario name, all applicable metrics
- Timestamp of the run

**Copy to Clipboard**: Plain-text summary (Markdown-formatted) suitable for pasting into a chat.

**JSON Export** (for sharing as a file):
```json
{
  "exportedAt": "2025-12-15T10:30:00Z",
  "device": { "modelName": "...", "chipName": "...", "totalMemoryBytes": 0, "osVersion": "...", "appVersion": "...", "sdkVersion": "..." },
  "run": {
    "id": "...",
    "startedAt": "...",
    "completedAt": "...",
    "status": "completed",
    "results": [
      {
        "id": "...",
        "category": "llm",
        "scenarioName": "Short generation",
        "componentModelInfo": { "modelId": "smollm2-360m-instruct-q8", "modelName": "SmolLM2-360M", "framework": "LlamaCpp", "formatOrQuantization": "gguf" },
        "metrics": { "loadTimeMs": 1234, "tokensPerSecond": 42.5, "endToEndLatencyMs": 2100, "inputTokens": 12, "outputTokens": 35 }
      }
    ]
  }
}
```

**CSV Export** (one row per result):
```
run_id,timestamp,category,scenario,model_id,model_name,framework,quantization,device,os,load_time_ms,warmup_ms,ttft_ms,tokens_per_sec,e2e_latency_ms,input_tokens,output_tokens,memory_delta_bytes,stt_time_ms,tts_time_ms,vlm_time_ms,diffusion_time_ms,error
```

### 1.5 Extensibility

The design MUST make it easy to add new components in the future:
- `BenchmarkCategory` enum: just add a new case
- `BenchmarkScenarioProvider` protocol: each component implements a provider that returns its scenarios
- `BenchmarkRunner` dispatches to the correct provider based on category
- Adding a new component = adding one new `BenchmarkScenarioProvider` conformance + one new enum case + one registration line

### 1.6 Storage

- Store runs as JSON file in app Documents directory: `benchmarks.json`
- Use `Codable` for serialization
- Keep last 50 runs max; auto-prune oldest on save
- Provide "Clear All Results" button

---

## 2. iOS Implementation (Detailed)

### 2.1 Project Location & File Structure

All new files go under the existing iOS example app:

```
examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Benchmarks/
├── Models/
│   ├── BenchmarkTypes.swift            // All enums, structs from section 1.1
│   └── BenchmarkStore.swift            // JSON persistence to Documents/benchmarks.json
├── ViewModels/
│   └── BenchmarkViewModel.swift        // @Observable, orchestrates everything
├── Views/
│   ├── BenchmarkDashboardView.swift    // Main screen: run buttons, past runs list
│   ├── BenchmarkDetailView.swift       // Single run detail with grouped results
│   └── BenchmarkProgressView.swift     // Live progress overlay during execution
├── Services/
│   ├── BenchmarkRunner.swift           // Orchestrator: iterates scenarios, measures, collects results
│   └── Providers/
│       ├── BenchmarkScenarioProvider.swift  // Protocol definition
│       ├── LLMBenchmarkProvider.swift       // LLM scenarios + execution
│       ├── STTBenchmarkProvider.swift       // STT scenarios + execution
│       ├── TTSBenchmarkProvider.swift       // TTS scenarios + execution
│       ├── VLMBenchmarkProvider.swift       // VLM scenarios + execution
│       └── DiffusionBenchmarkProvider.swift // Diffusion scenarios + execution
└── Utilities/
    ├── BenchmarkReportFormatter.swift  // Generates Markdown, JSON, CSV strings
    └── SyntheticInputGenerator.swift   // Generates silent audio, sine waves, solid-color images
```

**Total new files: 13**

### 2.2 Navigation Integration

#### iOS: `CombinedSettingsView.swift`

**File to modify**: `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/CombinedSettingsView.swift`

The Settings tab (tab 4) is wrapped in a `NavigationView` in `ContentView.swift:49`. The iOS form is `IOSSettingsContent` (a private struct). Add a `NavigationLink` inside the `Form`, as a **new Section** between the "Logging Configuration" section and the "About" section:

```swift
// In IOSSettingsContent body, inside the Form, add this Section
// AFTER "Logging Configuration" and BEFORE the "About" section:
Section("Performance") {
    NavigationLink {
        BenchmarkDashboardView()
    } label: {
        HStack {
            Image(systemName: "speedometer")
                .foregroundColor(AppColors.primaryAccent)
                .frame(width: 28)
            Text("Benchmarks")
            Spacer()
            Text("Measure AI performance")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}
```

**Why Settings → Benchmarks (not a new tab)**: iOS has a 5-tab limit. The app already has 5 tabs (Chat, Vision, Voice, More, Settings). A NavigationLink from Settings keeps navigation clean.

#### macOS: `MacOSSettingsContent`

Add a "Benchmarks" card between `LoggingConfigurationCard` and `AboutCard`:

```swift
// In MacOSSettingsContent body, add between LoggingConfigurationCard and AboutCard:
BenchmarksCard()
```

Where `BenchmarksCard` is a new private struct using the existing `SettingsCard` component:
```swift
private struct BenchmarksCard: View {
    @State private var showingBenchmarks = false

    var body: some View {
        SettingsCard(title: "Performance") {
            VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(AppColors.primaryAccent)
                    Text("Benchmarks")
                        .font(AppTypography.headline)
                }
                Text("Measure AI model performance across all components.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)

                Button("Open Benchmarks") { showingBenchmarks = true }
                    .buttonStyle(.bordered)
                    .tint(AppColors.primaryAccent)
            }
        }
        .sheet(isPresented: $showingBenchmarks) {
            BenchmarkDashboardView()
                .frame(minWidth: AppLayout.sheetMinWidth,
                       idealWidth: AppLayout.sheetIdealWidth,
                       minHeight: AppLayout.sheetMinHeight,
                       idealHeight: AppLayout.sheetIdealHeight)
        }
    }
}
```

### 2.3 BenchmarkTypes.swift — Complete Type Definitions

```swift
import Foundation

// MARK: - Enums

enum BenchmarkCategory: String, Codable, CaseIterable, Identifiable, Comparable {
    case llm, stt, tts, vlm, diffusion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .llm: "LLM"
        case .stt: "Speech-to-Text"
        case .tts: "Text-to-Speech"
        case .vlm: "Vision Language"
        case .diffusion: "Image Generation"
        }
    }

    var iconName: String {
        switch self {
        case .llm: "text.bubble"
        case .stt: "waveform"
        case .tts: "speaker.wave.2"
        case .vlm: "eye"
        case .diffusion: "photo.on.rectangle.angled"
        }
    }

    /// Maps to SDK's ModelCategory for filtering available models
    var modelCategory: ModelCategory {
        switch self {
        case .llm: .language
        case .stt: .speechRecognition
        case .tts: .speechSynthesis
        case .vlm: .multimodal
        case .diffusion: .imageGeneration
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum BenchmarkRunStatus: String, Codable {
    case running, completed, failed, cancelled
}

// MARK: - Data Structs (all Codable, Sendable)

struct ComponentModelInfo: Codable, Sendable {
    let modelId: String
    let modelName: String
    let framework: String
    let category: BenchmarkCategory
    let formatOrQuantization: String?
    let downloadSizeBytes: Int64?

    /// Create from SDK ModelInfo
    init(from modelInfo: ModelInfo, category: BenchmarkCategory) {
        self.modelId = modelInfo.id
        self.modelName = modelInfo.name
        self.framework = modelInfo.framework.displayName  // InferenceFramework.displayName
        self.category = category
        self.formatOrQuantization = modelInfo.format.rawValue  // ModelFormat.rawValue
        self.downloadSizeBytes = modelInfo.downloadSize
    }
}

struct BenchmarkDeviceInfo: Codable, Sendable {
    let modelName: String
    let chipName: String
    let totalMemoryBytes: Int64
    let availableMemoryBytes: Int64
    let osVersion: String
    let appVersion: String
    let sdkVersion: String

    /// Create using existing DeviceInfoService singleton
    static func fromSystem() -> BenchmarkDeviceInfo {
        let sysInfo = DeviceInfoService.shared.deviceInfo
        return BenchmarkDeviceInfo(
            modelName: sysInfo?.modelName ?? "Unknown",
            chipName: sysInfo?.chipName ?? "Unknown",
            totalMemoryBytes: sysInfo?.totalMemory ?? 0,
            availableMemoryBytes: Int64(os_proc_available_memory()),
            osVersion: sysInfo?.osVersion ?? "Unknown",
            appVersion: sysInfo?.appVersion ?? "Unknown",
            sdkVersion: "0.1"
        )
    }
}

struct BenchmarkMetrics: Codable, Sendable {
    var loadTimeMs: Double?
    var warmupTimeMs: Double?
    var timeToFirstTokenMs: Double?
    var tokensPerSecond: Double?
    var endToEndLatencyMs: Double
    var inputTokens: Int?
    var outputTokens: Int?
    var peakMemoryDeltaBytes: Int64?
    var sttTranscriptionTimeMs: Double?
    var ttsSynthesisTimeMs: Double?
    var vlmDescriptionTimeMs: Double?
    var imageGenerationTimeMs: Double?
    var error: String?

    /// Memberwise init with defaults for all optional fields.
    /// Allows `BenchmarkMetrics(endToEndLatencyMs: 0)` for error cases
    /// and `BenchmarkMetrics(loadTimeMs: 123, endToEndLatencyMs: 456, ...)` for success cases.
    init(
        loadTimeMs: Double? = nil,
        warmupTimeMs: Double? = nil,
        timeToFirstTokenMs: Double? = nil,
        tokensPerSecond: Double? = nil,
        endToEndLatencyMs: Double,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        peakMemoryDeltaBytes: Int64? = nil,
        sttTranscriptionTimeMs: Double? = nil,
        ttsSynthesisTimeMs: Double? = nil,
        vlmDescriptionTimeMs: Double? = nil,
        imageGenerationTimeMs: Double? = nil,
        error: String? = nil
    ) {
        self.loadTimeMs = loadTimeMs
        self.warmupTimeMs = warmupTimeMs
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.tokensPerSecond = tokensPerSecond
        self.endToEndLatencyMs = endToEndLatencyMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.peakMemoryDeltaBytes = peakMemoryDeltaBytes
        self.sttTranscriptionTimeMs = sttTranscriptionTimeMs
        self.ttsSynthesisTimeMs = ttsSynthesisTimeMs
        self.vlmDescriptionTimeMs = vlmDescriptionTimeMs
        self.imageGenerationTimeMs = imageGenerationTimeMs
        self.error = error
    }
}

struct BenchmarkResult: Codable, Sendable, Identifiable {
    let id: String  // UUID string
    let timestamp: Date
    let category: BenchmarkCategory
    let scenarioName: String
    let componentModelInfo: ComponentModelInfo
    let deviceInfo: BenchmarkDeviceInfo
    let metrics: BenchmarkMetrics
}

struct BenchmarkRun: Codable, Sendable, Identifiable {
    let id: String  // UUID string
    let startedAt: Date
    var completedAt: Date?
    var results: [BenchmarkResult]
    let deviceInfo: BenchmarkDeviceInfo
    var status: BenchmarkRunStatus
}
```

### 2.4 BenchmarkScenarioProvider Protocol

```swift
import RunAnywhere

/// Each component implements this to define its benchmark scenarios.
/// Adding a new component = adding one new conformance.
protocol BenchmarkScenarioProvider {
    var category: BenchmarkCategory { get }

    /// Return the list of scenario definitions (name + configuration)
    func scenarios() -> [BenchmarkScenario]

    /// Execute a single scenario against a specific model.
    /// The provider is responsible for:
    ///   1. Loading the model (and measuring load time)
    ///   2. Running the scenario (and measuring inference metrics)
    ///   3. Unloading the model after measurement
    ///   4. Returning a BenchmarkMetrics
    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo
    ) async throws -> BenchmarkMetrics
}

struct BenchmarkScenario: Sendable {
    let name: String
    let category: BenchmarkCategory
}
```

### 2.5 BenchmarkRunner.swift — Orchestration

```swift
import RunAnywhere

actor BenchmarkRunner {
    private let providers: [BenchmarkCategory: any BenchmarkScenarioProvider]

    init() {
        // Register all providers. Adding a new component = adding one line here.
        providers = [
            .llm: LLMBenchmarkProvider(),
            .stt: STTBenchmarkProvider(),
            .tts: TTSBenchmarkProvider(),
            .vlm: VLMBenchmarkProvider(),
            .diffusion: DiffusionBenchmarkProvider(),
        ]
    }

    /// Run benchmarks for selected categories across all downloaded models.
    /// Reports progress via the callback. Checks for cancellation via Task.isCancelled.
    func runBenchmarks(
        categories: Set<BenchmarkCategory>,
        onProgress: @Sendable (BenchmarkProgressUpdate) -> Void
    ) async throws -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        let deviceInfo = BenchmarkDeviceInfo.fromSystem()
        let allModels = try await RunAnywhere.availableModels()

        // Build work list: (category, model, scenario) triples
        var workItems: [(BenchmarkCategory, ModelInfo, BenchmarkScenario)] = []
        for category in categories.sorted() {
            guard let provider = providers[category] else { continue }
            let models = downloadedModels(for: category, from: allModels)
            if models.isEmpty { continue }
            for model in models {
                for scenario in provider.scenarios() {
                    workItems.append((category, model, scenario))
                }
            }
        }

        let totalItems = workItems.count
        guard totalItems > 0 else { return [] }

        for (index, (category, model, scenario)) in workItems.enumerated() {
            try Task.checkCancellation()

            onProgress(BenchmarkProgressUpdate(
                currentScenario: "\(category.displayName): \(scenario.name) (\(model.name))",
                progress: Double(index) / Double(totalItems),
                completedCount: index,
                totalCount: totalItems
            ))

            guard let provider = providers[category] else { continue }

            do {
                let metrics = try await provider.execute(
                    scenario: scenario,
                    model: model,
                    deviceInfo: deviceInfo
                )
                results.append(BenchmarkResult(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    category: category,
                    scenarioName: scenario.name,
                    componentModelInfo: ComponentModelInfo(from: model, category: category),
                    deviceInfo: deviceInfo,
                    metrics: metrics
                ))
            } catch {
                // Record error result, don't abort the entire run
                var errorMetrics = BenchmarkMetrics(endToEndLatencyMs: 0)
                errorMetrics.error = error.localizedDescription
                results.append(BenchmarkResult(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    category: category,
                    scenarioName: scenario.name,
                    componentModelInfo: ComponentModelInfo(from: model, category: category),
                    deviceInfo: deviceInfo,
                    metrics: errorMetrics
                ))
            }
        }

        return results
    }

    /// Map BenchmarkCategory → SDK ModelCategory for filtering downloaded models.
    /// Includes both user-downloaded models and built-in models (if any are present and ready).
    private func downloadedModels(for category: BenchmarkCategory, from allModels: [ModelInfo]) -> [ModelInfo] {
        allModels.filter { $0.category == category.modelCategory && $0.isDownloaded }
    }
}

struct BenchmarkProgressUpdate: Sendable {
    let currentScenario: String
    let progress: Double  // 0.0–1.0
    let completedCount: Int
    let totalCount: Int
}
```

### 2.6 Provider Implementations — Verified SDK Integration Points

Each provider calls the real SDK APIs. The method signatures below have been **verified against the actual SDK source code**.

#### 2.6.1 LLMBenchmarkProvider

**SDK APIs used** (`RunAnywhere+TextGeneration.swift`, `RunAnywhere+ModelManagement.swift`):
```swift
// Load:    RunAnywhere.loadModel(_ modelId: String) async throws
// Unload:  RunAnywhere.unloadModel() async throws
// Check:   RunAnywhere.isModelLoaded: Bool { get async }
// Generate: RunAnywhere.generate(_ prompt: String, options: LLMGenerationOptions?) async throws -> LLMGenerationResult
// Stream:   RunAnywhere.generateStream(_ prompt: String, options: LLMGenerationOptions?) async throws -> LLMStreamingResult
```

**LLMGenerationResult properties** (`LLMTypes.swift`):
- `.text: String`, `.inputTokens: Int`, `.tokensUsed: Int` (output tokens), `.responseTokens: Int`
- `.latencyMs: TimeInterval`, `.tokensPerSecond: Double`, `.timeToFirstTokenMs: Double?`
- `.modelUsed: String`, `.framework: String?`

**LLMGenerationOptions init** (`LLMTypes.swift`):
```swift
LLMGenerationOptions(
    maxTokens: Int = 100,
    temperature: Float = 0.8,
    topP: Float = 1.0,
    stopSequences: [String] = [],
    streamingEnabled: Bool = false,
    preferredFramework: InferenceFramework? = nil,
    structuredOutput: StructuredOutputConfig? = nil,
    systemPrompt: String? = nil
)
```

**LLMStreamingResult** (`LLMTypes.swift`):
- `.stream: AsyncThrowingStream<String, Error>` — iterate to get tokens
- `.result: Task<LLMGenerationResult, Error>` — `await .value` for final metrics

**Implementation sketch**:
```swift
struct LLMBenchmarkProvider: BenchmarkScenarioProvider {
    let category = BenchmarkCategory.llm

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Short generation", category: .llm),
            BenchmarkScenario(name: "Medium generation", category: .llm),
            BenchmarkScenario(name: "Long generation", category: .llm),
        ]
    }

    func execute(scenario: BenchmarkScenario, model: ModelInfo, deviceInfo: BenchmarkDeviceInfo) async throws -> BenchmarkMetrics {
        let (prompt, maxTokens, temp) = config(for: scenario.name)

        // 1. Measure load time
        let memBefore = Int64(os_proc_available_memory())
        let loadStart = CFAbsoluteTimeGetCurrent()
        try await RunAnywhere.loadModel(model.id)
        let loadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        let memAfter = Int64(os_proc_available_memory())
        let memDelta = memBefore - memAfter

        // 2. Warmup: one short non-streaming generation
        let warmupStart = CFAbsoluteTimeGetCurrent()
        _ = try await RunAnywhere.generate("Hi", options: LLMGenerationOptions(maxTokens: 5, temperature: 0))
        let warmupTimeMs = (CFAbsoluteTimeGetCurrent() - warmupStart) * 1000

        // 3. Streaming generation (captures TTFT + tok/s)
        let options = LLMGenerationOptions(maxTokens: maxTokens, temperature: temp, streamingEnabled: true)
        let genStart = CFAbsoluteTimeGetCurrent()
        let streamResult = try await RunAnywhere.generateStream(prompt, options: options)

        var firstTokenTime: Double?
        for try await _ in streamResult.stream {
            if firstTokenTime == nil {
                firstTokenTime = (CFAbsoluteTimeGetCurrent() - genStart) * 1000
            }
        }
        let totalTimeMs = (CFAbsoluteTimeGetCurrent() - genStart) * 1000
        let finalMetrics = try await streamResult.result.value

        // 4. Unload
        try await RunAnywhere.unloadModel()

        return BenchmarkMetrics(
            loadTimeMs: loadTimeMs,
            warmupTimeMs: warmupTimeMs,
            timeToFirstTokenMs: firstTokenTime ?? finalMetrics.timeToFirstTokenMs,
            tokensPerSecond: finalMetrics.tokensPerSecond,
            endToEndLatencyMs: totalTimeMs,
            inputTokens: finalMetrics.inputTokens,
            outputTokens: finalMetrics.tokensUsed,
            peakMemoryDeltaBytes: memDelta > 0 ? memDelta : nil
        )
    }

    private func config(for name: String) -> (prompt: String, maxTokens: Int, temperature: Float) {
        switch name {
        case "Short generation":
            ("What is 2+2? Answer briefly.", 50, 0.0)
        case "Medium generation":
            ("Explain how photosynthesis works in 3 paragraphs.", 256, 0.0)
        case "Long generation":
            ("Write a short story about a robot learning to paint.", 512, 0.7)
        default:
            ("Hello", 50, 0.0)
        }
    }
}
```

#### 2.6.2 STTBenchmarkProvider

**SDK APIs used** (`RunAnywhere+STT.swift`, `RunAnywhere+ModelManagement.swift`):
```swift
// Load:       RunAnywhere.loadSTTModel(_ modelId: String) async throws
// Unload:     RunAnywhere.unloadSTTModel() async throws
// Check:      RunAnywhere.isSTTModelLoaded: Bool { get async }
// Transcribe: RunAnywhere.transcribeWithOptions(_ audioData: Data, options: STTOptions) async throws -> STTOutput
//   (alternative: RunAnywhere.transcribe(_ audioData: Data) async throws -> String -- simpler but less metadata)
```

**STTOutput properties** (`STTTypes.swift`):
- `.text: String`, `.confidence: Float`
- `.metadata: TranscriptionMetadata` with:
  - `.processingTime: TimeInterval` (seconds)
  - `.audioLength: TimeInterval` (seconds)
  - `.realTimeFactor: Double` (processingTime / audioLength)
  - `.modelId: String`

**STTOptions init** (`STTTypes.swift`):
```swift
STTOptions(
    language: String = "en",
    detectLanguage: Bool = false,
    enablePunctuation: Bool = true,
    enableDiarization: Bool = false,
    maxSpeakers: Int? = nil,
    enableTimestamps: Bool = true,
    vocabularyFilter: [String] = [],
    audioFormat: AudioFormat = .pcm,
    sampleRate: Int = 16000,
    preferredFramework: InferenceFramework? = nil
)
```

**Synthetic audio generation**:
```swift
// Silent audio: 2 seconds of zeros, 16kHz mono Int16
let silentData = Data(count: 2 * 16000 * 2)  // 64,000 bytes

// Sine tone: 3 seconds of 440Hz, 16kHz mono Int16
func generateSineWave(durationSec: Double, frequency: Double, sampleRate: Int = 16000) -> Data {
    let sampleCount = Int(durationSec * Double(sampleRate))
    var data = Data(capacity: sampleCount * 2)
    for i in 0..<sampleCount {
        let t = Double(i) / Double(sampleRate)
        let sample = Int16(sin(2.0 * .pi * frequency * t) * Double(Int16.max / 2))
        withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}
```

**Implementation sketch**:
```swift
struct STTBenchmarkProvider: BenchmarkScenarioProvider {
    let category = BenchmarkCategory.stt

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Silent audio (2s)", category: .stt),
            BenchmarkScenario(name: "Synthetic tone (3s)", category: .stt),
        ]
    }

    func execute(scenario: BenchmarkScenario, model: ModelInfo, deviceInfo: BenchmarkDeviceInfo) async throws -> BenchmarkMetrics {
        let audioData: Data = switch scenario.name {
        case "Silent audio (2s)":
            SyntheticInputGenerator.silentAudio(durationSeconds: 2.0)
        default:
            SyntheticInputGenerator.sineWaveAudio(durationSeconds: 3.0, frequencyHz: 440.0)
        }

        // 1. Load model
        let memBefore = availableMemoryBytes()
        let loadStart = CFAbsoluteTimeGetCurrent()
        try await RunAnywhere.loadSTTModel(model.id)
        let loadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        let memDelta = memBefore - availableMemoryBytes()

        // 2. Transcribe with options to get metadata
        let e2eStart = CFAbsoluteTimeGetCurrent()
        let output = try await RunAnywhere.transcribeWithOptions(audioData, options: STTOptions())
        let e2eMs = (CFAbsoluteTimeGetCurrent() - e2eStart) * 1000

        // 3. Unload
        try await RunAnywhere.unloadSTTModel()

        return BenchmarkMetrics(
            loadTimeMs: loadTimeMs,
            endToEndLatencyMs: e2eMs,
            peakMemoryDeltaBytes: memDelta > 0 ? memDelta : nil,
            sttTranscriptionTimeMs: output.metadata.processingTime * 1000
        )
    }
}
```

#### 2.6.3 TTSBenchmarkProvider

**SDK APIs used** (`RunAnywhere+TTS.swift`, `RunAnywhere+ModelManagement.swift`):
```swift
// Load:       RunAnywhere.loadTTSModel(_ voiceId: String) async throws
//   (note: loadTTSModel uses voiceId, which is the model.id string)
// Unload:     RunAnywhere.unloadTTSVoice() async throws
// Check:      RunAnywhere.isTTSVoiceLoaded: Bool { get async }
// Synthesize: RunAnywhere.synthesize(_ text: String, options: TTSOptions) async throws -> TTSOutput
//   (NOT .speak() — speak() plays audio through speakers which adds overhead)
```

**TTSOutput properties** (`TTSTypes.swift`):
- `.audioData: Data`, `.format: AudioFormat`, `.duration: TimeInterval`
- `.metadata: TTSSynthesisMetadata` with:
  - `.processingTime: TimeInterval` (seconds)
  - `.characterCount: Int`
  - `.charactersPerSecond: Double` (computed: characterCount / processingTime)
  - `.voice: String`, `.language: String`

**TTSOptions init** (`TTSTypes.swift`):
```swift
TTSOptions(
    voice: String? = nil,
    language: String = "en-US",
    rate: Float = 1.0,
    pitch: Float = 1.0,
    volume: Float = 1.0,
    audioFormat: AudioFormat = .pcm,
    sampleRate: Int = 22050,
    useSSML: Bool = false
)
```

**Important**: Use `synthesize()` (not `speak()`) for benchmarks to avoid audio playback overhead. `synthesize` returns `TTSOutput` with raw audio data; `speak` returns `TTSSpeakResult` and plays through speakers.

**Implementation sketch**:
```swift
struct TTSBenchmarkProvider: BenchmarkScenarioProvider {
    let category = BenchmarkCategory.tts

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Short text", category: .tts),
            BenchmarkScenario(name: "Medium text", category: .tts),
        ]
    }

    func execute(scenario: BenchmarkScenario, model: ModelInfo, deviceInfo: BenchmarkDeviceInfo) async throws -> BenchmarkMetrics {
        let text: String = switch scenario.name {
        case "Short text":
            "Hello, world."
        default:
            "The quick brown fox jumps over the lazy dog. This is a benchmark test for text to speech synthesis quality and speed."
        }

        // 1. Load model (TTS uses "voice" terminology)
        let memBefore = availableMemoryBytes()
        let loadStart = CFAbsoluteTimeGetCurrent()
        try await RunAnywhere.loadTTSModel(model.id)
        let loadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        let memDelta = memBefore - availableMemoryBytes()

        // 2. Synthesize (NOT speak — avoids audio playback overhead)
        let e2eStart = CFAbsoluteTimeGetCurrent()
        let output = try await RunAnywhere.synthesize(text, options: TTSOptions())
        let e2eMs = (CFAbsoluteTimeGetCurrent() - e2eStart) * 1000

        // 3. Unload
        try await RunAnywhere.unloadTTSVoice()

        return BenchmarkMetrics(
            loadTimeMs: loadTimeMs,
            endToEndLatencyMs: e2eMs,
            peakMemoryDeltaBytes: memDelta > 0 ? memDelta : nil,
            ttsSynthesisTimeMs: output.metadata.processingTime * 1000
        )
    }
}
```

#### 2.6.4 VLMBenchmarkProvider

**SDK APIs used** (`RunAnywhere+VisionLanguage.swift`, `RunAnywhere+VLMModels.swift`):
```swift
// Load (from ModelInfo — handles path resolution internally):
//   RunAnywhere.loadVLMModel(_ model: ModelInfo) async throws
//   (this is in RunAnywhere+VLMModels.swift — it resolves modelPath + mmprojPath automatically)
//
// Low-level alternative (DO NOT USE — the ModelInfo overload is simpler):
//   RunAnywhere.loadVLMModel(_ modelPath: String, mmprojPath: String?, modelId: String, modelName: String)
//
// Unload:  RunAnywhere.unloadVLMModel() async
// Check:   RunAnywhere.isVLMModelLoaded: Bool { get async }
//
// Process (non-streaming):
//   RunAnywhere.processImage(_ image: VLMImage, prompt: String, maxTokens: Int32, temperature: Float) async throws -> VLMResult
//
// Process (streaming):
//   RunAnywhere.processImageStream(_ image: VLMImage, prompt: String, maxTokens: Int32, temperature: Float) async throws -> VLMStreamingResult
```

**IMPORTANT — VLM loading pattern**: Use `RunAnywhere.loadVLMModel(model)` passing the entire `ModelInfo` object. This is how `ModelSelectionSheet` does it. The SDK internally resolves `modelPath` and `mmprojPath` by scanning the model's local directory for `.gguf` files. Do NOT try to resolve paths manually.

**VLMResult properties** (`VLMTypes.swift`):
- `.text: String`, `.promptTokens: Int`, `.completionTokens: Int`
- `.totalTimeMs: Double`, `.tokensPerSecond: Double`

**VLMImage constructors** (`VLMTypes.swift`):
```swift
VLMImage(image: UIImage)        // from UIImage
VLMImage(filePath: String)      // from file path
VLMImage(rgbPixels: Data, width: Int, height: Int)  // from raw RGB data
VLMImage(pixelBuffer: CVPixelBuffer)  // from camera buffer
VLMImage(base64: String)        // from base64 encoded image
```

**For benchmarks**: Use `VLMImage(image: syntheticUIImage)` with programmatically generated UIImages.

**Implementation sketch**:
```swift
struct VLMBenchmarkProvider: BenchmarkScenarioProvider {
    let category = BenchmarkCategory.vlm

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Solid color image", category: .vlm),
            BenchmarkScenario(name: "Gradient image", category: .vlm),
        ]
    }

    func execute(scenario: BenchmarkScenario, model: ModelInfo, deviceInfo: BenchmarkDeviceInfo) async throws -> BenchmarkMetrics {
        let (image, prompt, maxTokens): (UIImage, String, Int32) = switch scenario.name {
        case "Solid color image":
            (SyntheticInputGenerator.solidColorImage(color: .red), "Describe what you see in this image.", 100)
        default:
            (SyntheticInputGenerator.gradientImage(from: .red, to: .blue), "What colors and patterns do you see?", 100)
        }

        // 1. Load model (pass full ModelInfo — SDK resolves paths)
        let memBefore = availableMemoryBytes()
        let loadStart = CFAbsoluteTimeGetCurrent()
        try await RunAnywhere.loadVLMModel(model)
        let loadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        let memDelta = memBefore - availableMemoryBytes()

        // 2. Warmup with a short prompt
        let warmupStart = CFAbsoluteTimeGetCurrent()
        _ = try await RunAnywhere.processImage(VLMImage(image: image), prompt: "Hi", maxTokens: 5, temperature: 0)
        let warmupTimeMs = (CFAbsoluteTimeGetCurrent() - warmupStart) * 1000

        // 3. Actual inference
        let result = try await RunAnywhere.processImage(VLMImage(image: image), prompt: prompt, maxTokens: maxTokens, temperature: 0)

        // 4. Unload
        await RunAnywhere.unloadVLMModel()

        return BenchmarkMetrics(
            loadTimeMs: loadTimeMs,
            warmupTimeMs: warmupTimeMs,
            tokensPerSecond: result.tokensPerSecond,
            endToEndLatencyMs: result.totalTimeMs,
            inputTokens: result.promptTokens,
            outputTokens: result.completionTokens,
            peakMemoryDeltaBytes: memDelta > 0 ? memDelta : nil,
            vlmDescriptionTimeMs: result.totalTimeMs
        )
    }
}
```

#### 2.6.5 DiffusionBenchmarkProvider

**SDK APIs used** (`RunAnywhere+Diffusion.swift`):
```swift
// Load:
//   RunAnywhere.loadDiffusionModel(modelPath: String, modelId: String, modelName: String, configuration: DiffusionConfiguration?) async throws
//   (requires model.localPath.path — the raw filesystem path)
//
// Unload:   RunAnywhere.unloadDiffusionModel() async throws
// Check:    RunAnywhere.isDiffusionModelLoaded: Bool { get async }
//
// Generate (non-streaming — simpler):
//   RunAnywhere.generateImage(prompt: String, options: DiffusionGenerationOptions?) async throws -> DiffusionResult
//
// Generate (streaming — with progress):
//   RunAnywhere.generateImageStream(prompt: String, options: DiffusionGenerationOptions?) async throws -> AsyncThrowingStream<DiffusionProgress, Error>
```

**IMPORTANT — Diffusion loading pattern**: Unlike VLM which has a `ModelInfo` overload, Diffusion requires explicit `modelPath` string. Follow `DiffusionViewModel` pattern:
```swift
guard let path = model.localPath else { throw ... }
let config = DiffusionConfiguration(modelVariant: .sd15, enableSafetyChecker: true, reduceMemory: true)
try await RunAnywhere.loadDiffusionModel(
    modelPath: path.path,       // model.localPath is URL?, .path gives String
    modelId: model.id,
    modelName: model.name,
    configuration: config
)
```

**DiffusionResult properties** (`DiffusionTypes.swift`):
- `.imageData: Data`, `.width: Int`, `.height: Int`
- `.seedUsed: Int64`, `.generationTimeMs: Int64`, `.safetyFlagged: Bool`

**DiffusionGenerationOptions convenience factory** (`DiffusionTypes.swift`):
```swift
DiffusionGenerationOptions.textToImage(
    prompt: "A red circle on a white background",
    width: 512,
    height: 512,
    steps: 10,
    guidanceScale: 7.5,
    seed: 42
)
```

**DiffusionConfiguration init** (`DiffusionTypes.swift`):
```swift
DiffusionConfiguration(
    modelId: String? = nil,
    modelVariant: DiffusionModelVariant = .sd15,
    enableSafetyChecker: Bool = true,
    reduceMemory: Bool = false,
    preferredFramework: InferenceFramework? = nil,
    tokenizerSource: DiffusionTokenizerSource? = nil
)
```

For benchmarks use `steps: 10` and `seed: 42` for reproducibility.

**Implementation sketch**:
```swift
struct DiffusionBenchmarkProvider: BenchmarkScenarioProvider {
    let category = BenchmarkCategory.diffusion

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Simple prompt (fast)", category: .diffusion),
        ]
    }

    func execute(scenario: BenchmarkScenario, model: ModelInfo, deviceInfo: BenchmarkDeviceInfo) async throws -> BenchmarkMetrics {
        guard let localPath = model.localPath else {
            throw NSError(domain: "Benchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not downloaded"])
        }

        // 1. Load model (requires explicit path string)
        let memBefore = availableMemoryBytes()
        let loadStart = CFAbsoluteTimeGetCurrent()
        let config = DiffusionConfiguration(modelVariant: .sd15, enableSafetyChecker: true, reduceMemory: true)
        try await RunAnywhere.loadDiffusionModel(
            modelPath: localPath.path,
            modelId: model.id,
            modelName: model.name,
            configuration: config
        )
        let loadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        let memDelta = memBefore - availableMemoryBytes()

        // 2. Generate image (non-streaming for simplicity)
        let genStart = CFAbsoluteTimeGetCurrent()
        let options = DiffusionGenerationOptions.textToImage(
            prompt: "A red circle on a white background",
            width: 512, height: 512, steps: 10, guidanceScale: 7.5, seed: 42
        )
        let result = try await RunAnywhere.generateImage(prompt: "A red circle on a white background", options: options)
        let genMs = (CFAbsoluteTimeGetCurrent() - genStart) * 1000

        // 3. Unload
        try await RunAnywhere.unloadDiffusionModel()

        return BenchmarkMetrics(
            loadTimeMs: loadTimeMs,
            endToEndLatencyMs: genMs,
            peakMemoryDeltaBytes: memDelta > 0 ? memDelta : nil,
            imageGenerationTimeMs: Double(result.generationTimeMs)
        )
    }
}
```

### 2.7 BenchmarkViewModel

```swift
import SwiftUI
import RunAnywhere

@MainActor
@Observable
final class BenchmarkViewModel {
    // MARK: - State

    private(set) var isRunning = false
    private(set) var currentScenario: String = ""
    private(set) var progress: Double = 0.0
    private(set) var completedCount: Int = 0
    private(set) var totalCount: Int = 0
    private(set) var currentRun: BenchmarkRun?
    private(set) var pastRuns: [BenchmarkRun] = []
    private(set) var errorMessage: String?
    var selectedCategories: Set<BenchmarkCategory> = Set(BenchmarkCategory.allCases)

    // MARK: - Dependencies

    private let store = BenchmarkStore()
    private let runner = BenchmarkRunner()
    private let reportFormatter = BenchmarkReportFormatter()
    private var runTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        pastRuns = store.loadRuns()
    }

    // MARK: - Actions

    func runAll() {
        run(categories: Set(BenchmarkCategory.allCases))
    }

    func runSelected() {
        run(categories: selectedCategories)
    }

    func runCategory(_ category: BenchmarkCategory) {
        run(categories: [category])
    }

    func cancel() {
        runTask?.cancel()
    }

    func clearAllResults() {
        store.clearAll()
        pastRuns = []
    }

    // MARK: - Export

    func copyReportToClipboard(run: BenchmarkRun) {
        let markdown = reportFormatter.formatMarkdown(run: run)
        #if os(iOS)
        UIPasteboard.general.string = markdown
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif
    }

    func exportJSON(run: BenchmarkRun) -> URL {
        reportFormatter.writeJSON(run: run)
    }

    func exportCSV(run: BenchmarkRun) -> URL {
        reportFormatter.writeCSV(run: run)
    }

    func saveToDocuments(run: BenchmarkRun, format: BenchmarkReportFormatter.ExportFormat) -> URL {
        reportFormatter.saveToDocuments(run: run, format: format)
    }

    // MARK: - Private

    private func run(categories: Set<BenchmarkCategory>) {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        let deviceInfo = BenchmarkDeviceInfo.fromSystem()
        var run = BenchmarkRun(
            id: UUID().uuidString,
            startedAt: Date(),
            results: [],
            deviceInfo: deviceInfo,
            status: .running
        )
        currentRun = run

        runTask = Task {
            do {
                let results = try await runner.runBenchmarks(
                    categories: categories,
                    onProgress: { [weak self] update in
                        Task { @MainActor in
                            self?.currentScenario = update.currentScenario
                            self?.progress = update.progress
                            self?.completedCount = update.completedCount
                            self?.totalCount = update.totalCount
                        }
                    }
                )
                run.results = results
                run.completedAt = Date()
                run.status = .completed
            } catch is CancellationError {
                run.completedAt = Date()
                run.status = .cancelled
            } catch {
                run.completedAt = Date()
                run.status = .failed
                errorMessage = error.localizedDescription
            }

            currentRun = run
            store.save(run: run)
            pastRuns = store.loadRuns()
            isRunning = false
        }
    }
}
```

### 2.8 BenchmarkStore.swift — Persistence

```swift
/// Thread-safe because all operations are synchronous file I/O
/// and the class holds no mutable shared state beyond the file URL.
/// Used from @MainActor (ViewModel) only — do NOT call from BenchmarkRunner actor.
final class BenchmarkStore: Sendable {
    private let fileURL: URL
    private let maxRuns = 50

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("benchmarks.json")
    }

    func loadRuns() -> [BenchmarkRun] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BenchmarkRun].self, from: data)) ?? []
    }

    func save(run: BenchmarkRun) {
        var runs = loadRuns()
        runs.insert(run, at: 0)
        if runs.count > maxRuns { runs = Array(runs.prefix(maxRuns)) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(runs) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

### 2.9 UI Views

#### 2.9.1 BenchmarkDashboardView

Main screen accessible from Settings:

- **Header**: Device info card (model, chip, RAM) using `DeviceInfoService.shared`
- **Run Controls**:
  - "Run All Benchmarks" primary button (disabled while running)
  - Category filter: horizontal `ScrollView` of toggle chips for each `BenchmarkCategory`, using `BenchmarkCategory.allCases`. Each chip shows the category's `iconName` + `displayName`, tinted `AppColors.primaryAccent` when selected, `AppColors.textSecondary` when deselected. Tapping toggles the category in `viewModel.selectedCategories`.
  ```swift
  ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: AppSpacing.smallMedium) {
          ForEach(BenchmarkCategory.allCases) { category in
              let isSelected = viewModel.selectedCategories.contains(category)
              Button {
                  if isSelected { viewModel.selectedCategories.remove(category) }
                  else { viewModel.selectedCategories.insert(category) }
              } label: {
                  Label(category.displayName, systemImage: category.iconName)
                      .font(AppTypography.caption)
                      .padding(.horizontal, AppSpacing.smallMedium)
                      .padding(.vertical, AppSpacing.small)
                      .background(isSelected ? AppColors.primaryAccent.opacity(0.15) : AppColors.backgroundSecondary)
                      .foregroundColor(isSelected ? AppColors.primaryAccent : AppColors.textSecondary)
                      .cornerRadius(AppSpacing.cornerRadiusRegular)
              }
          }
      }
      .padding(.horizontal, AppSpacing.medium)
  }
  ```
  - "Run Selected" secondary button (runs only checked categories)
- **Progress overlay** (when `isRunning`): `BenchmarkProgressView` as a sheet or overlay
  - Current scenario label
  - `ProgressView(value: progress)` linear bar
  - Completed count / total count
  - Cancel button
- **Past Runs list**: `List` of past `BenchmarkRun` entries as cards showing:
  - Date, duration, result count, status badge (completed/cancelled/failed)
  - Tapping navigates to `BenchmarkDetailView`
- **Toolbar**: "Clear All" button (with confirmation alert)

Design tokens to use:
- Buttons: `AppColors.primaryAccent` tint, `AppSpacing.cornerRadiusRegular`
- Cards: `AppColors.backgroundSecondary` background, `AppSpacing.cornerRadiusLarge`
- Status badges: `AppColors.statusGreen` (completed), `AppColors.statusOrange` (cancelled), `AppColors.statusRed` (failed)

#### 2.9.2 BenchmarkDetailView

Shows a single `BenchmarkRun` in detail:

- **Run metadata card**: Start/end time, duration, status, device info
- **Results grouped by category**: `Section` per `BenchmarkCategory`, each containing result rows
- **Each result row shows**:
  - Scenario name + model name/ID
  - Framework badge (use `AppColors.frameworkBadgeColor(framework:)`)
  - Key metrics displayed as labeled values:
    - LLM: Load time, TTFT, tok/s, E2E latency, tokens (in/out)
    - STT: Load time, transcription time, real-time factor
    - TTS: Load time, synthesis time, chars/sec
    - VLM: Load time, description time, tok/s
    - Diffusion: Load time, generation time
  - Memory delta if available
  - Error message (red, `AppColors.primaryRed`) if failed
- **Toolbar actions**:
  - "Copy Report" button → copies Markdown to clipboard with haptic feedback
  - "Share" button → `ShareLink` with JSON/CSV picker via `Menu`
  - "Save to Files" → writes to Documents and shows confirmation

#### 2.9.3 BenchmarkProgressView

Sheet/overlay shown during benchmark execution:

```swift
VStack(spacing: AppSpacing.large) {
    Text("Running Benchmarks")
        .font(AppTypography.headline)
    ProgressView(value: viewModel.progress)
        .progressViewStyle(.linear)
        .tint(AppColors.primaryAccent)
    Text(viewModel.currentScenario)
        .font(AppTypography.caption)
        .foregroundColor(AppColors.textSecondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    Text("\(viewModel.completedCount) / \(viewModel.totalCount)")
        .font(AppTypography.monospaced)
        .foregroundColor(AppColors.textSecondary)
    Button("Cancel") { viewModel.cancel() }
        .buttonStyle(.bordered)
        .tint(AppColors.primaryRed)
}
.padding(AppSpacing.xxLarge)
```

### 2.10 BenchmarkReportFormatter.swift

Generates three output formats from a `BenchmarkRun`:

1. **Markdown** (for clipboard): Human-readable summary with tables
2. **JSON** (for file export): Full structured data matching schema in section 1.4
3. **CSV** (for file export): Flat table, one row per result

```swift
struct BenchmarkReportFormatter {
    // MARK: - Markdown (for clipboard copy)

    func formatMarkdown(run: BenchmarkRun) -> String {
        var lines: [String] = []
        lines.append("# Benchmark Report")
        lines.append("")
        lines.append("**Date**: \(run.startedAt.formatted())")
        lines.append("**Status**: \(run.status.rawValue)")
        if let completed = run.completedAt {
            let duration = completed.timeIntervalSince(run.startedAt)
            lines.append("**Duration**: \(String(format: "%.1f", duration))s")
        }
        lines.append("")
        lines.append("## Device")
        lines.append("- Model: \(run.deviceInfo.modelName)")
        lines.append("- Chip: \(run.deviceInfo.chipName)")
        lines.append("- RAM: \(run.deviceInfo.totalMemoryBytes / 1_073_741_824) GB")
        lines.append("- OS: \(run.deviceInfo.osVersion)")
        lines.append("- App: \(run.deviceInfo.appVersion), SDK: \(run.deviceInfo.sdkVersion)")
        lines.append("")

        // Group results by category
        let grouped = Dictionary(grouping: run.results, by: \.category)
        for category in BenchmarkCategory.allCases {
            guard let results = grouped[category], !results.isEmpty else { continue }
            lines.append("## \(category.displayName)")
            lines.append("")
            for result in results {
                lines.append("### \(result.scenarioName) — \(result.componentModelInfo.modelName)")
                lines.append("- Framework: \(result.componentModelInfo.framework)")
                if let q = result.componentModelInfo.formatOrQuantization { lines.append("- Format: \(q)") }
                let m = result.metrics
                if let v = m.loadTimeMs { lines.append("- Load: \(String(format: "%.0f", v)) ms") }
                if let v = m.warmupTimeMs { lines.append("- Warmup: \(String(format: "%.0f", v)) ms") }
                if let v = m.timeToFirstTokenMs { lines.append("- TTFT: \(String(format: "%.0f", v)) ms") }
                if let v = m.tokensPerSecond { lines.append("- Tokens/sec: \(String(format: "%.1f", v))") }
                lines.append("- E2E Latency: \(String(format: "%.0f", m.endToEndLatencyMs)) ms")
                if let v = m.inputTokens { lines.append("- Input tokens: \(v)") }
                if let v = m.outputTokens { lines.append("- Output tokens: \(v)") }
                if let v = m.sttTranscriptionTimeMs { lines.append("- Transcription: \(String(format: "%.0f", v)) ms") }
                if let v = m.ttsSynthesisTimeMs { lines.append("- Synthesis: \(String(format: "%.0f", v)) ms") }
                if let v = m.vlmDescriptionTimeMs { lines.append("- VLM time: \(String(format: "%.0f", v)) ms") }
                if let v = m.imageGenerationTimeMs { lines.append("- Generation: \(String(format: "%.0f", v)) ms") }
                if let v = m.peakMemoryDeltaBytes { lines.append("- Memory delta: \(v / 1_048_576) MB") }
                if let e = m.error { lines.append("- **ERROR**: \(e)") }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON (for file export)

    func writeJSON(run: BenchmarkRun) -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(run)) ?? Data()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark_\(run.id).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - CSV (for file export)

    func writeCSV(run: BenchmarkRun) -> URL {
        let header = "run_id,timestamp,category,scenario,model_id,model_name,framework,quantization,device,os,load_time_ms,warmup_ms,ttft_ms,tokens_per_sec,e2e_latency_ms,input_tokens,output_tokens,memory_delta_bytes,stt_time_ms,tts_time_ms,vlm_time_ms,diffusion_time_ms,error"
        var rows = [header]
        let df = ISO8601DateFormatter()
        for r in run.results {
            let m = r.metrics
            let row = [
                run.id, df.string(from: r.timestamp), r.category.rawValue, r.scenarioName,
                r.componentModelInfo.modelId, r.componentModelInfo.modelName,
                r.componentModelInfo.framework, r.componentModelInfo.formatOrQuantization ?? "",
                run.deviceInfo.modelName, run.deviceInfo.osVersion,
                m.loadTimeMs.map { String(format: "%.1f", $0) } ?? "",
                m.warmupTimeMs.map { String(format: "%.1f", $0) } ?? "",
                m.timeToFirstTokenMs.map { String(format: "%.1f", $0) } ?? "",
                m.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "",
                String(format: "%.1f", m.endToEndLatencyMs),
                m.inputTokens.map(String.init) ?? "",
                m.outputTokens.map(String.init) ?? "",
                m.peakMemoryDeltaBytes.map(String.init) ?? "",
                m.sttTranscriptionTimeMs.map { String(format: "%.1f", $0) } ?? "",
                m.ttsSynthesisTimeMs.map { String(format: "%.1f", $0) } ?? "",
                m.vlmDescriptionTimeMs.map { String(format: "%.1f", $0) } ?? "",
                m.imageGenerationTimeMs.map { String(format: "%.1f", $0) } ?? "",
                m.error ?? "",
            ].map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ",")
            rows.append(row)
        }
        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark_\(run.id).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Save to Documents (for on-device storage)

    func saveToDocuments(run: BenchmarkRun, format: ExportFormat) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ext = format == .json ? "json" : "csv"
        let filename = "benchmark_\(run.id).\(ext)"
        let destURL = docs.appendingPathComponent(filename)
        let sourceURL = format == .json ? writeJSON(run: run) : writeCSV(run: run)
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    enum ExportFormat { case json, csv }
}
```

### 2.10.1 Export & Share UX in BenchmarkDetailView

The detail view toolbar provides three export actions:

```swift
// In BenchmarkDetailView toolbar:
ToolbarItem(placement: .primaryAction) {
    Menu {
        Button {
            viewModel.copyReportToClipboard(run: run)
            showCopiedConfirmation = true  // triggers a brief "Copied!" toast
        } label: {
            Label("Copy Markdown Report", systemImage: "doc.on.clipboard")
        }

        Divider()

        ShareLink("Share JSON", item: viewModel.exportJSON(run: run))
        ShareLink("Share CSV", item: viewModel.exportCSV(run: run))

        Divider()

        Button {
            let saved = viewModel.saveToDocuments(run: run, format: .json)
            savedFileURL = saved
            showSavedConfirmation = true  // triggers alert: "Saved to \(saved.lastPathComponent)"
        } label: {
            Label("Save JSON to Files", systemImage: "square.and.arrow.down")
        }

        Button {
            let saved = viewModel.saveToDocuments(run: run, format: .csv)
            savedFileURL = saved
            showSavedConfirmation = true
        } label: {
            Label("Save CSV to Files", systemImage: "square.and.arrow.down")
        }
    } label: {
        Image(systemName: "square.and.arrow.up")
    }
}
```

**Haptic feedback**: On iOS, trigger `UINotificationFeedbackGenerator().notificationOccurred(.success)` after "Copy" and "Save" actions.

**Confirmation UI**: Use a temporary overlay or `.alert` modifier:
```swift
.overlay(alignment: .bottom) {
    if showCopiedConfirmation {
        Text("Copied to clipboard")
            .font(AppTypography.caption)
            .padding(AppSpacing.smallMedium)
            .background(AppColors.backgroundTertiary)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showCopiedConfirmation = false }
                }
            }
    }
}
```

### 2.11 SyntheticInputGenerator.swift

Utility to generate test inputs without requiring hardware (microphone/camera):

```swift
import UIKit

enum SyntheticInputGenerator {
    // MARK: - Audio

    /// 16kHz mono Int16 PCM silence
    static func silentAudio(durationSeconds: Double) -> Data {
        let sampleCount = Int(durationSeconds * 16000)
        return Data(count: sampleCount * 2)  // 2 bytes per Int16 sample
    }

    /// 16kHz mono Int16 PCM sine wave
    static func sineWaveAudio(durationSeconds: Double, frequencyHz: Double = 440.0) -> Data {
        let sampleRate = 16000
        let sampleCount = Int(durationSeconds * Double(sampleRate))
        var data = Data(capacity: sampleCount * 2)
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            let sample = Int16(sin(2.0 * .pi * frequencyHz * t) * Double(Int16.max / 2))
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    // MARK: - Images

    /// Solid-color UIImage using UIGraphicsImageRenderer
    static func solidColorImage(color: UIColor, width: Int = 224, height: Int = 224) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Linear gradient UIImage (top-to-bottom) using UIGraphicsImageRenderer
    static func gradientImage(from startColor: UIColor, to endColor: UIColor, width: Int = 224, height: Int = 224) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            let colors = [startColor.cgColor, endColor.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil) else { return }
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: size.width / 2, y: 0),
                end: CGPoint(x: size.width / 2, y: size.height),
                options: []
            )
        }
    }
}
```

### 2.12 Memory Measurement

Place this helper function in `SyntheticInputGenerator.swift` (or at file scope in any Benchmarks utility file):

```swift
import Darwin

/// Returns the current available memory in bytes. Used by all providers
/// to compute peak memory delta around model load operations.
func availableMemoryBytes() -> Int64 {
    Int64(os_proc_available_memory())
}

// Usage pattern in each provider:
let memBefore = availableMemoryBytes()
// ... load model ...
let memAfter = availableMemoryBytes()
let peakMemoryDelta = memBefore - memAfter  // positive = memory consumed
```

### 2.13 Model Requirements & Pre-flight Check

Before running benchmarks for a category, the runner checks which models are downloaded:
```swift
let allModels = try await RunAnywhere.availableModels()
let downloadedLLMs = allModels.filter { $0.category == .language && $0.isDownloaded && !$0.isBuiltIn }
```

The UI shows which categories have models available. Categories with no downloaded models show a "No models available — download from Settings" message and are skipped during execution (not an error).

### 2.14 Design System Compliance

Use the existing design tokens throughout:
- Colors: `AppColors.primaryAccent` (orange `#FF5500`), `AppColors.textSecondary`, `AppColors.statusGreen`, `AppColors.statusOrange`, `AppColors.statusRed`, `AppColors.primaryRed`, `AppColors.backgroundSecondary`, `AppColors.backgroundTertiary`, `AppColors.frameworkBadgeColor(framework:)`
- Typography: `AppTypography.headline`, `AppTypography.caption`, `AppTypography.monospaced`, `AppTypography.subheadlineMedium`, `AppTypography.caption2`, `AppTypography.body`, `AppTypography.largeTitleBold`
- Spacing: `AppSpacing.large` (16), `AppSpacing.medium` (10), `AppSpacing.smallMedium` (8), `AppSpacing.xLarge` (20), `AppSpacing.xxLarge` (30), `AppSpacing.cornerRadiusRegular` (8), `AppSpacing.cornerRadiusLarge` (10), `AppSpacing.cornerRadiusCard` (16)
- Reference: `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/DesignSystem/`

---

## 3. Android Implementation (Outline / TBD)

> **Status:** This branch (`ios_bench`) is intentionally **iOS-first**. The Android section is kept as an outline so iOS work can land independently.
>
> Implement Android in a dedicated follow-up branch (see `android_bench`) with a full Compose UI + persistence + export/share implementation plan.

### 3.1 Target UX (Android)

- Settings screen has a **Benchmarks** row.
- Tapping navigates to a **Benchmarks** screen.
- Benchmarks cover **LLM / STT / TTS** (and are extensible for future components).
- Each benchmark run uses **synthetic prompts / synthetic inputs** and records:
  - Component category
  - **Model info** (id/name/format/quantization/size when available)
  - Timings/metrics (load, warmup, E2E, TTFT/tokens/sec for streaming where available)
- User can:
  - Run per-component benchmarks or “Run all”
  - Cancel a run
  - View past runs
  - Export a report: **copy to clipboard**, **save to file**, and **share**

### 3.2 Android Hook Points (to fill in on android_bench)

- `examples/android/RunAnywhereAI/app/src/main/java/.../presentation/settings/SettingsScreen.kt`
- `.../presentation/navigation/AppNavigation.kt`
- `.../presentation/chat/ChatViewModel.kt` (LLM patterns)
- `.../presentation/stt/SpeechToTextViewModel.kt` (STT patterns)
- `.../presentation/tts/TextToSpeechViewModel.kt` (TTS patterns)

### 3.3 Export Strategy (Android outline)

- Clipboard: `ClipboardManager`
- Save: Storage Access Framework (create document) or MediaStore (Downloads)
- Share: `ACTION_SEND` intent for JSON/CSV/text

## 4. Acceptance Criteria

### Functional

- [ ] **AC-1**: Settings screen has a "Benchmarks" navigation item that opens the Benchmarks dashboard
- [ ] **AC-2**: "Run All" executes benchmark scenarios for ALL downloaded models across ALL categories
- [ ] **AC-3**: "Run Selected" runs only the categories the user has toggled on
- [ ] **AC-4**: Real-time progress UI shows current scenario name, progress bar, and completed/total count
- [ ] **AC-5**: Cancel stops the benchmark run and saves partial results with status "cancelled"
- [ ] **AC-6**: Completed runs appear in a scrollable history list, most recent first
- [ ] **AC-7**: Tapping a run shows detailed per-scenario results grouped by category
- [ ] **AC-8**: Each result shows component + model info (modelId, modelName, framework, quantization)
- [ ] **AC-9**: Each result shows per-metric timings (load time, TTFT, tok/s, E2E latency, etc.)
- [ ] **AC-10**: "Copy Report" copies a Markdown-formatted summary to clipboard
- [ ] **AC-11**: "Share" opens share sheet with JSON or CSV file
- [ ] **AC-12**: JSON export matches the schema in section 1.4
- [ ] **AC-13**: CSV export has correct headers matching section 1.4
- [ ] **AC-14**: "Save to Files" writes JSON or CSV to Documents directory and shows confirmation with filename
- [ ] **AC-15**: "Clear All" removes all stored benchmark data (with confirmation)
- [ ] **AC-16**: Results persist across app restarts (stored in Documents/benchmarks.json)
- [ ] **AC-17**: LLM benchmarks capture: load time, warmup, TTFT, tok/s, E2E latency, input/output tokens, memory delta
- [ ] **AC-18**: STT benchmarks capture: load time, transcription time (from `STTOutput.metadata.processingTime`), memory delta
- [ ] **AC-19**: TTS benchmarks capture: load time, synthesis time (from `TTSOutput.metadata.processingTime`), memory delta
- [ ] **AC-20**: VLM benchmarks capture: load time, description time (from `VLMResult.totalTimeMs`), tok/s, memory delta (iOS only)
- [ ] **AC-21**: Diffusion benchmarks capture: load time, generation time (from `DiffusionResult.generationTimeMs`), memory delta (iOS only)
- [ ] **AC-22**: Device info captured in every run (model, chip, memory, OS, app version, SDK version)
- [ ] **AC-23**: Categories with no downloaded models show a warning message, not a crash
- [ ] **AC-24**: Benchmarks work with any downloaded model — model list is dynamic
- [ ] **AC-25**: App remains responsive during benchmark execution (heavy work on background threads/actors)
- [ ] **AC-26**: No new external dependencies — only SDK APIs and platform frameworks

### Non-Functional

- [ ] **AC-27**: Uses `@Observable` (not `ObservableObject`) for the ViewModel
- [ ] **AC-28**: All types are `Codable` and `Sendable`
- [ ] **AC-29**: Strong typing everywhere — no raw strings for categories, statuses, or metrics keys
- [ ] **AC-30**: Follows existing design system (AppColors, AppTypography, AppSpacing)
- [ ] **AC-31**: Only files created are in `Features/Benchmarks/` plus minimal wiring in `CombinedSettingsView.swift`
- [ ] **AC-32**: Adding a new benchmark component requires only: (a) new enum case, (b) new provider file, (c) one registration line in `BenchmarkRunner.init()`

---

## 5. Manual Test Plan

### 5.1 Prerequisites

1. Open `examples/ios/RunAnywhereAI/` in Xcode
2. Select iPhone 16 Pro Simulator (iOS 17+)
3. Build and run (`Cmd+R`)
4. Go to Settings, download at least **SmolLM2-360M** (smallest LLM, model ID `smollm2-360m-instruct-q8`)
5. Optionally download: Whisper Tiny (STT), Piper TTS US English (TTS), SmolVLM 500M (VLM), a diffusion model

### 5.2 Test Cases

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| T1 | Navigate to Benchmarks | Settings tab → tap "Benchmarks" | Dashboard visible with device info, empty run list |
| T2 | No models warning | Ensure no models downloaded → tap "Run All" | Shows "No models downloaded" message or skips all categories gracefully |
| T3 | Run All (LLM only) | Download SmolLM2 → Run All | Progress UI appears, shows each LLM scenario. On completion, run appears in history. |
| T4 | Cancel mid-run | Start Run All → wait 1 scenario → Cancel | Run stops. Partial results saved with status "cancelled". |
| T5 | View run detail | Tap a completed run | Detail view shows results grouped by category with all metrics. Model info (name, framework) shown. |
| T6 | Run single category | Toggle only "LLM" → "Run Selected" | Only LLM scenarios execute |
| T7 | Copy report | Complete a run → "Copy Report" | Clipboard contains Markdown text with device info and metrics |
| T8 | Export JSON | Complete a run → Share → JSON | Share sheet with .json file. File is valid JSON matching schema. |
| T9 | Export CSV | Complete a run → Share → CSV | Share sheet with .csv file. CSV has correct headers and data. |
| T10 | Persistence | Complete a run → force-quit → reopen → Benchmarks | Previous runs still visible |
| T11 | Clear All | "Clear All" → confirm | History empty |
| T12 | Multiple models | Download SmolLM2 + Qwen 0.5B → Run All | Both models benchmarked in same run |
| T13 | STT benchmark | Download Whisper → Run Category: STT | STT scenarios with synthetic audio execute, transcription time captured |
| T14 | TTS benchmark | Download Piper → Run Category: TTS | TTS scenarios execute, synthesis time captured |
| T15 | VLM benchmark | Download SmolVLM → Run Category: VLM | VLM scenario runs with synthetic test image |
| T16 | Diffusion benchmark | Download SD model → Run Category: Diffusion | Generation benchmark runs (may take minutes) |
| T17 | Memory delta | View any completed result detail | Memory delta field shows a value |
| T18 | App responsiveness | During benchmark, switch to Chat tab and back | App stays responsive, benchmark continues |
| T19 | Error handling | Delete model files on disk → run benchmark | Error recorded for that model, other models still run |
| T20 | Report contains model info | View/copy any report | Report includes modelId, modelName, framework, quantization for each result |
| T21 | Save to Files | Complete a run → Menu → "Save JSON to Files" | File saved to Documents. Confirmation shows filename. File readable via Files app. |
| T22 | Haptic feedback | Copy report or save to files on physical device | Haptic success feedback fires on copy/save |

### 5.3 Validation Checks

1. Tokens/sec in benchmark results should be within 20% of values shown in Chat analytics
2. Memory delta values are positive and in a reasonable range (10MB–4GB)
3. JSON field names match between iOS export and the schema in section 1.4
4. No crashes when all categories are empty (no models downloaded)
5. Benchmark runs complete even if one model fails (error is captured, run continues)

---

## Appendix A: Key iOS File References

| File | Purpose | Path |
|------|---------|------|
| Tab navigation | 5-tab TabView | `examples/ios/RunAnywhereAI/RunAnywhereAI/App/ContentView.swift` |
| Settings (iOS) | Form with sections | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/CombinedSettingsView.swift` |
| Settings VM | Settings logic | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/SettingsViewModel.swift` |
| Device info | System info | `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/DeviceInfoService.swift` |
| App types | SystemDeviceInfo | `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Models/AppTypes.swift` |
| Design system | Colors, spacing, typography | `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/DesignSystem/` |
| LLM generation | generate/generateStream | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+TextGeneration.swift` |
| LLM types | LLMGenerationResult, Options | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/LLMTypes.swift` |
| STT API | transcribe/transcribeWithOptions | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/STT/RunAnywhere+STT.swift` |
| STT types | STTOutput, TranscriptionMetadata | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/STT/STTTypes.swift` |
| TTS API | synthesize/speak | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/RunAnywhere+TTS.swift` |
| TTS types | TTSOutput, TTSSynthesisMetadata | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/TTSTypes.swift` |
| VLM API (low-level) | processImage/loadVLMModel | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/RunAnywhere+VisionLanguage.swift` |
| VLM API (ModelInfo load) | loadVLMModel(ModelInfo) | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/RunAnywhere+VLMModels.swift` |
| VLM types | VLMImage, VLMResult | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/VLMTypes.swift` |
| Diffusion API | generateImage/loadDiffusionModel | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Diffusion/RunAnywhere+Diffusion.swift` |
| Diffusion types | DiffusionResult, Options | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Diffusion/DiffusionTypes.swift` |
| Model mgmt | loadModel, loadSTTModel, etc | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+ModelManagement.swift` |
| Model types | ModelInfo, ModelCategory | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift` |
| Model list VM | Download/load lifecycle | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelListViewModel.swift` |
| Model selection | Context-based loading | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/ModelSelectionSheet.swift` |
| LLM ViewModel | Chat generation reference | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ViewModels/LLMViewModel.swift` |
| VLM ViewModel | VLM loading reference | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Vision/VLMViewModel.swift` |
| Diffusion VM | Diffusion loading reference | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Diffusion/DiffusionViewModel.swift` |
| STT ViewModel | STT usage reference | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/STTViewModel.swift` |
| TTS ViewModel | TTS usage reference | `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/TTSViewModel.swift` |

### SDK Imports

```swift
import RunAnywhere  // Core: RunAnywhere.initialize(), .generate(), .generateStream(), .loadModel(), etc.
```

---

## Appendix B: Critical SDK API Differences Summary

| Component | Load Method | Load Argument | Unload Method |
|-----------|-------------|---------------|---------------|
| LLM | `RunAnywhere.loadModel(_:)` | `model.id` (String) | `RunAnywhere.unloadModel()` |
| STT | `RunAnywhere.loadSTTModel(_:)` | `model.id` (String) | `RunAnywhere.unloadSTTModel()` |
| TTS | `RunAnywhere.loadTTSModel(_:)` | `model.id` (String) | `RunAnywhere.unloadTTSVoice()` |
| VLM | `RunAnywhere.loadVLMModel(_:)` | `model` (ModelInfo object) | `RunAnywhere.unloadVLMModel()` |
| Diffusion | `RunAnywhere.loadDiffusionModel(modelPath:modelId:modelName:configuration:)` | `model.localPath!.path` + `model.id` + `model.name` + config | `RunAnywhere.unloadDiffusionModel()` |

**Key differences**:
- LLM/STT/TTS: Simple — pass `model.id` string
- VLM: Pass the entire `ModelInfo` object (SDK resolves paths internally)
- Diffusion: Pass explicit filesystem path string + model metadata + configuration

## Appendix C: Verified Design Token Values

| Token | Value |
|-------|-------|
| `AppColors.primaryAccent` | `#FF5500` (orange) |
| `AppColors.primaryRed` | `#EF4444` |
| `AppColors.statusGreen` | green |
| `AppColors.statusOrange` | orange |
| `AppColors.statusRed` | red |
| `AppSpacing.large` | 16 |
| `AppSpacing.xxLarge` | 30 |
| `AppSpacing.cornerRadiusRegular` | 8 |
| `AppSpacing.cornerRadiusLarge` | 10 |
| `AppSpacing.cornerRadiusCard` | 16 |
| `AppTypography.monospaced` | body, monospaced design |
| `AppTypography.headline` | .headline weight |
| `AppTypography.caption` | .caption weight |
