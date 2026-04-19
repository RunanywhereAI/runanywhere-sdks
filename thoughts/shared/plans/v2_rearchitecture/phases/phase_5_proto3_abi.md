# Phase 5 — proto3 at the C ABI boundary

> Goal: replace struct-based C ABI types (configs, events, status) with
> proto3-encoded length-prefixed byte buffers. The wire format becomes
> the single source of truth. Every SDK frontend (Kotlin / Swift /
> Flutter / RN / Web) gets the same generated types for free.

---

## Prerequisites

- Phase 0 shipped the `idl/` tree with proto3 files for every message
  we currently pass across the ABI.
- Phase 1–4 migrated the C++ side to streaming + plugin registry; the
  old callback surface is gone so the only consumers that still see C
  structs are the C ABI entry points themselves.

---

## What this phase delivers

1. **Every `ra_*` C ABI function accepts and returns proto3 byte
   buffers** instead of C structs. A typical signature:

   ```c
   ra_status_t ra_llm_create(const uint8_t* cfg_bytes, size_t cfg_len,
                             ra_llm_session_t** out);
   ```

   where `cfg_bytes` decodes into the generated `ra::idl::LlmConfig`
   proto.

2. **Generated C++ code** under `sdk/runanywhere-commons/src/gen/` via
   a CMake `Protobuf.cmake` target. Regenerated every build from `idl/`
   so the header is never hand-edited.

3. **Thin encode/decode helpers** at each ABI boundary — accept the
   byte buffer, decode, dispatch to the C++ core using the already-
   streaming C++ types from Phase 2, encode the result back.

4. **Deprecated C structs removed** from public headers. `ra_prompt_t`,
   `ra_llm_config_t`, `ra_tts_config_t`, `ra_vad_event_t`, etc. all go.
   The only C types remaining on the public surface are opaque session
   handles, `ra_status_t`, sized byte buffers, and primitive integer
   IDs.

5. **A streaming ABI shape**: for functions that return a `StreamEdge`
   in C++, the C ABI exposes a pair — `ra_*_next(session, buf, len,
   out_bytes, out_len)` for the consumer to pull one encoded event,
   plus `ra_*_cancel(session)` to signal cancellation. The frontend
   drives the pump from its own language thread/coroutine.

---

## Why proto3 specifically

- **Deterministic wire format** across languages. Kotlin gets Kotlin
  data classes via `protoc --kotlin_out`, Swift gets structs via
  `swift-protobuf`, TypeScript gets classes via `protobuf-ts`,
  Flutter gets Dart via `protoc_plugin`, React Native reuses the
  Kotlin/Swift bindings through its bridge.
- **Forward compatibility** is baked in — unknown fields round-trip
  through intermediate layers. Adding a field never breaks an older
  SDK frontend.
- **Varint-packed** length-prefix framing keeps the hot path small
  for simple messages (a `Token` is often ≤8 bytes on the wire).
