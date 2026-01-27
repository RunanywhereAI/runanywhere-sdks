//
//  RunAnywhere+VisionLanguage.swift
//  RunAnywhere SDK
//
//  Public API for Vision Language Model (VLM) operations.
//  Supports multiple backends:
//  - llama.cpp (GGUF models) via C++ CppBridge.VLM
//  - MLX (safetensors/HuggingFace) via Swift MLXVLMAdapter
//
//  Backend selection is automatic based on which model is loaded,
//  or can be explicitly specified.
//

import CRACommons
import Foundation

// MARK: - VLM Backend Selection

/// VLM backend selection for processing
public enum VLMBackend: Sendable {
    /// Automatically select based on which backend has a model loaded
    /// Priority: MLX (if loaded) > llama.cpp (if loaded)
    case auto

    /// Use llama.cpp backend (GGUF models)
    case llamaCpp

    /// Use MLX backend (safetensors/HuggingFace models)
    case mlx
}

// MARK: - Vision Language Model

public extension RunAnywhere {

    // MARK: - Simple API

    /// Describe an image with a simple text prompt
    ///
    /// Automatically selects the backend based on which model is loaded.
    ///
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - prompt: Text prompt describing what to analyze (e.g., "What's in this image?")
    /// - Returns: Generated text description
    static func describeImage(_ image: VLMImage, prompt: String = "What's in this image?") async throws -> String {
        let result = try await processImage(image, prompt: prompt, options: nil, backend: .auto)
        return result.text
    }

    /// Ask a question about an image
    ///
    /// Automatically selects the backend based on which model is loaded.
    ///
    /// - Parameters:
    ///   - question: The question to ask about the image
    ///   - image: The image to analyze
    /// - Returns: Generated answer
    static func askAboutImage(_ question: String, image: VLMImage) async throws -> String {
        let result = try await processImage(image, prompt: question, options: nil, backend: .auto)
        return result.text
    }

    // MARK: - Full API with Backend Selection

    /// Process an image with full metrics and options
    ///
    /// - Parameters:
    ///   - image: The image to process
    ///   - prompt: Text prompt
    ///   - options: Generation options (optional)
    ///   - backend: Backend selection (defaults to .auto)
    /// - Returns: VLMGenerationResult with full metrics
    static func processImage(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions? = nil,
        backend: VLMBackend = .auto
    ) async throws -> VLMGenerationResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let resolvedBackend = try await resolveBackend(backend)

