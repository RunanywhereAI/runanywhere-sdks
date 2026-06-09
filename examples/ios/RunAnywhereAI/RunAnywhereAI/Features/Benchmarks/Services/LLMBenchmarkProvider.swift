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
        model: RAModelInfo
    ) async throws -> BenchmarkMetrics {
        let maxTokens = Int(scenario.parameters?["maxTokens"] ?? "") ?? 512
        var metrics = BenchmarkMetrics()

        // Ensure clean state: unload any LLM left over from Chat or a previous run
        var preUnloadRequest = RAModelUnloadRequest()
        preUnloadRequest.category = .language
        _ = await RunAnywhere.unloadModel(preUnloadRequest)

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load (canonical proto-request form)
        let loadStart = Date()
        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = model.id
        loadRequest.category = .language
        let loadResult = await RunAnywhere.loadModel(loadRequest)
        guard loadResult.success else {
            throw SDKException(code: .unknown, message: loadResult.errorMessage, category: .internal)
        }
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        var unloadRequest = RAModelUnloadRequest()
        unloadRequest.category = .language

        do {
            // generateStream returns
            // AsyncStream<RALLMStreamEvent>; benchmark derives TTFT +
            // tokens/sec from the event sequence directly.
            let warmupStart = Date()
            var warmupRequest = RALLMGenerateRequest()
            warmupRequest.prompt = "Hello"
            warmupRequest.maxTokens = 5
            warmupRequest.temperature = 0.0
            let warmupEvents = try await RunAnywhere.generateStream(warmupRequest)
            for await event in warmupEvents where event.isFinal { break }
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            // Benchmark
            let benchStart = Date()
            let systemPrompt = "You are a helpful assistant. Always give extremely detailed, "
                + "thorough responses. Never stop early. Use the full response length available "
                + "to you. Elaborate on every point with examples and explanations."
            let prompt = "Write a very long and detailed explanation of how neural networks work, "
                + "covering perceptrons, activation functions, backpropagation, gradient descent, "
                + "loss functions, convolutional layers, recurrent layers, transformers, attention "
                + "mechanisms, and training procedures. Be as thorough as possible."
            var benchRequest = RALLMGenerateRequest()
            benchRequest.prompt = prompt
            benchRequest.maxTokens = Int32(maxTokens)
            benchRequest.temperature = 0.0
            benchRequest.systemPrompt = systemPrompt
            let benchEvents = try await RunAnywhere.generateStream(benchRequest)

            let result = await RunAnywhere.aggregateStream(prompt: prompt, events: benchEvents)
            let wallMs = Date().timeIntervalSince(benchStart) * 1000
            let generationMs = result.generationTimeMs > 0 ? result.generationTimeMs : wallMs

            metrics.endToEndLatencyMs = generationMs
            metrics.ttftMs = result.ttftMs > 0 ? result.ttftMs : nil
            metrics.tokensPerSecond = result.tokensPerSecond > 0 ? result.tokensPerSecond : nil
            metrics.inputTokens = result.inputTokens > 0 ? Int(result.inputTokens) : nil
            metrics.outputTokens = result.tokensGenerated > 0 ? Int(result.tokensGenerated) : nil

            if result.decodeTimeMs > 0, result.tokensGenerated > 0 {
                metrics.decodeTokensPerSecond =
                    Double(result.tokensGenerated) / (Double(result.decodeTimeMs) / 1000.0)
            }
            if result.promptEvalTimeMs > 0, result.inputTokens > 0 {
                metrics.prefillTokensPerSecond =
                    Double(result.inputTokens) / (Double(result.promptEvalTimeMs) / 1000.0)
            }

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            _ = await RunAnywhere.unloadModel(unloadRequest)
            return metrics
        } catch {
            _ = await RunAnywhere.unloadModel(unloadRequest)
            throw error
        }
    }
}