- The alternatives we considered (Flatbuffers, Cap'n Proto, Avro) are
  all viable but have less tooling reach across our five language
  frontends. Proto3 is the least friction per language-binding.

---

## Exact file-level deliverables

### IDL additions and updates

Phase 0 laid down initial proto3 files. Phase 5 tightens and adds:

```text
sdk/runanywhere-commons/idl/
├── ra_common.proto              UPDATED — adds StreamControl, StreamError
├── ra_llm.proto                 UPDATED — LlmConfig, Prompt, Token, LlmEvent
├── ra_stt.proto                 UPDATED — SttConfig, AudioFrame, TranscriptChunk, SttEvent
├── ra_tts.proto                 UPDATED — TtsConfig, SynthRequest, AudioOut, TtsEvent
├── ra_vad.proto                 UPDATED — VadConfig, VadEvent
├── ra_embeddings.proto          UPDATED — EmbedConfig, EmbedRequest, EmbedResult
├── ra_vlm.proto                 UPDATED — VlmConfig, VlmRequest, VlmEvent
├── ra_diffusion.proto           UPDATED — DiffusionConfig, DiffusionRequest, DiffusionStep
├── ra_voice_agent.proto         UPDATED — VoiceAgentConfig, VoiceAgentEvent
├── ra_rag.proto                 UPDATED — RagConfig, RagDocument, RagQuery, RagResult
├── ra_wakeword.proto            NEW — WakeWordConfig, WakeWordEvent
├── ra_download.proto            NEW — DownloadRequest, DownloadEvent
├── ra_server.proto              UPDATED — OpenAI-compatible types mirror
└── ra_observability.proto       NEW — LogEvent, MetricSample, TraceSpan
```

Each proto file declares `syntax = "proto3";` and `package ra.idl;`.
Messages use explicit field numbers (never reuse, never reorder once
committed to the main branch).

### Example: `ra_llm.proto`

```proto
syntax = "proto3";
package ra.idl;

import "ra_common.proto";

message LlmConfig {
    string model_id        = 1;
    string runtime_hint    = 2;   // "cpu" | "cuda" | "metal" | "auto"
    int32  context_len     = 3;
    int32  n_gpu_layers    = 4;
    float  temperature     = 5;
    float  top_p           = 6;
    int32  max_tokens      = 7;
    bool   use_kv_cache    = 8;
    map<string, string> extra = 9;
}

message Prompt {
    enum Role { USER = 0; ASSISTANT = 1; SYSTEM = 2; TOOL = 3; }
    message Message {
        Role   role = 1;
        string text = 2;
    }
    repeated Message messages    = 1;
    repeated string  stop_tokens = 2;
    int32            seed        = 3;
}

message Token {
    int32 id    = 1;
    string text = 2;
    float logprob = 3;
}

// Events on the LLM output stream. Envelope; one of body fields set.
message LlmEvent {
    oneof body {
        Token         token       = 1;
        ToolCall      tool_call   = 2;
        StreamError   error       = 3;
        StreamControl control     = 4;  // end-of-stream, cancelled
    }
    int64 ts_ns = 5;  // producer-side wallclock ns
}

message ToolCall {
    string name   = 1;
    string json_args = 2;
    string call_id = 3;
}
```

### Example: `ra_common.proto`

```proto
syntax = "proto3";
package ra.idl;

enum Status {
    OK                  = 0;
    CANCELLED           = 1;
    INVALID_ARGUMENT    = 2;
    NOT_FOUND           = 3;
    UNAVAILABLE         = 4;
    OUT_OF_MEMORY       = 5;
    INTERNAL            = 6;
    UNIMPLEMENTED       = 7;
}

message StreamError {
    Status code    = 1;
    string message = 2;
}

message StreamControl {
    enum Kind {
        BEGIN = 0;
        END   = 1;
        FLUSH = 2;
        CANCELLED = 3;
    }
    Kind kind = 1;
}

message AudioFrame {
    bytes  pcm_f32      = 1;  // little-endian float32 samples
    int32  sample_rate  = 2;
    int32  channels     = 3;
    int64  ts_ns        = 4;
}
```

### CMake changes

`cmake/Protobuf.cmake` (introduced in Phase 0 as a stub) becomes real:

```cmake
find_package(Protobuf REQUIRED)

set(RA_IDL_DIR   "${CMAKE_SOURCE_DIR}/idl")
set(RA_IDL_OUT   "${CMAKE_BINARY_DIR}/gen/ra/idl")
file(MAKE_DIRECTORY "${RA_IDL_OUT}")

file(GLOB RA_IDL_PROTOS "${RA_IDL_DIR}/*.proto")

set(RA_IDL_SRCS "")
set(RA_IDL_HDRS "")
foreach(PROTO IN LISTS RA_IDL_PROTOS)
    get_filename_component(STEM "${PROTO}" NAME_WE)
    set(PB_CC "${RA_IDL_OUT}/${STEM}.pb.cc")
    set(PB_H  "${RA_IDL_OUT}/${STEM}.pb.h")
    list(APPEND RA_IDL_SRCS "${PB_CC}")
    list(APPEND RA_IDL_HDRS "${PB_H}")
    add_custom_command(
        OUTPUT "${PB_CC}" "${PB_H}"
        COMMAND protobuf::protoc
                --cpp_out=${RA_IDL_OUT}
                -I ${RA_IDL_DIR}
                ${PROTO}
        DEPENDS "${PROTO}" protobuf::protoc
        COMMENT "Generating ${STEM}.pb.{h,cc}"
    )
endforeach()

add_library(ra_idl STATIC ${RA_IDL_SRCS})
target_include_directories(ra_idl PUBLIC "${CMAKE_BINARY_DIR}/gen")
target_link_libraries(ra_idl PUBLIC protobuf::libprotobuf)
set_target_properties(ra_idl PROPERTIES POSITION_INDEPENDENT_CODE ON)
```

Root `CMakeLists.txt` adds:

```cmake
include(cmake/Protobuf.cmake)
target_link_libraries(runanywhere_commons PUBLIC ra_idl)
```

`vcpkg.json` gains `"protobuf"` in the dependency list (already stubbed
in Phase 0; Phase 5 is the first consumer).

### C ABI entry points — the new shape

`sdk/runanywhere-commons/include/rac/abi/ra_llm.h`:

```c
#pragma once
#include "rac/abi/ra_status.h"
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ra_llm_session ra_llm_session_t;

// Create a session from an encoded LlmConfig proto.
ra_status_t ra_llm_create(const uint8_t* cfg_bytes, size_t cfg_len,
                          ra_llm_session_t** out);

ra_status_t ra_llm_destroy(ra_llm_session_t* session);

// Begin generation. `prompt_bytes` is an encoded Prompt proto.
// The session owns the stream; caller drains via ra_llm_next.
ra_status_t ra_llm_start(ra_llm_session_t* session,
                         const uint8_t* prompt_bytes, size_t prompt_len);

// Pull one LlmEvent off the stream. If `buf` is NULL the call only
// writes the required size to `*out_len` and returns OK. Otherwise if
// `*out_len` on entry is < required, returns RA_STATUS_BUFFER_TOO_SMALL
// and sets `*out_len` to required. On success, writes exactly that
// many bytes into `buf` and updates `*out_len`.
ra_status_t ra_llm_next(ra_llm_session_t* session,
                        uint8_t* buf, size_t buf_cap, size_t* out_len);

// Request cancellation. Idempotent.
ra_status_t ra_llm_cancel(ra_llm_session_t* session);

#ifdef __cplusplus
}
#endif
```

Matching pattern for STT, TTS, VAD, VLM, diffusion: `create → start →
next → cancel → destroy`.

### The encode/decode edge

Each C entry point is a thin shim. Example for `ra_llm_start`:

```cpp
// sdk/runanywhere-commons/src/abi/ra_llm_abi.cpp
ra_status_t ra_llm_start(ra_llm_session_t* session,
                         const uint8_t* prompt_bytes, size_t prompt_len) {
    if (!session || !prompt_bytes) return RA_STATUS_INVALID_ARGUMENT;
    ra::idl::Prompt prompt;
    if (!prompt.ParseFromArray(prompt_bytes, static_cast<int>(prompt_len))) {
        return RA_STATUS_INVALID_ARGUMENT;
    }
    // Map proto → in-process C++ struct.
    auto cpp_prompt = ra::abi::from_proto(prompt);
    return session->impl->start(cpp_prompt);
}
```

`ra::abi::from_proto` / `ra::abi::to_proto` functions live in
`src/abi/conversions.{h,cpp}` and are the only place that bridges the
two representations.

### Pulling events out of a C++ StreamEdge into a proto buffer

```cpp
ra_status_t ra_llm_next(ra_llm_session_t* session,
                        uint8_t* buf, size_t cap, size_t* out_len) {
    if (!session || !out_len) return RA_STATUS_INVALID_ARGUMENT;

    ra::features::llm::Token tok;
    auto pop = session->impl->out_stream().pop();  // blocking
    if (!pop.has_value()) {
        // Stream closed. Serialize a final StreamControl{END}.
        ra::idl::LlmEvent evt;
        evt.mutable_control()->set_kind(ra::idl::StreamControl::END);
        return ra::abi::serialize_into(evt, buf, cap, out_len);
    }
    ra::idl::LlmEvent evt = ra::abi::token_to_event(*pop);
    return ra::abi::serialize_into(evt, buf, cap, out_len);
}
```

### Deleted C symbols

The moment this phase lands, the following are gone from `include/rac`:

```text
ra_prompt_t, ra_generation_config_t, ra_llm_config_t        (ra_llm.h)
ra_stt_config_t, ra_audio_frame_t, ra_transcript_t          (ra_stt.h)
ra_tts_config_t, ra_tts_request_t                           (ra_tts.h)
ra_vad_config_t, ra_vad_event_t                             (ra_vad.h)
ra_vlm_config_t, ra_vlm_request_t                           (ra_vlm.h)
ra_rag_config_t, ra_rag_document_t, ra_rag_query_t          (ra_rag.h)
ra_voice_agent_config_t, ra_voice_agent_event_t             (ra_voice_agent.h)
```

All callers inside commons now go through `ra::abi::*` conversions
instead of hand-rolling structs.

### Tests

```text
tests/integration/abi_proto_roundtrip_test.cpp
  — constructs every proto message, serialises, parses, asserts
    field-level equality.

tests/integration/abi_llm_stream_test.cpp
  — starts an LLM session via ra_llm_create + ra_llm_start, pumps
    ra_llm_next in a tight loop, parses each event as LlmEvent, asserts
    terminates on StreamControl::END.

tests/integration/abi_cancel_test.cpp
  — issues ra_llm_cancel from one thread while another drains
    ra_llm_next; asserts all subsequent events are either the final
    StreamControl{CANCELLED} or empty with RA_STATUS_STREAM_CLOSED.
    TSan-clean.

tests/integration/abi_backpressure_test.cpp
  — consumer deliberately calls ra_llm_next slowly; asserts producer
    thread stays alive and no events are dropped (confirmed by
    counting). TSan-clean.
```

### Benchmark additions

`tools/benchmark/abi_encode_cost.cpp` — measures encode + decode ns per
message across Token (smallest), TranscriptChunk (medium), RagResult
(largest). Gate: encode+decode for Token p99 ≤ 2 µs on a dev MacBook,
so the ABI overhead stays under the measurement noise of the primitive
itself.

---

## Implementation order

1. **Finalize the `idl/` schemas.** One proto file per feature, field
   numbers locked. Code review before any codegen runs.

2. **Wire `cmake/Protobuf.cmake` into the build.** Verify codegen
   produces `build/gen/ra/idl/*.pb.{h,cc}`. Add `ra_idl` target to
   commons link.

3. **Write `src/abi/conversions.{h,cpp}`** — all proto ↔ C++ struct
   conversion helpers. Unit test each direction.

4. **Update `ra_plugin.h` vtable.** Engines still see C++ types, not
   proto — the proto boundary lives at the C ABI, not the plugin ABI.
   So the plugin vtable signatures don't change in this phase. (We
   considered pushing proto all the way down; decided against it —
   adds copies on the hot path inside-process.)

