import FluidAudio
import Foundation
@preconcurrency import RunAnywhere

// Define the missing type locally until it's added to the SDK
public struct SpeakerDiarizationResult {
    public let segments: [DiarizedSegment]
    public let speakers: [SpeakerInfo]

    public init(segments: [DiarizedSegment], speakers: [SpeakerInfo]) {
        self.segments = segments
        self.speakers = speakers
    }
}

public struct DiarizedSegment {
    public let speaker: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String?

    public init(speaker: String, startTime: TimeInterval, endTime: TimeInterval, text: String? = nil) {
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

// Legacy type for compatibility
struct SpeakerSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let speakerId: String
    let confidence: Float?

    init(startTime: TimeInterval, endTime: TimeInterval, speakerId: String, confidence: Float? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.speakerId = speakerId
        self.confidence = confidence
    }
}

/// FluidAudio-based implementation of speaker diarization
/// Provides production-ready speaker diarization with 17.7% DER
@available(iOS 16.0, macOS 13.0, *)
public class FluidAudioDiarization: SpeakerDiarizationService {

    private let diarizerManager: DiarizerManager
    private var speakers: [String: SpeakerInfo] = [:]
    private var currentSpeaker: SpeakerInfo?
    private let logger = SDKLogger(category: "FluidAudioDiarization")
    private let diarizationQueue = DispatchQueue(
        label: "com.runanywhere.fluidaudio.diarization",
        attributes: .concurrent
    )

    /// Configuration for diarization
    private let config: DiarizerConfig

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

