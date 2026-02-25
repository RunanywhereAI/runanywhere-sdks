//
//  FlowSessionManager.swift
//  RunAnywhereAI
//
//  Manages a "Flow Session" triggered by the keyboard extension deep link.
//
//  iOS Architecture (WisprFlow pattern):
//    1. Keyboard writes sessionState = "activating" to App Group, opens runanywhere://startFlow
//    2. Main app (this file) receives the URL, auto-loads STT model if needed, then starts
//       AVAudioEngine WHILE STILL FOREGROUNDED (iOS blocks engine start from background)
//    3. A Live Activity is started immediately so iOS sees the app as having an ongoing
//       user-visible task — combined with the active audio session this keeps the main app
//       alive in the background indefinitely
//    4. sessionState transitions to "ready" — keyboard shows "Using iPhone Microphone"
//    5. User swipes back to host app and taps the mic icon on the keyboard
//    6. Keyboard posts startListening Darwin notification
//    7. Main app resets audio buffer, transitions to .listening — engine is already running
//       and its callback is now gated to append audio data to the buffer
//    8. User taps ✓ (or X to cancel) → keyboard posts stopListening / cancelListening
//    9. Main app transitions out of .listening (stops buffering), transcribes on-device
//       (Sherpa Whisper) and delivers result. Engine KEEPS RUNNING for subsequent segments.
//   10. Result written to App Group + transcriptionReady Darwin notification posted
//   11. Keyboard extension inserts text → session returns to "ready" (not "idle")
//   12. User can dictate again — engine is still running, just gates on .listening phase
//
//  Key design: AVAudioEngine MUST be started while the app is foregrounded.
//  UIBackgroundModes:audio allows a running engine to CONTINUE in background, but iOS
//  blocks starting a new engine from a backgrounded app (error 'what' / 2003329396).
//  Buffer accumulation is gated by sessionPhase == .listening in the audio callback.
//
//  iOS only — uses AVAudioSession + ActivityKit which are not on macOS.
//

#if os(iOS)
import ActivityKit
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
    private var elapsedTask: Task<Void, Never>?
    private var elapsedSeconds = 0
    private var wordCount = 0

    // MARK: - Live Activity

    @available(iOS 16.1, *)
    private var liveActivity: Activity<DictationActivityAttributes>?

    private init() {
        // Clear any stale session state from a previous app run.
        // On a fresh launch the keyboard should always start in idle.
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

    /// Called from RunAnywhereAIApp when runanywhere://startFlow is received.
    /// Checks preconditions, auto-loads model if needed, and activates the background audio session.
    func handleStartFlow() async {
        guard sessionPhase == .idle else {
            logger.warning("Flow session already active — ignoring duplicate start")
            return
        }
        await activateSession()
    }

    /// Called by FlowActivationView's X button to abort before reaching ready state,
    /// or by the keyboard's endSession Darwin notification.
    func endSession() async {
        guard sessionPhase != .idle else { return }
        logger.info("Flow session ending")

        elapsedTask?.cancel()

        // Stop engine and deactivate audio session (engine was running since activateSession)
        audioCapture.stopRecording(deactivateSession: true)

        if #available(iOS 16.1, *) { await endLiveActivity(transcript: "") }
        SharedDataBridge.shared.clearSession()   // also clears heartbeat → keyboard reverts to idle
        transition(to: .idle)
    }

    // MARK: - Session Activation (State: idle → activating → ready)

    private func activateSession() async {
        lastError = nil
        elapsedSeconds = 0
        wordCount = 0

        // Write an initial heartbeat immediately so the keyboard knows the app is alive
        SharedDataBridge.shared.lastHeartbeatTimestamp = Date().timeIntervalSince1970
        transition(to: .activating)

        // ── Model: load if not already in memory ────────────────────────────
        if await RunAnywhere.currentSTTModel == nil {
            if let preferredId = SharedDataBridge.shared.preferredSTTModelId {
                logger.info("Auto-loading preferred STT model: \(preferredId)")
                do {
                    try await RunAnywhere.loadSTTModel(preferredId)
                } catch {
                    lastError = "Could not load model. Please check Voice Keyboard settings."
                    logger.error("Auto-load failed: \(error.localizedDescription)")
                    SharedDataBridge.shared.clearSession()
                    transition(to: .idle)
                    return
                }
            } else {
                lastError = "No STT model selected. Open Voice Keyboard settings to download one."
                logger.error("No STT model — aborting flow session")
                SharedDataBridge.shared.clearSession()
                transition(to: .idle)
                return
            }
        }

        // ── Microphone permission ────────────────────────────────────────────
        let permitted = await audioCapture.requestPermission()
        guard permitted else {
            lastError = "Microphone access denied."
            logger.error("Microphone permission denied")
            SharedDataBridge.shared.clearSession()
            transition(to: .idle)
            return
        }

        // ── Start AVAudioEngine while still foregrounded ─────────────────────
        // iOS blocks engine.start() from a backgrounded app (error 'what'/2003329396).
        // UIBackgroundModes:audio allows a running engine to CONTINUE in background,
        // but the engine MUST be started here while the app is still visible.
        // Buffer accumulation is gated by sessionPhase (.listening only) in the callback.
        do {
            try audioCapture.startRecording { [weak self] data in
                // AudioCaptureManager dispatches this callback on DispatchQueue.main
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Always update audio level for waveform display
                    SharedDataBridge.shared.audioLevel = self.audioCapture.audioLevel
                    // Only accumulate audio data during the explicit listening window
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

        // Start Live Activity while still foregrounded
        if #available(iOS 16.1, *) { startLiveActivity() }

        // Start elapsed timer (also writes heartbeat every second)
        startElapsedTimer()

        // Transition to ready — keyboard can now show "Using iPhone Microphone"
        transition(to: .ready)
        SharedDataBridge.shared.sessionState = "ready"
        DarwinNotificationCenter.shared.post(name: SharedConstants.DarwinNotifications.sessionReady)
        logger.info("Flow session ready — mic active in background")
    }

    // MARK: - Listening Lifecycle (State: ready → listening)

    private func handleStartListening() async {
        guard case .ready = sessionPhase else {
            logger.warning("startListening received in unexpected phase: \(self.sessionPhase.description)")
            return
        }
        // Engine is already running from activateSession() — just reset the buffer
        // and transition. The audio callback gates on .listening to start accumulating.
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

        // Gate closed: transition away from .listening so the audio callback stops buffering.
        // Engine keeps running for subsequent dictation segments.
        transition(to: .transcribing)
        SharedDataBridge.shared.sessionState = "transcribing"
        if #available(iOS 16.1, *) {
            await updateLiveActivity(phase: "transcribing", transcript: "")
        }

        // Brief drain to let any already-queued DispatchQueue.main.async audio callbacks flush.
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

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

        // Engine keeps running — just discard the buffer and return to ready
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

        // Brief "done" state, then return to ready for the next dictation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
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
                    // Write heartbeat so the keyboard extension knows the app is alive
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
            SharedDataBridge.shared.audioLevel = 0   // reset waveform when returning to ready
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
