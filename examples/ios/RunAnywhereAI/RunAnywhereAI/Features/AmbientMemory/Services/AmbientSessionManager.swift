//
//  AmbientSessionManager.swift
//  RunAnywhereAI
//
//  The one owner of ambient capture and session state.
//
//  Only the microphone lifecycle, iOS background policy, Live Activity, and
//  storage policy live here. VAD debounce, segmentation, and transcription all
//  belong to `RunAnywhere.ambient`, which this manager drives with a single
//  start call and consumes as an event stream.
//
//  iOS background rules this encodes:
//    - AVAudioEngine must be started while the app is foregrounded. iOS blocks
//      engine.start() from the background, so `start()` refuses to run when the
//      scene is not active.
//    - `UIBackgroundModes: audio` keeps an already-running engine alive after
//      the screen locks; it does not grant a covert always-on service.
//    - A Live Activity keeps the session visible for as long as it records.
//

#if os(iOS)
import ActivityKit
import AVFoundation
import CallKit
import Combine
import Foundation
import RunAnywhere
import UIKit
import os

@MainActor
final class AmbientSessionManager: ObservableObject {
    static let shared = AmbientSessionManager()

    // MARK: - Published State

    @Published private(set) var phase: AmbientSessionPhase = .idle
    @Published private(set) var sessionRecord: AmbientSessionRecord?
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var activeGates: [RAAmbientResourceGate.Reason: String] = [:]
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var lastError: String?
    /// True while a user-triggered Summarize / Rewrite is loading the LLM.
    @Published private(set) var isSummarizing = false
    /// Map-pass progress for long digests (`completed` / `total` chunks).
    @Published private(set) var digestChunkProgress: (completed: Int, total: Int) = (0, 0)
    /// True while Label speakers is loading Sortformer or aligning turns.
    @Published private(set) var isLabelingSpeakers = false
    /// Anchor for the Live Activity's system timer (survives backgrounding).
    private var liveActivityTimerStart = Date()

    /// Selection the active (or most recent) session ran with.
    @Published private(set) var selection: AmbientModelSelection?
    @Published private(set) var retentionPolicy: AmbientRetentionPolicy = .retainAudio

    /// Fires when Summarize / Rewrite finishes so the notes list can refresh.
    let didFinishDeferredMerge = PassthroughSubject<String, Never>()
    /// Fires when speaker labeling finishes (or fails) so note detail refreshes.
    let didFinishSpeakerLabeling = PassthroughSubject<String, Never>()

    var isRecording: Bool { phase.isRecording }

    /// True whenever the Lab still owns the audio engine and the Live Activity,
    /// including while paused or finishing up. Anything else that wants the
    /// microphone or a Live Activity must wait for this to clear.
    var isCapturing: Bool { phase.holdsAudioSession }

    // MARK: - Collaborators

    private let logger = Logger(subsystem: "com.runanywhere", category: "AmbientSession")
    private let audioCapture = AudioCaptureManager()
    private let store = AmbientMemoryStore.shared
    private let benchmarkRecorder = AmbientBenchmarkRecorder()

    private var session: RAAmbientSession?
    private var eventTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var digestTask: Task<Void, Never>?
    private var audioWriteTask: Task<Void, Never>?
    private var interruptionObservers: [NSObjectProtocol] = []

    /// Transcript accumulated since the last chunk digest. Summarizing every
    /// segment would run the LLM on single sentences; batching gives the model
    /// enough context to write something worth reading.
    private var pendingChunk = ""
    /// Most recent structured digest from the map/merge pass — applied onto
    /// the note so sections and citations survive the partial-summary string path.
    private var latestStructuredDigest: RAAmbientNoteDigest?
    /// True while the note is recording audio to disk, so a storage gate can
    /// stop writing without ending the note.
    private var isWritingAudio = false

    /// When true, digest/label paths avoid intermediate `@Published` churn so
    /// SwiftUI cannot burn the 10s scene-update watchdog during Metal LLM work.
    private var quietPostASRUI = false
    /// Working note while `quietPostASRUI` — never assigned to `sessionRecord`
    /// until the pass finishes (one publish instead of one per chunk).
    private var digestScratch: AmbientSessionRecord?
    /// Quiet digests skip `@Published isSummarizing` so Notes chrome is not
    /// invalidated; this private latch still prevents overlapping passes.
    private var quietSummarizeInFlight = false

    /// Live capture performance knobs (economy VAD, warm-keep, stream diar).
    private var performanceSettings = AmbientCapturePerformanceSettings.load()
    /// Post-ASR model intentionally left resident between Label/Summarize passes.
    private var warmKeptDiarizationModelID: String?
    private var warmKeptDigestModelID: String?
    /// Live Sortformer stream tee (PCM → `diarizeStream`) while capturing.
    private var diarAudioContinuation: AsyncStream<Data>.Continuation?
    private var diarStreamTask: Task<Void, Never>?
    private var streamingDiarModelID: String?
    private var latestStreamingDiarResult: RADiarizationResult?

    @available(iOS 16.1, *)
    private var liveActivity: Activity<AmbientActivityAttributes>? {
        get { liveActivityStorage as? Activity<AmbientActivityAttributes> }
        set { liveActivityStorage = newValue }
    }
    private var liveActivityStorage: Any?

    private init() {
        observeInterruptions()
        observeStopRequests()
        observeForeground()
        // Force-quit leaves Live Activities behind — clear orphans on launch.
        Task { await self.dismissOrphanLiveActivities() }
    }

    // MARK: - Start

    /// Begin a visible ambient session. Must be called while the app is
    /// foregrounded; the caller is responsible for having shown consent.
    func start(
        selection: AmbientModelSelection,
        retention: AmbientRetentionPolicy,
        context: AmbientCaptureContext,
        conditions: AmbientDeviceConditions
    ) async {
        guard phase == .idle || phase == .stopped || phase == .failed else {
            logger.warning("Ambient session already active — ignoring duplicate start")
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            fail("Open RunAnywhere and try again — recording can only start while the app is on screen.")
            return
        }
        guard !FlowSessionManager.shared.holdsAudioSession else {
            fail("Voice Keyboard dictation is using the microphone. End that session first.")
            return
        }
        // A phone/FaceTime call owns the mic exclusively — setActive fails with
        // a generic "Session activation failed" otherwise, which looks like a bug.
        if Self.isInPhoneCall {
            fail("End the phone call first — the green call indicator in the status bar means the mic is busy.")
            return
        }
        guard selection.canStartCapture else {
            fail("Pick and download a speech detector and a transcription model before recording.")
            return
        }
        guard !conditions.shouldStopCapture else {
            fail("The device is too hot to start an ambient session. Let it cool down first.")
            return
        }

        reset()
        self.selection = selection
        self.retentionPolicy = retention
        performanceSettings = AmbientCapturePerformanceSettings.load()
        // ASR never shares RAM with a warm post-ASR model.
        await releaseWarmModelsBeforeCapture()
        transition(to: .preparing)
        statusMessage = "Loading \(selection.asrModelID)…"

        guard await requestMicrophone() else { return }

        let sessionID = UUID().uuidString
        var configuration = RAAmbientConfiguration.defaults(sttModelID: selection.asrModelID)
        configuration.vadModelID = selection.vadModelID
        // The note keeps its own continuous recording, so the pipeline does not
        // need to hand back per-segment audio as well.
        configuration.retainSegmentAudio = false
        configuration.vadMode = performanceSettings.vadMode
        if performanceSettings.vadMode != .silero {
            // Economy/hybrid produce segments more aggressively on long notes;
            // allow a deeper STT backlog when CPU RTF ≪ 1.
            configuration.maxQueuedSegments = max(configuration.maxQueuedSegments, 8)
        }

        let started: RAAmbientSession
        do {
            started = try await RunAnywhere.ambient.start(configuration, sessionID: sessionID)
        } catch {
            fail("Could not prepare the models: \(error.localizedDescription)")
            return
        }
        session = started

        // Do not touch disk until the mic is actually open. Saving first left
        // empty date-only notes whenever session activation failed (phone call,
        // Bluetooth, etc.) — the list then showed a growing duration forever.
        guard await startAudioEngine(feeding: started) else {
            await started.cancel(reason: "Microphone unavailable")
            session = nil
            return
        }

        let deviceInfo = DeviceInfoService.shared.deviceInfo
        var record = AmbientSessionRecord(
            id: sessionID,
            startedAt: Date(),
            profileID: selection.profileID,
            vadModelID: selection.vadModelID,
            sttModelID: selection.asrModelID,
            digestModelID: selection.digestModelID,
            retentionPolicy: retention,
            context: context,
            deviceModel: deviceInfo?.modelName ?? "Unknown",
            osVersion: deviceInfo?.osVersion ?? ""
        )
        if retention.retainsAudio, await hasStorageHeadroom(for: Self.recordingHeadroomBytes) {
            record.audioRelativePath = await store.beginRecording(
                sessionID: sessionID,
                sampleRate: Self.captureSampleRate
            )
            isWritingAudio = record.audioRelativePath != nil
        }
        sessionRecord = record
        await store.save(record)

        // After the note exists so live labels can persist onto it.
        await maybeStartStreamingDiarization(
            sessionID: sessionID,
            conditions: conditions
        )

        consumeEvents(from: started)
        benchmarkRecorder.begin(sessionID: sessionID, conditions: conditions)
        benchmarkRecorder.configurePerformance(performanceSettings)
        if #available(iOS 16.1, *) { startLiveActivity(sessionID: sessionID) }
        startElapsedTimer()

        transition(to: .listening)
        var listenStatus = "Listening. Lock the screen if you like — recording stays visible."
        if performanceSettings.vadMode == .economy {
            listenStatus = "Listening (economy VAD). Lock the screen if you like — recording stays visible."
        } else if performanceSettings.vadMode == .hybrid {
            listenStatus = "Listening (hybrid VAD). Lock the screen if you like — recording stays visible."
        }
        if streamingDiarModelID != nil {
            listenStatus += " Speakers labeling in the background."
        }
        statusMessage = listenStatus
        logger.info("Ambient session \(sessionID, privacy: .public) started")
    }

