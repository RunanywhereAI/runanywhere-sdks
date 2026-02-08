# In-App Benchmarking — Implementation Prompt

You are implementing a **complete in-app benchmarking experience** for the RunAnywhere AI sample apps. Users tap a "Benchmarks" button on the Settings screen, navigate to a Benchmarks screen, run benchmarks across AI components, and export/share a detailed report.

- **iOS**: LLM, STT, TTS, VLM, and Diffusion benchmarks (5 providers)
- **Android**: LLM, STT, and TTS benchmarks (3 providers now; VLM/Diffusion extensible for future)

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
- Use `Codable` (iOS) / `kotlinx.serialization` with `@Serializable` (Android) for serialization
- Keep last 50 runs max; auto-prune oldest on save
- Provide "Clear All Results" button

### 1.7 Timestamp Serialization — Cross-Platform Consistency

The JSON **export** format (section 1.4) uses ISO8601 strings for dates (`"2025-12-15T10:30:00Z"`). Each platform handles this differently:

- **iOS**: Uses `Date` type with `JSONEncoder.dateEncodingStrategy = .iso8601` → automatic ISO8601 strings in JSON
- **Android**: Uses `Long` (epoch millis) internally for `kotlinx.serialization` simplicity. The **JSON export** (`writeJSON`) must wrap the `BenchmarkRun` with a custom serializer or manual conversion to produce ISO8601 strings for `startedAt`, `completedAt`, and `timestamp` fields. The **internal persistence** (`BenchmarkStore`) can use raw `Long` values since it's only read by the same app.

Both platforms serialize the `BenchmarkRun` object directly (not the wrapper structure shown in 1.4). The exported JSON will contain all the same fields — device info, results array, metrics — just at the top level of the run object rather than nested under a `"run"` key.

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

## 3. Android Implementation (Detailed)

### 3.1 Project Location & File Structure

All new files go under the existing Android example app:

```
examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/
├── domain/models/
│   └── BenchmarkModels.kt                   // All enums, data classes from section 1.1 (kotlinx.serialization)
├── data/
│   └── BenchmarkStore.kt                    // JSON persistence to filesDir/benchmarks.json
└── presentation/benchmarks/
    ├── BenchmarkViewModel.kt                // ViewModel, orchestrates everything
    ├── BenchmarkDashboardScreen.kt          // Main screen: run buttons, past runs list
    ├── BenchmarkDetailScreen.kt             // Single run detail with grouped results
    ├── BenchmarkProgressOverlay.kt          // Live progress overlay during execution
    ├── BenchmarkRunner.kt                   // Orchestrator: iterates scenarios, measures, collects results
    ├── BenchmarkReportFormatter.kt          // Generates Markdown, JSON, CSV strings
    ├── SyntheticInputGenerator.kt           // Generates silent audio, sine waves
    └── providers/
        ├── BenchmarkScenarioProvider.kt     // Interface definition
        ├── LLMBenchmarkProvider.kt          // LLM scenarios + execution
        ├── STTBenchmarkProvider.kt          // STT scenarios + execution
        └── TTSBenchmarkProvider.kt          // TTS scenarios + execution
```

**Total new files: 12** (plus 1 new XML resource: `res/xml/file_paths.xml`)
**Files to modify: 5** (`gradle/libs.versions.toml`, `app/build.gradle.kts`, `AndroidManifest.xml`, `AppNavigation.kt`, `SettingsScreen.kt`)

### 3.2 Navigation Integration

#### 3.2.1 Adding the Route

**File to modify**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/navigation/AppNavigation.kt`

Add two new route constants to the `NavigationRoute` object (currently at lines 172-178) and two composable destinations:

```kotlin
// In NavigationRoute object (lines 172-178), add 2 new constants:
object NavigationRoute {
    const val CHAT = "chat"
    const val STT = "stt"
    const val TTS = "tts"
    const val VOICE = "voice"
    const val SETTINGS = "settings"
    const val BENCHMARKS = "benchmarks"          // NEW
    const val BENCHMARK_DETAIL = "benchmark/{runId}"  // NEW
}
```

Add composable destinations inside the `NavHost` block (after the `SETTINGS` composable):

```kotlin
composable(NavigationRoute.BENCHMARKS) {
    BenchmarkDashboardScreen(
        onNavigateToDetail = { runId ->
            navController.navigate("benchmark/$runId")
        },
        onNavigateBack = { navController.popBackStack() }
    )
}

composable(
    route = NavigationRoute.BENCHMARK_DETAIL,
    arguments = listOf(navArgument("runId") { type = NavType.StringType })
) { backStackEntry ->
    val runId = backStackEntry.arguments?.getString("runId") ?: return@composable
    BenchmarkDetailScreen(
        runId = runId,
        onNavigateBack = { navController.popBackStack() }
    )
}
```

**Why nested navigation from Settings (not a new tab)**: Android has 5 bottom tabs (Chat, STT, TTS, Voice, Settings) matching iOS. Adding a 6th tab would break parity. A navigation from Settings keeps it clean.

#### 3.2.2 Adding the Settings Entry Point

**File to modify**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/settings/SettingsScreen.kt`

The `SettingsScreen` composable currently accepts only a `SettingsViewModel`. We need to add an `onNavigateToBenchmarks` callback parameter and insert a new "Performance" section between the "Storage Management" section and the "About" section.

**Step 1**: Change the `SettingsScreen` signature to accept a navigation callback:

```kotlin
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel(),
    onNavigateToBenchmarks: () -> Unit = {},  // NEW
)
```

**Step 2**: Wire the callback from `AppNavigation.kt` (currently at line 66-68, which reads `composable(NavigationRoute.SETTINGS) { SettingsScreen() }`):

```kotlin
// Replace the existing SettingsScreen() call (AppNavigation.kt line 66-68):
composable(NavigationRoute.SETTINGS) {
    SettingsScreen(
        onNavigateToBenchmarks = {
            navController.navigate(NavigationRoute.BENCHMARKS)
        }
    )
}
```

**Step 3**: Insert a new "Performance" section in `SettingsScreen` body, between "Storage Management" and "About":

```kotlin
// NEW: Performance Section (between Storage Management and About)
SettingsSection(title = "Performance") {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onNavigateToBenchmarks),
        shape = RoundedCornerShape(8.dp),
        color = AppColors.primaryAccent.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Outlined.Speed,
                contentDescription = null,
                tint = AppColors.primaryAccent,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Benchmarks",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    text = "Measure AI model performance",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = "Open benchmarks",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}
```

**Important**: `SettingsSection` is declared as a `private` composable within `SettingsScreen.kt` (lines 335–372). Since you are adding code inside the same file's body, you can use it directly. If you prefer to extract benchmarks into a separate file, you'll need to either make `SettingsSection` `internal` or duplicate the pattern.

This inserts at **line 196** of `SettingsScreen.kt` (after the "Storage Management" `SettingsSection` closing brace at line 195 and before the "About" `SettingsSection` at line 198). The exact insertion point is between:
```kotlin
        }  // end Storage Management SettingsSection (line 195)

        // INSERT NEW "Performance" SECTION HERE

        // About Section  (line 198)
        SettingsSection(title = "About") {
```

### 3.3 BenchmarkModels.kt — Complete Type Definitions

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/domain/models/BenchmarkModels.kt`

```kotlin
package com.runanywhere.runanywhereai.domain.models

import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.serialization.Serializable

// MARK: - Enums

@Serializable
enum class BenchmarkCategory(val displayName: String, val iconName: String) {
    LLM("LLM", "text_bubble"),
    STT("Speech-to-Text", "waveform"),
    TTS("Text-to-Speech", "speaker_wave"),
    VLM("Vision Language", "eye"),
    DIFFUSION("Image Generation", "photo");

    /** Maps to SDK's ModelCategory for filtering available models */
    val modelCategory: ModelCategory
        get() = when (this) {
            LLM -> ModelCategory.LANGUAGE
            STT -> ModelCategory.SPEECH_RECOGNITION
            TTS -> ModelCategory.SPEECH_SYNTHESIS
            VLM -> ModelCategory.MULTIMODAL
            DIFFUSION -> ModelCategory.IMAGE_GENERATION
        }
}

@Serializable
enum class BenchmarkRunStatus {
    RUNNING, COMPLETED, FAILED, CANCELLED
}

// MARK: - Data Classes (all @Serializable)

@Serializable
data class ComponentModelInfo(
    val modelId: String,
    val modelName: String,
    val framework: String,
    val category: BenchmarkCategory,
    val formatOrQuantization: String? = null,
    val downloadSizeBytes: Long? = null,
) {
    companion object {
        /** Create from SDK ModelInfo */
        fun from(modelInfo: ModelInfo, category: BenchmarkCategory) = ComponentModelInfo(
            modelId = modelInfo.id,
            modelName = modelInfo.name,
            framework = modelInfo.framework.rawValue,
            category = category,
            formatOrQuantization = modelInfo.format.value,
            downloadSizeBytes = modelInfo.downloadSize,
        )
    }
}

@Serializable
data class BenchmarkDeviceInfo(
    val modelName: String,
    val chipName: String,
    val totalMemoryBytes: Long,
    val availableMemoryBytes: Long,
    val osVersion: String,
    val appVersion: String,
    val sdkVersion: String,
) {
    companion object {
        /** Create using Android system APIs */
        fun fromSystem(context: android.content.Context): BenchmarkDeviceInfo {
            val activityManager = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
            val memInfo = android.app.ActivityManager.MemoryInfo()
            activityManager?.getMemoryInfo(memInfo)

            return BenchmarkDeviceInfo(
                modelName = android.os.Build.MODEL,
                chipName = android.os.Build.HARDWARE,
                totalMemoryBytes = memInfo.totalMem,
                availableMemoryBytes = memInfo.availMem,
                osVersion = "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})",
                appVersion = try {
                    if (android.os.Build.VERSION.SDK_INT >= 33) {
                        context.packageManager.getPackageInfo(
                            context.packageName,
                            android.content.pm.PackageManager.PackageInfoFlags.of(0)
                        ).versionName ?: "Unknown"
                    } else {
                        @Suppress("DEPRECATION")
                        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "Unknown"
                    }
                } catch (_: Exception) { "Unknown" },
                sdkVersion = RunAnywhere.version,  // Delegates to SDKConstants.VERSION = "0.1.0"
            )
        }
    }
}

@Serializable
data class BenchmarkMetrics(
    val loadTimeMs: Double? = null,
    val warmupTimeMs: Double? = null,
    val timeToFirstTokenMs: Double? = null,
    val tokensPerSecond: Double? = null,
    val endToEndLatencyMs: Double,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    val peakMemoryDeltaBytes: Long? = null,
    val sttTranscriptionTimeMs: Double? = null,
    val ttsSynthesisTimeMs: Double? = null,
    val vlmDescriptionTimeMs: Double? = null,
    val imageGenerationTimeMs: Double? = null,
    val error: String? = null,
)

@Serializable
data class BenchmarkResult(
    val id: String,
    val timestamp: Long,  // epoch millis (kotlinx.serialization-friendly)
    val category: BenchmarkCategory,
    val scenarioName: String,
    val componentModelInfo: ComponentModelInfo,
    val deviceInfo: BenchmarkDeviceInfo,
    val metrics: BenchmarkMetrics,
)

