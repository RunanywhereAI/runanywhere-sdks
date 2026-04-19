# Phase 2 — Streaming L3 primitives

> Goal: every L3 primitive (LLM, STT, TTS, VAD, embed, VLM, diffusion)
> exposes a `Stream<T>` API. The callback-based APIs are removed
> entirely — no shim.

---

## Prerequisites

- Phase 1 complete: every backend is reached through PluginRegistry, and
  `ra_engine_vtable_t` fills are wired in each `<backend>_plugin.cpp`.
- The graph primitives (`StreamEdge<T>`, `CancelToken`) from Phase 0 are
  available.

---

## What this phase delivers

One stream-shaped API per primitive:

| Primitive | Service file today | New shape |
| --- | --- | --- |
| `generate_text` | `src/features/llm/rac_llm_service.cpp` + 5 others | `StreamEdge<Token> llm_generate(session, Prompt, cancel_token)` |
| `transcribe` | `src/features/stt/` | `StreamEdge<TranscriptChunk> stt_transcribe(session, StreamEdge<AudioFrame>&, cancel_token)` |
| `synthesize` | `src/features/tts/` | `StreamEdge<AudioFrame> tts_synthesize(session, StreamEdge<std::string>&, cancel_token)` |
| `detect_voice` | `src/features/vad/` | `StreamEdge<VADEvent> vad_stream(session, StreamEdge<AudioFrame>&, cancel_token)` |
| `embed` | `src/features/embeddings/` | `std::vector<float> embed(session, std::string_view)` single-shot; `StreamEdge<std::vector<float>> embed_stream(session, StreamEdge<std::string>&)` batch |
| `vlm` (image → text) | `src/features/vlm/` | `StreamEdge<Token> vlm_describe(session, Image, Prompt, cancel_token)` |
| `diffusion` (text → image) | `src/features/diffusion/` | `StreamEdge<DiffusionStep> diffuse(session, Prompt, cancel_token)` — progressive denoising steps |

All **callback-based rac_* service functions are deleted.** The 1,243-LOC
`llm_component.cpp` gets the callback loop stripped; same for other
components. Tool calling (1,950 LOC) and structured output (504 LOC)
logic stays intact — they become transformations *over* the token
stream instead of inside the callback.

---

## Exact file-level deliverables

### New streaming primitive headers

```text
sdk/runanywhere-commons/include/rac/features/llm/stream_api.h
sdk/runanywhere-commons/include/rac/features/stt/stream_api.h
sdk/runanywhere-commons/include/rac/features/tts/stream_api.h
sdk/runanywhere-commons/include/rac/features/vad/stream_api.h
sdk/runanywhere-commons/include/rac/features/embeddings/stream_api.h
sdk/runanywhere-commons/include/rac/features/vlm/stream_api.h
sdk/runanywhere-commons/include/rac/features/diffusion/stream_api.h
```

Each header declares the streaming function and the relevant message
struct (`Token`, `TranscriptChunk`, `VADEvent`, `DiffusionStep`, etc.) —
these are **C++ in-process types**, not the C ABI wire types. The C ABI
gets proto3 encoding in Phase 5.

### Deleted public symbols

From every service header and matching `.cpp`:

- `rac_llm_generate(session, prompt, callback, user_data)`
- `rac_llm_cancel(session)`
- `rac_stt_feed_audio + rac_stt_flush + rac_stt_set_callback`
- `rac_tts_synthesize(session, text, out_pcm, max_samples, written, sr)`
  — the buffer-based API
- `rac_vad_feed_audio + rac_vad_set_callback`

Replaced entirely by stream-based APIs in the new `stream_api.h` files.

### Backend vtable update

`ra_engine_vtable_t` in `include/rac/abi/ra_plugin.h` changes its
function-pointer shape to be stream-oriented. The existing Phase-0 entries
move to the streaming signatures:

```cpp
// Before Phase 2
ra_status_t (*llm_generate)(ra_llm_session_t*, const ra_prompt_t*,
                             ra_token_callback_t on_token,
                             ra_error_callback_t on_error,
                             void* user_data);

// After Phase 2
ra_status_t (*llm_generate)(ra_llm_session_t*, const ra_prompt_t*,
                             ra::core::StreamEdge<Token>* out_stream,
                             ra::core::CancelToken* cancel);
```

Every `<backend>_plugin.cpp` from Phase 1 updates its function pointers
to the stream shape. Internally, each backend still produces tokens in
whatever native way it did (llama.cpp decode loop, sherpa FIFO, etc.);
the plugin glue pushes each token onto `out_stream`.

### Tool calling + structured output