        switch resolvedBackend {
        case .mlx:
            return try await processImageWithMLX(image, prompt: prompt, options: options)
        case .llamaCpp, .auto:
            return try await processImageWithLlamaCpp(image, prompt: prompt, options: options)
        }
    }

    /// Stream image processing with real-time token output
    ///
    /// Example usage:
    /// ```swift
    /// let result = try await RunAnywhere.processImageStream(image, prompt: "Describe this")
    ///
    /// // Display tokens in real-time
    /// for try await token in result.stream {
    ///     print(token, terminator: "")
    /// }
    ///
    /// // Get complete analytics after streaming finishes
    /// let metrics = try await result.result.value
    /// print("Speed: \(metrics.tokensPerSecond) tok/s")
    /// ```
    ///
    /// - Parameters:
    ///   - image: The image to process
    ///   - prompt: Text prompt
    ///   - options: Generation options (optional)
    ///   - backend: Backend selection (defaults to .auto)
    /// - Returns: VLMStreamingResult containing both the token stream and final metrics task
    static func processImageStream(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions? = nil,
        backend: VLMBackend = .auto
    ) async throws -> VLMStreamingResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let resolvedBackend = try await resolveBackend(backend)

        switch resolvedBackend {
        case .mlx:
            return try await processImageStreamWithMLX(image, prompt: prompt, options: options)
        case .llamaCpp, .auto:
            return try await processImageStreamWithLlamaCpp(image, prompt: prompt, options: options)
        }
    }

    // MARK: - Model Management

    /// Load a VLM model (llama.cpp backend)
    /// - Parameters:
    ///   - modelPath: Path to the main model file (GGUF)
    ///   - mmprojPath: Path to the vision projector file (required for llama.cpp)
    ///   - modelId: Model identifier
    ///   - modelName: Human-readable name
    static func loadVLMModel(
        _ modelPath: String,
        mmprojPath: String?,
        modelId: String,
        modelName: String
    ) async throws {
        try await CppBridge.VLM.shared.loadModel(modelPath, mmprojPath: mmprojPath, modelId: modelId, modelName: modelName)
    }

    /// Unload the current VLM model (both backends)
    static func unloadVLMModel() async {
        // Unload llama.cpp backend
        await CppBridge.VLM.shared.unload()

        // Unload MLX backend
        if #available(iOS 16.0, macOS 14.0, *) {
            await MLXVLMAdapter.shared.unloadModel()
        }
    }

    /// Check if any VLM model is loaded (either backend)
    static var isVLMModelLoaded: Bool {
        get async {
            // Check llama.cpp backend
            let llamaCppLoaded = await CppBridge.VLM.shared.isLoaded

            // Check MLX backend
            var mlxLoaded = false
            if #available(iOS 16.0, macOS 14.0, *) {
                mlxLoaded = await MLXVLMAdapter.shared.isLoaded
            }

            return llamaCppLoaded || mlxLoaded
        }
    }

    /// Get the currently active VLM backend
    static var activeVLMBackend: VLMBackend? {
        get async {
            if #available(iOS 16.0, macOS 14.0, *) {
                if await MLXVLMAdapter.shared.isLoaded {
                    return .mlx
                }
            }
            if await CppBridge.VLM.shared.isLoaded {
                return .llamaCpp
            }
            return nil
        }
    }

    /// Cancel ongoing VLM generation (both backends)
    static func cancelVLMGeneration() async {
        // Cancel llama.cpp backend
        await CppBridge.VLM.shared.cancel()

        // Cancel MLX backend
        if #available(iOS 16.0, macOS 14.0, *) {
            await MLXVLMAdapter.shared.cancel()
        }
    }

    // MARK: - Backend Resolution

    /// Resolve which backend to use based on selection and loaded models
    private static func resolveBackend(_ requested: VLMBackend) async throws -> VLMBackend {
        switch requested {
        case .auto:
            // Check MLX first (preferred on Apple Silicon)
            if #available(iOS 16.0, macOS 14.0, *) {
                if await MLXVLMAdapter.shared.isLoaded {
                    return .mlx
                }
            }
            // Fall back to llama.cpp
            if await CppBridge.VLM.shared.isLoaded {
                return .llamaCpp
            }
            // No model loaded
            throw SDKError.vlm(.notInitialized, "No VLM model loaded. Load a model first.")

        case .mlx:
            if #available(iOS 16.0, macOS 14.0, *) {
                guard await MLXVLMAdapter.shared.isLoaded else {
                    throw SDKError.vlm(.notInitialized, "MLX VLM model not loaded")
                }
                return .mlx
            } else {
                throw SDKError.vlm(.notInitialized, "MLX requires iOS 16+ or macOS 14+")
            }

        case .llamaCpp:
            guard await CppBridge.VLM.shared.isLoaded else {
                throw SDKError.vlm(.notInitialized, "llama.cpp VLM model not loaded")
            }
            return .llamaCpp
        }
    }

    // MARK: - MLX Backend Processing

    @available(iOS 16.0, macOS 14.0, *)
    private static func processImageWithMLX(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions?
    ) async throws -> VLMGenerationResult {
        let opts = options ?? VLMGenerationOptions()
        return try await MLXVLMAdapter.shared.processImage(
            image: image,
            prompt: prompt,
            options: opts
        )
    }

    @available(iOS 16.0, macOS 14.0, *)
    private static func processImageStreamWithMLX(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions?
    ) async throws -> VLMStreamingResult {
        let opts = options ?? VLMGenerationOptions()
        let modelId = await MLXVLMAdapter.shared.currentModelId ?? "unknown"

        let collector = VLMStreamingMetricsCollector(modelId: modelId, promptLength: prompt.count)
        await collector.markStart()

        let rawStream = try await MLXVLMAdapter.shared.processImageStream(
            image: image,
            prompt: prompt,
            options: opts
        )

        // Wrap stream to collect metrics
        let metricsStream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await token in rawStream {
                        await collector.recordToken(token)
                        continuation.yield(token)
                    }
                    continuation.finish()
                    await collector.markComplete()
                } catch {
                    continuation.finish(throwing: error)
                    await collector.markFailed(error)
                }
            }
        }

        let resultTask = Task<VLMGenerationResult, Error> {
            try await collector.waitForResult()
        }

        return VLMStreamingResult(stream: metricsStream, result: resultTask)
    }

    // MARK: - llama.cpp Backend Processing

    private static func processImageWithLlamaCpp(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions?
    ) async throws -> VLMGenerationResult {
        try await ensureServicesReady()

        // Get handle from CppBridge.VLM
        let handle = try await CppBridge.VLM.shared.getHandle()

        // Verify model is loaded
        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKError.vlm(.notInitialized, "VLM model not loaded")
        }

        let modelId = await CppBridge.VLM.shared.currentModelId ?? "unknown"
        let opts = options ?? VLMGenerationOptions()

        // Convert Swift image to C struct
        guard let (cImage, retainedData) = image.toCImage() else {
            throw SDKError.vlm(.invalidImage, "Failed to convert image to C format")
        }

        // Generate (non-streaming)
        var vlmResult = rac_vlm_result_t()
        let generateResult: rac_result_t = try opts.withCOptions { cOptionsPtr in
            return withImagePointers(cImage: cImage, format: image.format, retainedData: retainedData) { cImagePtr in
                return prompt.withCString { promptPtr in
                    return rac_vlm_component_process(handle, cImagePtr, promptPtr, cOptionsPtr, &vlmResult)
                }
            }
        }

        guard generateResult == RAC_SUCCESS else {
            throw SDKError.vlm(.processingFailed, "VLM processing failed: \(generateResult)")
        }

        defer {
            // Free the result text if allocated
            rac_vlm_result_free(&vlmResult)
        }

        return VLMGenerationResult(from: vlmResult, modelId: modelId)
    }

    private static func processImageStreamWithLlamaCpp(
        _ image: VLMImage,
        prompt: String,
        options: VLMGenerationOptions?
    ) async throws -> VLMStreamingResult {
        try await ensureServicesReady()

        let handle = try await CppBridge.VLM.shared.getHandle()

        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKError.vlm(.notInitialized, "VLM model not loaded")
        }

        let modelId = await CppBridge.VLM.shared.currentModelId ?? "unknown"
        let opts = options ?? VLMGenerationOptions()

        // Convert Swift image to C struct
        guard let (cImage, retainedData) = image.toCImage() else {
            throw SDKError.vlm(.invalidImage, "Failed to convert image to C format")
        }

        let collector = VLMStreamingMetricsCollector(modelId: modelId, promptLength: prompt.count)

        let stream = createVLMTokenStream(
            image: image,
            cImage: cImage,
            retainedData: retainedData,
            prompt: prompt,
            handle: handle,
            options: opts,
            collector: collector
        )

        let resultTask = Task<VLMGenerationResult, Error> {
            try await collector.waitForResult()
        }

        return VLMStreamingResult(stream: stream, result: resultTask)
    }

    // MARK: - Private Streaming Helpers

    private static func createVLMTokenStream(
        image: VLMImage,
        cImage: rac_vlm_image_t,
        retainedData: (any Sendable)?,
        prompt: String,
        handle: UnsafeMutableRawPointer,
        options: VLMGenerationOptions,
        collector: VLMStreamingMetricsCollector
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    await collector.markStart()

                    let context = VLMStreamCallbackContext(continuation: continuation, collector: collector)
                    let contextPtr = Unmanaged.passRetained(context).toOpaque()

                    let callbacks = VLMStreamCallbacks.create()

                    let streamResult: rac_result_t = try options.withCOptions { cOptionsPtr in
                        return withImagePointers(cImage: cImage, format: image.format, retainedData: retainedData) { cImagePtr in
                            return prompt.withCString { promptPtr in
                                return rac_vlm_component_process_stream(
                                    handle,
                                    cImagePtr,
                                    promptPtr,
                                    cOptionsPtr,
                                    callbacks.token,
                                    callbacks.complete,
                                    callbacks.error,
                                    contextPtr
                                )
                            }
                        }
                    }

                    if streamResult != RAC_SUCCESS {
                        Unmanaged<VLMStreamCallbackContext>.fromOpaque(contextPtr).release()
                        let error = SDKError.vlm(.processingFailed, "VLM stream processing failed: \(streamResult)")
                        continuation.finish(throwing: error)
                        await collector.markFailed(error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                    await collector.markFailed(error)
                }
            }
        }
    }

    /// Helper to set up image pointers for C API
    private static func withImagePointers<T>(
        cImage: rac_vlm_image_t,
        format: VLMImage.Format,
        retainedData: (any Sendable)?,
        body: (UnsafePointer<rac_vlm_image_t>) -> T
    ) -> T {
        var mutableImage = cImage

        switch format {
        case .filePath(let path):
            return path.withCString { pathPtr in
                mutableImage.file_path = pathPtr
                return body(&mutableImage)
            }

        case .rgbPixels(let data, _, _):
            return data.withUnsafeBytes { buffer in
                mutableImage.pixel_data = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return body(&mutableImage)
            }

        case .base64(let encoded):
            return encoded.withCString { base64Ptr in
                mutableImage.base64_data = base64Ptr
                return body(&mutableImage)
            }

        #if canImport(UIKit)
        case .uiImage:
            // retainedData contains the converted RGB data
            if let rgbData = retainedData as? Data {
                return rgbData.withUnsafeBytes { buffer in
                    mutableImage.pixel_data = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    return body(&mutableImage)
                }
            }
            return body(&mutableImage)
        #endif

        #if canImport(CoreVideo)
        case .pixelBuffer:
            // retainedData contains the converted RGB data
            if let rgbData = retainedData as? Data {
                return rgbData.withUnsafeBytes { buffer in
                    mutableImage.pixel_data = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    return body(&mutableImage)
                }
            }
            return body(&mutableImage)
        #endif
        }
    }
}

