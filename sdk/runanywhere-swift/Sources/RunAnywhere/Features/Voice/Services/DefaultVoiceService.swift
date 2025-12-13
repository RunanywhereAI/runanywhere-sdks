//
//  DefaultVoiceService.swift
//  RunAnywhere SDK
//
//  Default implementation of VoiceService that orchestrates components
//

import Foundation

// MARK: - Default Voice Service

/// Default implementation of VoiceService
/// Orchestrates VAD, STT, LLM, and TTS components
@MainActor
public final class DefaultVoiceService: VoiceService {

    // MARK: - Properties

    private let vadComponent: VADComponent?
    private let sttComponent: STTComponent?
    private let llmComponent: LLMComponent?
    private let ttsComponent: TTSComponent?
    private let eventBus: EventBus
    private let logger = SDKLogger(category: "DefaultVoiceService")

    // MARK: - Initialization

    public init(
        vadComponent: VADComponent?,
        sttComponent: STTComponent?,
        llmComponent: LLMComponent?,
        ttsComponent: TTSComponent?,
        eventBus: EventBus
    ) {
        self.vadComponent = vadComponent
        self.sttComponent = sttComponent
        self.llmComponent = llmComponent
        self.ttsComponent = ttsComponent
        self.eventBus = eventBus
    }

    // MARK: - VoiceService Implementation

    public func processAudio(_ audioData: Data) async throws -> VoiceAgentResult {
        var result = VoiceAgentResult()

        // VAD Processing
        if let vad = vadComponent?.getService() {
            let floatData = audioData.toFloatArray()
            let isSpeech = vad.processAudioData(floatData)
            result.speechDetected = isSpeech

            if !isSpeech {
                return result // No speech, return early
            }

            eventBus.publish(SDKVoiceEvent.speechDetected)
        }

        // STT Processing
        if let stt = sttComponent?.getService() {
            let transcription = try await stt.transcribe(
                audioData: audioData,
                options: STTOptions()
            )
            result.transcription = transcription.transcript
            eventBus.publish(SDKVoiceEvent.transcriptionFinal(text: transcription.transcript))
        }

        // LLM Processing
        if let llm = llmComponent?.getService(),
           let transcript = result.transcription {
            let llmConfig = (llmComponent?.configuration as? LLMConfiguration) ?? LLMConfiguration()
            let response = try await llm.generate(
                prompt: transcript,
                options: LLMGenerationOptions(
                    maxTokens: llmConfig.maxTokens,
                    temperature: Float(llmConfig.temperature),
                    preferredFramework: llmConfig.preferredFramework
                )
            )
            result.response = response
            eventBus.publish(SDKVoiceEvent.responseGenerated(text: response))
        }

        // TTS Processing
        if let tts = ttsComponent?.getService(),
           let responseText = result.response {
            let audioData = try await tts.synthesize(
                text: responseText,
                options: TTSOptions()
            )
            result.synthesizedAudio = audioData
            eventBus.publish(SDKVoiceEvent.audioGenerated(data: audioData))
        }

        return result
    }

    public func processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for await audioData in audioStream {
                        let result = try await processAudio(audioData)
                        continuation.yield(.processed(result))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func detectVoiceActivity(_ audioData: Data) -> Bool {
        guard let vad = vadComponent?.getService() else { return true }
        let floatData = audioData.toFloatArray()
        return vad.processAudioData(floatData)
    }

    public func transcribe(_ audioData: Data) async throws -> String? {
        guard let stt = sttComponent?.getService() else { return nil }
        let result = try await stt.transcribe(audioData: audioData, options: STTOptions())
        return result.transcript
    }

    public func generateResponse(_ prompt: String) async throws -> String? {
        guard let llm = llmComponent?.getService() else { return nil }
        let llmConfig = (llmComponent?.configuration as? LLMConfiguration) ?? LLMConfiguration()
        let result = try await llm.generate(
            prompt: prompt,
            options: LLMGenerationOptions(
                maxTokens: llmConfig.maxTokens,
                temperature: Float(llmConfig.temperature),
                preferredFramework: llmConfig.preferredFramework
            )
        )
        return result
    }

    public func synthesizeSpeech(_ text: String) async throws -> Data? {
        guard let tts = ttsComponent?.getService() else { return nil }
        return try await tts.synthesize(text: text, options: TTSOptions())
    }

    public func cleanup() async throws {
        try? await vadComponent?.cleanup()
        try? await sttComponent?.cleanup()
        try? await llmComponent?.cleanup()
        try? await ttsComponent?.cleanup()
    }
}

// MARK: - Helper Extensions

private extension Data {
    func toFloatArray() -> [Float] {
        // Convert Data to Float array for VAD processing
        let count = self.count / MemoryLayout<Float>.size
        return self.withUnsafeBytes { bytes in
            Array(UnsafeBufferPointer(
                start: bytes.bindMemory(to: Float.self).baseAddress,
                count: count
            ))
        }
    }
}