    // MARK: - Stop / Pause

    /// Stop capture, finish in-flight transcription, and save. Summarization
    /// is opt-in via Summarize / Rewrite so the LLM is only loaded on demand.
    func stop(reason: String? = nil) async {
        guard phase != .idle, phase != .stopped else { return }
        logger.info("Ambient session stopping (\(reason ?? "user", privacy: .public))")

        elapsedTask?.cancel()
        elapsedTask = nil
        audioCapture.stopRecording(deactivateSession: true)
        isWritingAudio = false
        await closeRecording()
        transition(to: .processing)
        statusMessage = "Finishing transcription…"

        await session?.finish()
        session = nil
        await eventTask?.value
        eventTask = nil
        await digestTask?.value
        digestTask = nil
        pendingChunk = ""

        sessionRecord?.endedAt = Date()
        sessionRecord?.stopReason = reason

        // Free ASR/VAD immediately — do not pull the digest LLM in here.
        if let asr = selection?.asrModelID {
            var unload = RAModelUnloadRequest()
            unload.modelID = asr
            unload.category = .speechRecognition
            _ = await RunAnywhere.unloadModel(unload)
        }
        if let vad = selection?.vadModelID, performanceSettings.vadMode != .economy {
            var unload = RAModelUnloadRequest()
            unload.modelID = vad
            unload.category = .voiceActivityDetection
            _ = await RunAnywhere.unloadModel(unload)
        }
        benchmarkRecorder.markMemoryAfterASRUnload()

        // Finish live Sortformer (if any) only after ASR is gone — then either
        // warm-keep it or unload before any digester work.
        await finishStreamingDiarization()

        if var record = sessionRecord {
            let hasTranscript = !record.fullTranscript
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let canSummarize = record.digestModelID != nil || selection?.digestModelID != nil
            if record.digestModelID == nil {
                record.digestModelID = selection?.digestModelID
            }
            // Empty summary + pending flag = "tap Summarize" in the UI.
            record.summaryPending = hasTranscript && canSummarize && record.summary.isEmpty
            sessionRecord = record
            await store.save(record)
            await benchmarkRecorder.finish(record: record, store: store)
        }

        if #available(iOS 16.1, *) { await endLiveActivity() }
        audioLevel = 0
        transition(to: .stopped)
        if sessionRecord?.summaryPending == true {
            statusMessage = "Note saved. Open it and tap Summarize when you want the LLM."
        } else {
            statusMessage = reason.map { "Stopped: \($0)" } ?? "Note saved."
        }
    }

    func pause() async {
        guard phase.isRecording else { return }
        await session?.pause()
        transition(to: .paused)
        statusMessage = "Paused. The microphone stays open but nothing is captured."
        // Freeze the Island/Lock Screen clock at the current elapsed time.
        updateLiveActivityIfNeeded()
    }

    func resume() async {
        guard phase == .paused else { return }
        await session?.resume()
        // Rewind the system timer so it continues from the frozen elapsed value.
        liveActivityTimerStart = Date().addingTimeInterval(-TimeInterval(elapsedSeconds))
        transition(to: .listening)
        statusMessage = "Listening."
        updateLiveActivityIfNeeded()
    }


    // MARK: - Event Consumption

    private func consumeEvents(from session: RAAmbientSession) {
        eventTask = Task { [weak self] in
            for await event in session.events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: RAAmbientEvent) async {
        switch event {
        case .state(let state):
            applyPipelineState(state)

        case .speechStarted:
            benchmarkRecorder.markSpeechStarted()

        case .speechEnded(_, let durationMs):
            benchmarkRecorder.markSpeechEnded(durationMs: durationMs)

        case .segmentOpened:
            if phase == .listening { transition(to: .capturingSpeech) }

        case .segmentFinalized(let segment):
            await persist(segment)

        case .transcript(let transcript):
            await persist(transcript)

        case .resourceGate(let gate):
            apply(gate)

        case .failure(let failure):
            await handle(failure)
        }
    }

    private func applyPipelineState(_ state: RAAmbientState) {
        switch state {
        case .listening where phase.isRecording:
            transition(to: .listening)
        case .speechSegment where phase.isRecording:
            transition(to: .capturingSpeech)
        case .processing where phase.isRecording:
            transition(to: .transcribing)
        default:
            break
        }
    }

    private func persist(_ segment: RAAmbientSegment) async {
        guard var record = sessionRecord else { return }
        record.upsert(AmbientSegmentRecord(from: segment))
        sessionRecord = record
        benchmarkRecorder.markSegment()
        await store.save(record)
        updateLiveActivityIfNeeded()
    }

    private func persist(_ transcript: RAAmbientTranscript) async {
        guard var record = sessionRecord else { return }

        // Transcription can finish before the segmentFinalized event is
        // handled on this actor; create a stub segment so the text is never
        // dropped.
        var segment = record.segments.first(where: { $0.id == transcript.segmentID })
            ?? AmbientSegmentRecord(
                id: transcript.segmentID,
                sessionID: transcript.sessionID,
                index: transcript.segmentIndex,
                startedAt: transcript.startedAt,
                endedAt: transcript.endedAt,
                durationMs: transcript.audioDurationMs,
                sampleRate: Self.captureSampleRate,
                peakConfidence: transcript.confidence
            )

        segment.apply(transcript)
        record.upsert(segment)
        sessionRecord = record
        liveTranscript = transcript.text
        benchmarkRecorder.markTranscript(transcript)
        await store.save(record)

        accumulate(transcript.text)
    }

    private func apply(_ gate: RAAmbientResourceGate) {
        if gate.isActive {
            activeGates[gate.reason] = gate.detail
        } else {
            activeGates.removeValue(forKey: gate.reason)
        }
        benchmarkRecorder.markGate(gate)
        logger.info("Ambient gate \(gate.reason.rawValue, privacy: .public) active=\(gate.isActive)")
    }

    private func handle(_ failure: RAAmbientFailure) async {
        let detail = "[\(failure.stage.rawValue)] \(failure.message)"
        logger.error("Ambient failure \(detail, privacy: .public)")
        lastError = failure.message
        guard failure.isFatal else { return }
        await stop(reason: failure.message)
        transition(to: .failed)
    }

    // MARK: - Summarization

    /// Map-chunk size. Larger ⇒ fewer slow LLM passes on long notes.
    /// Resume keys off chunk index, so keep this stable across an in-flight run.
    private static let chunkCharacterLimit = 8_000

    /// Buffer finalized transcript. LLM work waits until stop/retry so ASR and
    /// the digest model are never coresident (a common jetsam cause for 4B).
    private func accumulate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingChunk += pendingChunk.isEmpty ? trimmed : " " + trimmed
    }

