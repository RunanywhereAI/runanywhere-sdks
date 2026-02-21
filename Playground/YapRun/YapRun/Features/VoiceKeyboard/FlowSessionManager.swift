//
//  FlowSessionManager.swift
//  YapRun
//
//  Manages a "Flow Session" triggered by the keyboard extension deep link.
//
//  Architecture (WisprFlow pattern):
//    1. Keyboard writes sessionState = "activating" + opens yaprun://startFlow
//    2. Main app starts AVAudioEngine WHILE STILL FOREGROUNDED
//    3. Live Activity keeps the app alive in the background
//    4. sessionState → "ready", keyboard shows "Using iPhone Microphone"
//    5. User swipes back, taps mic → Darwin startListening notification
//    6. Audio buffering gates on .listening phase
//    7. User taps ✓ → stopListening → transcribe on-device → deliver result
//

#if os(iOS)
import ActivityKit
import Combine
import Foundation
import RunAnywhere
import os

@MainActor
final class FlowSessionManager: ObservableObject {

    static let shared = FlowSessionManager()

    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "FlowSession")
    private let audioCapture = AudioCaptureManager()

    // MARK: - Published State

    @Published var isActive = false
    @Published var sessionPhase: FlowSessionPhase = .idle
    @Published var lastError: String?

    // MARK: - Private State

    private var audioBuffer = Data()
    private var elapsedTask: Task<Void, Never>?
    private var elapsedSeconds = 0
    private var wordCount = 0

    // MARK: - Live Activity

    @available(iOS 16.1, *)
    private var liveActivity: Activity<DictationActivityAttributes>?

    private init() {
        SharedDataBridge.shared.clearSession()
        setupDarwinObservers()
    }

    // MARK: - Darwin Observer Setup

    private func setupDarwinObservers() {
        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.startListening
        ) { [weak self] in
            Task { await self?.handleStartListening() }
        }

        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.stopListening
        ) { [weak self] in
            Task { await self?.handleStopListening() }
        }

        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.cancelListening
        ) { [weak self] in
            Task { await self?.handleCancelListening() }
        }

        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.endSession
        ) { [weak self] in
            Task { await self?.endSession() }
        }
    }

    // MARK: - Entry Points

    func handleStartFlow() async {
        guard sessionPhase == .idle else {
            logger.warning("Flow session already active — ignoring duplicate start")
            return
        }
        await activateSession()
    }

    func endSession() async {
        guard sessionPhase != .idle else { return }
        logger.info("Flow session ending")

        elapsedTask?.cancel()
        audioCapture.stopRecording()

        if #available(iOS 16.1, *) { await endLiveActivity(transcript: "") }
        SharedDataBridge.shared.clearSession()
        transition(to: .idle)
    }

    // MARK: - Session Activation

    private func activateSession() async {
        lastError = nil
        elapsedSeconds = 0
        wordCount = 0

        SharedDataBridge.shared.lastHeartbeatTimestamp = Date().timeIntervalSince1970
        transition(to: .activating)

        // Load STT model if needed
        if await RunAnywhere.currentSTTModel == nil {
            if let preferredId = SharedDataBridge.shared.preferredSTTModelId {
                logger.info("Auto-loading preferred STT model: \(preferredId)")
                do {
                    try await RunAnywhere.loadSTTModel(preferredId)
                } catch {
                    lastError = "Could not load model. Please check settings."
                    logger.error("Auto-load failed: \(error.localizedDescription)")
                    SharedDataBridge.shared.clearSession()
                    transition(to: .idle)
                    return
                }
            } else {
                lastError = "No STT model selected. Open YapRun to download one."
                logger.error("No STT model — aborting flow session")
                SharedDataBridge.shared.clearSession()
                transition(to: .idle)
                return
            }
        }

        // Microphone permission
        let permitted = await audioCapture.requestPermission()
        guard permitted else {
            lastError = "Microphone access denied."
            logger.error("Microphone permission denied")
            SharedDataBridge.shared.clearSession()
            transition(to: .idle)
            return
        }

        // Start AVAudioEngine while foregrounded
        do {
            try audioCapture.startRecording { [weak self] data in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    SharedDataBridge.shared.audioLevel = self.audioCapture.audioLevel
                    guard case .listening = self.sessionPhase else { return }
                    self.audioBuffer.append(data)
                }
            }
        } catch {
            lastError = "Could not start microphone: \(error.localizedDescription)"
            logger.error("Audio engine start failed: \(error.localizedDescription)")
            SharedDataBridge.shared.clearSession()
            transition(to: .idle)
            return
        }

        if #available(iOS 16.1, *) { startLiveActivity() }
        startElapsedTimer()

        transition(to: .ready)
        SharedDataBridge.shared.sessionState = "ready"
        DarwinNotificationCenter.shared.post(name: SharedConstants.DarwinNotifications.sessionReady)
        logger.info("Flow session ready — mic active in background")
    }

    // MARK: - Listening Lifecycle

    private func handleStartListening() async {
        guard case .ready = sessionPhase else {
            logger.warning("startListening received in unexpected phase: \(self.sessionPhase.description)")
            return
        }
        audioBuffer = Data()
        transition(to: .listening)
        SharedDataBridge.shared.sessionState = "listening"
        if #available(iOS 16.1, *) {
            await updateLiveActivity(phase: "listening", transcript: "")
        }
        logger.info("Listening started — buffering audio")
    }

    private func handleStopListening() async {
        guard case .listening = sessionPhase else {
            logger.warning("stopListening received in unexpected phase: \(self.sessionPhase.description)")
            return
        }

        transition(to: .transcribing)
        SharedDataBridge.shared.sessionState = "transcribing"
        if #available(iOS 16.1, *) {
            await updateLiveActivity(phase: "transcribing", transcript: "")
        }

        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms drain

        let audio = audioBuffer
        audioBuffer = Data()
        SharedDataBridge.shared.audioLevel = 0

        guard !audio.isEmpty else {
            logger.warning("No audio captured — returning to ready")
            transition(to: .ready)
            SharedDataBridge.shared.sessionState = "ready"
            if #available(iOS 16.1, *) {
                await updateLiveActivity(phase: "ready", transcript: "")
            }
            return
        }

        await transcribeAndDeliver(audio)
    }

    private func handleCancelListening() async {
        guard case .listening = sessionPhase else { return }

        audioBuffer = Data()
        SharedDataBridge.shared.audioLevel = 0

        transition(to: .ready)
        SharedDataBridge.shared.sessionState = "ready"
        if #available(iOS 16.1, *) {
            await updateLiveActivity(phase: "ready", transcript: "")
        }
        logger.info("Listening cancelled — buffer discarded")
    }

    // MARK: - Transcription

    private func transcribeAndDeliver(_ audio: Data) async {
        logger.info("Transcribing \(audio.count) bytes")

        do {
            let text = try await RunAnywhere.transcribe(audio)
            logger.info("Transcription complete: \"\(text)\"")
            wordCount += text.split(separator: " ").count

            if #available(iOS 16.1, *) {
                await updateLiveActivity(phase: "done", transcript: text)
            }
            deliverResult(text)
        } catch {
            lastError = "Transcription failed: \(error.localizedDescription)"
            logger.error("Transcription error: \(error.localizedDescription)")
            if #available(iOS 16.1, *) {
                await updateLiveActivity(phase: "ready", transcript: "")
            }
            transition(to: .ready)
            SharedDataBridge.shared.sessionState = "ready"
        }
    }

    // MARK: - Result Delivery

    private func deliverResult(_ text: String) {
        SharedDataBridge.shared.transcribedText = text
        SharedDataBridge.shared.lastInsertedText = text
        SharedDataBridge.shared.sessionState = "done"

        DarwinNotificationCenter.shared.post(
            name: SharedConstants.DarwinNotifications.transcriptionReady
        )

        transition(to: .done(text))
        appendHistory(text: text)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            await self?.returnToReady()
        }
    }

    private func returnToReady() async {
        guard case .done = sessionPhase else { return }
        transition(to: .ready)
        SharedDataBridge.shared.sessionState = "ready"
        if #available(iOS 16.1, *) {
            await updateLiveActivity(phase: "ready", transcript: "")
        }
        logger.info("Session returned to ready — awaiting next dictation")
    }

    // MARK: - Live Activity Management

    @available(iOS 16.1, *)
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities not enabled — skipping")
            return
        }
        let attributes = DictationActivityAttributes(sessionId: UUID().uuidString)
        let state = DictationActivityAttributes.ContentState(
            phase: "ready", elapsedSeconds: 0, transcript: "", wordCount: 0
        )
        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            logger.info("Live Activity started — ID: \(self.liveActivity?.id ?? "?")")
        } catch {
            logger.warning("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    @available(iOS 16.1, *)
    private func updateLiveActivity(phase: String, transcript: String) async {
        guard let activity = liveActivity else { return }
        let state = DictationActivityAttributes.ContentState(
            phase: phase, elapsedSeconds: elapsedSeconds,
            transcript: transcript, wordCount: wordCount
        )
        await activity.update(.init(state: state, staleDate: nil))
    }

    @available(iOS 16.1, *)
    private func endLiveActivity(transcript: String) async {
        guard let activity = liveActivity else { return }
        let finalState = DictationActivityAttributes.ContentState(
            phase: "done", elapsedSeconds: elapsedSeconds,
            transcript: transcript, wordCount: wordCount
        )
        await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 4))
        liveActivity = nil
        logger.info("Live Activity ended")
    }

    // MARK: - Elapsed Timer + Heartbeat

    private func startElapsedTimer() {
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { break }
                let phase = await self.sessionPhase
                guard phase != .idle else { break }
                await MainActor.run {
                    self.elapsedSeconds += 1
                    SharedDataBridge.shared.lastHeartbeatTimestamp = Date().timeIntervalSince1970
                }
                if #available(iOS 16.1, *) {
                    let currentPhase = await self.sessionPhase
                    await self.updateLiveActivity(phase: currentPhase.liveActivityPhase, transcript: "")
                }
            }
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
        isActive = (phase == .ready || phase == .listening || phase == .transcribing)
        switch phase {
        case .idle:
            elapsedSeconds = 0
            wordCount = 0
            SharedDataBridge.shared.audioLevel = 0
        case .ready:
            SharedDataBridge.shared.audioLevel = 0
        default:
            break
        }
        logger.debug("Session phase → \(phase.description)")
    }
}

// MARK: - Supporting Types

enum FlowSessionPhase: Equatable {
    case idle
    case activating
    case ready
    case listening
    case transcribing
    case done(String)

    var description: String {
        switch self {
        case .idle:         return "idle"
        case .activating:   return "activating"
        case .ready:        return "ready"
        case .listening:    return "listening"
        case .transcribing: return "transcribing"
        case .done:         return "done"
        }
    }

    var liveActivityPhase: String {
        switch self {
        case .idle:         return "idle"
        case .activating:   return "ready"
        case .ready:        return "ready"
        case .listening:    return "listening"
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
