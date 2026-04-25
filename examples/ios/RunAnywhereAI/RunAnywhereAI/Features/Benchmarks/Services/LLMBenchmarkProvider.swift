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
            BenchmarkScenario(name: "Long (512 tokens)", category: .llm, parameters: ["maxTokens": "512"])
        ]
    }

    // swiftlint:disable:next function_body_length
    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo
    ) async throws -> BenchmarkMetrics {
        let maxTokens = Int(scenario.parameters?["maxTokens"] ?? "") ?? 512
        var metrics = BenchmarkMetrics()

        // Ensure clean state: unload any model left over from Chat or a previous run
        try? await RunAnywhere.unloadModel()

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        let loadStart = Date()
        try await RunAnywhere.loadModel(model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        do {
            // v2 close-out Phase G-2: generateStream returns
            // AsyncStream<RALLMStreamEvent>; benchmark derives TTFT +
            // tokens/sec from the event sequence directly.
            let warmupStart = Date()
            let warmupOptions = LLMGenerationOptions(maxTokens: 5, temperature: 0.0)
            let warmupEvents = try await RunAnywhere.generateStream("Hello", options: warmupOptions)
            for await event in warmupEvents where event.isFinal { break }
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            // Benchmark
            let benchStart = Date()
            let systemPrompt = "You are a helpful assistant. Always give extremely detailed, "
                + "thorough responses. Never stop early. Use the full response length available "
                + "to you. Elaborate on every point with examples and explanations."
            let options = LLMGenerationOptions(
                maxTokens: maxTokens,
                temperature: 0.0,
                systemPrompt: systemPrompt
            )
            let prompt = "Write a very long and detailed explanation of how neural networks work, "
                + "covering perceptrons, activation functions, backpropagation, gradient descent, "
                + "loss functions, convolutional layers, recurrent layers, transformers, attention "
                + "mechanisms, and training procedures. Be as thorough as possible."
            let benchEvents = try await RunAnywhere.generateStream(prompt, options: options)

            var tokenCount = 0
            var firstTokenTime: Date?
            for await event in benchEvents {
                if !event.token.isEmpty {
                    if firstTokenTime == nil { firstTokenTime = Date() }
                    tokenCount += 1
                }
                if event.isFinal { break }
            }
            let inputTokens = max(1, prompt.count / 4)

            let e2eMs = Date().timeIntervalSince(benchStart) * 1000
            metrics.endToEndLatencyMs = e2eMs
            metrics.ttftMs = firstTokenTime.map { $0.timeIntervalSince(benchStart) * 1000 }
            metrics.tokensPerSecond = e2eMs > 0 ? Double(tokenCount) / (e2eMs / 1000.0) : 0
            metrics.inputTokens = inputTokens
            metrics.outputTokens = tokenCount

            if let ttft = metrics.ttftMs, ttft > 0 {
                let decodeMs = e2eMs - ttft
                let decodeTokens = max(tokenCount - 1, 0)
                if decodeMs > 0, decodeTokens > 0 {
                    metrics.decodeTokensPerSecond = Double(decodeTokens) / (decodeMs / 1000.0)
                }
                if inputTokens > 0 {
                    metrics.prefillTokensPerSecond = Double(inputTokens) / (ttft / 1000.0)
                }
            }

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
