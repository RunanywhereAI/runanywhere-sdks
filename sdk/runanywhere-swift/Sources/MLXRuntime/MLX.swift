//
//  MLX.swift
//  MLXRuntime Module
//

// swiftlint:disable file_length

import CoreImage
import CRACommons
import Foundation
import MLX
import MLXAudioSTT
import MLXAudioTTS
import MLXBackend
import MLXEmbedders
import MLXLLM
import MLXLMCommon
import MLXVLM
import os
import RunAnywhere
import Tokenizers

public enum MLX {
    private static let logger = SDKLogger(category: "MLX")
    private static var isRegistered = false

    public static let version = "1.0.0"
    public static let mlxSwiftLMVersion = "3.31.4"

    @MainActor
    @discardableResult
    public static func register(priority _: Int = 100) -> Bool {
        guard !isRegistered else {
            logger.debug("MLX already registered, returning")
            return true
        }

        var callbacks = rac_mlx_callbacks_t()
        callbacks.struct_size = UInt32(MemoryLayout<rac_mlx_callbacks_t>.size)
        callbacks.create = mlxCreate
        callbacks.initialize = mlxInitialize
        callbacks.llm_generate = mlxLLMGenerate
        callbacks.llm_generate_stream = mlxLLMGenerateStream
        callbacks.vlm_process = mlxVLMProcess
        callbacks.vlm_process_stream = mlxVLMProcessStream
        callbacks.embed_batch = mlxEmbedBatch
        callbacks.embedding_info = mlxEmbeddingInfo
        callbacks.stt_transcribe = mlxSTTTranscribe
        callbacks.stt_transcribe_stream = mlxSTTTranscribeStream
        callbacks.stt_info = mlxSTTInfo
        callbacks.tts_synthesize = mlxTTSSynthesize
        callbacks.tts_synthesize_stream = mlxTTSSynthesizeStream
        callbacks.tts_stop = mlxTTSStop
        callbacks.tts_info = mlxTTSInfo
        callbacks.cancel = mlxCancel
        callbacks.cleanup = mlxCleanup
        callbacks.destroy = mlxDestroy
        callbacks.user_data = nil

        let callbackResult = rac_mlx_set_callbacks(&callbacks)
        guard callbackResult == RAC_SUCCESS else {
            let message = String(cString: rac_error_message(callbackResult))
            logger.error("MLX callback registration failed: \(message)")
            return false
        }

        let registerResult = rac_backend_mlx_register()
        if registerResult != RAC_SUCCESS && registerResult != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            let message = String(cString: rac_error_message(registerResult))
            logger.error("MLX backend registration failed: \(message)")
            return false
        }

        isRegistered = true
        logger.info("MLX backend registered successfully")
        return true
    }

    @MainActor
    public static func unregister() {
        guard isRegistered else { return }
        _ = rac_backend_mlx_unregister()
        isRegistered = false
        logger.info("MLX backend unregistered")
    }

    public static let autoRegister: Void = {
        Task { @MainActor in
            _ = MLX.register()
        }
    }()
}

private enum MLXSessionKind {
    case llm
    case vlm
    case embeddings
    case stt
    case tts
}

private struct TransformersTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TransformersTokenizerBridge(upstream)
    }
}

private struct TransformersTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private struct MLXGenerationMetrics {
    var promptTokens = 0
    var completionTokens = 0
    var totalTimeMs: Int64 = 0
    var tokensPerSecond: Float = 0
}

private enum MLXMemoryPolicy {
    private static let vlmCacheLimitBytes = 64 * 1024 * 1024

    static func prepareForVLMGeneration() -> (() -> Void)? {
        prepareCacheLimit(for: .vlm)
    }

    static func prepareForModelLoad(_ kind: MLXSessionKind) -> (() -> Void)? {
        prepareCacheLimit(for: kind)
    }

    static func releaseVLMTemporaryBuffers() {
        clearCachedBuffers(reason: "VLM request")
    }

    static func releaseGenerationCachedBuffers(reason: String) {
        clearCachedBuffers(reason: reason)
    }

    private static func prepareCacheLimit(for kind: MLXSessionKind) -> (() -> Void)? {
        guard kind == .vlm else { return nil }

        let previousLimit = Memory.cacheLimit
        if previousLimit > vlmCacheLimitBytes {
            Memory.cacheLimit = vlmCacheLimitBytes
        }

        return {
            if Memory.cacheLimit != previousLimit {
                Memory.cacheLimit = previousLimit
            }
        }
    }

    private static func clearCachedBuffers(reason: String) {
        Stream().synchronize()
        Memory.clearCache()

        let snapshot = Memory.snapshot()
        mlxRuntimeLogger.debug(
            "MLX memory after cache clear (\(reason)): active=\(snapshot.activeMemory), cache=\(snapshot.cacheMemory), peak=\(snapshot.peakMemory)"
        )
    }
}

private enum MLXSessionCoordinator {
    private static let lock = OSAllocatedUnfairLock<[ObjectIdentifier: MLXSession]>(
        initialState: [:]
    )

    static func register(_ session: MLXSession) {
        lock.withLock { $0[ObjectIdentifier(session)] = session }
    }

    static func unregister(_ session: MLXSession) {
        lock.withLock {
            _ = $0.removeValue(forKey: ObjectIdentifier(session))
        }
    }

    static func prepareForLoad(_ session: MLXSession) {
        guard session.isGenerationSession else { return }

        let residents = lock.withLock { sessions in
            sessions.values.filter {
                $0 !== session && $0.isGenerationSession && $0.isLoadedSnapshot
            }
        }

        for resident in residents {
            let residentKind = resident.kindDescription
            let residentModelID = resident.modelID
            let sessionKind = session.kindDescription
            let sessionModelID = session.modelID
            mlxRuntimeLogger.info(
                "Evicting resident MLX \(residentKind) model '\(residentModelID)' before loading \(sessionKind) model '\(sessionModelID)'"
            )
            resident.releaseResidentGenerationModel()
        }

        MLXMemoryPolicy.releaseGenerationCachedBuffers(reason: "before loading \(session.kindDescription)")
    }
}

