// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Vision-language model session — image + text → text. Wraps the
// `ra_vlm_*` C ABI dispatch.

import Foundation
import CRACommonsCore

/// Image input to a VLM session.
public struct VLMImage: Sendable {
    public enum Format: Sendable { case rgb, rgba, bgr, bgra }

    public let bytes: Data
    public let width: Int
    public let height: Int
    public let format: Format

    public init(bytes: Data, width: Int, height: Int, format: Format = .rgba) {
        self.bytes = bytes; self.width = width; self.height = height; self.format = format
    }

    fileprivate var raFormat: ra_vlm_image_format_t {
        switch format {
        case .rgb:  return ra_vlm_image_format_t(RA_VLM_IMAGE_FORMAT_RGB)
        case .rgba: return ra_vlm_image_format_t(RA_VLM_IMAGE_FORMAT_RGBA)
        case .bgr:  return ra_vlm_image_format_t(RA_VLM_IMAGE_FORMAT_BGR)
        case .bgra: return ra_vlm_image_format_t(RA_VLM_IMAGE_FORMAT_BGRA)
        }
    }
}

public struct VLMGenerationOptions: Sendable {
    public var maxTokens: Int
    public var temperature: Float
    public var topP: Float
    public var topK: Int
    public var systemPrompt: String?

    public init(maxTokens: Int = 256, temperature: Float = 0.7,
                topP: Float = 1.0, topK: Int = 40,
                systemPrompt: String? = nil) {
        self.maxTokens = maxTokens; self.temperature = temperature
        self.topP = topP; self.topK = topK; self.systemPrompt = systemPrompt
    }
}

public final class VLMSession: @unchecked Sendable {

    public struct Token: Sendable {
        public let text: String
        public let isFinal: Bool
    }

    private var handle: OpaquePointer?
    private let modelId: String

    public init(modelId: String, modelPath: String,
                format: ModelFormat = .gguf) throws {
        self.modelId = modelId
        var out: OpaquePointer?
        let status: Int32 = modelId.withCString { idPtr in
            modelPath.withCString { pathPtr in
                var spec = ra_model_spec_t()
                spec.model_id = idPtr
                spec.model_path = pathPtr
                spec.format = ra_model_format_t(format.raw)
                spec.preferred_runtime = ra_runtime_id_t(RA_RUNTIME_SELF_CONTAINED)
                var cfg = ra_session_config_t()
                return ra_vlm_create(&spec, &cfg, &out)
            }
        }
        guard status == RA_OK, let h = out else {
            throw RunAnywhereError(status: status, context: "ra_vlm_create")
        }
        self.handle = h
    }

    deinit { if let h = handle { ra_vlm_destroy(h) } }