    /// Split transcript into stable map chunks (word-boundary aware).
    static func splitDigestChunks(_ source: String, limit: Int = chunkCharacterLimit) -> [String] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var chunks: [String] = []
        var remaining = trimmed
        while !remaining.isEmpty {
            if remaining.count <= limit {
                chunks.append(remaining)
                break
            }
            let endIdx = remaining.index(remaining.startIndex, offsetBy: limit)
            var split = endIdx
            if let space = remaining[..<endIdx].lastIndex(of: " "),
               space > remaining.startIndex {
                split = space
            }
            let piece = String(remaining[..<split])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = String(remaining[split...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.count >= remaining.count {
                remaining = String(remaining[endIdx...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                remaining = rest
            }
            if !piece.isEmpty { chunks.append(piece) }
            if chunks.count > 64 { break }
        }
        return chunks
    }

    /// Digests one chunk. Returns `false` on failure / background interrupt.
    @discardableResult
    private func digestChunk(_ chunk: String, modelID: String) async -> Bool {
        guard canRunDigestNow else {
            lastError = "Keep the app in the foreground — digester paused. Tap Resume to continue."
            logger.info("Chunk digest deferred — app is not in the foreground")
            return false
        }
        do {
            if !quietPostASRUI {
                statusMessage = "Loading \(modelID)…"
            }
            let loadID = modelID
            try await Task.detached(priority: .userInitiated) {
                var request = RACurrentModelRequest()
                request.category = .language
                if RunAnywhere.currentModel(request).modelID == loadID { return }
                var load = RAModelLoadRequest()
                load.modelID = loadID
                load.category = .language
                let result = await RunAnywhere.loadModel(load)
                guard result.success else {
                    throw NSError(
                        domain: "AmbientMemory",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: result.errorMessage]
                    )
                }
            }.value
            guard canRunDigestNow else {
                lastError = "Keep the app in the foreground — digester paused. Tap Resume to continue."
                return false
            }
            if !quietPostASRUI {
                let progress = digestChunkProgress
                statusMessage = "Summarizing chunk \(progress.completed + 1)/\(max(progress.total, 1))…"
            }
            let chunkText = chunk
            let digest = try await Task.detached(priority: .userInitiated) {
                try await RunAnywhere.ambient.digest(text: chunkText, mode: .chunk)
            }.value
            guard var record = (quietPostASRUI ? digestScratch : sessionRecord) else { return false }
            latestStructuredDigest = digest
            record.partialSummaries.append(digest.summary)
            record.digestMapChunksCompleted = record.partialSummaries.count
            record.mergeActionItems(digest.actionItems)
            if record.summary.isEmpty || record.summaryPending {
                record.summary = record.partialSummaries.joined(separator: "\n\n")
            }
            if record.partialSummaries.count == 1 {
                record.applyStructuredDigest(digest)
            }
            // Stay pending until merge finishes so kills remain resumable.
            record.summaryPending = true
            if quietPostASRUI {
                digestScratch = record
            } else {
                sessionRecord = record
            }
            await store.save(record)
            digestChunkProgress = (record.digestMapChunksCompleted, digestChunkProgress.total)
            benchmarkRecorder.markDigest(digest)
            // Let the scene breathe between Metal bursts.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 150_000_000)
            return true
        } catch {
            let detail = error.localizedDescription
            lastError = "Summarization failed: \(detail)"
            logger.warning("Chunk digest failed: \(detail, privacy: .public)")
            if var record = (quietPostASRUI ? digestScratch : sessionRecord) {
                record.summaryPending = true
                if quietPostASRUI {
                    digestScratch = record
                } else {
                    sessionRecord = record
                }
                await store.save(record)
            }
            return false
        }
    }

    /// Run remaining map chunks. On interrupt, leaves `summaryPending` + partials.
    private func runMapChunks(_ chunks: [String], modelID: String, startingAt skip: Int) async -> Bool {
        let remaining = Array(chunks.dropFirst(skip))
        guard !remaining.isEmpty else { return true }
        for (offset, piece) in remaining.enumerated() {
            digestChunkProgress = (skip + offset, chunks.count)
            guard await digestChunk(piece, modelID: modelID) else { return false }
        }
        digestChunkProgress = (chunks.count, chunks.count)
        return true
    }

    /// Load the chosen digest model on demand, write summary + action items,
    /// then unload. Map chunks are persisted after each success so a kill can
    /// resume. Pass `rewrite: true` to discard prior machine draft + partials.
    /// `modelID` overrides the note's stored choice (from the note-detail picker).
    func generateSummary(
        for noteID: String,
        modelID overrideModelID: String? = nil,
        rewrite: Bool = false,
        quietUI: Bool = false,
        maxSourceChars: Int? = nil
    ) async {
        guard !isSummarizing, !quietSummarizeInFlight else { return }
        guard !phase.holdsAudioSession else {
            lastError = "Stop the current recording before summarizing."
            return
        }
        guard var note = await store.loadSession(id: noteID) else { return }
        let modelID = overrideModelID
            ?? note.digestModelID
            ?? selection?.digestModelID
        guard let modelID, !modelID.isEmpty else {
            lastError = "Pick a summarizing model, then try again."
            return
        }
        // Long digests on MLX were the main scene-watchdog path; steer to llama.cpp.
        if modelID.lowercased().hasPrefix("mlx-"),
           note.digestSourceTranscript.count > Self.chunkCharacterLimit {
            lastError = "Use a llama.cpp digester (e.g. Qwen3 4B GGUF) for long notes — MLX digests trip the scene watchdog."
            if !quietUI { statusMessage = lastError ?? "" }
            return
        }
        guard canRunDigestNow else {
            lastError = "Bring the app to the foreground to run the summarizer."
            return
        }

        var source = note.digestSourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if let maxSourceChars, maxSourceChars > 0, source.count > maxSourceChars {
            var cut = source.index(source.startIndex, offsetBy: maxSourceChars)
            if let nl = source[..<cut].lastIndex(of: "\n") { cut = source.index(after: nl) }
            source = String(source[..<cut])
            logger.info("Digest capped to \(source.count, privacy: .public) chars")
        }
        guard !source.isEmpty else {
            lastError = "Nothing to summarize — this note has no transcript."
            if !quietUI { statusMessage = lastError ?? "" }
            return
        }
        guard !isLabelingSpeakers else {
            lastError = "Wait for speaker labeling to finish before summarizing."
            if !quietUI { statusMessage = lastError ?? "" }
            return
        }

        // Long notes always use quiet persistence so each chunk lands on disk.
        let useQuiet = quietUI || source.count > Self.chunkCharacterLimit
        if useQuiet {
            guard !quietSummarizeInFlight else { return }
            quietSummarizeInFlight = true
        }
        isSummarizing = true
        quietPostASRUI = useQuiet
        lastError = nil
        UIApplication.shared.isIdleTimerDisabled = true
        var backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AmbientDigest") {}
        defer {
            quietSummarizeInFlight = false
            isSummarizing = false
            quietPostASRUI = false
            digestChunkProgress = (0, 0)
            UIApplication.shared.isIdleTimerDisabled = false
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }

        await prepareExclusiveWarmKeep(for: .digester)

        let previousSummary = note.summary
        let previousMachineItems = note.actionItems.filter { !$0.isManual }.map(\.text)
        let previousPartials = note.partialSummaries
        let previousChunksCompleted = note.digestMapChunksCompleted
        let previousSections = note.digestSections
        let previousDigestTitle = note.digestTitle

        let resuming = !rewrite && note.hasResumableDigest
        let allChunks = Self.splitDigestChunks(source)
        let skip = resuming
            ? min(max(note.digestMapChunksCompleted, note.partialSummaries.count), allChunks.count)
            : 0

        note.summaryPending = true
        note.digestModelID = modelID
        if rewrite || !resuming {
            note.partialSummaries = []
            note.digestMapChunksCompleted = 0
            if rewrite {
                note.summary = ""
                note.digestSections = []
                note.replaceMachineActionItems(with: [String]())
            }
        } else {
            // Keep committed map chunks; align counter with partials.
            note.digestMapChunksCompleted = skip
            if note.partialSummaries.count > skip {
                note.partialSummaries = Array(note.partialSummaries.prefix(skip))
            }
        }

        digestChunkProgress = (skip, allChunks.count)
        statusMessage = resuming
            ? "Resuming digester at chunk \(skip + 1)/\(allChunks.count)…"
            : (rewrite ? "Rewriting summary…" : "Loading model and summarizing…")

        if useQuiet {
            digestScratch = note
        } else {
            sessionRecord = note
        }
        await store.save(note)
        pendingChunk = ""
        latestStructuredDigest = nil

        let load: (loadMs: Int, warmHit: Bool)
        let digestWallStarted = Date()
        do {
            load = try await ensureLoaded(modelID: modelID, category: .language)
        } catch {
            lastError = error.localizedDescription
            statusMessage = lastError ?? ""
            // Keep resumable pending state if we already had chunks.
            if !resuming {
                note.summaryPending = false
                note.partialSummaries = previousPartials
                note.digestMapChunksCompleted = previousChunksCompleted
            }
            await store.save(note)
            return
        }

        let flushed = await runMapChunks(allChunks, modelID: modelID, startingAt: skip)
        let working = useQuiet ? digestScratch : sessionRecord
        guard flushed, var current = working else {
            // Interrupted or failed — keep map progress for Resume.
            if var paused = working {
                paused.summaryPending = true
                paused.digestMapChunksCompleted = paused.partialSummaries.count
                if paused.summary.isEmpty {
                    paused.summary = paused.partialSummaries.joined(separator: "\n\n")
                }
                await store.save(paused)
                if !useQuiet { sessionRecord = paused }
                digestScratch = nil
            } else if rewrite {
                var restored = note
                restored.summary = previousSummary
                restored.partialSummaries = previousPartials
                restored.digestMapChunksCompleted = previousChunksCompleted
                restored.digestSections = previousSections
                restored.digestTitle = previousDigestTitle
                restored.replaceMachineActionItems(with: previousMachineItems as [String])
                restored.summaryPending = false
                await store.save(restored)
                sessionRecord = restored
                digestScratch = nil
            }
            if lastError == nil {
                lastError = "Digester paused — keep the app foregrounded and tap Resume."
            }
            statusMessage = lastError ?? ""
            await unloadLanguageModelUnlessWarm(modelID)
            return
        }

        if current.partialSummaries.count > 1 {
            guard canRunDigestNow else {
                current.summaryPending = true
                await store.save(current)
                lastError = "Keep the app in the foreground — digester paused before merge. Tap Resume."
                statusMessage = lastError ?? ""
                await unloadLanguageModelUnlessWarm(modelID)
                return
            }
            current = await merged(current, modelID: modelID)
        } else if current.partialSummaries.count == 1 {
            if let digest = latestStructuredDigest {
                current.applyStructuredDigest(digest)
            } else {
                current.summary = current.partialSummaries[0]
            }
            current.summaryPending = false
        }

        let newSummary = current.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeFallback = newSummary.count <= 200
            && (source.hasPrefix(newSummary) || source.contains(newSummary))
            && current.actionItems.filter({ !$0.isManual }).isEmpty
            && current.digestSections.count <= 1
        if newSummary.isEmpty || (rewrite && looksLikeFallback && !previousSummary.isEmpty) {
            current.summary = previousSummary
            current.partialSummaries = previousPartials
            current.digestMapChunksCompleted = previousChunksCompleted
            current.digestSections = previousSections
            current.digestTitle = previousDigestTitle
            current.replaceMachineActionItems(with: previousMachineItems)
            current.summaryPending = false
            await store.save(current)
            sessionRecord = current
            digestScratch = nil
            await unloadLanguageModelUnlessWarm(modelID)
            lastError = "Rewrite did not produce a usable summary — previous draft kept."
            statusMessage = lastError ?? ""
            return
        }

        current.digestStale = false
        current.summaryPending = false
        current.digestMapChunksCompleted = current.partialSummaries.count
        await store.save(current)
        let digestWallMs = Int(Date().timeIntervalSince(digestWallStarted) * 1000)
        let digestMemory = AmbientBenchmarkRecorder.residentMemoryBytes()
        await benchmarkRecorder.amendDigestPass(
            sessionID: noteID,
            store: store,
            loadMs: load.loadMs,
            warmHit: load.warmHit,
            wallMs: digestWallMs,
            memoryBytes: digestMemory,
            sectionCount: current.digestSections.count,
            bulletCount: current.digestSections.reduce(0) { $0 + $1.bullets.count }
        )
        await unloadLanguageModelUnlessWarm(modelID)
        sessionRecord = current
        digestScratch = nil
        didFinishDeferredMerge.send(current.id)
        statusMessage = rewrite ? "Summary rewritten." : "Summary ready."
        lastError = nil
    }

    /// Back-compat name used by older call sites / tests.
    func retrySummary(for noteID: String) async {
        await generateSummary(for: noteID, rewrite: false)
    }

    // MARK: - Speaker Labeling (opt-in post-pass)

    /// Persist the chosen Sortformer model on a note without running inference.
    func setDiarizationModel(for noteID: String, modelID: String) async {
        guard var note = await store.loadSession(id: noteID) else { return }
        note.diarizationModelID = modelID
        if note.speakerLabelingState == .notConfigured
            || note.speakerLabelingState == .failed
            || note.speakerLabelingState == .interrupted {
            note.speakerLabelingState = .modelSelected
        }
        note.speakerLabelingDetail = nil
        await store.save(note)
        if sessionRecord?.id == noteID {
            sessionRecord = note
        }
        didFinishSpeakerLabeling.send(noteID)
    }

    /// Load Sortformer, diarize the note WAV, align speakers onto ASR segments,
    /// then unload. Never runs during capture or while summarizing.
    func labelSpeakers(for noteID: String, modelID overrideModelID: String? = nil) async {
        guard !isLabelingSpeakers else { return }
        guard !isSummarizing else {
            lastError = "Wait for summarization to finish before labeling speakers."
            statusMessage = lastError ?? ""
            return
        }
        guard !phase.holdsAudioSession else {
            lastError = "Stop the current recording before labeling speakers."
            statusMessage = lastError ?? ""
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            lastError = "Bring the app to the foreground to label speakers."
            statusMessage = lastError ?? ""
            return
        }

        guard var note = await store.loadSession(id: noteID) else { return }
        let modelID = overrideModelID ?? note.diarizationModelID
        guard let modelID, !modelID.isEmpty else {
            lastError = "Choose a speaker model first."
            statusMessage = lastError ?? ""
            return
        }
        guard let relativePath = note.audioRelativePath else {
            lastError = "This note has no recording to label. Keep audio when recording."
            statusMessage = lastError ?? ""
            note.speakerLabelingState = .failed
            note.speakerLabelingDetail = lastError
            await store.save(note)
            didFinishSpeakerLabeling.send(noteID)
            return
        }
        guard !note.fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Nothing to label — this note has no transcript."
            statusMessage = lastError ?? ""
            return
        }

        isLabelingSpeakers = true
        lastError = nil
        defer { isLabelingSpeakers = false }

        // Sortformer and digester never share RAM.
        await prepareExclusiveWarmKeep(for: .diarization)

        note.diarizationModelID = modelID
        note.speakerLabelingState = .loadingModel
        note.speakerLabelingDetail = "Loading speaker model…"
        await store.save(note)
        sessionRecord = note
        statusMessage = "Loading speaker model…"
        didFinishSpeakerLabeling.send(noteID)

        do {
            let load = try await ensureLoaded(modelID: modelID, category: .speakerDiarization)
            guard UIApplication.shared.applicationState == .active else {
                throw NSError(
                    domain: "AmbientMemory",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Labeling interrupted — open the note and tap Resume."]
                )
            }

            note.speakerLabelingState = .labeling
            note.speakerLabelingDetail = "Labeling speakers…"
            await store.save(note)
            sessionRecord = note
            statusMessage = "Labeling speakers…"
            didFinishSpeakerLabeling.send(noteID)

            let url = await store.audioURL(for: relativePath)
            let pcm = try AmbientWAVPCMReader.pcm16Mono(from: url, expectedSampleRate: 16_000)
            guard pcm.count >= 16_000 else {
                throw NSError(
                    domain: "AmbientMemory",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Recording is too short to label speakers."]
                )
            }

            var options = RADiarizationOptions.defaults()
            options.sampleRateHz = 16_000
            options.channelCount = 1
            options.encoding = .pcmS16Le

            let diarStarted = Date()
            let result = try await RunAnywhere.diarize(audioData: pcm, options: options)
            let diarWallMs = Int(Date().timeIntervalSince(diarStarted) * 1000)
            let turns = AmbientSpeakerAlignment.turns(from: result)
            let assignments = AmbientSpeakerAlignment.assignments(
                segments: note.segments,
                turns: turns
            )

            // Reload in case the user edited the note while we ran.
            if let fresh = await store.loadSession(id: noteID) {
                note = fresh
            }
            note.applyDiarizationLabels(
                assignments,
                modelID: modelID,
                speakerCount: Int(result.speakerCount)
            )
            await store.save(note)
            sessionRecord = note
            let diarMemory = AmbientBenchmarkRecorder.residentMemoryBytes()
            await benchmarkRecorder.amendDiarizationPass(
                sessionID: noteID,
                store: store,
                loadMs: load.loadMs,
                warmHit: load.warmHit,
                wallMs: diarWallMs,
                memoryBytes: diarMemory
            )
            await unloadDiarizationModelUnlessWarm(modelID)
            statusMessage = note.speakerLabelingDetail ?? "Speakers labeled."
            lastError = nil
            didFinishSpeakerLabeling.send(noteID)
        } catch {
            await unloadDiarizationModelUnlessWarm(modelID)
            let detail = error.localizedDescription
            let interrupted = UIApplication.shared.applicationState != .active
                || detail.localizedCaseInsensitiveContains("interrupted")
            if let fresh = await store.loadSession(id: noteID) {
                note = fresh
            }
            note.speakerLabelingState = interrupted ? .interrupted : .failed
            note.speakerLabelingDetail = interrupted
                ? "Labeling interrupted — your transcript is safe. Tap Resume to try again."
                : detail
            await store.save(note)
            sessionRecord = note
            lastError = note.speakerLabelingDetail
            statusMessage = lastError ?? ""
            didFinishSpeakerLabeling.send(noteID)
            logger.warning("Speaker labeling failed: \(detail, privacy: .public)")
        }
    }

    private func unloadDiarizationModel(_ modelID: String) async {
        var unload = RAModelUnloadRequest()
        unload.modelID = modelID
        unload.category = .speakerDiarization
        _ = await RunAnywhere.unloadModel(unload)
        if warmKeptDiarizationModelID == modelID {
            warmKeptDiarizationModelID = nil
        }
    }

    private func unloadDiarizationModelUnlessWarm(_ modelID: String) async {
        performanceSettings = AmbientCapturePerformanceSettings.load()
        if performanceSettings.warmKeep == .diarization {
            warmKeptDiarizationModelID = modelID
            warmKeptDigestModelID = nil
            logger.info("Warm-keeping Sortformer \(modelID, privacy: .public)")
            return
        }
        await unloadDiarizationModel(modelID)
    }

    /// The reduce half of the map-reduce: one pass over the partial summaries.
    /// Returns the updated note, saved, so it can also finish a note that is no
    /// longer the active one.
    private func merged(_ note: AmbientSessionRecord, modelID: String) async -> AmbientSessionRecord {
        var record = note
        guard canRunDigestNow else {
            record.summaryPending = true
            await store.save(record)
            logger.info("Merge deferred — app is not in the foreground")
            return record
        }
        if record.partialSummaries.isEmpty {
            let source = record.digestSourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty {
                do {
                    try await ensureLoaded(modelID: modelID, category: .language)
                    guard canRunDigestNow else {
                        record.summaryPending = true
                        await store.save(record)
                        return record
                    }
                    // Must stay on MainActor — see digestChunk note about MLX main.sync.
                    let digest = try await RunAnywhere.ambient.digest(text: source, mode: .chunk)
                    latestStructuredDigest = digest
                    record.partialSummaries = [digest.summary]
                    record.applyStructuredDigest(digest)
                    benchmarkRecorder.markDigest(digest)
                } catch {
                    let detail = error.localizedDescription
                    logger.warning("Transcript digest failed: \(detail, privacy: .public)")
                    record.summaryPending = true
                    await store.save(record)
                    return record
                }
            } else {
                record.summaryPending = false
                await store.save(record)
                return record
            }
        }

        // A single partial is already one summary of one chunk; running the
        // merge over it would only paraphrase it and risk losing detail.
        guard record.partialSummaries.count > 1 else {
            record.summary = record.partialSummaries[0]
            record.summaryPending = false
            await store.save(record)
            return record
        }

        do {
            try await ensureLoaded(modelID: modelID, category: .language)
            guard canRunDigestNow else {
                record.summaryPending = true
                await store.save(record)
                return record
            }
            // Speed path: one polish over a compressed draft. No tree-reduce
            // (that was ~5 extra 4B calls and made Summarize feel multi-minute).
            let draftText: String
            if record.digestSections.count >= 2 && record.digestSections.count <= 10 {
                draftText = compressSectionsForPolish(record.digestSections)
            } else {
                draftText = compressPartialsForPolish(record.partialSummaries)
            }
            statusMessage = "Writing meeting note…"
            var digest = try await polishDigest(from: draftText)
            if !isAcceptableFinalNote(digest) {
                logger.warning("Polish still messy — one retry")
                statusMessage = "Retrying note…"
                let retry = try await polishDigest(from: String(draftText.prefix(2_800)))
                if isAcceptableFinalNote(retry) {
                    digest = retry
                }
            }
            if isAcceptableFinalNote(digest) {
                latestStructuredDigest = digest
                record.applyStructuredDigest(digest)
                benchmarkRecorder.markDigest(digest)
            } else {
                logger.warning("Polish did not synthesize — applying thematic draft from map chunks")
                applyThematicPartialDraft(to: &record)
            }
        } catch {
            applyThematicPartialDraft(to: &record)
            let detail = error.localizedDescription
            logger.warning("Merge failed, keeping a thematic draft: \(detail, privacy: .public)")
        }
        record.summaryPending = false
        await store.save(record)
        return record
    }

    private func polishDigest(from draftText: String) async throws -> RAAmbientNoteDigest {
        try await Task.detached(priority: .userInitiated) {
            try await RunAnywhere.ambient.digest(text: draftText, mode: .polish)
        }.value
    }

    /// Keep polish input bounded so Qwen finishes valid JSON, but retain themes.
    private func compressSectionsForPolish(_ sections: [AmbientDigestSection]) -> String {
        let blocks = sections.prefix(8).map { section -> String in
            let bullets = section.bullets.prefix(4).map { bullet -> String in
                let raw = bullet.lead.isEmpty ? bullet.text : "\(bullet.lead): \(bullet.text)"
                let cleaned = raw
                    .replacingOccurrences(of: #"^Speaker\s+\d+\s*:\s*"#, with: "", options: .regularExpression)
                return "• \(String(cleaned.prefix(180)))"
            }.joined(separator: "\n")
            let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(heading)\n\(bullets)"
        }
        return String(blocks.joined(separator: "\n\n").prefix(4_000))
    }

    /// Compress map partials directly — avoids a slow merge tree before polish.
    private func compressPartialsForPolish(_ partials: [String]) -> String {
        let stride = max(1, (partials.count + 5) / 6)
        var blocks: [String] = []
        var index = 0
        while index < partials.count && blocks.count < 6 {
            let end = min(index + stride, partials.count)
            let group = Array(partials[index..<end])
            var lines: [String] = []
            for partial in group {
                for line in partial.split(whereSeparator: \.isNewline) {
                    let trimmed = String(line)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "•- "))
                    guard trimmed.count >= 20 else { continue }
                    guard !trimmed.lowercased().hasPrefix("speaker ") else { continue }
                    lines.append("• \(String(trimmed.prefix(160)))")
                    if lines.count >= 5 { break }
                }
                if lines.count >= 5 { break }
            }
            let heading = group[0].split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Theme \(blocks.count + 1)"
            let title = (heading.count >= 6 && heading.count <= 48) ? heading : "Theme \(blocks.count + 1)"
            blocks.append("\(title)\n\(lines.joined(separator: "\n"))")
            index = end
        }
        return String(blocks.joined(separator: "\n\n").prefix(4_000))
    }

