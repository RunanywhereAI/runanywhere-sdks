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

        // Load (canonical proto-request form)
        let loadStart = Date()
        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = model.id
        loadRequest.category = .speechSynthesis
        let loadResult = await RunAnywhere.loadModel(loadRequest)
        guard loadResult.success else {
            throw SDKException(code: .unknown, message: loadResult.errorMessage, category: .internal)
        }
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        var unloadRequest = RAModelUnloadRequest()
        unloadRequest.category = .speechSynthesis

        do {
            let options = RATTSOptions.defaults()

            // Warmup: one discarded synthesis so first-run cache/JIT cost is not
            // charged to the measured pass (parity with the LLM/VLM warmup).
            let warmupStart = Date()
            _ = try? await RunAnywhere.synthesize("Hi.", options: options)
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            // Synthesize (not speak)
            let benchStart = Date()
            let result = try await RunAnywhere.synthesize(text, options: options)
            metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000

            // processingTime is in seconds, convert to ms-context
            metrics.audioDurationSeconds = result.duration
            metrics.charactersProcessed = Int(result.metadata.characterCount)

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
