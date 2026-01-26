//
//  BenchmarkTypes.swift
//  RunAnywhereAI
//
//  Shared types for benchmarking functionality
//

import Foundation

// MARK: - Benchmark Configuration

/// Configuration for benchmark runs
struct BenchmarkConfig: Codable {
    let warmupIterations: Int
    let testIterations: Int
    let maxTokensList: [Int]
    let prompts: [BenchmarkPrompt]
    
    static let `default` = BenchmarkConfig(
        warmupIterations: 3,
        testIterations: 5,
        maxTokensList: [50, 100],
        prompts: BenchmarkPrompt.standardPrompts
    )
    
    static let quick = BenchmarkConfig(
        warmupIterations: 1,
        testIterations: 3,
        maxTokensList: [50],
        prompts: [BenchmarkPrompt.standardPrompts[0]]
    )
    
    static let comprehensive = BenchmarkConfig(
        warmupIterations: 3,
        testIterations: 10,
        maxTokensList: [50, 100, 256],
        prompts: BenchmarkPrompt.standardPrompts
    )
}

/// A benchmark prompt with metadata
struct BenchmarkPrompt: Codable, Identifiable {
    let id: String
    let text: String
    let category: PromptCategory
    let expectedMinTokens: Int
    
    enum PromptCategory: String, Codable {
        case short
        case medium
        case long
        case reasoning
    }
    
    // Standard prompts for benchmarking different capabilities
    // See examples/benchmark-config.json for the full configurable prompt list
    static let standardPrompts: [BenchmarkPrompt] = [
        // Short - Quick responses
        BenchmarkPrompt(
            id: "short-1",
            text: "What is 2+2?",
            category: .short,
            expectedMinTokens: 5
        ),
        // Medium - General explanations
        BenchmarkPrompt(
            id: "medium-1",
            text: "Explain quantum computing in simple terms.",
            category: .medium,
            expectedMinTokens: 50
        ),
        // Reasoning - Math and logic
        BenchmarkPrompt(
            id: "reasoning-1",
            text: "If a train travels at 60 mph for 2.5 hours, how far does it travel? Show your work.",
            category: .reasoning,
            expectedMinTokens: 30
        ),
        // Long - Extended generation (used in comprehensive mode)
        BenchmarkPrompt(
            id: "long-1",
            text: "Write a short story about a robot learning to paint. Include a beginning, middle, and end.",
            category: .long,
            expectedMinTokens: 150
        )
    ]
}

// MARK: - Benchmark Results

/// Result of a single inference run
struct SingleRunResult: Codable {
    let promptId: String
    let maxTokens: Int
    let tokensPerSecond: Double
    let latencyMs: Double
    let ttftMs: Double?
    let outputTokens: Int
    let inputTokens: Int
    let timestamp: Date
}

/// Aggregated benchmark result for a model
struct BenchmarkResult: Codable, Identifiable {
    let id: String
    let modelId: String
    let modelName: String
    let framework: String
    
    // Device info
    let deviceId: String
    let deviceModel: String
    let osVersion: String
    let sdkVersion: String
    let gitCommit: String?
    
    // Timing
    let timestamp: Date
    let modelLoadTimeMs: Double
    
    // Aggregated LLM metrics
    let avgTokensPerSecond: Double
    let p50TokensPerSecond: Double
    let p95TokensPerSecond: Double
    let minTokensPerSecond: Double
    let maxTokensPerSecond: Double
    
    let avgTtftMs: Double
    let p50TtftMs: Double
    let p95TtftMs: Double
    
    let avgLatencyMs: Double
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    
    let peakMemoryBytes: Int64
    let totalRuns: Int
    
    // Per-prompt breakdown
    let promptResults: [PromptAggregatedResult]
    
    // Configuration used
    let config: BenchmarkConfig
}

/// Aggregated results for a specific prompt
struct PromptAggregatedResult: Codable, Identifiable {
    var id: String { promptId }
    let promptId: String
    let promptCategory: String
    let avgTokensPerSecond: Double
    let avgLatencyMs: Double
    let avgTtftMs: Double
    let runCount: Int
}

// MARK: - Benchmark State

/// Current state of benchmark execution
enum BenchmarkState: Equatable {
    case idle
    case preparing
    case warmingUp(model: String, iteration: Int, total: Int)
    case running(model: String, prompt: String, iteration: Int, total: Int)
    case completed
    case failed(error: String)
    
    var isRunning: Bool {
        switch self {
        case .preparing, .warmingUp, .running:
            return true
        default:
            return false
        }
    }
}

/// Progress information for UI
struct BenchmarkProgress {
    let state: BenchmarkState
    let overallProgress: Double
    let currentModelIndex: Int
    let totalModels: Int
    let elapsedTime: TimeInterval
    let estimatedRemainingTime: TimeInterval?
}

// MARK: - Export Format

/// Container for exporting benchmark results
struct BenchmarkExport: Codable {
    let exportVersion: String
    let exportedAt: Date
    let results: [BenchmarkResult]
    
    static let currentVersion = "1.0"
    
    init(results: [BenchmarkResult]) {
        self.exportVersion = Self.currentVersion
        self.exportedAt = Date()
        self.results = results
    }
}
