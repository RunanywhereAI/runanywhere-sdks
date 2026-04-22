/**
 * VoiceAgentStreamAdapter.ts (Web / WASM)
 *
 * GAP 09 Phase 19 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
 *
 * Wraps an Emscripten Module.addFunction() callback as an
 * `AsyncIterable<VoiceEvent>` using the codegen'd transport wrapper
 * from `idl/codegen/templates/ts_async_iterable.njk` (Phase 14).
 *
 * Cancellation: `AsyncIterator.return()` (triggered by `for-await break`)
 * calls our cancel function, which removes the function from the
 * Emscripten function table and tells C++ to clear the callback slot.
 */

import { VoiceEvent, VoiceAgentRequest } from '../generated/voice_agent_service';
import {
  streamVoiceAgent,
  VoiceAgentStreamTransport,
} from '../generated/streams/voice_agent_service_stream';
import { runanywhereModule } from '../runtime/EmscriptenModule';

/**
 * Adapter that exposes the C++ proto-byte voice agent callback as a
 * standard JS AsyncIterable. Holds an opaque [handle] (a pointer
 * returned from the WASM `_rac_voice_agent_create()` thunk) and
 * constructs a fresh transport per [stream()] call.
 */
export class VoiceAgentStreamAdapter {
  constructor(private readonly handle: number) {}

  stream(req: VoiceAgentRequest = { eventFilter: '' }): AsyncIterable<VoiceEvent> {
    return streamVoiceAgent(this.transport(), req);
  }

  private transport(): VoiceAgentStreamTransport {
    const handle = this.handle;
    return {
      subscribe(_req, onMessage, onError, onDone) {
        const m = runanywhereModule;

        // Allocate a JS function pointer in the Emscripten function table.
        // The C signature is `(uint8_t*, size_t, void*) -> void`, encoded
        // as 'viii' (3 i32 args, void return).
        const cbPtr = m.addFunction(
          (bytesPtr: number, bytesLen: number, _userData: number) => {
            try {
              if (bytesPtr === 0 || bytesLen <= 0) return;
              // Copy off the WASM heap (the buffer is invalidated when
              // this callback returns; the proto deserializer keeps no
              // reference to the original memory).
              const bytes = new Uint8Array(
                m.HEAPU8.buffer, bytesPtr, bytesLen,
              ).slice();   // .slice() copies into a fresh Uint8Array.
              onMessage(VoiceEvent.decode(bytes));
            } catch (e) {
              onError(e instanceof Error ? e : new Error(String(e)));
            }
          },
          'viii',
        );

        const rc = m._rac_voice_agent_set_proto_callback(handle, cbPtr, 0);
        if (rc !== 0) {
          m.removeFunction(cbPtr);
          onError(new Error(
            `rac_voice_agent_set_proto_callback failed: ${rc} ` +
            `(Protobuf may not be linked into the wasm module)`
          ));
          onDone();
          return () => {};
        }

        return () => {
          m._rac_voice_agent_set_proto_callback(handle, 0, 0);
          m.removeFunction(cbPtr);
        };
      },
    };
  }
}
