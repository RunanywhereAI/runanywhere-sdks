//
//  TTSBenchmarkProvider.swift
//  RunAnywhereAI
//
//  Benchmarks TTS synthesis with short and medium text inputs.
//

import Foundation
import RunAnywhere

struct TTSBenchmarkProvider: BenchmarkScenarioProvider {

    let category: BenchmarkCategory = .tts

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Short Text", category: .tts, parameters: ["length": "short"]),
            BenchmarkScenario(name: "Medium Text", category: .tts, parameters: ["length": "medium"]),
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo
    ) async throws -> BenchmarkMetrics {
        var metrics = BenchmarkMetrics()

        let text: String
        switch scenario.parameters?["length"] {
        case "short":
            text = "Hello, this is a test."
        default:
            text = "The quick brown fox jumps over the lazy dog. Machine learning models can generate speech from text with remarkable quality and natural intonation."
        }

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        let loadStart = Date()
        try await RunAnywhere.loadTTSModel(model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        do {
            // Synthesize (not speak)
            let benchStart = Date()
            let options = TTSOptions()
            let result = try await RunAnywhere.synthesize(text, options: options)
            metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000

            // processingTime is in seconds, convert to ms-context
            metrics.audioDurationSeconds = result.duration
            metrics.charactersProcessed = result.metadata.characterCount

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            try? await RunAnywhere.unloadTTSVoice()
            return metrics
        } catch {
            try? await RunAnywhere.unloadTTSVoice()
            throw error
        }
    }
}