private struct RepetitionRunGuard {
    private static let repeatedTokenLimit = 6
    private var recentTokens: [String] = []

    mutating func shouldStop(after token: String) -> Bool {
        let normalized = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        recentTokens.append(normalized)
        if recentTokens.count > Self.repeatedTokenLimit {
            recentTokens.removeFirst(recentTokens.count - Self.repeatedTokenLimit)
        }

        guard recentTokens.count == Self.repeatedTokenLimit else { return false }
        return recentTokens.dropFirst().allSatisfy { $0 == recentTokens[0] }
    }
}

// swiftlint:disable:next type_body_length
private final class MLXSession: @unchecked Sendable {
    private struct State {
        var isCancelled = false
        var isLoaded = false
        var embeddingDimension = 0
        var isSynthesizing = false
    }

    // swiftlint:disable:next strict_fileprivate
    fileprivate let kind: MLXSessionKind
    // swiftlint:disable:next strict_fileprivate
    fileprivate let modelID: String
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private var generationContainer: ModelContainer?
    private var embedderContainer: EmbedderModelContainer?
    private var sttModel: STTGenerationModel?
    private var ttsModel: SpeechGenerationModel?

    init(kind: MLXSessionKind, modelID: String) {
        self.kind = kind
        self.modelID = modelID
        MLXSessionCoordinator.register(self)
    }

    func load(modelPath: String) async throws {
        #if targetEnvironment(simulator)
        throw MLXRuntimeError.simulatorUnsupported
        #else
        MLXSessionCoordinator.prepareForLoad(self)
        let restoreMemoryPolicy = MLXMemoryPolicy.prepareForModelLoad(kind)
        defer { restoreMemoryPolicy?() }

        let directory = modelDirectoryURL(from: modelPath)
        let tokenizerLoader: any TokenizerLoader = TransformersTokenizerLoader()
        switch kind {
        case .llm:
            generationContainer = try await LLMModelFactory.shared.loadContainer(
                from: directory,
                using: tokenizerLoader
            )
        case .vlm:
            generationContainer = try await VLMModelFactory.shared.loadContainer(
                from: directory,
                using: tokenizerLoader
            )
        case .embeddings:
            embedderContainer = try await EmbedderModelFactory.shared.loadContainer(
                from: directory,
                using: tokenizerLoader
            )
        case .stt:
            sttModel = try await loadSpeechRecognitionModel(from: directory, modelID: modelID)
        case .tts:
            ttsModel = try await MLXAudioTTS.TTS.loadModel(modelRepo: directory.path)
        }
        lock.withLock {
            $0.isLoaded = true
            $0.isCancelled = false
        }
        #endif
    }

    func generate(prompt: String, options: UnsafePointer<rac_llm_options_t>?) async throws
        -> (String, MLXGenerationMetrics) {
        let resolvedOptions = options?.pointee
        let params = generateParameters(from: resolvedOptions)
        let input = UserInput(
            prompt: prompt,
            additionalContext: llmAdditionalContext(from: resolvedOptions)
        )
        return try await collect(input: input, parameters: params)
    }

    func generateStream(
        prompt: String,
        options: UnsafePointer<rac_llm_options_t>?,
        callback: rac_llm_stream_callback_fn?,
        userData: UnsafeMutableRawPointer?
    ) async throws -> MLXGenerationMetrics {
        let resolvedOptions = options?.pointee
        let params = generateParameters(from: resolvedOptions)
        let input = UserInput(
            prompt: prompt,
            additionalContext: llmAdditionalContext(from: resolvedOptions)
        )
        return try await stream(input: input, parameters: params) { token in
            guard let callback else { return false }
            return token.withCString { callback($0, userData) == RAC_TRUE }
        }
    }

    func process(
        image: UnsafePointer<rac_vlm_image_t>,
        prompt: String,
        options: UnsafePointer<rac_vlm_options_t>?
    ) async throws -> (String, MLXGenerationMetrics) {
        let image = try imageInput(from: image.pointee)
        let params = generateParameters(from: options?.pointee)
        return try await collectVLM(prompt: prompt, image: image, parameters: params)
    }

    func processStream(
        image: UnsafePointer<rac_vlm_image_t>,
        prompt: String,
        options: UnsafePointer<rac_vlm_options_t>?,
        callback: rac_vlm_stream_callback_fn?,
        userData: UnsafeMutableRawPointer?
    ) async throws -> MLXGenerationMetrics {
        let image = try imageInput(from: image.pointee)
        let params = generateParameters(from: options?.pointee)
        return try await streamVLM(prompt: prompt, image: image, parameters: params) { token in
            guard let callback else { return false }
            return token.withCString { callback($0, userData) == RAC_TRUE }
        }
    }

    func cancel() {
        lock.withLock { $0.isCancelled = true }
    }

    func cleanup() {
        generationContainer = nil
        embedderContainer = nil
        sttModel = nil
        ttsModel = nil
        if isGenerationSession {
            MLXMemoryPolicy.releaseGenerationCachedBuffers(reason: "cleanup \(kindDescription)")
        }
        lock.withLock {
            $0.isLoaded = false
            $0.isCancelled = true
            $0.embeddingDimension = 0
            $0.isSynthesizing = false
        }
    }

    private func collect(input: UserInput, parameters: GenerateParameters) async throws
        -> (String, MLXGenerationMetrics) {
        var text = ""
        let metrics = try await stream(input: input, parameters: parameters) { token in
            text += token
            return true
        }
        return (text, metrics)
    }

