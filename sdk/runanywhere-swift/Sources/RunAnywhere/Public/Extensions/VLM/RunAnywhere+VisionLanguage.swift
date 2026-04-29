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
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        let handle = try await CppBridge.VLM.shared.getHandle()
        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKException.vlm(.notInitialized, "VLM model not loaded")
        }

        guard let imageData = image.toCImage() else {
            throw SDKException.vlm(.invalidImage, "Failed to convert image")
        }
        var cImage = imageData.0
        let rgbData = imageData.1

        // Setup options using C struct directly
        var opts = rac_vlm_options_t()
        opts.max_tokens = maxTokens
        opts.temperature = temperature
        opts.top_p = topP
        opts.streaming_enabled = RAC_FALSE
        opts.use_gpu = RAC_TRUE

        var vlmResult = rac_vlm_result_t()
        let result: rac_result_t = image.withCPointers(cImage: &cImage, rgbData: rgbData) { cImagePtr in
            prompt.withCString { promptPtr in
                rac_vlm_component_process(handle, cImagePtr, promptPtr, &opts, &vlmResult)
            }
        }

        guard result == RAC_SUCCESS else {
            throw SDKException.vlm(.processingFailed, "VLM processing failed: \(result)")
        }
        defer { rac_vlm_result_free(&vlmResult) }

        return VLMResult(from: vlmResult)
    }

    /// Stream image processing with real-time tokens
    static func processImageStream(
        _ image: VLMImage,
        prompt: String,
        maxTokens: Int32 = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9
    ) async throws -> VLMStreamingResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        let handle = try await CppBridge.VLM.shared.getHandle()
        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKException.vlm(.notInitialized, "VLM model not loaded")
        }

        guard let imageData = image.toCImage() else {
            throw SDKException.vlm(.invalidImage, "Failed to convert image")
        }
        var cImage = imageData.0
        let rgbData = imageData.1
        let capturedCImage = cImage

        let collector = StreamingCollector()

        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                let context = StreamContext(continuation: continuation, collector: collector)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                var opts = rac_vlm_options_t()
                opts.max_tokens = maxTokens
                opts.temperature = temperature
                opts.top_p = topP
                opts.streaming_enabled = RAC_TRUE
                opts.use_gpu = RAC_TRUE

                let tokenCb: rac_vlm_component_token_callback_fn = { tokenPtr, userData -> rac_bool_t in
                    guard let tokenPtr = tokenPtr, let userData = userData else { return RAC_TRUE }
                    let ctx = Unmanaged<StreamContext>.fromOpaque(userData).takeUnretainedValue()
                    let token = String(cString: tokenPtr)
                    Task {
                        await ctx.collector.addToken(token)
                        ctx.continuation.yield(token)
                    }
                    return RAC_TRUE
                }

                let completeCb: rac_vlm_component_complete_callback_fn = { _, userData in
                    guard let userData = userData else { return }
                    let ctx = Unmanaged<StreamContext>.fromOpaque(userData).takeRetainedValue()
                    ctx.continuation.finish()
                    Task { await ctx.collector.complete() }
                }

                let errorCb: rac_vlm_component_error_callback_fn = { _, msg, userData in
                    guard let userData = userData else { return }
                    let ctx = Unmanaged<StreamContext>.fromOpaque(userData).takeRetainedValue()
                    let error = SDKException.vlm(.processingFailed, msg.map { String(cString: $0) } ?? "Unknown")
                    ctx.continuation.finish(throwing: error)
                    Task { await ctx.collector.fail(error) }
                }

                var localCImage = capturedCImage
                let result: rac_result_t = image.withCPointers(cImage: &localCImage, rgbData: rgbData) { cImagePtr in
                    prompt.withCString { promptPtr in
                        rac_vlm_component_process_stream(handle, cImagePtr, promptPtr, &opts, tokenCb, completeCb, errorCb, contextPtr)
                    }
                }

                if result != RAC_SUCCESS {
                    Unmanaged<StreamContext>.fromOpaque(contextPtr).release()
                    let error = SDKException.vlm(.processingFailed, "Stream failed: \(result)")
                    continuation.finish(throwing: error)
                    await collector.fail(error)
                }
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
        let opts = options ?? VLMGenerationOptions()
        return try await processImage(
            image,
            prompt: prompt,
            maxTokens: opts.maxTokens > 0 ? opts.maxTokens : 2048,
            temperature: opts.temperature > 0 ? opts.temperature : 0.7,
            topP: opts.topP > 0 ? opts.topP : 0.9
        )
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

private final class StreamContext: @unchecked Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    let collector: StreamingCollector
    init(continuation: AsyncThrowingStream<String, Error>.Continuation, collector: StreamingCollector) {
        self.continuation = continuation
        self.collector = collector
    }
}

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
