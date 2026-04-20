// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// Voice activity detection session. Feed PCM via `feedAudio`, receive
/// voice_start / voice_end / barge_in / silence events through `events`.
///
///     let session = try VADSession(modelId: "silero-v5", modelPath: path)
///     Task {
///         for try await ev in session.events {
///             print("VAD \(ev.kind) @ \(ev.frameOffsetUs)us energy=\(ev.energy)")
///         }
///     }
///     session.feedAudio(samples: pcm, sampleRateHz: 16000)
public final class VADSession: @unchecked Sendable {

    public struct Event: Sendable {
        public let kind: Kind
        public let frameOffsetUs: Int64
        public let energy: Float

        public enum Kind: Sendable {
            case unknown, voiceStart, voiceEnd, bargeIn, silence

            internal init(raw: Int32) {
                switch raw {
                case 1:  self = .voiceStart
                case 2:  self = .voiceEnd
                case 3:  self = .bargeIn
                case 4:  self = .silence
                default: self = .unknown
                }
            }
        }
    }

    private var handle: OpaquePointer?
    private var continuation: AsyncThrowingStream<Event, Error>.Continuation?

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
                return ra_vad_create(&spec, &cfg, &out)
            }
        }
        guard status == Int32(RA_OK), let h = out else {
            throw RunAnywhereError.mapStatus(status, message: "ra_vad_create")
        }
        self.handle = h
    }

    deinit {
        if let h = handle { ra_vad_destroy(h) }
    }

    public lazy var events: AsyncThrowingStream<Event, Error> = {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            guard let handle = self.handle else {
                continuation.finish(throwing:
                    RunAnywhereError.internalError("session not initialized"))
                return
            }
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            let status = ra_vad_set_callback(handle, { eventPtr, userData in
                guard let userData, let eventPtr else { return }
                let s = Unmanaged<VADSession>.fromOpaque(userData).takeUnretainedValue()
                let e = eventPtr.pointee
                s.continuation?.yield(Event(
                    kind: Event.Kind(raw: e.type),
                    frameOffsetUs: e.frame_offset_us,
                    energy: e.energy))
            }, ctx)
            if status != Int32(RA_OK) {
                continuation.finish(throwing:
                    RunAnywhereError.mapStatus(status, message: "ra_vad_set_callback"))
            }
        }
    }()

    public func feedAudio(samples: [Float], sampleRateHz: Int) throws {
        guard let h = handle else { return }
        let status = samples.withUnsafeBufferPointer { buf in
            ra_vad_feed_audio(h, buf.baseAddress, Int32(samples.count),
                               Int32(sampleRateHz))
        }
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status, message: "ra_vad_feed_audio")
        }
    }

    public func finish() {
        continuation?.finish()
    }
}