// MARK: - Streaming Callbacks

private enum VLMStreamCallbacks {
    typealias TokenFn = rac_vlm_component_token_callback_fn
    typealias CompleteFn = rac_vlm_component_complete_callback_fn
    typealias ErrorFn = rac_vlm_component_error_callback_fn

    struct Callbacks {
        let token: TokenFn
        let complete: CompleteFn
        let error: ErrorFn
    }

    static func create() -> Callbacks {
        let tokenCallback: TokenFn = { tokenPtr, userData -> rac_bool_t in
            guard let tokenPtr = tokenPtr, let userData = userData else { return RAC_TRUE }
            let ctx = Unmanaged<VLMStreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
            let token = String(cString: tokenPtr)
            Task {
                await ctx.collector.recordToken(token)
                ctx.continuation.yield(token)
            }
            return RAC_TRUE
        }

        let completeCallback: CompleteFn = { _, userData in
            guard let userData = userData else { return }
            let ctx = Unmanaged<VLMStreamCallbackContext>.fromOpaque(userData).takeRetainedValue()
            ctx.continuation.finish()
            Task { await ctx.collector.markComplete() }
        }

        let errorCallback: ErrorFn = { _, errorMsg, userData in
            guard let userData = userData else { return }
            let ctx = Unmanaged<VLMStreamCallbackContext>.fromOpaque(userData).takeRetainedValue()
            let message = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            let error = SDKError.vlm(.processingFailed, message)
            ctx.continuation.finish(throwing: error)
            Task { await ctx.collector.markFailed(error) }
        }

        return Callbacks(token: tokenCallback, complete: completeCallback, error: errorCallback)
    }
}

