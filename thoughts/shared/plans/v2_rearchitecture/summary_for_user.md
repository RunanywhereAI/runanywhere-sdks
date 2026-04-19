# Summary for review — full-stack refactor plan

> One-page executive view of everything under this directory.

---

## What's written here

```
v2_rearchitecture/
├── MASTER_PLAN.md              one-sentence principle, six-layer arch, 15-phase roadmap
├── current_state.md            inventory of sdk/runanywhere-commons/ today
├── testing_strategy.md         umbrella: feature preservation matrix + per-phase validation template
├── summary_for_user.md         (you are here)
├── decisions/
│   ├── README.md               index of ADRs
│   ├── 01_idl_choice.md        proto3 for the C ABI wire
│   ├── 02_plugin_loading_model.md    dlopen + static dual path
│   ├── 03_async_runtime.md     std::jthread / GCD / asyncify
│   ├── 04_sanitizers.md        ASan+UBSan default; TSan separate
│   ├── 05_vector_store.md      USearch in-process HNSW
│   ├── 06_barge_in_model.md    transactional cancel boundary
│   ├── 07_backwards_compat.md  none kept (no external consumers)
│   └── 08_scope_boundary.md    commons + all 5 SDKs + all example apps in this plan
└── phases/
    ├── phase_0_foundation.md          graph primitives, registry, IDL scaffolding
    ├── phase_1_plugin_backends.md     backends expose ra_plugin_entry
    ├── phase_2_streaming_l3_primitives.md  Stream<T> APIs, callbacks removed
    ├── phase_3_voice_agent_dag.md     streaming DAG + barge-in (≤80 ms first audio)
    ├── phase_4_rag_hybrid.md          BM25 + HNSW + RRF + reranker (≤5 ms @ 10K)
    ├── phase_5_proto3_abi.md          C ABI carries proto3 bytes
    ├── phase_6_sanitizer_ci.md        ASan+UBSan+TSan CI gates
    ├── phase_7_plugin_loading.md      dlopen / static loader impls
    ├── phase_8_cleanup.md             final deletion sweep
    ├── phase_9_swift_sdk.md           Swift SDK + iOS example rewrite
    ├── phase_10_kotlin_sdk.md         Kotlin KMP + Android example + IntelliJ plugin
    ├── phase_11_flutter_sdk.md        Flutter SDK + Flutter example
    ├── phase_12_react_native_sdk.md   RN SDK (TurboModules + JSI) + RN example
    ├── phase_13_web_sdk.md            Web SDK (WASM + optional WebGPU) + web example
    └── phase_14_release_and_infra.md  coordinated v2.0.0 release; top-level CI
```

Total plan: ≈ 6,000 lines of markdown across 15 phase docs + 8
decisions. Each phase doc is self-contained.

---

## The principle in one sentence

**The C++ core already holds the real business logic; this refactor
makes it easier to extend, easier to reason about, and faster at
runtime — in place, without breaking any feature, without keeping
any deprecated API — and then every SDK frontend and example app
moves onto the new architecture in lock-step.**

---

## What you get after all 15 phases

1. **Streaming voice agent** — end-of-utterance to first audible
   sample ≤80 ms on M-series MacBook. Today: seconds, no barge-in.
2. **Transactional barge-in** — single-mutex atomic cancel boundary
   tested under TSan.
3. **Hybrid RAG** — BM25 + HNSW + RRF + `bge-reranker-v2-m3`. Top-6
   retrieval ≤5 ms at 10K chunks.
4. **Plugin-based backends** — llama.cpp, whisper.cpp, sherpa-onnx,
   MetalRT, WhisperKit each live behind a single
   `ra_plugin_entry_<name>` vtable. Dynamic on macOS/Linux/Android,
   static on iOS/WASM.
5. **proto3 at the C ABI** — every event / config / status carries
   length-prefixed proto3 bytes. Every SDK gets generated types from
   the same schema.
6. **Streaming-native SDKs** across all five languages:
   - Swift 6 actors + AsyncSequence
   - Kotlin coroutines + Flow
   - Dart async* generators
   - TypeScript async iterables (RN + Web)
