import Foundation
import RunAnywhereSDK
import AVFoundation
import Combine
import os

@MainActor
class VoiceAssistantViewModel: ObservableObject, VoiceSessionDelegate {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceAssistantViewModel")
    private let sdk = RunAnywhereSDK.shared
    private let audioCapture = AudioCapture()

    // MARK: - Published Properties
    @Published var currentTranscript: String = ""
    @Published var assistantResponse: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var isInitialized = false
    @Published var currentStatus = "Initializing..."

    // MARK: - Real-time Voice Session
    private var voiceSession: VoiceSessionManager?
    @Published var sessionState: VoiceSessionManager.SessionState = .disconnected
    @Published var isListening: Bool = false

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing VoiceAssistantViewModel...")

        // Request microphone permission
        logger.info("Requesting microphone permission...")
        let hasPermission = await AudioCapture.requestMicrophonePermission()
        logger.info("Microphone permission: \(hasPermission)")
        guard hasPermission else {
            currentStatus = "Microphone permission denied"
            errorMessage = "Please enable microphone access in Settings"
            logger.error("Microphone permission denied")
            return
        }

        logger.info("Voice assistant initialized")
        currentStatus = "Ready to listen"
        isInitialized = true
    }

    // MARK: - Real-time Conversation Methods

    /// Start real-time conversation
    func startConversation() async {
        do {
            // Create voice session with configuration
            let config = VoiceSessionConfig(
                recognitionModel: "whisper-base",
                ttsModel: "system",
                enableVAD: true,
                enableStreaming: true,
                maxSessionDuration: 300,
                silenceTimeout: 2.0,
                language: "en",
                useLLM: true,
                llmModel: nil  // Use default model
            )

            // Create voice session with audio capture providers
            voiceSession = sdk.createVoiceSession(
                config: config,
                audioCaptureProvider: { [weak self] in
                    // Connect to the actual audio capture stream
                    guard let self = self else {
                        return AsyncStream { $0.finish() }
                    }
                    self.logger.info("Starting audio capture stream")
                    return self.audioCapture.startContinuousCapture()
                },
                stopAudioCapture: { [weak self] in
                    self?.logger.info("Stopping audio capture")
                    self?.audioCapture.stopContinuousCapture()
                }
            )
            voiceSession?.delegate = self

            // Connect and start listening
            try await voiceSession?.connect()
            try await voiceSession?.startListening()

            isListening = true
            errorMessage = nil
            currentStatus = "Listening..."
        } catch {
            errorMessage = "Failed to start conversation: \(error.localizedDescription)"
            isListening = false
            logger.error("Failed to start conversation: \(error)")
        }
    }

    /// Stop conversation
    func stopConversation() async {
        logger.info("Stopping conversation...")
        isListening = false

        // First stop listening if we're in that state
        if sessionState == .listening {
            await voiceSession?.stopListening()
        }

        // Then disconnect the session
        await voiceSession?.disconnect()
        voiceSession = nil

        // Reset UI state
        currentStatus = "Ready to listen"
        sessionState = .disconnected
        logger.info("Conversation stopped")
    }

    /// Interrupt AI response
    func interruptResponse() async {
        await voiceSession?.interrupt()
    }

    // MARK: - VoiceSessionDelegate Implementation

    func voiceSession(_ session: VoiceSessionManager, didChangeState state: VoiceSessionManager.SessionState) {
        DispatchQueue.main.async {
            self.sessionState = state

            switch state {
            case .listening:
                self.isProcessing = false
                self.isListening = true
                self.currentStatus = "Listening..."
            case .processing:
                self.isProcessing = true
                self.currentStatus = "Thinking..."
            case .speaking:
                self.isProcessing = true
                self.currentStatus = "Speaking..."
            case .connected:
                self.currentStatus = "Ready"
            case .connecting:
                self.currentStatus = "Connecting..."
            case .disconnected:
                self.currentStatus = "Disconnected"
                self.isListening = false
            case .error(let errorMessage):
                self.errorMessage = errorMessage
                self.isProcessing = false
                self.isListening = false
                self.currentStatus = "Error"
            }
        }
    }

    func voiceSession(_ session: VoiceSessionManager, didReceiveTranscript text: String, isFinal: Bool) {
        DispatchQueue.main.async {
            self.currentTranscript = text

            // Clear response when new transcript starts
            if !isFinal && self.assistantResponse.isEmpty == false {
                self.assistantResponse = ""
            }

            self.logger.info("Transcript (\(isFinal ? "final" : "partial")): '\(text)'")
        }
    }

    func voiceSession(_ session: VoiceSessionManager, didReceiveResponse text: String) {
        DispatchQueue.main.async {
            self.assistantResponse = text

            // Log when response is complete
            let isComplete = !text.hasSuffix("...") &&
                            (text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") ||
                             text.hasSuffix(")") || text.count > 100)

            if isComplete && !text.isEmpty {
                self.logger.info("AI Response completed: '\(text.prefix(50))...'")
                // TTS is now handled by the SDK pipeline when ttsEnabled is true
            }
        }
    }

    func voiceSession(_ session: VoiceSessionManager, didEncounterError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isProcessing = false
            self.logger.error("Voice session error: \(error)")
        }
    }

    func voiceSession(_ session: VoiceSessionManager, didReceiveAudio data: Data) {
        // Audio playback handled by TTS service
        // Can add custom audio handling here if needed
        Task {
            // Play audio through TTS service if needed
            // For now, TTS is handled internally
        }
    }

    // MARK: - Legacy Methods (for backward compatibility)

    func startRecording() async throws {
        // Convert to new real-time approach
        await startConversation()
    }

    func stopRecordingAndProcess() async throws -> VoicePipelineResult {
        // This method is kept for backward compatibility
        // In real-time mode, processing happens continuously
        await stopConversation()

        // Return a mock result since real-time doesn't have a single result
        return VoicePipelineResult(
            transcription: VoiceTranscriptionResult(
                text: currentTranscript,
                language: "en",
                confidence: 0.95,
                duration: 0
            ),
            llmResponse: assistantResponse,
            audioOutput: nil,
            processingTime: 0,
            stageTiming: [:]
        )
    }

    func speakResponse(_ text: String) async {
        logger.info("Speaking response: '\(text, privacy: .public)'")
        // TTS is now handled by the SDK pipeline
        logger.info("TTS handled by SDK")
    }
}
