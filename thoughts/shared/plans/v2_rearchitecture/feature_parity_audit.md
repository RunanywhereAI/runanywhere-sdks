# Feature parity audit — legacy commons vs new architecture

> Source: two parallel audits run on 2026-04-19.
> Legacy audited: `sdk/runanywhere-commons/src/*` + `include/rac/*`.
> New architecture audited: `core/`, `engines/`, `solutions/`, `idl/`, `tools/`.

## Gap summary

For each capability in legacy commons, state of the new architecture:

### L3 primitives

| Capability | Legacy | New | Status |
|---|---|---|---|
| LLM streaming generation | ✓ | ✓ | PARITY |
| LLM tool calling | ✓ (`rac_tool_calling.h`) | — | **GAP** |
| LLM structured output | ✓ (`rac_llm_structured_output.h`) | — | **GAP** |
| LLM streaming metrics (TTL/TTD) | ✓ (per-service timing) | partial (bench only) | **GAP** |
| LLM LoRA adapter load/remove/clear | ✓ | — | **GAP** |
| LLM KV-cache context injection | ✓ (`inject_system_prompt`, `append_context`) | — | **GAP** |
| STT streaming | ✓ | ✓ | PARITY |
| STT batch (full-file) | ✓ | — | **GAP** |
| TTS blocking synthesis | ✓ | ✓ | PARITY |
| TTS streaming synthesis (long text) | ✓ | — | **GAP** |
| VAD sherpa-onnx | ✓ | ✓ | PARITY |
| VAD energy-based fallback | ✓ (`rac_vad_energy.h`) | — | **GAP** |
| VLM (image + text) | ✓ (llamacpp mmproj, MLX stub) | — | **GAP** |
| Embed single text | ✓ | ✓ | PARITY |
| Embed batch | ✓ | — | **GAP** |
| Diffusion text→image / image→image / inpaint | ✓ (partial) | — | **GAP** |
| Wake word (single) | ✓ | ✓ | PARITY |
| Wake word multi-keyword | ✓ | partial | PARITY-lite |

### L5 solutions

| Capability | Legacy | New | Status |
|---|---|---|---|
| Voice agent full pipeline | ✓ | ✓ | PARITY (architecturally cleaner) |
| Voice agent state machine (WAITING_WAKEWORD → LISTENING → …) | ✓ | partial (barge-in only) | **GAP** |
| RAG retrieval | ✓ (header only) | ✓ (BM25 + HybridRetriever) | PARITY |
| RAG full pipeline (retrieve → context → LLM compose) | ✓ (header) | — | **GAP** |

### Infrastructure

| Capability | Legacy | New | Status |
|---|---|---|---|
| Model download with state machine + retry | ✓ (`rac_download_orchestrator.h`) | partial (one-shot libcurl) | **GAP** |
| Extraction (ZIP, TAR.GZ, TAR.BZ2, TAR.XZ) with zip-slip protection | ✓ (libarchive) | — | **GAP** |
| File management (centralized directory ops) | ✓ (`rac_file_manager.h`) | — | **GAP** |
| Model paths standardization (`{base}/RunAnywhere/Models/…`) | ✓ | — | **GAP** |
| Model compatibility checking | ✓ | — | **GAP** |
| LoRA registry | ✓ (separate from model registry) | — | **GAP** |
| HTTP client (GET/POST/PUT/DELETE/PATCH, headers) | ✓ | partial (libcurl inside downloader) | **GAP** |
| Auth manager (API keys) | ✓ | — | **GAP** |
| Endpoints config + environment (dev/staging/prod) | ✓ | — | **GAP** |
| Device manager (HW probe + registration + analytics) | ✓ | partial (HardwareProfile only) | **GAP** |
| Storage analyzer (capacity) | ✓ | — | **GAP** |
| Telemetry event queue + JSON serialization | ✓ | basic MetricsEvent only | **GAP** |

### Other

| Capability | Legacy | New | Status |
|---|---|---|---|
| OpenAI HTTP server (`/v1/chat/completions` streaming) | ✓ | — | **GAP** |
| JNI bridges (LLM/STT/TTS/VAD) | ✓ | — | **GAP (blocks Kotlin migration)** |
| Error taxonomy (900 codes × 16 domains) | ✓ | basic status enum | **GAP** |
| Lifecycle state machine | ✓ | basic session lifecycle | PARTIAL |
| Events pub-sub (50+ event types) | ✓ centralized | StreamEdge-based per-pipeline | DIFFERENT |
| Audio utilities (float32/int16 → WAV) | ✓ | — | **GAP** |
| Image utilities | ✓ (stub) | — | PARTIAL |
| Centralized logger macros | ✓ (`RAC_LOG_*`) | uses spdlog | DIFFERENT |

## Execution plan

Closing order (priority = what blocks SDK migration):

1. **HTTP client + auth + endpoints + environment** — needed by every SDK
2. **Extraction** — needed by downloader (legacy downloader auto-extracts)
3. **Error taxonomy** — needed by every SDK for user-facing error strings
4. **Audio utilities** — needed by frontends for WAV encoding
5. **Telemetry queue** — needed for cross-SDK analytics
6. **OpenAI HTTP server** — used by desktop / server integrations
7. **JNI bridge** — blocks Kotlin SDK migration
8. **Model paths** — small, widely used
9. **LoRA registry** — small
10. **Lifecycle enum** — small
11. **LLM extensions (tool-calling, structured output, LoRA, KV-cache)** — plugin capability extensions
12. **VLM + diffusion engines** — can defer (new engines not SDK-blocking)
13. **Voice agent state machine** — architectural, can defer

## Migration prerequisites per SDK

- **Swift**: needs core XCFramework containing the gap-closed new core + new error strings + audio utils
- **Kotlin**: needs JNI bridge ported to new ABI (biggest lift)
- **Flutter**: needs FFI bindings regenerated + pre-built native libs per platform
- **React Native**: delegates to Swift + Kotlin, so blocked on those
- **Web**: needs WASM build of new core (already partially working)
