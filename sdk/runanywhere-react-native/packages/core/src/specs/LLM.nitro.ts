/**
 * LLM Nitrogen Spec
 *
 * v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
 *
 * Closes the RN side of Phase G-2. `LLMStreamAdapter.ts` imports this
 * HybridObject and calls `NitroLLM.subscribeProtoEvents(handle, onBytes,
 * onDone, onError)` to wire `rac_llm_set_stream_proto_callback` (commons
 * C ABI) through the Nitro bridge into the JS runtime.
 *
 * Mirrors the voice-agent equivalent (`VoiceAgent.nitro.ts`). The same
 * heap-copy lifetime contract applies: the bytes array is copied off the
 * C arena before dispatch, so holding onto it past the callback is safe.
 */
import type { HybridObject } from 'react-native-nitro-modules';

/** Callback fired once per serialized LLMStreamEvent proto message. */
export type OnLLMProtoBytes = (bytes: Uint8Array) => void;

/** Callback fired when the token stream terminates (stop / length). */
export type OnLLMStreamDone = () => void;

/** Callback fired when the transport encounters a non-recoverable error. */
export type OnLLMStreamError = (message: string) => void;

/** Unsubscribe function returned by `subscribeProtoEvents`. */
export type LLMUnsubscribeFn = () => void;

/**
 * LLM streaming surface for React Native.
 *
 * ABI limitation: `rac_llm_set_stream_proto_callback` keeps exactly one
 * callback slot per handle; concurrent subscribers on the SAME handle
 * replace each other. Fan-out for RN can be built on top if needed
 * (parity with Kotlin's `HandleFanOut`); not in this phase's scope.
 */
export interface LLM
  extends HybridObject<{
    ios: 'c++';
    android: 'c++';
  }> {
  /**
   * Register a proto-byte LLMStreamEvent callback on an LLM handle.
   *
   * @param handle  LLM component handle (cast to a JS number; the C++
   *                side reinterprets as `rac_handle_t`).
   * @param onBytes Fires once per `runanywhere.v1.LLMStreamEvent` with
   *                the serialized proto bytes. Safe to retain.
   * @param onDone  Fires at most once when the generation reaches its
   *                terminal state.
   * @param onError Fires at most once on transport-level errors.
   * @returns Zero-arg function that clears the C-side callback via
   *          `rac_llm_unset_stream_proto_callback(handle)`.
   */
  subscribeProtoEvents(
    handle: number,
    onBytes: OnLLMProtoBytes,
    onDone: OnLLMStreamDone,
    onError: OnLLMStreamError,
  ): LLMUnsubscribeFn;
}
