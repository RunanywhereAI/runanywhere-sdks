// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Diffusion (text → image) session over `ra_diffusion_*`.

import Foundation
import CRACommonsCore

public enum DiffusionScheduler: Sendable {
    case `default`, ddim, dpmsolver, euler, eulerAncestral

    var raw: Int32 {
        switch self {
        case .default:         return Int32(RA_DIFFUSION_SCHEDULER_DEFAULT)
        case .ddim:            return Int32(RA_DIFFUSION_SCHEDULER_DDIM)
        case .dpmsolver:       return Int32(RA_DIFFUSION_SCHEDULER_DPMSOLVER)
        case .euler:           return Int32(RA_DIFFUSION_SCHEDULER_EULER)
        case .eulerAncestral:  return Int32(RA_DIFFUSION_SCHEDULER_EULER_ANCESTRAL)
        }
    }
}

public struct DiffusionConfiguration: Sendable {
    public var width: Int
    public var height: Int
    public var inferenceSteps: Int
    public var guidanceScale: Float
    public var seed: Int64
    public var scheduler: DiffusionScheduler
    public var enableSafetyChecker: Bool

    public init(width: Int = 512, height: Int = 512,
                inferenceSteps: Int = 25, guidanceScale: Float = 7.5,
                seed: Int64 = -1, scheduler: DiffusionScheduler = .default,
                enableSafetyChecker: Bool = true) {
        self.width = width; self.height = height
        self.inferenceSteps = inferenceSteps
        self.guidanceScale = guidanceScale
        self.seed = seed; self.scheduler = scheduler
        self.enableSafetyChecker = enableSafetyChecker
    }
}

public struct DiffusionGenerationOptions: Sendable {
    public var negativePrompt: String?
    public var numImages: Int
    public var batchSize: Int

    public init(negativePrompt: String? = nil, numImages: Int = 1, batchSize: Int = 0) {
        self.negativePrompt = negativePrompt
        self.numImages = numImages
        self.batchSize = batchSize
    }
}

public enum DiffusionModelVariant: String, Sendable {
    case sd15, sd2, sdxl, sdxlTurbo, custom
}

public struct DiffusionRequest: Sendable {
    public var prompt: String
    public var configuration: DiffusionConfiguration
    public var options: DiffusionGenerationOptions
    public init(prompt: String,
                configuration: DiffusionConfiguration = .init(),
                options: DiffusionGenerationOptions = .init()) {
        self.prompt = prompt; self.configuration = configuration; self.options = options
    }
}

public struct DiffusionResult: Sendable {
    public let pngData: Data
    public let width: Int
    public let height: Int
    public init(pngData: Data, width: Int, height: Int) {
        self.pngData = pngData; self.width = width; self.height = height
    }
}

public final class DiffusionSession: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let modelId: String
    private let configuration: DiffusionConfiguration

    public init(modelId: String, modelPath: String,
                format: ModelFormat = .coreML,
                configuration: DiffusionConfiguration = .init()) throws {
        self.modelId = modelId
        self.configuration = configuration

        var out: OpaquePointer?
        let status: Int32 = modelId.withCString { idPtr in
            modelPath.withCString { pathPtr in
                var spec = ra_model_spec_t()
                spec.model_id = idPtr
                spec.model_path = pathPtr
                spec.format = ra_model_format_t(format.raw)
                spec.preferred_runtime = ra_runtime_id_t(RA_RUNTIME_COREML)
                var cfg = ra_diffusion_config_t()
                cfg.width = Int32(configuration.width)
                cfg.height = Int32(configuration.height)
                cfg.num_inference_steps = Int32(configuration.inferenceSteps)
                cfg.guidance_scale = configuration.guidanceScale
                cfg.seed = configuration.seed
                cfg.scheduler = ra_diffusion_scheduler_t(configuration.scheduler.raw)
                cfg.enable_safety_checker = configuration.enableSafetyChecker ? 1 : 0
                return ra_diffusion_create(&spec, &cfg, &out)
            }
        }
        guard status == RA_OK, let h = out else {
            throw RunAnywhereError(status: status, context: "ra_diffusion_create")
        }
        self.handle = h
    }

    deinit { if let h = handle { ra_diffusion_destroy(h) } }

    public func generate(prompt: String,
                          options: DiffusionGenerationOptions = .init()) throws -> DiffusionResult {
        guard let h = handle else { throw RunAnywhereError.invalidArgument("session destroyed") }
        var bytesPtr: UnsafeMutablePointer<UInt8>?
        var size: Int32 = 0
        let status = prompt.withCString { p -> Int32 in
            var opts = ra_diffusion_options_t()
            opts.num_images = Int32(options.numImages)
            opts.batch_size = Int32(options.batchSize)
            if let neg = options.negativePrompt {
                return neg.withCString { n in
                    opts.negative_prompt = n
                    return ra_diffusion_generate(h, p, &opts, &bytesPtr, &size)
                }
            }
            return ra_diffusion_generate(h, p, &opts, &bytesPtr, &size)
        }
        guard status == RA_OK, let raw = bytesPtr, size > 0 else {
            throw RunAnywhereError(status: status, context: "ra_diffusion_generate")
        }
        let data = Data(bytes: raw, count: Int(size))
        ra_diffusion_bytes_free(raw)
        return DiffusionResult(pngData: data,
                                width: configuration.width,
                                height: configuration.height)
    }

    public func cancel() {
        if let h = handle { _ = ra_diffusion_cancel(h) }
    }
}

// MARK: - RunAnywhere.* convenience

@MainActor
public extension RunAnywhere {

    static var isDiffusionModelLoaded: Bool {
        !SessionRegistry.currentDiffusionModelId.isEmpty
    }
    static var currentDiffusionModelId: String? {
        SessionRegistry.currentDiffusionModelId.isEmpty ? nil : SessionRegistry.currentDiffusionModelId
    }

    static func loadDiffusionModel(_ modelId: String, modelPath: String,
                                     format: ModelFormat = .coreML,
                                     configuration: DiffusionConfiguration = .init()) throws {
        _ = try DiffusionSession(modelId: modelId, modelPath: modelPath,
                                   format: format, configuration: configuration)
        SessionRegistry.currentDiffusionModelId = modelId
    }

    static func unloadDiffusionModel() { SessionRegistry.currentDiffusionModelId = "" }

    static func generateImage(_ request: DiffusionRequest) async throws -> DiffusionResult {
        guard let info = ModelCatalog.model(id: SessionRegistry.currentDiffusionModelId) else {
            throw RunAnywhereError.backendUnavailable("no diffusion model loaded")
        }
        let session = try DiffusionSession(
            modelId: info.id,
            modelPath: info.localPath ?? "",
            format: info.framework.modelFormat,
            configuration: request.configuration)
        return try session.generate(prompt: request.prompt, options: request.options)
    }

    /// Legacy-shaped convenience. Sample apps call
    /// `RunAnywhere.generateImage(prompt: "...", options: .init(...))`.
    static func generateImage(
        prompt: String,
        options: DiffusionGenerationOptions = .init()
    ) async throws -> DiffusionResult {
        try await generateImage(DiffusionRequest(prompt: prompt, options: options))
    }

    static func cancelImageGeneration() {
        // Best-effort: no per-process diffusion session held in registry.
    }
}
