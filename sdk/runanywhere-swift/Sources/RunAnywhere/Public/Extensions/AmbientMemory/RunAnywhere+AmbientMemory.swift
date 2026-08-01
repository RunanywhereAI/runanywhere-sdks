//
//  RunAnywhere+AmbientMemory.swift
//  RunAnywhere SDK
//
//  Public API for the ambient-memory solution — one entry point that composes
//  VAD, segmentation, transcription, structured memory extraction, and RAG
//  recall for long-running "listen and remember" experiences.
//
//  Division of responsibility:
//    - Host: microphone acquisition, foreground/background policy, consent UI,
//      storage, retention, and everything the platform gates.
//    - SDK: model loading, VAD debounce, pre/post-roll, segment boundaries,
//      serial transcription scheduling, extraction prompts, and RAG plumbing.
//
//  Hosts start a session, push Int16 PCM into the handle, and consume the
//  handle's `events` stream. They never drive the individual stages.
//

import Foundation

// MARK: - Session Handle

/// Live handle to one ambient-memory session.
///
/// The handle is the host's only interface to a running pipeline: feed it
/// audio, read its events, and end it. It is safe to use from any isolation
/// domain.
public final class RAAmbientSession: Sendable {

    /// Identifier shared by every segment, transcript, and memory this session
    /// produces. Hosts persist it to group a recording.
    public let id: String

    /// Ordered lifecycle events. Finishes after `finish()` / `cancel()` or a
    /// fatal pipeline failure.
    public let events: AsyncStream<RAAmbientEvent>

    private let configuration: RAAmbientConfiguration
    private let pipeline: AmbientMemoryPipeline
    private let audio: AsyncStream<Data>.Continuation
    private let runTask: Task<Void, Never>

    private init(
        id: String,
        configuration: RAAmbientConfiguration,
        events: AsyncStream<RAAmbientEvent>,
        pipeline: AmbientMemoryPipeline,
        audio: AsyncStream<Data>.Continuation,
        runTask: Task<Void, Never>
    ) {
        self.id = id
        self.configuration = configuration
        self.events = events
        self.pipeline = pipeline
        self.audio = audio
        self.runTask = runTask
    }

    /// Push one microphone chunk of Int16 PCM at the configured sample rate.
    ///
    /// Non-blocking. The pipeline buffers a bounded number of chunks; if the
    /// host outruns detection, the oldest chunks are dropped rather than
    /// growing memory without limit.
    public func ingest(pcm16: Data) {
        guard !pcm16.isEmpty else { return }
        audio.yield(pcm16)
    }

    /// Offline / file-feed ingest that waits until VAD has processed the chunk.
    ///
    /// Use this for imported WAV/m4a dogfood so the host never outruns the
    /// bounded live-audio buffer (which would silently drop most of a long file).
    public func ingestOffline(pcm16: Data) async {
        guard !pcm16.isEmpty else { return }
        await pipeline.ingestOffline(pcm16)
    }

    /// Stop consuming audio while keeping segment and queue state.
    public func pause() async {
        await pipeline.pause()
    }

    public func resume() async {
        await pipeline.resume()
    }

    /// Surface a host-detected condition (thermal, memory, storage) on the
    /// session's event stream so consumers see one ordered timeline.
    public func report(gate: RAAmbientResourceGate) async {
        await pipeline.report(gate: gate)
    }

    /// Close the open segment, transcribe everything queued, then end the
    /// session. Returns once the event stream has finished.
    public func finish() async {
        audio.finish()
        await runTask.value
    }

    /// End immediately and discard queued transcription work. Use when the
    /// microphone is lost or the host must release resources now.
    public func cancel(reason: String) async {
        audio.finish()
        await pipeline.abort(RAAmbientFailure(
            stage: .ingestion,
            message: reason,
            isFatal: true
        ))
        runTask.cancel()
    }

    // MARK: Factory

    static func start(
        id: String,
        configuration: RAAmbientConfiguration
    ) async throws -> RAAmbientSession {
        let (events, eventContinuation) = AsyncStream.makeStream(of: RAAmbientEvent.self)
        let pipeline = AmbientMemoryPipeline(
            sessionID: id,
            configuration: configuration,
            continuation: eventContinuation
        )

        do {
            try await pipeline.prepare()
        } catch {
            eventContinuation.finish()
            throw error
        }

        // Bounded so a host feeding faster than the detector can drain sheds
        // the oldest audio instead of accumulating unbounded PCM.
        let (audio, audioContinuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingNewest(configuration.maxQueuedAudioChunks)
        )
        let runTask = Task { await pipeline.run(audio: audio) }

        return RAAmbientSession(
            id: id,
            configuration: configuration,
            events: events,
            pipeline: pipeline,
            audio: audioContinuation,
            runTask: runTask
        )
    }
}

// MARK: - Ambient Capability

public extension RunAnywhere {