    private func collectVLM(
        prompt: String,
        image: UserInput.Image,
        parameters: GenerateParameters
    ) async throws -> (String, MLXGenerationMetrics) {
        var text = ""
        let metrics = try await streamVLM(prompt: prompt, image: image, parameters: parameters) { token in
            text += token
            return true
        }
        return (text, metrics)
    }

    private func streamVLM(
        prompt: String,
        image: UserInput.Image,
        parameters: GenerateParameters,
        onToken: @escaping @Sendable (String) -> Bool
    ) async throws -> MLXGenerationMetrics {
        guard let container = generationContainer else {
            throw MLXRuntimeError.notLoaded(modelID)
        }

        let restoreMemoryPolicy = MLXMemoryPolicy.prepareForVLMGeneration()
        defer {
            MLXMemoryPolicy.releaseVLMTemporaryBuffers()
            restoreMemoryPolicy?()
        }

        let session = ChatSession(
            container,
            generateParameters: parameters,
            processing: UserInput.Processing(resize: CGSize(width: 512, height: 512))
        )
        let events = session.streamDetails(to: prompt, images: [image])
        var metrics = MLXGenerationMetrics()
        var repetitionGuard = RepetitionRunGuard()
        var suppressRunawayTokens = false
        let started = Date()

        generationLoop: for try await event in events {
            if isCancelled {
                break
            }
            switch event {
            case .chunk(let token):
                if suppressRunawayTokens {
                    continue
                }
                if repetitionGuard.shouldStop(after: token) {
                    mlxRuntimeLogger.warning("Suppressing MLX VLM tokens after repeated token runaway")
                    suppressRunawayTokens = true
                    continue
                }
                if !onToken(token) {
                    cancel()
                    break generationLoop
                }
            case .info(let info):
                metrics.promptTokens = info.promptTokenCount
                metrics.completionTokens = info.generationTokenCount
                metrics.tokensPerSecond = Float(info.tokensPerSecond)
                metrics.totalTimeMs = Int64((info.promptTime + info.generateTime) * 1000)
            case .toolCall:
                break
            }
        }

        if metrics.totalTimeMs == 0 {
            metrics.totalTimeMs = Int64(Date().timeIntervalSince(started) * 1000)
        }
        return metrics
    }

    private func stream(
        input: UserInput,
        parameters: GenerateParameters,
        onToken: @escaping @Sendable (String) -> Bool
    ) async throws -> MLXGenerationMetrics {
        guard let container = generationContainer else {
            throw MLXRuntimeError.notLoaded(modelID)
        }

        let prepared = try await container.prepare(input: input)
        let events = try await container.generate(input: prepared, parameters: parameters)
        var metrics = MLXGenerationMetrics()
        let started = Date()

        for await event in events {
            if isCancelled {
                break
            }
            switch event {
            case .chunk(let token):
                if !onToken(token) {
                    cancel()
                    break
                }
            case .info(let info):
                metrics.promptTokens = info.promptTokenCount
                metrics.completionTokens = info.generationTokenCount
                metrics.tokensPerSecond = Float(info.tokensPerSecond)
                metrics.totalTimeMs = Int64((info.promptTime + info.generateTime) * 1000)
            case .toolCall:
                break
            }
        }

        if metrics.totalTimeMs == 0 {
            metrics.totalTimeMs = Int64(Date().timeIntervalSince(started) * 1000)
        }
        return metrics
    }

    func embedBatch(
        texts: [String],
        options: UnsafePointer<rac_embeddings_options_t>?
    ) async throws -> ([[Float]], Int32) {
        guard let container = embedderContainer else {
            throw MLXRuntimeError.notLoaded(modelID)
        }

        let normalizeOverride = options?.pointee.normalize ?? RAC_EMBEDDINGS_OPTIONS_DEFAULT.normalize
        let normalize = normalizeOverride != RAC_EMBEDDINGS_NORMALIZE_NONE.rawValue
        let (embeddings, tokenCount) = try await container.perform { context in
            let tokenizer = context.tokenizer
            let padToken = tokenizer.eosTokenId ?? tokenizer.unknownTokenId ?? 0
            let maxTokens = context.model.maxPositionEmbeddings ?? Int(RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS)
            let encoded = texts.map { text in
                Array(tokenizer.encode(text: text, addSpecialTokens: true).prefix(maxTokens))
            }
            let maxLength = encoded.reduce(into: 1) { current, item in
                current = max(current, item.count)
            }
            let padded = stacked(
                encoded.map { item in
                    MLXArray(item + Array(repeating: padToken, count: maxLength - item.count))
                }
            )
            let mask = (padded .!= padToken)
            let tokenTypes = MLXArray.zeros(like: padded)
            let modelOutput = context.model(
                padded,
                positionIds: nil,
                tokenTypeIds: tokenTypes,
                attentionMask: mask
            )
            let result = context.pooling(
                modelOutput,
                normalize: normalize,
                applyLayerNorm: true
            )
            result.eval()
            let tokenCount = encoded.reduce(Int32(0)) { total, item in
                total + Int32(item.count)
            }
            return (result.map { $0.asArray(Float.self) }, tokenCount)
        }

        lock.withLock { state in
            state.embeddingDimension = embeddings.first?.count ?? 0
        }
        return (embeddings, tokenCount)
    }

    func embeddingInfo() -> rac_embeddings_info_t {
        let state = lock.withLock { $0 }
        var info = rac_embeddings_info_t()
        info.is_ready = state.isLoaded ? RAC_TRUE : RAC_FALSE
        info.current_model = nil
        info.dimension = state.embeddingDimension
        info.max_tokens = Int32(RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS)
        return info
    }

