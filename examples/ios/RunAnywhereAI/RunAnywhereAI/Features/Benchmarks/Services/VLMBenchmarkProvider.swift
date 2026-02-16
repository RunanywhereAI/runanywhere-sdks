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
            BenchmarkScenario(name: "Solid Red Image", category: .vlm),
            BenchmarkScenario(name: "Gradient Image", category: .vlm),
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo
    ) async throws -> BenchmarkMetrics {
        #if canImport(UIKit)
        var metrics = BenchmarkMetrics()

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load (pass ModelInfo object)
        let loadStart = Date()
        try await RunAnywhere.loadVLMModel(model)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        defer { Task { await RunAnywhere.unloadVLMModel() } }

        // Generate image
        let image: UIImage
        if scenario.name.contains("Solid") {
            image = SyntheticInputGenerator.solidColorImage()
        } else {
            image = SyntheticInputGenerator.gradientImage()
        }
        let vlmImage = VLMImage(image: image)

        // Warmup
        let warmupStart = Date()
        _ = try await RunAnywhere.processImage(vlmImage, prompt: "Hi", maxTokens: 5, temperature: 0.0)
        metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

        // Benchmark
        let benchStart = Date()
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

        return metrics
        #else
        var metrics = BenchmarkMetrics()
        metrics.errorMessage = "VLM benchmarks require UIKit (iOS)"
        return metrics
        #endif
    }
}
