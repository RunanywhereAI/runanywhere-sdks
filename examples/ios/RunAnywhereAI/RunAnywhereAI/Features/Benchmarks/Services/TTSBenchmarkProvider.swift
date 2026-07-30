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
            BenchmarkScenario(name: "Medium Text", category: .tts, parameters: ["length": "medium"])
        ]
    }

    // swiftlint:disable:next function_body_length
    func execute(
        scenario: BenchmarkScenario,
        model: RAModelInfo
    ) async throws -> BenchmarkMetrics {
        var metrics = BenchmarkMetrics()

        let text: String
        switch scenario.parameters?["length"] {
        case "short":
            text = "Hello, this is a test."
        default:
            text = "The quick brown fox jumps over the lazy dog. Machine learning models can "
                + "generate speech from text with remarkable quality and natural intonation."
        }

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        let loadStart = Date()
        try await RunAnywhere.models.load(id: model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        do {
            // Warmup: one discarded synthesis so first-run cache/JIT cost is not
            // charged to the measured pass (parity with the LLM/VLM warmup).
            let warmupStart = Date()
            do {
                _ = try await RunAnywhere.tts.synthesize("Hi.")
            } catch let error as CancellationError {
                throw error
            } catch {
                // Warmup is best-effort.
            }
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            // Synthesize (not speak)
            let benchStart = Date()
            let audio = try await RunAnywhere.tts.synthesize(text)
            metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000

            metrics.audioDurationSeconds = Double(audio.durationMs) / 1000.0
            metrics.charactersProcessed = text.count

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            try? await RunAnywhere.models.unload(category: .speechSynthesis)
            return metrics
        } catch {
            try? await RunAnywhere.models.unload(category: .speechSynthesis)
            throw error
        }
    }
}
