// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

/// A live VoiceAgent session. Events stream via `run()`. The underlying C
/// pipeline is created lazily on first `run()` call and torn down on
/// deinit.
public final class VoiceSession: @unchecked Sendable {

    public struct Handle {
        internal let pipelinePointer: OpaquePointer
    }

    public enum Event: Sendable {
        case userSaid(text: String, isFinal: Bool)
        case assistantToken(text: String, kind: TokenKind, isFinal: Bool)
        case audio(pcm: Data, sampleRateHz: Int)
        case interrupted(reason: String)
        case stateChange(previous: PipelineState, current: PipelineState)
        case metrics(latencyMilliseconds: Double)
        case error(Error)
    }

    public enum TokenKind: Sendable {
        case answer
        case thought
        case toolCall
    }

    public enum PipelineState: Sendable {
        case idle, listening, thinking, speaking, stopped
    }

    internal static func create(from config: SolutionConfig) async throws
        -> VoiceSession {
        // TODO(phase-1): bridge to core/abi/ra_pipeline.h via generated
        // proto3 SolutionConfig bytes. For now return a handle-less
        // session so the public API compiles and the tests exercise the
        // adapter surface.
        return VoiceSession(handle: nil, config: config)
    }

    private init(handle: Handle?, config: SolutionConfig) {
        self.handle = handle
        self.config = config
    }

    private let handle: Handle?
    private let config: SolutionConfig

    /// Streams the event sequence. Cancel by dropping the iterator.
    public func run() -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) { [self] in
                defer { continuation.finish() }
                guard handle != nil else {
                    // Without a bridged C pipeline we cannot produce real
                    // events. Emit an error so consumers can surface it.
                    continuation.finish(throwing:
                        RunAnywhereError.backendUnavailable(
                            "RunAnywhereV2 C core not linked in this build"))
                    return
                }
                // TODO(phase-1): decode proto3 VoiceEvent bytes from the C
                // callback into VoiceSession.Event and yield.
            }
        }
    }

    public func stop() {
        // TODO(phase-1): ra_pipeline_cancel(handle)
    }

    deinit {
        // TODO(phase-1): ra_pipeline_destroy(handle)
    }
}

public enum RunAnywhereError: Error, CustomStringConvertible, Sendable {
    case backendUnavailable(String)
    case modelNotFound(String)
    case cancelled
    case abiMismatch(expected: UInt32, got: UInt32)
    case internalError(String)

    public var description: String {
        switch self {
        case .backendUnavailable(let m): return "backend unavailable: \(m)"
        case .modelNotFound(let m):      return "model not found: \(m)"
        case .cancelled:                 return "cancelled"
        case .abiMismatch(let e, let g): return "ABI mismatch: expected \(e), got \(g)"
        case .internalError(let m):      return "internal: \(m)"
        }
    }
}
