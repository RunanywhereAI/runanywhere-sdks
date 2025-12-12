import Foundation

/// Handles progressive TTS for streaming text generation
/// Speaks complete sentences as they become available during streaming
public class StreamingTTSHandler {
    private let ttsService: TTSService
    private let logger = SDKLogger(category: "StreamingTTSHandler")

    // State tracking
    private var spokenText = ""
    private var pendingBuffer = ""
    private let queue = DispatchQueue(label: "com.runanywhere.streamingtts", qos: .userInitiated)

    // Configuration
    private let sentenceDelimiters = CharacterSet(charactersIn: ".!?")
    private let minSentenceLength = 3 // Minimum characters for a valid sentence

    public init(ttsService: TTSService) {
        self.ttsService = ttsService
    }

    /// Reset the handler for a new streaming session
    public func reset() {
        queue.sync {
            spokenText = ""
            pendingBuffer = ""
        }
        logger.debug("StreamingTTS handler reset")
    }

    /// Process a new token from the streaming response
    /// Returns true if TTS was triggered
    @discardableResult
    public func processToken(
        _ token: String,
        options: TTSOptions? = nil,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation? = nil
    ) async -> Bool {
        return await withCheckedContinuation { completion in
            queue.async { [weak self] in
                guard let self = self else {
                    completion.resume(returning: false)
                    return
                }

                // Add token to pending buffer
                self.pendingBuffer += token

                // Check for complete sentences
                let sentences = self.extractCompleteSentences()

                if !sentences.isEmpty {
                    // Speak the complete sentences
                    Task {
                        for sentence in sentences {
                            await self.speakSentence(
                                sentence,
                                options: options,
                                continuation: continuation
                            )
                        }
                    }
                    completion.resume(returning: true)
                } else {
                    completion.resume(returning: false)
                }
            }
        }
    }

    /// Extract complete sentences from the pending buffer
    private func extractCompleteSentences() -> [String] {
        var completeSentences: [String] = []

        // Find all sentence delimiters in the buffer
        var currentIndex = pendingBuffer.startIndex

        while currentIndex < pendingBuffer.endIndex {
            // Find next delimiter
            if let delimiterRange = pendingBuffer[currentIndex...].rangeOfCharacter(from: sentenceDelimiters) {
                let sentenceEndIndex = delimiterRange.upperBound
                let sentence = String(pendingBuffer[currentIndex..<sentenceEndIndex])

                // Check if this sentence is new (not already spoken)
                let fullTextSoFar = spokenText + sentence
                if !spokenText.hasSuffix(sentence) && sentence.count >= minSentenceLength {
                    completeSentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    spokenText = fullTextSoFar
                }

                currentIndex = sentenceEndIndex
            } else {
                // No more delimiters found
                break
            }
        }

        // Update pending buffer to only contain unprocessed text
        if currentIndex < pendingBuffer.endIndex {
            pendingBuffer = String(pendingBuffer[currentIndex...])
        } else {
            pendingBuffer = ""
        }

        return completeSentences
    }

    /// Speak a single sentence
    private func speakSentence(
        _ sentence: String,
        options: TTSOptions?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation?
    ) async {
        guard !sentence.isEmpty else { return }

        logger.debug("Speaking sentence: \(sentence)")
        continuation?.yield(.ttsStarted)

        do {
            let ttsOptions = options ?? TTSOptions(
                voice: "system",
                language: "en",
                rate: 1.0,
                pitch: 1.0,
                volume: 1.0
            )
            _ = try await ttsService.synthesize(text: sentence, options: ttsOptions)
            continuation?.yield(.ttsCompleted)
        } catch {
            logger.error("TTS failed for sentence: \(error)")
        }
    }

    /// Speak any remaining text in the buffer (call at end of streaming)
    public func flushRemaining(
        options: TTSOptions? = nil,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation? = nil
    ) async {
        await withCheckedContinuation { completion in
            queue.async { [weak self] in
                guard let self = self, !self.pendingBuffer.isEmpty else {
                    completion.resume()
                    return
                }

                let remainingText = self.pendingBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                self.pendingBuffer = ""

                if !remainingText.isEmpty && !self.spokenText.contains(remainingText) {
                    Task {
                        await self.speakSentence(
                            remainingText,
                            options: options,
                            continuation: continuation
                        )
                        completion.resume()
                    }
                } else {
                    completion.resume()
                }
            }
        }
    }
}

// MARK: - Convenience Extension

extension StreamingTTSHandler {
    /// Process streaming text with default TTS options from config
    public func processStreamingText(
        _ text: String,
        config: TTSConfiguration?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation? = nil
    ) async {
        let options = TTSOptions(
            voice: config?.voice,
            language: config?.language ?? "en",
            rate: config?.speakingRate ?? 1.0,
            pitch: config?.pitch ?? 1.0,
            volume: config?.volume ?? 1.0
        )

        await processToken(text, options: options, continuation: continuation)
    }
}
