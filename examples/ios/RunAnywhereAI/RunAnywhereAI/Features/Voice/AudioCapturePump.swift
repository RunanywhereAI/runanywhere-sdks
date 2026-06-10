//
//  AudioCapturePump.swift
//  RunAnywhereAI
//
//  Example-app helper for routing SDK microphone chunks onto MainActor-owned
//  view model state.
//

import Foundation
import RunAnywhere

enum AudioCapturePump {
    /// `AudioCaptureManager` delivers chunks on the main queue. Centralize the
    /// MainActor hop so STT, VAD, and keyboard dictation do not repeat it.
    static func startRecording(
        with audioCapture: AudioCaptureManager,
        onChunk: @escaping @MainActor @Sendable (Data) -> Void
    ) async throws {
        try await audioCapture.startRecording { audioData in
            MainActor.assumeIsolated {
                onChunk(audioData)
            }
        }
    }
}