    private func isAcceptableFinalNote(_ digest: RAAmbientNoteDigest) -> Bool {
        let count = digest.sections.count
        guard (4...6).contains(count) else { return false }
        let bullets = digest.sections.reduce(0) { $0 + $1.bullets.count }
        guard bullets >= 10 else { return false }
        let garbage = digest.sections.contains { section in
            let h = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if h.count < 3 { return true }
            if h.lowercased().hasPrefix("part ") { return true }
            if h.lowercased() == "meeting summary" { return true }
            // Truncated ASR crumbs like "3: Uh" / "out to the"
            if h.count <= 12 && h.contains("Uh") { return true }
            if section.bullets.count == 1 && section.bullets[0].text.count > 600 { return true }
            return false
        }
        return !garbage
    }

    /// Fallback when the model won't synthesize: 5 themed buckets from map chunks.
    private func applyThematicPartialDraft(to record: inout AmbientSessionRecord) {
        applyCompactPartialDraft(to: &record, maxSections: 5)
        // Prefer clearer titles than raw first-line crumbs when possible.
        let themes = [
            "Goals & direction",
            "Product & SDK",
            "Go-to-market",
            "Open source & community",
            "Next steps",
        ]
        if record.digestSections.count == themes.count {
            for i in record.digestSections.indices {
                let heading = record.digestSections[i].heading
                if heading.count < 8 || heading.contains("Uh") || heading.lowercased().hasPrefix("part") {
                    record.digestSections[i].heading = themes[i]
                }
            }
        }
        record.digestTitle = "YC discussion"
        record.summary = record.digestSections.map { section in
            let body = section.bullets.map(\.text).joined(separator: "\n")
            return "\(section.heading)\n\(body)"
        }.joined(separator: "\n\n")
        // SDK polish path already harvests; thematic fallback just scrapes partials.
        let scraped = scrapeActionLines(from: record.partialSummaries.joined(separator: "\n"), max: 8)
        if !scraped.isEmpty {
            record.replaceMachineActionItems(with: scraped)
        }
    }

