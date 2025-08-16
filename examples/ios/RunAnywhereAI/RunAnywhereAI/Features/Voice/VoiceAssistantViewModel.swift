import Foundation
import RunAnywhereSDK
import AVFoundation
import Combine
import os

@MainActor
class VoiceAssistantViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceAssistantViewModel")
    private let sdk = RunAnywhereSDK.shared
    let audioCapture = AudioCapture()  // Made accessible for VoiceAssistantView
    private let ttsService = SystemTTSService()

    @Published var isInitialized = false
    @Published var currentStatus = "Initializing..."

    func initialize() async {
        logger.info("Initializing VoiceAssistantViewModel...")
        // Request microphone permission
        logger.info("Requesting microphone permission...")
        let hasPermission = await AudioCapture.requestMicrophonePermission()
        logger.info("Microphone permission: \(hasPermission)")
        guard hasPermission else {
            currentStatus = "Microphone permission denied"
            logger.error("Microphone permission denied")
            return
        }

        // Initialize voice service through SDK
        // The SDK should already have WhisperKit adapter registered from app startup
        logger.info("Voice assistant initialized")
        currentStatus = "Voice assistant ready"
        isInitialized = true
    }

    func startRecording() async throws {
        logger.info("Starting recording...")
        try await audioCapture.startRecording()
        logger.info("Recording started")
    }

    func stopRecordingAndProcess() async throws -> VoicePipelineResult {
        logger.info("Stopping recording and processing...")

        // Stop recording and get audio data
        logger.info("Getting audio data...")
        let audioData = try await audioCapture.stopRecording()
        logger.debug("Audio data size: \(audioData.count) bytes")

        // Process through voice pipeline with proper timeouts
        logger.info("Processing voice query with SDK orchestrator...")
        let result = try await sdk.processVoiceQuery(
            audio: audioData,
            voiceModelId: "whisper-base",
            llmModelId: nil,
            ttsEnabled: false  // TTS will be handled separately for now
        )
        logger.info("Voice query processed")
        logger.info("Input: '\(result.transcription.text, privacy: .public)'")
        logger.info("Output: '\(result.llmResponse, privacy: .public)'")

        return result
    }

    func speakResponse(_ text: String) async {
        logger.info("Speaking response: '\(text, privacy: .public)'")
        await ttsService.speak(text: text)
        logger.info("Response spoken")
    }

    func transcribeOnly(_ audioData: Data) async throws -> String {
        logger.info("Transcribing audio data...")
        logger.debug("Audio data size: \(audioData.count) bytes")

        let result = try await sdk.transcribe(
            audio: audioData,
            modelId: "whisper-base"
        )

        logger.info("Transcription complete: '\(result.text, privacy: .public)'")
        return result.text
    }

    func processVoiceWithStreaming(_ audioData: Data) async throws -> VoicePipelineResult {
        logger.info("Processing voice with streaming events...")

        var lastResult: VoicePipelineResult?
        var accumulatedResponse = ""

        // Configure pipeline with streaming enabled for better UX
        let config = VoicePipelineConfig(
            sttModelId: "whisper-base",
            llmModelId: nil,  // Use current model
            ttsEnabled: true,  // Enable TTS for streaming synthesis
            streamingEnabled: true,  // Enable streaming for LLM generation
            timeouts: VoicePipelineConfig.PipelineTimeouts(
                transcription: 30.0,
                llmGeneration: 60.0,
                textToSpeech: 30.0
            ),
            generationOptions: GenerationOptions(
                maxTokens: 200,  // Increased for better responses
                temperature: 0.7
            )
        )

        // Process with streaming events
        for try await event in sdk.processVoiceStream(audio: audioData, config: config) {
            switch event {
            case .transcriptionCompleted(let result):
                logger.info("Transcription completed: '\(result.text, privacy: .public)'")
                await MainActor.run {
                    self.currentStatus = "You said: \(result.text)"
                }

            case .llmGenerationStarted:
                logger.info("LLM generation started")
                await MainActor.run {
                    self.currentStatus = "Generating response..."
                }

            case .llmGenerationProgress(let text, let tokens):
                // Update UI with streaming text
                accumulatedResponse = text
                logger.debug("LLM streaming: \(tokens) tokens")
                await MainActor.run {
                    // Show partial response for better UX
                    let preview = text.prefix(100)
                    self.currentStatus = "Generating: \(preview)..."
                }

            case .llmGenerationCompleted(let text):
                logger.info("LLM generation completed: '\(text.prefix(100), privacy: .public)'...")
                await MainActor.run {
                    self.currentStatus = "Speaking response..."
                }

            case .ttsStarted:
                logger.info("TTS synthesis started")

            case .ttsProgress(let audioChunk, let progress):
                logger.debug("TTS progress: \(Int(progress * 100))%")
                // In a real implementation, we could play audio chunks here
                // For now, the system TTS will handle playback

            case .ttsCompleted(let audio):
                logger.info("TTS completed, audio size: \(audio.count) bytes")

            case .completed(let result):
                lastResult = result
                logger.info("Pipeline completed successfully")
                await MainActor.run {
                    self.currentStatus = "Response complete"
                }

                // Speak the complete response if TTS wasn't streamed
                if !config.ttsEnabled {
                    await speakResponse(result.llmResponse)
                }

            case .error(let stage, let error):
                logger.error("Pipeline error at \(stage.rawValue): \(error)")
                await MainActor.run {
                    self.currentStatus = "Error: \(error.localizedDescription)"
                }
                throw error

            case .started(let sessionId):
                logger.info("Pipeline started with session: \(sessionId)")

            case .transcriptionStarted:
                logger.info("Transcription started")
                await MainActor.run {
                    self.currentStatus = "Listening..."
                }

            case .transcriptionProgress(let text, let confidence):
                logger.debug("Transcription progress: '\(text)' (confidence: \(confidence))")

            @unknown default:
                logger.debug("Unhandled pipeline event")
            }
        }

        guard let result = lastResult else {
            throw NSError(domain: "VoiceAssistant", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Voice pipeline failed to complete"])
        }

        return result
    }
}