`src/features/llm/tool_calling.cpp` and `structured_output.cpp` become
**stream transforms**. They consume `StreamEdge<Token>` and emit
`StreamEdge<ToolCall>` / `StreamEdge<StructuredEvent>`. No semantic
change — just API reshape.

### Streaming metrics

`src/features/llm/streaming_metrics.cpp` (548 LOC) collects first-token
latency, tokens/sec, etc. Moves from reading the callback to reading
from a tee on the token stream:

```cpp
auto [metrics_edge, llm_out_edge] = tee(llm_generate_stream);
attach_metrics(metrics_edge);
// consumer reads llm_out_edge
```

### Tests (new)

```text
tests/integration/llm_stream_test.cpp
  — asserts that a generated token stream produces ≥N tokens for a fixed
    prompt + seed; asserts cancel_token.cancel() stops the stream
    within ≤100ms.

tests/integration/stt_stream_test.cpp
  — feeds a known WAV; asserts the output stream emits partial chunks
    followed by a final chunk matching expected transcription.

tests/integration/tts_stream_test.cpp
  — feeds two sentences; asserts the output PCM stream length ≈ expected
    duration ±10%.

tests/integration/vad_stream_test.cpp
  — feeds a WAV containing silence→speech→silence; asserts VOICE_START,
    VOICE_END_OF_UTTERANCE events arrive in order.
```

---

## Implementation order

1. **Define `Token`, `TranscriptChunk`, `VADEvent`, `DiffusionStep`,
   `ToolCall`, `StructuredEvent` C++ structs.** These are internal to
   commons; not on the C ABI yet.

2. **Migrate LLM first.** Lowest dependency risk — self-contained
   backend (llama.cpp or MetalRT). Steps:
   - Update `rac_llm_service.cpp`: new `llm_generate` takes a `StreamEdge<Token>*`.
   - Inside the llama.cpp plugin file, the existing llama.cpp decode
     loop pushes each decoded token onto the output stream.
   - Delete the old `rac_llm_generate(..., callback, ...)` signature.
   - Update every caller inside commons (server/openai_handler, voice
     agent, tool calling, structured output).

3. **Fix tool calling + structured output** by making them stream
   transforms. Test: run an existing LLM flow that uses tool calling;
   verify the tool_call events still arrive.

4. **Migrate STT.** Now `stt_feed_audio` is an upstream push onto
   `StreamEdge<AudioFrame>`, and the STT plugin spawns its own worker
   that pops audio, feeds sherpa-onnx / whisper.cpp, and pushes
   `TranscriptChunk` onto the output stream.

5. **Migrate TTS.** `tts_synthesize` reads sentences from an input
   `StreamEdge<std::string>` and pushes PCM frames to an output
   `StreamEdge<AudioFrame>`.

6. **Migrate VAD.** Similar pattern: input audio stream, output event
   stream.

7. **Migrate embed.** Two variants: single-shot and batch-stream.
   Single-shot stays function-based (no benefit from streaming 1 item);
   batch-stream added for RAG ingestion in Phase 4.

8. **Migrate VLM.** `vlm_describe(Image, Prompt) → StreamEdge<Token>`.

9. **Migrate diffusion.** `diffuse(Prompt) → StreamEdge<DiffusionStep>`.
   Emits each denoising step so UIs can show progress.

10. **Migrate streaming_metrics.cpp.** Use a tee operator on the stream.

11. **Delete all callback-based service functions.** Single commit that
    removes the old symbols + updates the JNI bridges to the new shape.

12. **Update JNI bridges** to pull from streams instead of registering
    callbacks. Android / iOS / Flutter / RN / Web all eventually need
    their bridge reshaped, but **this plan only covers commons**. JNI
    changes here are only the commons-side JNI code; platform SDK
    bridges are Phase 2 of the frontend plan, which is out of scope.

13. **Add the integration tests.** Ensure each test runs under ASan.

---

## API changes

### Removed

Every `rac_*` callback-based primitive. No replacement provided under
the old name. The new streaming primitives live under `ra::core::*` /
`ra::features::*` C++ namespaces. C ABI streaming wrappers land in
Phase 5 when we switch to proto3 at the boundary.

### New (C++ in-process)

