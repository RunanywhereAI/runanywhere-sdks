//
//  RunAnywhere+Vocoder.swift
//  RunAnywhere SDK
//
//  Public neural-vocoder facade.
//

import Foundation

/// Dense row-major float32 mel tensor with logical shape `[B, M, T]`.
public struct VocoderRequest: Sendable, Equatable {
    /// Tensor values in row-major `[batch, mel bin, frame]` order.
    public let melSpectrogram: [Float]
    /// `B`: number of independent mel tensors.
    public let batchSize: Int
    /// `M`: mel-frequency bins per frame.
    public let melBinCount: Int
    /// `T`: time frames per mel tensor.
    public let frameCount: Int

    public init(
        melSpectrogram: [Float],
        batchSize: Int,
        melBinCount: Int,
        frameCount: Int
    ) {
        self.melSpectrogram = melSpectrogram
        self.batchSize = batchSize
        self.melBinCount = melBinCount
        self.frameCount = frameCount
    }
}

/// Dense row-major float32 waveform tensor with logical shape `[B, C, S]`.
public struct VocoderResult: Sendable, Equatable {
    /// Waveform values in row-major `[batch, channel, sample]` order.
    public let samples: [Float]
    /// `B`: output batch size.
    public let batchSize: Int
    /// `C`: output channels per batch item.
    public let channelCount: Int
    /// `S`: samples per channel, not the flattened sample total.
    public let sampleCount: Int
    public let sampleRateHz: Int
    /// Waveform samples represented by one input mel frame.
    public let hopLength: Int
    public let processingTimeMs: Int64
    public let modelID: String

    public init(
        samples: [Float],
        batchSize: Int,
        channelCount: Int,
        sampleCount: Int,
        sampleRateHz: Int,
        hopLength: Int,
        processingTimeMs: Int64,
        modelID: String
    ) {
        self.samples = samples
        self.batchSize = batchSize
        self.channelCount = channelCount
        self.sampleCount = sampleCount
        self.sampleRateHz = sampleRateHz
        self.hopLength = hopLength
        self.processingTimeMs = processingTimeMs
        self.modelID = modelID
    }
}

public extension RunAnywhere {
    /// Convert a float32 mel tensor into waveform samples with the currently
    /// loaded `.vocoder` model.
    ///
    /// Model ownership stays in the canonical lifecycle. Import or register
    /// a model, then call `loadModel(_:)` with `category = .vocoder` before
    /// invoking this method. This inference entry point never downloads or
    /// silently swaps model weights.
    static func vocode(_ request: VocoderRequest) async throws -> VocoderResult {
        guard isInitialized else {
            throw SDKException(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .internal
            )
        }
        try await ensureServicesReady()

        let snapshot = loadedModelSnapshot(category: .vocoder)
        let loadedModelID = try requireVocoderModel(snapshot)
        let wireRequest = try VocoderWireCodec.makeWireRequest(request)
        let wireResult = try await CppBridge.Vocoder.vocode(wireRequest)
        return try VocoderWireCodec.makePublicResult(
            wireResult,
            request: request,
            loadedModelID: loadedModelID
        )
    }

    /// Shared readiness gate kept separate from native dispatch so focused
    /// tests can prove the no-model contract without mutating global SDK state.
    internal static func requireVocoderModel(_ snapshot: RACurrentModelResult) throws -> String {
        guard snapshot.found else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "Vocoder model not loaded",
                category: .component
            )
        }
        guard !snapshot.modelID.isEmpty else {
            throw SDKException(
                code: .processingFailed,
                message: "Loaded vocoder snapshot has no model ID",
                category: .internal
            )
        }
        return snapshot.modelID
    }
}

/// Converts ergonomic float arrays to and from the byte-efficient wire form.
///
/// The protobuf contract names the payloads `*_f32_le`; conversion is explicit
/// rather than relying on host endianness, `Data` alignment, or an unsafe
/// rebind of potentially unaligned storage.
enum VocoderWireCodec {
    private static let bytesPerFloat = MemoryLayout<UInt32>.size
    private static let maximumWireDimension = Int(UInt32.max)

    static func makeWireRequest(_ request: VocoderRequest) throws -> RAVocoderRequest {
        try validateDimension(request.batchSize, fieldPath: "VocoderRequest.batchSize")
        try validateDimension(request.melBinCount, fieldPath: "VocoderRequest.melBinCount")
        try validateDimension(request.frameCount, fieldPath: "VocoderRequest.frameCount")

        let expectedCount = try checkedProduct(
            request.batchSize,
            request.melBinCount,
            request.frameCount,
            fieldPath: "VocoderRequest.melSpectrogram"
        )
        guard request.melSpectrogram.count == expectedCount else {
            throw validationFailure(
                fieldPath: "VocoderRequest.melSpectrogram",
                message: "melSpectrogram must contain exactly B*M*T (\(expectedCount)) values"
            )
        }
        try validateFinite(
            request.melSpectrogram,
            fieldPath: "VocoderRequest.melSpectrogram"
        )

        var wire = RAVocoderRequest()
        wire.melSpectrogramF32Le = try encodeFloat32LittleEndian(
            request.melSpectrogram,
            fieldPath: "VocoderRequest.melSpectrogram"
        )
        wire.batchSize = UInt32(request.batchSize)
        wire.melBinCount = UInt32(request.melBinCount)
        wire.frameCount = UInt32(request.frameCount)
        return wire
    }

