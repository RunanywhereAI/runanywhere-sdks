//
//  Handles.swift
//  RunAnywhere SDK
//
//  v4 ownership handles: LoadedModel, SpeechHandle, SttStream, VadStream,
//  and SDKCapabilities. Follows LiteRT/ExecuTorch residency ownership and
//  LiveKit speech/stream lifecycle conventions.
//

import Foundation

// MARK: - AudioEncoding

/// Sample layout for a live audio stream, established once per `AudioFormatSpec`.
public typealias AudioEncoding = RAAudioEncoding

/// Container format for encoded (non-raw-PCM) audio.
public typealias AudioFormat = RAAudioFormat

// MARK: - AcceleratorPolicy / BackendPreference

/// Preferred accelerator class at load time.
public enum AcceleratorPolicy: Sendable {
    case auto
    case cpu
    case gpu
    case npu
}

/// Ordered backend preference for model load.
public struct BackendPreference: Sendable {
    public var backend: InferenceFramework
    public var required: Bool

    public init(backend: InferenceFramework, required: Bool = false) {
        self.backend = backend
        self.required = required
    }
}

/// Where a loaded model actually runs.
public struct DevicePlacement: Sendable {
    public let deviceId: String
    public let deviceName: String
    public let deviceKind: String

    public init(deviceId: String = "", deviceName: String = "", deviceKind: String = "unknown") {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceKind = deviceKind
    }
}

// MARK: - LoadedModel

/// Resident ownership handle returned by `models.load`.
///
/// Closing the handle (or calling `models.unload(id:)`) releases runtime
/// memory without deleting downloaded artifacts.
public final class LoadedModel: @unchecked Sendable {
    public let id: String
    public let category: ModelCategory
    public let requestedBackend: InferenceFramework?
    public let actualBackend: InferenceFramework
    public let actualDevice: DevicePlacement
    public let runtimeVersion: String?
    public let abiVersion: String?
    public let fallbackReason: String?

    private let closeHandler: @Sendable (String) async throws -> Void
    private let lock = NSLock()
    private var closed = false

    init(
        id: String,
        category: ModelCategory,
        requestedBackend: InferenceFramework?,
        actualBackend: InferenceFramework,
        actualDevice: DevicePlacement,
        runtimeVersion: String? = nil,
        abiVersion: String? = nil,
        fallbackReason: String? = nil,
        closeHandler: @escaping @Sendable (String) async throws -> Void
    ) {
        self.id = id
        self.category = category
        self.requestedBackend = requestedBackend
        self.actualBackend = actualBackend
        self.actualDevice = actualDevice
        self.runtimeVersion = runtimeVersion
        self.abiVersion = abiVersion
        self.fallbackReason = fallbackReason
        self.closeHandler = closeHandler
    }

    /// Release this resident model. Idempotent.
    public func close() async throws {
        let shouldClose: Bool = {
            lock.lock()
            defer { lock.unlock() }
            if closed { return false }
            closed = true
            return true
        }()
        guard shouldClose else { return }
        try await closeHandler(id)
    }
}

// MARK: - SpeechHandle

/// Playback handle returned by `tts.speak` and `VoiceSession.say`.
public final class SpeechHandle: @unchecked Sendable {
    public let id: String

    private let lock = NSLock()
    private var _interrupted = false
    private var _error: Error?
    private var _done = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let interruptHandler: @Sendable () async -> Void

    init(id: String = UUID().uuidString, interruptHandler: @escaping @Sendable () async -> Void) {
        self.id = id
        self.interruptHandler = interruptHandler
    }

    public var interrupted: Bool {
        lock.lock(); defer { lock.unlock() }
        return _interrupted
    }

    public var error: Error? {
        lock.lock(); defer { lock.unlock() }
        return _error
    }

    /// Interrupt this utterance only.
    public func interrupt() async {
        markInterrupted()
        await interruptHandler()
        finish()
    }

    private func markInterrupted() {
        lock.lock()
        defer { lock.unlock() }
        _interrupted = true
    }

    /// Await until playout completes, is interrupted, or fails.
    public func waitForPlayout() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if _done {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func complete(error: Error? = nil) {
        lock.lock()
        if let error { _error = error }
        lock.unlock()
        finish()
    }

    private func finish() {
        lock.lock()
        guard !_done else { lock.unlock(); return }
        _done = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in pending { waiter.resume() }
    }
}

// MARK: - AudioFormatSpec / AudioFrame

/// Format established once for a live audio stream.
public struct AudioFormatSpec: Sendable {
    public var encoding: AudioEncoding
    public var sampleRate: Int
    public var channels: Int
    public var container: AudioFormat?

    public init(
        encoding: AudioEncoding,
        sampleRate: Int,
        channels: Int = 1,
        container: AudioFormat? = nil
    ) {
        self.encoding = encoding
        self.sampleRate = sampleRate
        self.channels = channels
        self.container = container
    }
}

/// One PCM frame for a live STT/VAD stream.
public struct AudioFrame: Sendable {
    public var samples: Data
    public var sampleCount: Int
    public var timestampMs: Int64?

