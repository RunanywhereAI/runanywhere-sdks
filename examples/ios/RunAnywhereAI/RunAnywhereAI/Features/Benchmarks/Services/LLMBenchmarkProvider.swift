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

    private static let systemPrompt = "You are a helpful assistant. Always give extremely detailed, "
        + "thorough responses. Never stop early. Use the full response length available "
        + "to you. Elaborate on every point with examples and explanations."

    private static let prompt = "Write a very long and detailed explanation of how neural networks work, "
        + "covering perceptrons, activation functions, backpropagation, gradient descent, "
        + "loss functions, convolutional layers, recurrent layers, transformers, attention "
        + "mechanisms, and training procedures. Be as thorough as possible."

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Short (50 tokens)", category: .llm, parameters: ["maxTokens": "50"]),
            BenchmarkScenario(name: "Medium (256 tokens)", category: .llm, parameters: ["maxTokens": "256"]),
            BenchmarkScenario(name: "Long (512 tokens)", category: .llm, parameters: ["maxTokens": "512"])
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: RAModelInfo
    ) async throws -> BenchmarkMetrics {
        let maxTokens = Int(scenario.parameters?["maxTokens"] ?? "") ?? 512
        var metrics = BenchmarkMetrics()

        // Ensure clean state: unload any LLM left over from Chat or a previous run
        try? await RunAnywhere.models.unload(category: .language)

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        let loadStart = Date()
        try await RunAnywhere.models.load(id: model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        do {
            metrics.warmupTimeMs = try await runWarmup()
            try await measure(maxTokens: maxTokens, into: &metrics)

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            try? await RunAnywhere.models.unload(category: .language)
            return metrics
        } catch {
            try? await RunAnywhere.models.unload(category: .language)
            throw error
        }
    }

    /// One discarded short generation so first-run cache/JIT cost is not charged
    /// to the measured pass.
    private func runWarmup() async throws -> Double {
        let start = Date()
        let events = try await RunAnywhere.llm.generateStream(
            prompt: "Hello",
            options: LlmOptions(maxOutputTokens: 5, temperature: 0.0)
        )
        for try await event in events {
            if case .completed = event { break }
        }
        return Date().timeIntervalSince(start) * 1000
    }

    /// Cancelling the consuming Task cancels the generation, so no explicit
    /// cancel verb is needed on the benchmark's cancellation path.
    private func measure(maxTokens: Int, into metrics: inout BenchmarkMetrics) async throws {
        let start = Date()
        let events = try await RunAnywhere.llm.generateStream(
            prompt: Self.prompt,
            options: LlmOptions(
                maxOutputTokens: maxTokens,
                temperature: 0.0,
                systemPrompt: Self.systemPrompt
            )
        )

        var final: GenerationResult?
        for try await event in events {
            try Task.checkCancellation()
            if case .completed(let payload) = event {
                final = payload.result
                break
            }
        }

        let wallMs = Date().timeIntervalSince(start) * 1000
        metrics.endToEndLatencyMs = wallMs
        metrics.generationTimeMs = wallMs
        guard let final else { return }
        metrics.ttftMs = final.timeToFirstTokenMs > 0 ? Double(final.timeToFirstTokenMs) : nil
        metrics.tokensPerSecond = final.tokensPerSecond > 0 ? Double(final.tokensPerSecond) : nil
        metrics.inputTokens = final.inputTokens > 0 ? final.inputTokens : nil
        metrics.outputTokens = final.outputTokens > 0 ? final.outputTokens : nil
    }
}
