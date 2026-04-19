# Phase 4 — RAG hybrid retriever + neural reranker

> Goal: replace the current single-path RAG retrieval with a parallel
> BM25 + HNSW + Reciprocal Rank Fusion hybrid, plus a neural reranker
> (`bge-reranker-v2-m3`) for top-K precision. Target: top-6 retrieval
> in ≤5 ms at 10,000 chunks on a mobile-class CPU.

---

## Prerequisites

- Phase 2: `embed` streaming primitive exists so the embedding path can
  produce the query vector concurrently with BM25.
- Phase 1: sherpa-onnx plugin exposes `embed` for the ONNX embedding
  model path; llama.cpp plugin exposes `embed` for GGUF embedding models.

---

## What this phase delivers

1. **Parallel hybrid retrieval**:
   ```text
   query ─┬─► BM25Index::search    (std::thread, ~0.01 ms)
          │
          └─► embed → VectorStore::search   (main thread, ~3-5 ms)

   ┌─── join via RRF (k=60) ────┐
   │  BM25 hits + vector hits → fused top-K
   └────────────────────────────┘

                     top-K ──► NeuralReranker → top-k_final
   ```
2. **Zero-alloc hot path** — score buffers pre-allocated at build time,
   reused per query.
3. **`bge-reranker-v2-m3` cross-encoder** as a new L3 primitive alongside
   `embed`. Runs through the llama.cpp plugin (since it wraps a GGUF
   reranker model via the same llama decoder API).
4. **Public RAG API unchanged** — `rac_rag_create_pipeline`,
   `rac_rag_ingest`, `rac_rag_query` keep their signatures; the internals
   swap underneath.
5. **The BC shim at `vector_store_usearch.h:38-44`** (`chunk_id` /
   `similarity` alias fields) is removed.

---

## Exact file-level deliverables

### New files

```text
sdk/runanywhere-commons/include/rac/features/rag/
├── hybrid_retriever.h              NEW — parallel BM25 + vector + RRF
└── neural_reranker.h               NEW — bge-reranker-v2-m3 primitive

sdk/runanywhere-commons/src/features/rag/
├── hybrid_retriever.cpp            NEW
└── neural_reranker.cpp             NEW
```

### Rewritten files

```text
sdk/runanywhere-commons/src/features/rag/
├── rac_rag_pipeline.cpp            REWRITTEN — now calls HybridRetriever
├── rag_backend.cpp                 TRIMMED — single-path retrieval removed
├── bm25_index.cpp                  HARDENED — zero-alloc score buffer, pre-allocated at build_done
└── vector_store_usearch.cpp        TRIMMED — BC alias fields removed
```

### hybrid_retriever.h — the interface

```cpp
namespace ra::features::rag {

struct HybridResult {
    std::uint32_t doc_id;
    float         fused_score;    // RRF score
    float         bm25_score;     // from BM25
    float         vector_score;   // from vector search
};

class HybridRetriever {
public:
    HybridRetriever(const BM25Index*   bm25,
                    const VectorStore* vectors,
                    int                rrf_k = 60);

    // Launches BM25 search on an internal worker thread, runs vector
    // search on the calling thread, joins, fuses.
    std::vector<HybridResult> retrieve(std::string_view  query,
                                        const float*      query_vec,
                                        int               dims,
                                        std::size_t       top_k,
                                        std::vector<float>* scratch = nullptr) const;

private:
    const BM25Index*   bm25_;
    const VectorStore* vectors_;
    int                rrf_k_;
};

} // namespace
```

### bm25_index — hardening

The existing `bm25_index.cpp` (FastVoice reference port) has a shared
`mutable std::vector<float> scratch_scores_`. That's a data race under
concurrent search callers. The hardening:

- Remove the mutable shared buffer.
- `search(query, top_k, scratch)` takes an optional caller-owned
  scratch vector. If null, allocates a local vector per call.
- `build_done()` still pre-computes IDF + freezes the index.
- Idempotent and thread-safe for any number of concurrent readers
  post-`build_done()`.

### neural_reranker

```cpp
class NeuralReranker {
public:
    NeuralReranker(const std::string& model_path, LlmEngine* llm);

    std::vector<RankedDocument> rerank(std::string_view                 query,
                                         std::span<const Document>       candidates,
                                         int                              top_k);
};
```