    public init(samples: Data, sampleCount: Int, timestampMs: Int64? = nil) {
        self.samples = samples
        self.sampleCount = sampleCount
        self.timestampMs = timestampMs
    }
}

// MARK: - SttStream / VadStream

/// Live transcription stream: push frames, then flush/finish/close.
public final class SttStream: @unchecked Sendable {
    public let events: AsyncThrowingStream<TranscriptionEvent, Error>
    private let pushHandler: @Sendable (AudioFrame) -> Void
    private let flushHandler: @Sendable () -> Void
    private let finishHandler: @Sendable () -> Void
    private let closeHandler: @Sendable () async -> Void
    private let lock = NSLock()
    private var closed = false

    init(
        events: AsyncThrowingStream<TranscriptionEvent, Error>,
        pushHandler: @escaping @Sendable (AudioFrame) -> Void,
        flushHandler: @escaping @Sendable () -> Void,
        finishHandler: @escaping @Sendable () -> Void,
        closeHandler: @escaping @Sendable () async -> Void
    ) {
        self.events = events
        self.pushHandler = pushHandler
        self.flushHandler = flushHandler
        self.finishHandler = finishHandler
        self.closeHandler = closeHandler
    }

    public func pushFrame(_ frame: AudioFrame) { pushHandler(frame) }
    public func flush() { flushHandler() }
    public func finish() { finishHandler() }

    public func close() async {
        guard markClosed() else { return }
        await closeHandler()
    }

    /// Returns `true` the first time it is called; idempotent afterward.
    private func markClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }
        closed = true
        return true
    }
}

/// Live VAD stream: push frames, then flush/finish/close.
public final class VadStream: @unchecked Sendable {
    public let events: AsyncThrowingStream<VadEvent, Error>
    private let pushHandler: @Sendable (AudioFrame) -> Void
    private let flushHandler: @Sendable () -> Void
    private let finishHandler: @Sendable () -> Void
    private let closeHandler: @Sendable () async -> Void
    private let lock = NSLock()
    private var closed = false

    init(
        events: AsyncThrowingStream<VadEvent, Error>,
        pushHandler: @escaping @Sendable (AudioFrame) -> Void,
        flushHandler: @escaping @Sendable () -> Void,
        finishHandler: @escaping @Sendable () -> Void,
        closeHandler: @escaping @Sendable () async -> Void
    ) {
        self.events = events
        self.pushHandler = pushHandler
        self.flushHandler = flushHandler
        self.finishHandler = finishHandler
        self.closeHandler = closeHandler
    }

    public func pushFrame(_ frame: AudioFrame) { pushHandler(frame) }
    public func flush() { flushHandler() }
    public func finish() { finishHandler() }

    public func close() async {
        guard markClosed() else { return }
        await closeHandler()
    }

    /// Returns `true` the first time it is called; idempotent afterward.
    private func markClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }
        closed = true
        return true
    }
}

// MARK: - StructuredEnforcementMode / RagQueryOptions / SDKCapabilities

/// How structured output is enforced for `generateStructured`.
public enum StructuredEnforcementMode: Sendable, Equatable {
    /// Engine-constrained decoding when available.
    case constrained
    /// Generate freely, then validate against the schema.
    case validationOnly
    /// Validate and attempt repair retries.
    case repair
}

/// Retrieval + generation options for one RAG query.
public struct RagQueryOptions: Sendable {
    public var retrievalTopK: Int?
    public var similarityThreshold: Float?
    public var generation: LlmOptions?

    public init(
        retrievalTopK: Int? = nil,
        similarityThreshold: Float? = nil,
        generation: LlmOptions? = nil
    ) {
        self.retrievalTopK = retrievalTopK
        self.similarityThreshold = similarityThreshold
        self.generation = generation
    }
}

/// Packaged and executable surface reported by `RunAnywhere.capabilities()`.
public struct SDKCapabilities: Sendable {
    public var modalities: [String]
    public var backends: [InferenceFramework]
    public var audioFormats: [AudioFormat]
    public var streaming: StreamingCapabilities
    public var tools: ToolCapabilities
    public var rag: RagCapabilities
    public var unavailable: [UnavailableCapability]

    public struct StreamingCapabilities: Sendable {
        public var llmTokenStream: Bool
        public var sttLiveFrames: Bool
        public var ttsAudioChunks: Bool
        public var vadLiveFrames: Bool
        public var voiceSession: Bool

        public init(
            llmTokenStream: Bool = true,
            sttLiveFrames: Bool = true,
            ttsAudioChunks: Bool = true,
            vadLiveFrames: Bool = true,
            voiceSession: Bool = true
        ) {
            self.llmTokenStream = llmTokenStream
            self.sttLiveFrames = sttLiveFrames
            self.ttsAudioChunks = ttsAudioChunks
            self.vadLiveFrames = vadLiveFrames
            self.voiceSession = voiceSession
        }
    }

    public struct ToolCapabilities: Sendable {
        public var registry: Bool
        public var parallel: Bool
        public var cancellation: Bool

        public init(registry: Bool = true, parallel: Bool = false, cancellation: Bool = false) {
            self.registry = registry
            self.parallel = parallel
            self.cancellation = cancellation
        }
    }

    public struct RagCapabilities: Sendable {
        public var multiSession: Bool
        public var persistent: Bool

        public init(multiSession: Bool = true, persistent: Bool = false) {
            self.multiSession = multiSession
            self.persistent = persistent
        }
    }

    public struct UnavailableCapability: Sendable {
        public var name: String
        public var reason: String

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }
}