    func transcribe(
        audioData: Data,
        options: UnsafePointer<rac_stt_options_t>?
    ) throws -> STTOutput {
        guard let model = sttModel else {
            throw MLXRuntimeError.notLoaded(modelID)
        }
        let audio = try makeSTTAudioArray(audioData: audioData, options: options?.pointee)
        let parameters = sttGenerateParameters(from: options?.pointee)
        return model.generate(audio: audio, generationParameters: parameters)
    }

    func transcribeStream(
        audioData: Data,
        options: UnsafePointer<rac_stt_options_t>?,
        callback: rac_stt_stream_callback_t?,
        userData: UnsafeMutableRawPointer?
    ) async throws {
        guard let model = sttModel else {
            throw MLXRuntimeError.notLoaded(modelID)
        }
        let audio = try makeSTTAudioArray(audioData: audioData, options: options?.pointee)
        let parameters = sttGenerateParameters(from: options?.pointee)
        var finalText = ""
        var emittedFinal = false

        for try await event in model.generateStream(audio: audio, generationParameters: parameters) {
            if isCancelled {
                break
            }
            switch event {
            case .token(let token):
                finalText += token
                token.withCString { callback?($0, RAC_FALSE, userData) }
            case .result(let output):
                finalText = output.text
                emittedFinal = true
                output.text.withCString { callback?($0, RAC_TRUE, userData) }
            case .info:
                break
            }
        }

        if !emittedFinal, !finalText.isEmpty {
            finalText.withCString { callback?($0, RAC_TRUE, userData) }
        }
    }

    func sttInfo() -> rac_stt_info_t {
        let state = lock.withLock { $0 }
        var info = rac_stt_info_t()
        info.is_ready = state.isLoaded ? RAC_TRUE : RAC_FALSE
        info.current_model = nil
        info.supports_streaming = RAC_TRUE
        return info
    }

    func synthesize(
        text: String,
        options: UnsafePointer<rac_tts_options_t>?
    ) async throws -> (samples: [Float], sampleRate: Int, processingTimeMs: Int64) {
        guard let model = ttsModel else {
            throw MLXRuntimeError.notLoaded(modelID)
        }
        let started = Date()
        lock.withLock {
            $0.isCancelled = false
            $0.isSynthesizing = true
        }
        defer {
            lock.withLock { $0.isSynthesizing = false }
            MLXMemoryPolicy.releaseGenerationCachedBuffers(reason: "TTS synthesis")
        }

        let opts = options?.pointee
        let output = try await model.generate(
            text: text,
            voice: string(from: opts?.voice),
            refAudio: nil,
            refText: nil,
            language: string(from: opts?.language),
            generationParameters: model.defaultGenerationParameters
        )
        output.eval()
        let samples = output.asArray(Float.self)
        let elapsedMs = Int64(Date().timeIntervalSince(started) * 1000)
        return (samples, model.sampleRate, elapsedMs)
    }

    func synthesizeStream(
        text: String,
        options: UnsafePointer<rac_tts_options_t>?,
        callback: rac_tts_stream_callback_t?,
        userData: UnsafeMutableRawPointer?
    ) async throws {
        guard let model = ttsModel else {
            throw MLXRuntimeError.notLoaded(modelID)
        }
        lock.withLock {
            $0.isCancelled = false
            $0.isSynthesizing = true
        }
        defer {
            lock.withLock { $0.isSynthesizing = false }
            MLXMemoryPolicy.releaseGenerationCachedBuffers(reason: "TTS stream")
        }

        let opts = options?.pointee
        let stream = model.generateSamplesStream(
            text: text,
            voice: string(from: opts?.voice),
            refAudio: nil,
            refText: nil,
            language: string(from: opts?.language),
            generationParameters: model.defaultGenerationParameters
        )
        for try await chunk in stream {
            if isCancelled {
                break
            }
            let data = floatPCMData(from: chunk)
            data.withUnsafeBytes { rawBuffer in
                callback?(rawBuffer.baseAddress, rawBuffer.count, userData)
            }
        }
    }

    func ttsStop() {
        cancel()
        lock.withLock { $0.isSynthesizing = false }
    }

    func ttsInfo() -> rac_tts_info_t {
        let state = lock.withLock { $0 }
        var info = rac_tts_info_t()
        info.is_ready = state.isLoaded ? RAC_TRUE : RAC_FALSE
        info.is_synthesizing = state.isSynthesizing ? RAC_TRUE : RAC_FALSE
        info.available_voices = nil
        info.num_voices = 0
        return info
    }

    private var isCancelled: Bool {
        lock.withLock { $0.isCancelled }
    }

    // swiftlint:disable:next strict_fileprivate
    fileprivate var isGenerationSession: Bool {
        kind == .llm || kind == .vlm || kind == .stt || kind == .tts
    }

    // swiftlint:disable:next strict_fileprivate
    fileprivate var isLoadedSnapshot: Bool {
        lock.withLock { $0.isLoaded }
    }

    // swiftlint:disable:next strict_fileprivate
    fileprivate var kindDescription: String {
        switch kind {
        case .llm:
            return "LLM"
        case .vlm:
            return "VLM"
        case .embeddings:
            return "embeddings"
        case .stt:
            return "STT"
        case .tts:
            return "TTS"
        }
    }

    // swiftlint:disable:next strict_fileprivate
    fileprivate func releaseResidentGenerationModel() {
        guard isGenerationSession else { return }
        cancel()
        generationContainer = nil
        sttModel = nil
        ttsModel = nil
        lock.withLock {
            $0.isLoaded = false
            $0.isCancelled = true
            $0.isSynthesizing = false
        }
        MLXMemoryPolicy.releaseGenerationCachedBuffers(reason: "evict \(kindDescription)")
    }
}