Internally each (query, candidate) pair becomes an embed call; the
cross-encoder score is the dot product (or a model-specific output
head). The model file is a GGUF variant of bge-reranker-v2-m3.

### rac_rag_pipeline.cpp — rewritten flow

```cpp
ra_status_t rag_query(ra_rag_session_t* session, const char* query_text,
                       RagResult* out, int top_k) {
    // 1) Embed the query
    auto vec = ra::features::embed::one(embed_session, query_text);

    // 2) Hybrid retrieve (BM25 in parallel)
    auto hits = hybrid_retriever.retrieve(query_text, vec.data(),
                                            vec.size(), top_k * 4);

    // 3) Convert hits to Document objects
    std::vector<Document> candidates = hits_to_docs(hits, chunk_store);

    // 4) Neural rerank (optional based on config)
    if (cfg.enable_reranker) {
        candidates = reranker.rerank(query_text, candidates, top_k);
    }

    // 5) Build context + fill output
    return fill_output(out, candidates);
}
```

### Document ingestion chunker

`rag_chunker.cpp` stays as is (234 LOC). Semantic sentence-boundary
chunking is correct. **No `pdftotext` shell-out** (never was in the
current commons, per audit).

### Tests

```text
tests/integration/rag_hybrid_test.cpp
  — builds an index from a 10K-chunk fixture; asserts RRF fused ordering
    differs from BM25-only ordering for ambiguous queries; asserts
    top-6 returned in ≤5 ms on CI runner.

tests/integration/rag_concurrent_search_test.cpp
  — launches 8 threads each calling search() on the same index post-
    build_done; asserts TSan clean, same index returns consistent top-1
    per query.

tests/integration/rag_reranker_test.cpp
  — asserts reranker changes ordering vs RRF-only for a known query
    where BM25+vector misorders but cross-encoder corrects it.
```

### Benchmark

`tools/benchmark/rag_retrieval_latency.cpp` — measures p50/p90/p99
retrieval time across 1K/5K/10K/50K chunks with and without reranker.
CI gate in Phase 6.

---

## Implementation order

1. **Port / harden `BM25Index`**: remove the shared mutable scratch,
   accept caller-owned scratch vector. Verify existing RAG tests still
   pass.

2. **Port / harden `VectorStore`** (`vector_store_usearch.cpp`): delete
   the `chunk_id` / `similarity` BC alias fields on the public struct.
   Update every consumer to use the canonical `doc_id` / `score`.

3. **Write `hybrid_retriever.{h,cpp}`** — parallel BM25 + vector search
   + RRF fusion. Unit-test first.

4. **Integrate `HybridRetriever` into `rac_rag_pipeline.cpp`.** Replace
   the single-path retrieval code block with the new call. Public API
   signatures unchanged.

5. **Write `neural_reranker.{h,cpp}`**. Use the llama.cpp `embed`
   primitive as the underlying engine — `bge-reranker-v2-m3` is a GGUF
   model and llama.cpp handles it.

6. **Add config gate**: `enable_reranker` in the RAG config (defaults
   on iOS/macOS, off on low-RAM Android until memory tuned). Expose
   through the existing `RAGConfig` struct.

7. **Land the three integration tests.** Run under ASan + TSan.

8. **Run the retrieval benchmark** on a macOS-14 CI runner with a
   10K-chunk fixture. Fail the build if p50 > 5 ms.

---

## API changes

### Public (rac_rag.h) — unchanged

`rac_rag_create_pipeline`, `rac_rag_ingest`, `rac_rag_clear_documents`,
`rac_rag_query`, `rac_rag_destroy_pipeline` keep the same signatures.

The `RAGConfig` struct gains:
- `enable_reranker` (bool, default true)
- `rerank_model_id` (string, default "bge-reranker-v2-m3")
- `retrieve_k` (int, default 24) — pre-rerank fan-out
- `rerank_top` (int, default 6)
- `rrf_k` (int, default 60)

In Phase 5 this struct becomes the proto3 `RAGConfig` message.

### Removed

