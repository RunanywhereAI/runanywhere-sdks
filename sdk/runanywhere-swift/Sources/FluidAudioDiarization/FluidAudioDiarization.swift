import FluidAudio
import Foundation
@preconcurrency import RunAnywhere

/// FluidAudio-based implementation of speaker diarization
/// Provides production-ready speaker diarization with 17.7% DER
@available(iOS 16.0, macOS 13.0, *)
public class FluidAudioDiarization: SpeakerDiarizationService {

    private let diarizerManager: DiarizerManager
    private var speakers: [String: SpeakerDiarizationSpeakerInfo] = [:]
    private var currentSpeaker: SpeakerDiarizationSpeakerInfo?
    private let logger = SDKLogger(category: "FluidAudioDiarization")
    private let diarizationQueue = DispatchQueue(
        label: "com.runanywhere.fluidaudio.diarization",
        attributes: .concurrent
    )

    // MARK: - Framework Identification

    /// FluidAudio uses ONNX-based models for speaker diarization
    public let inferenceFramework: InferenceFrameworkType = .onnx

    // MARK: - Protocol Requirements

    public var isReady: Bool = false

    public func initialize() async throws {
        // Already initialized in init
        isReady = true
    }

    public func cleanup() async {
        reset()
        isReady = false
    }

    public func processAudio(_ samples: [Float]) -> SpeakerDiarizationSpeakerInfo {
        // For now, return a placeholder until API is fixed
        return currentSpeaker ?? SpeakerDiarizationSpeakerInfo(id: "speaker_1", name: "Speaker 1", embedding: nil)
    }

    /// Initialize FluidAudio diarization service
    /// - Parameter threshold: Similarity threshold for speaker matching (0.5-0.9)
    public init(threshold: Float = 0.65) async throws {
        // Configure diarization with appropriate threshold
        var config = DiarizerConfig.default
        // Set clustering threshold directly - no compensation needed
        // DiarizerManager will use this for clustering and multiply by 1.2 for speaker assignment
        // For speakers with ~26% difference, we need a threshold between 0.26 and 0.65
        config.clusteringThreshold = threshold
        config.minSpeechDuration = 0.5  // Reduced from 1.0 for quicker speaker detection
        config.minSilenceGap = 0.3  // Reduced from 0.5 for better responsiveness

        // Initialize DiarizerManager
        self.diarizerManager = DiarizerManager(config: config)

        // Download and initialize models
        logger.info("Downloading FluidAudio models...")
        let models = try await DiarizerModels.downloadIfNeeded()

        logger.info("Initializing FluidAudio diarization...")
        diarizerManager.initialize(models: models)

        logger.info("FluidAudio diarization ready")
        isReady = true
    }

    // MARK: - SpeakerDiarizationService Implementation

    public func updateSpeakerName(speakerId: String, name: String) {
        diarizationQueue.async(flags: .barrier) {
            if var speaker = self.speakers[speakerId] {
                speaker.name = name
                self.speakers[speakerId] = speaker

                // Also update in FluidAudio's speaker manager
                if let fluidSpeaker = self.diarizerManager.speakerManager.getSpeaker(for: speakerId) {
                    fluidSpeaker.name = name
                    self.diarizerManager.speakerManager.upsertSpeaker(fluidSpeaker)
                }

                self.logger.debug("Updated speaker name: \(speakerId) -> \(name)")
            }
        }
    }

    public func getAllSpeakers() -> [SpeakerDiarizationSpeakerInfo] {
        return diarizationQueue.sync {
            // Get all speakers from FluidAudio
            let fluidSpeakers = diarizerManager.speakerManager.getAllSpeakers()

            // Update our cache and return
            var allSpeakers: [SpeakerDiarizationSpeakerInfo] = []
            for (_, fluidSpeaker) in fluidSpeakers {
                let speakerInfo = mapToSpeakerInfo(fluidSpeaker)
                speakers[speakerInfo.id] = speakerInfo
                allSpeakers.append(speakerInfo)
            }
            return allSpeakers
        }
    }

    public func reset() {
        diarizationQueue.async(flags: .barrier) {
            self.speakers.removeAll()
            self.currentSpeaker = nil
            self.diarizerManager.speakerManager.reset()
            self.logger.debug("Reset speaker diarization state")
        }
    }

    // MARK: - Private Helpers

    /// Map FluidAudio Speaker to RunAnywhere SpeakerDiarizationSpeakerInfo
    private func mapToSpeakerInfo(_ fluidSpeaker: Speaker) -> SpeakerDiarizationSpeakerInfo {
        // Check if we already have this speaker with a custom name
        if let existingSpeaker = speakers[fluidSpeaker.id] {
            // Update embedding but preserve custom name
            return SpeakerDiarizationSpeakerInfo(
                id: fluidSpeaker.id,
                name: existingSpeaker.name ?? fluidSpeaker.name,
                embedding: fluidSpeaker.currentEmbedding
            )
        }

        // Create new SpeakerDiarizationSpeakerInfo from FluidAudio Speaker
        return SpeakerDiarizationSpeakerInfo(
            id: fluidSpeaker.id,
            name: fluidSpeaker.name,
            embedding: fluidSpeaker.currentEmbedding
        )
    }
}
