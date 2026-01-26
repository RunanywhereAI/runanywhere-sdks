//
//  VLMTypes.swift
//  RunAnywhere SDK
//
//  Public types for Vision Language Model (VLM) operations.
//  These are thin wrappers over C++ types in rac_vlm_types.h
//

import CRACommons
import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreVideo)
import CoreVideo
#endif

// MARK: - VLM Image Input

/// Represents an image input for VLM processing
/// Supports multiple input formats: UIImage, file path, raw pixels, base64
public struct VLMImage: Sendable {

    /// The underlying image format
    public enum Format: Sendable {
        /// Path to an image file on disk
        case filePath(String)

        /// Raw RGB pixel data with dimensions
        case rgbPixels(data: Data, width: Int, height: Int)

        /// Base64-encoded image data
        case base64(String)

        #if canImport(UIKit)
        /// UIImage (iOS/macOS)
        case uiImage(UIImage)
        #endif

        #if canImport(CoreVideo)
        /// CVPixelBuffer from camera/video
        case pixelBuffer(CVPixelBuffer)
        #endif
    }

    /// The image format
    public let format: Format

    // MARK: - Initializers

    /// Create from file path
    public init(filePath: String) {
        self.format = .filePath(filePath)
    }

    /// Create from raw RGB pixels
    public init(rgbPixels data: Data, width: Int, height: Int) {
        self.format = .rgbPixels(data: data, width: width, height: height)
    }

    /// Create from base64-encoded data
    public init(base64: String) {
        self.format = .base64(base64)
    }

    #if canImport(UIKit)
    /// Create from UIImage
    public init(image: UIImage) {
        self.format = .uiImage(image)
    }
    #endif

    #if canImport(CoreVideo)
    /// Create from CVPixelBuffer (camera capture)
    public init(pixelBuffer: CVPixelBuffer) {
        self.format = .pixelBuffer(pixelBuffer)
    }
    #endif

    // MARK: - C++ Bridge

    /// Convert to C struct for passing to C++ layer. Returns nil if conversion fails.
    internal func toCImage() -> (rac_vlm_image_t, (any Sendable)?)? { // swiftlint:disable:this function_body_length
        var cImage = rac_vlm_image_t()
        var retainedData: (any Sendable)?

        switch format {
        case .filePath(let path):
            cImage.format = RAC_VLM_IMAGE_FORMAT_FILE_PATH
            // We need to keep the string alive during the call
            // The caller must ensure the path string outlives the C struct
            retainedData = path
            return (cImage, retainedData)

        case .rgbPixels(let data, let width, let height):
            cImage.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
            cImage.width = UInt32(width)
            cImage.height = UInt32(height)
            cImage.data_size = data.count
            retainedData = data
            return (cImage, retainedData)

        case .base64(let encoded):
            cImage.format = RAC_VLM_IMAGE_FORMAT_BASE64
            cImage.data_size = encoded.utf8.count
            retainedData = encoded
            return (cImage, retainedData)

        #if canImport(UIKit)
        case .uiImage(let image):
            // Convert UIImage to RGB pixel data
            guard let cgImage = image.cgImage else { return nil }
            let width = cgImage.width
            let height = cgImage.height
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let totalBytes = bytesPerRow * height

            var pixelData = Data(count: totalBytes)
            pixelData.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }

            // Convert RGBA to RGB
            var rgbData = Data(capacity: width * height * 3)
            pixelData.withUnsafeBytes { buffer in
                let pixels = buffer.bindMemory(to: UInt8.self)
                for i in stride(from: 0, to: totalBytes, by: 4) {
                    rgbData.append(pixels[i])     // R
                    rgbData.append(pixels[i + 1]) // G
                    rgbData.append(pixels[i + 2]) // B
                }
            }

            cImage.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
            cImage.width = UInt32(width)
            cImage.height = UInt32(height)
            cImage.data_size = rgbData.count
            retainedData = rgbData
            return (cImage, retainedData)
        #endif

        #if canImport(CoreVideo)
        case .pixelBuffer(let buffer):
            // Lock the buffer for reading
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

            guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

            // Assume BGRA format from camera
            var rgbData = Data(capacity: width * height * 3)
            let pixelBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)

            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    rgbData.append(pixelBuffer[offset + 2]) // R (from BGRA)
                    rgbData.append(pixelBuffer[offset + 1]) // G
                    rgbData.append(pixelBuffer[offset])     // B
                }
            }

            cImage.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
            cImage.width = UInt32(width)
            cImage.height = UInt32(height)
            cImage.data_size = rgbData.count
            retainedData = rgbData
            return (cImage, retainedData)
        #endif
        }
    }
}