private func modelDirectoryURL(from modelPath: String) -> URL {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDirectory),
       !isDirectory.boolValue {
        return URL(fileURLWithPath: modelPath).deletingLastPathComponent()
    }
    return URL(fileURLWithPath: modelPath, isDirectory: true)
}

private enum MLXRuntimeError: LocalizedError {
    case simulatorUnsupported
    case notLoaded(String)
    case invalidImage
    case invalidAudioInput
    case unsupportedAudioFormat
    case unsupportedSTTModel([String])
    case allocationFailed

    var errorDescription: String? {
        switch self {
        case .simulatorUnsupported:
            return "MLX requires a physical Apple device or macOS. The iOS Simulator does not provide the Metal GPU family required by MLX."
        case .notLoaded(let modelID):
            return "MLX model is not loaded: \(modelID)"
        case .invalidImage:
            return "Invalid image input for MLX vision inference."
        case .invalidAudioInput:
            return "Invalid audio input for MLX speech inference."
        case .unsupportedAudioFormat:
            return "MLX speech inference currently accepts 16-bit mono PCM audio."
        case .unsupportedSTTModel(let hints):
            return "Unsupported MLX STT model. Supported local loaders: Qwen3-ASR and GLM-ASR. Hints: \(hints.joined(separator: ", "))"
        case .allocationFailed:
            return "MLX runtime failed to allocate output memory."
        }
    }
}

private let mlxRuntimeLogger = SDKLogger(category: "MLX")

private struct MLXModelConfigHints: Decodable {
    let modelType: String?
    let architecture: String?
    let architectures: [String]?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case architecture
        case architectures
    }
}

private func describeMLXError(_ error: Error) -> String {
    let nsError = error as NSError
    let localized = nsError.localizedDescription
    let described = String(describing: error)
    if localized.isEmpty || localized == described {
        return described
    }
    return "\(described): \(localized)"
}

private func recordMLXFailure(_ operation: String, error: Error, modelPath: String? = nil) {
    let reason = describeMLXError(error)
    let detail: String
    if let modelPath, !modelPath.isEmpty {
        detail = "\(operation) failed for \(modelPath): \(reason)"
    } else {
        detail = "\(operation) failed: \(reason)"
    }
    detail.withCString { rac_error_set_details($0) }
    mlxRuntimeLogger.error("\(detail)")
}

private final class SyncResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private func generateParameters(from options: rac_llm_options_t?) -> GenerateParameters {
    guard let options else {
        return GenerateParameters(maxTokens: 1024)
    }
    return GenerateParameters(
        maxTokens: options.max_tokens > 0 ? Int(options.max_tokens) : nil,
        temperature: options.temperature,
        topP: options.top_p,
        topK: Int(options.top_k),
        minP: options.min_p,
        repetitionPenalty: options.repetition_penalty == 1.0 ? nil : options.repetition_penalty,
        presencePenalty: options.presence_penalty == 0.0 ? nil : options.presence_penalty,
        frequencyPenalty: options.frequency_penalty == 0.0 ? nil : options.frequency_penalty,
        seed: options.seed > 0 ? UInt64(options.seed) : nil
    )
}

private func llmAdditionalContext(from options: rac_llm_options_t?) -> [String: any Sendable]? {
    guard options?.disable_thinking == RAC_TRUE else {
        return nil
    }
    return ["enable_thinking": false]
}

private func generateParameters(from options: rac_vlm_options_t?) -> GenerateParameters {
    guard let options else {
        return GenerateParameters(
            maxTokens: 1024,
            temperature: 0.7,
            topP: 0.9,
            topK: 40,
            repetitionPenalty: 1.1,
            repetitionContextSize: 32
        )
    }
    let repetitionPenalty = options.repetition_penalty > 0.0
        ? options.repetition_penalty
        : 1.1
    return GenerateParameters(
        maxTokens: options.max_tokens > 0 ? Int(options.max_tokens) : nil,
        temperature: options.temperature,
        topP: options.top_p,
        topK: Int(options.top_k),
        minP: options.min_p,
        repetitionPenalty: repetitionPenalty == 1.0 ? nil : repetitionPenalty,
        repetitionContextSize: 32,
        seed: options.seed > 0 ? UInt64(options.seed) : nil
    )
}

private func sttGenerateParameters(from options: rac_stt_options_t?) -> STTGenerateParameters {
    let resolved = options ?? RAC_STT_OPTIONS_DEFAULT
    let language = string(from: resolved.language)
    return STTGenerateParameters(language: language)
}

private func string(from pointer: UnsafePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    let value = String(cString: pointer)
    return value.isEmpty ? nil : value
}

private func modelHints(from directory: URL, modelID: String) -> [String] {
    var hints = [modelID, directory.lastPathComponent]
    let configURL = directory.appendingPathComponent("config.json")
    if let data = try? Data(contentsOf: configURL),
       let config = try? JSONDecoder().decode(MLXModelConfigHints.self, from: data) {
        if let modelType = config.modelType {
            hints.append(modelType)
        }
        if let architecture = config.architecture {
            hints.append(architecture)
        }
        hints.append(contentsOf: config.architectures ?? [])
    }
    return hints.map { $0.lowercased() }
}

private func loadSpeechRecognitionModel(from directory: URL, modelID: String) async throws
    -> STTGenerationModel {
    let hints = modelHints(from: directory, modelID: modelID)
    let joinedHints = hints.joined(separator: " ")

    if joinedHints.contains("qwen3") && joinedHints.contains("asr") {
        return try await Qwen3ASRModel.fromModelDirectory(directory)
    }

    if joinedHints.contains("glm") && joinedHints.contains("asr") {
        return try await GLMASRModel.fromModelDirectory(directory)
    }

    throw MLXRuntimeError.unsupportedSTTModel(hints)
}

