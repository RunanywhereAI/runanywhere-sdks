//
//  VLMBenchmarkProvider.swift
//  RunAnywhereAI
//
//  Benchmarks VLM image understanding with synthetic images.
//

import Foundation
import RunAnywhere
#if canImport(UIKit)
import UIKit
#endif

struct VLMBenchmarkProvider: BenchmarkScenarioProvider {
    let category: BenchmarkCategory = .vlm

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Image Description", category: .vlm, parameters: ["type": "gradient"])
        ]
    }

    // swiftlint:disable:next function_body_length
    func execute(
        scenario: BenchmarkScenario,
        model: RAModelInfo
    ) async throws -> BenchmarkMetrics {
        #if canImport(UIKit)
        var metrics = BenchmarkMetrics()

        // Ensure clean state: unload the VLM left over from Camera or a previous
        // run, plus any lingering LLM, to free memory headroom.
        try? await RunAnywhere.models.unload(category: .multimodal)
        try? await RunAnywhere.models.unload(category: .language)
        // Brief pause to let iOS reclaim GPU/Metal memory from the previous model
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        do {
            let loadStart = Date()
            try await RunAnywhere.models.load(id: model.id)
            metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

            // Build the synthetic image inside an autoreleasepool so CoreGraphics
            // intermediates are released before the vision encoder allocates.
            let image = try autoreleasepool {
                try ImageInput.uiImage(SyntheticInputGenerator.gradientImage())
            }

            // Warmup: single token to prime the pipeline without large KV allocation
            let warmupStart = Date()
            _ = try await RunAnywhere.vlm.generate(
                image: image,
                prompt: "Hi",
                options: LlmOptions(maxOutputTokens: 1, temperature: 0.0)
            )
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            let benchStart = Date()
            let result = try await RunAnywhere.vlm.generate(
                image: image,
                prompt: "Describe this image in detail.",
                options: LlmOptions(maxOutputTokens: 128, temperature: 0.0)
            )
            metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000
            metrics.ttftMs = result.timeToFirstTokenMs > 0 ? Double(result.timeToFirstTokenMs) : nil
            metrics.tokensPerSecond = result.tokensPerSecond > 0 ? Double(result.tokensPerSecond) : nil
            metrics.inputTokens = result.inputTokens > 0 ? result.inputTokens : nil
            metrics.outputTokens = result.outputTokens > 0 ? result.outputTokens : nil

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            try? await RunAnywhere.models.unload(category: .multimodal)
            // Give iOS time to release GPU/Metal buffers before the next model loads
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            return metrics
        } catch {
            try? await RunAnywhere.models.unload(category: .multimodal)
            try? await Task.sleep(nanoseconds: 300_000_000)
            throw error
        }
        #else
        var metrics = BenchmarkMetrics()
        metrics.errorMessage = "VLM benchmarks require UIKit (iOS)"
        return metrics
        #endif
    }
}