// MARK: - Streaming Callback Context

private final class VLMStreamCallbackContext: @unchecked Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    let collector: VLMStreamingMetricsCollector

    init(continuation: AsyncThrowingStream<String, Error>.Continuation, collector: VLMStreamingMetricsCollector) {
        self.continuation = continuation
        self.collector = collector
    }
}

// MARK: - Streaming Metrics Collector

/// Internal actor for collecting VLM streaming metrics
private actor VLMStreamingMetricsCollector {
    private let modelId: String
    private let promptLength: Int

    private var startTime: Date?
    private var firstTokenTime: Date?
    private var fullText = ""
    private var tokenCount = 0
    private var firstTokenRecorded = false
    private var isComplete = false
    private var error: Error?
    private var resultContinuation: CheckedContinuation<VLMGenerationResult, Error>?

    init(modelId: String, promptLength: Int) {
        self.modelId = modelId
        self.promptLength = promptLength
    }

    func markStart() {
        startTime = Date()
    }

    func recordToken(_ token: String) {
        fullText += token
        tokenCount += 1

        if !firstTokenRecorded {
            firstTokenRecorded = true
            firstTokenTime = Date()
        }
    }

    func markComplete() {
        isComplete = true
        if let continuation = resultContinuation {
            continuation.resume(returning: buildResult())
            resultContinuation = nil
        }
    }

    func markFailed(_ error: Error) {
        self.error = error
        if let continuation = resultContinuation {
            continuation.resume(throwing: error)
            resultContinuation = nil
        }
    }

    func waitForResult() async throws -> VLMGenerationResult {
        if isComplete {
            return buildResult()
        }
        if let error = error {
            throw error
        }
        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
        }
    }

    private func buildResult() -> VLMGenerationResult {
        let endTime = Date()
        let totalTimeMs = (startTime.map { endTime.timeIntervalSince($0) } ?? 0) * 1000

        var timeToFirstTokenMs: Double?
        if let start = startTime, let firstToken = firstTokenTime {
            timeToFirstTokenMs = firstToken.timeIntervalSince(start) * 1000
        }

        // Estimate tokens (rough approximation)
        let promptTokens = max(1, promptLength / 4)
        let completionTokens = tokenCount
        let tokensPerSecond = totalTimeMs > 0 ? Double(completionTokens) / (totalTimeMs / 1000.0) : 0

        return VLMGenerationResult(
            text: fullText,
            promptTokens: promptTokens,
            imageTokens: 0, // We don't have this from streaming
            completionTokens: completionTokens,
            totalTokens: promptTokens + completionTokens,
            timeToFirstTokenMs: timeToFirstTokenMs,
            imageEncodeTimeMs: nil,
            totalTimeMs: totalTimeMs,
            tokensPerSecond: tokensPerSecond,
            modelUsed: modelId
        )
    }
}
