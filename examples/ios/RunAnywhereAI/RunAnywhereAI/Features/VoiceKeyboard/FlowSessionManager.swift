//
//  FlowSessionManager.swift
//  RunAnywhereAI
//
//  Manages a "Flow Session" triggered by the keyboard extension deep link.
//  Flow:
//    1. Keyboard posts runanywhere://startFlow → main app receives it here
//    2. Audio recording starts in background (AVAudioSession background mode)
//    3. Silence detection triggers transcription via RunAnywhere.transcribe()
//    4. Result written to App Group UserDefaults
//    5. Darwin notification posted → keyboard extension inserts text
//    6. Optional bounce-back to host app via URL scheme
//
//  iOS only — uses AVAudioSession which is not available on macOS.
//

#if os(iOS)
import Foundation
import RunAnywhere
import os

@MainActor
final class FlowSessionManager: ObservableObject {

    static let shared = FlowSessionManager()

    private let logger = Logger(subsystem: "com.runanywhere", category: "FlowSession")
    private let audioCapture = AudioCaptureManager()

    // MARK: - Published State

    @Published var isActive = false
    @Published var sessionPhase: FlowSessionPhase = .idle
    @Published var lastError: String?

    // MARK: - Private State

    private var audioBuffer = Data()
    private var silenceCheckTask: Task<Void, Never>?
    private var lastSpeechTime: Date?
    private var isSpeechActive = false

    private let speechThreshold: Float = 0.015
    private let silenceDuration: TimeInterval = 1.8   // seconds of silence before transcribing
    private let maxRecordingDuration: TimeInterval = 60 // hard cap

    private init() {}

    // MARK: - Entry Point

    /// Called from RunAnywhereAIApp when runanywhere://startFlow is received.
    func handleStartFlow() {
        guard sessionPhase == .idle else {
            logger.warning("Flow session already active, ignoring duplicate start")
            return
        }
        logger.info("Flow session starting")
        Task { await startSession() }
    }

    // MARK: - Session Lifecycle

    private func startSession() async {
        lastError = nil
        audioBuffer = Data()

        // Ensure a model is loaded
        guard await RunAnywhere.currentSTTModel != nil else {
            lastError = "No STT model loaded. Select one in Voice Keyboard settings."
            logger.error("No STT model — aborting flow session")
            SharedDataBridge.shared.sessionState = "idle"
            return
        }

        // Request microphone permission
        let permitted = await audioCapture.requestPermission()
        guard permitted else {
            lastError = "Microphone access denied."
            logger.error("Microphone permission denied")
            SharedDataBridge.shared.sessionState = "idle"
            return
        }

        transition(to: .recording)

        do {
            try audioCapture.startRecording { [weak self] data in
                Task { @MainActor [weak self] in
                    self?.audioBuffer.append(data)
                }
            }
        } catch {
            lastError = "Could not start recording: \(error.localizedDescription)"
            logger.error("Recording start failed: \(error.localizedDescription)")
            transition(to: .idle)
            return
        }

        isActive = true
        startSilenceDetection()
        scheduleHardTimeout()
        logger.info("Flow session recording started")
    }

    // MARK: - Silence Detection

    private func startSilenceDetection() {
        silenceCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, await self.sessionPhase == .recording else { break }
                let level = await self.audioCapture.audioLevel
                await self.evaluateSpeechLevel(level)
                try? await Task.sleep(nanoseconds: 60_000_000) // 60 ms
            }
        }
    }

    private func evaluateSpeechLevel(_ level: Float) {
        if level > speechThreshold {
            if !isSpeechActive {
                logger.debug("Speech detected")
                isSpeechActive = true
            }
            lastSpeechTime = Date()
        } else if isSpeechActive, let last = lastSpeechTime,
                  Date().timeIntervalSince(last) > silenceDuration {
            logger.info("Silence detected — stopping and transcribing")
            isSpeechActive = false
            Task { await self.finishRecordingAndTranscribe() }
        }
    }

    private func scheduleHardTimeout() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.maxRecordingDuration ?? 60) * 1_000_000_000)
            guard let self = self, await self.sessionPhase == .recording else { return }
            logger.info("Hard recording timeout reached")
            await self.finishRecordingAndTranscribe()
        }
    }

    // MARK: - Transcription

    private func finishRecordingAndTranscribe() async {
        guard sessionPhase == .recording else { return }

        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        audioCapture.stopRecording()

        let audio = audioBuffer
        audioBuffer = Data()

        guard !audio.isEmpty else {
            logger.warning("No audio captured — aborting")
            transition(to: .idle)
            return
        }

        transition(to: .transcribing)
        logger.info("Transcribing \(audio.count) bytes")

        do {
            let text = try await RunAnywhere.transcribe(audio)
            logger.info("Transcription complete: \"\(text)\"")
            deliverResult(text)
        } catch {
            lastError = "Transcription failed: \(error.localizedDescription)"
            logger.error("Transcription error: \(error.localizedDescription)")
            SharedDataBridge.shared.sessionState = "idle"
            transition(to: .idle)
        }
    }

    // MARK: - Result Delivery

    private func deliverResult(_ text: String) {
        SharedDataBridge.shared.transcribedText = text
        SharedDataBridge.shared.sessionState = "done"

        // Notify keyboard extension via Darwin IPC
        DarwinNotificationCenter.shared.post(
            name: SharedConstants.DarwinNotifications.transcriptionReady
        )

        transition(to: .done(text))

        // Append to dictation history
        appendHistory(text: text)

        // Schedule reset back to idle after a short delay
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.transition(to: .idle)
            SharedDataBridge.shared.clearSession()
        }
    }

    // MARK: - History

    private func appendHistory(text: String) {
        guard let defaults = SharedDataBridge.shared.defaults else { return }
        var history = (try? JSONDecoder().decode(
            [DictationEntry].self,
            from: defaults.data(forKey: SharedConstants.Keys.dictationHistory) ?? Data()
        )) ?? []
        history.insert(DictationEntry(text: text, date: Date()), at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        if let encoded = try? JSONEncoder().encode(history) {
            defaults.set(encoded, forKey: SharedConstants.Keys.dictationHistory)
        }
    }

    // MARK: - Helpers

    private func transition(to phase: FlowSessionPhase) {
        sessionPhase = phase
        isActive = (phase == .recording || phase == .transcribing)
        if case .idle = phase {
            lastSpeechTime = nil
            isSpeechActive = false
        }
        logger.debug("Session phase → \(phase.description)")
    }
}

// MARK: - Supporting Types

enum FlowSessionPhase: Equatable {
    case idle
    case recording
    case transcribing
    case done(String)

    var description: String {
        switch self {
        case .idle:         return "idle"
        case .recording:    return "recording"
        case .transcribing: return "transcribing"
        case .done:         return "done"
        }
    }
}

struct DictationEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String, date: Date) {
        self.id = UUID()
        self.text = text
        self.date = date
    }
}

#endif
