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

        // Ensure clean state: unload any VLM model left over from Camera or a previous run
        var vlmUnloadRequest = RAModelUnloadRequest()
        vlmUnloadRequest.category = .multimodal
        _ = await RunAnywhere.unloadModel(vlmUnloadRequest)
        // Also unload any lingering LLM model to free memory headroom
        var llmUnloadRequest = RAModelUnloadRequest()
        llmUnloadRequest.category = .language
        _ = await RunAnywhere.unloadModel(llmUnloadRequest)
        // Brief pause to let iOS reclaim GPU/Metal memory from the previous model
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        do {
            // Load (canonical proto-request form)
            let loadStart = Date()
            var loadRequest = RAModelLoadRequest()
            loadRequest.modelID = model.id
            loadRequest.category = .multimodal
            let loadResult = await RunAnywhere.loadModel(loadRequest)
            guard loadResult.success else {
                throw SDKException(code: .unknown, message: loadResult.errorMessage, category: .internal)
            }
            metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

            // Generate a small synthetic image inside an autoreleasepool so CoreGraphics
            // intermediates are released promptly before we allocate the vision encoder.
            let maybeVLMImage = autoreleasepool {
                let image = SyntheticInputGenerator.gradientImage()
                return RAVLMImage.fromUIImage(image)
            }
            guard let vlmImage = maybeVLMImage else {
                throw NSError(
                    domain: "RunAnywhereAI.VLMBenchmark",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to convert synthetic image to VLM input"]
                )
            }

            // Warmup: single token to prime the pipeline without large KV allocation
            let warmupStart = Date()
            var warmupOptions = RAVLMGenerationOptions()
            warmupOptions.prompt = "Hi"
            warmupOptions.maxTokens = 1
            warmupOptions.temperature = 0.0
            _ = try await RunAnywhere.processImage(vlmImage, options: warmupOptions)
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            // Cancel to flush any lingering generation state / KV cache before the real run
            await RunAnywhere.cancelVLMGeneration()

            // Benchmark
            var benchOptions = RAVLMGenerationOptions()
            benchOptions.prompt = "Describe this image in detail."
            benchOptions.maxTokens = 128
            benchOptions.temperature = 0.0
            let result = try await RunAnywhere.processImage(vlmImage, options: benchOptions)
            metrics.endToEndLatencyMs = Double(result.processingTimeMs)
            metrics.tokensPerSecond = Double(result.tokensPerSecond)
            metrics.promptTokens = Int(result.promptTokens)
            metrics.completionTokens = Int(result.completionTokens)

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            _ = await RunAnywhere.unloadModel(vlmUnloadRequest)
            // Give iOS time to release GPU/Metal buffers before the next model loads
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            return metrics
        } catch {
            _ = await RunAnywhere.unloadModel(vlmUnloadRequest)
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
