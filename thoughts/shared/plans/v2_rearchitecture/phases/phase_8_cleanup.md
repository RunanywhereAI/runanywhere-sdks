# Phase 8 — Cleanup sweep and deprecation removal

> Goal: the final sweep. Anything that's been marked `DELETE-NOW` or
> `DELETE-AFTER-PHASE-N` across Phases 0–7 gets physically removed.
> Any shim, stub, or back-compat alias left behind for staged
> migration is deleted. The result is the codebase we'd have if we
> wrote commons from scratch with the new architecture from day one.

---

## Prerequisites

- Phase 0–7 merged to main.
- Every feature has a passing integration test under ASan, UBSan, and
  TSan.
- Benchmark thresholds have been stable for at least one release
  cycle.

---

## What this phase delivers

1. **Dead symbol sweep** — grep-and-delete for every placeholder the
   earlier phases left behind:
   - `rac_service_registry` and all related ServiceRegistry API calls
     (replaced by `PluginRegistry` in Phase 1).
   - `rac_module_register`, `rac_service_create`,
     `rac_service_register_provider` call sites.
   - `rac_backend_*_register.cpp` files (the 6 per-backend registrar
     files — Phase 1 emptied them; this phase deletes them).
   - BC alias fields: `vector_store_usearch.h:38-44` (`chunk_id`,
     `similarity`) — already gone as of Phase 4, this phase verifies.
   - `mutable std::vector<float> scratch_scores_` in `BM25Index` — Phase 4.
   - Any remaining `rac_llm_generate(..., callback, ...)` or other
     callback-based primitives — Phase 2 marked dead, delete now.
   - `ra_token_callback_t`, `ra_audio_callback_t`, etc., C ABI
     callback function-pointer typedefs — Phase 2.
   - MetalRT stub paths that always returned `RA_STATUS_UNIMPLEMENTED`
     on non-Apple chips — replaced by Phase 1 capability_check.
   - Wake word stub from `wakeword_service.cpp:210,233,477-498`
     (fixed in Phase 1; confirm the old stub is gone).

2. **Deprecated public headers removed:**
   ```text
   include/rac/features/llm/rac_llm_service.h    DELETED
   include/rac/features/stt/rac_stt_service.h    DELETED
   include/rac/features/tts/rac_tts_service.h    DELETED
   include/rac/features/vad/rac_vad_service.h    DELETED
   include/rac/features/rag/rac_rag_pipeline.h   KEPT (still public)
   ```
   The `rac_*_service.h` families were pre-streaming helpers; the
   public surface is now the `ra_*_abi.h` C ABI and the `ra::features::*`
   C++ types, nothing in between.

3. **Legacy `rac_` prefix renamed to `ra_`** across the entire public
   surface. (Phase 5 reshaped the types but kept the prefix naming
   schema. This phase commits the rename.)

4. **Directory reorganisation** settles into the target layout:
   ```text
   sdk/runanywhere-commons/
   ├── idl/                       ← proto3 sources (Phase 0 + 5)
   ├── include/rac/
   │   ├── abi/                   ← C ABI + proto encode/decode
   │   ├── core/                  ← graph / stream / pool / cancel
   │   ├── registry/              ← plugin + engine registry
   │   ├── router/                ← HardwareProfile + EngineRouter
   │   └── features/              ← LLM / STT / TTS / VAD / …
   ├── src/
   │   ├── abi/                   ← C ABI shims
   │   ├── core/
   │   ├── registry/
   │   ├── router/
   │   ├── features/
   │   ├── gen/                   ← generated protobuf (gitignored)
   │   └── bindings/jni/          ← commons-side JNI
   ├── plugins/                   ← one subdir per backend
   │   ├── llamacpp/
   │   ├── whispercpp/
   │   ├── sherpa_onnx/
   │   ├── metalrt/
   │   └── whisperkit_coreml/
   ├── tests/
   │   ├── core_tests/
   │   └── integration/
   ├── tools/
   │   ├── benchmark/
   │   ├── ci/
   │   └── dev-cli/
   ├── cmake/
   │   ├── PluginSystem.cmake
   │   ├── Protobuf.cmake
   │   └── Sanitizers.cmake
   ├── CMakeLists.txt
   ├── CMakePresets.json
   └── vcpkg.json
   ```