    private func scrapeActionLines(from text: String, max: Int) -> [String] {
        var seen = Set<String>()
        var items: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            var s = String(line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•- "))
            s = s.replacingOccurrences(
                of: #"^Speaker\s+\d+\s*:\s*"#,
                with: "",
                options: .regularExpression
            )
            guard s.count >= 18, s.count <= 160 else { continue }
            let low = s.lowercased()
            let looks =
                low.contains("follow up") || low.contains("follow-up")
                || low.contains("need to") || low.contains("should ")
                || low.contains("next step") || low.contains("pilot")
                || low.contains("schedule") || low.contains("define ")
            guard looks, seen.insert(low).inserted else { continue }
            items.append(s)
            if items.count >= max { break }
        }
        return items
    }

    /// Compact fallback: at most N sections from map partials.
    private func applyCompactPartialDraft(to record: inout AmbientSessionRecord, maxSections: Int = 6) {
        let partials = record.partialSummaries
        guard !partials.isEmpty else { return }
        let stride = max(1, (partials.count + maxSections - 1) / maxSections)
        var sections: [AmbientDigestSection] = []
        var index = 0
        while index < partials.count && sections.count < maxSections {
            let end = min(index + stride, partials.count)
            let group = Array(partials[index..<end])
            // Keep a few short bullets, not one giant blob.
            var bullets: [AmbientDigestBullet] = []
            for partial in group {
                for line in partial.split(whereSeparator: \.isNewline) {
                    let trimmed = String(line)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "•- "))
                    guard trimmed.count >= 24 else { continue }
                    guard !trimmed.lowercased().hasPrefix("speaker ") else { continue }
                    bullets.append(AmbientDigestBullet(text: String(trimmed.prefix(180))))
                    if bullets.count >= 5 { break }
                }
                if bullets.count >= 5 { break }
            }
            if bullets.isEmpty {
                bullets = [AmbientDigestBullet(text: String(group.joined(separator: " ").prefix(220)))]
            }
            let firstLine = group[0].split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Theme \(sections.count + 1)"
            let heading = (firstLine.count >= 8 && firstLine.count <= 48)
                ? firstLine
                : "Theme \(sections.count + 1)"
            sections.append(AmbientDigestSection(heading: heading, bullets: bullets))
            index = end
        }
        record.digestSections = sections
        record.summary = sections.map { section in
            let body = section.bullets.map { "• \($0.text)" }.joined(separator: "\n")
            return "\(section.heading)\n\(body)"
        }.joined(separator: "\n\n")
        let existingTitle = record.digestTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingTitle.isEmpty || existingTitle == "Meeting notes" {
            record.digestTitle = "Meeting notes"
        }
    }

    /// Re-run only the reduce pass over saved map chunks (fixes thin merges
    /// without redoing a 30‑min map).
    func remergeSummary(for noteID: String, modelID overrideModelID: String? = nil) async {
        guard !isSummarizing, !quietSummarizeInFlight else { return }
        guard !phase.holdsAudioSession else {
            lastError = "Stop the current recording before summarizing."
            return
        }
        guard var note = await store.loadSession(id: noteID) else { return }
        guard note.partialSummaries.count > 1 else {
            lastError = "Nothing to re-merge — this note has no map-pass chunks."
            return
        }
        let modelID = overrideModelID ?? note.digestModelID ?? selection?.digestModelID
        guard let modelID, !modelID.isEmpty else {
            lastError = "Pick a summarizing model, then try again."
            return
        }
        // Deep-link launch can still be inactive for a beat; wait briefly.
        for _ in 0..<20 where !canRunDigestNow {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard canRunDigestNow else {
            lastError = "Bring the app to the foreground to run the summarizer."
            return
        }
        isSummarizing = true
        quietPostASRUI = true
        quietSummarizeInFlight = true
        statusMessage = "Re-merging \(note.partialSummaries.count) chunks…"
        lastError = nil
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isSummarizing = false
            quietPostASRUI = false
            quietSummarizeInFlight = false
            UIApplication.shared.isIdleTimerDisabled = false
            digestChunkProgress = (0, 0)
        }
        await prepareExclusiveWarmKeep(for: .digester)
        note.digestModelID = modelID
        digestScratch = note
        note = await merged(note, modelID: modelID)
        digestScratch = nil
        sessionRecord = note
        didFinishDeferredMerge.send(note.id)
        if (4...6).contains(note.digestSections.count) {
            lastError = nil
            statusMessage = "Summary ready (\(note.digestSections.count) sections)."
        } else {
            lastError = "Note still has \(note.digestSections.count) sections — keep app unlocked and tap Rebuild again."
            statusMessage = lastError ?? "Summary ready."
        }
    }

    /// Summarization always needs the foreground. Stop-from-Lock-Screen leaves
    /// the process backgrounded, and both MLX and llama.cpp-on-Metal refuse
    /// GPU work there (`kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted`).
    /// Capture/ASR keep running; the note is marked `summaryPending` instead.
    private var canRunDigestNow: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// Summarization is user-triggered only (Summarize / Rewrite). Returning
    /// to the foreground no longer auto-loads the LLM.
    private func runDeferredDigests() async {
        // Intentionally empty — kept so the foreground observer can stay wired
        // for a future opt-in auto-finish without reintroducing silent loads.
    }

    /// Persist a resumable interrupted state if labeling was in flight when
    /// the app left the foreground (iOS may suspend before the pass finishes).
    private func markSpeakerLabelingInterruptedIfNeeded() async {
        guard isLabelingSpeakers, let noteID = sessionRecord?.id else { return }
        guard var note = await store.loadSession(id: noteID) else { return }
        guard note.speakerLabelingState == .loadingModel
            || note.speakerLabelingState == .labeling else { return }
        note.speakerLabelingState = .interrupted
        note.speakerLabelingDetail =
            "Labeling interrupted — your transcript is safe. Tap Resume to try again."
        await store.save(note)
        sessionRecord = note
        didFinishSpeakerLabeling.send(noteID)
    }

    @discardableResult
    private func ensureLoaded(
        modelID: String,
        category: RAModelCategory
    ) async throws -> (loadMs: Int, warmHit: Bool) {
        var request = RACurrentModelRequest()
        request.category = category
        if RunAnywhere.currentModel(request).modelID == modelID {
            return (0, true)
        }

        let started = Date()
        var load = RAModelLoadRequest()
        load.modelID = modelID
        load.category = category
        let result = await RunAnywhere.loadModel(load)
        let loadMs = Int(Date().timeIntervalSince(started) * 1000)
        guard result.success else {
            throw NSError(
                domain: "AmbientMemory",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: result.errorMessage]
            )
        }
        return (loadMs, false)
    }

    /// Free the digest LLM after summarize/retry so Notes does not keep it
    /// resident beside Chat or the next recording's ASR.
    private func unloadLanguageModel(_ modelID: String) async {
        var unload = RAModelUnloadRequest()
        unload.modelID = modelID
        unload.category = .language
        _ = await RunAnywhere.unloadModel(unload)
        if warmKeptDigestModelID == modelID {
            warmKeptDigestModelID = nil
        }
    }

    private func unloadLanguageModelUnlessWarm(_ modelID: String) async {
        performanceSettings = AmbientCapturePerformanceSettings.load()
        if performanceSettings.warmKeep == .digester {
            warmKeptDigestModelID = modelID
            warmKeptDiarizationModelID = nil
            logger.info("Warm-keeping digester \(modelID, privacy: .public)")
            return
        }
        await unloadLanguageModel(modelID)
    }

    /// Unload the opposite warm model before loading the requested post-ASR role.
    private func prepareExclusiveWarmKeep(for target: AmbientWarmKeepTarget) async {
        switch target {
        case .diarization:
            if let digestID = warmKeptDigestModelID {
                await unloadLanguageModel(digestID)
            }
        case .digester:
            if let diarID = warmKeptDiarizationModelID {
                await unloadDiarizationModel(diarID)
            }
        case .none:
            break
        }
    }

    /// ASR never shares RAM with a warm Sortformer or digester.
    private func releaseWarmModelsBeforeCapture() async {
        if let diarID = warmKeptDiarizationModelID {
            await unloadDiarizationModel(diarID)
        }
        if let digestID = warmKeptDigestModelID {
            await unloadLanguageModel(digestID)
        }
    }

    // MARK: - Streaming diarization during capture

    private static let defaultSortformerModelID = "diar-streaming-sortformer-4spk-v2.1"

    private func maybeStartStreamingDiarization(
        sessionID: String,
        conditions: AmbientDeviceConditions
    ) async {
        guard performanceSettings.canStreamDiarization(
            availableMemoryBytes: conditions.availableMemoryBytes,
            tier: conditions.tier
        ) else { return }

        let modelID = sessionRecord?.diarizationModelID
            ?? Self.defaultSortformerModelID
        guard isModelDownloaded(modelID) else {
            logger.info("Stream diar skipped — \(modelID, privacy: .public) not downloaded")
            return
        }

        do {
            let load = try await ensureLoaded(modelID: modelID, category: .speakerDiarization)
            benchmarkRecorder.markDiarizationLoad(ms: load.loadMs, warmHit: load.warmHit)
        } catch {
            logger.warning(
                "Stream diar load failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        var continuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data> { continuation = $0 }
        diarAudioContinuation = continuation
        streamingDiarModelID = modelID
        if var record = sessionRecord {
            record.diarizationModelID = modelID
            record.speakerLabelingState = .labeling
            record.speakerLabelingDetail = "Labeling speakers during capture…"
            sessionRecord = record
            await store.save(record)
        }

        var options = RADiarizationOptions.defaults()
        options.sampleRateHz = 16_000
        options.channelCount = 1
        options.encoding = .pcmS16Le

        diarStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let events = try await RunAnywhere.diarizeStream(audio: stream, options: options)
                for try await event in events {
                    self.consumeStreamingDiarEvent(event)
                }
            } catch {
                self.logger.warning(
                    "Stream diar ended: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        benchmarkRecorder.markStreamDiarUsed()
        logger.info(
            "Streaming Sortformer during capture for \(sessionID, privacy: .public)"
        )
    }

    private func consumeStreamingDiarEvent(_ event: RADiarizationStreamEvent) {
        switch event.kind {
        case .update, .final:
            latestStreamingDiarResult = event.result
        case .error:
            logger.warning("Stream diar error event")
        default:
            break
        }
    }

    private func teeDiarAudio(_ data: Data) {
        diarAudioContinuation?.yield(data)
    }

    private func finishStreamingDiarization() async {
        diarAudioContinuation?.finish()
        diarAudioContinuation = nil
        await diarStreamTask?.value
        diarStreamTask = nil

        let modelID = streamingDiarModelID
        streamingDiarModelID = nil
        guard let modelID else { return }

        if var note = sessionRecord, let result = latestStreamingDiarResult {
            let turns = AmbientSpeakerAlignment.turns(from: result)
            let assignments = AmbientSpeakerAlignment.assignments(
                segments: note.segments,
                turns: turns
            )
            if !assignments.isEmpty {
                note.applyDiarizationLabels(
                    assignments,
                    modelID: modelID,
                    speakerCount: Int(result.speakerCount)
                )
                sessionRecord = note
                await store.save(note)
                didFinishSpeakerLabeling.send(note.id)
            } else if note.speakerLabelingState == .labeling {
                note.speakerLabelingState = .modelSelected
                note.speakerLabelingDetail = "Live labeling finished — tap Label speakers if needed."
                sessionRecord = note
                await store.save(note)
            }
        }
        latestStreamingDiarResult = nil
        benchmarkRecorder.markMemoryAfterDiarization()
        await unloadDiarizationModelUnlessWarm(modelID)
    }

    private func isModelDownloaded(_ modelID: String) -> Bool {
        guard let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelID })
        else { return false }
        return model.isBuiltIn || model.localPathURL != nil
    }

    // MARK: - Audio Engine

    private func requestMicrophone() async -> Bool {
        guard await audioCapture.requestPermission() else {
            fail("Microphone access is required to record a note.")
            return false
        }
        return true
    }

    /// True while a cellular / FaceTime / VoIP call still owns the audio route.
    private static var isInPhoneCall: Bool {
        CXCallObserver().calls.contains { !$0.hasEnded }
    }

    private func startAudioEngine(feeding session: RAAmbientSession) async -> Bool {
        if Self.isInPhoneCall {
            fail("End the phone call first — the green call indicator in the status bar means the mic is busy.")
            return false
        }
        do {
            // Warm the session before the engine so a stale category left by
            // TTS / model-picker playback does not fail the first attempt.
            // The engine start then skips reconfiguration to avoid a second
            // deactivate/activate race against mediaserverd.
            try await audioCapture.activateAudioSession()
            try await AudioCapturePump.startRecording(
                with: audioCapture,
                configureSession: false
            ) { [weak self] data in
                guard let self else { return }
                self.audioLevel = self.audioCapture.audioLevel
                guard self.phase.isRecording else { return }
                session.ingest(pcm16: data)
                self.teeDiarAudio(data)
                // Every buffer goes to the recording, not just the speech the
                // detector kept, so playback is the room as it sounded rather
                // than a cut of detected utterances.
                if self.isWritingAudio { self.appendToRecording(data) }
            }
            return true
        } catch {
            if Self.isInPhoneCall {
                fail("End the phone call first — the green call indicator in the status bar means the mic is busy.")
            } else {
                let detail = error.localizedDescription
                fail(
                    "Could not start the microphone: \(detail). "
                        + "End any call, close other apps using the mic, then try Record again."
                )
            }
            return false
        }
    }

    /// Writes are chained rather than fired off independently: separate tasks
    /// entering the store actor have no ordering guarantee, and a WAV whose
    /// buffers land out of order is a scrambled recording.
    private func appendToRecording(_ data: Data) {
        let previous = audioWriteTask
        audioWriteTask = Task { [store] in
            await previous?.value
            await store.appendRecording(data)
        }
    }

    /// Drain queued writes before closing, so the last seconds of a note are in
    /// the file when its header is stamped with the final length.
    private func closeRecording() async {
        await audioWriteTask?.value
        audioWriteTask = nil
        await store.finishRecording()
    }

    // MARK: - Interruptions and External Stop

    private func observeInterruptions() {
        let center = NotificationCenter.default
        interruptionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleAudioInterruption(notification) }
        })

        interruptionObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stop(reason: "Audio services were reset") }
        })

        interruptionObservers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleThermalChange() }
        })
    }

    /// GPU summarization can only run on screen, so returning to the
    /// foreground is the trigger for anything that had to wait.
    private func observeForeground() {
        interruptionObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.markSpeakerLabelingInterruptedIfNeeded() }
        })

        interruptionObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Give iOS a beat after unlock before Metal work; immediate
                // generate right on didBecomeActive still races the GPU gate.
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard UIApplication.shared.applicationState == .active else { return }
                await self?.runDeferredDigests()
            }
        })
    }

    /// The Live Activity's Stop button and the App Intent both signal through
    /// the shared Darwin channel, so a stop from outside the app is honored.
    private func observeStopRequests() {
        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.ambientStopRequested
        ) { [weak self] in
            Task { @MainActor in await self?.stop(reason: "Stopped from the Lock Screen") }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        guard phase.isRecording || phase == .paused else { return }

        switch type {
        case .began:
            benchmarkRecorder.markInterruption()
            Task { await stop(reason: "Interrupted by a call or another app") }
        case .ended:
            // iOS will not let a backgrounded app restart the engine, so the
            // session stays stopped and the user restarts it explicitly.
            statusMessage = "Interruption ended. Start a new session when you are ready."
        @unknown default:
            break
        }
    }

    private func handleThermalChange() async {
        let conditions = AmbientModelProfileResolver().currentConditions(
            deviceInfo: DeviceInfoService.shared.deviceInfo
        )
        guard phase.isRecording else { return }

        if conditions.shouldStopCapture {
            await stop(reason: "Device reached a critical thermal state")
            return
        }
        await session?.report(gate: RAAmbientResourceGate(
            reason: .thermal,
            isActive: conditions.shouldSuspendDerivedWork,
            detail: "Thermal state: \(conditions.thermalDescription)"
        ))
    }

    private func hasStorageHeadroom(for bytes: Int) async -> Bool {
        let available = await store.availableCapacityBytes()
        return available == 0 || available > Int64(bytes) + Self.storageFloorBytes
    }

    /// A long note can fill the disk. Recording stops on its own when space
    /// runs low; transcription keeps going, because the text is what matters.
    private func stopRecordingAudioIfStorageIsLow() async {
        guard isWritingAudio,
              await !hasStorageHeadroom(for: Self.recordingHeadroomBytes) else { return }
        isWritingAudio = false
        await closeRecording()
        apply(RAAmbientResourceGate(
            reason: .storage,
            isActive: true,
            detail: "Low storage — the recording stopped, transcription continues"
        ))
    }

    // MARK: - Live Activity

    @available(iOS 16.1, *)
    private func startLiveActivity(sessionID: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities disabled — ambient session runs without one")
            return
        }
        do {
            liveActivity = try Activity.request(
                attributes: AmbientActivityAttributes(sessionId: sessionID),
                content: .init(state: currentActivityState(), staleDate: nil),
                pushType: nil
            )
        } catch {
            logger.warning("Ambient Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateLiveActivityIfNeeded() {
        guard #available(iOS 16.1, *), let activity = liveActivity else { return }
        let state = currentActivityState()
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    @available(iOS 16.1, *)
    private func endLiveActivity() async {
        guard let activity = liveActivity else { return }
        var state = currentActivityState()
        state.isStopped = true
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        liveActivity = nil
    }

    /// Force-quit / crash can leave a Dynamic Island / Lock Screen activity
    /// with no owning process. End every Ambient activity that is not the
    /// one for the current in-memory session.
    func dismissOrphanLiveActivities() async {
        guard #available(iOS 16.1, *) else { return }
        let keepID = liveActivity?.id
        for activity in Activity<AmbientActivityAttributes>.activities where activity.id != keepID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @available(iOS 16.1, *)
    private func currentActivityState() -> AmbientActivityAttributes.ContentState {
        AmbientActivityAttributes.ContentState(
            phase: phase.liveActivityPhase,
            timerStart: liveActivityTimerStart,
            elapsedSeconds: elapsedSeconds,
            segmentCount: sessionRecord?.segments.count ?? 0,
            actionItemCount: sessionRecord?.actionItems.count ?? 0,
            isStopped: !phase.isRecording && phase != .paused
        )
    }

    // MARK: - Timer

    private func startElapsedTimer() {
        liveActivityTimerStart = Date()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.phase.isRecording || self.phase == .paused else { break }
                // Keep in-app elapsed in sync with the Live Activity timer
                // anchor so pause/resume and the Notes UI stay honest even if
                // a background Task tick is delayed.
                if self.phase.isRecording {
                    self.elapsedSeconds = max(
                        0,
                        Int(Date().timeIntervalSince(self.liveActivityTimerStart))
                    )
                }
                // Segment counts still need an ActivityKit push; the clock itself
                // ticks in the widget via Text(..., style: .timer).
                if self.elapsedSeconds % 15 == 0 {
                    self.updateLiveActivityIfNeeded()
                }
                if self.elapsedSeconds % 30 == 0 {
                    await self.stopRecordingAudioIfStorageIsLow()
                }
            }
        }
    }

    // MARK: - Helpers

    private static let storageFloorBytes: Int64 = 500_000_000
    /// Roughly ten minutes of 16 kHz mono PCM, the headroom a note needs before
    /// it is worth opening a recording at all.
    private static let recordingHeadroomBytes = 20_000_000
    private static let captureSampleRate = 16_000

    private func reset() {
        elapsedSeconds = 0
        liveActivityTimerStart = Date()
        liveTranscript = ""
        activeGates.removeAll()
        lastError = nil
        statusMessage = ""
        sessionRecord = nil
        pendingChunk = ""
        isWritingAudio = false
    }

    private func transition(to next: AmbientSessionPhase) {
        guard phase != next else { return }
        phase = next
        logger.debug("Ambient phase → \(next.rawValue, privacy: .public)")
    }

    private func fail(_ message: String) {
        lastError = message
        statusMessage = message
        transition(to: .failed)
        logger.error("Ambient session failed to start: \(message, privacy: .public)")
    }
}

