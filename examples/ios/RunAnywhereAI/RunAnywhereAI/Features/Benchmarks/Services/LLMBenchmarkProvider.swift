//
//  LLMBenchmarkProvider.swift
//  RunAnywhereAI
//
//  Benchmarks LLM generation with short/medium/long token counts.
//

import Foundation
import RunAnywhere

struct LLMBenchmarkProvider: BenchmarkScenarioProvider {

    let category: BenchmarkCategory = .llm

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Short (50 tokens)", category: .llm),
            BenchmarkScenario(name: "Medium (256 tokens)", category: .llm),
            BenchmarkScenario(name: "Long (512 tokens)", category: .llm),
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo
    ) async throws -> BenchmarkMetrics {
        let maxTokens = tokenCount(for: scenario)
        var metrics = BenchmarkMetrics()

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        let loadStart = Date()
        try await RunAnywhere.loadModel(model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        defer { Task { try? await RunAnywhere.unloadModel() } }

        // Warmup: short generate, discard
        let warmupStart = Date()
        let warmupOptions = LLMGenerationOptions(maxTokens: 5, temperature: 0.0)
        let warmupResult = try await RunAnywhere.generateStream("Hello", options: warmupOptions)
        for try await _ in warmupResult.stream {}
        _ = try await warmupResult.result.value
        metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

        // Benchmark
        let benchStart = Date()
        let options = LLMGenerationOptions(maxTokens: maxTokens, temperature: 0.0)
        let streamResult = try await RunAnywhere.generateStream(
            "Explain the concept of machine learning in detail.",
            options: options
        )
        for try await _ in streamResult.stream {}
        let result = try await streamResult.result.value

        metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000
        metrics.ttftMs = result.timeToFirstTokenMs
        metrics.tokensPerSecond = result.tokensPerSecond
        metrics.inputTokens = result.inputTokens
        metrics.outputTokens = result.tokensUsed

        let memAfter = SyntheticInputGenerator.availableMemoryBytes()
        metrics.memoryDeltaBytes = memBefore - memAfter

        return metrics
    }

    private func tokenCount(for scenario: BenchmarkScenario) -> Int {
        if scenario.name.contains("50") { return 50 }
        if scenario.name.contains("256") { return 256 }
        return 512
    }
}