7. **Coordinated v2.0.0 release** — all six artifacts published
   together (SPM, Maven Central, pub.dev, npm×2, GH release).
8. **Benchmark + sanitizer gates** on every commons PR.
9. **Clean codebase** — no `rac_service_registry`, no callback
   adapters, no BC alias fields, no stub-returning-false paths.

Every feature we have today survives: LLM inference, STT, TTS, VAD,
VLM, diffusion, wake word, model download, extraction, observability,
OpenAI HTTP server. Each is reachable from every frontend.

---

## Ordering — what blocks what

- **Phases 0–8 (commons)** are strictly sequential. Each blocks the
  next.
- **Phase 8 blocks all frontend phases.** Commons must be stable
  before any frontend migrates.
- **Phase 9 (Swift) + Phase 10 (Kotlin) unblock Phase 12 (RN)**
  because RN delegates to both native SDKs.
- **Phase 11 (Flutter) + Phase 13 (Web)** can start as soon as
  commons is done — they don't depend on other frontends.
- **Phase 14 is last.** The coordinated v2.0.0 release happens only
  after every SDK has its own green CI.

---

## Rough effort estimate

Engineer-days, single thread:

| Track | Phases | Effort |
| --- | --- | --- |
| Commons | 0–8 | ≈ 55 d |
| Swift | 9 | ≈ 15 d |
| Kotlin (KMP) | 10 | ≈ 18 d |
| Flutter | 11 | ≈ 12 d |
| React Native | 12 | ≈ 12 d |
| Web | 13 | ≈ 14 d |
| Release + infra | 14 | ≈ 5 d |
| **Total** | | **≈ 131 d** |

With two engineers splitting frontend phases 9–13 in parallel after
Phase 8 lands: **≈ 90 calendar days**.

---

## Still open before execution

All three blockers you originally flagged are resolved:

- **proto3 runtime (~300 KB)**: you confirmed acceptable.
- **No external C ABI consumers**: you confirmed none outside the
  monorepo, so we break freely.
- **Scope**: you expanded the plan to include all five frontends +
  example apps in the same execution window.

No remaining decisions need your sign-off before Phase 0 can start.

---

## Testing discipline (new)

Every phase now has an explicit **Validation checkpoint** section
pointing back to `testing_strategy.md`. The umbrella doc defines:

- A **feature preservation matrix** — every LLM / STT / TTS / VAD /
  VLM / diffusion / wake-word / RAG / voice-agent / server endpoint
  that exists today. Every phase boundary must re-run these smokes.
- A **C++ validation template** for phases 0–8 — build under
  ASan+UBSan and TSan, run feature-preservation smokes via a
  dev-CLI, diff outputs against a pre-refactor baseline, benchmark
  thresholds gated.
- A **frontend validation template** for phases 9–13 — actual
  compilation + lint must be green, example app must build + run,
  warnings fixed in-PR (no deferrals to cleanup phases).
- A **regression protocol** — if a checkpoint fails we revert, root
  cause, and add a new check, rather than stacking fixes.

Major phase checkpoints (1, 2, 3, 4, 5, 8, and each frontend phase
9–13) additionally require a second-engineer sign-off on the
feature preservation matrix before moving forward.

The dev-CLI — introduced as a stub in Phase 0, filled in across
Phases 1–4 — becomes the swiss army knife for running every
feature smoke in under 30 seconds. By Phase 8 every row of the
preservation matrix has a matching `ra-cli <verb>` subcommand.

---

## If you approve — what starts first

Phase 0 lays the foundation in commons: ABI headers, graph
primitives, plugin registry stubs, IDL scaffolding, CMake + sanitizer
wiring, **and the dev-CLI scaffolding** used to smoke features at
every later checkpoint. No existing code modified; baseline
feature-preservation outputs are captured from the pre-Phase-0
state and committed into `tests/fixtures/expected/` so every later
phase can diff against them.

If you'd like to dig into any single phase before we start, the docs
are designed to stand alone — just point me at the phase number.
