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
            BenchmarkScenario(name: "Simple Prompt (10 steps)", category: .diffusion),
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo
    ) async throws -> BenchmarkMetrics {
        var metrics = BenchmarkMetrics()

        guard let localPath = model.localPath else {
            metrics.errorMessage = "Model has no local path"
            return metrics
        }

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        let loadStart = Date()
        let config = DiffusionConfiguration(
            modelVariant: .sdxs,
            enableSafetyChecker: false,
            reduceMemory: true
        )
        try await RunAnywhere.loadDiffusionModel(
            modelPath: localPath.path,
            modelId: model.id,
            modelName: model.name,
            configuration: config
        )
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        defer { Task { try? await RunAnywhere.unloadDiffusionModel() } }

        // Generate
        let benchStart = Date()
        let options = DiffusionGenerationOptions(
            prompt: "A red circle on a white background",
            width: 512,
            height: 512,
            steps: 10,
            guidanceScale: 0.0,
            seed: 42
        )
        let result = try await RunAnywhere.generateImage(prompt: options.prompt, options: options)

        metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000
        metrics.generationTimeMs = Double(result.generationTimeMs)

        let memAfter = SyntheticInputGenerator.availableMemoryBytes()
        metrics.memoryDeltaBytes = memBefore - memAfter

        return metrics
    }
}
