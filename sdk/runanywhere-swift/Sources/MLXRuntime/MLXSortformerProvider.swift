//
//  MLXSortformerProvider.swift
//  MLXRuntime
//


import Foundation
import MLX
import MLXAudioVAD
import os

struct MLXSortformerCatalogFile: Equatable, Sendable {
    let url: URL
    let filename: String
    let sizeBytes: Int64
    let sha256: String
}

/// Immutable metadata for the reviewed four-speaker Sortformer MLX bundle.
enum MLXSortformerCatalog {
    static let modelID = "mlx-sortformer-4spk-v2.1-fp16"
    static let repository = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    static let revision = "e23e6404bd9859e93edbf94a740eb1c7fc58f12e"
    static let maximumSpeakerCount = 4
    static let supportedSampleRate = 16_000

    private static let baseURL =
        "https://huggingface.co/\(repository)/resolve/\(revision)"

    static let files: [MLXSortformerCatalogFile] = [
        makeFile(
            filename: "config.json",
            sizeBytes: 1_702,
            sha256: "17c9f943bed07b0593f2b8dca01e0be6a418053becc6148b01ecabdff9cbd84d"
        ),
        makeFile(
            filename: "model.safetensors",
            sizeBytes: 236_108_132,
            sha256: "3b60b8df29e59a8abaf8061ceeeae6e9284a68fbcd2e762c68f5e058bfceebfa"
        )
    ]

    static let downloadSizeBytes = files.reduce(Int64(0)) { total, file in
        total + file.sizeBytes
    }

    static func missingFileNames(in directory: URL) -> [String] {
        files.compactMap { file in
            let path = directory.appendingPathComponent(file.filename).path
            return FileManager.default.fileExists(atPath: path) ? nil : file.filename
        }
    }

    static func validateModelDirectory(_ directory: URL) throws {
        let missingFiles = missingFileNames(in: directory)
        guard missingFiles.isEmpty else {
            throw MLXSortformerProviderError.missingBundleFiles(missingFiles)
        }
    }

    private static func makeFile(
        filename: String,
        sizeBytes: Int64,
        sha256: String
    ) -> MLXSortformerCatalogFile {
        guard let url = URL(string: "\(baseURL)/\(filename)") else {
            preconditionFailure("Invalid pinned Sortformer URL for \(filename)")
        }
        return MLXSortformerCatalogFile(
            url: url,
            filename: filename,
            sizeBytes: sizeBytes,
            sha256: sha256
        )
    }
}

struct MLXSortformerOptions: Equatable, Sendable {
    var sampleRate = MLXSortformerCatalog.supportedSampleRate
    var threshold: Float = 0.5
    var minimumDuration: Float = 0
    var mergeGap: Float = 0
    var chunkDuration: Float = 5
    var speakerCacheFrames = 188
    var fifoFrames = 188

    func validateConfiguration() throws {
        guard sampleRate == MLXSortformerCatalog.supportedSampleRate else {
            throw MLXSortformerProviderError.unsupportedSampleRate(sampleRate)
        }
        guard (0...1).contains(threshold) else {
            throw MLXSortformerProviderError.invalidThreshold(threshold)
        }
        guard minimumDuration >= 0 else {
            throw MLXSortformerProviderError.invalidMinimumDuration(minimumDuration)
        }
        guard mergeGap >= 0 else {
            throw MLXSortformerProviderError.invalidMergeGap(mergeGap)
        }
        guard chunkDuration > 0 else {
            throw MLXSortformerProviderError.invalidChunkDuration(chunkDuration)
        }
        guard speakerCacheFrames > 0, fifoFrames > 0 else {
            throw MLXSortformerProviderError.invalidStreamingCacheSize
        }
    }

    func validate(sampleCount: Int) throws {
        guard sampleCount > 0 else {
            throw MLXSortformerProviderError.emptyAudio
        }
        try validateConfiguration()
    }
}

struct MLXSortformerSegment: Equatable, Sendable {
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let speakerIndex: Int
    let speakerID: String

    init(_ segment: DiarizationSegment) {
        startMilliseconds = Int64((Double(segment.start) * 1_000).rounded())
        endMilliseconds = Int64((Double(segment.end) * 1_000).rounded())
        speakerIndex = segment.speaker
        speakerID = "speaker_\(segment.speaker)"
    }
}

struct MLXSortformerResult: Equatable, Sendable {
    let segments: [MLXSortformerSegment]
    let activeSpeakerCount: Int
    let audioDurationMilliseconds: Int64
    let processingTimeMilliseconds: Int64

