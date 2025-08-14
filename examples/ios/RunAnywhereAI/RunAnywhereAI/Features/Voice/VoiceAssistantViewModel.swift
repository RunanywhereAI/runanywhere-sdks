import Foundation
import RunAnywhereSDK
import AVFoundation
import Combine

@MainActor
class VoiceAssistantViewModel: ObservableObject {
    private let sdk = RunAnywhereSDK.shared
    private let audioCapture = AudioCapture()
    private let ttsService = SystemTTSService()

    @Published var isInitialized = false
    @Published var currentStatus = "Initializing..."

    func initialize() async {
        do {
            // Request microphone permission
            let hasPermission = await AudioCapture.requestMicrophonePermission()
            guard hasPermission else {
                currentStatus = "Microphone permission denied"
                return
            }

            // Initialize voice service through SDK
            // The SDK should already have WhisperKit adapter registered from app startup
            currentStatus = "Voice assistant ready"
            isInitialized = true
        } catch {
            currentStatus = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    func startRecording() async throws {
        try await audioCapture.startRecording()
    }

    func stopRecordingAndProcess() async throws -> VoiceResponse {
        // Stop recording and get audio data
        let audioData = try await audioCapture.stopRecording()

        // Process through voice pipeline (STT -> LLM -> Response)
        let result = try await sdk.processVoiceQuery(
            audio: audioData,
            voiceModelId: "whisper-base"
        )

        return result
    }

    func speakResponse(_ text: String) async {
        await ttsService.speak(text: text)
    }

    func transcribeOnly(_ audioData: Data) async throws -> String {
        let result = try await sdk.transcribe(
            audio: audioData,
            modelId: "whisper-base"
        )
        return result.text
    }
}
