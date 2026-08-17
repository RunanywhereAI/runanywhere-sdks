# Commons subsystems reference

Deep-dive detail for the core subsystems, split out of `AGENTS.md` because it is only needed
when you are actually working inside one of these subsystems, not for every task in the module.
See `AGENTS.md` for the one-line orientation and when to come here.

## Lifecycle Manager (`src/core/capabilities/lifecycle_manager.cpp`)

The `rac_lifecycle_*` C API is a thin per-handle facade over the canonical global `g_loaded`
store (`src/core/model_lifecycle.cpp`), not a separate state machine. A `LifecycleManager` owns
no model state, only its config, per-handle metrics, and a pin token. `load()` calls the feature
module's own `create_fn` (path-based, with no registry lookup and no download) and stores the
resulting `rac_<mod>_service_t` into `g_loaded`; the single store/pin is `g_loaded` +
`LoadedModel::active_refs` + `g_lifecycle_cv`. Every facade op is **owner-scoped** (only touches
the `g_loaded[component]` slot whose `owner_lifecycle` is this handle), so destroying a
never-loaded component handle never evicts a user's registry-loaded model. State maps
READY→LOADED, ERROR→FAILED. `get_state`/`get_service` take `g_lifecycle_mutex` briefly (never
held across model creation). Auto-unload of a previous model drains in-flight refs via
`g_lifecycle_cv` before destroying. Under `#if !defined(RAC_HAVE_PROTOBUF)` (no `g_loaded`), the
original self-contained per-handle implementation is retained verbatim.

## Model registry and paths

- `rac_model_registry_t`: CRUD for model metadata; `discover_downloaded()` scans filesystem;
  `refresh()` combines remote catalog + local rescan + orphan pruning.
- `rac_model_paths_t`: all paths follow `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`.
- `rac_lora_registry_t`: LoRA adapter entries with compatible model ID matching.
- Model assignment (`rac_model_assignment_*` functions in `model_assignment.cpp`) fetches
  device-assigned models from the backend API with a TTL cache. Function-based API; there is no
  `rac_model_assignment_t` handle type.

## Download manager (`include/rac/infrastructure/download/rac_download_orchestrator.h`)

Orchestration (not HTTP transport). Stages: `DOWNLOADING` (0-80%) → `EXTRACTING` (80-95%) →
`VALIDATING` (95-99%) → `COMPLETED` (100%). HTTP delegated to `rac_http_download` (platform
adapter).

## Error categories (`include/rac/core/rac_structured_error.h`)

SDK-facing errors cross the boundary as `runanywhere.v1.SDKError` proto bytes through
`rac_result_to_proto_error()`, the canonical single error path. `rac_structured_error.h` now
holds only the `rac_error_category_t` taxonomy (`RAC_CATEGORY_*`), mapped onto the proto
`ErrorCategory` by `rac_proto_adapters`. The old structured-error subsystem (`rac_error_t`,
stack-trace capture, thread-local last-error, `rac_error_log_and_track`, the bespoke JSON /
`rac::Error` surface) was retired because it had no remaining callers once the proto path became
canonical. Per-result message/expectedness lookups live in `rac_error.cpp`
(`rac_error_message`, `rac_error_is_expected`).

For the numeric error code ranges (`-100` to `-799`), see `docs/DEVELOPMENT.md#error-codes` —
that table is canonical, do not fork a second copy.

## Logging

Atomic level-check on hot path (no mutex). `RAC_LOG_TRACE/DEBUG/INFO/WARNING/ERROR/FATAL` macros
skip `vsnprintf` entirely when level is filtered. Pre-init: falls back to stderr.
Per-environment defaults: dev=DEBUG, staging=INFO, prod=WARNING.

## RAG (`src/features/rag/`)

Hybrid retrieval-augmented generation behind the proto-byte C ABI `rac_rag_*`
(`include/rac/features/rag/rac_rag.h`). Query flow: `rac_rag_query_proto` → `RAGBackend::query`
(`rag_backend.cpp`) → `run_rag_query` (`rag_pipeline_graph.cpp`): embed query → USearch
dense search → BM25 keyword search → RRF fusion (`kRRFConstant=60`) → context assembly
(token budget) → prompt format → streaming LLM generate. Ingest: `rac_rag_ingest_proto` →
`RAGBackend::add_document`: recursive char-chunk → batch embed → USearch + BM25 insert.
Dense store is USearch HNSW (`vector_store_usearch.cpp`), sparse store is a hand-rolled
Okapi BM25 inverted index (`bm25_index.cpp`). Per-session `RAGBackend` guarded by a single
`mutex_`; the graph runs outside the lock. Multi-session; each handle independent.

### Design rules for RAG work (do not relitigate)

- Keep USearch as the dense ANN store. Do not replace it with a brute-force
  Hamming/binary-quantized scan. Techniques may be borrowed from reference engines, the
  storage engine is not.
- RAG's default rerank is LLM-pointwise (score fused candidates 1 to 5 with the existing
  LLM handle) and is the only reranking path wired into the RAG query flow today. The
  first-class `RAC_PRIMITIVE_RERANK` cross-encoder primitive (`rerank_ops`, revived in plugin
  ABI v8) exists and is reachable standalone through `rac_rerank_*`, but it is not yet invoked
  from the RAG query path: `RAGBackend`/`rag_pipeline_graph` do not score fused candidates
  through it. Until that wiring lands, `rac_rag_proto_abi` **rejects** a `reranker_model_id`
  at session-create with `RAC_ERROR_NOT_IMPLEMENTED` (rather than accepting it and silently
  no-op'ing); callers wanting reranking today use `rerank_results` (LLM-pointwise). With no
  `reranker_model_id` the default fusion path is unchanged.
- All RAG persistence goes through the platform adapter file I/O
  (`file_read`/`file_write`/`file_delete`/`file_exists`, `rac_platform_adapter.h`), never
  direct `std::ofstream`/`fopen`. This is what makes persistence work on Web (OPFS) as well
  as mobile.
- Content-addressed dedup: never re-embed the same input. Documents are keyed by
  `sha256(raw_bytes)` (files) or `sha256(normalized_text)` (text); chunk embeddings are
  cached by `sha256(chunk_text) + embedding_model_fingerprint`. A matching hash + matching
  fingerprint skips chunking/embedding. Embedding caches are namespaced by embedding
  fingerprint, so switching models is safe and reversible.
- SHA-256 is the shared foundation util `src/foundation/rac_sha256`. Do not add a
  second SHA-256 implementation (the old file-local one in `rac_http_download.cpp` is being
  consolidated here).
- Persisted indexes are fingerprint-guarded (embedding model + dim + format version).
  On mismatch, discard and re-embed; never load stale vectors against a different embedder.
- Proto changes to `idl/rag.proto` are additive only (new optional fields); regenerate
  all SDK bindings, no version bump.
