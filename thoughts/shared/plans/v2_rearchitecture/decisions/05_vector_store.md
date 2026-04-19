# Decision 05 — RAG vector store

## Question

What drives the dense vector index for RAG?

## Choice

**USearch** as the in-process HNSW index. No server backend.

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| pgvector (Postgres) | Requires a Postgres server; offline / mobile viable = 0; our runtime is supposed to run on a laptop and a phone, not a cluster |
| FAISS | BSD-3 is fine but build is heavy; pulls OpenMP + BLAS; porting to iOS/WASM is painful |
| Hand-rolled HNSW | Already available in USearch; reinventing earns us nothing |
| SQLite + brute force | Fine under 1K chunks, falls off a cliff at 10K |
| HNSWLib (nmslib) | Comparable to USearch but less mobile-friendly build story |

## Reasoning

USearch is:

- Header-only + a tiny .cpp; no external deps.
- Already vendored in `sdk/runanywhere-commons/external/usearch`.
- Benchmarked at ≤1 ms for top-10 retrieval on 10K vectors on an M2.
- MIT licensed.
- Works on macOS, Linux, Android arm64, iOS, and WASM — no
  platform-specific #ifdefs needed.
- Author responds to issues.

We don't need a server backend. Our entire value proposition is
"run anywhere, including on-device"; a networked vector DB
contradicts that. If in the future a backend wants to plug in a
remote vector store, the `VectorStore` abstraction is narrow enough
to host it behind a plugin without rewriting RAG.

## Implications

- RAG stays single-library.
- Phase 4 delivers the hybrid retriever (BM25 in parallel + USearch +
  RRF + neural reranker).
- No network dependency for RAG — matches the offline-first product
  stance.
- Storage: USearch ships with its own binary serialisation; we wrap
  it behind `VectorStore::save` / `load` and store the file in the
  same `runanywhere/rag/` app-data directory as the chunk store.