5. **Final doc pass** — `README.md` rewritten to describe the new
   architecture; `ARCHITECTURE.md` (new) at the commons root linking
   each layer (L1–L6) to its directory; `plugins/<name>/README.md`
   describing how to author a new backend.

---

## Exact file-level deliverables

### Deletions

```text
# Service registry (superseded by plugin registry)
src/core/rac_service_registry.cpp                  DELETE
src/core/rac_service_registry.h                    DELETE
src/core/rac_module_register.cpp                   DELETE
include/rac/core/rac_service_container.h           DELETE
src/core/rac_service_container.cpp                 DELETE

# Per-backend legacy registrar files (Phase 1 cleared bodies; delete)
src/backends/llamacpp/rac_backend_llamacpp_register.cpp   DELETE
src/backends/whispercpp/rac_backend_whispercpp_register.cpp DELETE
src/backends/onnx/rac_backend_onnx_register.cpp           DELETE
src/backends/metalrt/rac_backend_metalrt_register.cpp     DELETE
src/backends/whisperkit_coreml/rac_backend_whisperkit_register.cpp DELETE

# Pre-Phase-2 callback plumbing (if any bytes remain)
src/features/llm/llm_callback_adapter.cpp          DELETE
src/features/stt/stt_callback_adapter.cpp          DELETE
src/features/tts/tts_callback_adapter.cpp          DELETE
src/features/vad/vad_callback_adapter.cpp          DELETE

# Pre-Phase-3 batch voice agent
src/features/voice_agent/voice_agent_batch_loop.cpp DELETE

# Any .bak / .old files left from branch work
src/**/*.bak                                        DELETE
src/**/*.old                                        DELETE
```

After the deletes, search via grep for any call site that still
references the deleted symbols — fail the build if any exists.

### Renames (rac_ → ra_)

The rename is mechanical but not trivial because `rac` could be a
substring match in third-party code. Do it in two steps:

1. Rename the **files** that still carry the `rac_` prefix:
   ```text
   include/rac/features/rag/rac_rag_pipeline.h  →  include/rac/features/rag/ra_rag_pipeline.h
   src/features/rag/rac_rag_pipeline.cpp        →  src/features/rag/ra_rag_pipeline.cpp
   …etc for every surviving rac_* file…
   ```
2. Rename the **symbols** inside those files with a scoped
   `sed`-style rewrite that only touches `rac_` at word boundaries:
   `\brac_[a-z]` → `ra_[a-z]`.

The `rac/` *directory name* under `include/` is kept for historical
familiarity (and because changing it invalidates every `-I` flag
across the frontend SDKs); it becomes a namespace-style path under a
filename scheme of `ra_*`.

### Renames: prefix `rac::` → `ra::` for C++ namespaces

The C++ side of the codebase uses namespaces `ra::core`, `ra::abi`,
etc., and some older code still has a top-level `rac::` namespace from
pre-refactor days. Fold `rac::foo` into `ra::foo` via `using ra::foo =
rac::foo;` for a week, then delete the `rac::` namespace entirely
once downstream SDK frontends have migrated. (That migration is out
of scope for this commons-only plan; we coordinate the rename window
with the frontend teams in a follow-up.)

### Docs

```text
sdk/runanywhere-commons/README.md                 REWRITE
sdk/runanywhere-commons/ARCHITECTURE.md           NEW
sdk/runanywhere-commons/CONTRIBUTING.md           UPDATED
sdk/runanywhere-commons/plugins/README.md         NEW — how to author a plugin
sdk/runanywhere-commons/idl/README.md             NEW — IDL guidelines
sdk/runanywhere-commons/docs/                     NEW
  ├── layered_architecture.md
  ├── plugin_authoring.md
  ├── streaming_primitives.md
  ├── voice_agent_dag.md
  ├── rag_hybrid_retrieval.md
  └── proto3_wire_format.md
```

