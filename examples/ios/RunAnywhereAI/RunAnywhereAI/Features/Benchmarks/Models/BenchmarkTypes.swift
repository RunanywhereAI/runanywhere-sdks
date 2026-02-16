//
//  BenchmarkTypes.swift
//  RunAnywhereAI
//
//  Data models for the benchmarking suite.
//

import Foundation
import RunAnywhere

// MARK: - Benchmark Category

enum BenchmarkCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case llm
    case stt
    case tts
    case vlm
    case diffusion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .llm: return "LLM"
        case .stt: return "STT"
        case .tts: return "TTS"
        case .vlm: return "VLM"
        case .diffusion: return "Diffusion"
        }
    }

    var iconName: String {
        switch self {
        case .llm: return "text.bubble"
        case .stt: return "waveform"
        case .tts: return "speaker.wave.3"
        case .vlm: return "eye"
        case .diffusion: return "paintbrush"
        }
    }

    var modelCategory: ModelCategory {
        switch self {
        case .llm: return .language
        case .stt: return .speechRecognition
        case .tts: return .speechSynthesis
        case .vlm: return .multimodal
        case .diffusion: return .imageGeneration
        }
    }
}

// MARK: - Benchmark Run Status

enum BenchmarkRunStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

// MARK: - Benchmark Scenario

struct BenchmarkScenario: Codable, Sendable, Identifiable {
    let name: String
    let category: BenchmarkCategory

    var id: String { "\(category.rawValue)_\(name)" }
}

// MARK: - Component Model Info (snapshot of ModelInfo for persistence)

struct ComponentModelInfo: Codable, Sendable {
    let id: String
    let name: String
    let framework: String
    let category: String

    init(from model: ModelInfo) {
        self.id = model.id
        self.name = model.name
        self.framework = model.framework.displayName
        self.category = model.category.rawValue
    }
}

// MARK: - Device Info (snapshot for persistence)

struct BenchmarkDeviceInfo: Codable, Sendable {
    let modelName: String
    let chipName: String
    let totalMemoryBytes: Int64
    let availableMemoryBytes: Int64
    let osVersion: String

    static func fromSystem(_ info: SystemDeviceInfo) -> BenchmarkDeviceInfo {
        BenchmarkDeviceInfo(
            modelName: info.modelName,
            chipName: info.chipName,
            totalMemoryBytes: info.totalMemory,
            availableMemoryBytes: Int64(SyntheticInputGenerator.availableMemoryBytes()),
            osVersion: info.osVersion
        )
    }
}

// MARK: - Benchmark Metrics

struct BenchmarkMetrics: Codable, Sendable {
    // Common
    var endToEndLatencyMs: Double = 0
    var loadTimeMs: Double = 0
    var warmupTimeMs: Double = 0
    var memoryDeltaBytes: Int64 = 0

    // LLM-specific
    var ttftMs: Double?
    var tokensPerSecond: Double?
    var inputTokens: Int?
    var outputTokens: Int?

    // STT-specific
    var audioLengthSeconds: Double?
    var realTimeFactor: Double?

    // TTS-specific
    var audioDurationSeconds: Double?
    var charactersProcessed: Int?

    // VLM-specific
    var promptTokens: Int?
    var completionTokens: Int?

    // Diffusion-specific
    var generationTimeMs: Double?

    // Error info
    var errorMessage: String?
    var didSucceed: Bool { errorMessage == nil }
}

// MARK: - Benchmark Result

struct BenchmarkResult: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let category: BenchmarkCategory
    let scenario: BenchmarkScenario
    let modelInfo: ComponentModelInfo
    let metrics: BenchmarkMetrics

    init(
        category: BenchmarkCategory,
        scenario: BenchmarkScenario,
        modelInfo: ComponentModelInfo,
        metrics: BenchmarkMetrics
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.scenario = scenario
        self.modelInfo = modelInfo
        self.metrics = metrics
    }
}

// MARK: - Benchmark Run

struct BenchmarkRun: Codable, Sendable, Identifiable {
    let id: UUID
    let startedAt: Date
    var completedAt: Date?
    var results: [BenchmarkResult]
    var status: BenchmarkRunStatus
    let deviceInfo: BenchmarkDeviceInfo

    var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    init(deviceInfo: BenchmarkDeviceInfo) {
        self.id = UUID()
        self.startedAt = Date()
        self.results = []
        self.status = .running
        self.deviceInfo = deviceInfo
    }
}

// MARK: - Progress Update

struct BenchmarkProgressUpdate: Sendable {
    let completedCount: Int
    let totalCount: Int
    let currentScenario: String
    let currentModel: String

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}
