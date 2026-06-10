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
            BenchmarkScenario(name: "Sine Tone 3s", category: .stt, parameters: ["type": "sine"])
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
        loadRequest.category = .speechRecognition
        let loadResult = await RunAnywhere.loadModel(loadRequest)
        guard loadResult.success else {
            throw SDKException(code: .unknown, message: loadResult.errorMessage, category: .internal)
        }
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        var unloadRequest = RAModelUnloadRequest()
        unloadRequest.category = .speechRecognition

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
            let options = RASTTOptions.defaults()
            let result = try await RunAnywhere.transcribe(audio: audioData, options: options)
            metrics.endToEndLatencyMs = Date().timeIntervalSince(benchStart) * 1000

            // processingTime is in seconds
            metrics.audioLengthSeconds = audioDuration
            metrics.realTimeFactor = Double(result.metadata.realTimeFactor)

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
