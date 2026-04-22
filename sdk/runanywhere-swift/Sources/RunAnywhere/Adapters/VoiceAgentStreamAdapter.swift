//
//  VoiceAgentStreamAdapter.swift
//  RunAnywhere
//
//  GAP 09 Phase 16 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
//
//  Wraps `rac_voice_agent_set_proto_callback` (declared in
//  `rac_voice_event_abi.h`, GAP 09 Phase 15) as an `AsyncStream<RAVoiceEvent>`.
//  RAVoiceEvent is the codegen'd type from `idl/voice_events.proto` via
//  swift-protobuf (GAP 01).
//
//  Public API:
//      let stream = RunAnywhere.voiceAgent.stream()  // AsyncStream<RAVoiceEvent>
//      for await event in stream { handle(event) }
//
//  Cancellation: standard `for-await break` cancels the underlying
//  AsyncStream which deregisters the C callback via `onTermination`.

import Foundation
import SwiftProtobuf

/// AsyncStream-based wrapper over the GAP 09 proto-byte voice agent ABI.
///
/// One `VoiceAgentStreamAdapter` instance owns one C-side callback
/// registration. Multiple concurrent subscribers should each create their
/// own adapter — registrations are per-handle so subscribers fan out at
/// the C++ dispatcher.
public final class VoiceAgentStreamAdapter {

    // MARK: - C callback bridge

    /// `void (*)(uint8_t*, size_t, void*)` matching
    /// `rac_voice_agent_proto_event_callback_fn`.
    private typealias CCallback = @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?
    ) -> Void

    /// Box holds the AsyncStream continuation; passed to C as `user_data`,
    /// dereferenced from the trampoline. Strong-retained while the
    /// callback is registered, released in `onTermination`.
    private final class ContinuationBox {
        let continuation: AsyncStream<RAVoiceEvent>.Continuation
        init(_ c: AsyncStream<RAVoiceEvent>.Continuation) { self.continuation = c }
    }

    private let handle: rac_voice_agent_handle_t

    // MARK: - Init

    /// Wrap an existing voice agent handle as an event stream.
    public init(handle: rac_voice_agent_handle_t) {
        self.handle = handle
    }

    // MARK: - Public API

    /// Start a new subscription. The returned stream emits one
    /// `RAVoiceEvent` per agent event until cancelled or the agent ends.
    ///
    /// Calling `stream()` twice creates two independent registrations.
    public func stream() -> AsyncStream<RAVoiceEvent> {
        AsyncStream { continuation in
            let box = ContinuationBox(continuation)
            let userPtr = Unmanaged.passRetained(box).toOpaque()

            let trampoline: CCallback = { bytesPtr, bytesLen, userData in
                guard let bytesPtr = bytesPtr,
                      let userData = userData else { return }
                let box = Unmanaged<ContinuationBox>.fromOpaque(userData).takeUnretainedValue()

                // Copy bytes off the C buffer (per ABI contract, the buffer
                // is invalidated when this callback returns).
                let data = Data(bytes: bytesPtr, count: bytesLen)
                if let event = try? RAVoiceEvent(serializedBytes: data) {
                    box.continuation.yield(event)
                }
            }

            let result = rac_voice_agent_set_proto_callback(handle, trampoline, userPtr)
            if result != RAC_SUCCESS {
                Unmanaged<ContinuationBox>.fromOpaque(userPtr).release()
                continuation.finish()
                return
            }

            continuation.onTermination = { @Sendable [handle] _ in
                rac_voice_agent_set_proto_callback(handle, nil, nil)
                Unmanaged<ContinuationBox>.fromOpaque(userPtr).release()
            }
        }
    }
}
