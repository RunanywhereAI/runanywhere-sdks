//
//  RunAnywhere+VisionLanguage.swift
//  RunAnywhere SDK
//
//  Public API for Vision Language Model (VLM) operations.
//  Uses C++ directly via CppBridge.VLM.
//

import CRACommons
import Foundation

// C struct with raw pointers — safe to send across concurrency boundaries
// because the backing Data (rgbData) is kept alive alongside it.
extension rac_vlm_image_t: @unchecked Sendable {}

// MARK: - Vision Language Model

public extension RunAnywhere {

    // MARK: - Simple API

    /// Describe an image with a text prompt
    static func describeImage(_ image: VLMImage, prompt: String = "What's in this image?") async throws -> String {
        try await processImage(image, prompt: prompt).text
    }

    /// Ask a question about an image
    static func askAboutImage(_ question: String, image: VLMImage) async throws -> String {
        try await processImage(image, prompt: question).text
    }

    // MARK: - Full API

    /// Process an image with VLM
    static func processImage(
        _ image: VLMImage,
        prompt: String,
        maxTokens: Int32 = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9
    ) async throws -> VLMResult {
        var options = RAVLMGenerationOptions.defaults(prompt: prompt)
        options.maxTokens = maxTokens
        options.temperature = temperature
        options.topP = topP
        let result = try await processImage(image, options: options)
        return VLMResult(from: result)
    }

    /// Process an image through the generated-proto C++ VLM ABI.
    static func processImage(
        _ image: VLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> RAVLMResult {
        guard let protoImage = image.toRAVLMImage() else {
            throw SDKException.vlm(.invalidImage, "Failed to convert image")
        }
        return try await processImage(protoImage, options: options)
    }

    /// Process a generated-proto VLM image through the C++ VLM ABI.
    static func processImage(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> RAVLMResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKException.vlm(.notInitialized, "VLM model not loaded")
        }

        return try await CppBridge.VLM.shared.process(image: image, options: options)
    }