    init(_ output: DiarizationOutput, sampleCount: Int, sampleRate: Int) {
        segments = output.segments.map(MLXSortformerSegment.init)
        activeSpeakerCount = output.numSpeakers
        audioDurationMilliseconds = Int64(sampleCount * 1_000 / sampleRate)
        processingTimeMilliseconds = Int64((output.totalTime * 1_000).rounded())
    }

    init(
        segments: [MLXSortformerSegment],
        sampleCount: Int,
        sampleRate: Int,
        processingTimeMilliseconds: Int64
    ) {
        self.segments = segments
        activeSpeakerCount = Set(segments.map(\.speakerIndex)).count
        audioDurationMilliseconds = Int64(sampleCount * 1_000 / sampleRate)
        self.processingTimeMilliseconds = processingTimeMilliseconds
    }
}

enum MLXSortformerProviderError: Error, Equatable, LocalizedError {
    case emptyAudio
    case unsupportedSampleRate(Int)
    case invalidThreshold(Float)
    case invalidMinimumDuration(Float)
    case invalidMergeGap(Float)
    case invalidChunkDuration(Float)
    case invalidStreamingCacheSize
    case missingBundleFiles([String])
    case providerBusy
    case streamClosed

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "Sortformer requires at least one audio sample."
        case .unsupportedSampleRate(let sampleRate):
            return "Sortformer requires 16 kHz mono audio; received \(sampleRate) Hz."
        case .invalidThreshold(let threshold):
            return "Sortformer threshold must be between 0 and 1; received \(threshold)."
        case .invalidMinimumDuration(let duration):
            return "Sortformer minimum duration cannot be negative; received \(duration)."
        case .invalidMergeGap(let gap):
            return "Sortformer merge gap cannot be negative; received \(gap)."
        case .invalidChunkDuration(let duration):
            return "Sortformer streaming chunk duration must be positive; received \(duration)."
        case .invalidStreamingCacheSize:
            return "Sortformer streaming cache sizes must be positive."
        case .missingBundleFiles(let filenames):
            return "Sortformer bundle is missing required files: \(filenames.joined(separator: ", "))."
        case .providerBusy:
            return "Sortformer is already processing an audio stream."
        case .streamClosed:
            return "Sortformer stream is closed."
        }
    }
}

/// One persistent Sortformer stream backed by upstream `StreamingState`.
///
/// Each feed supplies only the newly-arrived samples to `SortformerModel.feed`.
/// The accumulated result is returned as a complete session snapshot, matching
/// the Commons diarization stream contract. The state lock rejects overlapping
/// feeds and makes close-vs-feed safe without holding a lock across `await`.
final class MLXSortformerPersistentStream: @unchecked Sendable {
    private struct State: @unchecked Sendable {
        var upstream: StreamingState
        var segments: [MLXSortformerSegment] = []
        var totalSampleCount = 0
        var processingTimeMilliseconds: Int64 = 0
        var feedInFlight = false
        var closed = false
        var providerLeaseReleased = false
    }

    private let model: SortformerModel
    private let options: MLXSortformerOptions
    private let onClose: @Sendable () -> Void
    private let state: OSAllocatedUnfairLock<State>

    init(
        model: SortformerModel,
        options: MLXSortformerOptions,
        upstream: StreamingState,
        onClose: @escaping @Sendable () -> Void
    ) {
        self.model = model
        self.options = options
        self.onClose = onClose
        state = OSAllocatedUnfairLock(initialState: State(upstream: upstream))
    }

    deinit {
        close()
    }

    func feed(samples: [Float]) async throws -> MLXSortformerResult {
        guard !samples.isEmpty else { return try flush() }
        let upstream = try state.withLock { current -> StreamingState in
            guard !current.closed else { throw MLXSortformerProviderError.streamClosed }
            guard !current.feedInFlight else { throw MLXSortformerProviderError.providerBusy }
            current.feedInFlight = true
            return current.upstream
        }

        let started = Date()
        do {
            let (output, nextState) = try await model.feed(
                chunk: MLXArray(samples),
                state: upstream,
                sampleRate: options.sampleRate,
                threshold: options.threshold,
                minDuration: options.minimumDuration,
                mergeGap: options.mergeGap,
                spkcacheMax: options.speakerCacheFrames,
                fifoMax: options.fifoFrames
            )
            try Task.checkCancellation()
            let elapsed = max(0, Int64(Date().timeIntervalSince(started) * 1_000))
            let result = try state.withLock { current -> MLXSortformerResult in
                defer { current.feedInFlight = false }
                guard !current.closed else { throw MLXSortformerProviderError.streamClosed }
                current.upstream = nextState
                current.segments.append(contentsOf: output.segments.map(MLXSortformerSegment.init))
                current.totalSampleCount += samples.count
                current.processingTimeMilliseconds += elapsed
                return Self.snapshot(current, sampleRate: options.sampleRate)
            }
            releaseProviderLeaseIfNeeded()
            return result
        } catch {
            state.withLock { $0.feedInFlight = false }
            releaseProviderLeaseIfNeeded()
            throw error
        }
    }