    static func makePublicResult(
        _ wire: RAVocoderResult,
        request: VocoderRequest,
        loadedModelID: String
    ) throws -> VocoderResult {
        let batchSize = Int(wire.batchSize)
        let channelCount = Int(wire.channelCount)
        let sampleCount = Int(wire.sampleCount)
        let sampleRateHz = Int(wire.sampleRateHz)
        let hopLength = Int(wire.hopLength)

        guard batchSize > 0 else { throw invalidResult("batchSize must be positive") }
        guard channelCount > 0 else { throw invalidResult("channelCount must be positive") }
        guard channelCount == 1 else {
            throw invalidResult("the BigVGAN vocoder must return one audio channel")
        }
        guard sampleCount > 0 else { throw invalidResult("sampleCount must be positive") }
        guard sampleRateHz > 0 else { throw invalidResult("sampleRateHz must be positive") }
        guard hopLength > 0 else { throw invalidResult("hopLength must be positive") }
        guard wire.processingTimeMs >= 0 else {
            throw invalidResult("processingTimeMs must not be negative")
        }
        guard batchSize == request.batchSize else {
            throw invalidResult("output batchSize does not match the request")
        }
        guard wire.modelID == loadedModelID else {
            throw invalidResult("output modelID does not match the lifecycle-owned model")
        }

        let expectedSampleCount = try checkedResultProduct(
            batchSize,
            channelCount,
            sampleCount
        )
        let expectedSamplesPerChannel = try checkedResultProduct(request.frameCount, hopLength)
        guard sampleCount == expectedSamplesPerChannel else {
            throw invalidResult("output sampleCount must equal request frameCount * hopLength")
        }

        let samples = try decodeFloat32LittleEndian(
            wire.samplesF32Le,
            expectedCount: expectedSampleCount
        )
        guard let invalidIndex = samples.firstIndex(where: { !$0.isFinite }) else {
            return VocoderResult(
                samples: samples,
                batchSize: batchSize,
                channelCount: channelCount,
                sampleCount: sampleCount,
                sampleRateHz: sampleRateHz,
                hopLength: hopLength,
                processingTimeMs: wire.processingTimeMs,
                modelID: wire.modelID
            )
        }
        throw invalidResult("output samples contain a non-finite value at index \(invalidIndex)")
    }

    static func encodeFloat32LittleEndian(
        _ values: [Float],
        fieldPath: String
    ) throws -> Data {
        let (byteCount, overflow) = values.count.multipliedReportingOverflow(by: bytesPerFloat)
        guard !overflow else {
            throw validationFailure(fieldPath: fieldPath, message: "float32 payload is too large")
        }

        var data = Data()
        data.reserveCapacity(byteCount)
        for value in values {
            var littleEndianBits = value.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &littleEndianBits) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    static func decodeFloat32LittleEndian(
        _ data: Data,
        expectedCount: Int
    ) throws -> [Float] {
        let (expectedByteCount, overflow) = expectedCount.multipliedReportingOverflow(
            by: bytesPerFloat
        )
        guard !overflow, data.count == expectedByteCount else {
            throw invalidResult(
                "samplesF32Le must contain exactly B*C*S*4 (\(overflow ? 0 : expectedByteCount)) bytes"
            )
        }

        let bytes = [UInt8](data)
        var values = [Float]()
        values.reserveCapacity(expectedCount)
        for offset in stride(from: 0, to: bytes.count, by: bytesPerFloat) {
            let bits = UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
            values.append(Float(bitPattern: bits))
        }
        return values
    }

    private static func validateDimension(_ value: Int, fieldPath: String) throws {
        guard value > 0, value <= maximumWireDimension else {
            throw validationFailure(
                fieldPath: fieldPath,
                message: "dimension must be in 1...UInt32.max"
            )
        }
    }

    private static func validateFinite(_ values: [Float], fieldPath: String) throws {
        guard let invalidIndex = values.firstIndex(where: { !$0.isFinite }) else { return }
        throw validationFailure(
            fieldPath: "\(fieldPath)[\(invalidIndex)]",
            message: "float32 tensor values must be finite"
        )
    }

    private static func checkedProduct(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        fieldPath: String
    ) throws -> Int {
        let (partial, firstOverflow) = first.multipliedReportingOverflow(by: second)
        let (product, secondOverflow) = partial.multipliedReportingOverflow(by: third)
        guard !firstOverflow, !secondOverflow else {
            throw validationFailure(fieldPath: fieldPath, message: "tensor dimensions overflow Int")
        }
        return product
    }

    private static func checkedResultProduct(_ first: Int, _ second: Int) throws -> Int {
        let (product, overflow) = first.multipliedReportingOverflow(by: second)
        guard !overflow else { throw invalidResult("output tensor dimensions overflow Int") }
        return product
    }

    private static func checkedResultProduct(
        _ first: Int,
        _ second: Int,
        _ third: Int
    ) throws -> Int {
        let partial = try checkedResultProduct(first, second)
        return try checkedResultProduct(partial, third)
    }

    private static func validationFailure(fieldPath: String, message: String) -> SDKException {
        SDKException.validationFailed(fieldPath: fieldPath, message: message)
    }

    private static func invalidResult(_ message: String) -> SDKException {
        SDKException(
            code: .processingFailed,
            message: "Invalid vocoder result: \(message)",
            category: .internal
        )
    }
}