    /// Stream image processing with real-time tokens
    static func processImageStream(
        _ image: VLMImage,
        prompt: String,
        maxTokens: Int32 = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9
    ) async throws -> VLMStreamingResult {
        guard let protoImage = image.toRAVLMImage() else {
            throw SDKException.vlm(.invalidImage, "Failed to convert image")
        }

        var options = RAVLMGenerationOptions.defaults(prompt: prompt)
        options.maxTokens = maxTokens
        options.temperature = temperature
        options.topP = topP
        options.streamingEnabled = true
        options.useGpu = true

        let events = try await processImageStream(protoImage, options: options)
        let collector = StreamingCollector()

        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                for await event in events {
                    if event.hasError {
                        let error = SDKException.vlm(.processingFailed, event.error.message)
                        continuation.finish(throwing: error)
                        await collector.fail(error)
                        return
                    }
                    guard case .generation(let generation)? = event.event else {
                        continue
                    }
                    switch generation.kind {
                    case .firstTokenGenerated, .tokenGenerated:
                        if !generation.token.isEmpty {
                            await collector.addToken(generation.token)
                            continuation.yield(generation.token)
                        }
                    case .streamingUpdate:
                        if !generation.streamingText.isEmpty {
                            await collector.replaceText(generation.streamingText, tokenCount: Int(generation.tokensCount))
                        }
                    case .completed, .streamCompleted:
                        if !generation.response.isEmpty {
                            await collector.replaceText(generation.response, tokenCount: Int(generation.tokensUsed))
                        }
                        await collector.complete()
                        continuation.finish()
                        return
                    case .failed:
                        let error = SDKException.vlm(.processingFailed, generation.error)
                        continuation.finish(throwing: error)
                        await collector.fail(error)
                        return
                    default:
                        break
                    }
                }
                await collector.complete()
                continuation.finish()
            }
        }

        let metricsTask = Task<VLMResult, Error> { try await collector.waitForResult() }
        return VLMStreamingResult(stream: stream, metrics: metricsTask)
    }

    // MARK: - Canonical Overloads (CANONICAL_API §7)

    /// Process an image with VLM — canonical form.
    ///
    /// Accepts `VLMGenerationOptions` (alias for proto `RAVLMGenerationOptions`) as a single
    /// optional parameter, matching the cross-SDK canonical spec.
    ///
    /// - Parameters:
    ///   - image: The image to process.
    ///   - prompt: Text prompt for the VLM.
    ///   - options: Optional `VLMGenerationOptions`; uses proto defaults when nil.
    /// - Returns: `VLMResult` with generated text and metrics.
    static func processImage(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions? = nil
    ) async throws -> VLMResult {
        var opts = options ?? VLMGenerationOptions.defaults(prompt: prompt)
        opts.prompt = prompt
        let result = try await processImage(image, options: opts)
        return VLMResult(from: result)
    }

    /// Stream generated-proto VLM events from C++.
    static func processImageStream(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> AsyncStream<RASDKEvent> {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()
        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKException.vlm(.notInitialized, "VLM model not loaded")
        }
        return try await CppBridge.VLM.shared.processStream(image: image, options: options)
    }

    /// Stream image processing — canonical form.
    ///
    /// Accepts `VLMGenerationOptions` and returns `AsyncStream<String>` matching
    /// the cross-SDK canonical spec (CANONICAL_API §7).
    ///
    /// - Parameters:
    ///   - image: The image to process.
    ///   - prompt: Text prompt for the VLM.
    ///   - options: Optional `VLMGenerationOptions`; uses proto defaults when nil.
    /// - Returns: `AsyncStream<String>` yielding tokens as they are generated.
    static func processImageStream(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions? = nil
    ) -> AsyncStream<String> {
        let opts = options ?? VLMGenerationOptions()
        let maxTokens = opts.maxTokens > 0 ? opts.maxTokens : 2048
        let temperature = opts.temperature > 0 ? opts.temperature : Float(0.7)
        let topP = opts.topP > 0 ? opts.topP : Float(0.9)
        return AsyncStream { continuation in
            Task {
                do {
                    let streamingResult = try await processImageStream(
                        image,
                        prompt: prompt,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP
                    )
                    for try await token in streamingResult.stream {
                        continuation.yield(token)
                    }
                } catch {
                    // Swallow errors; caller cannot throw from AsyncStream body.
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Model Management

    /// Load a VLM model by its registry ID (CANONICAL_API §7).
    ///
    /// Looks up the model in the registry and resolves its local path, then
    /// delegates to the 4-arg internal form.
    ///
    /// - Parameter modelId: Registry model identifier.
    static func loadVLMModel(_ modelId: String) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        // Resolve model path from registry
        let allModels = try await availableModels()
        if let modelInfo = allModels.first(where: { $0.id == modelId }),
           let localPath = modelInfo.localPath {
            try await CppBridge.VLM.shared.loadModel(
                localPath.path,
                mmprojPath: nil,
                modelId: modelId,
                modelName: modelInfo.name
            )
        } else {
            // Fall back to treating modelId as a direct path (development convenience).
            try await CppBridge.VLM.shared.loadModel(modelId, mmprojPath: nil, modelId: modelId, modelName: modelId)
        }
    }

    /// Load a VLM model with explicit paths (internal / advanced usage).
    static func loadVLMModel(_ modelPath: String, mmprojPath: String?, modelId: String, modelName: String) async throws {
        try await CppBridge.VLM.shared.loadModel(modelPath, mmprojPath: mmprojPath, modelId: modelId, modelName: modelName)
    }

    static func unloadVLMModel() async {
        await CppBridge.VLM.shared.unload()
    }

    static var isVLMModelLoaded: Bool {
        get async { await CppBridge.VLM.shared.isLoaded }
    }

    static func cancelVLMGeneration() async {
        await CppBridge.VLM.shared.cancel()
    }
}

// MARK: - Internal Streaming Helpers

private actor StreamingCollector {
    private let startTime = Date()
    private var text = ""
    private var tokens = 0
    private var isDone = false
    private var error: Error?
    private var waiting: CheckedContinuation<VLMResult, Error>?

    func addToken(_ token: String) {
        text += token
        tokens += 1
    }

    func replaceText(_ newText: String, tokenCount: Int) {
        text = newText
        tokens = max(tokens, tokenCount)
    }

    func complete() {
        isDone = true
        waiting?.resume(returning: buildResult())
        waiting = nil
    }

    func fail(_ error: Error) {
        self.error = error
        waiting?.resume(throwing: error)
        waiting = nil
    }

    func waitForResult() async throws -> VLMResult {
        if isDone { return buildResult() }
        if let error = error { throw error }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }

    private func buildResult() -> VLMResult {
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        let tps = elapsed > 0 ? Double(tokens) / (elapsed / 1000) : 0
        return VLMResult(text: text, promptTokens: 0, completionTokens: tokens, totalTimeMs: elapsed, tokensPerSecond: tps)
    }
}

// MARK: - VLMResult initializer extension

extension VLMResult {
    init(text: String, promptTokens: Int, completionTokens: Int, totalTimeMs: Double, tokensPerSecond: Double) {
        self.text = text
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTimeMs = totalTimeMs
        self.tokensPerSecond = tokensPerSecond
    }
}
