/**
 * LLM Nitrogen Spec
 *
 * Mirrors `VoiceAgent.nitro.ts`. Exposes the Nitro-backed proto-byte LLM
 * stream callback ABI used by `LLMStreamAdapter.ts`. The C++ side
 * (`HybridLLM.{cpp,hpp}`) wires this into `rac_llm_set_stream_proto_callback`
 * (commons C ABI). Cancellation goes back through the returned unsubscribe
 * function which clears the callback slot via
 * `rac_llm_set_stream_proto_callback(handle, NULL, NULL)`.
 *
 * Matches the Web `LLMStreamAdapter` pattern (Emscripten Module callback)
 * and the Swift `LLMStreamAdapter` pattern (CRACommons proto callback).
 */
import type { HybridObject } from 'react-native-nitro-modules';

/** Callback fired once per serialized LLMStreamEvent proto message.
 *  `Uint8Array` is the idiomatic wire-bytes type in TS — ts-proto's
 *  `LLMStreamEvent.decode(bytes)` accepts it directly without a copy.
 *  The Nitro C++ side heap-copies the proto arena bytes before
 *  dispatch, so holding onto the array past the callback is safe. */
export type OnProtoBytes = (bytes: ArrayBuffer) => void;

/** Callback fired when the LLM's event stream terminates normally. */
export type OnStreamDone = () => void;

/** Callback fired when the transport encounters a non-recoverable error. */
export type OnStreamError = (message: string) => void;

/**
 * Unsubscribe function returned by `subscribeProtoEvents`. Calling it
 * clears the C-side callback via `rac_llm_set_stream_proto_callback(handle, NULL, NULL)`.
 */
export type UnsubscribeFn = () => void;

/**
 * LLM streaming surface for React Native.
 *
 * One instance is created per handle (obtained via
 * `RunAnywhereCore.getLLMHandle()`); each `subscribeProtoEvents` call
 * creates an independent registration. **ABI limitation**: the underlying
 * `rac_llm_set_stream_proto_callback` keeps exactly one callback slot
 * per LLM handle, so multiple concurrent subscribers on the SAME handle
 * will replace each other.
 */
export interface LLM
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  /**
   * Register a proto-byte callback on an LLM handle.
   *
   * @param handle  The LLM handle returned by
   *                `RunAnywhereCore.getLLMHandle()`, reinterpreted
   *                as a JS number (the C++ side casts back to
   *                `rac_llm_handle_t`).
   * @param onBytes Fires once per `runanywhere.v1.LLMStreamEvent` with the
   *                serialized proto bytes.
   * @param onDone  Fires when the stream reaches its terminal state
   *                (LLMStreamEvent.isFinal == true). Called at most once.
   * @param onError Fires on transport-level errors. Called at most once.
   *
   * @returns A zero-argument function that, when called, deregisters
   *          the C-side callback and releases the JSI references.
   */
  subscribeProtoEvents(
    handle: number,
    onBytes: OnProtoBytes,
    onDone: OnStreamDone,
    onError: OnStreamError,
  ): UnsubscribeFn;
}
