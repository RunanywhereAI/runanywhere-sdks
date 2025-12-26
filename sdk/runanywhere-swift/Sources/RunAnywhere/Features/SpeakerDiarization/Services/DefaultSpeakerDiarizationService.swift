//
//  DefaultSpeakerDiarizationService.swift
//  RunAnywhere SDK
//
//  Default implementation of speaker diarization using simple audio features
//

import Accelerate
import Foundation
import os

// MARK: - Default Speaker Diarization Service

/// Default implementation of speaker diarization using simple audio features
/// This provides basic speaker tracking functionality without external dependencies
public class DefaultSpeakerDiarizationService: SpeakerDiarizationService {

    // MARK: - Framework Identification

    /// This is a built-in simple implementation, no external framework required
    public let inferenceFramework: InferenceFramework = .builtIn

    // MARK: - Internal State

    /// Internal state protected by lock (Swift 6 concurrency pattern)
    private struct State {
        var speakers: [String: SpeakerDiarizationSpeakerInfo] = [:]
        var temporarySpeakerSegments: [String: Int] = [:]
        var nextSpeakerId: Int = 1
    }

    /// Thread-safe state using OSAllocatedUnfairLock (Swift 6 pattern)
    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - Configuration

    /// Speaker change threshold (cosine similarity)
    private let speakerChangeThreshold: Float

    // MARK: - Logger

    private let logger = SDKLogger(category: "DefaultSpeakerDiarizationService")

    // MARK: - Protocol Properties

    public var isReady: Bool { true }

    // MARK: - Initialization

    public init(threshold: Float = 0.5) {
        self.speakerChangeThreshold = threshold
        logger.debug("Initialized default speaker diarization service")
    }

    // MARK: - SpeakerDiarizationService Implementation

    public func initialize() async throws {
        // No initialization needed for default implementation
    }

    public func processAudio(_ samples: [Float]) -> SpeakerDiarizationSpeakerInfo {
        // Create embedding outside the lock
        let embedding = createSimpleEmbedding(from: samples)

        return state.withLock { state in
            // Try to match with existing speakers
            if let matchedSpeaker = findMatchingSpeaker(embedding: embedding, speakers: state.speakers) {
                return matchedSpeaker
            }

            // Create new speaker if no match found
            let newSpeaker = createNewSpeaker(embedding: embedding, state: &state)
            logger.info("Detected new speaker: \(newSpeaker.id)")
            return newSpeaker
        }
    }

    public func updateSpeakerName(speakerId: String, name: String) {
        state.withLock { state in
            if var speaker = state.speakers[speakerId] {
                speaker.name = name
                state.speakers[speakerId] = speaker
                logger.debug("Updated speaker name: \(speakerId) -> \(name)")
            }
        }
    }

    public func getAllSpeakers() -> [SpeakerDiarizationSpeakerInfo] {
        return state.withLock { state in
            return Array(state.speakers.values)
        }
    }

    public func reset() {
        state.withLock { state in
            state.speakers.removeAll()
            state.temporarySpeakerSegments.removeAll()
            state.nextSpeakerId = 1
        }
        logger.debug("Reset speaker diarization state")
    }

    public func cleanup() async {
        reset()
    }

    // MARK: - Private Methods

    /// Find speaker that matches the given embedding
    private func findMatchingSpeaker(
        embedding: [Float],
        speakers: [String: SpeakerDiarizationSpeakerInfo]
    ) -> SpeakerDiarizationSpeakerInfo? {
        var bestMatch: (speaker: SpeakerDiarizationSpeakerInfo, similarity: Float)?

        for speaker in speakers.values {
            guard let speakerEmbedding = speaker.embedding else { continue }

            let similarity = cosineSimilarity(embedding, speakerEmbedding)

            if similarity > speakerChangeThreshold {
                if let currentBest = bestMatch {
                    if similarity > currentBest.similarity {
                        bestMatch = (speaker, similarity)
                    }
                } else {
                    bestMatch = (speaker, similarity)
                }
            }
        }

        return bestMatch?.speaker
    }

    /// Create a new speaker profile
    private func createNewSpeaker(embedding: [Float]?, state: inout State) -> SpeakerDiarizationSpeakerInfo {
        let speakerId = "speaker_\(state.nextSpeakerId)"
        let speakerNumber = state.nextSpeakerId
        state.nextSpeakerId += 1

        let speaker = SpeakerDiarizationSpeakerInfo(
            id: speakerId,
            name: "Speaker \(speakerNumber)",
            embedding: embedding
        )

        state.speakers[speakerId] = speaker
        return speaker
    }

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
        guard embedding1.count == embedding2.count, !embedding1.isEmpty else { return 0.0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(embedding1, 1, embedding2, 1, &dotProduct, vDSP_Length(embedding1.count))
        vDSP_svesq(embedding1, 1, &normA, vDSP_Length(embedding1.count))
        vDSP_svesq(embedding2, 1, &normB, vDSP_Length(embedding2.count))

        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }

    /// Create a simple embedding from audio (placeholder for real speaker embedding)
    /// In production, this would use a neural network to generate speaker embeddings
    private func createSimpleEmbedding(from audioBuffer: [Float]) -> [Float] {
        guard !audioBuffer.isEmpty else { return Array(repeating: 0, count: 128) }

        // Create a simple 128-dimensional "embedding" based on audio statistics
        // This is a placeholder - real speaker embeddings would use neural networks
        var embedding = Array(repeating: Float(0), count: 128)

        // Calculate some basic audio features
        let chunkSize = audioBuffer.count / 128
        for idx in 0..<min(128, audioBuffer.count / max(1, chunkSize)) {
            let start = idx * chunkSize
            let end = min(start + chunkSize, audioBuffer.count)
            let chunk = Array(audioBuffer[start..<end])

            // Calculate mean and variance for this chunk
            var mean: Float = 0
            var variance: Float = 0
            vDSP_meanv(chunk, 1, &mean, vDSP_Length(chunk.count))
            vDSP_measqv(chunk, 1, &variance, vDSP_Length(chunk.count))

            embedding[idx] = mean + variance
        }

        // Normalize the embedding
        var norm: Float = 0
        vDSP_svesq(embedding, 1, &norm, vDSP_Length(embedding.count))
        if norm > 0 {
            var factor = 1.0 / sqrt(norm)
            vDSP_vsmul(embedding, 1, &factor, &embedding, 1, vDSP_Length(embedding.count))
        }

        return embedding
    }
}
