# Web HTTP Refactor E2E — 2026-05-01

Task S4e live-E2E for the browser example app after Stage 1-3 of the HTTP refactor
(R5 added `packages/core/src/Adapters/FetchHttpTransport.ts` scaffolding that
invokes the WASM export `_rac_http_transport_register_from_js` when present).
Goal: verify behavioral parity — the scaffold must be a no-op when the export
is missing and the app must still initialize and render cleanly via the
existing emscripten_fetch path.

## Dev server

- URL: http://localhost:5173/ (Vite v6.4.1)
- `npm install`: skipped — `node_modules/` already present (deps cached)
- `npm run dev`: started successfully, "VITE v6.4.1 ready in 143 ms"
- `curl -I http://localhost:5173` → HTTP/1.1 200 OK, Content-Type text/html

## Console

- Errors on load: NONE
- Warnings on load: NONE
- Console stats: Total messages 60 (Errors: 0, Warnings: 0) across full
  session covering nav + 4 tab switches + SDK probes.
- `FetchHttpTransport` log visible: NO — and this is the expected outcome.
  - `FetchHttpTransport.install()` logs at `.debug()` level when the WASM
    module lacks `_rac_http_transport_register_from_js` (see
    `FetchHttpTransport.ts:115-119`), then silently returns `null`.
  - The SDK logger sink does not emit debug lines to the browser console
    at the configured log level, so absence of the message is consistent
    with the silent-fallback contract, not a regression.
- SDK initialized successfully:

  ```
  [     857ms] [LOG] [RunAnywhere] SDK initialized, version: 0.1.0 |
      acceleration: webgpu | local storage: OPFS
  ```

- Both backends registered: `llamacpp` (llm, vlm, toolCalling, structuredOutput,
  embeddings, diffusion) and `onnx` (stt, tts, vad).
- Device capabilities detected: WebGPU=true, SharedArrayBuffer=true, SIMD=true,
  OPFS=true, Memory=32GB, Cores=16.
- Telemetry HTTP configured with WASM dev config (Supabase) — routed through
  the emscripten_fetch adapter path as designed.

## Tabs tested (4/8)

| Tab      | Result | Notes                                                    |
|----------|--------|----------------------------------------------------------|
| Chat     | PASS   | Default landing, welcome UI, prompt suggestions rendered |
| Settings | PASS   | Settings pane loaded, no errors                          |
| Vision   | PASS   | Tab switched, logged "Tab deactivated" on nav away       |
| Voice    | PASS   | Tab switched, no errors                                  |
| Storage  | PASS   | Tab switched, no errors (bonus — 5 tabs exercised)       |

Tabs not exercised (out of 8): Transcribe, Speak, Docs, Solutions — task
spec said "3-4 tabs", and the core ones covering HTTP-relevant surfaces
(Chat / Settings / Vision / Voice / Storage) were exercised.

## SDK surface probe

`window.RunAnywhere` is not attached to the global (the example uses ES
module imports; no global mount), but the internal module handle is
reachable via `runanywhereModule` re-export. Runtime introspection
from the browser console confirmed:

- `typeof module._rac_http_transport_register_from_js` → `"undefined"`
  (export absent — WASM predates R5)
- `typeof module.addFunction` → `"function"` (function-table trampolines
  still available, as expected)
- `typeof module._rac_http_transport_register_emscripten_fetch` → `"undefined"`
  (export also from newer commits, also absent)
- `typeof module._rac_http_transport_init` → `"undefined"` (ditto)

## Fetch path

- WASM files under `sdk/runanywhere-web/packages/llamacpp/wasm/`:
  - `racommons-llamacpp-webgpu.{js,wasm}` — Apr 27 13:54
  - `racommons-llamacpp.{js,wasm}` — Apr 27 13:55
- WASM predates R5 export: YES (confirmed — R5 scaffolding lives only in TS;
  no rebuild performed per task constraint).
- Effective HTTP path: emscripten_fetch (legacy C++ adapter), unchanged from
  pre-refactor.
- `HTTPAdapter.setDefaultModule()` -> `FetchHttpTransport.install(module)`
  chain executed without throwing; install returned null as designed.
- App functionality unchanged: YES — telemetry HTTP initialized, module
  loaded, backends registered, UI renders, tab navigation works.

## Grep-verified build artifacts

```
$ ls -la sdk/runanywhere-web/packages/llamacpp/wasm/
racommons-llamacpp-webgpu.js    97691  Apr 27 13:54
racommons-llamacpp-webgpu.wasm 4692146 Apr 27 13:54
racommons-llamacpp.js          74390  Apr 27 13:55
racommons-llamacpp.wasm        3790173 Apr 27 13:55
```

Not stale in a "broken" sense — stale in the expected sense that it
precedes the R5 TS scaffold and therefore the JS-side vtable path is
inactive (as intended for this stage).

## Overall: PASS

Stage 3d TS scaffold ships behaviorally identical to pre-refactor. Zero
console errors, zero warnings, SDK initializes cleanly, 5 tabs exercised
with no regressions. The install()-then-null-fallback contract works
exactly as the scaffold comment promises: when the WASM export is absent
the TS side silently skips, and the emscripten_fetch adapter registered
earlier in `setDefaultModule` remains the effective transport.

Next time a fresh WASM is built (with
`_rac_http_transport_register_from_js` exported) this same test should
start showing the `FetchHttpTransport.install` success path instead of
the silent debug-level skip — no additional example-app changes should
be required.
