// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// Text-to-speech session. Synchronous synthesize call — returns PCM
/// samples. The new ra_tts_synthesize ABI is buffer-based, not streaming;
/// wrap in an AsyncStream yourself if you want chunked playback.
///
///     let session = try TTSSession(modelId: "kokoro", modelPath: path)
///     let (pcm, sr) = try session.synthesize("Hello world")
///     // pcm is [Float], sr is the model's output sample rate in Hz
public final class TTSSession: @unchecked Sendable {

    private var handle: OpaquePointer?

    private let modelId: String
    private let modelPath: String

    public init(modelId: String, modelPath: String,
                format: ModelFormat = .onnx,
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
                return ra_tts_create(&spec, &cfg, &out)
            }
        }
        guard status == Int32(RA_OK), let h = out else {
            throw RunAnywhereError.mapStatus(status, message: "ra_tts_create")
        }
        self.handle = h
    }

    deinit {
        if let h = handle { ra_tts_destroy(h) }
    }

    /// Synthesize `text` into PCM. `initialCapacity` is the starting buffer
    /// size in samples; the call retries with a larger buffer if the engine
    /// needs more space. Returns PCM and the sample rate in Hz.
    public func synthesize(_ text: String, initialCapacity: Int = 240_000)
        throws -> (pcm: [Float], sampleRateHz: Int)
    {
        guard let h = handle else {
            throw RunAnywhereError.internalError("TTS session not initialized")
        }

        var capacity = initialCapacity
        while capacity <= 4_000_000 {  // ~4M samples — 83s @ 48kHz
            var buffer = [Float](repeating: 0, count: capacity)
            var written: Int32 = 0
            var sampleRate: Int32 = 0

            let status = text.withCString { textPtr in
                buffer.withUnsafeMutableBufferPointer { bufPtr in
                    ra_tts_synthesize(h, textPtr, bufPtr.baseAddress,
                                       Int32(capacity), &written, &sampleRate)
                }
            }

            switch status {
            case Int32(RA_OK):
                return (Array(buffer[0..<Int(written)]), Int(sampleRate))
            case Int32(RA_ERR_OUT_OF_MEMORY):
                capacity *= 2
                continue
            default:
                throw RunAnywhereError.mapStatus(status, message: "ra_tts_synthesize")
            }
        }
        throw RunAnywhereError.internalError(
            "TTS output exceeds 4M samples — refuse to grow further")
    }

    public func cancel() {
        if let h = handle { _ = ra_tts_cancel(h) }
    }
}
