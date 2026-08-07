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

    /// `SyntheticInputGenerator` emits mono Int16 PCM at this rate.
    private static let sampleRate = 16_000

    func scenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(name: "Silent 2s", category: .stt, parameters: ["type": "silent"]),
            BenchmarkScenario(name: "Sine Tone 3s", category: .stt, parameters: ["type": "sine"])
        ]
    }

    // swiftlint:disable:next function_body_length
    func execute(
        scenario: BenchmarkScenario,
        model: RAModelInfo
    ) async throws -> BenchmarkMetrics {
        var metrics = BenchmarkMetrics()

        let memBefore = SyntheticInputGenerator.availableMemoryBytes()

        let loadStart = Date()
        try await RunAnywhere.models.load(id: model.id)
        metrics.loadTimeMs = Date().timeIntervalSince(loadStart) * 1000

        do {
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

            // Warmup: one discarded transcription so first-run cache/JIT cost is not
            // charged to the measured pass (parity with the LLM/VLM warmup).
            let warmupStart = Date()
            do {
                _ = try await RunAnywhere.stt.transcribe(
                    .pcm16(
                        SyntheticInputGenerator.silentAudio(durationSeconds: 0.5),
                        sampleRate: Self.sampleRate
                    )
                )
            } catch let error as CancellationError {
                throw error
            } catch {
                // Warmup is best-effort.
            }
            metrics.warmupTimeMs = Date().timeIntervalSince(warmupStart) * 1000

            let benchStart = Date()
            _ = try await RunAnywhere.stt.transcribe(.pcm16(audioData, sampleRate: Self.sampleRate))
            let elapsed = Date().timeIntervalSince(benchStart)
            metrics.endToEndLatencyMs = elapsed * 1000

            metrics.audioLengthSeconds = audioDuration
            // Wall-clock RTF: the transcript carries no backend timing block.
            metrics.realTimeFactor = audioDuration > 0 ? elapsed / audioDuration : nil

            let memAfter = SyntheticInputGenerator.availableMemoryBytes()
            metrics.memoryDeltaBytes = memBefore - memAfter

            try? await RunAnywhere.models.unload(category: .speechRecognition)
            return metrics
        } catch {
            try? await RunAnywhere.models.unload(category: .speechRecognition)
            throw error
        }
    }
}
