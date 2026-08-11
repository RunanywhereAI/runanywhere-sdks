//
//  Inputs.swift
//  RunAnywhere SDK
//
//  Audio, image, message, model-reference, and document inputs shared by the
//  v3 namespaces. Each type knows how to lower itself onto the canonical
//  generated proto request shapes; callers never touch the protos.
//

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

#if canImport(CoreVideo)
import CoreVideo
#endif

#if canImport(CoreImage)
import CoreImage
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

// MARK: - Aliases to canonical proto types

/// Tool the model may call, described by name, purpose, and parameters.
public typealias ToolDefinition = RAToolDefinition

/// A tool invocation the model asked for.
public typealias ToolCall = RAToolCall

/// JSON schema constraining structured output.
///
/// `RAJSONSchema` was deleted outright (idl/structured_output.proto):
/// `RAStructuredOutputOptions.schema` is now a single raw JSON Schema
/// STRING (the `oneof constraint` arm), so this is a plain `String` alias
/// rather than a typed proto message.
public typealias JsonSchema = String

/// A registry entry describing one model.
public typealias ModelInfo = RAModelInfo

/// A synthesis voice available on the device.
public typealias Voice = RATTSVoiceInfo

// MARK: - AudioInput

/// Audio handed to STT, VAD, or diarization.
public struct AudioInput: Sendable {

    /// How the bytes in `data` are laid out.
    public enum Encoding: Sendable {
        case pcm16
        case float32
        case wav
        case file
    }

    public let data: Data
    public let encoding: Encoding
    public let sampleRate: Int
    public let channels: Int

    /// Set only for `.file` inputs.
    public let path: String?

    private init(data: Data, encoding: Encoding, sampleRate: Int, channels: Int, path: String? = nil) {
        self.data = data
        self.encoding = encoding
        self.sampleRate = sampleRate
        self.channels = channels
        self.path = path
    }

    /// Wrap little-endian signed 16-bit PCM samples.
    public static func pcm16(_ bytes: Data, sampleRate: Int = 16000, channels: Int = 1) -> AudioInput {
        AudioInput(data: bytes, encoding: .pcm16, sampleRate: sampleRate, channels: channels)
    }

    /// Wrap IEEE-754 single-precision samples already packed as bytes.
    public static func float32(_ bytes: Data, sampleRate: Int = 16000, channels: Int = 1) -> AudioInput {
        AudioInput(data: bytes, encoding: .float32, sampleRate: sampleRate, channels: channels)
    }

    /// Wrap a float sample array.
    public static func float32(samples: [Float], sampleRate: Int = 16000, channels: Int = 1) -> AudioInput {
        let bytes = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return AudioInput(data: bytes, encoding: .float32, sampleRate: sampleRate, channels: channels)
    }

    /// Wrap a self-describing WAV/RIFF container.
    public static func wav(_ bytes: Data) -> AudioInput {
        AudioInput(data: bytes, encoding: .wav, sampleRate: 0, channels: 1)
    }

    /// Reference an audio file on disk; the backend reads it directly.
    public static func file(_ path: String) -> AudioInput {
        AudioInput(data: Data(), encoding: .file, sampleRate: 0, channels: 1, path: path)
    }

    // MARK: Lowering

    func toSTTAudioSource() -> RASTTAudioSource {
        var source = RASTTAudioSource()
        source.channels = Int32(max(1, channels))
        if sampleRate > 0 { source.sampleRate = Int32(sampleRate) }
        switch encoding {
        case .pcm16:
            // bits_per_sample was deleted outright (idl/stt_options.proto):
            // sample width is now determined by `encoding` alone
            // (pcmS16Le implies 16-bit, pcmF32Le implies 32-bit).
            source.audioData = data
            source.encoding = .pcmS16Le
        case .float32:
            source.audioData = data
            source.encoding = .pcmF32Le
        case .wav:
            source.audioData = data
            source.encoding = .container
            source.audioFormat = .wav
        case .file:
            source.fileUri = path ?? ""
            source.encoding = .container
        }
        return source
    }

    func toVADAudioSource() throws -> RAVADAudioSource {
        var source = RAVADAudioSource()
        source.channels = Int32(max(1, channels))
        if sampleRate > 0 { source.sampleRate = Int32(sampleRate) }
        switch encoding {
        case .pcm16:
            source.audioData = data
            source.encoding = .pcmS16Le
        case .float32:
            source.audioData = data
            source.encoding = .pcmF32Le
        case .wav, .file:
            throw SDKException(
                code: .invalidInput,
                message: "VAD needs raw PCM; use AudioInput.pcm16 or AudioInput.float32",
                category: .validation
            )
        }
        return source
    }

