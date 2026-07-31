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

    /// Selection the active (or most recent) session ran with.
    @Published private(set) var selection: AmbientModelSelection?
    @Published private(set) var retentionPolicy: AmbientRetentionPolicy = .retainAudio

    /// Fires when a note that stopped in the background finally gets the
    /// summary it had to defer, so the notes list can refresh that row.
    let didFinishDeferredMerge = PassthroughSubject<String, Never>()

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
    /// True while the note is recording audio to disk, so a storage gate can
    /// stop writing without ending the note.
    private var isWritingAudio = false

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
        transition(to: .preparing)
        statusMessage = "Loading \(selection.asrModelID)…"

        guard await requestMicrophone() else { return }

        let sessionID = UUID().uuidString
        var configuration = RAAmbientConfiguration.defaults(sttModelID: selection.asrModelID)
        configuration.vadModelID = selection.vadModelID
        // The note keeps its own continuous recording, so the pipeline does not
        // need to hand back per-segment audio as well.
        configuration.retainSegmentAudio = false

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

        consumeEvents(from: started)
        benchmarkRecorder.begin(sessionID: sessionID, conditions: conditions)
        if #available(iOS 16.1, *) { startLiveActivity(sessionID: sessionID) }
        startElapsedTimer()

        transition(to: .listening)
        statusMessage = "Listening. Lock the screen if you like — recording stays visible."
        logger.info("Ambient session \(sessionID, privacy: .public) started")
    }

    // MARK: - Stop / Pause

    /// Stop capture, finish in-flight transcription, summarize, and save.
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

        sessionRecord?.endedAt = Date()
        sessionRecord?.stopReason = reason

        statusMessage = "Writing the summary…"
        await summarizeNote()

        if let record = sessionRecord {
            await store.save(record)
            await benchmarkRecorder.finish(record: record, store: store)
        }

        if #available(iOS 16.1, *) { await endLiveActivity() }
        audioLevel = 0
        transition(to: .stopped)
        statusMessage = reason.map { "Stopped: \($0)" } ?? "Note saved."
    }

    func pause() async {
        guard phase.isRecording else { return }
        await session?.pause()
        transition(to: .paused)
        statusMessage = "Paused. The microphone stays open but nothing is captured."
    }

    func resume() async {
        guard phase == .paused else { return }
        await session?.resume()
        transition(to: .listening)
        statusMessage = "Listening."
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

    /// Roughly one page of transcript. Small enough that a 0.6B model still has
    /// room for its answer, large enough that the summary has real context.
    private static let chunkCharacterLimit = 2_000

    /// Buffer finalized transcript and digest it a chunk at a time, so a
    /// two-hour note is summarized as it happens rather than in one impossible
    /// pass at the end.
    private func accumulate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingChunk += pendingChunk.isEmpty ? trimmed : " " + trimmed
        guard pendingChunk.count >= Self.chunkCharacterLimit else { return }
        scheduleChunkDigest()
    }

    /// Digests are chained onto a single task so LLM work stays serialized
    /// behind transcription and never runs two generations at once.
    private func scheduleChunkDigest() {
        guard selection?.digestModelID != nil, !pendingChunk.isEmpty else { return }
        guard activeGates[.thermal] == nil, activeGates[.memory] == nil else {
            logger.info("Holding the chunk digest while a resource gate is active")
            return
        }
        // A Metal model cannot run while the screen is locked, and the whole
        // point of the feature is that capture survives locking. The text is
        // kept in the buffer and digested on return to the foreground.
        guard canRunDigestNow else {
            logger.info("Deferring chunk digest until the app is foregrounded")
            return
        }

        let chunk = pendingChunk
        pendingChunk = ""
        let previous = digestTask
        digestTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            // Re-check inside the task: the phone may have locked between
            // schedule and run, and Metal work from background always fails.
            await self.digestChunk(chunk)
        }
    }

    private func digestChunk(_ chunk: String) async {
        let modelID = selection?.digestModelID ?? sessionRecord?.digestModelID
        guard let modelID else { return }
        guard canRunDigestNow else {
            // Restore the text and wait for foreground — never touch Metal here.
            pendingChunk = chunk + (pendingChunk.isEmpty ? "" : " " + pendingChunk)
            if var record = sessionRecord {
                record.summaryPending = true
                sessionRecord = record
                await store.save(record)
            }
            logger.info("Chunk digest deferred — app is not in the foreground")
            return
        }
        do {
            try await ensureLoaded(modelID: modelID, category: .language)
            // Screen can lock during model load; refuse generate if it did.
            guard canRunDigestNow else {
                pendingChunk = chunk + (pendingChunk.isEmpty ? "" : " " + pendingChunk)
                logger.info("Chunk digest aborted after load — app left the foreground")
                return
            }
            let digest = try await RunAnywhere.ambient.digest(text: chunk, mode: .chunk)
            guard var record = sessionRecord else { return }
            record.partialSummaries.append(digest.summary)
            record.mergeActionItems(digest.actionItems)
            // Until the merge runs, the joined partials are the best summary
            // the note has, so a crash mid-recording still leaves it readable.
            if record.summary.isEmpty || record.summaryPending {
                record.summary = record.partialSummaries.joined(separator: "\n\n")
            }
            record.summaryPending = false
            sessionRecord = record
            benchmarkRecorder.markDigest(digest)
            await store.save(record)
            updateLiveActivityIfNeeded()
        } catch {
            // Put the text back so the next attempt still covers it.
            pendingChunk = chunk + (pendingChunk.isEmpty ? "" : " " + pendingChunk)
            let detail = error.localizedDescription
            logger.warning("Chunk digest failed: \(detail, privacy: .public)")
            if var record = sessionRecord {
                record.summaryPending = true
                sessionRecord = record
                await store.save(record)
            }
        }
    }

    /// Digest the tail of the transcript, then fold every partial summary into
    /// the one summary and action list the note keeps.
    private func summarizeNote() async {
        guard var record = sessionRecord else { return }
        let modelID = selection?.digestModelID ?? record.digestModelID
        guard let modelID else {
            logger.info("No digest model on the note — skipping summary")
            return
        }

        guard canRunDigestNow else {
            // Stop can arrive from the Live Activity or a Shortcut while the
            // app is backgrounded. Segments are already on disk, so the next
            // foreground can digest `fullTranscript` even with no partials yet.
            record.summaryPending = true
            if record.summary.isEmpty {
                record.summary = record.partialSummaries.joined(separator: "\n\n")
            }
            sessionRecord = record
            await store.save(record)
            logger.info("Merge deferred to the foreground for note \(record.id, privacy: .public)")
            return
        }

        if !pendingChunk.isEmpty {
            let tail = pendingChunk
            pendingChunk = ""
            await digestChunk(tail)
        }

        guard var current = sessionRecord else { return }
        // Short notes never hit the mid-session chunk threshold. If the live
        // buffer digest failed (or was empty), summarize from the persisted
        // transcript so a working STT note is never left summary-less.
        if current.partialSummaries.isEmpty {
            let source = current.fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty {
                pendingChunk = ""
                await digestChunk(source)
                current = sessionRecord ?? current
            }
        }

        let finished = await merged(current, modelID: modelID)
        if finished.summary.isEmpty, !finished.fullTranscript.isEmpty {
            var pending = finished
            pending.summaryPending = true
            sessionRecord = pending
            await store.save(pending)
            statusMessage = "Note saved. Summary still pending — open the note and tap Retry."
            logger.warning(
                "Summarization produced no summary for note \(pending.id, privacy: .public)"
            )
        } else {
            sessionRecord = finished
        }
    }

    /// Re-run summarization for a saved note that has a transcript but no
    /// summary (failed digest, deferred GPU work, etc.).
    func retrySummary(for noteID: String) async {
        guard !phase.holdsAudioSession else {
            lastError = "Stop the current recording before retrying a summary."
            return
        }
        guard var note = await store.loadSession(id: noteID) else { return }
        guard let modelID = note.digestModelID ?? selection?.digestModelID else {
            lastError = "Pick a summarizing model on Notes, then retry."
            return
        }
        guard canRunDigestNow else {
            lastError = "Bring the app to the foreground to finish the summary."
            return
        }

        statusMessage = "Writing the summary…"
        note.summaryPending = true
        note.digestModelID = modelID
        await store.save(note)

        if note.partialSummaries.isEmpty {
            let source = note.fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else {
                note.summaryPending = false
                await store.save(note)
                statusMessage = "Nothing to summarize — this note has no transcript."
                return
            }
            do {
                try await ensureLoaded(modelID: modelID, category: .language)
                guard canRunDigestNow else {
                    note.summaryPending = true
                    await store.save(note)
                    lastError = "Bring the app to the foreground to finish the summary."
                    statusMessage = lastError ?? ""
                    return
                }
                let digest = try await RunAnywhere.ambient.digest(text: source, mode: .chunk)
                note.partialSummaries = [digest.summary]
                note.mergeActionItems(digest.actionItems)
                note.summary = digest.summary
                benchmarkRecorder.markDigest(digest)
            } catch {
                note.summaryPending = true
                await store.save(note)
                lastError = "Summarization failed: \(error.localizedDescription)"
                statusMessage = lastError ?? ""
                return
            }
        }

        let finished = await merged(note, modelID: modelID)
        if sessionRecord?.id == finished.id { sessionRecord = finished }
        didFinishDeferredMerge.send(finished.id)
        statusMessage = finished.summary.isEmpty
            ? "Summary still empty — try a different summarizing model."
            : "Summary updated."
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
            let source = record.fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty {
                do {
                    try await ensureLoaded(modelID: modelID, category: .language)
                    guard canRunDigestNow else {
                        record.summaryPending = true
                        await store.save(record)
                        return record
                    }
                    let digest = try await RunAnywhere.ambient.digest(text: source, mode: .chunk)
                    record.partialSummaries = [digest.summary]
                    record.mergeActionItems(digest.actionItems)
                    record.summary = digest.summary
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
            let joined = record.partialSummaries.enumerated()
                .map { "Part \($0.offset + 1): \($0.element)" }
                .joined(separator: "\n\n")
            let digest = try await RunAnywhere.ambient.digest(text: joined, mode: .merge)
            record.summary = digest.summary
            record.replaceMachineActionItems(with: digest.actionItems)
            benchmarkRecorder.markDigest(digest)
        } catch {
            record.summary = record.partialSummaries.joined(separator: "\n\n")
            let detail = error.localizedDescription
            logger.warning("Merge failed, keeping the partial summaries: \(detail, privacy: .public)")
        }
        record.summaryPending = false
        await store.save(record)
        return record
    }

    /// Summarization always needs the foreground. Stop-from-Lock-Screen leaves
    /// the process backgrounded, and both MLX and llama.cpp-on-Metal refuse
    /// GPU work there (`kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted`).
    /// Capture/ASR keep running; the note is marked `summaryPending` instead.
    private var canRunDigestNow: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// Finish anything that had to wait for the GPU to become usable again:
    /// the current note's buffered chunks, and any note that stopped while
    /// backgrounded and never got its merge.
    private func runDeferredDigests() async {
        if phase.holdsAudioSession {
            if !pendingChunk.isEmpty { scheduleChunkDigest() }
            return
        }

        for note in await store.loadSessions() where note.summaryPending {
            guard let modelID = note.digestModelID else { continue }
            let finished = await merged(note, modelID: modelID)
            if sessionRecord?.id == finished.id { sessionRecord = finished }
            didFinishDeferredMerge.send(finished.id)
        }
    }

    private func ensureLoaded(modelID: String, category: RAModelCategory) async throws {
        var request = RACurrentModelRequest()
        request.category = category
        // Always reload. A prior stop-from-Lock-Screen attempt can leave the
        // Metal/llama.cpp backend wedged (`backend is in error state`), and
        // skipping load then makes every foreground retry fail too.
        if RunAnywhere.currentModel(request).modelID == modelID {
            var unload = RAModelUnloadRequest()
            unload.modelID = modelID
            unload.category = category
            _ = await RunAnywhere.unloadModel(unload)
        }

        var load = RAModelLoadRequest()
        load.modelID = modelID
        load.category = category
        let result = await RunAnywhere.loadModel(load)
        guard result.success else {
            throw NSError(
                domain: "AmbientMemory",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: result.errorMessage]
            )
        }
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
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4))
        liveActivity = nil
    }

    @available(iOS 16.1, *)
    private func currentActivityState() -> AmbientActivityAttributes.ContentState {
        AmbientActivityAttributes.ContentState(
            phase: phase.liveActivityPhase,
            elapsedSeconds: elapsedSeconds,
            segmentCount: sessionRecord?.segments.count ?? 0,
            actionItemCount: sessionRecord?.actionItems.count ?? 0,
            isStopped: !phase.isRecording && phase != .paused
        )
    }

    // MARK: - Timer

    private func startElapsedTimer() {
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.phase.isRecording || self.phase == .paused else { break }
                self.elapsedSeconds += 1
                if self.elapsedSeconds % 5 == 0 {
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
