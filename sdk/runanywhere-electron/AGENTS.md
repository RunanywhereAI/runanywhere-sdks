# AGENTS.md

This package is the Electron and Node binding for RunAnywhere. `CLAUDE.md` is a
symlink to this file.

## Ownership

- C++ commons owns AI truth: inference, model lifecycle, registry, download,
  RAG, cancellation, and the error taxonomy. The TypeScript facade and the N-API
  addon are thin bridges over it.
- The public surface mirrors the Swift SDK. When behavior is ambiguous, copy the
  Swift version and adapt syntax only.
- Proto IDL is canonical. Types come from `@runanywhere/proto-ts`; never
  hand-write an enum value or a wire type.

## Architecture

Everything crosses as serialized `runanywhere.v1` protos. The layers:

- `RaBackend` (`src/backend.ts`) is the one contract both hosts implement. Every
  operation takes and returns proto bytes plus a few scalars, with at most one
  proto-byte chunk callback for streams. RAG sessions are opaque string ids. No
  native handle is in the interface.
- `NativeBackend` (`src/native/backend.ts`) runs in-process over the addon.
  `RpcBackend` (`src/rpc/backend.ts`) forwards each call over a MessagePort. Both
  satisfy `RaBackend`, which is why `createRunAnywhere` is written once and runs
  in either host.
- The namespaces (`src/namespaces/*.ts`) build a request proto with
  `@runanywhere/proto-ts`, call the backend, and decode the result. No prompt
  templating, grammar building, or output parsing lives here; commons does it.
- The addon (`native/addon.cpp`) is a proto-byte pass-through. Loading is
  registry-first: `registerModel` (or `registerModelFromUrl`), then
  `rac_model_lifecycle_load_proto(rac_get_model_registry(), ...)`, then the
  modality `*_lifecycle_proto` op. Commons tracks one loaded model per component,
  so inference calls carry no handle.

## Native safety

- Every blocking call runs on a worker thread and holds an in-flight lease
  (`inflight_inc`/`inflight_dec`, or `begin_op`/`take_handle_when_idle` for RAG
  sessions). `shutdown` waits for the lease count to drain before `rac_shutdown`,
  so an unload cannot free state under a live call.
- Streaming marshals proto-byte events to JS through a bounded
  `ThreadSafeFunction` (`BlockingCall`, so a slow consumer applies backpressure).
  LLM and VLM streams call `rac_*_proto_quiesce` in the finalizer before freeing
  the context. STT and TTS streams have no quiesce, so they rely on the worker
  join.
- The built-in energy VAD is a component (no model): `create` then `initialize`
  then `start` before `process`, destroyed on `shutdown`. The lifecycle VAD path
  needs a loaded model and is not what `vad.*` uses.
- Windows file and secure paths use wide UTF-16; the secure store is DPAPI on
  Windows and 0600 files on POSIX through the desktop adapter.

## Honesty

- Document what is true today. Wired and exercised over the real addon: llm
  (prompt and message overloads, reasoning split, structured output, streaming
  with real token/latency metrics), vlm, stt (batch transcribe), tts, vad,
  embeddings, diarization, segmentation, rag, models (register/download/load/
  unload, single-file, multi-file, and archive), tool calling (including from a
  renderer, over the host reverse channel), voice (a composed transcribe/answer/
  speak turn), and LoRA.
- Structured output is grammar-constrained decoding: `generateStructured` builds
  GBNF from the JSON schema and constrains the decode, then parses the result.
- Three gaps remain. rerank is handle-based in commons
  (`rac_rerank_component_*`, no lifecycle op), so the addon `Rerank` is still a
  stub and `rerank()` reports NOT_IMPLEMENTED until the component path is wired.
  Live STT streaming (`stt.openStream`) matches the Swift shape but the addon's
  push ops are not implemented, so it throws at runtime; use `stt.transcribe`.
  Image generation (`images.generate`) runs the real diffusion op, but no
  diffusion engine is linked in this build, so it returns FEATURE_NOT_AVAILABLE
  until one is.
- MLX and CoreML are out of the link set: the commons MLX engine needs a Swift
  callback provider Electron does not have, and CoreML is an Apple runtime
  adapter, not an engine. macOS GPU is llama.cpp Metal.

## Testing

- `npm test` is the primary gate: hermetic unit tests over the dispatch router,
  the error mapping, the resource guards, the stream helpers, both backends
  against fakes, and the control-plane proto assembly. No addon or model needed.
- `npm run test:integration` needs `RUNANYWHERE_NATIVE_PATH` pointed at a built
  addon and a local model on disk. It proves the proto-byte path down to the
  engine and skips loudly when its prerequisites are absent, so it never silently
  passes.
- Prefer hermetic fakes over real models for unit coverage. Do not add mock
  public APIs for unfinished capabilities; report the limitation and defer.

## Anti-patterns

- A bare `throw new Error(String(racCode))` on the native-to-JS path. Use the
  typed `SDKException`; the addon tags errors with `code` / `cAbiCode` and the
  loader proxy recovers them.
- Dispatching an un-allowlisted RPC method. The allowlist is exactly the v3
  backend operations (`ALLOWED_RPC_METHODS`).
- Reintroducing host-side logic that commons owns: chat templating, grammar
  building, thinking-tag parsing, download orchestration, or a hand-written
  model catalog. If something is missing, fix it in commons.
- Loading the native addon into a worker thread (`process.dlopen` is not
  thread-safe) or on the main thread.
