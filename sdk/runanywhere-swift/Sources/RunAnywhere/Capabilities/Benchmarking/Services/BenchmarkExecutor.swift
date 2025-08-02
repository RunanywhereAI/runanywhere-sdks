//
//  BenchmarkExecutor.swift
//  RunAnywhere SDK
//
//  Executes individual benchmark runs
//

import Foundation

/// Executes individual benchmark runs
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public class BenchmarkExecutor {
    // MARK: - Properties

    private let performanceMonitor: PerformanceMonitor
    private let memoryTracker = MemoryTracker()
    private let logger = SDKLogger(category: "BenchmarkExecutor")

    // MARK: - Initialization

    public init(performanceMonitor: PerformanceMonitor) {
        self.performanceMonitor = performanceMonitor
    }

    // MARK: - Public Methods

    /// Warmup a service before benchmarking
    public func warmupService(_ service: LLMService, name: String) async throws {
        logger.debug("Warming up \(name)")

        _ = try await service.generate(
            prompt: "Hello",
            options: GenerationOptions(maxTokens: 5, temperature: 0.1)
        )
    }

    /// Benchmark a single prompt with multiple iterations
    public func benchmarkPrompt(
        service: LLMService,
        serviceName: String,
        prompt: BenchmarkPrompt,
        iterations: Int
    ) async throws -> [SingleRunResult] {
        var results: [SingleRunResult] = []

        for iteration in 0..<iterations {
            let result = try await benchmarkSingleRun(
                service: service,
                serviceName: serviceName,
                prompt: prompt,
                iteration: iteration
            )
            results.append(result)
        }

        return results
    }

    /// Execute a single benchmark run
    public func benchmarkSingleRun(
        service: LLMService,
        serviceName: String,
        prompt: BenchmarkPrompt,
        iteration: Int
    ) async throws -> SingleRunResult {
        // Track memory before
        let memoryBefore = memoryTracker.getCurrentMemoryUsage()

        // Start timing
        let startTime = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime?
        var tokens: [String] = []

        // Track with performance monitor
        if let modelInfo = service.modelInfo {
            performanceMonitor.beginGeneration(
                framework: modelInfo.framework,
                modelInfo: ModelInfo(
                    id: modelInfo.id,
                    name: modelInfo.name,
                    format: modelInfo.format,
                    estimatedMemory: modelInfo.memoryUsage
                )
            )
        }

        // Execute generation
        try await service.streamGenerate(
            prompt: prompt.text,
            options: GenerationOptions(
                maxTokens: prompt.expectedTokens,
                temperature: 0.7
            )
        ) { token in
            if firstTokenTime == nil {
                firstTokenTime = CFAbsoluteTimeGetCurrent()
            }
            tokens.append(token)
            self.performanceMonitor.recordToken(token)
        }

        // End timing and collect metrics
        let endTime = CFAbsoluteTimeGetCurrent()
        let memoryAfter = memoryTracker.getCurrentMemoryUsage()
        let perfSummary = performanceMonitor.endGeneration()

        return SingleRunResult(
            serviceName: serviceName,
            framework: service.modelInfo?.framework,
            promptId: prompt.id,
            iteration: iteration,
            totalTime: endTime - startTime,
            timeToFirstToken: firstTokenTime.map { $0 - startTime } ?? 0,
            tokensGenerated: tokens.count,
            tokensPerSecond: perfSummary?.tokensPerSecond ?? Double(tokens.count) / (endTime - startTime),
            memoryUsed: memoryAfter - memoryBefore,
            generatedText: tokens.joined()
        )
    }
}