// MARK: - VLM Generation Options

/// Options for VLM generation
public struct VLMGenerationOptions: Sendable {

    /// Maximum number of tokens to generate
    public let maxTokens: Int

    /// Temperature for sampling (0.0 - 2.0)
    public let temperature: Float

    /// Top-p sampling parameter
    public let topP: Float

    /// Stop sequences
    public let stopSequences: [String]

    /// Enable streaming mode
    public let streamingEnabled: Bool

    /// System prompt
    public let systemPrompt: String?

    /// Max image dimension for resize (0 = model default)
    public let maxImageSize: Int

    /// Number of CPU threads for vision encoder (0 = auto)
    public let threads: Int

    /// Use GPU for vision encoding
    public let useGPU: Bool

    public init(
        maxTokens: Int = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        stopSequences: [String] = [],
        streamingEnabled: Bool = true,
        systemPrompt: String? = nil,
        maxImageSize: Int = 0,
        threads: Int = 0,
        useGPU: Bool = true
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.streamingEnabled = streamingEnabled
        self.systemPrompt = systemPrompt
        self.maxImageSize = maxImageSize
        self.threads = threads
        self.useGPU = useGPU
    }

    // MARK: - C++ Bridge

    /// Execute a closure with the C++ equivalent options struct
    internal func withCOptions<T>(_ body: (UnsafePointer<rac_vlm_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_vlm_options_t()
        cOptions.max_tokens = Int32(maxTokens)
        cOptions.temperature = temperature
        cOptions.top_p = topP
        cOptions.streaming_enabled = streamingEnabled ? RAC_TRUE : RAC_FALSE
        cOptions.stop_sequences = nil
        cOptions.num_stop_sequences = 0
        cOptions.max_image_size = Int32(maxImageSize)
        cOptions.n_threads = Int32(threads)
        cOptions.use_gpu = useGPU ? RAC_TRUE : RAC_FALSE

        if let prompt = systemPrompt {
            return try prompt.withCString { promptPtr in
                cOptions.system_prompt = promptPtr
                return try body(&cOptions)
            }
        } else {
            cOptions.system_prompt = nil
            return try body(&cOptions)
        }
    }
}

// MARK: - VLM Generation Result

/// Result of a VLM generation request
public struct VLMGenerationResult: Sendable {

    /// Generated text response
    public let text: String

    /// Number of prompt tokens (text + image tokens)
    public let promptTokens: Int

    /// Number of image tokens specifically
    public let imageTokens: Int

    /// Number of completion tokens generated
    public let completionTokens: Int

    /// Total tokens (prompt + completion)
    public let totalTokens: Int

    /// Time to first token in milliseconds
    public let timeToFirstTokenMs: Double?

    /// Time spent encoding the image in milliseconds
    public let imageEncodeTimeMs: Double?

    /// Total generation time in milliseconds
    public let totalTimeMs: Double

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Model used for generation
    public let modelUsed: String

    public init(
        text: String,
        promptTokens: Int = 0,
        imageTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        timeToFirstTokenMs: Double? = nil,
        imageEncodeTimeMs: Double? = nil,
        totalTimeMs: Double = 0,
        tokensPerSecond: Double = 0,
        modelUsed: String = ""
    ) {
        self.text = text
        self.promptTokens = promptTokens
        self.imageTokens = imageTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.imageEncodeTimeMs = imageEncodeTimeMs
        self.totalTimeMs = totalTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.modelUsed = modelUsed
    }