5. **One feature at a time, bottom-up:**
   1. LLM first (same reason as Phase 2 — isolated).
   2. STT + TTS + VAD.
   3. Embed + VLM + diffusion.
   4. Voice agent (which aggregates several of the above).
   5. RAG.
   6. Wake word.
   7. Model download / extraction / observability side channels.

   For each: delete the old C struct → add the new proto accessor →
   rewrite the ABI entry points → update the OpenAI HTTP server
   handler to use protos internally where it bridges to features.

6. **Delete the structs from public headers** in a single sweep at the
   end — every caller has already been migrated piecewise.

7. **Regenerate JNI bridges** inside commons (the commons-side JNI
   stubs under `src/bindings/jni/`). Each JNI entry decodes a
   jbyteArray → proto → C++ → back. Frontend SDK updates are out of
   scope for this plan but this phase hands them a working C ABI.

8. **Run the full integration + benchmark suite** under ASan + TSan.

---

## API changes

### Public C ABI — reshaped

Every `ra_*_create`, `ra_*_start`, `ra_*_next`, `ra_*_cancel`,
`ra_*_destroy` function takes byte buffers where it used to take a
struct pointer. Opaque session handles unchanged. `ra_status_t` values
unchanged.

### Public C++ — unchanged

`ra::features::*` stream APIs from Phase 2 are not affected.