// MARK: - Phase

/// UI-facing session phase. Distinct from the SDK's pipeline state because it
/// also covers permission/model preparation and terminal app-side outcomes.
enum AmbientSessionPhase: String, Sendable {
    case idle
    case preparing
    case listening
    case capturingSpeech
    case transcribing
    case processing
    case paused
    case stopped
    case failed

    var isRecording: Bool {
        switch self {
        case .listening, .capturingSpeech, .transcribing:
            return true
        default:
            return false
        }
    }

    /// A paused session keeps the engine running so it can resume instantly,
    /// and `preparing`/`processing` bracket the same resources, so all of them
    /// count as holding the microphone.
    var holdsAudioSession: Bool {
        switch self {
        case .idle, .stopped, .failed:
            return false
        default:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "Not recording"
        case .preparing: return "Preparing models"
        case .listening: return "Listening"
        case .capturingSpeech: return "Capturing speech"
        case .transcribing: return "Transcribing"
        case .processing: return "Finishing up"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .failed: return "Stopped on an error"
        }
    }

    var liveActivityPhase: String {
        switch self {
        case .capturingSpeech: return "speech"
        case .transcribing, .processing: return "processing"
        case .paused: return "paused"
        case .preparing: return "preparing"
        default: return "listening"
        }
    }
}
#endif
