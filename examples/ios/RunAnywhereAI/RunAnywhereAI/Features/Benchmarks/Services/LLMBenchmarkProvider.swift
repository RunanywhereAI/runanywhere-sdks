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
            BenchmarkScenario(name: "Short (50 tokens)", category: .llm, parameters: ["maxTokens": "50"]),
            BenchmarkScenario(name: "Medium (256 tokens)", category: .llm, parameters: ["maxTokens": "256"]),
            BenchmarkScenario(name: "Long (512 tokens)", category: .llm, parameters: ["maxTokens": "512"]),
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo
    ) async throws -> BenchmarkMetrics {
        let maxTokens = Int(scenario.parameters?["maxTokens"] ?? "") ?? 512
        var metrics = BenchmarkMetrics()

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        let loadStart = Date()
        try await RunAnywhere.loadModel(model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        do {
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

            try? await RunAnywhere.unloadModel()
            return metrics
        } catch {
            try? await RunAnywhere.unloadModel()
            throw error
        }
    }
}