@Serializable
data class BenchmarkRun(
    val id: String,
    val startedAt: Long,  // epoch millis
    val completedAt: Long? = null,
    val results: List<BenchmarkResult> = emptyList(),
    val deviceInfo: BenchmarkDeviceInfo,
    val status: BenchmarkRunStatus,
)
// Note: All fields are `val` — use `.copy()` to produce updated instances (the ViewModel
// already follows this pattern). This is idiomatic Kotlin for immutable data classes.
```

**Key differences from iOS types**:
- Uses `Long` (epoch millis) instead of `Date` for timestamps — simpler for `kotlinx.serialization`
- `BenchmarkDeviceInfo.fromSystem(context)` requires Android `Context` (uses `Build.MODEL`, `Build.HARDWARE`, `ActivityManager`)
- Uses `sdkVersion = RunAnywhere.version` (the SDK exposes this as a property)
- `ComponentModelInfo.from()` uses `modelInfo.framework.rawValue` (the `InferenceFramework` enum's string representation)
- `modelInfo.format.value` maps to the `ModelFormat` enum's string value

### 3.4 BenchmarkScenarioProvider Interface

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/providers/BenchmarkScenarioProvider.kt`

```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks.providers

import com.runanywhere.runanywhereai.domain.models.BenchmarkCategory
import com.runanywhere.runanywhereai.domain.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.domain.models.BenchmarkMetrics
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

/**
 * Each component implements this to define its benchmark scenarios.
 * Adding a new component = adding one new implementation.
 */
interface BenchmarkScenarioProvider {
    val category: BenchmarkCategory

    /** Return the list of scenario definitions (name + category) */
    fun scenarios(): List<BenchmarkScenario>

    /**
     * Execute a single scenario against a specific model.
     * The provider is responsible for:
     *   1. Loading the model (and measuring load time)
     *   2. Running the scenario (and measuring inference metrics)
     *   3. Unloading the model after measurement
     *   4. Returning a BenchmarkMetrics
     */
    suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics
}

data class BenchmarkScenario(
    val name: String,
    val category: BenchmarkCategory,
)
```

### 3.5 Verified Android SDK API Signatures

All method signatures below are verified against the actual KMP SDK source code at `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/`.

#### 3.5.1 Model Management APIs

**Source**: `RunAnywhere+ModelManagement.kt`

```kotlin
// Discovery
suspend fun RunAnywhere.availableModels(): List<ModelInfo>
suspend fun RunAnywhere.downloadedModels(): List<ModelInfo>
suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo>

// LLM Loading
suspend fun RunAnywhere.loadLLMModel(modelId: String)
suspend fun RunAnywhere.unloadLLMModel()
suspend fun RunAnywhere.isLLMModelLoaded(): Boolean
val RunAnywhere.currentLLMModelId: String?

// STT Loading
suspend fun RunAnywhere.loadSTTModel(modelId: String)
suspend fun RunAnywhere.unloadSTTModel()
suspend fun RunAnywhere.isSTTModelLoaded(): Boolean
val RunAnywhere.currentSTTModelId: String?

// TTS Loading
suspend fun RunAnywhere.loadTTSVoice(voiceId: String)         // NOTE: loadTTSVoice, not loadTTSModel
suspend fun RunAnywhere.unloadTTSVoice()
suspend fun RunAnywhere.isTTSVoiceLoaded(): Boolean
val RunAnywhere.currentTTSVoiceId: String?
```

#### 3.5.2 LLM Generation APIs

**Source**: `RunAnywhere+TextGeneration.kt`

```kotlin
// Non-streaming (returns full result with metrics)
suspend fun RunAnywhere.generate(prompt: String, options: LLMGenerationOptions? = null): LLMGenerationResult

// Streaming (Flow of tokens)
fun RunAnywhere.generateStream(prompt: String, options: LLMGenerationOptions? = null): Flow<String>

// Streaming with metrics (Flow + Deferred result)
suspend fun RunAnywhere.generateStreamWithMetrics(prompt: String, options: LLMGenerationOptions? = null): LLMStreamingResult

// Cancel
fun RunAnywhere.cancelGeneration()
```

**LLMGenerationOptions** (`LLMTypes.kt`):
```kotlin
data class LLMGenerationOptions(
    val maxTokens: Int = 100,
    val temperature: Float = 0.8f,
    val topP: Float = 1.0f,
    val stopSequences: List<String> = emptyList(),
    val streamingEnabled: Boolean = false,
    val preferredFramework: InferenceFramework? = null,
    val structuredOutput: StructuredOutputConfig? = null,
    val systemPrompt: String? = null,
)
```

**LLMGenerationResult** (`LLMTypes.kt`):
```kotlin
data class LLMGenerationResult(
    val text: String,
    val thinkingContent: String? = null,
    val inputTokens: Int = 0,
    val tokensUsed: Int,               // output tokens
    val modelUsed: String,
    val latencyMs: Double,             // total latency in milliseconds
    val framework: String? = null,
    val tokensPerSecond: Double = 0.0,
    val timeToFirstTokenMs: Double? = null,
    val thinkingTokens: Int? = null,
    val responseTokens: Int = tokensUsed,
)
```

**LLMStreamingResult** (`LLMTypes.kt`):
```kotlin
data class LLMStreamingResult(
    val stream: Flow<String>,                     // Flow of tokens
    val result: Deferred<LLMGenerationResult>,    // Deferred final metrics
)
```

#### 3.5.3 STT APIs

**Source**: `RunAnywhere+STT.kt`

```kotlin
// Simple transcription
suspend fun RunAnywhere.transcribe(audioData: ByteArray): String

// Transcription with options and metadata
suspend fun RunAnywhere.transcribeWithOptions(audioData: ByteArray, options: STTOptions): STTOutput
```

**STTOptions** (`STTTypes.kt`):
```kotlin
data class STTOptions(
    val language: String = "en",
    val detectLanguage: Boolean = false,
    val enablePunctuation: Boolean = true,
    val enableDiarization: Boolean = false,
    val maxSpeakers: Int? = null,
    val enableTimestamps: Boolean = true,
    val vocabularyFilter: List<String> = emptyList(),
    val audioFormat: AudioFormat = AudioFormat.PCM,
    val sampleRate: Int = 16000,
    val preferredFramework: InferenceFramework? = null,
)
```

**STTOutput** (`STTTypes.kt`):
```kotlin
data class STTOutput(
    val text: String,
    val confidence: Float,
    val wordTimestamps: List<WordTimestamp>? = null,
    val detectedLanguage: String? = null,
    val alternatives: List<TranscriptionAlternative>? = null,
    val metadata: TranscriptionMetadata,
)
```

**TranscriptionMetadata** (`STTTypes.kt`):
```kotlin
data class TranscriptionMetadata(
    val modelId: String,
    val processingTime: Double,     // seconds
    val audioLength: Double,        // seconds
) {
    val realTimeFactor: Double      // processingTime / audioLength
}
```

#### 3.5.4 TTS APIs

**Source**: `RunAnywhere+TTS.kt`

```kotlin
// Synthesis (returns audio data — NO playback)
suspend fun RunAnywhere.synthesize(text: String, options: TTSOptions = TTSOptions()): TTSOutput

// Speak (synthesizes AND plays through speakers — do NOT use for benchmarks)
suspend fun RunAnywhere.speak(text: String, options: TTSOptions = TTSOptions()): TTSSpeakResult
```

**IMPORTANT**: Use `synthesize()` (not `speak()`) for benchmarks to avoid audio playback overhead. `synthesize` returns `TTSOutput` with raw audio bytes; `speak` returns `TTSSpeakResult` and plays through speakers.

**TTSOptions** (`TTSTypes.kt`):
```kotlin
data class TTSOptions(
    val voice: String? = null,
    val language: String = "en-US",
    val rate: Float = 1.0f,
    val pitch: Float = 1.0f,
    val volume: Float = 1.0f,
    val audioFormat: AudioFormat = AudioFormat.PCM,
    val sampleRate: Int = 22050,
    val useSSML: Boolean = false,
)
```

**TTSOutput** (`TTSTypes.kt`):
```kotlin
data class TTSOutput(
    val audioData: ByteArray,
    val format: AudioFormat,
    val duration: Double,                       // seconds
    val phonemeTimestamps: List<TTSPhonemeTimestamp>? = null,
    val metadata: TTSSynthesisMetadata,
)
```

**TTSSynthesisMetadata** (`TTSTypes.kt`):
```kotlin
data class TTSSynthesisMetadata(
    val voice: String,
    val language: String,
    val processingTime: Double,     // seconds
    val characterCount: Int,
) {
    val charactersPerSecond: Double  // characterCount / processingTime
}
```

#### 3.5.5 Memory Measurement (Android)

```kotlin
import android.os.Debug

/** Returns native heap allocated size in bytes. Best-effort memory measurement. */
fun availableNativeHeapBytes(): Long = Debug.getNativeHeapAllocatedSize()

// Usage pattern in each provider:
val memBefore = availableNativeHeapBytes()
// ... load model ...
val memAfter = availableNativeHeapBytes()
val peakMemoryDelta = memAfter - memBefore  // positive = memory consumed
```

**Note**: On Android, `Debug.getNativeHeapAllocatedSize()` measures native (C++) heap. Since all model loading happens in C++ via JNI, this is the correct metric. It increases when a model is loaded. Unlike iOS's `os_proc_available_memory()` (which measures available), Android's returns allocated (so delta = after - before, not before - after).

### 3.6 Provider Implementations — Verified SDK Integration Points

#### 3.6.1 LLMBenchmarkProvider

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/providers/LLMBenchmarkProvider.kt`

**Implementation sketch**:
```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks.providers

import android.os.Debug
import com.runanywhere.runanywhereai.domain.models.BenchmarkCategory
import com.runanywhere.runanywhereai.domain.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.domain.models.BenchmarkMetrics
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStreamWithMetrics
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.unloadLLMModel
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

class LLMBenchmarkProvider : BenchmarkScenarioProvider {
    override val category = BenchmarkCategory.LLM

    override fun scenarios() = listOf(
        BenchmarkScenario(name = "Short generation", category = BenchmarkCategory.LLM),
        BenchmarkScenario(name = "Medium generation", category = BenchmarkCategory.LLM),
        BenchmarkScenario(name = "Long generation", category = BenchmarkCategory.LLM),
    )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val (prompt, maxTokens, temp) = config(scenario.name)

        // 1. Measure load time
        val memBefore = Debug.getNativeHeapAllocatedSize()
        val loadStart = System.nanoTime()
        RunAnywhere.loadLLMModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0
        val memAfter = Debug.getNativeHeapAllocatedSize()
        val memDelta = memAfter - memBefore

        // 2. Warmup: one short non-streaming generation
        val warmupStart = System.nanoTime()
        RunAnywhere.generate("Hi", LLMGenerationOptions(maxTokens = 5, temperature = 0f))
        val warmupTimeMs = (System.nanoTime() - warmupStart) / 1_000_000.0

        // 3. Streaming generation with metrics (captures TTFT + tok/s)
        val options = LLMGenerationOptions(
            maxTokens = maxTokens,
            temperature = temp,
            streamingEnabled = true,
        )
        val genStart = System.nanoTime()
        val streamResult = RunAnywhere.generateStreamWithMetrics(prompt, options)

        var firstTokenTime: Double? = null
        streamResult.stream.collect { _ ->
            if (firstTokenTime == null) {
                firstTokenTime = (System.nanoTime() - genStart) / 1_000_000.0
            }
        }
        val totalTimeMs = (System.nanoTime() - genStart) / 1_000_000.0
        val finalMetrics = streamResult.result.await()

        // 4. Unload
        RunAnywhere.unloadLLMModel()

        return BenchmarkMetrics(
            loadTimeMs = loadTimeMs,
            warmupTimeMs = warmupTimeMs,
            timeToFirstTokenMs = firstTokenTime ?: finalMetrics.timeToFirstTokenMs,
            tokensPerSecond = finalMetrics.tokensPerSecond,
            endToEndLatencyMs = totalTimeMs,
            inputTokens = finalMetrics.inputTokens,
            outputTokens = finalMetrics.tokensUsed,
            peakMemoryDeltaBytes = if (memDelta > 0) memDelta else null,
        )
    }

    private data class ScenarioConfig(val prompt: String, val maxTokens: Int, val temperature: Float)

    private fun config(name: String): ScenarioConfig = when (name) {
        "Short generation" ->
            ScenarioConfig("What is 2+2? Answer briefly.", 50, 0.0f)
        "Medium generation" ->
            ScenarioConfig("Explain how photosynthesis works in 3 paragraphs.", 256, 0.0f)
        "Long generation" ->
            ScenarioConfig("Write a short story about a robot learning to paint.", 512, 0.7f)
        else ->
            ScenarioConfig("Hello", 50, 0.0f)
    }
}
```

#### 3.6.2 STTBenchmarkProvider

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/providers/STTBenchmarkProvider.kt`

