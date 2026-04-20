// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// Text embedding session — maps a string to a fixed-dimension vector.
///
///     let session = try EmbedSession(modelId: "bge-small", modelPath: path)
///     let vec = try session.embed("hello world")  // [Float] of length .dims
public final class EmbedSession: @unchecked Sendable {

    private var handle: OpaquePointer?
    public let dims: Int

    private let modelId: String
    private let modelPath: String

    public init(modelId: String, modelPath: String,
                format: ModelFormat = .gguf,
                config: LLMSession.Config = .init()) throws {
        self.modelId = modelId
        self.modelPath = modelPath

        var out: OpaquePointer?
        let status: Int32 = modelId.withCString { idPtr in
            modelPath.withCString { pathPtr in
                var spec = ra_model_spec_t()
                spec.model_id = idPtr
                spec.model_path = pathPtr
                spec.format = ra_model_format_t(format.raw)
                spec.preferred_runtime = ra_runtime_id_t(RA_RUNTIME_SELF_CONTAINED)
                var cfg = ra_session_config_t()
                cfg.context_size = Int32(config.contextSize)
                cfg.n_gpu_layers = Int32(config.numGpuLayers)
                cfg.n_threads = Int32(config.numThreads)
                cfg.use_mmap = config.useMmap ? 1 : 0
                cfg.use_mlock = config.useMlock ? 1 : 0
                return ra_embed_create(&spec, &cfg, &out)
            }
        }
        guard status == Int32(RA_OK), let h = out else {
            throw RunAnywhereError.mapStatus(status, message: "ra_embed_create")
        }
        self.handle = h
        self.dims = Int(ra_embed_dims(h))
    }

    deinit {
        if let h = handle { ra_embed_destroy(h) }
    }

    public func embed(_ text: String) throws -> [Float] {
        guard let h = handle else {
            throw RunAnywhereError.internalError("embed session not initialized")
        }
        var vec = [Float](repeating: 0, count: dims)
        let status = text.withCString { textPtr in
            vec.withUnsafeMutableBufferPointer { buf in
                ra_embed_text(h, textPtr, buf.baseAddress, Int32(dims))
            }
        }
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status, message: "ra_embed_text")
        }
        return vec
    }
}