| Signature | Location |
| --- | --- |
| `StreamEdge<Token> ra::features::llm::generate(session, prompt, cancel)` | `rac/features/llm/stream_api.h` |
| `StreamEdge<TranscriptChunk> ra::features::stt::transcribe(session, audio_in, cancel)` | `rac/features/stt/stream_api.h` |
| `StreamEdge<AudioFrame> ra::features::tts::synthesize(session, text_in, cancel)` | `rac/features/tts/stream_api.h` |
| `StreamEdge<VADEvent> ra::features::vad::stream(session, audio_in, cancel)` | `rac/features/vad/stream_api.h` |
| `std::vector<float> ra::features::embed::one(session, text)` | `rac/features/embeddings/stream_api.h` |
| `StreamEdge<std::vector<float>> ra::features::embed::batch(session, text_in)` | idem |
| `StreamEdge<Token> ra::features::vlm::describe(session, image, prompt, cancel)` | `rac/features/vlm/stream_api.h` |
| `StreamEdge<DiffusionStep> ra::features::diffusion::diffuse(session, prompt, cancel)` | `rac/features/diffusion/stream_api.h` |

---

## Acceptance criteria

- [ ] `grep -rn "ra_token_callback_t\|rac_llm_generate\b" sdk/runanywhere-commons/` returns empty.
- [ ] Every L3 primitive test in `tests/integration/*_stream_test.cpp`
      green under ASan + UBSan + TSan.
- [ ] Tool calling + structured output tests (existing) still pass.
- [ ] Voice agent and RAG continue to build (even though Phase 3 / 4
      haven't rewritten them yet — they consume the new stream APIs
      via adapter wrappers added in this phase as a `// TODO(phase-3/4)`
      bridge).
- [ ] First-token latency benchmark available via a new
      `tools/benchmark/` invocation.

## Validation checkpoint — **MAJOR**

See `testing_strategy.md` for the umbrella discipline. Phase 2 is
the second major checkpoint — every L3 primitive changed signature.

- **Full L3 feature preservation matrix run.** Every primitive
  (LLM, STT, TTS, VAD, VLM, embed, diffusion) smoke-tested via the
  new `Stream<T>` API. Output shape/content matches pre-Phase-2 on
  the same fixture. Tool calling + structured output continue to
  produce identical parsed results for a fixed prompt.
- **Callback-parity regression.** For each primitive, a paired
  test asserts that the new stream API produces the same total
  output as the old callback API did (pinned expected fixture
  captured before the phase starts). For the LLM, that's token
  sequence identity given fixed seed.
- **Back-pressure stress test.** A slow consumer on any
  `StreamEdge<T>` correctly applies back-pressure to the producer
  — verified by a dedicated `back_pressure_stress_test.cpp` under
  TSan + ASan. No dropped frames, no deadlock within 10× the
  normal test duration.
- **Cancel latency.** Calling `cancel()` on a running LLM stream
  terminates the stream within ≤100 ms p99 across 100 iterations.
- **Streaming metrics continuity.** `streaming_metrics.cpp` still
  reports the same `first_token_ms` / `tokens_per_second` values
  (within noise) as pre-Phase-2 — the tee-based reading must not
  change the numbers.
- **Voice agent + RAG build-and-run intact.** Even with their
  Phase-3/4 rewrites deferred, the adapter bridge in this phase
  keeps them functional. Run the feature preservation matrix rows
  for voice agent + RAG; all pass.
- **Sanitizer matrix.** New `_stream_test.cpp` files green under
  ASan, UBSan, and TSan. Any newly added suppression is reviewed
  and documented.

**Sign-off before Phase 3**: dev CLI smoke-tests every primitive
via its new Stream API; outputs visually match expectations.

---

## What this phase does NOT do

- Voice agent still uses a batch-like flow (it consumes streams via
  blocking `pop()` calls, not a true DAG). That becomes a true DAG in
  Phase 3.
- RAG retrieval unchanged.
- C ABI still carries C structs, not proto3. That's Phase 5.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Plugin function pointers change shape — breaks Phase 1 vtables | Expected | Update all 5 `<backend>_plugin.cpp` vtable fills in the same PR |
| Tool calling parser depends on seeing all tokens in one call | Medium | Parser already accepts incremental input; confirmed from `tool_calling.cpp:pattern_accumulator_*`. Refactor iteratively feeds it each Token |
| Back-pressure: a slow TTS consumer blocks the LLM producer | Medium | `StreamEdge` bounded capacity is the backpressure signal. Pipeline_validator (Phase 6) flags deadlock-prone topologies |
| TSan flags races on token stream access across the LLM decode thread and consumer | Medium | `StreamEdge` is mutex + condvar protected; Phase 0 TSan tests already cover concurrent push/pop |
| JNI bridge to Kotlin/Flutter doesn't have a stream concept | OUT OF SCOPE | C ABI streaming wrappers in Phase 5 give each language runtime a way to iterate — SDK frontend plan covers the JNI update |