private func makeSTTAudioArray(
    audioData: Data,
    options: rac_stt_options_t?
) throws -> MLXArray {
    let format = options?.audio_format ?? RAC_STT_OPTIONS_DEFAULT.audio_format
    guard format == RAC_AUDIO_FORMAT_PCM else {
        throw MLXRuntimeError.unsupportedAudioFormat
    }
    guard !audioData.isEmpty, audioData.count.isMultiple(of: MemoryLayout<Int16>.stride) else {
        throw MLXRuntimeError.invalidAudioInput
    }

    let sampleCount = audioData.count / MemoryLayout<Int16>.stride
    var samples: [Float] = []
    samples.reserveCapacity(sampleCount)
    audioData.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
        for index in 0..<sampleCount {
            let low = UInt16(base[index * 2])
            let high = UInt16(base[index * 2 + 1]) << 8
            let sample = Int16(bitPattern: high | low)
            samples.append(Float(sample) / Float(Int16.max))
        }
    }

    guard samples.count == sampleCount else {
        throw MLXRuntimeError.invalidAudioInput
    }
    return MLXArray(samples)
}

private func floatPCMData(from samples: [Float]) -> Data {
    var copy = samples
    return copy.withUnsafeMutableBufferPointer { buffer in
        Data(buffer: UnsafeBufferPointer(buffer))
    }
}

private func copyFloatPCMResult(
    samples: [Float],
    sampleRate: Int,
    processingTimeMs: Int64,
    outResult: UnsafeMutablePointer<rac_tts_result_t>
) -> rac_result_t {
    outResult.pointee = rac_tts_result_t()
    let byteCount = samples.count * MemoryLayout<Float>.stride
    if byteCount > 0 {
        guard let audioData = malloc(byteCount) else {
            return RAC_ERROR_OUT_OF_MEMORY
        }
        samples.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                audioData.copyMemory(from: baseAddress, byteCount: byteCount)
            }
        }
        outResult.pointee.audio_data = audioData
    }
    outResult.pointee.audio_size = byteCount
    outResult.pointee.audio_format = RAC_AUDIO_FORMAT_PCM
    outResult.pointee.sample_rate = Int32(sampleRate)
    if sampleRate > 0 {
        outResult.pointee.duration_ms = Int64(samples.count * 1000 / sampleRate)
    }
    outResult.pointee.processing_time_ms = processingTimeMs
    return RAC_SUCCESS
}

