import Foundation
@preconcurrency import RunAnywhereSDK
import FluidAudio
import os

/// FluidAudio-based implementation of speaker diarization
/// Provides production-ready speaker diarization with 17.7% DER
@available(iOS 16.0, macOS 13.0, *)
public class FluidAudioDiarization: SpeakerDiarizationProtocol {

    private let diarizerManager: DiarizerManager
    private var speakers: [String: SpeakerInfo] = [:]
    private var currentSpeaker: SpeakerInfo?
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "FluidAudioDiarization")
    private let diarizationQueue = DispatchQueue(label: "com.runanywhere.fluidaudio.diarization", attributes: .concurrent)

    /// Configuration for diarization
    private let config: DiarizerConfig

    /// Initialize FluidAudio diarization service
    /// - Parameter threshold: Similarity threshold for speaker matching (0.5-0.9)
    public init(threshold: Float = 0.7) async throws {
        // Configure diarization
        var config = DiarizerConfig.default
        config.clusteringThreshold = threshold
        config.minSpeechDuration = 1.0
        config.minSilenceGap = 0.5
        self.config = config

        // Initialize DiarizerManager
        self.diarizerManager = DiarizerManager(config: config)

        // Download and initialize models
        logger.info("Downloading FluidAudio models...")
        let models = try await DiarizerModels.downloadIfNeeded()

        logger.info("Initializing FluidAudio diarization...")
        diarizerManager.initialize(models: models)

        logger.info("FluidAudio diarization ready")
    }

    // MARK: - SpeakerDiarizationProtocol Implementation

    public func detectSpeaker(from audioBuffer: [Float], sampleRate: Int) -> SpeakerInfo {
        return diarizationQueue.sync {
            do {
                // Perform diarization on the audio buffer
                let result = try diarizerManager.performCompleteDiarization(
                    audioBuffer,
                    sampleRate: sampleRate
                )

                // Process the segments to find the dominant speaker
                if let firstSegment = result.segments.first {
                    // Check if this speaker already exists
                    if let existingSpeaker = diarizerManager.speakerManager.getSpeaker(for: firstSegment.speakerId) {
                        let speakerInfo = mapToSpeakerInfo(existingSpeaker)
                        currentSpeaker = speakerInfo
                        return speakerInfo
                    } else {
                        // Create new speaker
                        let speakerInfo = SpeakerInfo(
                            id: firstSegment.speakerId,
                            name: "Speaker \(firstSegment.speakerId)",
                            embedding: firstSegment.embedding
                        )
                        speakers[speakerInfo.id] = speakerInfo
                        currentSpeaker = speakerInfo
                        logger.info("New speaker detected: \(speakerInfo.id)")
                        return speakerInfo
                    }
                } else {
                    // No speaker detected, return unknown
                    return createUnknownSpeaker()
                }
            } catch {
                logger.error("FluidAudio diarization failed: \(error.localizedDescription)")
                // Fallback to unknown speaker on error
                return createUnknownSpeaker()
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

            return SpeakerDiarizationResult(segments: segments, speakers: speakerInfos)
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