`ARCHITECTURE.md` is the single-entry-point doc a new engineer lands
on; it's kept tight (≤200 lines) and links out to `docs/` for depth.

### Final CMake consolidation

- Remove any `CMakeLists.txt` left dangling under deleted folders.
- Consolidate the in-tree `deps/` / `external/` / `third_party/`
  directory usage — settle on one naming (`external/`) and move the
  others.
- Remove any hand-rolled `FindXXX.cmake` modules if vcpkg now provides
  them.

### Tests added in this phase

```text
tests/integration/deprecation_sweep_test.cpp
  — a compile-only test that tries to #include each of the deleted
    headers; CMake build fails if any remain. Negative test.
```

This is a belt-and-braces check; the primary check is the grep gate
in acceptance criteria.

---

## Implementation order

1. **Grep every deleted-symbol name** across the repo. Build a hit
   list. Triage — is the remaining reference in tests? In a backend?
   In docs? Adjust.

2. **Delete the pointed-at files** in one commit per logical group
   (service registry, callback adapters, etc.). Each commit is
   independent and bisectable.

3. **Run the full test matrix (ASan+UBSan, TSan, bench) after each
   commit.** If a bench regresses, stop — the "dead" code may have
   held a live side effect.

4. **Rename `rac_*` files to `ra_*`** in one mechanical commit using
   `git mv`. Follow with an edit commit that renames the symbols
   inside.

5. **Fold `rac::` namespace into `ra::`** with a one-week alias
   grace period (aliased `using` declarations); after one release
   cycle, delete the `rac::` declarations.

6. **Directory shuffle** into the target layout. Keep the individual
   moves as separate commits to ease reviewing.

7. **Doc pass.** Write `ARCHITECTURE.md` top-down from the layered
   design. Write each `docs/*.md` against the matching phase plan.

8. **Final acceptance sweep.** Green CI, green sanitizers, green
   benchmarks, zero hits for every banned symbol.

---

## API changes

### Removed (final)

- Every symbol on the DELETE list above.
- Every header file in the DELETE list.
- The `rac::` C++ namespace.
- The `rac_*` C function prefix (renamed to `ra_*`).

### Renamed

- Files: `rac_*` → `ra_*` (file name schema).
- Symbols: `rac_foo_bar` → `ra_foo_bar`.
- Namespaces: `rac::X` → `ra::X`.

### Added

None. This phase only deletes and renames.

---

## Acceptance criteria

- [ ] `grep -rn "rac_service_registry\|rac_module_register\|rac_service_create" sdk/runanywhere-commons/`
      returns empty.
- [ ] `grep -rn "ra_token_callback_t\|ra_audio_callback_t\|ra_vad_callback_t" sdk/runanywhere-commons/include/`
      returns empty.