    /// Capability accessor for the ambient-memory solution.
    /// Mirrors the shape of `RunAnywhere.solutions` / `RunAnywhere.lora`.
    static var ambient: AmbientMemory { AmbientMemory() }

    /// Stateless namespace for ambient-memory APIs. Each session owns its own
    /// pipeline, so this type holds no mutable state.
    struct AmbientMemory: Sendable {

        /// Internal so the namespace is only reachable through
        /// `RunAnywhere.ambient` rather than constructed by callers.
        init() {}

        /// Load the configured VAD/STT models and open an ambient session.
        ///
        /// - Parameters:
        ///   - configuration: Segmentation and model tuning for this session.
        ///   - sessionID: Stable id for the recording. Supply your own when
        ///     the host already minted one for persistence.
        /// - Returns: A started session ready to receive audio.
        /// - Throws: `SDKException` when the SDK is not initialized or a
        ///   required model cannot be loaded.
        public func start(
            _ configuration: RAAmbientConfiguration,
            sessionID: String = UUID().uuidString
        ) async throws -> RAAmbientSession {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await RunAnywhere.ensureServicesReady()

            return try await RAAmbientSession.start(id: sessionID, configuration: configuration)
        }

        /// Summarize text into one summary plus action items using the
        /// currently loaded language model.
        ///
        /// Call with `.chunk` while capture runs to digest each block of
        /// transcript, then once with `.merge` over the joined partial
        /// summaries to produce the note's final summary and a deduplicated
        /// action list. The prompt, JSON contract, and response repair all
        /// live here so hosts never post-process model output themselves.
        public func digest(
            text: String,
            mode: RAAmbientDigestMode = .chunk,
            maxActionItems: Int = 8
        ) async throws -> RAAmbientNoteDigest {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            let snapshot = RunAnywhere.loadedModelSnapshot(category: .language)
            guard snapshot.found else {
                throw SDKException(
                    code: .modelNotLoaded,
                    message: "Ambient note summarization requires a loaded language model",
                    category: .component
                )
            }

            let startedAt = Date()
            var options = RALLMGenerationOptions.defaults()
            options.temperature = 0.1
            // Structured Notion-style digests need more room than a short prose blob.
            options.maxTokens = 1_024
            // Thinking models (e.g. Qwen3) otherwise emit <think>…</think> before
            // JSON; parse then falls back to a transcript snippet and empty
            // action items — which looks like a "failed rewrite".
            options.disableThinking = true
            options.systemPrompt = AmbientDigestPrompt.system(mode: mode, maxActionItems: maxActionItems)
            let result = try await RunAnywhere.generate(
                prompt: AmbientDigestPrompt.user(text: text, mode: mode),
                options: options
            )

            let parsed = AmbientDigestPrompt.parse(result.text, fallbackText: text)
            let cited = Array(parsed.actionItems.prefix(maxActionItems))
            return RAAmbientNoteDigest(
                summary: parsed.summary,
                actionItems: cited.map(\.text),
                extractionMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                modelID: snapshot.modelID,
                title: parsed.title,
                sections: parsed.sections,
                citedActionItems: cited
            )
        }

        /// Ingest a finalized transcript into the RAG index with ambient
        /// provenance attached, so recall results can be traced back to the
        /// session, segment, and capture time they came from.
        ///
        /// The RAG pipeline must already be created via
        /// `RunAnywhere.ragCreatePipeline(...)`.
        @discardableResult
        public func index(
            transcript: RAAmbientTranscript,
            extraMetadata: [String: String] = [:]
        ) async throws -> RARAGStatistics {
            var document = RARAGDocument()
            document.id = transcript.segmentID
            document.text = transcript.text
            document.mediaType = "text/plain"
            document.metadata = extraMetadata.merging([
                "source": "ambient-memory",
                "sessionId": transcript.sessionID,
                "segmentId": transcript.segmentID,
                "segmentIndex": String(transcript.segmentIndex),
                "capturedAt": ISO8601DateFormatter().string(from: transcript.startedAt),
                "sttModelId": transcript.modelID,
            ]) { provided, _ in provided }

            return try await RunAnywhere.ragIngest(document)
        }

        /// Answer a recall question over previously indexed ambient
        /// transcripts. Retrieval and LLM synthesis both happen on-device.
        public func recall(
            question: String,
            options: RARAGQueryOptions? = nil
        ) async throws -> RARAGResult {
            try await RunAnywhere.ragQuery(question: question, options: options)
        }
    }
}

// MARK: - Configuration Derivations

extension RAAmbientConfiguration {
    /// Audio chunks the ingestion stream buffers before shedding the oldest.
    /// Scaled off the segment queue depth so both backpressure limits move
    /// together when a host tunes for a slower device.
    var maxQueuedAudioChunks: Int {
        max(16, maxQueuedSegments * 16)
    }
}