**Implementation sketch**:
```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks.providers

import android.os.Debug
import com.runanywhere.runanywhereai.domain.models.BenchmarkCategory
import com.runanywhere.runanywhereai.domain.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.domain.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.SyntheticInputGenerator
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.unloadSTTModel
import com.runanywhere.sdk.public.extensions.transcribeWithOptions
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

class STTBenchmarkProvider : BenchmarkScenarioProvider {
    override val category = BenchmarkCategory.STT

    override fun scenarios() = listOf(
        BenchmarkScenario(name = "Silent audio (2s)", category = BenchmarkCategory.STT),
        BenchmarkScenario(name = "Synthetic tone (3s)", category = BenchmarkCategory.STT),
    )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val audioData: ByteArray = when (scenario.name) {
            "Silent audio (2s)" -> SyntheticInputGenerator.silentAudio(durationSeconds = 2.0)
            else -> SyntheticInputGenerator.sineWaveAudio(durationSeconds = 3.0, frequencyHz = 440.0)
        }

        // 1. Load model
        val memBefore = Debug.getNativeHeapAllocatedSize()
        val loadStart = System.nanoTime()
        RunAnywhere.loadSTTModel(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0
        val memDelta = Debug.getNativeHeapAllocatedSize() - memBefore

        // 2. Transcribe with options to get metadata
        val e2eStart = System.nanoTime()
        val output = RunAnywhere.transcribeWithOptions(audioData, STTOptions())
        val e2eMs = (System.nanoTime() - e2eStart) / 1_000_000.0

        // 3. Unload
        RunAnywhere.unloadSTTModel()

        return BenchmarkMetrics(
            loadTimeMs = loadTimeMs,
            endToEndLatencyMs = e2eMs,
            peakMemoryDeltaBytes = if (memDelta > 0) memDelta else null,
            sttTranscriptionTimeMs = output.metadata.processingTime * 1000,
        )
    }
}
```

#### 3.6.3 TTSBenchmarkProvider

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/providers/TTSBenchmarkProvider.kt`

**Implementation sketch**:
```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks.providers

import android.os.Debug
import com.runanywhere.runanywhereai.domain.models.BenchmarkCategory
import com.runanywhere.runanywhereai.domain.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.domain.models.BenchmarkMetrics
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import com.runanywhere.sdk.public.extensions.unloadTTSVoice
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

class TTSBenchmarkProvider : BenchmarkScenarioProvider {
    override val category = BenchmarkCategory.TTS

    override fun scenarios() = listOf(
        BenchmarkScenario(name = "Short text", category = BenchmarkCategory.TTS),
        BenchmarkScenario(name = "Medium text", category = BenchmarkCategory.TTS),
    )

    override suspend fun execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo,
    ): BenchmarkMetrics {
        val text: String = when (scenario.name) {
            "Short text" -> "Hello, world."
            else -> "The quick brown fox jumps over the lazy dog. This is a benchmark test for text to speech synthesis quality and speed."
        }

        // 1. Load model (TTS uses "voice" terminology)
        val memBefore = Debug.getNativeHeapAllocatedSize()
        val loadStart = System.nanoTime()
        RunAnywhere.loadTTSVoice(model.id)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0
        val memDelta = Debug.getNativeHeapAllocatedSize() - memBefore

        // 2. Synthesize (NOT speak — avoids audio playback overhead)
        val e2eStart = System.nanoTime()
        val output = RunAnywhere.synthesize(text, TTSOptions())
        val e2eMs = (System.nanoTime() - e2eStart) / 1_000_000.0

        // 3. Unload
        RunAnywhere.unloadTTSVoice()

        return BenchmarkMetrics(
            loadTimeMs = loadTimeMs,
            endToEndLatencyMs = e2eMs,
            peakMemoryDeltaBytes = if (memDelta > 0) memDelta else null,
            ttsSynthesisTimeMs = output.metadata.processingTime * 1000,
        )
    }
}
```

### 3.7 BenchmarkRunner.kt — Orchestration

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/BenchmarkRunner.kt`

```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks

import com.runanywhere.runanywhereai.domain.models.*
import com.runanywhere.runanywhereai.presentation.benchmarks.providers.*
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext
import java.util.UUID

data class BenchmarkProgressUpdate(
    val currentScenario: String,
    val progress: Float,    // 0.0–1.0
    val completedCount: Int,
    val totalCount: Int,
)

class BenchmarkRunner {
    private val providers: Map<BenchmarkCategory, BenchmarkScenarioProvider> = mapOf(
        // Register all providers. Adding a new component = adding one line here.
        BenchmarkCategory.LLM to LLMBenchmarkProvider(),
        BenchmarkCategory.STT to STTBenchmarkProvider(),
        BenchmarkCategory.TTS to TTSBenchmarkProvider(),
        // Future: BenchmarkCategory.VLM to VLMBenchmarkProvider(),
        // Future: BenchmarkCategory.DIFFUSION to DiffusionBenchmarkProvider(),
    )

    /**
     * Run benchmarks for selected categories across all downloaded models.
     * Reports progress via the callback. Checks for cancellation via coroutineContext.
     */
    suspend fun runBenchmarks(
        categories: Set<BenchmarkCategory>,
        deviceInfo: BenchmarkDeviceInfo,
        onProgress: (BenchmarkProgressUpdate) -> Unit,
    ): List<BenchmarkResult> {
        val results = mutableListOf<BenchmarkResult>()
        val allModels = RunAnywhere.availableModels()

        // Build work list: (category, model, scenario) triples
        val workItems = mutableListOf<Triple<BenchmarkCategory, ModelInfo, BenchmarkScenario>>()
        for (category in categories.sorted()) {
            val provider = providers[category] ?: continue
            val models = downloadedModels(category, allModels)
            if (models.isEmpty()) continue
            for (model in models) {
                for (scenario in provider.scenarios()) {
                    workItems.add(Triple(category, model, scenario))
                }
            }
        }

        val totalItems = workItems.size
        if (totalItems == 0) return emptyList()

        for ((index, triple) in workItems.withIndex()) {
            coroutineContext.ensureActive() // check for cancellation

            val (category, model, scenario) = triple

            onProgress(BenchmarkProgressUpdate(
                currentScenario = "${category.displayName}: ${scenario.name} (${model.name})",
                progress = index.toFloat() / totalItems.toFloat(),
                completedCount = index,
                totalCount = totalItems,
            ))

            val provider = providers[category] ?: continue

            try {
                val metrics = provider.execute(scenario, model, deviceInfo)
                results.add(BenchmarkResult(
                    id = UUID.randomUUID().toString(),
                    timestamp = System.currentTimeMillis(),
                    category = category,
                    scenarioName = scenario.name,
                    componentModelInfo = ComponentModelInfo.from(model, category),
                    deviceInfo = deviceInfo,
                    metrics = metrics,
                ))
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e // propagate cancellation
            } catch (e: Exception) {
                // Record error result, don't abort the entire run
                results.add(BenchmarkResult(
                    id = UUID.randomUUID().toString(),
                    timestamp = System.currentTimeMillis(),
                    category = category,
                    scenarioName = scenario.name,
                    componentModelInfo = ComponentModelInfo.from(model, category),
                    deviceInfo = deviceInfo,
                    metrics = BenchmarkMetrics(
                        endToEndLatencyMs = 0.0,
                        error = e.message ?: "Unknown error",
                    ),
                ))
            }
        }

        return results
    }

    /**
     * Filter downloaded models for a given category.
     * Includes both user-downloaded models and built-in models (if any).
     */
    private fun downloadedModels(
        category: BenchmarkCategory,
        allModels: List<ModelInfo>,
    ): List<ModelInfo> {
        return allModels.filter { it.category == category.modelCategory && it.isDownloaded }
    }

    /** Sorted categories for deterministic ordering */
    private fun Set<BenchmarkCategory>.sorted(): List<BenchmarkCategory> {
        return this.sortedBy { it.ordinal }
    }
}
```

### 3.8 SyntheticInputGenerator.kt

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/SyntheticInputGenerator.kt`

```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin

/**
 * Generates synthetic test inputs (audio buffers) for benchmarks
 * without requiring hardware (microphone/camera).
 */
object SyntheticInputGenerator {
    private const val SAMPLE_RATE = 16000 // 16kHz for STT models

    /**
     * 16kHz mono Int16 PCM silence.
     * @param durationSeconds Duration in seconds
     * @return ByteArray of zeroed PCM samples
     */
    fun silentAudio(durationSeconds: Double): ByteArray {
        val sampleCount = (durationSeconds * SAMPLE_RATE).toInt()
        return ByteArray(sampleCount * 2) // 2 bytes per Int16 sample, all zeros
    }

    /**
     * 16kHz mono Int16 PCM sine wave.
     * @param durationSeconds Duration in seconds
     * @param frequencyHz Frequency in Hz (default 440 = A4)
     * @return ByteArray of PCM samples
     */
    fun sineWaveAudio(durationSeconds: Double, frequencyHz: Double = 440.0): ByteArray {
        val sampleCount = (durationSeconds * SAMPLE_RATE).toInt()
        val buffer = ByteBuffer.allocate(sampleCount * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until sampleCount) {
            val t = i.toDouble() / SAMPLE_RATE
            val sample = (sin(2.0 * PI * frequencyHz * t) * (Short.MAX_VALUE / 2)).toInt().toShort()
            buffer.putShort(sample)
        }
        return buffer.array()
    }

    // MARK: - Images (for future VLM benchmarks)
    // When VLM benchmarks are added, add these methods to match iOS's SyntheticInputGenerator:
    //
    //   fun solidColorBitmap(color: Int, width: Int = 224, height: Int = 224): Bitmap {
    //       return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
    //           eraseColor(color)
    //       }
    //   }
    //
    //   fun gradientBitmap(fromColor: Int, toColor: Int, width: Int = 224, height: Int = 224): Bitmap {
    //       val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    //       val canvas = Canvas(bitmap)
    //       val paint = Paint()
    //       paint.shader = LinearGradient(
    //           0f, 0f, 0f, height.toFloat(),
    //           fromColor, toColor, Shader.TileMode.CLAMP,
    //       )
    //       canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    //       return bitmap
    //   }
    //
    // Required imports: android.graphics.{Bitmap, Canvas, LinearGradient, Paint, Shader}
}
```

### 3.9 BenchmarkStore.kt — Persistence

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/BenchmarkStore.kt`

```kotlin
package com.runanywhere.runanywhereai.data

import android.content.Context
import com.runanywhere.runanywhereai.domain.models.BenchmarkRun
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Persists benchmark runs as JSON in app internal storage.
 * NOT thread-safe — should only be called from ViewModel (MainThread/viewModelScope).
 */
class BenchmarkStore(context: Context) {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
    private val file: File = File(context.filesDir, FILENAME)

    fun loadRuns(): List<BenchmarkRun> {
        if (!file.exists()) return emptyList()
        return try {
            json.decodeFromString<List<BenchmarkRun>>(file.readText())
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun save(run: BenchmarkRun) {
        val runs = loadRuns().toMutableList()
        // Replace existing run with same ID or insert at front
        val existingIndex = runs.indexOfFirst { it.id == run.id }
        if (existingIndex >= 0) {
            runs[existingIndex] = run
        } else {
            runs.add(0, run)
        }
        // Prune to max
        val pruned = if (runs.size > MAX_RUNS) runs.take(MAX_RUNS) else runs
        file.writeText(json.encodeToString(pruned))
    }

    fun clearAll() {
        file.delete()
    }

    companion object {
        private const val FILENAME = "benchmarks.json"
        private const val MAX_RUNS = 50
    }
}
```