    var diarizationEncoding: RAAudioEncoding {
        encoding == .pcm16 ? .pcmS16Le : .pcmF32Le
    }

    func diarizationBytes() throws -> Data {
        switch encoding {
        case .pcm16, .float32:
            return data
        case .wav, .file:
            throw SDKException(
                code: .invalidInput,
                message: "Diarization needs raw PCM; use AudioInput.pcm16 or AudioInput.float32",
                category: .validation
            )
        }
    }

    // MARK: Live-stream adapters (deprecated `transcribeStream`/`detectStream`)

    /// The `AudioFormatSpec` this batch chunk would establish for a live
    /// stream. Only raw PCM inputs can seed a live stream.
    func liveFormatSpec() throws -> AudioFormatSpec {
        switch encoding {
        case .pcm16:
            return AudioFormatSpec(encoding: .pcmS16Le, sampleRate: sampleRate, channels: channels)
        case .float32:
            return AudioFormatSpec(encoding: .pcmF32Le, sampleRate: sampleRate, channels: channels)
        case .wav, .file:
            throw SDKException(
                code: .invalidInput,
                message: "Live streams need raw PCM; use AudioInput.pcm16 or AudioInput.float32",
                category: .validation
            )
        }
    }

    /// Whether this chunk shares `format`'s encoding, sample rate, and channels.
    func matchesLiveFormat(_ format: AudioFormatSpec) -> Bool {
        guard let mine = try? liveFormatSpec() else { return false }
        return mine.encoding == format.encoding
            && mine.sampleRate == format.sampleRate
            && mine.channels == format.channels
    }

    /// Wrap this chunk's bytes as one `AudioFrame`, sized in samples for the
    /// PCM layout `encoding` implies.
    func toLiveFrame() -> AudioFrame {
        let bytesPerSample = encoding == .float32 ? 4 : 2
        return AudioFrame(samples: data, sampleCount: data.count / bytesPerSample)
    }
}

/// Reference-type wrapper around an `AsyncStream<AudioInput>` iterator so the
/// deprecated `transcribeStream`/`detectStream` adapters can advance it from
/// inside a `Task` closure without capturing a non-`Sendable` mutable `var`.
final class AudioInputIteratorBox: @unchecked Sendable {
    private var iterator: AsyncStream<AudioInput>.AsyncIterator

    init(_ stream: AsyncStream<AudioInput>) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async -> AudioInput? {
        await iterator.next()
    }
}

// MARK: - ImageInput

/// Image handed to VLM, segmentation, or inpainting.
public struct ImageInput: Sendable {

    enum Source: Sendable {
        case file(String)
        case encoded(Data)
        case rawRgb(Data, width: Int, height: Int)
    }

    let source: Source

    /// Reference an image file on disk.
    public static func file(_ path: String) -> ImageInput {
        ImageInput(source: .file(path))
    }

    /// Wrap an encoded JPEG, PNG, or WebP buffer.
    public static func bytes(_ data: Data) -> ImageInput {
        ImageInput(source: .encoded(data))
    }

    /// Wrap packed 24-bit RGB pixels.
    public static func rawRgb(_ data: Data, width: Int, height: Int) -> ImageInput {
        ImageInput(source: .rawRgb(data, width: width, height: height))
    }

    #if canImport(CoreGraphics)
    /// Wrap a Core Graphics image, converting to packed RGB.
    public static func cgImage(_ image: CGImage) throws -> ImageInput {
        guard let rgb = ImageInput.packedRGB(from: image) else {
            throw SDKException(
                code: .invalidInput,
                message: "Could not read pixels from the supplied CGImage",
                category: .validation
            )
        }
        return .rawRgb(rgb, width: image.width, height: image.height)
    }
    #endif

    #if canImport(UIKit)
    /// Wrap a UIKit image, converting to packed RGB.
    public static func uiImage(_ image: UIImage) throws -> ImageInput {
        guard let cg = image.cgImage else {
            throw SDKException(
                code: .invalidInput,
                message: "UIImage has no backing CGImage",
                category: .validation
            )
        }
        return try cgImage(cg)
    }
    #endif