### Plugin vtable — unchanged

Engine plugins still speak C++ types as of Phase 1/2. Proto never
reaches the plugin layer — it stops at the ABI wall.

---

## Acceptance criteria

- [ ] `grep -rn "ra_llm_config_t\|ra_prompt_t\|ra_tts_config_t\|ra_vad_event_t" sdk/runanywhere-commons/include/`
      returns no matches.
- [ ] `abi_proto_roundtrip_test` — every message encodes + decodes
      with field equality across the 40+ messages in the IDL tree.
- [ ] `abi_llm_stream_test` — green under ASan, TSan, UBSan.
- [ ] `abi_cancel_test` — no stuck threads; no use-after-free.
- [ ] Encode+decode latency for a `Token`: p99 ≤ 2 µs on the CI
      benchmark runner.
- [ ] `cmake --build .` regenerates `src/gen/` from scratch on a clean
      build with no hand-edited proto output in the tree.
- [ ] Codegen is reproducible: two clean builds produce byte-identical
      `.pb.cc` files (no timestamps baked in).

## Validation checkpoint — **MAJOR**

See `testing_strategy.md`. Phase 5 reshapes the entire C ABI
surface — every external caller's entrypoint changed. Checkpoint
is exhaustive:

- **Feature preservation matrix via new ABI.** Every row exercised
  through the new `ra_*_create/start/next/cancel/destroy` shape.
  Identical outputs (deterministic ops) or within tolerance
  (STT / VLM) vs pre-Phase-5 reference.