**Storage location**: `context.filesDir/benchmarks.json` (app-internal, survives app updates, not user-visible without root).

**Threading note**: `BenchmarkStore` performs synchronous file I/O. The ViewModel calls `store.save()` and `store.loadRuns()` from `viewModelScope.launch` which runs on the Main dispatcher by default. For small files (< 50 runs ≈ a few hundred KB) this is acceptable. If you want to be strictly correct, wrap file I/O calls in `withContext(Dispatchers.IO) { ... }` inside the ViewModel. The key constraint is: **do NOT call `BenchmarkStore` from `BenchmarkRunner`** (which runs on `Dispatchers.IO`) — only call it from the ViewModel after the runner completes.

### 3.10 BenchmarkViewModel.kt

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/BenchmarkViewModel.kt`

```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.BenchmarkStore
import com.runanywhere.runanywhereai.domain.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

data class BenchmarkUiState(
    val isRunning: Boolean = false,
    val currentScenario: String = "",
    val progress: Float = 0f,
    val completedCount: Int = 0,
    val totalCount: Int = 0,
    val currentRun: BenchmarkRun? = null,
    val pastRuns: List<BenchmarkRun> = emptyList(),
    val errorMessage: String? = null,
    val selectedCategories: Set<BenchmarkCategory> = setOf(
        BenchmarkCategory.LLM,
        BenchmarkCategory.STT,
        BenchmarkCategory.TTS,
    ),
)

class BenchmarkViewModel(application: Application) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(BenchmarkUiState())
    val uiState: StateFlow<BenchmarkUiState> = _uiState.asStateFlow()

    private val store = BenchmarkStore(application)
    private val runner = BenchmarkRunner()
    private val reportFormatter = BenchmarkReportFormatter()
    private var runJob: Job? = null

    init {
        _uiState.update { it.copy(pastRuns = store.loadRuns()) }
    }

    // MARK: - Category Selection

    fun toggleCategory(category: BenchmarkCategory) {
        _uiState.update { state ->
            val newSet = state.selectedCategories.toMutableSet()
            if (newSet.contains(category)) newSet.remove(category) else newSet.add(category)
            state.copy(selectedCategories = newSet)
        }
    }

    // MARK: - Run Actions

    fun runAll() {
        run(setOf(BenchmarkCategory.LLM, BenchmarkCategory.STT, BenchmarkCategory.TTS))
    }

    fun runSelected() {
        run(_uiState.value.selectedCategories)
    }

    fun runCategory(category: BenchmarkCategory) {
        run(setOf(category))
    }

    fun cancel() {
        runJob?.cancel()
    }

    fun clearAllResults() {
        store.clearAll()
        _uiState.update { it.copy(pastRuns = emptyList()) }
    }

    // MARK: - Export

    fun copyReportToClipboard(run: BenchmarkRun) {
        val markdown = reportFormatter.formatMarkdown(run)
        val clipboard = getApplication<Application>().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Benchmark Report", markdown))
        Toast.makeText(getApplication(), "Copied to clipboard", Toast.LENGTH_SHORT).show()
    }

    /**
     * Create a share Intent for JSON or CSV export.
     * Caller should startActivity with this Intent.
     */
    fun createShareIntent(run: BenchmarkRun, format: ExportFormat): Intent {
        val context = getApplication<Application>()
        val file = when (format) {
            ExportFormat.JSON -> reportFormatter.writeJSON(run, context)
            ExportFormat.CSV -> reportFormatter.writeCSV(run, context)
        }
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
        return Intent(Intent.ACTION_SEND).apply {
            type = when (format) {
                ExportFormat.JSON -> "application/json"
                ExportFormat.CSV -> "text/csv"
            }
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    /**
     * Save report to app-visible external storage (Downloads via MediaStore on API 29+).
     */
    fun saveToDevice(run: BenchmarkRun, format: ExportFormat): String {
        val context = getApplication<Application>()
        val filename = reportFormatter.saveToDownloads(run, format, context)
        Toast.makeText(context, "Saved: $filename", Toast.LENGTH_SHORT).show()
        return filename
    }

    // MARK: - Query

    fun getRun(runId: String): BenchmarkRun? {
        return _uiState.value.pastRuns.find { it.id == runId }
            ?: _uiState.value.currentRun?.takeIf { it.id == runId }
    }

    // MARK: - Private

    private fun run(categories: Set<BenchmarkCategory>) {
        if (_uiState.value.isRunning) return
        val context = getApplication<Application>()
        val deviceInfo = BenchmarkDeviceInfo.fromSystem(context)

        val newRun = BenchmarkRun(
            id = UUID.randomUUID().toString(),
            startedAt = System.currentTimeMillis(),
            deviceInfo = deviceInfo,
            status = BenchmarkRunStatus.RUNNING,
        )

        _uiState.update {
            it.copy(
                isRunning = true,
                errorMessage = null,
                currentRun = newRun,
                progress = 0f,
                completedCount = 0,
                totalCount = 0,
            )
        }

        runJob = viewModelScope.launch {
            var run = newRun
            try {
                val results = withContext(Dispatchers.IO) {
                    runner.runBenchmarks(
                        categories = categories,
                        deviceInfo = deviceInfo,
                        onProgress = { update ->
                            _uiState.update { state ->
                                state.copy(
                                    currentScenario = update.currentScenario,
                                    progress = update.progress,
                                    completedCount = update.completedCount,
                                    totalCount = update.totalCount,
                                )
                            }
                        },
                    )
                }
                run = run.copy(
                    results = results,
                    completedAt = System.currentTimeMillis(),
                    status = BenchmarkRunStatus.COMPLETED,
                )
            } catch (_: kotlinx.coroutines.CancellationException) {
                run = run.copy(
                    completedAt = System.currentTimeMillis(),
                    status = BenchmarkRunStatus.CANCELLED,
                )
            } catch (e: Exception) {
                run = run.copy(
                    completedAt = System.currentTimeMillis(),
                    status = BenchmarkRunStatus.FAILED,
                )
                _uiState.update { it.copy(errorMessage = e.message) }
            }

            store.save(run)
            _uiState.update {
                it.copy(
                    isRunning = false,
                    currentRun = run,
                    pastRuns = store.loadRuns(),
                )
            }
        }
    }
}

enum class ExportFormat { JSON, CSV }
```

**Key Android-specific patterns**:
- Uses `AndroidViewModel` (needs `Application` context for clipboard, FileProvider, Toast)
- `viewModelScope.launch` for coroutines with `Dispatchers.IO` for heavy work
- `FileProvider` for sharing files via `Intent.ACTION_SEND`
- `ClipboardManager` for copy-to-clipboard
- `Toast` for confirmation messages
- `MediaStore` for saving to Downloads (API 29+)

**Required dependency addition**: `collectAsStateWithLifecycle()` requires `androidx.lifecycle:lifecycle-runtime-compose`, which is **NOT currently present** in the app-level `build.gradle.kts` OR the version catalog. The `build.gradle.kts` has `lifecycle-runtime-ktx` (line 244) and `lifecycle-viewmodel-compose` (line 245) but NOT `lifecycle-runtime-compose`. You **MUST** add it in two places:

**Step 1** — Add to version catalog (`gradle/libs.versions.toml`):
```toml
# In [libraries] section, after the existing lifecycle entries (lines 158-159), add:
androidx-lifecycle-runtime-compose = { group = "androidx.lifecycle", name = "lifecycle-runtime-compose", version.ref = "lifecycleRuntimeKtx" }
```
This reuses the existing `lifecycleRuntimeKtx = "2.8.7"` version reference (line 14).

**Step 2** — Add to `app/build.gradle.kts` dependencies block (after line 245):
```kotlin
implementation(libs.androidx.lifecycle.runtime.compose)
```

### 3.11 BenchmarkReportFormatter.kt

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/BenchmarkReportFormatter.kt`

```kotlin
package com.runanywhere.runanywhereai.presentation.benchmarks

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.runanywhere.runanywhereai.domain.models.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.addJsonObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BenchmarkReportFormatter {

    private val json = Json {
        prettyPrint = true
        encodeDefaults = true
    }
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }

    // MARK: - Markdown (for clipboard copy)

    fun formatMarkdown(run: BenchmarkRun): String = buildString {
        appendLine("# Benchmark Report")
        appendLine()
        appendLine("**Date**: ${dateFormat.format(Date(run.startedAt))}")
        appendLine("**Status**: ${run.status.name.lowercase()}")
        run.completedAt?.let { completedAt ->
            val durationSec = (completedAt - run.startedAt) / 1000.0
            appendLine("**Duration**: ${"%.1f".format(durationSec)}s")
        }
        appendLine()
        appendLine("## Device")
        appendLine("- Model: ${run.deviceInfo.modelName}")
        appendLine("- Chip: ${run.deviceInfo.chipName}")
        appendLine("- RAM: ${run.deviceInfo.totalMemoryBytes / 1_073_741_824} GB")
        appendLine("- OS: ${run.deviceInfo.osVersion}")
        appendLine("- App: ${run.deviceInfo.appVersion}, SDK: ${run.deviceInfo.sdkVersion}")
        appendLine()

        // Group results by category
        val grouped = run.results.groupBy { it.category }
        for (category in BenchmarkCategory.entries) {
            val results = grouped[category] ?: continue
            if (results.isEmpty()) continue
            appendLine("## ${category.displayName}")
            appendLine()
            for (result in results) {
                appendLine("### ${result.scenarioName} — ${result.componentModelInfo.modelName}")
                appendLine("- Framework: ${result.componentModelInfo.framework}")
                result.componentModelInfo.formatOrQuantization?.let { appendLine("- Format: $it") }
                val m = result.metrics
                m.loadTimeMs?.let { appendLine("- Load: ${"%.0f".format(it)} ms") }
                m.warmupTimeMs?.let { appendLine("- Warmup: ${"%.0f".format(it)} ms") }
                m.timeToFirstTokenMs?.let { appendLine("- TTFT: ${"%.0f".format(it)} ms") }
                m.tokensPerSecond?.let { appendLine("- Tokens/sec: ${"%.1f".format(it)}") }
                appendLine("- E2E Latency: ${"%.0f".format(m.endToEndLatencyMs)} ms")
                m.inputTokens?.let { appendLine("- Input tokens: $it") }
                m.outputTokens?.let { appendLine("- Output tokens: $it") }
                m.sttTranscriptionTimeMs?.let { appendLine("- Transcription: ${"%.0f".format(it)} ms") }
                m.ttsSynthesisTimeMs?.let { appendLine("- Synthesis: ${"%.0f".format(it)} ms") }
                m.peakMemoryDeltaBytes?.let { appendLine("- Memory delta: ${it / 1_048_576} MB") }
                m.error?.let { appendLine("- **ERROR**: $it") }
                appendLine()
            }
        }
    }

    // MARK: - JSON (for file export)

    /**
     * Writes JSON export with ISO8601 timestamps for cross-platform compatibility.
     * Internal storage (BenchmarkStore) uses raw Long epoch millis, but the export
     * format must use ISO8601 strings to match the shared spec (section 1.4/1.7).
     *
     * Uses buildJsonObject to manually construct the export JSON with converted timestamps
     * rather than relying on raw @Serializable output (which would emit Long values).
     */
    fun writeJSON(run: BenchmarkRun, context: Context): File {
        val exportJson = buildJsonObject {
            put("id", run.id)
            put("startedAt", dateFormat.format(Date(run.startedAt)))
            run.completedAt?.let { put("completedAt", dateFormat.format(Date(it))) }
            put("status", run.status.name.lowercase())
            put("deviceInfo", json.encodeToJsonElement(run.deviceInfo))
            putJsonArray("results") {
                for (r in run.results) {
                    addJsonObject {
                        put("id", r.id)
                        put("timestamp", dateFormat.format(Date(r.timestamp)))
                        put("category", r.category.name.lowercase())
                        put("scenarioName", r.scenarioName)
                        put("componentModelInfo", json.encodeToJsonElement(r.componentModelInfo))
                        put("deviceInfo", json.encodeToJsonElement(r.deviceInfo))
                        put("metrics", json.encodeToJsonElement(r.metrics))
                    }
                }
            }
        }
        val data = json.encodeToString(exportJson)
        val file = File(context.cacheDir, "benchmark_${run.id}.json")
        file.writeText(data)
        return file
    }

    // MARK: - CSV (for file export)

    fun writeCSV(run: BenchmarkRun, context: Context): File {
        val header = "run_id,timestamp,category,scenario,model_id,model_name,framework,quantization,device,os,load_time_ms,warmup_ms,ttft_ms,tokens_per_sec,e2e_latency_ms,input_tokens,output_tokens,memory_delta_bytes,stt_time_ms,tts_time_ms,vlm_time_ms,diffusion_time_ms,error"
        val rows = mutableListOf(header)
        for (r in run.results) {
            val m = r.metrics
            val row = listOf(
                run.id, dateFormat.format(Date(r.timestamp)), r.category.name.lowercase(), r.scenarioName,
                r.componentModelInfo.modelId, r.componentModelInfo.modelName,
                r.componentModelInfo.framework, r.componentModelInfo.formatOrQuantization ?: "",
                run.deviceInfo.modelName, run.deviceInfo.osVersion,
                m.loadTimeMs?.let { "%.1f".format(it) } ?: "",
                m.warmupTimeMs?.let { "%.1f".format(it) } ?: "",
                m.timeToFirstTokenMs?.let { "%.1f".format(it) } ?: "",
                m.tokensPerSecond?.let { "%.1f".format(it) } ?: "",
                "%.1f".format(m.endToEndLatencyMs),
                m.inputTokens?.toString() ?: "",
                m.outputTokens?.toString() ?: "",
                m.peakMemoryDeltaBytes?.toString() ?: "",
                m.sttTranscriptionTimeMs?.let { "%.1f".format(it) } ?: "",
                m.ttsSynthesisTimeMs?.let { "%.1f".format(it) } ?: "",
                m.vlmDescriptionTimeMs?.let { "%.1f".format(it) } ?: "",
                m.imageGenerationTimeMs?.let { "%.1f".format(it) } ?: "",
                m.error ?: "",
            ).map { if (it.contains(",")) "\"$it\"" else it }.joinToString(",")
            rows.add(row)
        }
        val file = File(context.cacheDir, "benchmark_${run.id}.csv")
        file.writeText(rows.joinToString("\n"))
        return file
    }

    // MARK: - Save to Downloads (MediaStore for API 29+, legacy for older)

    fun saveToDownloads(run: BenchmarkRun, format: ExportFormat, context: Context): String {
        val ext = if (format == ExportFormat.JSON) "json" else "csv"
        val mimeType = if (format == ExportFormat.JSON) "application/json" else "text/csv"
        val filename = "benchmark_${run.id}.$ext"
        val content = if (format == ExportFormat.JSON) {
            json.encodeToString(run)
        } else {
            // Reuse CSV generation
            val csvFile = writeCSV(run, context)
            csvFile.readText().also { csvFile.delete() }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Use MediaStore for API 29+
            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
            uri?.let { resolver.openOutputStream(it)?.use { os -> os.write(content.toByteArray()) } }
        } else {
            // Legacy: write to external Downloads directory
            @Suppress("DEPRECATION")
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            File(downloadsDir, filename).writeText(content)
        }

        return filename
    }
}
```

**Android-specific export differences from iOS**:
- **Clipboard**: `ClipboardManager.setPrimaryClip()` + `Toast` confirmation (iOS uses `UIPasteboard` + haptic)
- **Share**: `Intent.ACTION_SEND` with `FileProvider` URI (iOS uses `ShareLink`)
- **Save to device**: `MediaStore.Downloads` on API 29+ (iOS uses `FileManager` Documents directory)
- **FileProvider**: Requires a `file_paths.xml` resource — the app does **NOT** currently have one. Add both files (see section 3.13).

#### 3.11.1 Export & Share UX Flow (Android)

The detail screen overflow menu (`DetailExportMenu` in 3.12.2) provides five export actions. Here is the complete UX flow for each:

**1. Copy Markdown Report**:
- User taps "Copy Markdown Report" in overflow menu
- `BenchmarkViewModel.copyReportToClipboard(run)` is called
- `ClipboardManager.setPrimaryClip()` copies Markdown text
- `Toast.makeText(..., "Copied to clipboard", Toast.LENGTH_SHORT).show()` provides confirmation
- No haptic feedback (Android `Toast` is the standard confirmation pattern, unlike iOS haptic)

**2. Share JSON / Share CSV**:
- User taps "Share JSON" or "Share CSV"
- `BenchmarkViewModel.createShareIntent(run, format)` creates a share `Intent`:
  1. `BenchmarkReportFormatter.writeJSON()` or `.writeCSV()` writes file to `context.cacheDir`
  2. `FileProvider.getUriForFile()` creates a content URI for the file
  3. `Intent(Intent.ACTION_SEND)` is configured with MIME type + `EXTRA_STREAM` + `FLAG_GRANT_READ_URI_PERMISSION`
- `context.startActivity(Intent.createChooser(intent, "Share JSON"))` opens Android share sheet
- Receiving app gets read access to the file via the content URI grant

**3. Save JSON / Save CSV to Downloads**:
- User taps "Save JSON to Downloads" or "Save CSV to Downloads"
- `BenchmarkViewModel.saveToDevice(run, format)` is called
- `BenchmarkReportFormatter.saveToDownloads()` writes to device Downloads:
  - **API 29+**: Uses `MediaStore.Downloads.EXTERNAL_CONTENT_URI` with `ContentResolver.insert()` — no storage permission needed
  - **API 24-28**: Uses `Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)` — may need `WRITE_EXTERNAL_STORAGE` permission (already declared in manifest for audio recording)
- `Toast.makeText(..., "Saved: benchmark_xxx.json", Toast.LENGTH_SHORT).show()` confirms with filename

**Confirmation patterns**:
- All confirmations use `Toast.LENGTH_SHORT` (~2 seconds)
- No haptic feedback (Android convention uses `Toast`, not haptic; iOS uses haptic feedback on copy/save)
- Share chooser appears immediately via `startActivity`

### 3.12 UI Screens (Compose)

#### 3.12.1 BenchmarkDashboardScreen

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/BenchmarkDashboardScreen.kt`

**Layout**:
```kotlin
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchmarkDashboardScreen(
    onNavigateToDetail: (runId: String) -> Unit,
    onNavigateBack: () -> Unit,
    viewModel: BenchmarkViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showClearConfirm by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Benchmarks") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (uiState.pastRuns.isNotEmpty()) {
                        IconButton(onClick = { showClearConfirm = true }) {
                            Icon(Icons.Outlined.DeleteSweep, contentDescription = "Clear All")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            // 1. Device Info Card
            DeviceInfoCard(deviceInfo = BenchmarkDeviceInfo.fromSystem(LocalContext.current))

            // 2. Category Filter Chips
            CategoryFilterChips(
                selectedCategories = uiState.selectedCategories,
                onToggle = viewModel::toggleCategory,
            )

            // 3. Run Buttons
            RunButtonsSection(
                isRunning = uiState.isRunning,
                onRunAll = viewModel::runAll,
                onRunSelected = viewModel::runSelected,
                onCancel = viewModel::cancel,
            )

            // 4. Progress Overlay (when running)
            if (uiState.isRunning) {
                BenchmarkProgressOverlay(
                    currentScenario = uiState.currentScenario,
                    progress = uiState.progress,
                    completedCount = uiState.completedCount,
                    totalCount = uiState.totalCount,
                    onCancel = viewModel::cancel,
                )
            }

            // 5. Error Message
            uiState.errorMessage?.let { error ->
                ErrorCard(message = error)
            }

            // 6. Past Runs List
            PastRunsList(
                runs = uiState.pastRuns,
                onRunClick = { onNavigateToDetail(it.id) },
            )

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    // Clear All Confirmation
    if (showClearConfirm) {
        AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            title = { Text("Clear All Results") },
            text = { Text("Are you sure? All benchmark history will be deleted.") },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.clearAllResults(); showClearConfirm = false },
                    colors = ButtonDefaults.textButtonColors(contentColor = AppColors.primaryRed),
                ) { Text("Delete All") }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirm = false }) { Text("Cancel") }
            },
        )
    }
}
```

**Sub-composables** (all in the same file or as private functions):

**CategoryFilterChips** — Horizontal scrollable row of filter chips:
```kotlin
@Composable
private fun CategoryFilterChips(
    selectedCategories: Set<BenchmarkCategory>,
    onToggle: (BenchmarkCategory) -> Unit,
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(vertical = 8.dp),
    ) {
        items(listOf(BenchmarkCategory.LLM, BenchmarkCategory.STT, BenchmarkCategory.TTS)) { category ->
            val isSelected = selectedCategories.contains(category)
            FilterChip(
                selected = isSelected,
                onClick = { onToggle(category) },
                label = { Text(category.displayName) },
                leadingIcon = {
                    Icon(
                        imageVector = categoryIcon(category),
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = AppColors.primaryAccent.copy(alpha = 0.15f),
                    selectedLabelColor = AppColors.primaryAccent,
                    selectedLeadingIconColor = AppColors.primaryAccent,
                ),
            )
        }
    }
}

