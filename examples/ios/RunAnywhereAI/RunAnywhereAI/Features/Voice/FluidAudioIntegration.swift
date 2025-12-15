import Foundation
import RunAnywhere
import os

/// Helper class to integrate FluidAudioDiarization with the app
@MainActor
class FluidAudioIntegration {
    private static let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "FluidAudioIntegration")

    /// Initialize speaker diarization using the SDK
    static func initializeDiarization() async -> Bool {
        do {
            try await RunAnywhere.initializeSpeakerDiarization()
            logger.info("Speaker diarization initialized successfully")
            return true
        } catch {
            logger.error("Failed to initialize speaker diarization: \(error)")
            return false
        }
    }

    /// Identify speaker from audio samples
    static func identifySpeaker(_ samples: [Float]) async -> SpeakerDiarizationSpeakerInfo? {
        do {
            let speakerInfo = try await RunAnywhere.identifySpeaker(samples)
            return speakerInfo
        } catch {
            logger.error("Failed to identify speaker: \(error)")
            return nil
        }
    }

    /// Get all detected speakers
    static func getAllSpeakers() async -> [SpeakerDiarizationSpeakerInfo] {
        do {
            return try await RunAnywhere.getAllSpeakers()
        } catch {
            logger.error("Failed to get speakers: \(error)")
            return []
        }
    }

    /// Update speaker name
    static func updateSpeakerName(speakerId: String, name: String) async -> Bool {
        do {
            try await RunAnywhere.updateSpeakerName(speakerId: speakerId, name: name)
            logger.info("Updated speaker name: \(name)")
            return true
        } catch {
            logger.error("Failed to update speaker name: \(error)")
            return false
        }
    }

    /// Reset speaker diarization
    static func resetDiarization() async {
        do {
            try await RunAnywhere.resetSpeakerDiarization()
            logger.info("Speaker diarization reset")
        } catch {
            logger.error("Failed to reset speaker diarization: \(error)")
        }
    }
}
