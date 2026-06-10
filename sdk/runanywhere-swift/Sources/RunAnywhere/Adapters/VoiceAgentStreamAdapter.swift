//
//  VoiceAgentStreamAdapter.swift
//  RunAnywhere
//
//  This file used to carry ~197 LOC of fan-out machinery (per-handle
//  registry, OSAllocatedUnfairLock-guarded continuations, retained-Unmanaged
//  trampoline) that was bit-for-bit identical to `LLMStreamAdapter`
//  except for the native handle / proto event types and the
//  register/unregister C symbols. That machinery was extracted
//  into the generic `HandleStreamAdapter<Handle, Event>`; this file is
//  now a thin specialization that wires the voice-agent-specific symbols.
//
//  Public API (preserved):
//      try await RunAnywhere.initializeVoiceAgentWithLoadedModels()
//      let handle = try await CppBridge.VoiceAgent.shared.getHandle()
//      let adapter = VoiceAgentStreamAdapter(handle: handle)
//      for await event in adapter.stream() { handle(event) }
//
//  Cancellation: standard `for-await break` cancels the underlying
//  AsyncStream which deregisters the C callback via `onTermination`
//  (handled inside `HandleStreamAdapter`).

import CRACommons

/// AsyncStream-based wrapper over the proto-byte voice agent ABI.
///
/// Backed by the generic `HandleStreamAdapter<rac_voice_agent_handle_t, RAVoiceEvent>`.
/// All fan-out, lifecycle, and cancellation semantics live in the
/// generic — this typealias only fixes the type parameters so the
/// public `VoiceAgentStreamAdapter(handle:)` / `.stream()` shape is
/// preserved. Voice events fan out forever (no terminal-event predicate)
/// — consumers exit the stream by `break`-ing out of the `for-await`.
public typealias VoiceAgentStreamAdapter = HandleStreamAdapter<rac_voice_agent_handle_t, RAVoiceEvent>

private enum VoiceAgentStreamProtoABI {
    typealias QuiesceFn = @convention(c) () -> Void

    // `rac_voice_agent_proto_quiesce` is absent from older RACommons
    // binaries, so it is resolved dynamically (dlsym) rather than called
    // directly; nil means the linked binary predates the symbol and
    // teardown skips the quiesce.
    static let quiesce = NativeProtoABI.load("rac_voice_agent_proto_quiesce", as: QuiesceFn.self)
}

public extension HandleStreamAdapter where Handle == rac_voice_agent_handle_t, Event == RAVoiceEvent {

    /// Wrap an existing voice agent handle as an event stream.
    ///
    /// Wires the voice-agent-specific C registration symbol
    /// (`rac_voice_agent_set_proto_callback`, declared in
    /// `rac_voice_event_abi.h`) into the generic fan-out adapter. The
    /// same symbol both installs and clears the callback (NULL clears),
    /// so `register` and `unregister` both call it. Teardown additionally
    /// calls `rac_voice_agent_proto_quiesce` between unset and context
    /// release. There is no terminal event for voice agents — events fan
    /// out until subscribers detach.
    convenience init(handle: rac_voice_agent_handle_t) {
        self.init(
            handle: handle,
            streamKey: "voice-agent",
            register: { handle, cb, ud in rac_voice_agent_set_proto_callback(handle, cb, ud) },
            unregister: { handle in _ = rac_voice_agent_set_proto_callback(handle, nil, nil) },
            quiesce: { VoiceAgentStreamProtoABI.quiesce?() }
        )
    }
}