- **Proto3 round-trip tests.** Every `ra.idl.*` message
  serialises + deserialises with field-level equality across the
  entire schema tree (40+ messages).
- **Ambient benchmark.** `abi_encode_cost` bench green:
  Token round-trip p99 ≤ 2 µs. Voice agent + RAG benches show no
  regression (ABI wrapping not on the hot path).
- **Fuzz pass.** A libFuzzer target feeds random bytes into
  `ra_llm_start` / `ra_stt_start` etc.; asserts the ABI never
  crashes, only returns `INVALID_ARGUMENT`. Run for ≥10 minutes
  per entry point in CI.
- **Backward-incompatible rename check.** `grep -rn "ra_llm_config_t\|ra_prompt_t"`
  in the commons include tree returns zero. Any straggler = a
  caller we missed.
- **Cross-feature smoke.** Start voice agent, start RAG in
  parallel, stream from both, no deadlock, no interference. Tests
  that ABI concurrency is safe.
- **Cancellation correctness.** `abi_cancel_test` green under TSan.
  No stuck threads, no use-after-free.
- **Lite runtime linkage.** Linker flag audit confirms the binary
  links `libprotobuf-lite` not full `libprotobuf` (binary size
  check: ≤ +400 KB vs pre-phase baseline).
- **Integration gate with Swift/Kotlin/TS consumers.** Build a
  trivial consumer in each of Swift + Kotlin + TS against the
  generated proto types for one message (e.g. `Token`); prove
  they decode bytes produced by the C++ side. This is the proto3
  interop canary — cheap here, expensive to debug later.

**Sign-off before Phase 6**: proto3 round-trip fuzz ran ≥10
minutes per entry point; interop canary green.

---

## What this phase does NOT do

- No language-specific generators yet — Kotlin/Swift/Dart/TS codegen
  lives in the frontend SDK migration plans.
- Plugin vtable stays on C++ types. Proto stops at the C ABI.
- gRPC / network protobuf — out of scope. This is an in-process wire
  format only. (A future remote-engine backend could trivially reuse
  the schemas but that's not scoped here.)
- No deprecation shims. The C struct symbols are removed outright.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Protobuf adds ≈2 MB to the binary — bloats iOS / web bundles | High | Use `protoc --cpp_out=lite:...` with `-DPROTOBUF_USE_DLLS=OFF` + link `libprotobuf-lite`. Lite runtime is ~300 KB. Benchmark bundle sizes per platform and gate in Phase 6 |
| Encode+decode on hot token stream adds real latency | Medium | Benchmark gate at ≤2 µs p99 per Token round-trip. Small messages are near-free on lite runtime (single varint + short string). Pool a thread-local `google::protobuf::io::ArrayOutputStream` to avoid re-alloc |
| Frontend SDK developers lag behind schema changes and ship broken builds | High | Version the IDL tree: bump `ra_idl.version` field every breaking change. Frontend builds assert compatibility at plugin-init time. Out of scope here, but documented for the follow-up |
| `oneof` envelope for events forces a switch per consume — looks heavy | Low | Compiler generates inline accessors; switch compiles to a table lookup. Verified in godbolt for small oneofs. Worth it for forward compatibility |
| Length-prefixing in `ra_*_next` means one extra allocation per call for the buffer | Medium | Caller owns the buffer, reuses it across calls. For streams where the consumer calls `next` in a loop, the buffer is allocated once and reused. Design matches gRPC's ClientReader — proven |
| Older integration code paths still construct C structs in one place we miss | Medium | Deletion sweep is final and mechanical — grep for each removed symbol after touching the feature. Acceptance criterion includes the grep check |
| Protobuf version skew between vcpkg-installed and system-installed protoc | Medium | Pin the protobuf version in `vcpkg.json`; CI invokes `vcpkg install` before configure; Dockerfile in `tools/ci` uses the same vcpkg toolchain |