private func imageInput(from image: rac_vlm_image_t) throws -> UserInput.Image {
    switch image.format {
    case RAC_VLM_IMAGE_FORMAT_FILE_PATH:
        guard let filePath = image.file_path else { throw MLXRuntimeError.invalidImage }
        return .url(URL(fileURLWithPath: String(cString: filePath)))
    case RAC_VLM_IMAGE_FORMAT_BASE64:
        guard let base64 = image.base64_data,
              let data = Data(base64Encoded: String(cString: base64)),
              let ciImage = CIImage(data: data) else {
            throw MLXRuntimeError.invalidImage
        }
        return .ciImage(ciImage)
    case RAC_VLM_IMAGE_FORMAT_RGB_PIXELS:
        guard let pixels = image.pixel_data, image.width > 0, image.height > 0 else {
            throw MLXRuntimeError.invalidImage
        }
        let width = Int(image.width)
        let height = Int(image.height)
        let expectedRGBByteCount = width * height * 3
        guard Int(image.data_size) >= expectedRGBByteCount else {
            throw MLXRuntimeError.invalidImage
        }
        let rgb = UnsafeBufferPointer(start: pixels, count: expectedRGBByteCount)
        var rgba = Data(capacity: width * height * 4)
        for pixelIndex in 0..<(width * height) {
            let base = pixelIndex * 3
            rgba.append(rgb[base])
            rgba.append(rgb[base + 1])
            rgba.append(rgb[base + 2])
            rgba.append(255)
        }
        let ciImage = CIImage(
            bitmapData: rgba,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return .ciImage(ciImage)
    default:
        throw MLXRuntimeError.invalidImage
    }
}

private func syncWait<T>(_ work: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
    let semaphore = DispatchSemaphore(value: 0)
    let box = SyncResultBox<T>()
    Task.detached(priority: .userInitiated) {
        do {
            box.result = .success(try await work())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return box.result ?? .failure(MLXRuntimeError.notLoaded("unknown"))
}

private func session(from handle: rac_handle_t?) -> MLXSession? {
    guard let handle else { return nil }
    return Unmanaged<MLXSession>.fromOpaque(handle).takeUnretainedValue()
}

private let mlxCreate: rac_mlx_create_fn = { kind, modelIDPtr, _, outHandle, _ in
    guard let outHandle else { return RAC_ERROR_NULL_POINTER }
    let modelID = modelIDPtr.map { String(cString: $0) } ?? ""
    let sessionKind: MLXSessionKind
    switch kind {
    case RAC_MLX_SESSION_KIND_VLM:
        sessionKind = .vlm
    case RAC_MLX_SESSION_KIND_EMBEDDINGS:
        sessionKind = .embeddings
    case RAC_MLX_SESSION_KIND_STT:
        sessionKind = .stt
    case RAC_MLX_SESSION_KIND_TTS:
        sessionKind = .tts
    default:
        sessionKind = .llm
    }
    let session = MLXSession(kind: sessionKind, modelID: modelID)
    outHandle.pointee = UnsafeMutableRawPointer(Unmanaged.passRetained(session).toOpaque())
    return RAC_SUCCESS
}

private let mlxInitialize: rac_mlx_initialize_fn = { handle, modelPathPtr, _ in
    guard let session = session(from: handle), let modelPathPtr else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let modelPath = String(cString: modelPathPtr)
    switch syncWait({ try await session.load(modelPath: modelPath) }) {
    case .success:
        return RAC_SUCCESS
    case .failure(let error):
        recordMLXFailure("MLX model load", error: error, modelPath: modelPath)
        return RAC_ERROR_MODEL_LOAD_FAILED
    }
}

private let mlxLLMGenerate: rac_mlx_llm_generate_fn = { handle, promptPtr, options, outResult, _ in
    guard let session = session(from: handle), let promptPtr, let outResult else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let prompt = String(cString: promptPtr)
    switch syncWait({ try await session.generate(prompt: prompt, options: options) }) {
    case .success(let output):
        outResult.pointee.text = strdup(output.0)
        outResult.pointee.prompt_tokens = Int32(output.1.promptTokens)
        outResult.pointee.completion_tokens = Int32(output.1.completionTokens)
        outResult.pointee.total_tokens = Int32(output.1.promptTokens + output.1.completionTokens)
        outResult.pointee.total_time_ms = output.1.totalTimeMs
        outResult.pointee.tokens_per_second = output.1.tokensPerSecond
        return outResult.pointee.text == nil ? RAC_ERROR_OUT_OF_MEMORY : RAC_SUCCESS
    case .failure(let error):
        recordMLXFailure("MLX text generation", error: error)
        return RAC_ERROR_GENERATION_FAILED
    }
}

private let mlxLLMGenerateStream: rac_mlx_llm_generate_stream_fn = { handle, promptPtr, options, callback, callbackUserData, _ in
    guard let session = session(from: handle), let promptPtr else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let prompt = String(cString: promptPtr)
    switch syncWait({
        try await session.generateStream(
            prompt: prompt,
            options: options,
            callback: callback,
            userData: callbackUserData
        )
    }) {
    case .success:
        return RAC_SUCCESS
    case .failure(let error):
        recordMLXFailure("MLX streaming text generation", error: error)
        return RAC_ERROR_GENERATION_FAILED
    }
}

private let mlxVLMProcess: rac_mlx_vlm_process_fn = { handle, image, promptPtr, options, outResult, _ in
    guard let session = session(from: handle), let image, let promptPtr, let outResult else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let prompt = String(cString: promptPtr)
    switch syncWait({ try await session.process(image: image, prompt: prompt, options: options) }) {
    case .success(let output):
        outResult.pointee.text = strdup(output.0)
        outResult.pointee.prompt_tokens = Int32(output.1.promptTokens)
        outResult.pointee.completion_tokens = Int32(output.1.completionTokens)
        outResult.pointee.total_tokens = Int32(output.1.promptTokens + output.1.completionTokens)
        outResult.pointee.total_time_ms = output.1.totalTimeMs
        outResult.pointee.tokens_per_second = output.1.tokensPerSecond
        return outResult.pointee.text == nil ? RAC_ERROR_OUT_OF_MEMORY : RAC_SUCCESS
    case .failure(let error):
        recordMLXFailure("MLX vision generation", error: error)
        return RAC_ERROR_GENERATION_FAILED
    }
}

private let mlxVLMProcessStream: rac_mlx_vlm_process_stream_fn = { handle, image, promptPtr, options, callback, callbackUserData, _ in
    guard let session = session(from: handle), let image, let promptPtr else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let prompt = String(cString: promptPtr)
    switch syncWait({
        try await session.processStream(
            image: image,
            prompt: prompt,
            options: options,
            callback: callback,
            userData: callbackUserData
        )
    }) {
    case .success:
        return RAC_SUCCESS
    case .failure(let error):
        recordMLXFailure("MLX streaming vision generation", error: error)
        return RAC_ERROR_GENERATION_FAILED
    }
}

private func fillEmbeddingResult(
    _ vectors: [[Float]],
    tokenCount: Int32,
    outResult: UnsafeMutablePointer<rac_embeddings_result_t>
) -> rac_result_t {
    outResult.pointee = rac_embeddings_result_t()
    guard let dimension = vectors.first?.count else {
        outResult.pointee.num_embeddings = 0
        outResult.pointee.dimension = 0
        outResult.pointee.total_tokens = tokenCount
        return RAC_SUCCESS
    }
    guard dimension > 0, vectors.allSatisfy({ $0.count == dimension }) else {
        return RAC_ERROR_INFERENCE_FAILED
    }

    let vectorCount = vectors.count
    guard let embeddingsRaw = malloc(vectorCount * MemoryLayout<rac_embedding_vector_t>.stride) else {
        return RAC_ERROR_OUT_OF_MEMORY
    }
    let embeddings = embeddingsRaw.bindMemory(to: rac_embedding_vector_t.self, capacity: vectorCount)
    for index in 0..<vectorCount {
        embeddings.advanced(by: index).initialize(to: rac_embedding_vector_t())
    }

    outResult.pointee.embeddings = embeddings
    outResult.pointee.num_embeddings = vectorCount
    outResult.pointee.dimension = dimension
    outResult.pointee.processing_time_ms = 0
    outResult.pointee.total_tokens = tokenCount

    for (index, vector) in vectors.enumerated() {
        guard let dataRaw = malloc(dimension * MemoryLayout<Float>.stride) else {
            rac_embeddings_result_free(outResult)
            return RAC_ERROR_OUT_OF_MEMORY
        }
        let data = dataRaw.bindMemory(to: Float.self, capacity: dimension)
        data.initialize(from: vector, count: dimension)
        embeddings[index].data = data
        embeddings[index].dimension = dimension
    }
    return RAC_SUCCESS
}

private let mlxEmbedBatch: rac_mlx_embed_batch_fn = { handle, texts, numTexts, options, outResult, _ in
    guard let session = session(from: handle), let texts, let outResult else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let count = Int(numTexts)
    var inputTexts: [String] = []
    inputTexts.reserveCapacity(count)
    for index in 0..<count {
        guard let text = texts[index] else { return RAC_ERROR_INVALID_PARAMETER }
        inputTexts.append(String(cString: text))
    }
    switch syncWait({ try await session.embedBatch(texts: inputTexts, options: options) }) {
    case .success(let output):
        return fillEmbeddingResult(output.0, tokenCount: output.1, outResult: outResult)
    case .failure(let error):
        recordMLXFailure("MLX embeddings", error: error)
        return RAC_ERROR_INFERENCE_FAILED
    }
}

private let mlxEmbeddingInfo: rac_mlx_embedding_info_fn = { handle, outInfo, _ in
    guard let session = session(from: handle), let outInfo else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    outInfo.pointee = session.embeddingInfo()
    return RAC_SUCCESS
}

private let mlxSTTTranscribe: rac_mlx_stt_transcribe_fn = { handle, audioData, audioSize, options, outResult, _ in
    guard let session = session(from: handle), let audioData, audioSize > 0, let outResult else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let input = Data(bytes: audioData, count: Int(audioSize))
    let started = Date()
    do {
        let output = try session.transcribe(audioData: input, options: options)
        outResult.pointee = rac_stt_result_t()
        outResult.pointee.text = strdup(output.text)
        if outResult.pointee.text == nil {
            return RAC_ERROR_OUT_OF_MEMORY
        }
        if let language = output.language, !language.isEmpty {
            outResult.pointee.detected_language = strdup(language)
            if outResult.pointee.detected_language == nil {
                rac_stt_result_free(outResult)
                return RAC_ERROR_OUT_OF_MEMORY
            }
        }
        outResult.pointee.confidence = output.text.isEmpty ? 0.0 : RAC_STT_DEFAULT_CONFIDENCE
        let outputTimeMs = Int64(output.totalTime * 1000)
        outResult.pointee.processing_time_ms = outputTimeMs > 0
            ? outputTimeMs
            : Int64(Date().timeIntervalSince(started) * 1000)
        return RAC_SUCCESS
    } catch {
        recordMLXFailure("MLX speech transcription", error: error)
        return RAC_ERROR_INFERENCE_FAILED
    }
}

private let mlxSTTTranscribeStream: rac_mlx_stt_transcribe_stream_fn = { handle, audioData, audioSize, options, callback, callbackUserData, _ in
    guard let session = session(from: handle), let audioData, audioSize > 0 else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let input = Data(bytes: audioData, count: Int(audioSize))
    switch syncWait({
        try await session.transcribeStream(
            audioData: input,
            options: options,
            callback: callback,
            userData: callbackUserData
        )
    }) {
    case .success:
        return RAC_SUCCESS
    case .failure(let error):
        recordMLXFailure("MLX streaming speech transcription", error: error)
        return RAC_ERROR_INFERENCE_FAILED
    }
}

private let mlxSTTInfo: rac_mlx_stt_info_fn = { handle, outInfo, _ in
    guard let session = session(from: handle), let outInfo else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    outInfo.pointee = session.sttInfo()
    return RAC_SUCCESS
}

private let mlxTTSSynthesize: rac_mlx_tts_synthesize_fn = { handle, textPtr, options, outResult, _ in
    guard let session = session(from: handle), let textPtr, let outResult else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let text = String(cString: textPtr)
    switch syncWait({ try await session.synthesize(text: text, options: options) }) {
    case .success(let output):
        return copyFloatPCMResult(
            samples: output.samples,
            sampleRate: output.sampleRate,
            processingTimeMs: output.processingTimeMs,
            outResult: outResult
        )
    case .failure(let error):
        recordMLXFailure("MLX speech synthesis", error: error)
        return RAC_ERROR_INFERENCE_FAILED
    }
}

private let mlxTTSSynthesizeStream: rac_mlx_tts_synthesize_stream_fn = { handle, textPtr, options, callback, callbackUserData, _ in
    guard let session = session(from: handle), let textPtr else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    let text = String(cString: textPtr)
    switch syncWait({
        try await session.synthesizeStream(
            text: text,
            options: options,
            callback: callback,
            userData: callbackUserData
        )
    }) {
    case .success:
        return RAC_SUCCESS
    case .failure(let error):
        recordMLXFailure("MLX streaming speech synthesis", error: error)
        return RAC_ERROR_INFERENCE_FAILED
    }
}

private let mlxTTSStop: rac_mlx_tts_stop_fn = { handle, _ in
    guard let session = session(from: handle) else { return RAC_ERROR_INVALID_PARAMETER }
    session.ttsStop()
    return RAC_SUCCESS
}

private let mlxTTSInfo: rac_mlx_tts_info_fn = { handle, outInfo, _ in
    guard let session = session(from: handle), let outInfo else {
        return RAC_ERROR_INVALID_PARAMETER
    }
    outInfo.pointee = session.ttsInfo()
    return RAC_SUCCESS
}

private let mlxCancel: rac_mlx_cancel_fn = { handle, _ in
    guard let session = session(from: handle) else { return RAC_ERROR_INVALID_PARAMETER }
    session.cancel()
    return RAC_SUCCESS
}

private let mlxCleanup: rac_mlx_cleanup_fn = { handle, _ in
    guard let session = session(from: handle) else { return RAC_ERROR_INVALID_PARAMETER }
    session.cleanup()
    return RAC_SUCCESS
}

private let mlxDestroy: rac_mlx_destroy_fn = { handle, _ in
    guard let handle else { return }
    let unmanaged = Unmanaged<MLXSession>.fromOpaque(handle)
    let session = unmanaged.takeUnretainedValue()
    MLXSessionCoordinator.unregister(session)
    unmanaged.release()
}