    // Guard matches the `import AppKit` above: Catalyst-style targets that can
    // see both frameworks take the UIKit path.
    #if canImport(AppKit) && !canImport(UIKit)
    /// Wrap an AppKit image, converting to packed RGB.
    public static func nsImage(_ image: NSImage) throws -> ImageInput {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SDKException(
                code: .invalidInput,
                message: "NSImage has no backing CGImage",
                category: .validation
            )
        }
        return try cgImage(cg)
    }
    #endif

    #if canImport(CoreVideo) && canImport(CoreImage)
    /// Wrap a camera frame, converting to packed RGB.
    public static func pixelBuffer(_ buffer: CVPixelBuffer) throws -> ImageInput {
        // BGRA frames have a direct byte path; anything else (420v/420f from
        // AVCapture) goes through Core Image, which owns the colour conversion.
        if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
           let rgb = packedRGB(fromBGRA: buffer) {
            return .rawRgb(
                rgb,
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer)
            )
        }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cg = ImageInput.sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw SDKException(
                code: .invalidInput,
                message: "Could not convert the supplied CVPixelBuffer to an image",
                category: .validation
            )
        }
        return try cgImage(cg)
    }

    /// One context for the whole process: `CIContext` creation is expensive and
    /// camera frames arrive at frame rate.
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func packedRGB(fromBGRA buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer), width > 0, height > 0 else {
            return nil
        }

        var rgb = Data(capacity: width * height * 3)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * bytesPerRow + column * 4
                rgb.append(pixels[offset + 2])
                rgb.append(pixels[offset + 1])
                rgb.append(pixels[offset])
            }
        }
        return rgb
    }
    #endif

    // MARK: Lowering

    func toVLMImage() -> RAVLMImage {
        switch source {
        case .file(let path):
            return RAVLMImage.fromFilePath(path)
        case .encoded(let data):
            return RAVLMImage.fromEncoded(data, mediaType: ImageInput.mediaType(of: data))
        case .rawRgb(let data, let width, let height):
            return RAVLMImage.fromRawRGB(data, width: width, height: height)
        }
    }

    /// Packed 24-bit RGB pixels, decoding the file or encoded buffer when needed.
    func rawPixels() throws -> (data: Data, width: Int, height: Int) {
        switch source {
        case .rawRgb(let data, let width, let height):
            return (data, width, height)
        case .encoded(let data):
            return try ImageInput.decode(data)
        case .file(let path):
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try ImageInput.decode(data)
        }
    }

    func toSegmentationImage() throws -> RASegmentationImage {
        let pixels = try rawPixels()
        var image = RASegmentationImage()
        image.data = pixels.data
        image.width = UInt32(pixels.width)
        image.height = UInt32(pixels.height)
        image.pixelFormat = .rgb8
        return image
    }

    /// Encoded PNG/JPEG container bytes plus their sniffed media type, for
    /// diffusion's `image`/`mask_image` fields — which the proto documents as
    /// requiring "an encoded PNG or JPEG container", not raw pixels
    /// (idl/diffusion_options.proto). `.rawRgb` inputs are PNG-encoded on
    /// the fly since that source only ever carries unencoded pixels.
    func encodedImageBytes() throws -> (data: Data, mediaType: String) {
        switch source {
        case .encoded(let data):
            return (data, ImageInput.mediaType(of: data))
        case .file(let path):
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return (data, ImageInput.mediaType(of: data))
        case .rawRgb(let data, let width, let height):
            let encoded = try ImageInput.encodePNG(rgb: data, width: width, height: height)
            return (encoded, "image/png")
        }
    }

    // MARK: Decoding

    /// RAVLMImageFormat was deleted along with the rest of the closed VLM
    /// image-format enum (idl/vlm_options.proto); `mediaType` is now a plain
    /// MIME string, so magic-byte sniffing resolves directly to one instead
    /// of to an enum case.
    private static func mediaType(of data: Data) -> String {
        guard data.count >= 4 else { return "application/octet-stream" }
        let prefix = [UInt8](data.prefix(4))
        if prefix[0] == 0xFF, prefix[1] == 0xD8 { return "image/jpeg" }
        if prefix[0] == 0x89, prefix[1] == 0x50 { return "image/png" }
        if prefix[0] == 0x52, prefix[1] == 0x49 { return "image/webp" }
        return "application/octet-stream"
    }

    private static func decode(_ data: Data) throws -> (data: Data, width: Int, height: Int) {
        #if canImport(CoreGraphics)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rgb = packedRGB(from: image) else {
            throw SDKException(
                code: .invalidInput,
                message: "Could not decode the supplied image bytes",
                category: .validation
            )
        }
        return (rgb, image.width, image.height)
        #else
        throw SDKException(
            code: .featureNotAvailable,
            message: "Image decoding needs CoreGraphics; supply ImageInput.rawRgb instead",
            category: .validation
        )
        #endif
    }

    #if canImport(CoreGraphics)
    private static func packedRGB(from image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = 4 * width
        let totalBytes = bytesPerRow * height
        guard totalBytes > 0 else { return nil }

        var rgba = Data(count: totalBytes)
        var drew = false
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            drew = true
        }
        guard drew else { return nil }

        var rgb = Data(capacity: width * height * 3)
        rgba.withUnsafeBytes { buffer in
            let pixels = buffer.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: totalBytes, by: 4) {
                rgb.append(pixels[index])
                rgb.append(pixels[index + 1])
                rgb.append(pixels[index + 2])
            }
        }
        return rgb
    }
    #endif

    /// Encode packed 24-bit RGB pixels as a PNG container, for diffusion's
    /// `image`/`mask_image` fields (which require an encoded container, not
    /// raw pixels).
    private static func encodePNG(rgb: Data, width: Int, height: Int) throws -> Data {
        #if canImport(CoreGraphics)
        let bytesPerRow = 3 * width
        guard let provider = CGDataProvider(data: rgb as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 24,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw SDKException(
                code: .invalidInput,
                message: "Could not build a CGImage from the supplied raw RGB pixels",
                category: .validation
            )
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.png" as CFString, 1, nil
        ) else {
            throw SDKException(
                code: .invalidInput,
                message: "Could not create a PNG image destination",
                category: .validation
            )
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SDKException(
                code: .invalidInput,
                message: "Could not finalize the PNG encoding",
                category: .validation
            )
        }
        return output as Data
        #else
        throw SDKException(
            code: .featureNotAvailable,
            message: "PNG encoding needs CoreGraphics/ImageIO; supply ImageInput.bytes or .file instead",
            category: .validation
        )
        #endif
    }
}