    // MARK: - C++ Bridge

    /// Initialize from C++ rac_vlm_result_t
    internal init(from cResult: rac_vlm_result_t, modelId: String) {
        self.init(
            text: cResult.text.map { String(cString: $0) } ?? "",
            promptTokens: Int(cResult.prompt_tokens),
            imageTokens: Int(cResult.image_tokens),
            completionTokens: Int(cResult.completion_tokens),
            totalTokens: Int(cResult.total_tokens),
            timeToFirstTokenMs: cResult.time_to_first_token_ms > 0
                ? Double(cResult.time_to_first_token_ms) : nil,
            imageEncodeTimeMs: cResult.image_encode_time_ms > 0
                ? Double(cResult.image_encode_time_ms) : nil,
            totalTimeMs: Double(cResult.total_time_ms),
            tokensPerSecond: Double(cResult.tokens_per_second),
            modelUsed: modelId
        )
    }
}

// MARK: - VLM Streaming Result

/// Container for streaming VLM generation with metrics
public struct VLMStreamingResult: Sendable {

    /// Stream of tokens as they are generated
    public let stream: AsyncThrowingStream<String, Error>

    /// Task that completes with final generation result including metrics
    public let result: Task<VLMGenerationResult, Error>

    public init(
        stream: AsyncThrowingStream<String, Error>,
        result: Task<VLMGenerationResult, Error>
    ) {
        self.stream = stream
        self.result = result
    }
}

// MARK: - VLM Configuration

/// Configuration for VLM component
public struct VLMConfiguration: Sendable {

    /// Model ID (optional - uses default if not specified)
    public let modelId: String?

    /// Context length (max tokens the model can handle)
    public let contextLength: Int

    /// Temperature for sampling (0.0 - 2.0)
    public let temperature: Float

    /// Maximum tokens to generate
    public let maxTokens: Int

    /// System prompt for generation
    public let systemPrompt: String?

    /// Enable streaming mode
    public let streamingEnabled: Bool

    public init(
        modelId: String? = nil,
        contextLength: Int = 4096,
        temperature: Float = 0.7,
        maxTokens: Int = 2048,
        systemPrompt: String? = nil,
        streamingEnabled: Bool = true
    ) {
        self.modelId = modelId
        self.contextLength = contextLength
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.streamingEnabled = streamingEnabled
    }

    // MARK: - Validation

    public func validate() throws {
        guard contextLength > 0 && contextLength <= 32768 else {
            throw SDKError.general(.validationFailed, "Context length must be between 1 and 32768")
        }
        guard temperature >= 0 && temperature <= 2.0 else {
            throw SDKError.general(.validationFailed, "Temperature must be between 0 and 2.0")
        }
        guard maxTokens > 0 && maxTokens <= contextLength else {
            throw SDKError.general(.validationFailed, "Max tokens must be between 1 and context length")
        }
    }
}

// MARK: - VLM Info

/// Information about a VLM service instance
public struct VLMInfo: Sendable {

    /// Whether the service is ready for generation
    public let isReady: Bool

    /// Current model identifier
    public let currentModel: String?

    /// Context length (0 if unknown)
    public let contextLength: Int

    /// Whether streaming is supported
    public let supportsStreaming: Bool

    /// Whether multiple images per request are supported
    public let supportsMultipleImages: Bool

    /// Vision encoder type (e.g., "clip", "siglip")
    public let visionEncoderType: String?

    internal init(from cInfo: rac_vlm_info_t) {
        self.isReady = cInfo.is_ready == RAC_TRUE
        self.currentModel = cInfo.current_model.map { String(cString: $0) }
        self.contextLength = Int(cInfo.context_length)
        self.supportsStreaming = cInfo.supports_streaming == RAC_TRUE
        self.supportsMultipleImages = cInfo.supports_multiple_images == RAC_TRUE
        self.visionEncoderType = cInfo.vision_encoder_type.map { String(cString: $0) }
    }
}