private fun categoryIcon(category: BenchmarkCategory): ImageVector = when (category) {
    BenchmarkCategory.LLM -> Icons.Outlined.Chat
    BenchmarkCategory.STT -> Icons.Outlined.GraphicEq
    BenchmarkCategory.TTS -> Icons.Outlined.VolumeUp
    BenchmarkCategory.VLM -> Icons.Outlined.RemoveRedEye
    BenchmarkCategory.DIFFUSION -> Icons.Outlined.Image
}
```

**PastRunsList** — List of past run cards:
```kotlin
@Composable
private fun PastRunsList(
    runs: List<BenchmarkRun>,
    onRunClick: (BenchmarkRun) -> Unit,
) {
    if (runs.isEmpty()) {
        Text(
            text = "No benchmark runs yet",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 24.dp),
        )
        return
    }
    Column(modifier = Modifier.padding(horizontal = 16.dp)) {
        Text(
            text = "Past Runs",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(vertical = 8.dp),
        )
        runs.forEach { run ->
            BenchmarkRunCard(run = run, onClick = { onRunClick(run) })
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}
```

**BenchmarkRunCard** — Single past run summary card:
```kotlin
@Composable
private fun BenchmarkRunCard(run: BenchmarkRun, onClick: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = dateFormat.format(Date(run.startedAt)),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    text = "${run.results.size} results" +
                        run.completedAt?.let { " • ${"%.1f".format((it - run.startedAt) / 1000.0)}s" }.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            StatusBadge(status = run.status)
            Icon(
                Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun StatusBadge(status: BenchmarkRunStatus) {
    val (color, label) = when (status) {
        BenchmarkRunStatus.COMPLETED -> AppColors.primaryGreen to "Done"
        BenchmarkRunStatus.CANCELLED -> AppColors.primaryOrange to "Cancelled"
        BenchmarkRunStatus.FAILED -> AppColors.primaryRed to "Failed"
        BenchmarkRunStatus.RUNNING -> AppColors.primaryAccent to "Running"
    }
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = color.copy(alpha = 0.15f),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
        )
    }
}
```

**DeviceInfoCard** — Shown at top of dashboard:
```kotlin
@Composable
private fun DeviceInfoCard(deviceInfo: BenchmarkDeviceInfo) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Device",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(8.dp))
            DeviceInfoRow("Model", deviceInfo.modelName)
            DeviceInfoRow("Chip", deviceInfo.chipName)
            DeviceInfoRow("RAM", "${deviceInfo.totalMemoryBytes / 1_073_741_824} GB")
            DeviceInfoRow("OS", deviceInfo.osVersion)
            DeviceInfoRow("App", deviceInfo.appVersion)
        }
    }
}