// MARK: - ChatMessage

/// One turn in a conversation handed to `llm.generate(messages:)`.
public struct ChatMessage: Sendable {

    /// Who produced the turn.
    public enum Role: Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var content: String

    /// Set on `.tool` turns to link the result back to its call.
    public var toolCallId: String?

    /// Build a conversation turn.
    public init(role: Role, content: String, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
    }

    func toProto() -> RAChatMessage {
        var proto = RAChatMessage()
        switch role {
        case .system: proto.role = .system
        case .user: proto.role = .user
        case .assistant: proto.role = .assistant
        case .tool: proto.role = .tool
        }
        proto.content = content
        if let toolCallId { proto.toolCallID = toolCallId }
        return proto
    }
}

// MARK: - ModelRef

/// A model identifier, plus an optional voice for TTS.
public struct ModelRef: Sendable, ExpressibleByStringLiteral {
    public var id: String
    public var voice: String?

    /// Reference a model by registry id.
    public init(id: String, voice: String? = nil) {
        self.id = id
        self.voice = voice
    }

    public init(stringLiteral value: String) {
        self.init(id: value)
    }
}

// MARK: - RagDocument

/// A document to ingest into a RAG session.
public struct RagDocument: Sendable {
    public var text: String
    public var metadata: [String: String]?

    /// Set when the document should be read from disk by the backend.
    public var path: String?

    /// Build an in-memory document.
    public init(text: String, metadata: [String: String]? = nil) {
        self.text = text
        self.metadata = metadata
        self.path = nil
    }

    /// Reference a document file on disk.
    public static func file(_ path: String, metadata: [String: String]? = nil) -> RagDocument {
        var document = RagDocument(text: "", metadata: metadata)
        document.path = path
        return document
    }

    func toProto() -> RARAGDocument {
        var proto = RARAGDocument()
        proto.text = text
        if let metadata { proto.metadata = metadata }
        if let path { proto.sourceUri = path }
        return proto
    }
}

// MARK: - ModelFilter

/// Narrow `models.list` to a subset of the registry.
public struct ModelFilter: Sendable {
    public var category: ModelCategory?
    public var framework: InferenceFramework?
    public var downloadedOnly: Bool?
    public var search: String?