- `vector_store_usearch::chunk_id` (alias for `doc_id`)
- `vector_store_usearch::similarity` (alias for `score`)
- Any single-path retrieval branch inside `rag_backend.cpp`
- The `mutable scratch_scores_` field in `BM25Index`

---

## Acceptance criteria

- [ ] Hybrid retrieval p50 ≤ 5 ms on 10K chunks (CI benchmark).
- [ ] Concurrent 8-thread search: TSan clean.
- [ ] Reranker test: produces different ordering than RRF-only on a
      fixture designed to exercise cross-encoder semantics.
- [ ] `grep -rn "chunk_id\|similarity" sdk/runanywhere-commons/src/features/rag/`
      returns no matches in the aliased sense (the real fields are
      `doc_id` and `score`).
- [ ] `rag_chunker.cpp` unchanged (234 LOC).
- [ ] Public RAG API signatures unchanged; existing SDK callers still
      build against commons.

## Validation checkpoint — **MAJOR**

See `testing_strategy.md`. Phase 4 rewrites retrieval, so quality
checks (not just latency) matter.

- **Retrieval quality on fixed eval set.** A 10K-chunk corpus
  fixture with a 200-query ground-truth set (each query has one
  or more relevant chunk_ids). Post-phase measurements:
  - Recall@10: must equal or exceed the pre-Phase-4 baseline.
  - MRR@10: equal or exceed baseline.
  - Top-1 precision (with reranker): equal or exceed baseline.

  Captured as `tools/benchmark/fixtures/rag_eval_set.json`. Any
  quality regression blocks merge.
- **Latency benchmarks.**
  - Top-6 retrieval over 10K chunks p50 ≤ 5 ms; p90 ≤ 8 ms;
    p99 ≤ 12 ms. Thresholds gated.
  - Reranker cost measured separately; documented in the bench
    output so future tuning has baseline numbers.
- **Concurrent search TSan clean.** 8 concurrent threads calling
  `search()` on the same frozen index — zero race reports.
- **Ingest round-trip.** Ingest the 10-doc fixture, query, receive
  the expected docs, delete, confirm empty. Storage layout
  unchanged from pre-Phase-4.
- **Neural reranker correctness.** `rag_reranker_test` shows a
  case where BM25+vector mis-orders and the reranker corrects it
  (proves the reranker is actually running, not a pass-through).
- **Grep gates for deleted BC aliases.** `chunk_id` / `similarity`
  alias fields gone (Phase 4 did this — reconfirm via
  `grep -rn` in the phase acceptance).
- **Feature preservation.** LLM / STT / TTS / VAD / VoiceAgent
  smokes remain green; RAG change must not have ricocheted into
  other features through shared code.
- **Public RAG API unchanged** — SDK frontends linked against the
  current commons tag still compile. Compile-only smoke against
  a pinned Swift + Kotlin + Dart + TS consumer confirms this.

**Sign-off before Phase 5**: RAG quality eval numbers reviewed by
a second engineer; no silent metric drops.

---

## What this phase does NOT do

- C ABI still carries a C struct `RAGConfig`, not proto3. Phase 5.
- Ingestion pipeline is not rewritten; existing chunker stays.
- No pgvector backend; remains USearch-only.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Reranker model ≈200 MB — breaks tight Android RAM budgets | Medium | `enable_reranker=false` default on Android for now; user-configurable. Re-enable when we land MLX-quantized reranker in a follow-up |
| Parallel BM25 thread has overhead greater than its savings at < 5 K chunks | Low | Measured in FastVoice reference at sub-ms for 5K. Still beneficial because embedding dominates vector-search latency. Benchmark guards |
| Replacing single-path retrieval surfaces hidden differences in score semantics that SDK UIs depend on | Medium | SDKs consume the fused + reranker score; publish the per-component scores (`bm25_score`, `vector_score`) on the result struct so UIs can display them if wanted |
| `bge-reranker-v2-m3` isn't distributed pre-quantized in GGUF | Medium | If not on HF, we ship conversion instructions. Or we use a lighter reranker model (`bge-reranker-v2-gemma-2`). Evaluate before locking in |
| The removal of BC aliases breaks an external SDK adapter we don't control | Low | Commons is consumed only by the 5 SDK frontends in this repo. The frontend migration (out of scope here) reconciles during the next per-frontend phase |
