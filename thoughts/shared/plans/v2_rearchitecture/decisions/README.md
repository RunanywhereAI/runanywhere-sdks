# Decisions index

High-level binding decisions for the commons refactor. Each file here
is a single ADR-style note: the question, the choice, the alternatives
considered, and the reasoning. Anything not listed here is an
implementation detail left to the phase doc.

| # | File | Question | Choice |
| --- | --- | --- | --- |
| 1 | `01_idl_choice.md` | Which IDL for the C ABI wire format? | **proto3** (libprotobuf-lite) |
| 2 | `02_plugin_loading_model.md` | How do engines get loaded? | **dlopen** on macOS/Linux/Android; **static** on iOS/WASM |
| 3 | `03_async_runtime.md` | What does our threading primitive look like per platform? | **std::jthread** on desktop+Android; **GCD** on iOS; **asyncify** on WASM |
| 4 | `04_sanitizers.md` | Which sanitizers are mandatory? | **ASan + UBSan in default Debug**; **TSan in a separate Debug+TSan job** |
| 5 | `05_vector_store.md` | What drives the vector store for RAG? | **USearch (in-process HNSW)**, no pgvector |
| 6 | `06_barge_in_model.md` | How does barge-in work? | **Transactional cancel boundary** under one mutex |
| 7 | `07_backwards_compat.md` | What do we keep compatible? | **Nothing.** Every API can be renamed / removed |
| 8 | `08_scope_boundary.md` | What is in and out of scope? | **commons only**. Frontends / examples in follow-up plans |

All of these have been baked into the MASTER_PLAN binding-decisions
table; these files exist so reviewers can challenge any single choice
without re-reading the whole plan.

The user-facing confirmation list is in `summary_for_user.md` at the
plan root (if present), which flags any decision that might want a
sanity-check from the product owner before execution begins.
