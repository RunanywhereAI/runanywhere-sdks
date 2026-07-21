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
///
/// This is intentionally provider-local until Commons exposes an executable
/// speaker-diarization component. Registering it as `ModelCategory.audio`
/// today would route it through the ordinary VAD lifecycle and discard the
/// speaker identity carried by Sortformer.
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

    func validate(sampleCount: Int) throws {
        guard sampleCount > 0 else {
            throw MLXSortformerProviderError.emptyAudio
        }
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
    let processingTimeMilliseconds: Int64

    init(_ output: DiarizationOutput) {
        segments = output.segments.map(MLXSortformerSegment.init)
        activeSpeakerCount = output.numSpeakers
        processingTimeMilliseconds = Int64((output.totalTime * 1_000).rounded())
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
        }
    }
}

/// Real MLX Sortformer execution plumbing shared by a future Commons bridge.
///
/// The operation gate prevents overlapping calls from mutating the upstream
/// model concurrently. The provider returns plain, Sendable speaker segments
/// rather than leaking MLX arrays across the bridge.
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
        return MLXSortformerResult(output)
    }

    func diarizeStream(
        samples: [Float],
        options: MLXSortformerOptions = MLXSortformerOptions()
    ) throws -> AsyncThrowingStream<MLXSortformerResult, Error> {
        try options.validate(sampleCount: samples.count)
        try beginOperation()
        let upstream = model.generateStream(
            audio: MLXArray(samples),
            sampleRate: options.sampleRate,
            chunkDuration: options.chunkDuration,
            threshold: options.threshold,
            minDuration: options.minimumDuration,
            mergeGap: options.mergeGap,
            spkcacheMax: options.speakerCacheFrames,
            fifoMax: options.fifoFrames
        )

        return AsyncThrowingStream { continuation in
            let producer = Task {
                defer { self.finishOperation() }
                do {
                    for try await output in upstream {
                        try Task.checkCancellation()
                        continuation.yield(MLXSortformerResult(output))
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
