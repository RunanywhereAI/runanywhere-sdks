// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// Streaming speech-to-text session. Feed PCM via `feedAudio`, receive
/// transcript chunks through the `transcripts` stream. Partial chunks
/// arrive as they're detected; final chunks follow a `flush()` call.
///
///     let session = try STTSession(modelId: "whisper-base", modelPath: path)
///     Task {
///         for try await chunk in session.transcripts {
///             print(chunk.text, terminator: chunk.isPartial ? "" : "\n")
///         }
///     }
///     session.feedAudio(samples: pcm, sampleRateHz: 16000)
///     session.flush()
public final class STTSession: @unchecked Sendable {

    public struct Chunk: Sendable {
        public let text: String
        public let isPartial: Bool
        public let confidence: Float
        public let audioStartUs: Int64
        public let audioEndUs: Int64
    }

    private var handle: OpaquePointer?
    private var continuation: AsyncThrowingStream<Chunk, Error>.Continuation?

    private let modelId: String
    private let modelPath: String

    public init(modelId: String, modelPath: String,
                format: ModelFormat = .whisperKit,
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
                return ra_stt_create(&spec, &cfg, &out)
            }
        }
        guard status == Int32(RA_OK), let h = out else {
            throw RunAnywhereError.mapStatus(status, message: "ra_stt_create")
        }
        self.handle = h
    }

    deinit {
        if let h = handle { ra_stt_destroy(h) }
    }

    public lazy var transcripts: AsyncThrowingStream<Chunk, Error> = {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            guard let handle = self.handle else {
                continuation.finish(throwing:
                    RunAnywhereError.internalError("session not initialized"))
                return
            }
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            let status = ra_stt_set_callback(handle, { chunkPtr, userData in
                guard let userData, let chunkPtr else { return }
                let s = Unmanaged<STTSession>.fromOpaque(userData).takeUnretainedValue()
                let c = chunkPtr.pointee
                s.continuation?.yield(Chunk(
                    text: c.text.map { String(cString: $0) } ?? "",
                    isPartial: c.is_partial != 0,
                    confidence: c.confidence,
                    audioStartUs: c.audio_start_us,
                    audioEndUs: c.audio_end_us))
            }, ctx)
            if status != Int32(RA_OK) {
                continuation.finish(throwing:
                    RunAnywhereError.mapStatus(status, message: "ra_stt_set_callback"))
            }
        }
    }()

    public func feedAudio(samples: [Float], sampleRateHz: Int) throws {
        guard let h = handle else { return }
        let status = samples.withUnsafeBufferPointer { buf in
            ra_stt_feed_audio(h, buf.baseAddress, Int32(samples.count),
                               Int32(sampleRateHz))
        }
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status, message: "ra_stt_feed_audio")
        }
    }

    /// Signals end of utterance — pending partial chunks flush as finals.
    public func flush() throws {
        guard let h = handle else { return }
        let status = ra_stt_flush(h)
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status, message: "ra_stt_flush")
        }
    }

    public func finish() {
        continuation?.finish()
    }
}

public enum ModelFormat: Sendable {
    case unknown, gguf, onnx, coreml, mlxSafetensors, executorchPte,
         whisperKit, openvinoIr

    var raw: Int32 {
        switch self {
        case .unknown:         return Int32(RA_FORMAT_UNKNOWN)
        case .gguf:            return Int32(RA_FORMAT_GGUF)
        case .onnx:            return Int32(RA_FORMAT_ONNX)
        case .coreml:          return Int32(RA_FORMAT_COREML)
        case .mlxSafetensors:  return Int32(RA_FORMAT_MLX_SAFETENSORS)
        case .executorchPte:   return Int32(RA_FORMAT_EXECUTORCH_PTE)
        case .whisperKit:      return Int32(RA_FORMAT_WHISPERKIT)
        case .openvinoIr:      return Int32(RA_FORMAT_OPENVINO_IR)
        }
    }
}
