//
//  DiffusionBenchmarkProvider.swift
//  RunAnywhereAI
//
//  Benchmarks Diffusion image generation with a deterministic prompt.
//

import Foundation
import RunAnywhere

struct DiffusionBenchmarkProvider: BenchmarkScenarioProvider {
    let category: BenchmarkCategory = .diffusion

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Simple Prompt (10 steps)", category: .diffusion)
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: RAModelInfo
    ) async throws -> BenchmarkMetrics {
        var metrics = BenchmarkMetrics()

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load (canonical proto-request form)
        let loadStart = Date()
        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = model.id
        loadRequest.category = .imageGeneration
        let loadResult = await RunAnywhere.loadModel(loadRequest)
        guard loadResult.success else {
            throw SDKException.general(.unknown, loadResult.errorMessage)
        }
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        var unloadRequest = RAModelUnloadRequest()
        unloadRequest.category = .imageGeneration

        do {
            // Generate
            let benchStart = Date()
            var options = RADiffusionGenerationOptions.defaults(prompt: "A red circle on a white background")
            options.width = 512
            options.height = 512
            options.numInferenceSteps = 10
            options.guidanceScale = 0.0
            options.seed = 42
            let result = try await RunAnywhere.generateImage(options: options)

            metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000
            metrics.generationTimeMs = Double(result.totalTimeMs)

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
