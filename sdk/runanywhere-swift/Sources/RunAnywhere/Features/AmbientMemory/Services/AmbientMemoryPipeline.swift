//
//  AmbientMemoryPipeline.swift
//  RunAnywhere SDK
//
//  The composed ambient-memory pipeline: VAD debounce, pre/post-roll,
//  segment finalization, and serially-scheduled transcription.
//
//  Hosts never see this type. They start a session through
//  `RunAnywhere.ambient.start(...)`, push microphone PCM into the returned
//  handle, and consume `RAAmbientEvent`s. Keeping the loop here — rather than
//  in each app — is what makes the ambient feature one SDK entry point
//  instead of a multi-stage orchestration every consumer reimplements.
//

import Foundation

/// Serialised owner of one ambient session's audio state machine.
///
/// Reentrancy is deliberate: `transcribe` suspends the actor so incoming audio
/// keeps being framed and segmented while a previous segment is still being
/// transcribed. Transcription itself stays serial because only the single
/// drain task pulls from `pendingTranscriptions`.
actor AmbientMemoryPipeline {

    // MARK: - Segment Accumulation

    private struct OpenSegment {
        let index: Int
        let startedAt: Date
        /// Sample index into the ingested (non-paused) recording timeline at
        /// the first sample of this segment, including pre-roll.
        let startOffsetSamples: Int
        var samples: [Int16]
        var peakConfidence: Float
        /// Audio appended since the last speech frame, used to trim the tail
        /// back to the configured post-roll when the segment closes.
        var trailingSilenceSamples: Int
    }

    private struct PendingTranscription {
        let segment: RAAmbientSegment
        let samples: [Int16]
    }

    // MARK: - Stored State

    private let sessionID: String
    private let configuration: RAAmbientConfiguration
    private let continuation: AsyncStream<RAAmbientEvent>.Continuation
    private let logger = SDKLogger(category: "AmbientMemory")

    private let frameSampleCount: Int
    private let frameDurationMs: Int
    private let preRollCapacity: Int
    private let postRollSampleCount: Int
    private let maxSegmentSampleCount: Int

    private var state: RAAmbientState = .idle
    private var isPaused = false
    private var isFinished = false

    /// Samples received but not yet aligned into a whole detector frame.
    private var frameRemainder: [Int16] = []
    /// Rolling window kept while no segment is open, so an opened segment can
    /// reach back across the debounce window plus the configured pre-roll.
    private var preRoll: [Int16] = []

    private var openSegment: OpenSegment?
    private var speechRunMs = 0
    private var silenceRunMs = 0
    private var nextSegmentIndex = 0
    /// Samples ingested while not paused. Matches the continuous WAV timeline
    /// the host writes, so diarization can align without wall-clock dates.
    private var ingestedSampleCount = 0

    private var pendingTranscriptions: [PendingTranscription] = []
    private var drainTask: Task<Void, Never>?
    private var isBackpressureActive = false

    /// Rolling frame energies for adaptive economy/hybrid thresholds.
    private var recentEnergies: [Float] = []
    private var hybridFrameCounter = 0
    private var lastNeuralResult: RAVADResult?

    // MARK: - Init

    init(
        sessionID: String,
        configuration: RAAmbientConfiguration,
        continuation: AsyncStream<RAAmbientEvent>.Continuation
    ) {
        self.sessionID = sessionID
        self.configuration = configuration
        self.continuation = continuation

        let frameSamples = configuration.vadFrameSampleCount
        self.frameSampleCount = frameSamples
        self.frameDurationMs = max(1, frameSamples * 1000 / max(1, configuration.sampleRate))
        self.preRollCapacity = Self.sampleCount(
            forMs: configuration.preRollMs + configuration.speechDebounceMs,
            sampleRate: configuration.sampleRate
        )
        self.postRollSampleCount = Self.sampleCount(
            forMs: configuration.postRollMs,
            sampleRate: configuration.sampleRate
        )
        self.maxSegmentSampleCount = Self.sampleCount(
            forMs: configuration.maxSegmentMs,
            sampleRate: configuration.sampleRate
        )
    }

    // MARK: - Lifecycle

    /// Load the configured VAD and STT models, then arm the detector.
    /// Throws only when a model the session cannot run without fails to load.
    func prepare() async throws {
        transition(to: .preparing)

        if configuration.requiresNeuralVAD {
            try await loadModel(
                id: configuration.vadModelID,
                category: .voiceActivityDetection,
                label: "VAD"
            )
            try? await RunAnywhere.resetVAD()
        } else {
            logger.info("Ambient economy VAD — skipping neural VAD load")
        }
        try await loadModel(
            id: configuration.sttModelID,
            category: .speechRecognition,
            label: "STT"
        )

        transition(to: .listening)
    }

    /// Consume host audio until the stream closes, then flush and stop.
    func run(audio: AsyncStream<Data>) async {
        for await chunk in audio {
            guard !isFinished else { break }
            await ingest(chunk)
        }
        await finish()
    }

    func pause() {
        guard !isFinished, !isPaused else { return }
        isPaused = true
        transition(to: .paused)
    }

    func resume() {
        guard !isFinished, isPaused else { return }
        isPaused = false
        transition(to: openSegment == nil ? .listening : .speechSegment)
    }

    /// Forward a host-observed condition (thermal, memory, storage) onto the
    /// same event stream so consumers have one ordered source of truth.
    func report(gate: RAAmbientResourceGate) {
        guard !isFinished else { return }
        continuation.yield(.resourceGate(gate))
    }

    /// Close any open segment, drain queued transcriptions, and end the stream.
    func finish() async {
        guard !isFinished else { return }
        isFinished = true

        if openSegment != nil {
            closeSegment(reason: .sessionEnd, at: Date())
        }
        await drainTask?.value

        transition(to: .stopped)
        continuation.finish()
    }

    /// End the session immediately, discarding queued work. Used when the host
    /// loses the microphone or hits a fatal error.
    func abort(_ failure: RAAmbientFailure) {
        guard !isFinished else { return }
        isFinished = true

        drainTask?.cancel()
        drainTask = nil
        pendingTranscriptions.removeAll()
        openSegment = nil

        continuation.yield(.failure(failure))
        transition(to: .failed)
        continuation.finish()
    }

    // MARK: - Ingestion

    /// File-feed entry point used by `RAAmbientSession.ingestOffline`.
    func ingestOffline(_ chunk: Data) async {
        await ingest(chunk)
    }

    private func ingest(_ chunk: Data) async {
        guard !isPaused, !isFinished else { return }

        frameRemainder.append(contentsOf: Self.int16Samples(from: chunk))
        while frameRemainder.count >= frameSampleCount, !isFinished {
            let frame = Array(frameRemainder.prefix(frameSampleCount))
            frameRemainder.removeFirst(frameSampleCount)
            await processFrame(frame)
        }
    }

    private func processFrame(_ frame: [Int16]) async {
        // Count every non-paused frame so offsets stay aligned with the host WAV.
        ingestedSampleCount += frame.count

        let energy = Self.frameRMS(frame)
        rememberEnergy(energy)
        let energyResult = energySpeechResult(energy: energy)

        let result: RAVADResult
        switch configuration.vadMode {
        case .economy:
            result = energyResult

        case .silero:
            do {
                result = try await runNeuralVAD(frame: frame)
            } catch {
                continuation.yield(.failure(RAAmbientFailure(
                    stage: .vad,
                    message: "Voice activity detection failed: \(error.localizedDescription)",
                    isFatal: false
                )))
                return
            }

        case .hybrid:
            // Energy silence while idle skips Silero entirely. When energy is
            // hot or a segment is open, Silero runs on a hop schedule.
            let needsNeural = energyResult.isSpeech || openSegment != nil
            if needsNeural {
                hybridFrameCounter += 1
                let hop = configuration.hybridSileroHopFrames
                if hybridFrameCounter >= hop || lastNeuralResult == nil {
                    hybridFrameCounter = 0
                    do {
                        let neural = try await runNeuralVAD(frame: frame)
                        lastNeuralResult = neural
                        result = neural
                    } catch {
                        // Fall back to energy rather than dropping the frame.
                        result = energyResult
                    }
                } else {
                    result = lastNeuralResult ?? energyResult
                }
            } else {
                hybridFrameCounter = 0
                lastNeuralResult = nil
                result = energyResult
            }
        }

        guard result.errorMessage.isEmpty else {
            continuation.yield(.failure(RAAmbientFailure(
                stage: .vad,
                message: result.errorMessage,
                isFatal: false
            )))
            return
        }

        if openSegment == nil {
            advanceWhileIdle(frame: frame, result: result)
        } else {
            advanceWhileSpeaking(frame: frame, result: result)
        }
    }

    private func runNeuralVAD(frame: [Int16]) async throws -> RAVADResult {
        let float32 = Self.float32Data(from: frame)
        return try await RunAnywhere.detectVoiceActivity(
            float32,
            options: configuration.vadOptions
        )
    }

    private func rememberEnergy(_ energy: Float) {
        recentEnergies.append(energy)
        if recentEnergies.count > 200 {
            recentEnergies.removeFirst(recentEnergies.count - 200)
        }
    }

    /// Offline-style adaptive RMS threshold mapped onto a single live frame.
    private func energySpeechResult(energy: Float) -> RAVADResult {
        let sorted = recentEnergies.sorted()
        let noiseIdx = min(sorted.count - 1, max(0, sorted.count / 10))
        let noise = sorted.isEmpty ? 0 : sorted[noiseIdx]
        let threshold = max(350, noise * 3.5)
        let isSpeech = energy >= threshold
        var result = RAVADResult()
        result.isSpeech = isSpeech
        result.confidence = min(1, energy / 8_000)
        return result
    }

    /// No segment open: keep a rolling pre-roll window and wait for enough
    /// continuous speech to clear the debounce threshold.
    private func advanceWhileIdle(frame: [Int16], result: RAVADResult) {
        preRoll.append(contentsOf: frame)
        if preRoll.count > preRollCapacity {
            preRoll.removeFirst(preRoll.count - preRollCapacity)
        }

        guard result.isSpeech else {
            speechRunMs = 0
            return
        }

        speechRunMs += frameDurationMs
        guard speechRunMs >= configuration.speechDebounceMs else { return }

        let startedAt = Date()
        let index = nextSegmentIndex
        nextSegmentIndex += 1
        let startOffsetSamples = max(0, ingestedSampleCount - preRoll.count)
        openSegment = OpenSegment(
            index: index,
            startedAt: startedAt,
            startOffsetSamples: startOffsetSamples,
            samples: preRoll,
            peakConfidence: result.confidence,
            trailingSilenceSamples: 0
        )
        preRoll.removeAll(keepingCapacity: true)
        speechRunMs = 0
        silenceRunMs = 0

        continuation.yield(.speechStarted(at: startedAt))
        continuation.yield(.segmentOpened(
            id: Self.segmentID(sessionID: sessionID, index: index),
            index: index,
            startedAt: startedAt
        ))
        transition(to: .speechSegment)
    }

    /// Segment open: accumulate audio, then close on sustained silence or when
    /// the segment hits its length cap.
    private func advanceWhileSpeaking(frame: [Int16], result: RAVADResult) {
        guard var segment = openSegment else { return }

        segment.samples.append(contentsOf: frame)
        if result.isSpeech {
            segment.peakConfidence = max(segment.peakConfidence, result.confidence)
            segment.trailingSilenceSamples = 0
            silenceRunMs = 0
        } else {
            segment.trailingSilenceSamples += frame.count
            silenceRunMs += frameDurationMs
        }
        openSegment = segment

        if silenceRunMs >= configuration.silenceHangoverMs {
            closeSegment(reason: .silence, at: Date())
        } else if segment.samples.count >= maxSegmentSampleCount {
            closeSegment(reason: .lengthCap, at: Date())
        }
    }

    // MARK: - Segment Finalization

    private enum CloseReason {
        case silence
        case lengthCap
        case sessionEnd
    }

    private func closeSegment(reason: CloseReason, at endedAt: Date) {
        guard let segment = openSegment else { return }
        openSegment = nil
        silenceRunMs = 0
        speechRunMs = 0

        var samples = segment.samples
        // Only a silence-triggered close has a measured silent tail to trim;
        // the length cap and session end stop mid-speech.
        if reason == .silence, segment.trailingSilenceSamples > postRollSampleCount {
            samples.removeLast(segment.trailingSilenceSamples - postRollSampleCount)
        }

        let durationMs = Self.durationMs(sampleCount: samples.count, sampleRate: configuration.sampleRate)
        continuation.yield(.speechEnded(at: endedAt, durationMs: durationMs))

        guard durationMs >= configuration.minSegmentMs else {
            logger.debug(
                "Dropping \(durationMs)ms ambient segment below the "
                + "\(self.configuration.minSegmentMs)ms floor"
            )
            transition(to: pendingTranscriptions.isEmpty && drainTask == nil ? .listening : .processing)
            return
        }

        let startOffsetMs = Self.durationMs(
            sampleCount: segment.startOffsetSamples,
            sampleRate: configuration.sampleRate
        )
        let endOffsetMs = startOffsetMs + durationMs
        let record = RAAmbientSegment(
            id: Self.segmentID(sessionID: sessionID, index: segment.index),
            sessionID: sessionID,
            index: segment.index,
            startedAt: segment.startedAt,
            endedAt: endedAt,
            durationMs: durationMs,
            sampleRate: configuration.sampleRate,
            peakConfidence: segment.peakConfidence,
            pcm16: configuration.retainSegmentAudio ? Self.pcm16Data(from: samples) : nil,
            startOffsetMs: startOffsetMs,
            endOffsetMs: endOffsetMs
        )
        continuation.yield(.segmentFinalized(record))
        enqueue(PendingTranscription(segment: record, samples: samples))
    }

    // MARK: - Serial Transcription

    private func enqueue(_ job: PendingTranscription) {
        pendingTranscriptions.append(job)

        while pendingTranscriptions.count > configuration.maxQueuedSegments {
            let dropped = pendingTranscriptions.removeFirst()
            isBackpressureActive = true
            continuation.yield(.resourceGate(RAAmbientResourceGate(
                reason: .backpressure,
                isActive: true,
                detail: "Dropped segment \(dropped.segment.index): transcription is behind capture"
            )))
        }

        transition(to: .processing)
        startDrainingIfNeeded()
    }

    private func startDrainingIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !pendingTranscriptions.isEmpty, !Task.isCancelled {
            let job = pendingTranscriptions.removeFirst()
            await transcribe(job)
        }
        drainTask = nil

        if isBackpressureActive {
            isBackpressureActive = false
            continuation.yield(.resourceGate(RAAmbientResourceGate(
                reason: .backpressure,
                isActive: false,
                detail: "Transcription caught up with capture"
            )))
        }

        guard !isFinished else { return }
        transition(to: openSegment == nil ? .listening : .speechSegment)
    }

    private func transcribe(_ job: PendingTranscription) async {
        let startedAt = Date()
        do {
            let output = try await RunAnywhere.transcribe(
                audio: Self.pcm16Data(from: job.samples),
                options: configuration.sttOptions
            )
            guard output.errorMessage.isEmpty else {
                yieldTranscriptionFailure(output.errorMessage, segmentID: job.segment.id)
                return
            }

            let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                logger.debug("Ambient segment \(job.segment.index) transcribed to empty text; skipping")
                return
            }

            continuation.yield(.transcript(RAAmbientTranscript(
                id: job.segment.id,
                sessionID: sessionID,
                segmentID: job.segment.id,
                segmentIndex: job.segment.index,
                text: text,
                confidence: output.confidence,
                languageCode: output.hasLanguageCode ? output.languageCode : "",
                startedAt: job.segment.startedAt,
                endedAt: job.segment.endedAt,
                audioDurationMs: job.segment.durationMs,
                transcriptionMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                modelID: configuration.sttModelID
            )))
        } catch {
            yieldTranscriptionFailure(error.localizedDescription, segmentID: job.segment.id)
        }
    }

    private func yieldTranscriptionFailure(_ message: String, segmentID: String) {
        continuation.yield(.failure(RAAmbientFailure(
            stage: .transcription,
            message: message,
            isFatal: false,
            segmentID: segmentID
        )))
    }

    // MARK: - Helpers

    private func loadModel(id: String, category: RAModelCategory, label: String) async throws {
        guard !id.isEmpty else {
            throw SDKException(
                code: .invalidArgument,
                message: "Ambient memory requires a \(label) model id",
                category: .validation
            )
        }

        let snapshot = RunAnywhere.loadedModelSnapshot(category: category)
        if snapshot.found, snapshot.modelID == id { return }

        var request = RAModelLoadRequest()
        request.modelID = id
        request.category = category
        let result = await RunAnywhere.loadModel(request)
        guard result.success else {
            let failure = RAAmbientFailure(
                stage: .modelLoad,
                message: "\(label) model '\(id)' failed to load: \(result.errorMessage)",
                isFatal: true
            )
            continuation.yield(.failure(failure))
            throw SDKException(code: .modelLoadFailed, message: failure.message, category: .component)
        }
    }

    private func transition(to next: RAAmbientState) {
        guard state != next else { return }
        state = next
        continuation.yield(.state(next))
    }

    private static func segmentID(sessionID: String, index: Int) -> String {
        "\(sessionID)-seg-\(String(format: "%06d", index))"
    }

    private static func sampleCount(forMs milliseconds: Int, sampleRate: Int) -> Int {
        max(0, milliseconds * sampleRate / 1000)
    }

    private static func durationMs(sampleCount: Int, sampleRate: Int) -> Int {
        guard sampleRate > 0 else { return 0 }
        return sampleCount * 1000 / sampleRate
    }

    private static func int16Samples(from data: Data) -> [Int16] {
        let count = data.count / MemoryLayout<Int16>.size
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(
                start: raw.baseAddress?.assumingMemoryBound(to: Int16.self),
                count: count
            ))
        }
    }

    private static func pcm16Data(from samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func float32Data(from samples: [Int16]) -> Data {
        let floats = samples.map { Float($0) / 32_768.0 }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func frameRMS(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var acc: Float = 0
        for sample in samples {
            let v = Float(sample)
            acc += v * v
        }
        return sqrt(acc / Float(samples.count))
    }
}