    /// One-shot batch inference. Returns the full generated text.
    public func process(image: VLMImage, prompt: String,
                         options: VLMGenerationOptions = .init()) throws -> String {
        guard let h = handle else { throw RunAnywhereError.invalidArgument("session destroyed") }
        var outText: UnsafeMutablePointer<CChar>?
        let status = image.bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
            var img = ra_vlm_image_t()
            img.data = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
            img.width = Int32(image.width)
            img.height = Int32(image.height)
            img.row_stride = 0
            img.format = image.raFormat
            var opts = ra_vlm_options_t()
            opts.max_tokens = Int32(options.maxTokens)
            opts.temperature = options.temperature
            opts.top_p = options.topP
            opts.top_k = Int32(options.topK)
            opts.stream = 0
            return prompt.withCString { p in
                if let sys = options.systemPrompt {
                    return sys.withCString { s in
                        opts.system_prompt = s
                        return ra_vlm_process(h, &img, p, &opts, &outText)
                    }
                }
                return ra_vlm_process(h, &img, p, &opts, &outText)
            }
        }
        guard status == RA_OK, let raw = outText else {
            throw RunAnywhereError(status: status, context: "ra_vlm_process")
        }
        let result = String(cString: raw)
        ra_vlm_string_free(outText)
        return result
    }

    /// Streaming inference. Yields tokens as they're produced.
    public func processStream(image: VLMImage, prompt: String,
                                options: VLMGenerationOptions = .init())
        -> AsyncThrowingStream<Token, Error>
    {
        AsyncThrowingStream { continuation in
            guard let h = self.handle else {
                continuation.finish(throwing: RunAnywhereError.invalidArgument("session destroyed"))
                return
            }
            // Heap-allocated context bridges the C callback back into the
            // Swift continuation. Released on stream finish.
            final class Ctx { let cont: AsyncThrowingStream<Token, Error>.Continuation
                init(_ c: AsyncThrowingStream<Token, Error>.Continuation) { cont = c } }
            let ctx = Unmanaged.passRetained(Ctx(continuation))

            let onToken: ra_token_callback_t = { tokenPtr, userData in
                guard let user = userData,
                      let ptr = tokenPtr?.pointee.text else { return }
                let ctx = Unmanaged<Ctx>.fromOpaque(user).takeUnretainedValue()
                let text = String(cString: ptr)
                let isFinal = tokenPtr!.pointee.is_final != 0
                ctx.cont.yield(Token(text: text, isFinal: isFinal))
                if isFinal { ctx.cont.finish() }
            }
            let onError: ra_error_callback_t = { code, msg, userData in
                guard let user = userData else { return }
                let ctx = Unmanaged<Ctx>.fromOpaque(user).takeUnretainedValue()
                let m = msg.flatMap { String(cString: $0) } ?? "vlm error"
                ctx.cont.finish(throwing: RunAnywhereError(status: code, context: m))
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let status = image.bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
                    var img = ra_vlm_image_t()
                    img.data = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    img.width = Int32(image.width)
                    img.height = Int32(image.height)
                    img.row_stride = 0
                    img.format = image.raFormat
                    var opts = ra_vlm_options_t()
                    opts.max_tokens = Int32(options.maxTokens)
                    opts.temperature = options.temperature
                    opts.top_p = options.topP
                    opts.top_k = Int32(options.topK)
                    opts.stream = 1
                    return prompt.withCString { p in
                        ra_vlm_process_stream(h, &img, p, &opts, onToken, onError, ctx.toOpaque())
                    }
                }
                if status != RA_OK {
                    continuation.finish(throwing: RunAnywhereError(status: status, context: "ra_vlm_process_stream"))
                }
                ctx.release()
            }
        }
    }

    public func cancel() {
        if let h = handle { _ = ra_vlm_cancel(h) }
    }
}

// MARK: - RunAnywhere.* convenience

@MainActor
public extension RunAnywhere {

    static var isVLMModelLoaded: Bool { SessionRegistry.currentVLMModelId.isEmpty == false }
    static var currentVLMModelId: String? {
        SessionRegistry.currentVLMModelId.isEmpty ? nil : SessionRegistry.currentVLMModelId
    }

    static func loadVLMModel(_ modelId: String, modelPath: String,
                              format: ModelFormat = .gguf) throws {
        _ = try VLMSession(modelId: modelId, modelPath: modelPath, format: format)
        SessionRegistry.currentVLMModelId = modelId
    }

    static func unloadVLMModel() {
        SessionRegistry.currentVLMModelId = ""
    }

    static func processImage(_ image: VLMImage, prompt: String,
                              options: VLMGenerationOptions = .init()) async throws -> String {
        guard let info = ModelCatalog.model(id: SessionRegistry.currentVLMModelId) else {
            throw RunAnywhereError.backendUnavailable("no VLM loaded")
        }
        let session = try VLMSession(
            modelId: info.id,
            modelPath: info.localPath ?? "",
            format: info.framework.modelFormat)
        return try session.process(image: image, prompt: prompt, options: options)
    }

    static func processImageStream(_ image: VLMImage, prompt: String,
                                     options: VLMGenerationOptions = .init())
        -> AsyncThrowingStream<VLMSession.Token, Error>
    {
        guard let info = ModelCatalog.model(id: SessionRegistry.currentVLMModelId) else {
            return AsyncThrowingStream { $0.finish(throwing: RunAnywhereError.backendUnavailable("no VLM loaded")) }
        }
        do {
            let session = try VLMSession(
                modelId: info.id,
                modelPath: info.localPath ?? "",
                format: info.framework.modelFormat)
            return session.processStream(image: image, prompt: prompt, options: options)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    static func cancelVLMGeneration() {
        // Best-effort: no per-process VLM session held in registry currently.
    }

    /// Convenience that decodes `imageData` (raw RGBA bytes) and dispatches.
    static func generateVision(imageData: Data, width: Int, height: Int,
                                prompt: String,
                                options: VLMGenerationOptions = .init()) async throws -> String {
        try await processImage(
            VLMImage(bytes: imageData, width: width, height: height),
            prompt: prompt, options: options)
    }
}
