import Foundation
import os

/// Default implementation of VoiceOrchestrator
final class DefaultVoiceOrchestrator: VoiceOrchestrator {
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "VoiceOrchestrator")
    private let voiceServiceProvider: () async throws -> VoiceService?
    private let generationService: GenerationService
    private let streamingService: StreamingService
    private let ttsServiceProvider: () async throws -> TextToSpeechService?
    private let adapterRegistry: AdapterRegistry
    private let modelRegistry: ModelRegistry

    init(
        voiceServiceProvider: @escaping () async throws -> VoiceService?,
        generationService: GenerationService,
        streamingService: StreamingService? = nil,
        ttsServiceProvider: @escaping () async throws -> TextToSpeechService?,
        adapterRegistry: AdapterRegistry,
        modelRegistry: ModelRegistry
    ) {
        self.voiceServiceProvider = voiceServiceProvider
        self.generationService = generationService
        self.streamingService = streamingService ?? StreamingService(generationService: generationService)
        self.ttsServiceProvider = ttsServiceProvider
        self.adapterRegistry = adapterRegistry
        self.modelRegistry = modelRegistry
    }

    func processVoicePipeline(
        audio: Data,
        config: VoicePipelineConfig
    ) -> AsyncThrowingStream<VoicePipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let sessionId = UUID().uuidString
                let startTime = Date()
                var stageTiming: [PipelineStage: TimeInterval] = [:]

                do {
                    // Start pipeline
                    logger.info("[VoiceOrchestrator] Starting voice pipeline session: \(sessionId)")
                    continuation.yield(.started(sessionId: sessionId))

                    // Stage 1: Speech-to-Text
                    let sttStartTime = Date()
                    continuation.yield(.transcriptionStarted)
                    logger.info("[VoiceOrchestrator] Starting transcription with model: \(config.sttModelId)")

                    let transcription = try await processTranscription(
                        audio: audio,
                        modelId: config.sttModelId,
                        timeout: config.timeouts.transcription,
                        progressHandler: config.streamingEnabled ? { text, confidence in
                            continuation.yield(.transcriptionProgress(text: text, confidence: confidence))
                        } : nil
                    )

                    stageTiming[.transcription] = Date().timeIntervalSince(sttStartTime)
                    continuation.yield(.transcriptionCompleted(result: transcription))
                    logger.info("[VoiceOrchestrator] Transcription completed: '\(transcription.text)'")

                    // Stage 2: LLM Generation with Streaming
                    let llmStartTime = Date()
                    continuation.yield(.llmGenerationStarted)
                    logger.info("[VoiceOrchestrator] Starting LLM generation with streaming: \(config.streamingEnabled)")

                    var llmResponse = ""
                    var audioOutput: Data?
                    var ttsStartTime: Date?

                    if config.streamingEnabled {
                        // Stream LLM generation and process TTS in parallel
                        var accumulatedText = ""
                        var sentenceBuffer = ""
                        var tokenCount = 0

                        do {
                            for try await token in streamingService.generateStream(
                                prompt: transcription.text,
                                options: config.generationOptions
                            ) {
                                accumulatedText += token
                                sentenceBuffer += token
                                tokenCount += 1

                                // Emit progress event
                                continuation.yield(.llmGenerationProgress(text: accumulatedText, tokensGenerated: tokenCount))

                                // Check for sentence completion for TTS
                                if config.ttsEnabled && isCompleteSentence(sentenceBuffer) {
                                    if ttsStartTime == nil {
                                        ttsStartTime = Date()
                                        continuation.yield(.ttsStarted)
                                        logger.info("[VoiceOrchestrator] Starting streaming TTS")
                                    }

                                    // Process TTS for this sentence asynchronously
                                    let sentence = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !sentence.isEmpty {
                                        logger.debug("[VoiceOrchestrator] Processing TTS for sentence: \(sentence)")

                                        // Attempt TTS synthesis for the sentence
                                        if let ttsChunk = try? await processTextToSpeech(
                                            text: sentence,
                                            voice: config.ttsVoice,
                                            timeout: 5.0, // Shorter timeout for streaming chunks
                                            progressHandler: nil
                                        ) {
                                            continuation.yield(.ttsProgress(audioChunk: ttsChunk ?? Data(), progress: Float(accumulatedText.count) / Float(config.generationOptions.maxTokens)))
                                        }
                                    }

                                    sentenceBuffer = ""
                                }
                            }

                            // Process any remaining text in buffer
                            if config.ttsEnabled && !sentenceBuffer.isEmpty {
                                let finalSentence = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !finalSentence.isEmpty {
                                    logger.debug("[VoiceOrchestrator] Processing final TTS chunk: \(finalSentence)")
                                    if let ttsChunk = try? await processTextToSpeech(
                                        text: finalSentence,
                                        voice: config.ttsVoice,
                                        timeout: 5.0,
                                        progressHandler: nil
                                    ) {
                                        continuation.yield(.ttsProgress(audioChunk: ttsChunk ?? Data(), progress: 1.0))
                                    }
                                }
                            }

                            llmResponse = accumulatedText
                        } catch {
                            logger.error("[VoiceOrchestrator] Streaming generation failed: \(error)")
                            throw error
                        }
                    } else {
                        // Non-streaming fallback
                        llmResponse = try await processLLMGeneration(
                            prompt: transcription.text,
                            modelId: config.llmModelId,
                            options: config.generationOptions,
                            timeout: config.timeouts.llmGeneration,
                            progressHandler: nil
                        )

                        // Process TTS for complete response if enabled
                        if config.ttsEnabled {
                            ttsStartTime = Date()
                            continuation.yield(.ttsStarted)
                            logger.info("[VoiceOrchestrator] Starting text-to-speech")

                            audioOutput = try await processTextToSpeech(
                                text: llmResponse,
                                voice: config.ttsVoice,
                                timeout: config.timeouts.textToSpeech,
                                progressHandler: config.streamingEnabled ? { chunk, progress in
                                    continuation.yield(.ttsProgress(audioChunk: chunk, progress: progress))
                                } : nil
                            )
                        }
                    }

                    stageTiming[.llmGeneration] = Date().timeIntervalSince(llmStartTime)
                    continuation.yield(.llmGenerationCompleted(text: llmResponse))
                    logger.info("[VoiceOrchestrator] LLM generation completed")

                    if let ttsStart = ttsStartTime {
                        stageTiming[.textToSpeech] = Date().timeIntervalSince(ttsStart)
                        continuation.yield(.ttsCompleted(audio: audioOutput ?? Data()))
                        logger.info("[VoiceOrchestrator] Text-to-speech completed")
                    }

                    // Complete pipeline
                    let totalTime = Date().timeIntervalSince(startTime)
                    let result = VoicePipelineResult(
                        transcription: transcription,
                        llmResponse: llmResponse,
                        audioOutput: audioOutput,
                        processingTime: totalTime,
                        stageTiming: stageTiming
                    )

                    continuation.yield(.completed(result: result))
                    logger.info("[VoiceOrchestrator] Pipeline completed in \(String(format: "%.2f", totalTime))s")
                    continuation.finish()

                } catch {
                    let stage = determineFailedStage(error: error)
                    logger.error("[VoiceOrchestrator] Pipeline failed at \(stage.rawValue): \(error)")
                    continuation.yield(.error(stage: stage, error: error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func processVoiceQuery(
        audio: Data,
        config: VoicePipelineConfig
    ) async throws -> VoicePipelineResult {
        var lastResult: VoicePipelineResult?

        for try await event in processVoicePipeline(audio: audio, config: config) {
            if case .completed(let result) = event {
                lastResult = result
            }
        }

        guard let result = lastResult else {
            throw VoiceOrchestratorError.operationFailed
        }

        return result
    }

    // MARK: - Private Methods

    private func processTranscription(
        audio: Data,
        modelId: String,
        timeout: TimeInterval,
        progressHandler: ((String, Float) -> Void)?
    ) async throws -> VoiceTranscriptionResult {
        try await withTimeout(timeout) {
            // Get voice service
            guard let voiceService = try await self.findVoiceService(for: modelId) else {
                throw VoiceOrchestratorError.stageError(
                    stage: .transcription,
                    underlying: NSError(domain: "VoiceOrchestrator", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "No voice service available"])
                )
            }

            // Initialize service
            try await voiceService.initialize(modelPath: modelId)

            // Perform transcription
            let result = try await voiceService.transcribe(
                audio: audio,
                options: VoiceTranscriptionOptions()
            )

            // Don't cleanup - keep service cached for reuse
            // await voiceService.cleanup()

            return result
        }
    }

    private func processLLMGeneration(
        prompt: String,
        modelId: String?,
        options: GenerationOptions,
        timeout: TimeInterval,
        progressHandler: ((String, Int) -> Void)?
    ) async throws -> String {
        try await withTimeout(timeout) {
            let result = try await self.generationService.generate(
                prompt: prompt,
                options: options
            )
            return result.text
        }
    }

    private func processTextToSpeech(
        text: String,
        voice: String?,
        timeout: TimeInterval,
        progressHandler: ((Data, Float) -> Void)?
    ) async throws -> Data? {
        try await withTimeout(timeout) {
            guard let ttsService = try await self.ttsServiceProvider() else {
                self.logger.warning("[VoiceOrchestrator] TTS service not available")
                return nil
            }

            // Create TTS options
            let options = TTSOptions(
                voice: voice,
                language: "en-US",
                rate: 1.0,
                pitch: 1.0,
                volume: 1.0,
                audioFormat: .pcm,
                sampleRate: 16000,
                useSSML: false
            )

            // Speak the text directly through system TTS
            // Note: System TTS plays audio directly, doesn't return raw data
            try await ttsService.speak(text: text, options: options)

            // Return empty data as system TTS plays directly
            // The audio is played through the device speakers
            return Data()
        }
    }

    private func findVoiceService(for modelId: String) async throws -> VoiceService? {
        // Try to find a model info for this modelId
        if let model = try? modelRegistry.getModel(by: modelId) {
            // Find adapter that can handle this model
            if let unifiedAdapter = adapterRegistry.findBestAdapter(for: model),
               unifiedAdapter.supportedModalities.contains(.voiceToText) {
                // Create a voice service from the unified adapter
                if let voiceService = unifiedAdapter.createService(for: .voiceToText) as? VoiceService {
                    return voiceService
                }
            }
        }

        // Fallback: Find any framework that supports voice-to-text
        let voiceFrameworks = adapterRegistry.getFrameworks(for: .voiceToText)
        if let firstVoiceFramework = voiceFrameworks.first,
           let adapter = adapterRegistry.getAdapter(for: firstVoiceFramework) {
            if let voiceService = adapter.createService(for: .voiceToText) as? VoiceService {
                return voiceService
            }
        }

        return nil
    }

    private func determineFailedStage(error: Error) -> PipelineStage {
        // Analyze error to determine which stage failed
        let errorString = error.localizedDescription.lowercased()
        if errorString.contains("transcr") || errorString.contains("whisper") {
            return .transcription
        } else if errorString.contains("generat") || errorString.contains("llm") {
            return .llmGeneration
        } else if errorString.contains("speech") || errorString.contains("tts") {
            return .textToSpeech
        }
        return .llmGeneration // Default
    }

    /// Helper function to detect if text contains a complete sentence
    private func isCompleteSentence(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for common sentence endings
        let sentenceEndings = [".", "!", "?", "。", "！", "？"] // Including CJK punctuation

        for ending in sentenceEndings {
            if trimmedText.hasSuffix(ending) {
                // Additional check: ensure there's actual content before the punctuation
                let withoutEnding = trimmedText.dropLast(ending.count)
                if !withoutEnding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            }
        }

        // Check for complete sentence patterns (e.g., newline after substantial text)
        if trimmedText.contains("\n") && trimmedText.count > 10 {
            return true
        }

        return false
    }
}
