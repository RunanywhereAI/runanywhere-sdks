//
//  BenchmarkRunner.swift
//  RunAnywhere SDK
//
//  Protocol defining benchmark execution capabilities
//

import Foundation

/// Protocol for benchmark execution
public protocol BenchmarkRunner {
    /// Whether a benchmark is currently running
    var isRunning: Bool { get }

    /// Current benchmark progress (0.0 to 1.0)
    var currentProgress: Double { get }

    /// Current benchmark being executed
    var currentBenchmark: String { get }

    /// Run a full benchmark suite
    func runFullBenchmark(
        services: [String: LLMService],
        options: BenchmarkOptions,
        prompts: [BenchmarkPrompt]?
    ) async throws -> BenchmarkReport

    /// Run a quick benchmark for a single service
    func runQuickBenchmark(
        service: LLMService,
        serviceName: String
    ) async throws -> QuickBenchmarkResult

    /// Compare two services head-to-head
    func compareServices(
        _ service1: LLMService,
        service1Name: String,
        _ service2: LLMService,
        service2Name: String,
        prompt: String?
    ) async throws -> ComparisonResult
}
