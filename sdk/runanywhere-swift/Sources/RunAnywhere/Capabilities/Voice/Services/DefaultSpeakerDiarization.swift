import Foundation
import Accelerate

/// Default implementation of speaker diarization using simple audio features
/// This provides basic speaker tracking functionality without external dependencies
public class DefaultSpeakerDiarization: SpeakerDiarizationProtocol {

    /// Manages detected speakers and their profiles
    private var speakers: [String: SpeakerInfo] = [:]

    /// Current active speaker
    private var currentSpeaker: SpeakerInfo?

    /// Speaker change threshold (cosine similarity)
    /// Lowered from 0.7 to 0.5 for better speaker differentiation
    private let speakerChangeThreshold: Float = 0.5

    /// Minimum segments before confirming new speaker
    private let minSegmentsForNewSpeaker: Int = 2

    /// Temporary speaker segments counter
    private var temporarySpeakerSegments: [String: Int] = [:]

    /// Next speaker ID counter
    private var nextSpeakerId: Int = 1

    /// Lock for thread safety
    private let lock = NSLock()

    /// Logger
    private let logger = SDKLogger(category: "DefaultSpeakerDiarization")

    public init() {
        logger.debug("Initialized default speaker diarization")
    }

    // MARK: - SpeakerDiarizationProtocol Implementation

    public func detectSpeaker(from audioBuffer: [Float], sampleRate: Int) -> SpeakerInfo {
        lock.lock()
        defer { lock.unlock() }

        // Create a simple embedding from audio features
        let embedding = createSimpleEmbedding(from: audioBuffer)

        // Try to match with existing speakers
        if let matchedSpeaker = findMatchingSpeaker(embedding: embedding) {
            currentSpeaker = matchedSpeaker
            return matchedSpeaker
        }

        // Create new speaker if no match found
        let newSpeaker = createNewSpeaker(embedding: embedding)
        currentSpeaker = newSpeaker
        logger.info("Detected new speaker: \(newSpeaker.id)")
        return newSpeaker
    }

    public func updateSpeakerName(speakerId: String, name: String) {
        lock.lock()
        defer { lock.unlock() }

        if var speaker = speakers[speakerId] {
            speaker.name = name
            speakers[speakerId] = speaker
            logger.debug("Updated speaker name: \(speakerId) -> \(name)")
        }
    }

    public func getAllSpeakers() -> [SpeakerInfo] {
        lock.lock()
        defer { lock.unlock() }

        return Array(speakers.values)
    }

    public func getCurrentSpeaker() -> SpeakerInfo? {
        lock.lock()
        defer { lock.unlock() }

        return currentSpeaker
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        speakers.removeAll()
        currentSpeaker = nil
        temporarySpeakerSegments.removeAll()
        nextSpeakerId = 1
        logger.debug("Reset speaker diarization state")
    }

    // MARK: - Private Methods

    /// Find speaker that matches the given embedding
    private func findMatchingSpeaker(embedding: [Float]) -> SpeakerInfo? {
        var bestMatch: (speaker: SpeakerInfo, similarity: Float)?

        for speaker in speakers.values {
            guard let speakerEmbedding = speaker.embedding else { continue }

            let similarity = cosineSimilarity(embedding, speakerEmbedding)

            if similarity > speakerChangeThreshold {
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (speaker, similarity)
                }
            }
        }

        return bestMatch?.speaker
    }

    /// Create a new speaker profile
    private func createNewSpeaker(embedding: [Float]?) -> SpeakerInfo {
        let speakerId = "speaker_\(nextSpeakerId)"
        let speakerNumber = nextSpeakerId
        nextSpeakerId += 1

        let speaker = SpeakerInfo(
            id: speakerId,
            name: "Speaker \(speakerNumber)",
            embedding: embedding
        )

        speakers[speakerId] = speaker
        return speaker
    }

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count > 0 else { return 0.0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

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
        for i in 0..<min(128, audioBuffer.count / max(1, chunkSize)) {
            let start = i * chunkSize
            let end = min(start + chunkSize, audioBuffer.count)
            let chunk = Array(audioBuffer[start..<end])

            // Calculate mean and variance for this chunk
            var mean: Float = 0
            var variance: Float = 0
            vDSP_meanv(chunk, 1, &mean, vDSP_Length(chunk.count))
            vDSP_measqv(chunk, 1, &variance, vDSP_Length(chunk.count))

            embedding[i] = mean + variance
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
