//
//  LLMStreamAdapter.swift
//  RunAnywhere
//
//  v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
//
//  Wraps `rac_llm_set_stream_proto_callback` (declared in
//  `rac_llm_stream.h`) as an `AsyncStream<RALLMStreamEvent>`.
//  RALLMStreamEvent is the codegen'd type from `idl/llm_service.proto`
//  via swift-protobuf (GAP 01).
//
//  This is the unified LLM streaming path — the per-SDK hand-rolled
//  AsyncThrowingStream<String, Error> shim in RunAnywhere+TextGeneration.swift
//  was DELETED in the same change; the public `generateStream` on
//  `RunAnywhere` now pulls from this adapter.
//
//  Public API:
//      let handle = try await CppBridge.LLM.shared.getHandle()
//      let adapter = LLMStreamAdapter(handle: handle)
//      for await event in adapter.stream() {
//          if event.isFinal { break }
//          print(event.token, terminator: "")
//      }
//
//  Cancellation: `break` out of the `for-await` loop deregisters the C
//  callback via `onTermination`.

import CRACommons
import Foundation
import SwiftProtobuf

/// AsyncStream-based wrapper over the Phase G-2 proto-byte LLM stream ABI.
///
/// One `LLMStreamAdapter` instance owns one C-side callback registration
/// per `stream()` call. The C ABI exposes exactly one callback slot per
/// handle; callers needing multiple concurrent collectors on the same
/// handle should build their own fan-out on top.
public final class LLMStreamAdapter {

    // MARK: - C callback bridge

    /// `void (*)(uint8_t*, size_t, void*)` matching
    /// `rac_llm_stream_proto_callback_fn`.
    private typealias CCallback = @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?
    ) -> Void

    /// Box holds the AsyncStream continuation; passed to C as `user_data`,
    /// dereferenced from the trampoline. Strong-retained while the
    /// callback is registered, released in `onTermination`.
    private final class ContinuationBox {
        let continuation: AsyncStream<RALLMStreamEvent>.Continuation
        init(_ c: AsyncStream<RALLMStreamEvent>.Continuation) { self.continuation = c }
    }

    private let handle: rac_handle_t

    // MARK: - Init

    /// Wrap an existing LLM component handle as an event stream.
    public init(handle: rac_handle_t) {
        self.handle = handle
    }

    // MARK: - Public API

    /// Start a new subscription. The returned stream emits one
    /// `RALLMStreamEvent` per generated token plus a terminal event
    /// (`isFinal == true`).
    public func stream() -> AsyncStream<RALLMStreamEvent> {
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
                if let event = try? RALLMStreamEvent(serializedBytes: data) {
                    box.continuation.yield(event)
                    if event.isFinal {
                        box.continuation.finish()
                    }
                }
            }

            let result = rac_llm_set_stream_proto_callback(handle, trampoline, userPtr)
            if result != RAC_SUCCESS {
                Unmanaged<ContinuationBox>.fromOpaque(userPtr).release()
                continuation.finish()
                return
            }

            continuation.onTermination = { @Sendable [handle] _ in
                _ = rac_llm_unset_stream_proto_callback(handle)
                Unmanaged<ContinuationBox>.fromOpaque(userPtr).release()
            }
        }
    }
}
