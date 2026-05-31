//
//  LLMStreamAdapter.swift
//  RunAnywhere
//
//  Swift simplification Phase 1 — see
//  gaps/gaps/simplification/swift-bridge-duplication.md §1 Pattern C.
//
//  This file used to carry ~221 LOC of fan-out machinery (per-handle
//  registry, OSAllocatedUnfairLock-guarded continuations, retained-Unmanaged
//  trampoline) that was bit-for-bit identical to `VoiceAgentStreamAdapter`
//  except for the native handle / proto event types and the
//  register/unregister C symbols. Phase 1 P1-T6 extracted that machinery
//  into the generic `HandleStreamAdapter<Handle, Event>`; this file is
//  now a thin specialization that wires the LLM-specific symbols and
//  the LLM `isFinal` terminal-event predicate.
//
//  Public API (preserved):
//      let handle = try await CppBridge.LLM.shared.getHandle()
//      let adapter = LLMStreamAdapter(handle: handle)
//      for await event in adapter.stream() {
//          if event.isFinal { break }
//          print(event.token, terminator: "")
//      }
//
//  Cancellation: `break` out of the `for-await` loop deregisters the C
//  callback via `onTermination` (handled inside `HandleStreamAdapter`).

import CRACommons

/// AsyncStream-based wrapper over the proto-byte LLM stream ABI.
///
/// Backed by the generic `HandleStreamAdapter<rac_handle_t, RALLMStreamEvent>`.
/// All fan-out, lifecycle, and cancellation semantics live in the
/// generic — this typealias only fixes the type parameters so the
/// public `LLMStreamAdapter(handle:)` / `.stream()` shape is preserved.
public typealias LLMStreamAdapter = HandleStreamAdapter<rac_handle_t, RALLMStreamEvent>

private enum LLMStreamProtoABI {
    typealias QuiesceFn = @convention(c) () -> Void

    // `rac_llm_proto_quiesce` is absent from older RACommons binaries, so it
    // is resolved dynamically (dlsym) rather than called directly; nil means
    // the linked binary predates the symbol and teardown skips the quiesce.
    static let quiesce = NativeProtoABI.load("rac_llm_proto_quiesce", as: QuiesceFn.self)
}

public extension HandleStreamAdapter where Handle == rac_handle_t, Event == RALLMStreamEvent {

    /// Wrap an existing LLM component handle as an event stream.
    ///
    /// Wires the LLM-specific C registration symbols
    /// (`rac_llm_set_stream_proto_callback` /
    /// `rac_llm_unset_stream_proto_callback`), the teardown quiesce symbol
    /// (`rac_llm_proto_quiesce`), and the LLM terminal-event predicate
    /// (`event.isFinal`) into the generic fan-out adapter.
    convenience init(handle: rac_handle_t) {
        self.init(
            handle: handle,
            streamKey: "llm",
            register: { handle, cb, ud in rac_llm_set_stream_proto_callback(handle, cb, ud) },
            unregister: { handle in _ = rac_llm_unset_stream_proto_callback(handle) },
            quiesce: { LLMStreamProtoABI.quiesce?() },
            isTerminalEvent: { $0.isFinal }
        )
    }
}