@Composable
private fun DeviceInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
        )
    }
}
```

**RunButtonsSection** — Primary and secondary action buttons:
```kotlin
@Composable
private fun RunButtonsSection(
    isRunning: Boolean,
    onRunAll: () -> Unit,
    onRunSelected: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Button(
            onClick = onRunAll,
            enabled = !isRunning,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryAccent),
        ) {
            Icon(Icons.Outlined.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("Run All Benchmarks")
        }
        OutlinedButton(
            onClick = onRunSelected,
            enabled = !isRunning,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.primaryAccent),
        ) {
            Text("Run Selected")
        }
    }
}
```

**ErrorCard** — Displayed when a run fails:
```kotlin
@Composable
private fun ErrorCard(message: String) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(8.dp),
        color = AppColors.primaryRed.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Outlined.ErrorOutline,
                contentDescription = null,
                tint = AppColors.primaryRed,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.primaryRed,
            )
        }
    }
}
```

**`dateFormat`** — Shared date formatter for run cards (at file level or companion):
```kotlin
private val dateFormat = java.text.SimpleDateFormat("MMM d, HH:mm", java.util.Locale.getDefault())
```

**Design tokens to use** (matching existing app patterns from `AppColors.kt`, `AppSpacing.kt`, `Dimensions.kt`):
- Section containers: `MaterialTheme.colorScheme.surfaceVariant`, `RoundedCornerShape(12.dp)`
- Primary buttons: `AppColors.primaryAccent` as `containerColor`
- Status: `AppColors.primaryGreen` (completed), `AppColors.primaryOrange` (cancelled), `AppColors.primaryRed` (failed)
- Spacing: `16.dp` horizontal padding, `8.dp` between items (matches existing `SettingsScreen` padding pattern)
- Typography: `MaterialTheme.typography.titleSmall` for section headers, `bodyMedium` for content, `bodySmall` for secondary text
- Cards: Follow the `SettingsSection` pattern — `Surface` with `RoundedCornerShape(12.dp)` + `surfaceVariant` color

#### 3.12.2 BenchmarkDetailScreen

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/BenchmarkDetailScreen.kt`

Shows a single `BenchmarkRun` in detail. Full composable implementation:

```kotlin
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchmarkDetailScreen(
    runId: String,
    onNavigateBack: () -> Unit,
    viewModel: BenchmarkViewModel = viewModel(),
) {
    val run = viewModel.getRun(runId)
    if (run == null) {
        // Run not found — navigate back
        LaunchedEffect(Unit) { onNavigateBack() }
        return
    }

    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Benchmark Details") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    DetailExportMenu(run = run, viewModel = viewModel, context = context)
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            // 1. Run Metadata Card
            RunMetadataCard(run = run)

            // 2. Results Grouped by Category
            val grouped = run.results.groupBy { it.category }
            for (category in BenchmarkCategory.entries) {
                val results = grouped[category] ?: continue
                if (results.isEmpty()) continue
                CategoryResultsSection(category = category, results = results)
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}
```

**RunMetadataCard** — Run summary at top:
```kotlin
@Composable
private fun RunMetadataCard(run: BenchmarkRun) {
    val dateFormat = remember { SimpleDateFormat("MMM d, yyyy HH:mm:ss", Locale.getDefault()) }
    Surface(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Run Summary", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                StatusBadge(status = run.status)
            }
            Spacer(modifier = Modifier.height(8.dp))
            DetailRow("Started", dateFormat.format(Date(run.startedAt)))
            run.completedAt?.let { completed ->
                DetailRow("Completed", dateFormat.format(Date(completed)))
                DetailRow("Duration", "${"%.1f".format((completed - run.startedAt) / 1000.0)}s")
            }
            DetailRow("Results", "${run.results.size} scenarios")
            DetailRow("Device", run.deviceInfo.modelName)
            DetailRow("OS", run.deviceInfo.osVersion)
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
    }
}
```

**CategoryResultsSection** — Groups results under a category header:
```kotlin
@Composable
private fun CategoryResultsSection(category: BenchmarkCategory, results: List<BenchmarkResult>) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = categoryIcon(category),
                contentDescription = null,
                tint = AppColors.primaryAccent,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = category.displayName,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        results.forEach { result ->
            BenchmarkResultCard(result = result)
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}
```

**BenchmarkResultCard** — Individual result with per-component metrics:
```kotlin
@Composable
private fun BenchmarkResultCard(result: BenchmarkResult) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Scenario name + model name
            Text(
                text = result.scenarioName,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "${result.componentModelInfo.modelName} (${result.componentModelInfo.framework})",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Framework badge
            Spacer(modifier = Modifier.height(4.dp))
            Surface(
                shape = RoundedCornerShape(4.dp),
                color = AppColors.frameworkBadgeColor(result.componentModelInfo.framework),
            ) {
                Text(
                    text = result.componentModelInfo.framework,
                    style = MaterialTheme.typography.labelSmall,
                    color = AppColors.frameworkTextColor(result.componentModelInfo.framework),
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }

            result.componentModelInfo.formatOrQuantization?.let { format ->
                Text(
                    text = "Format: $format",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(8.dp))

            // Metrics — display based on category
            val m = result.metrics
            m.loadTimeMs?.let { MetricRow("Load Time", "${"%.0f".format(it)} ms") }
            m.warmupTimeMs?.let { MetricRow("Warmup", "${"%.0f".format(it)} ms") }
            m.timeToFirstTokenMs?.let { MetricRow("Time to First Token", "${"%.0f".format(it)} ms") }
            m.tokensPerSecond?.let { MetricRow("Tokens/sec", "${"%.1f".format(it)}") }
            MetricRow("E2E Latency", "${"%.0f".format(m.endToEndLatencyMs)} ms")
            m.inputTokens?.let { MetricRow("Input Tokens", "$it") }
            m.outputTokens?.let { MetricRow("Output Tokens", "$it") }
            m.sttTranscriptionTimeMs?.let { MetricRow("Transcription Time", "${"%.0f".format(it)} ms") }
            m.ttsSynthesisTimeMs?.let { MetricRow("Synthesis Time", "${"%.0f".format(it)} ms") }
            m.vlmDescriptionTimeMs?.let { MetricRow("VLM Time", "${"%.0f".format(it)} ms") }
            m.imageGenerationTimeMs?.let { MetricRow("Generation Time", "${"%.0f".format(it)} ms") }
            m.peakMemoryDeltaBytes?.let { MetricRow("Memory Delta", "${it / 1_048_576} MB") }

            // Error
            m.error?.let { error ->
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "ERROR: $error",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.primaryRed,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}

@Composable
private fun MetricRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 1.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium)
    }
}
```

**DetailExportMenu** — Overflow menu with all export actions:
```kotlin
@Composable
private fun DetailExportMenu(
    run: BenchmarkRun,
    viewModel: BenchmarkViewModel,
    context: Context,
) {
    var showMenu by remember { mutableStateOf(false) }
    IconButton(onClick = { showMenu = true }) {
        Icon(Icons.Default.MoreVert, contentDescription = "Export options")
    }
    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
        DropdownMenuItem(
            text = { Text("Copy Markdown Report") },
            leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
            onClick = { viewModel.copyReportToClipboard(run); showMenu = false },
        )
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text("Share JSON") },
            leadingIcon = { Icon(Icons.Outlined.Share, null) },
            onClick = {
                context.startActivity(Intent.createChooser(
                    viewModel.createShareIntent(run, ExportFormat.JSON), "Share JSON"
                ))
                showMenu = false
            },
        )
        DropdownMenuItem(
            text = { Text("Share CSV") },
            leadingIcon = { Icon(Icons.Outlined.Share, null) },
            onClick = {
                context.startActivity(Intent.createChooser(
                    viewModel.createShareIntent(run, ExportFormat.CSV), "Share CSV"
                ))
                showMenu = false
            },
        )
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text("Save JSON to Downloads") },
            leadingIcon = { Icon(Icons.Outlined.SaveAlt, null) },
            onClick = { viewModel.saveToDevice(run, ExportFormat.JSON); showMenu = false },
        )
        DropdownMenuItem(
            text = { Text("Save CSV to Downloads") },
            leadingIcon = { Icon(Icons.Outlined.SaveAlt, null) },
            onClick = { viewModel.saveToDevice(run, ExportFormat.CSV); showMenu = false },
        )
    }
}
```

#### 3.12.3 BenchmarkProgressOverlay

**File**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/benchmarks/BenchmarkProgressOverlay.kt`

```kotlin
@Composable
fun BenchmarkProgressOverlay(
    currentScenario: String,
    progress: Float,
    completedCount: Int,
    totalCount: Int,
    onCancel: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(12.dp),
        color = AppColors.primaryAccent.copy(alpha = 0.08f),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Running Benchmarks",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
                color = AppColors.primaryAccent,
                trackColor = AppColors.primaryAccent.copy(alpha = 0.15f),
            )
            Text(
                text = currentScenario,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                textAlign = TextAlign.Center,
            )
            Text(
                text = "$completedCount / $totalCount",
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedButton(
                onClick = onCancel,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.primaryRed),
            ) {
                Text("Cancel")
            }
        }
    }
}
```

### 3.13 FileProvider Configuration

The Android example app does **NOT** currently have a `FileProvider` configured. The `AndroidManifest.xml` has no `<provider>` element, and `res/xml/` contains only `backup_rules.xml` and `data_extraction_rules.xml`. You **MUST** add both files below:

**File**: `examples/android/RunAnywhereAI/app/src/main/res/xml/file_paths.xml`
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="benchmark_exports" path="." />
</paths>
```