- [ ] `grep -rn "chunk_id\|similarity" sdk/runanywhere-commons/src/features/rag/ --include="*.h" --include="*.cpp"`
      returns only uses of the canonical `doc_id` and `score` fields
      (which don't match these patterns).
- [ ] `find sdk/runanywhere-commons -name 'rac_*.cpp' -o -name 'rac_*.h'` returns empty.
- [ ] `ctest --preset commons-asan-ubsan` green.
- [ ] `ctest --preset commons-tsan` green.
- [ ] Benchmark gate green.
- [ ] `ARCHITECTURE.md` reviewed by at least two maintainers.
- [ ] `README.md` rewritten.
- [ ] Size of `sdk/runanywhere-commons/` measured: LOC count
      dropped ≥ 15 % vs pre-refactor baseline (the baseline was
      captured in `thoughts/shared/plans/v2_rearchitecture/current_state.md`).
- [ ] Every public header under `include/rac/` compiles in isolation
      (no hidden transitive `#include` deps) — enforced by a
      `headers_compile_standalone_test`.

## Validation checkpoint — **MAJOR**

See `testing_strategy.md`. Phase 8 closes the commons track —
this checkpoint is the final commons sign-off before frontends
begin migrating. Exhaustive:

- **Full feature preservation matrix, final run.** Every row green.
  Diffed against the pre-refactor baseline captured before Phase 0.
  No row shows a regression.
- **Benchmark suite, final run.** Every threshold green within
  tolerance. Record the post-refactor numbers as the new baseline
  for future PRs.
- **Sanitizer suite, final run.** ASan + UBSan + TSan green with
  zero new suppressions compared to Phase 6 baseline.
- **Deletion grep sweep.** Every banned symbol returns empty.
  Every deleted file actually gone.
- **Directory layout matches the target.** Tree in the phase doc's
  file-level deliverables section is what's on disk.
- **LOC budget.** At least 15 % LOC drop vs pre-refactor inventory
  (see `current_state.md`); if under, document why.
- **Headers compile-standalone.** `headers_compile_standalone_test`
  green.
- **Dev-CLI feature coverage.** Every feature matrix row has a
  matching `ra-cli <verb>` subcommand; running them all in a
  script exits 0.
- **Build matrix.** macOS + Linux + Android + iOS + WASM all green
  from a clean clone in ≤ 20 minutes each on CI.
- **Documentation.** `ARCHITECTURE.md` + `docs/*.md` published;
  reviewed by two maintainers.
- **Human sign-off.** Two maintainers check off explicitly before
  Phase 9 (Swift SDK) starts. Nothing regresses silently on the
  frontend tracks because commons settled on known-good.

---

## What this phase does NOT do

- No behavioural change. By the time this phase lands, every feature
  already runs on the new architecture; this is pure janitorial work.
- No frontend SDK cleanup. The Kotlin / Swift / Dart / TS / Web SDKs
  still contain their own pre-refactor code; that's handled by the
  per-frontend follow-up plans.
- No example-app cleanup. `examples/` still references old API
  shapes; per-app follow-up work.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| A deletion accidentally removes a symbol still imported by a frontend SDK JNI bridge | Medium | The commons-side JNI stubs under `src/bindings/jni/` are migrated in Phase 2 / 5 / 7 as features come online. Before the delete sweep, grep the JNI stubs; if any still reference a doomed symbol, the feature wasn't fully migrated and the delete is premature |
| Rename `rac_ → ra_` accidentally hits an unrelated `rac` substring | Medium | Use word-boundary regex (`\brac_`), not naked substring. CI compile gate catches any false positive because the symbol stops resolving |
| Directory shuffle breaks existing IDE projects / include paths | Low | Keep the `-I include/rac` root; only moving files inside. IDE project files (if any committed) regenerated |
| LOC drop target of 15 % not met because some rewrites are longer than what they replaced | Low | The target is a sanity check, not a contract. If we're at +5 % because streaming made the code slightly longer but markedly clearer, that's fine — note in the PR description and waive the target |
| `headers_compile_standalone_test` flags decades-old transitive includes that break when a neighbour header moves | Medium | Fix properly — add the missing `#include`s. This is exactly the hygiene the test is supposed to enforce |
| Some symbol grep gate returns a false positive because a comment or a string literal mentions the symbol | Low | Grep gate is scoped to source files and excludes `docs/`, `README*.md`, `CHANGELOG.md`. Real leaks still caught |

---

## After this phase

Commons is done. The next plans live under
`thoughts/shared/plans/frontend_rearchitecture/` and handle:

- Kotlin / Swift / Dart / TS frontend SDKs consuming the new C ABI
  via the generated proto types.
- Example apps.
- Top-level `scripts/` and `tools/` tidy-up.

Commons at that point is a stable foundation. Further changes to it
go through the normal feature-development workflow, not a multi-phase
migration plan.