    public func processAudio(_ samples: [Float]) -> SpeakerInfo {
        // For now, return a placeholder until API is fixed
        return currentSpeaker ?? SpeakerInfo(id: "speaker_1", confidence: 0.95)
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
        self.config = config

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

    public func detectSpeaker(from audioBuffer: [Float], sampleRate: Int) -> SpeakerInfo {
        return diarizationQueue.sync {
            do {
                // Perform diarization to extract embeddings
                let result = try diarizerManager.performCompleteDiarization(
                    audioBuffer,
                    sampleRate: sampleRate
                )

                // Get the first segment's embedding (for short audio chunks, usually only one segment)
                guard let firstSegment = result.segments.first else {
                    logger.debug("No speaker segment found in audio")
                    return currentSpeaker ?? createUnknownSpeaker()
                }

                let embedding = firstSegment.embedding

                // Use the speaker manager to assign/find speaker based on embedding
                // This maintains speaker database across calls
                let speechDuration = Float(audioBuffer.count) / Float(sampleRate)
                let fluidSpeaker = diarizerManager.speakerManager.assignSpeaker(
                    embedding,
                    speechDuration: speechDuration,
                    confidence: firstSegment.qualityScore
                )

                if let fluidSpeaker = fluidSpeaker {
                    let speakerInfo = mapToSpeakerInfo(fluidSpeaker)

                    // Track new speakers
                    if speakers[speakerInfo.id] == nil {
                        logger.info("New speaker detected: \(speakerInfo.id)")
                        speakers[speakerInfo.id] = speakerInfo
                    }

                    // Log speaker changes
                    if self.currentSpeaker?.id != speakerInfo.id {
                        logger.debug("Speaker changed from \(self.currentSpeaker?.id ?? "none") to \(speakerInfo.id)")
                    }

                    currentSpeaker = speakerInfo
                    return speakerInfo
                } else {
                    // No speaker assigned, return current or unknown
                    return currentSpeaker ?? createUnknownSpeaker()
                }
            } catch {
                logger.error("FluidAudio diarization failed: \(error.localizedDescription)")
                // Fallback to current speaker or unknown on error
                if let current = currentSpeaker {
                    return current
                } else {
                    return createUnknownSpeaker()
                }
            }
        }
    }

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

    public func getAllSpeakers() -> [SpeakerInfo] {
        return diarizationQueue.sync {
            // Get all speakers from FluidAudio
            let fluidSpeakers = diarizerManager.speakerManager.getAllSpeakers()

            // Update our cache and return
            var allSpeakers: [SpeakerInfo] = []
            for (_, fluidSpeaker) in fluidSpeakers {
                let speakerInfo = mapToSpeakerInfo(fluidSpeaker)
                speakers[speakerInfo.id] = speakerInfo
                allSpeakers.append(speakerInfo)
            }
            return allSpeakers
        }
    }

    public func getCurrentSpeaker() -> SpeakerInfo? {
        return diarizationQueue.sync {
            currentSpeaker
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

    // MARK: - Advanced Features

    /// Perform detailed diarization with segments and multiple speakers
    public func performDetailedDiarization(audioBuffer: [Float]) async throws -> SpeakerDiarizationResult? {
        do {
            // Perform complete diarization
            let result = try diarizerManager.performCompleteDiarization(
                audioBuffer,
                sampleRate: 16000
            )

            // Map FluidAudio segments to our format
            let segments = result.segments.map { segment in
                SpeakerSegment(
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds),
                    speakerId: segment.speakerId,
                    confidence: segment.qualityScore
                )
            }

            // Get all speakers and map to our format
            let fluidSpeakers = diarizerManager.speakerManager.getAllSpeakers()
            let speakerInfos = fluidSpeakers.values.map { mapToSpeakerInfo($0) }

            // Update our speaker database
            diarizationQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                for speaker in speakerInfos {
                    self.speakers[speaker.id] = speaker
                }
            }

            // Convert SpeakerSegment to DiarizedSegment
            let diarizedSegments = segments.map { segment in
                DiarizedSegment(
                    speaker: segment.speakerId,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    text: nil
                )
            }

            return SpeakerDiarizationResult(segments: diarizedSegments, speakers: speakerInfos)
        } catch {
            logger.error("Detailed diarization failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Compare two audio samples to determine if they're from the same speaker
    public func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        do {
            // Extract embeddings from both audio samples
            let result1 = try diarizerManager.performCompleteDiarization(audio1, sampleRate: 16000)
            let result2 = try diarizerManager.performCompleteDiarization(audio2, sampleRate: 16000)

            guard let embedding1 = result1.segments.first?.embedding,
                  let embedding2 = result2.segments.first?.embedding else {
                return 0.0
            }

            // Calculate cosine similarity (FluidAudio uses cosine distance)
            let distance = SpeakerUtilities.cosineDistance(embedding1, embedding2)
            let similarity = 1.0 - distance // Convert distance to similarity

            return similarity
        } catch {
            logger.error("Speaker comparison failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Map FluidAudio Speaker to RunAnywhere SpeakerInfo
    private func mapToSpeakerInfo(_ fluidSpeaker: Speaker) -> SpeakerInfo {
        // Check if we already have this speaker with a custom name
        if let existingSpeaker = speakers[fluidSpeaker.id] {
            // Update embedding but preserve custom name
            return SpeakerInfo(
                id: fluidSpeaker.id,
                name: existingSpeaker.name ?? fluidSpeaker.name,
                embedding: fluidSpeaker.currentEmbedding
            )
        }

        // Create new SpeakerInfo from FluidAudio Speaker
        return SpeakerInfo(
            id: fluidSpeaker.id,
            name: fluidSpeaker.name,
            embedding: fluidSpeaker.currentEmbedding
        )
    }

    /// Create an unknown speaker when detection fails
    private func createUnknownSpeaker() -> SpeakerInfo {
        return SpeakerInfo(
            id: "unknown",
            name: "Unknown Speaker",
            embedding: nil
        )
    }
}

// MARK: - Configuration

/// Configuration for FluidAudio diarization
public struct FluidAudioDiarizationConfig {
    /// Similarity threshold for speaker matching (0.5-0.9)
    /// Lower values = more sensitive to speaker changes
    /// Higher values = more conservative speaker matching
    /// Default: 0.7 (achieves 17.7% DER)
    public let threshold: Float

    /// Maximum number of speakers to track
    public let maxSpeakers: Int

    /// Minimum audio duration for diarization (seconds)
    public let minAudioDuration: TimeInterval

    public init(
        threshold: Float = 0.7,
        maxSpeakers: Int = 10,
        minAudioDuration: TimeInterval = 0.5
    ) {
        self.threshold = threshold
        self.maxSpeakers = maxSpeakers
        self.minAudioDuration = minAudioDuration
    }
}
