//
//  MLXVLMAdapter.swift
//  RunAnywhere SDK
//
//  MLX-based VLM adapter for Apple Silicon native inference.
//  Uses mlx-swift and mlx-swift-examples for Vision Language Models.
//
//  NOTE: MLX support is OPTIONAL. In a future release, this will be moved
//  to a separate "RunAnywhereMLX" module (similar to RunAnywhereONNX and
//  RunAnywhereLlamaCPP) so users who don't need MLX VLM can avoid the
//  extra dependency overhead.
//

import CoreImage
import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreVideo)
import CoreVideo
#endif

#if canImport(MLX) && canImport(MLXLLM)
import MLX
import MLXFast
import MLXLLM
import MLXLMCommon
import MLXNN
import MLXRandom

/// MLX-based Vision Language Model adapter for Apple Silicon
///
/// Provides native Apple Silicon inference for VLM models using MLX framework.
/// Supports HuggingFace safetensors models including Qwen2-VL, SmolVLM, LLaVA.
@available(iOS 16.0, macOS 14.0, *)
public actor MLXVLMAdapter {

    // MARK: - Singleton

    /// Shared MLX VLM adapter instance
    public static let shared = MLXVLMAdapter()

    // MARK: - State

    /// Loaded model container
    private var modelContainer: ModelContainer?

    /// Chat session for simplified generation
    private var chatSession: ChatSession?

    /// Currently loaded model ID
    private var loadedModelId: String?

    /// Currently loaded model path (HuggingFace ID or local path)
    private var loadedModelPath: String?

    /// Cancellation flag for generation
    private var isCancelled = false

    /// Logger instance
    private let logger = SDKLogger(category: "MLXVLMAdapter")

    // MARK: - Init

    private init() {}

    // MARK: - Model Loading

    /// Load an MLX VLM model from HuggingFace or local path
    ///
    /// - Parameters:
    ///   - modelPath: HuggingFace model ID (e.g., "mlx-community/Qwen2.5-VL-3B-Instruct-4bit")
    ///                or local directory path
    ///   - modelId: Unique identifier for the model (for telemetry)
    /// - Throws: SDKError if loading fails
    public func loadModel(
        _ modelPath: String,
        modelId: String
    ) async throws {
        // Unload existing model
        if modelContainer != nil {
            await unloadModel()
        }

        logger.info("Loading MLX VLM model: \(modelId) from \(modelPath)")

        do {
            let container: ModelContainer

            // Determine if it's a HuggingFace hub path or local path
            if modelPath.hasPrefix("/") || modelPath.hasPrefix("file://") {
                // Local path
                let url: URL
                if modelPath.hasPrefix("file://") {
                    guard let fileURL = URL(string: modelPath) else {
                        throw SDKError.vlm(.modelLoadFailed, "Invalid file URL: \(modelPath)")
                    }
                    url = fileURL
                } else {
                    url = URL(fileURLWithPath: modelPath)
                }
                container = try await loadModelContainer(directory: url) { progress in
                    self.logger.debug("Loading progress: \(Int(progress.fractionCompleted * 100))%")
                }
            } else {
                // HuggingFace hub path - will download if needed
                container = try await loadModelContainer(id: modelPath) { progress in
                    self.logger.debug("Loading progress: \(Int(progress.fractionCompleted * 100))%")
                }
            }

            self.modelContainer = container
            self.chatSession = ChatSession(
                container,
                generateParameters: GenerateParameters(maxTokens: 512)
            )
            self.loadedModelId = modelId
            self.loadedModelPath = modelPath

            logger.info("MLX VLM model loaded successfully: \(modelId)")

        } catch {
            logger.error("Failed to load MLX VLM model: \(error.localizedDescription)")
            throw SDKError.vlm(.modelLoadFailed, "Failed to load MLX VLM model: \(error.localizedDescription)")
        }
    }

    /// Unload the current model and free memory
    public func unloadModel() async {
        modelContainer = nil
        chatSession = nil
        loadedModelId = nil
        loadedModelPath = nil

        // Clear GPU memory cache
        MLX.GPU.clearCache()

        logger.info("MLX VLM model unloaded")
    }

    // MARK: - State Queries

    /// Whether a model is currently loaded
    public var isLoaded: Bool { modelContainer != nil }

    /// ID of the currently loaded model
    public var currentModelId: String? { loadedModelId }

    /// Path of the currently loaded model
    public var currentModelPath: String? { loadedModelPath }

    // MARK: - VLM Processing - Streaming

    /// Process an image with a text prompt, streaming tokens as they're generated
    ///
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - prompt: Text prompt describing what to analyze
    ///   - options: Generation options
    /// - Returns: AsyncThrowingStream of generated tokens
    public func processImageStream(
        image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let container = modelContainer else {
            throw SDKError.vlm(.notInitialized, "MLX VLM model not loaded")
        }

        isCancelled = false

        // Convert VLMImage to MLX UserInput.Image
        let mlxImage = try await convertToMLXImage(image)

        // Create chat session with custom parameters for this request
        let generateParams = GenerateParameters(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
            topP: options.topP
        )

        let session = ChatSession(
            container,
            generateParameters: generateParams
        )

        // Get the stream from chat session
        let rawStream = session.streamResponse(to: prompt, image: mlxImage)

        // Return stream that checks cancellation
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                do {
                    for try await token in rawStream {
                        if await self?.isCancelled == true {
                            break
                        }
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - VLM Processing - Non-Streaming

    /// Process an image with a text prompt, returning complete result
    ///
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - prompt: Text prompt describing what to analyze
    ///   - options: Generation options
    /// - Returns: VLMGenerationResult with generated text and metrics
    public func processImage(
        image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions
    ) async throws -> VLMGenerationResult {
        guard let container = modelContainer else {
            throw SDKError.vlm(.notInitialized, "MLX VLM model not loaded")
        }

        isCancelled = false
        let startTime = Date()
        var firstTokenTime: Date?
        var fullText = ""
        var tokenCount = 0

        // Convert VLMImage to MLX UserInput.Image
        let mlxImage = try await convertToMLXImage(image)

        // Create chat session with custom parameters for this request
        let generateParams = GenerateParameters(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
            topP: options.topP
        )

        let session = ChatSession(
            container,
            generateParameters: generateParams
        )

        // Stream and collect all tokens
        let stream = session.streamResponse(to: prompt, image: mlxImage)

        for try await token in stream {
            if isCancelled {
                break
            }

            if firstTokenTime == nil {
                firstTokenTime = Date()
            }

            fullText += token
            tokenCount += 1
        }

        let endTime = Date()
        let totalTimeMs = endTime.timeIntervalSince(startTime) * 1000
        let ttftMs = firstTokenTime.map { $0.timeIntervalSince(startTime) * 1000 }
        let tokensPerSecond = totalTimeMs > 0 ? Double(tokenCount) / (totalTimeMs / 1000) : 0

        return VLMGenerationResult(
            text: fullText,
            promptTokens: 0, // MLX doesn't easily expose prompt token count
            imageTokens: 0,
            completionTokens: tokenCount,
            totalTokens: tokenCount,
            timeToFirstTokenMs: ttftMs,
            imageEncodeTimeMs: nil,
            totalTimeMs: totalTimeMs,
            tokensPerSecond: tokensPerSecond,
            modelUsed: loadedModelId ?? "unknown"
        )
    }

    /// Cancel ongoing generation
    public func cancel() {
        isCancelled = true
        logger.debug("MLX VLM generation cancelled")
    }

    // MARK: - Private Helpers

    /// Convert VLMImage to MLX UserInput.Image format
    private func convertToMLXImage(_ image: VLMImage) async throws -> UserInput.Image {
        switch image.format {
        case .filePath(let path):
            return .url(URL(fileURLWithPath: path))

        case .base64(let encoded):
            guard let data = Data(base64Encoded: encoded) else {
                throw SDKError.vlm(.invalidImage, "Invalid base64 image data")
            }
            // Create CIImage from data
            guard let ciImage = CIImage(data: data) else {
                throw SDKError.vlm(.invalidImage, "Failed to create image from base64 data")
            }
            return .ciImage(ciImage)

        case .rgbPixels(let data, let width, let height):
            // Convert RGB pixels to CIImage
            let ciImage = try createCIImageFromRGB(data: data, width: width, height: height)
            return .ciImage(ciImage)

        #if canImport(UIKit)
        case .uiImage(let uiImage):
            guard let cgImage = uiImage.cgImage else {
                throw SDKError.vlm(.invalidImage, "Failed to get CGImage from UIImage")
            }
            let ciImage = CIImage(cgImage: cgImage)
            return .ciImage(ciImage)
        #endif

        #if canImport(CoreVideo)
        case .pixelBuffer(let buffer):
            let ciImage = CIImage(cvPixelBuffer: buffer)
            return .ciImage(ciImage)
        #endif
        }
    }

    /// Create CIImage from raw RGB pixel data
    private func createCIImageFromRGB(data: Data, width: Int, height: Int) throws -> CIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: width * 3,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw SDKError.vlm(.invalidImage, "Failed to create image from RGB data")
        }

        return CIImage(cgImage: cgImage)
    }
}

#else

// MARK: - Stub for non-MLX platforms

/// Stub MLXVLMAdapter for platforms without MLX support
@available(iOS 16.0, macOS 14.0, *)
public actor MLXVLMAdapter {
    public static let shared = MLXVLMAdapter()

    private init() {}

    public var isLoaded: Bool { false }
    public var currentModelId: String? { nil }
    public var currentModelPath: String? { nil }

    public func loadModel(_ modelPath: String, modelId: String) async throws {
        throw SDKError.vlm(.notInitialized, "MLX is not available on this platform. Use llama.cpp backend instead.")
    }

    public func unloadModel() async {}

    public func processImageStream(
        image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        throw SDKError.vlm(.notInitialized, "MLX is not available on this platform")
    }

    public func processImage(
        image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions
    ) async throws -> VLMGenerationResult {
        throw SDKError.vlm(.notInitialized, "MLX is not available on this platform. Use llama.cpp backend instead.")
    }

    public func cancel() {}
}

#endif