**In** `AndroidManifest.xml` (inside `<application>` tag, if not already present):
```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

### 3.14 Threading & Coroutine Strategy

| Operation | Dispatcher | Reason |
|-----------|-----------|--------|
| UI state updates | Main (viewModelScope default) | Compose state must be updated on Main |
| `BenchmarkRunner.runBenchmarks()` | `Dispatchers.IO` | Model loading/inference is blocking I/O |
| `onProgress` callback | Main (via `_uiState.update`) | StateFlow update is thread-safe |
| File I/O (BenchmarkStore, export) | `Dispatchers.IO` | File system operations |
| `MediaStore` writes | `Dispatchers.IO` | ContentResolver operations |

All SDK calls (`RunAnywhere.loadLLMModel()`, `RunAnywhere.generate()`, etc.) are `suspend` functions that internally dispatch to native code via JNI. The `Dispatchers.IO` wrapper ensures the coroutine doesn't block the Main thread.

### 3.15 Extensibility

Adding a new benchmark component (e.g., VLM, Diffusion) requires only:

1. **New enum case** in `BenchmarkCategory` (already includes `VLM` and `DIFFUSION`)
2. **New provider file** implementing `BenchmarkScenarioProvider` (e.g., `VLMBenchmarkProvider.kt`)
3. **One line** in `BenchmarkRunner.providers` map:
   ```kotlin
   BenchmarkCategory.VLM to VLMBenchmarkProvider(),
   ```
4. **One FilterChip** added to the category chips list in `BenchmarkDashboardScreen`

No other code changes required.

### 3.16 Design System Compliance (Android)

Use the existing design tokens throughout (from `AppColors.kt`, `AppSpacing.kt`, `Dimensions.kt`, `Type.kt`):

- **Colors**: `AppColors.primaryAccent` (`#FF5500` orange), `AppColors.primaryRed` (`#EF4444`), `AppColors.primaryGreen` (`#10B981`), `AppColors.primaryOrange` (`#FF5500`), `AppColors.primaryBlue` (`#3B82F6`), `AppColors.frameworkBadgeColor(framework)`, `AppColors.frameworkTextColor(framework)`
- **Typography**: `MaterialTheme.typography.titleSmall` for section headers, `bodyMedium` for content, `bodySmall` for secondary text, `labelSmall` for badges. Use `FontFamily.Monospace` for metric values. Use `FontWeight.SemiBold` for headers and `FontWeight.Medium` for emphasis. Custom styles available: `AppTypography.caption` (12.sp), `AppTypography.monospacedCaption` (9.sp bold mono).
- **Spacing**: Prefer `AppSpacing` tokens — `AppSpacing.large` (16.dp) for horizontal screen padding, `AppSpacing.small` (8.dp) between items, `AppSpacing.medium` (12.dp) for internal card padding, `AppSpacing.settingsSectionSpacing` (24.dp) between sections. Raw dp values are acceptable when there's no token match.
- **Corner radius**: `AppSpacing.cornerRadiusMedium` (12.dp) for cards/sections, `AppSpacing.cornerRadiusSmall` (8.dp) for buttons/badges, `Dimensions.cornerRadiusSmall` (4.dp) for small badges. Note: `AppSpacing` and `Dimensions` have overlapping names — use either consistently.
- **Shapes**: `RoundedCornerShape(12.dp)` for cards/sections, `RoundedCornerShape(8.dp)` for buttons/badges, `RoundedCornerShape(4.dp)` for small badges
- **Surfaces**: Use `MaterialTheme.colorScheme.surfaceVariant` as card background. Follow existing `SettingsSection` composable pattern (declared at `SettingsScreen.kt:335–372`).
- **Reference files**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/theme/` (contains `AppColors.kt`, `AppSpacing.kt`, `Dimensions.kt`, `Type.kt`)

### 3.17 Model Requirements & Pre-flight Check (Android)

**minSdk note**: The app targets `minSdk = 24` (Android 7.0). The `MediaStore.Downloads` API used for saving reports requires API 29+ (Android 10). A legacy fallback using `Environment.getExternalStoragePublicDirectory()` is provided in `BenchmarkReportFormatter.saveToDownloads()` for API 24–28. All other benchmark features (running, persistence, clipboard, sharing) work on all supported API levels.

Before running benchmarks for a category, the runner checks which models are downloaded:
```kotlin
val allModels = RunAnywhere.availableModels()
val downloadedLLMs = allModels.filter { it.category == ModelCategory.LANGUAGE && it.isDownloaded }
```

The UI shows which categories have models available. Categories with no downloaded models are skipped during execution (not an error). The `BenchmarkDashboardScreen` should show a hint message when no models are available:

```kotlin
// In CategoryFilterChips, show a note if a selected category has no downloaded models
if (selectedCategories.isNotEmpty()) {
    // This check happens at run time in BenchmarkRunner.runBenchmarks()
    // Categories with no models are silently skipped
    // The UI can optionally show: "Download models from Settings to benchmark them"
}
```

### 3.18 Required Imports Summary

**BenchmarkDashboardScreen.kt** key imports:
```kotlin
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.domain.models.*
import com.runanywhere.runanywhereai.ui.theme.AppColors
```

**BenchmarkReportFormatter.kt** additional imports (for JSON export with ISO8601 timestamps):
```kotlin
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.addJsonObject
```

**BenchmarkDetailScreen.kt** additional imports:
```kotlin
import android.content.Context
import android.content.Intent
import androidx.compose.ui.text.font.FontFamily
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
```

**BenchmarkViewModel.kt** key imports:
```kotlin
import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
```

### 3.19 Implementation Checklist (Android)

Follow this order to minimize compilation errors and enable incremental testing:

| Step | What | Section | Files Created/Modified |
|------|------|---------|----------------------|
| 1 | Add `lifecycle-runtime-compose` dependency | 3.10 note | `gradle/libs.versions.toml` + `app/build.gradle.kts` |
| 2 | Create data models | 3.3 | `domain/models/BenchmarkModels.kt` |
| 3 | Create scenario provider interface | 3.4 | `providers/BenchmarkScenarioProvider.kt` |
| 4 | Create synthetic input generator | 3.8 | `SyntheticInputGenerator.kt` |
| 5 | Create LLM provider | 3.6.1 | `providers/LLMBenchmarkProvider.kt` |
| 6 | Create STT provider | 3.6.2 | `providers/STTBenchmarkProvider.kt` |
| 7 | Create TTS provider | 3.6.3 | `providers/TTSBenchmarkProvider.kt` |
| 8 | Create benchmark runner | 3.7 | `BenchmarkRunner.kt` |
| 9 | Create benchmark store | 3.9 | `data/BenchmarkStore.kt` |
| 10 | Create report formatter | 3.11 | `BenchmarkReportFormatter.kt` |
| 11 | Create progress overlay | 3.12.3 | `BenchmarkProgressOverlay.kt` |
| 12 | Create ViewModel | 3.10 | `BenchmarkViewModel.kt` |
| 13 | Create dashboard screen | 3.12.1 | `BenchmarkDashboardScreen.kt` |
| 14 | Create detail screen | 3.12.2 | `BenchmarkDetailScreen.kt` |
| 15 | Add FileProvider config | 3.13 | `res/xml/file_paths.xml` + `AndroidManifest.xml` |
| 16 | Add navigation routes | 3.2.1 | `AppNavigation.kt` (modify) |
| 17 | Add Settings entry point | 3.2.2 | `SettingsScreen.kt` (modify) |
| 18 | Build & test | 5.2 | — |

**Total: 12 new files, 5 modified files** (gradle/libs.versions.toml, app/build.gradle.kts, AndroidManifest.xml, AppNavigation.kt, SettingsScreen.kt)

---

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

### Android-Specific Functional

- [ ] **AC-27**: Settings screen has "Performance" section with a "Benchmarks" clickable row that navigates to BenchmarkDashboardScreen
- [ ] **AC-28**: Navigation uses Compose NavHost with `NavigationRoute.BENCHMARKS` and `NavigationRoute.BENCHMARK_DETAIL` routes
- [ ] **AC-29**: "Share" uses Android `Intent.ACTION_SEND` with `FileProvider` URI for JSON/CSV files
- [ ] **AC-30**: "Save to Downloads" uses `MediaStore.Downloads` on API 29+ with fallback for older APIs
- [ ] **AC-31**: "Copy Report" uses `ClipboardManager.setPrimaryClip()` with `Toast` confirmation
- [ ] **AC-32**: `BenchmarkViewModel` extends `AndroidViewModel` with `StateFlow<BenchmarkUiState>` pattern
- [ ] **AC-33**: Heavy benchmark work runs on `Dispatchers.IO`, UI updates on Main thread via `StateFlow.update`
- [ ] **AC-34**: `FileProvider` is configured in `AndroidManifest.xml` with `file_paths.xml` for cache-path sharing
- [ ] **AC-35**: `BenchmarkDeviceInfo.fromSystem(context)` uses `Build.MODEL`, `Build.HARDWARE`, `ActivityManager.MemoryInfo`
- [ ] **AC-36**: Memory measurement uses `Debug.getNativeHeapAllocatedSize()` (not `ActivityManager.getMemoryInfo()`)

### iOS-Specific Functional

- [ ] **AC-37**: Uses `@Observable` (not `ObservableObject`) for the ViewModel
- [ ] **AC-38**: All types are `Codable` and `Sendable`
- [ ] **AC-39**: Only files created are in `Features/Benchmarks/` plus minimal wiring in `CombinedSettingsView.swift`
- [ ] **AC-40**: VLM benchmarks use `VLMImage(image:)` with synthetic `UIImage` from `UIGraphicsImageRenderer`
- [ ] **AC-41**: Diffusion benchmarks use `model.localPath!.path` for loading via `loadDiffusionModel(modelPath:)`
- [ ] **AC-42**: Haptic feedback fires via `UINotificationFeedbackGenerator` on copy/save actions

### Non-Functional (Both Platforms)

- [ ] **AC-43**: Strong typing everywhere — no raw strings for categories, statuses, or metrics keys
- [ ] **AC-44**: Follows existing design system (AppColors, AppTypography, AppSpacing) on each platform
- [ ] **AC-45**: Adding a new benchmark component requires only: (a) new enum case, (b) new provider file, (c) one registration line in `BenchmarkRunner`
- [ ] **AC-46**: No new external dependencies — only SDK APIs and platform frameworks

---

## 5. Manual Test Plan

### 5.1 iOS Prerequisites

1. Open `examples/ios/RunAnywhereAI/` in Xcode
2. Select iPhone 16 Pro Simulator (iOS 17+)
3. Build and run (`Cmd+R`)
4. Go to Settings, download at least **SmolLM2-360M** (smallest LLM, model ID `smollm2-360m-instruct-q8`)
5. Optionally download: Whisper Tiny (STT), Piper TTS US English (TTS), SmolVLM 500M (VLM), a diffusion model

### 5.2 Android Prerequisites

1. Open `examples/android/RunAnywhereAI/` in Android Studio
2. Select a physical device or emulator (API 29+, arm64 recommended for model inference)
3. Build and run
4. Go to Settings, download at least **SmolLM2-360M** (smallest LLM)
5. Optionally download: Whisper Tiny (STT), Piper TTS (TTS)

### 5.3 Cross-Platform Test Cases

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| T1 | Navigate to Benchmarks | Settings tab → tap "Benchmarks" | Dashboard visible with device info, empty run list |
| T2 | No models warning | Ensure no models downloaded → tap "Run All" | Shows empty message or skips all categories gracefully — no crash |
| T3 | Run All (LLM only) | Download SmolLM2 → Run All | Progress UI appears, shows each LLM scenario. On completion, run appears in history. |
| T4 | Cancel mid-run | Start Run All → wait 1 scenario → Cancel | Run stops. Partial results saved with status "cancelled". |
| T5 | View run detail | Tap a completed run | Detail view shows results grouped by category with all metrics. Model info (name, framework, quantization) shown. |
| T6 | Run single category | Toggle only "LLM" → "Run Selected" | Only LLM scenarios execute |
| T7 | Copy report | Complete a run → "Copy Report" | Clipboard contains Markdown text with device info and metrics |
| T8 | Export JSON | Complete a run → Share → JSON | Share sheet (iOS) / share chooser (Android) with .json file. File is valid JSON matching schema. |
| T9 | Export CSV | Complete a run → Share → CSV | Share sheet (iOS) / share chooser (Android) with .csv file. CSV has correct headers and data. |
| T10 | Persistence | Complete a run → force-quit → reopen → Benchmarks | Previous runs still visible |
| T11 | Clear All | "Clear All" → confirm | History empty |
| T12 | Multiple models | Download SmolLM2 + Qwen 0.5B → Run All | Both models benchmarked in same run |
| T13 | STT benchmark | Download Whisper → Run Category: STT | STT scenarios with synthetic audio execute, transcription time captured |
| T14 | TTS benchmark | Download Piper → Run Category: TTS | TTS scenarios execute, synthesis time captured |
| T15 | VLM benchmark (iOS only) | Download SmolVLM → Run Category: VLM | VLM scenario runs with synthetic test image |
| T16 | Diffusion benchmark (iOS only) | Download SD model → Run Category: Diffusion | Generation benchmark runs (may take minutes) |
| T17 | Memory delta | View any completed result detail | Memory delta field shows a positive value |
| T18 | App responsiveness | During benchmark, switch to Chat tab and back | App stays responsive, benchmark continues |
| T19 | Error handling | Delete model files on disk → run benchmark | Error recorded for that model, other models still run |
| T20 | Report contains model info | View/copy any report | Report includes modelId, modelName, framework, quantization for each result |

### 5.4 iOS-Specific Test Cases

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| T21 | Save to Files | Complete a run → Menu → "Save JSON to Files" | File saved to Documents. Confirmation shows filename. File readable via Files app. |
| T22 | Haptic feedback | Copy report or save to files on physical device | Haptic success feedback fires on copy/save |
| T23 | macOS Benchmarks card | Run on macOS → Settings → Benchmarks card | "Open Benchmarks" button shows sheet with BenchmarkDashboardView |

### 5.5 Android-Specific Test Cases

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| T24 | Save to Downloads | Complete a run → overflow menu → "Save JSON to Downloads" | Toast shows "Saved: benchmark_xxx.json". File appears in device Downloads folder. |
| T25 | Share Intent | Complete a run → overflow menu → "Share JSON" | Android share chooser appears with JSON file attachment. Sharing to email/Files/Drive works. |
| T26 | Share CSV | Complete a run → overflow menu → "Share CSV" | Android share chooser appears with CSV file attachment. |
| T27 | Toast on copy | Complete a run → overflow menu → "Copy Markdown Report" | Toast shows "Copied to clipboard". Paste in Notes/etc shows Markdown report. |
| T28 | Back navigation | Benchmarks Dashboard → tap a run → press back → press back | Returns to Settings. No crash, proper back stack behavior. |
| T29 | Screen rotation | Start a benchmark run → rotate device | Progress continues without restart. StateFlow preserves state across config changes. |
| T30 | API 29+ Downloads | Test on Android 10+ device | `MediaStore.Downloads` used. File visible in Downloads app without storage permission. |
| T31 | FileProvider URI | Share a file → check receiving app | Receiving app can read the file. `FLAG_GRANT_READ_URI_PERMISSION` set correctly. |

### 5.6 Validation Checks

1. Tokens/sec in benchmark results should be within 20% of values shown in Chat analytics
2. Memory delta values are positive and in a reasonable range (10MB–4GB)
3. JSON field names match between iOS and Android exports (same schema from section 1.4)
4. No crashes when all categories are empty (no models downloaded)
5. Benchmark runs complete even if one model fails (error is captured, run continues)
6. **Android**: `benchmarks.json` is stored in `context.filesDir` (not external storage)
7. **Android**: `FileProvider` URI grants read access correctly — no `FileUriExposedException`
8. **iOS/Android**: CSV headers match exactly between both platforms

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

## Appendix B: iOS SDK API Differences Summary

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

## Appendix B2: Android/KMP SDK API Differences Summary

| Component | Load Method | Load Argument | Unload Method |
|-----------|-------------|---------------|---------------|
| LLM | `RunAnywhere.loadLLMModel(modelId)` | `model.id` (String) | `RunAnywhere.unloadLLMModel()` |
| STT | `RunAnywhere.loadSTTModel(modelId)` | `model.id` (String) | `RunAnywhere.unloadSTTModel()` |
| TTS | `RunAnywhere.loadTTSVoice(voiceId)` | `model.id` (String) | `RunAnywhere.unloadTTSVoice()` |

**Key differences from iOS**:
- LLM load: `loadLLMModel(modelId)` on Android vs `loadModel(modelId)` on iOS (different method name)
- LLM unload: `unloadLLMModel()` on Android vs `unloadModel()` on iOS
- TTS load: `loadTTSVoice(voiceId)` on both (same!)
- TTS unload: `unloadTTSVoice()` on both (same!)
- STT: Identical names on both platforms
- Generation: `generate()` on Android vs `generate()` on iOS (same); streaming is `generateStreamWithMetrics()` on Android (returns `Flow<String>` + `Deferred<LLMGenerationResult>`) vs `generateStream()` on iOS (returns `AsyncThrowingStream<String>` + `Task<LLMGenerationResult>`)
- VLM/Diffusion: Not yet available in Android benchmarks (future extensibility)

## Appendix B3: Key Android File References

| File | Purpose | Path |
|------|---------|------|
| App navigation | 5-tab NavHost + routes | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/navigation/AppNavigation.kt` |
| Settings screen | Form with sections | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/settings/SettingsScreen.kt` |
| Settings VM | Storage, API config | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/settings/SettingsViewModel.kt` |
| Chat ViewModel | Generation reference | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/chat/ChatViewModel.kt` |
| Chat models | MessageAnalytics, etc. | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/domain/models/ChatMessage.kt` |
| STT screen | STT usage reference | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/stt/SpeechToTextScreen.kt` |
| TTS screen | TTS usage reference | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/tts/TextToSpeechScreen.kt` |
| Theme colors | AppColors object | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/theme/AppColors.kt` |
| Theme spacing | AppSpacing object | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/theme/AppSpacing.kt` |
| Theme dimensions | Dimensions object (paddings, radii, icon sizes) | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/theme/Dimensions.kt` |
| Theme typography | Typography config + AppTypography | `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/theme/Type.kt` |
| Version catalog | Dependency versions (lifecycle, etc.) | `gradle/libs.versions.toml` (shared; referenced via `settings.gradle.kts` line 24) |
| Build config | Dependencies, SDK | `examples/android/RunAnywhereAI/app/build.gradle.kts` |
| Manifest | FileProvider registration | `examples/android/RunAnywhereAI/app/src/main/AndroidManifest.xml` |
| KMP LLM API | generate/generateStream | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+TextGeneration.kt` |
| KMP LLM types | LLMGenerationResult, Options | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/LLM/LLMTypes.kt` |
| KMP STT API | transcribe/transcribeWithOptions | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+STT.kt` |
| KMP STT types | STTOutput, Metadata | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/STT/STTTypes.kt` |
| KMP TTS API | synthesize/speak | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+TTS.kt` |
| KMP TTS types | TTSOutput, Metadata | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/TTS/TTSTypes.kt` |
| KMP Model mgmt | loadLLMModel, loadSTTModel, etc | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+ModelManagement.kt` |
| KMP Model types | ModelInfo, ModelCategory | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/Models/ModelTypes.kt` |
| KMP DeviceInfo | Device info model | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/models/DeviceInfo.kt` |

