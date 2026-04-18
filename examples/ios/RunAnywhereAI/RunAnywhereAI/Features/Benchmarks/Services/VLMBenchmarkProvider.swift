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

    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo
    ) async throws -> BenchmarkMetrics {
        #if canImport(UIKit)
        var metrics = BenchmarkMetrics()

        // Ensure clean state: unload any VLM model left over from Camera or a previous run
        await RunAnywhere.unloadVLMModel()
        // Also unload any lingering LLM model to free memory headroom
        try? await RunAnywhere.unloadModel()
        // Brief pause to let iOS reclaim GPU/Metal memory from the previous model
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        do {
            // Load
            let loadStart = Date()
            try await RunAnywhere.loadVLMModel(model)
            metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

            // Generate a small synthetic image inside an autoreleasepool so CoreGraphics
            // intermediates are released promptly before we allocate the vision encoder.
            let vlmImage: VLMImage = autoreleasepool {
                let image = SyntheticInputGenerator.gradientImage()
                return VLMImage(image: image)
            }

            // Warmup: single token to prime the pipeline without large KV allocation
            let warmupStart = Date()
            _ = try await RunAnywhere.processImage(vlmImage, prompt: "Hi", maxTokens: 1, temperature: 0.0)
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            // Cancel to flush any lingering generation state / KV cache before the real run
            await RunAnywhere.cancelVLMGeneration()

            // Benchmark
            let result = try await RunAnywhere.processImage(
                vlmImage,
                prompt: "Describe this image in detail.",
                maxTokens: 128,
                temperature: 0.0
            )
            metrics.endToEndLatencyMs = result.totalTimeMs
            metrics.tokensPerSecond = result.tokensPerSecond
            metrics.promptTokens = result.promptTokens
            metrics.completionTokens = result.completionTokens

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            await RunAnywhere.unloadVLMModel()
            // Give iOS time to release GPU/Metal buffers before the next model loads
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            return metrics
        } catch {
            await RunAnywhere.unloadVLMModel()
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
