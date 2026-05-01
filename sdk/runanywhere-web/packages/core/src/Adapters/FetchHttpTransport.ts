/**
 * FetchHttpTransport.ts (Stage 3d).
 *
 * JS-side implementation of the commons HTTP transport vtable
 * (`rac_http_transport_ops_t` declared in
 * `sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_transport.h`).
 *
 * Why this exists:
 *   H7 added a C++ emscripten_fetch shim in `rac_http_client_emscripten.cpp`
 *   that implements the transport vtable, but that path has two drawbacks:
 *     1. `emscripten_fetch` is natively async — synchronous mode requires
 *        `-sASYNCIFY=1`, which the CPU WASM variant does not link with.
 *     2. Every HTTP request pays an extra C++ ↔ JS hop: C++ calls
 *        `emscripten_fetch`, which calls JS `fetch()`, which calls into
 *        the browser network stack. The JS side has no way to inject
 *        retry / caching / service-worker interception.
 *
 *   This module lets the JS layer implement the transport directly using
 *   `window.fetch()` + `ReadableStream.getReader()`, registered via
 *   `_rac_http_transport_register_from_js`. The C side keeps the existing
 *   emscripten_fetch adapter as a fallback (null pointers for any op we
 *   don't override dispatch through the emscripten_fetch path
 *   automatically).
 *
 * Status — Stage 3d MVP:
 *   This file intentionally ships as a SCAFFOLD. The vtable registration
 *   path is wired end-to-end (TS → `Module.addFunction` → C function
 *   pointer → `_rac_http_transport_register_from_js` → `rac_http_transport.cpp`
 *   registry → router dispatch), but the three op implementations
 *   currently install null pointers for `request_stream` / `request_resume`
 *   and a stub for `request_send` that returns `RAC_ERROR_NETWORK_ERROR`
 *   with a diagnostic log line. The streaming / buffered body translation
 *   between the C ABI (`rac_http_request_t` / `rac_http_response_t`
 *   pointers into the WASM heap) and a JS `Promise<Response>` requires
 *   non-trivial WASM memory marshaling plus a way to block C on a JS
 *   promise (Atomics.wait on a worker, or JSPI on the main thread) — both
 *   out of scope for the Stage 3d TS scaffold. The follow-up can lift
 *   the heavy lifting out of `HTTPAdapter.ts` since the struct offset
 *   helpers are already exported from WASM.
 *
 * Usage (after Stage 3d scaffold lands):
 *
 *     import { FetchHttpTransport } from '@runanywhere/web';
 *     import { setRunanywhereModule } from '@runanywhere/web';
 *
 *     await initRunanywhereModule(...);
 *     FetchHttpTransport.install(module);  // optional; falls back to emscripten_fetch if skipped
 */

import { SDKLogger } from '../Foundation/SDKLogger';
import type { HTTPModule } from './HTTPAdapter';

const logger = new SDKLogger('FetchHttpTransport');

// rac_error.h error codes (mirrored locally to avoid a cross-file import
// — the commons header is C not TS, so these are hand-kept in sync the
// same way every other adapter does).
const RAC_SUCCESS = 0;
// RAC_ERROR_NETWORK_ERROR - used to surface "not implemented yet" so the
// caller sees a clear network failure rather than a silent zero response.
const RAC_ERROR_NETWORK_ERROR = -150;

/**
 * Extension of HTTPModule with the Stage 3d registration export.
 * Stays optional at type level so missing builds fall back to the
 * emscripten_fetch transport rather than hard-erroring at import time.
 */
export interface FetchHttpTransportModule extends HTTPModule {
  /**
   * `rac_result_t rac_http_transport_register_from_js(
   *    rac_result_t (*request_send)(void*, const rac_http_request_t*, rac_http_response_t*),
   *    rac_result_t (*request_stream)(void*, const rac_http_request_t*,
   *                                   rac_http_body_chunk_fn, void*, rac_http_response_t*),
   *    rac_result_t (*request_resume)(void*, const rac_http_request_t*, uint64_t,
   *                                   rac_http_body_chunk_fn, void*, rac_http_response_t*));`
   *
   * Pass function-table indices obtained from `Module.addFunction(fn, sig)`
   * for each op you want to route through JS, or 0 to fall back to
   * emscripten_fetch for that op. Passing 0 for all three unregisters
   * the JS adapter.
   */
  _rac_http_transport_register_from_js?(
    requestSendPtr: number,
    requestStreamPtr: number,
    requestResumePtr: number,
  ): number;
}

/**
 * JS-side HTTP transport installed via the commons transport vtable.
 *
 * Created by `FetchHttpTransport.install(module)`. Keeps a handle to the
 * underlying `addFunction` trampolines so `uninstall()` can remove them
 * and return memory to the WASM function table.
 */
export class FetchHttpTransport {
  private requestSendPtr = 0;
  private requestStreamPtr = 0;
  private requestResumePtr = 0;

  private constructor(private readonly m: FetchHttpTransportModule) {}

  /**
   * Install the JS-side HTTP transport into the given Emscripten module.
   *
   * Returns the transport instance (so the caller can `uninstall()` it
   * during teardown) or `null` if the module was built without the
   * Stage 3d export (`_rac_http_transport_register_from_js`). In the
   * latter case the caller should fall back to
   * `HTTPAdapter.setDefaultModule(...)` which registers the older
   * emscripten_fetch adapter.
   */
  static install(m: FetchHttpTransportModule): FetchHttpTransport | null {
    if (typeof m._rac_http_transport_register_from_js !== 'function') {
      logger.debug(
        'FetchHttpTransport.install: module missing _rac_http_transport_register_from_js; ' +
          'skipping JS-side HTTP transport (emscripten_fetch fallback remains active)',
      );
      return null;
    }

    const transport = new FetchHttpTransport(m);
    transport.doInstall();
    return transport;
  }

