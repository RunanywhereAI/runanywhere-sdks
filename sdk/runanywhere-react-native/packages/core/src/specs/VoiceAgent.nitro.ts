/**
 * VoiceAgent Nitrogen Spec
 *
 * Closes the RN half of GAP 09 #6 (v3-readiness Phase A3). The existing
 * VoiceAgentStreamAdapter.ts imports
 * `'../generated/NitroVoiceAgentSpec'` as `NitroVoiceAgent` and calls
 * `NitroVoiceAgent.subscribeProtoEvents(handle, onBytes, onDone, onError)`.
 * Before this file, that import resolved nowhere and the adapter did
 * not compile.
 *
 * The HybridObject has ONE method: `subscribeProtoEvents`, which wires
 * `rac_voice_agent_set_proto_callback` (commons C ABI) through the
 * Nitro bridge into the JS runtime. Cancellation goes back through the
 * returned unsubscribe function.
 *
 * Matches the Kotlin `VoiceAgentStreamAdapter` pattern (JNI-backed
 * nativeRegisterCallback) and the Dart `RacNative` binding
 * (`rac_voice_agent_set_proto_callback`).
 */
import type { HybridObject } from 'react-native-nitro-modules';

/** Callback fired once per serialized VoiceEvent proto message.
 *  `Uint8Array` is the idiomatic wire-bytes type in TS — ts-proto's
 *  `VoiceEvent.decode(bytes)` accepts it directly without a copy.
 *  The Nitro C++ side heap-copies the proto arena bytes before
 *  dispatch, so holding onto the array past the callback is safe. */
export type OnProtoBytes = (bytes: Uint8Array) => void;

/** Callback fired when the agent's event stream terminates normally. */
export type OnStreamDone = () => void;

/** Callback fired when the transport encounters a non-recoverable error. */
export type OnStreamError = (message: string) => void;

/**
 * Unsubscribe function returned by `subscribeProtoEvents`. Calling it
 * clears the C-side callback via `rac_voice_agent_set_proto_callback(handle, NULL, NULL)`.
 */
export type UnsubscribeFn = () => void;

/**
 * VoiceAgent streaming surface for React Native.
 *
 * One instance is created per handle; each `subscribeProtoEvents` call
 * creates an independent registration. **ABI limitation**: the underlying
 * `rac_voice_agent_set_proto_callback` keeps exactly one callback slot
 * per voice agent handle, so multiple concurrent subscribers on the
 * SAME handle will replace each other. True fan-out requires an ABI
 * extension (tracked separately; not in v2 scope).
 */
export interface VoiceAgent
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  /**
   * Register a proto-byte callback on a voice agent handle.
   *
   * @param handle  The voice agent handle returned by
   *                `RunAnywhereCore.voiceAgentCreate(...)`, reinterpreted
   *                as a JS number (the C++ side casts back to
   *                `rac_voice_agent_handle_t`).
   * @param onBytes Fires once per `runanywhere.v1.VoiceEvent` with the
   *                serialized proto bytes. The ArrayBuffer is copied off
   *                the C arena before being handed to JS — the buffer
   *                is safe to retain past the callback.
   * @param onDone  Fires when the agent reaches its terminal state
   *                (stopped). Called at most once.
   * @param onError Fires on transport-level errors (e.g. invalid handle,
   *                Protobuf not linked). Called at most once. Message
   *                includes the underlying `rac_result_t` code.
   *
   * @returns A zero-argument function that, when called, deregisters
   *          the C-side callback and releases the JSI references.
   *          Always called by the AsyncIterable cancel path.
   */
  subscribeProtoEvents(
    handle: number,
    onBytes: OnProtoBytes,
    onDone: OnStreamDone,
    onError: OnStreamError,
  ): UnsubscribeFn;
}