    /// Build a registry filter.
    public init(
        category: ModelCategory? = nil,
        framework: InferenceFramework? = nil,
        downloadedOnly: Bool? = nil,
        search: String? = nil
    ) {
        self.category = category
        self.framework = framework
        self.downloadedOnly = downloadedOnly
        self.search = search
    }

    func toProto() -> RAModelQuery {
        var query = RAModelQuery()
        if let category { query.category = category }
        if let framework { query.framework = framework }
        if let downloadedOnly { query.downloadedOnly = downloadedOnly }
        if let search { query.searchQuery = search }
        return query
    }
}

// MARK: - ModelRegistration

/// One builder covering URL, archive, and multi-file model registration.
public struct ModelRegistration: Sendable {

    enum Payload: Sendable {
        case url(String)
        case archive(url: String, structure: RAArchiveStructure, type: RAArchiveType?)
        case multiFile([RAModelFileDescriptor])
    }

    let payload: Payload
    public var id: String?
    public var name: String
    public var framework: InferenceFramework
    public var category: ModelCategory
    public var memoryRequirementBytes: Int64?
    public var downloadSizeBytes: Int64?
    public var contextLength: Int?
    public var supportsThinking: Bool
    public var supportsLora: Bool

    /// Computer-Use-Agent profile id (e.g. `RunAnywhere.CUA.faraProfile`) for a
    /// CUA-capable model; lands on `RAModelInfo.cuaProfile` so callers can
    /// discover which registered models are drivable through `RunAnywhere.CUA`.
    public var cuaProfile: String?

    private init(
        payload: Payload,
        id: String?,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory,
        memoryRequirementBytes: Int64?,
        downloadSizeBytes: Int64?,
        contextLength: Int?,
        supportsThinking: Bool,
        supportsLora: Bool,
        cuaProfile: String? = nil
    ) {
        self.payload = payload
        self.id = id
        self.name = name
        self.framework = framework
        self.category = category
        self.memoryRequirementBytes = memoryRequirementBytes
        self.downloadSizeBytes = downloadSizeBytes
        self.contextLength = contextLength
        self.supportsThinking = supportsThinking
        self.supportsLora = supportsLora
        self.cuaProfile = cuaProfile
    }

    /// Register a model served from a single download URL or `hf.co` reference.
    public static func url(
        _ url: String,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory = .language,
        id: String? = nil,
        memoryRequirementBytes: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) -> ModelRegistration {
        ModelRegistration(
            payload: .url(url),
            id: id,
            name: name,
            framework: framework,
            category: category,
            memoryRequirementBytes: memoryRequirementBytes,
            downloadSizeBytes: nil,
            contextLength: nil,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora,
            cuaProfile: cuaProfile
        )
    }

    /// Register an archive-packaged model whose on-disk layout the URL cannot imply.
    public static func archive(
        _ url: String,
        structure: RAArchiveStructure,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory = .language,
        archiveType: RAArchiveType? = nil,
        id: String? = nil,
        memoryRequirementBytes: Int64? = nil,
        supportsThinking: Bool = false,
        supportsLora: Bool = false,
        cuaProfile: String? = nil
    ) -> ModelRegistration {
        ModelRegistration(
            payload: .archive(url: url, structure: structure, type: archiveType),
            id: id,
            name: name,
            framework: framework,
            category: category,
            memoryRequirementBytes: memoryRequirementBytes,
            downloadSizeBytes: nil,
            contextLength: nil,
            supportsThinking: supportsThinking,
            supportsLora: supportsLora,
            cuaProfile: cuaProfile
        )
    }

    /// Register a model made of several files, each carrying its own URL.
    public static func multiFile(
        _ files: [RAModelFileDescriptor],
        id: String,
        name: String,
        framework: InferenceFramework,
        category: ModelCategory = .language,
        memoryRequirementBytes: Int64? = nil,
        downloadSizeBytes: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        cuaProfile: String? = nil
    ) -> ModelRegistration {
        ModelRegistration(
            payload: .multiFile(files),
            id: id,
            name: name,
            framework: framework,
            category: category,
            memoryRequirementBytes: memoryRequirementBytes,
            downloadSizeBytes: downloadSizeBytes,
            contextLength: contextLength,
            supportsThinking: supportsThinking,
            supportsLora: false,
            cuaProfile: cuaProfile
        )
    }
}
