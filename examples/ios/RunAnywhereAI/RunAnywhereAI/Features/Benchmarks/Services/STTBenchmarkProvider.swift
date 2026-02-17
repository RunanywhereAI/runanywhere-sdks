//
//  STTBenchmarkProvider.swift
//  RunAnywhereAI
//
//  Benchmarks STT transcription with synthetic audio inputs.
//

import Foundation
import RunAnywhere

struct STTBenchmarkProvider: BenchmarkScenarioProvider {

    let category: BenchmarkCategory = .stt

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Silent 2s", category: .stt, parameters: ["type": "silent"]),
            BenchmarkScenario(name: "Sine Tone 3s", category: .stt, parameters: ["type": "sine"]),
        ]
    }

    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo
    ) async throws -> BenchmarkMetrics {
        var metrics = BenchmarkMetrics()

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        // Load
        let loadStart = Date()
        try await RunAnywhere.loadSTTModel(model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        do {
            // Generate audio
            let audioData: Data
            let audioDuration: Double
            switch scenario.parameters?["type"] {
            case "silent":
                audioDuration = 2.0
                audioData = SyntheticInputGenerator.silentAudio(durationSeconds: audioDuration)
            default:
                audioDuration = 3.0
                audioData = SyntheticInputGenerator.sineWaveAudio(durationSeconds: audioDuration)
            }

            // Transcribe
            let benchStart = Date()
            let options = STTOptions()
            let result = try await RunAnywhere.transcribeWithOptions(audioData, options: options)
            metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000

            // processingTime is in seconds
            metrics.audioLengthSeconds = audioDuration
            metrics.realTimeFactor = result.metadata.realTimeFactor

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            try? await RunAnywhere.unloadSTTModel()
            return metrics
        } catch {
            try? await RunAnywhere.unloadSTTModel()
            throw error
        }
    }
}