    func flush() throws -> MLXSortformerResult {
        try state.withLock { current in
            guard !current.closed else { throw MLXSortformerProviderError.streamClosed }
            guard !current.feedInFlight else { throw MLXSortformerProviderError.providerBusy }
            return Self.snapshot(current, sampleRate: options.sampleRate)
        }
    }

    func close() {
        state.withLock { $0.closed = true }
        releaseProviderLeaseIfNeeded()
    }

    private func releaseProviderLeaseIfNeeded() {
        let shouldRelease = state.withLock { current -> Bool in
            guard current.closed, !current.feedInFlight, !current.providerLeaseReleased else {
                return false
            }
            current.providerLeaseReleased = true
            return true
        }
        if shouldRelease {
            onClose()
        }
    }

    private static func snapshot(_ state: State, sampleRate: Int) -> MLXSortformerResult {
        MLXSortformerResult(
            segments: state.segments,
            sampleCount: state.totalSampleCount,
            sampleRate: sampleRate,
            processingTimeMilliseconds: state.processingTimeMilliseconds
        )
    }
}

/// Real MLX Sortformer execution plumbing shared by the Commons callback bridge.
///
/// One exclusive operation is admitted at a time. A persistent stream retains
/// its lease until `close()`, so offline inference cannot mutate the same MLX
/// model between feeds.
final class MLXSortformerProvider: @unchecked Sendable {
    private let model: SortformerModel
    private let operationState = OSAllocatedUnfairLock(initialState: false)

    init(modelDirectory: URL) throws {
        try MLXSortformerCatalog.validateModelDirectory(modelDirectory)
        model = try SortformerModel.fromModelDirectory(modelDirectory)
    }

    func diarize(
        samples: [Float],
        options: MLXSortformerOptions = MLXSortformerOptions()
    ) async throws -> MLXSortformerResult {
        try options.validate(sampleCount: samples.count)
        try beginOperation()
        defer { finishOperation() }
        let output = try await model.generate(
            audio: MLXArray(samples),
            sampleRate: options.sampleRate,
            threshold: options.threshold,
            minDuration: options.minimumDuration,
            mergeGap: options.mergeGap
        )
        return MLXSortformerResult(
            output,
            sampleCount: samples.count,
            sampleRate: options.sampleRate
        )
    }

    func makePersistentStream(
        options: MLXSortformerOptions = MLXSortformerOptions()
    ) throws -> MLXSortformerPersistentStream {
        try options.validateConfiguration()
        try beginOperation()
        return MLXSortformerPersistentStream(
            model: model,
            options: options,
            upstream: model.initStreamingState(),
            onClose: { [weak self] in self?.finishOperation() }
        )
    }

    /// Convenience whole-buffer adapter implemented in terms of the real
    /// persistent `initStreamingState` + `feed(chunk:state:)` path.
    func diarizeStream(
        samples: [Float],
        options: MLXSortformerOptions = MLXSortformerOptions()
    ) throws -> AsyncThrowingStream<MLXSortformerResult, Error> {
        try options.validate(sampleCount: samples.count)
        let stream = try makePersistentStream(options: options)

        return AsyncThrowingStream { continuation in
            let producer = Task {
                defer { stream.close() }
                do {
                    let chunkSize = max(1, Int(options.chunkDuration * Float(options.sampleRate)))
                    var offset = 0
                    while offset < samples.count {
                        try Task.checkCancellation()
                        let end = min(samples.count, offset + chunkSize)
                        continuation.yield(try await stream.feed(samples: Array(samples[offset..<end])))
                        offset = end
                    }
                    try Task.checkCancellation()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
    }

    private func beginOperation() throws {
        let started = operationState.withLock { isRunning in
            guard !isRunning else { return false }
            isRunning = true
            return true
        }
        guard started else {
            throw MLXSortformerProviderError.providerBusy
        }
    }

    private func finishOperation() {
        operationState.withLock { $0 = false }
    }
}