  /**
   * Remove the JS-side adapter from the transport registry and free
   * the `addFunction` table slots. Idempotent.
   */
  uninstall(): void {
    if (typeof this.m._rac_http_transport_register_from_js === 'function') {
      try {
        this.m._rac_http_transport_register_from_js(0, 0, 0);
      } catch (err) {
        logger.warning(
          `FetchHttpTransport.uninstall: register(0,0,0) threw: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    for (const ptr of [this.requestSendPtr, this.requestStreamPtr, this.requestResumePtr]) {
      if (ptr !== 0) {
        try {
          this.m.removeFunction(ptr);
        } catch {
          /* noop */
        }
      }
    }
    this.requestSendPtr = 0;
    this.requestStreamPtr = 0;
    this.requestResumePtr = 0;
  }

  // -------------------------------------------------------------------------
  // Implementation (Stage 3d scaffold — see file header)
  // -------------------------------------------------------------------------

  private doInstall(): void {
    // rac_http_transport_ops_t signatures (for reference when wiring
    // real implementations in follow-up):
    //   request_send:   (user_data*, req*, out_resp*) -> i32        sig 'iiii'
    //   request_stream: (user_data*, req*, cb*, cb_ud*, out_meta*) -> i32
    //                                                               sig 'iiiiii'
    //   request_resume: (user_data*, req*, resume_from_byte_j,
    //                    cb*, cb_ud*, out_meta*) -> i32             sig 'iiijiii'
    // i = i32, j = i64. Emscripten lowers pointer args as i32 on WASM32.
    //
    // Stage 3d scaffold: we register with ALL-NULL pointers, which the
    // C shim (`rac_http_client_emscripten.cpp`) interprets as "fall back
    // to emscripten_fetch for every op." This exercises the registration
    // path end-to-end (JS → addFunction-free 0 ptrs → C register_from_js
    // → transport registry → router dispatch → js_request_send →
    // emscripten_request_send) without committing to a heap-marshaling
    // implementation yet. The `makeRequestSend` scaffold is retained as
    // a reference for the follow-up (it is not wired in here because
    // returning RAC_ERROR from it would break requests — a real
    // implementation must actually call fetch() and populate the WASM
    // response struct).
    //
    // Callers who want to force emscripten_fetch fallback can simply
    // skip `FetchHttpTransport.install` entirely; the older
    // `HTTPAdapter.setDefaultModule` path already calls
    // `_rac_http_transport_register_emscripten()` which gives the same
    // routing behaviour.
    this.requestSendPtr = 0;
    this.requestStreamPtr = 0;
    this.requestResumePtr = 0;

    // Silence the "unused" lint on the scaffold without actually wiring
    // it — the real implementation will replace this.
    void this.makeRequestSend;

    const rc = this.m._rac_http_transport_register_from_js!(
      this.requestSendPtr,
      this.requestStreamPtr,
      this.requestResumePtr,
    );
    if (rc !== RAC_SUCCESS) {
      logger.warning(
        `FetchHttpTransport: register_from_js returned rc=${rc}; uninstalling`,
      );
      this.uninstall();
      return;
    }
    logger.debug(
      'FetchHttpTransport: JS HTTP transport registered (all ops fall back to emscripten_fetch; Stage 3d scaffold)',
    );
  }

  /**
   * JS implementation of `rac_http_transport_ops_t.request_send`.
   *
   * Full implementation is deferred to the follow-up — the current
   * scaffold returns `RAC_ERROR_NETWORK_ERROR` and leaves the existing
   * emscripten_fetch adapter as the effective HTTP path via the C-side
   * fallback (the C shim reroutes to `emscripten_request_send` when its
   * JS trampoline returns a non-success status).
   *
   * To flesh out this op the implementor needs to:
   *   1. Read the rac_http_request_t fields out of the WASM heap using
   *      the `_rac_wasm_offsetof_http_request_*` helpers.
   *   2. Pack them into a JS `Request` and call `fetch()`.
   *   3. Wait for the response (requires Atomics.wait on a worker or
   *      JSPI on the main thread — the C ABI is synchronous).
   *   4. Allocate WASM heap buffers for body / headers / redirected_url
   *      and write the response struct using the offset helpers +
   *      `_rac_wasm_sizeof_*`.
   *
   * The same offset helpers already underpin `HTTPAdapter.ts`, so the
   * marshaling logic can be lifted out of that file and shared.
   */
  private makeRequestSend(): (
    userData: number,
    reqPtr: number,
    outRespPtr: number,
  ) => number {
    return (_userData, reqPtr, outRespPtr) => {
      logger.debug(
        `FetchHttpTransport.request_send stub invoked (reqPtr=${reqPtr}, outRespPtr=${outRespPtr}); ` +
          `Stage 3d scaffold — falling back to emscripten_fetch path on C side`,
      );
      // Returning an error here does NOT cause the caller to fail — the
      // C shim sees the non-success code, but the transport registry
      // dispatched to `js_request_send` which only calls back into the
      // emscripten_fetch path when the JS trampoline is null. Until we
      // flip the C side to re-route on RC != 0, a real scaffold needs
      // to either (a) implement the op, or (b) be registered as null.
      // We pick (b): this function is NEVER installed by default — see
      // `doInstall()` above. The returning code below is defensive for
      // test harnesses that opt into the scaffold explicitly.
      return RAC_ERROR_NETWORK_ERROR;
    };
  }
}