## Appendix C: Verified iOS Design Token Values

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

## Appendix D: Verified Android Design Token Values

| Token | Value | Source |
|-------|-------|--------|
| `AppColors.primaryAccent` | `Color(0xFFFF5500)` | `AppColors.kt:19` |
| `AppColors.primaryOrange` | `Color(0xFFFF5500)` (same as accent) | `AppColors.kt:20` |
| `AppColors.primaryGreen` | `Color(0xFF10B981)` (Emerald-500) | `AppColors.kt:22` |
| `AppColors.primaryRed` | `Color(0xFFEF4444)` (Red-500) | `AppColors.kt:23` |
| `AppColors.primaryBlue` | `Color(0xFF3B82F6)` | `AppColors.kt:24` |
| `AppColors.statusGreen` | = `primaryGreen` | `AppColors.kt:107` |
| `AppColors.statusOrange` | = `primaryOrange` | `AppColors.kt:108` |
| `AppColors.statusRed` | = `primaryRed` | `AppColors.kt:109` |
| `AppColors.frameworkBadgeColor(fw)` | Varies by framework; LlamaCpp = accent 20% | `AppColors.kt:245` |
| `AppColors.frameworkTextColor(fw)` | Varies by framework; LlamaCpp = accent | `AppColors.kt:258` |
| `RoundedCornerShape(12.dp)` | Card/section rounding | `SettingsScreen.kt:363` |
| `RoundedCornerShape(8.dp)` | Button/badge rounding | `SettingsScreen.kt:491` |
| `RoundedCornerShape(4.dp)` | Small badge/chip rounding | Used for status badges |
| `AppSpacing.large` / `16.dp` | Horizontal screen padding | `AppSpacing.kt:22`, `SettingsScreen.kt:346` |
| `AppSpacing.small` / `8.dp` | Between-item spacing | `AppSpacing.kt:16`, `SettingsScreen.kt:360` |
| `AppSpacing.medium` / `12.dp` | Internal card padding | `AppSpacing.kt:18`, `SettingsScreen.kt:495` |
| `AppSpacing.settingsSectionSpacing` / `24.dp` | Between-section spacing | `AppSpacing.kt:75` |
| `AppSpacing.cornerRadiusSmall` / `8.dp` | Small corner radius | `AppSpacing.kt:33` |
| `AppSpacing.cornerRadiusMedium` / `12.dp` | Medium corner radius (cards) | `AppSpacing.kt:34` |
| `MaterialTheme.typography.titleSmall` | Section headers | `SettingsScreen.kt:353` |
| `MaterialTheme.typography.bodyMedium` | Content text | `SettingsScreen.kt:435` |
| `MaterialTheme.typography.bodySmall` | Secondary/detail text | `SettingsScreen.kt:440` |
| `MaterialTheme.typography.labelSmall` | Badge text | Material 3 default |
| `FontWeight.SemiBold` | Section title weight | `SettingsScreen.kt:354` |
| `FontWeight.Medium` | Emphasis weight | `SettingsScreen.kt:436` |
| `FontFamily.Monospace` | Metric values | Kotlin standard |
| `AppTypography.caption` | 12.sp regular caption | `Type.kt:204` |
| `AppTypography.monospacedCaption` | 9.sp bold monospace | `Type.kt:233` |

## Appendix E: Android SettingsScreen Insertion Points

Exact line numbers for modifying `SettingsScreen.kt` (verified against current source):

```
Line  45: fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
Line  78:   SettingsSection(title = "API Configuration (Testing)") {
Line 119:   ToolSettingsSection()
Line 122:   SettingsSection(title = "Storage Overview", ...) {
Line 158:   SettingsSection(title = "Downloaded Models") {
Line 180:   SettingsSection(title = "Storage Management") {
Line 195:   }  // <-- END of Storage Management section
Line 196:   // ← INSERT NEW "Performance" SECTION HERE
Line 197:
Line 198:   SettingsSection(title = "About") {
Line 260:   Spacer(modifier = Modifier.height(32.dp))
```

**Step 1**: Change line 45 signature to:
```kotlin
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel(),
    onNavigateToBenchmarks: () -> Unit = {},
)
```

**Step 2**: Insert at line 196 (between Storage Management and About):
```kotlin
        // Performance Section
        SettingsSection(title = "Performance") {
            Surface(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onNavigateToBenchmarks),
                shape = RoundedCornerShape(8.dp),
                color = AppColors.primaryAccent.copy(alpha = 0.1f),
            ) { /* ... see section 3.2.2 for full content */ }
        }
```

**Step 3**: In `AppNavigation.kt`, wire the callback:
```kotlin
composable(NavigationRoute.SETTINGS) {
    SettingsScreen(
        onNavigateToBenchmarks = { navController.navigate(NavigationRoute.BENCHMARKS) }
    )
}
```

**Reference — `SettingsSection` composable** (lines 335–372, private in `SettingsScreen.kt`):
```kotlin
@Composable
private fun SettingsSection(
    title: String,
    trailing: @Composable (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
)
```
This wraps content in a `Surface` with `RoundedCornerShape(12.dp)` + `surfaceVariant` background. Title uses `MaterialTheme.typography.titleSmall` + `FontWeight.SemiBold`.

**Reference — Current `AppNavigation.kt` SettingsScreen wiring** (lines 66–68):
```kotlin
composable(NavigationRoute.SETTINGS) {
    SettingsScreen()
}
```
This must be updated to pass `onNavigateToBenchmarks` callback (see section 3.2.2 Step 2).

**Reference — Current `NavigationRoute` object** (lines 172–178):
```kotlin
object NavigationRoute {
    const val CHAT = "chat"
    const val STT = "stt"
    const val TTS = "tts"
    const val VOICE = "voice"
    const val SETTINGS = "settings"
}
```
Add `BENCHMARKS` and `BENCHMARK_DETAIL` constants (see section 3.2.1).
