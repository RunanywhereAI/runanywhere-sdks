# Phase 6 — Sanitizers, benchmarks, and CI gates

> Goal: every Phase 0–5 deliverable has a CI gate that *proves* it
> stayed correct. ASan + UBSan + TSan run on the full integration
> suite. Latency / memory benchmarks gate on regression thresholds.

---

## Prerequisites

- Phase 0–5 complete: plugin registry, streaming primitives, voice
  agent DAG, hybrid RAG, proto3 ABI are all in place and each ships
  its own integration tests.
- A macOS runner image and a Linux runner image available in GitHub
  Actions (we already use both for the existing SDK workflows).

---

## What this phase delivers

1. **Three CI matrix jobs for commons:**
   - `commons-asan-ubsan` — Debug build with `-fsanitize=address,undefined`,
     runs every integration test.
   - `commons-tsan` — Debug build with `-fsanitize=thread`, runs the
     concurrency-heavy tests (voice agent, RAG concurrent search, ABI
     stream pump, graph scheduler).
   - `commons-release-bench` — Release build, runs
     `tools/benchmark/*` and fails if any p50 / p99 metric regresses
     past its threshold file.

2. **A benchmark threshold system** under
   `tools/benchmark/thresholds/` — one JSON file per benchmark with
   `p50_ms`, `p90_ms`, `p99_ms` ceilings. Thresholds live in git and
   are bumped through normal code review when a legitimate regression
   is accepted.

3. **A single reusable CMake preset** per sanitizer mode so any
   engineer can run the exact CI configuration locally:

   ```text
   cmake --preset commons-asan-ubsan
   cmake --preset commons-tsan
   cmake --preset commons-release-bench
   ```

4. **Artifacts uploaded on failure** — sanitizer reports (.txt),
   benchmark JSON, core dumps where the runner retains them.

5. **One workflow file** per job, path-filtered so a change under
   `sdk/runanywhere-commons/**` is the only trigger. Existing
   per-SDK workflows unchanged.

---

## Exact file-level deliverables

### CMake presets

`sdk/runanywhere-commons/CMakePresets.json` (new):

```json
{
  "version": 4,
  "configurePresets": [
    {
      "name": "commons-asan-ubsan",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/asan-ubsan",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "CMAKE_CXX_STANDARD": "20",
        "RA_ENABLE_ASAN":  "ON",
        "RA_ENABLE_UBSAN": "ON",
        "RA_ENABLE_TESTS": "ON"
      }
    },
    {
      "name": "commons-tsan",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/tsan",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "CMAKE_CXX_STANDARD": "20",
        "RA_ENABLE_TSAN":  "ON",
        "RA_ENABLE_TESTS": "ON"
      }
    },
    {
      "name": "commons-release-bench",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/release-bench",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Release",
        "CMAKE_CXX_STANDARD": "20",
        "RA_ENABLE_BENCHMARKS": "ON"
      }
    }
  ],
  "buildPresets": [
    { "name": "commons-asan-ubsan",    "configurePreset": "commons-asan-ubsan" },
    { "name": "commons-tsan",          "configurePreset": "commons-tsan" },
    { "name": "commons-release-bench", "configurePreset": "commons-release-bench" }
  ],
  "testPresets": [
    { "name": "commons-asan-ubsan",    "configurePreset": "commons-asan-ubsan",   "output": {"outputOnFailure": true} },
    { "name": "commons-tsan",          "configurePreset": "commons-tsan",         "output": {"outputOnFailure": true} }
  ]
}
```

### Sanitizer CMake fragment

`cmake/Sanitizers.cmake` (introduced as a stub in Phase 0, wired here):

```cmake
option(RA_ENABLE_ASAN       "Enable AddressSanitizer"     OFF)
option(RA_ENABLE_UBSAN      "Enable UndefinedBehaviorSan" OFF)
option(RA_ENABLE_TSAN       "Enable ThreadSanitizer"      OFF)

function(ra_apply_sanitizers TARGET)
    if(RA_ENABLE_TSAN AND (RA_ENABLE_ASAN OR RA_ENABLE_UBSAN))
        message(FATAL_ERROR "TSan is exclusive; cannot combine with ASan/UBSan")
    endif()

    set(_flags "")
    if(RA_ENABLE_ASAN)
        list(APPEND _flags -fsanitize=address -fno-omit-frame-pointer)
    endif()
    if(RA_ENABLE_UBSAN)
        list(APPEND _flags -fsanitize=undefined
                           -fno-sanitize-recover=undefined
                           -fsanitize=float-divide-by-zero
                           -fsanitize=implicit-conversion
                           -fsanitize=local-bounds
                           -fsanitize=nullability)
    endif()
    if(RA_ENABLE_TSAN)
        list(APPEND _flags -fsanitize=thread -fno-omit-frame-pointer)
    endif()

    if(_flags)
        target_compile_options(${TARGET} PRIVATE ${_flags})
        target_link_options(${TARGET}    PRIVATE ${_flags})
    endif()
endfunction()
```

`ra_apply_sanitizers(runanywhere_commons)` is called unconditionally
in the root `CMakeLists.txt`; it's a no-op when none of the options
are on.

### Sanitizer runtime configuration

`tools/ci/sanitizer-suppressions/asan.supp` — empty for now, grows as
we discover genuine third-party leaks (e.g. inside a model runtime we
can't patch).

`tools/ci/sanitizer-suppressions/tsan.supp`:

```text
# USearch library accesses std::unordered_map in a read-mostly way —
# false positive; we guard ourselves with a shared_mutex.
race:usearch::

# Protobuf internal singleton init — protobuf's own init races are
# well-known and benign.
race:google::protobuf::internal::OnShutdownDestroyString
```

`tools/ci/sanitizer-suppressions/ubsan.supp`:

```text
# Third-party header-only libs that upcast void* to float*; safe.
alignment:external/usearch/
```

These suppression files are passed via
`ASAN_OPTIONS=suppressions=...`, `TSAN_OPTIONS=...`,
`UBSAN_OPTIONS=...` in the CI workflow.

### GitHub workflows

`.github/workflows/commons-sanitizers.yml` (new):

```yaml
name: commons-sanitizers

on:
  pull_request:
    paths: ['sdk/runanywhere-commons/**']
  push:
    branches: [main]
    paths: ['sdk/runanywhere-commons/**']

jobs:
  asan-ubsan:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Setup vcpkg
        run: ./tools/ci/setup-vcpkg.sh
      - name: Configure
        working-directory: sdk/runanywhere-commons
        run: cmake --preset commons-asan-ubsan
      - name: Build
        working-directory: sdk/runanywhere-commons
        run: cmake --build --preset commons-asan-ubsan
      - name: Test
        working-directory: sdk/runanywhere-commons
        env:
          ASAN_OPTIONS: "suppressions=${{github.workspace}}/tools/ci/sanitizer-suppressions/asan.supp:halt_on_error=1:detect_leaks=1"
          UBSAN_OPTIONS: "suppressions=${{github.workspace}}/tools/ci/sanitizer-suppressions/ubsan.supp:print_stacktrace=1:halt_on_error=1"
        run: ctest --preset commons-asan-ubsan --output-on-failure
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: asan-ubsan-logs
          path: sdk/runanywhere-commons/build/asan-ubsan/Testing/**/*.log

  tsan:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: ./tools/ci/setup-vcpkg.sh
      - working-directory: sdk/runanywhere-commons
        run: cmake --preset commons-tsan
      - working-directory: sdk/runanywhere-commons
        run: cmake --build --preset commons-tsan
      - name: Test
        working-directory: sdk/runanywhere-commons
        env:
          TSAN_OPTIONS: "suppressions=${{github.workspace}}/tools/ci/sanitizer-suppressions/tsan.supp:halt_on_error=1:second_deadlock_stack=1"
        run: ctest --preset commons-tsan --output-on-failure
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: tsan-logs
          path: sdk/runanywhere-commons/build/tsan/Testing/**/*.log
```

`.github/workflows/commons-bench.yml` (new):

```yaml
name: commons-bench

on:
  pull_request:
    paths: ['sdk/runanywhere-commons/**']
  push:
    branches: [main]
    paths: ['sdk/runanywhere-commons/**']

jobs:
  bench:
    runs-on: macos-14-large   # larger, more deterministic
    steps:
      - uses: actions/checkout@v4
      - run: ./tools/ci/setup-vcpkg.sh
      - working-directory: sdk/runanywhere-commons
        run: cmake --preset commons-release-bench
      - working-directory: sdk/runanywhere-commons
        run: cmake --build --preset commons-release-bench
      - name: Run benchmarks
        working-directory: sdk/runanywhere-commons
        run: |
          ./build/release-bench/tools/benchmark/voice_agent_latency \
              --fixture tools/benchmark/fixtures/voice_agent.wav \
              --out build/release-bench/voice_agent.json
          ./build/release-bench/tools/benchmark/rag_retrieval_latency \
              --corpus tools/benchmark/fixtures/rag_10k_chunks.bin \
              --out build/release-bench/rag_retrieval.json
          ./build/release-bench/tools/benchmark/abi_encode_cost \
              --out build/release-bench/abi_encode.json
          ./build/release-bench/tools/benchmark/llm_first_token \
              --model tools/benchmark/fixtures/tiny-llama-q4.gguf \
              --out build/release-bench/llm_first_token.json
      - name: Gate against thresholds
        working-directory: sdk/runanywhere-commons
        run: python tools/ci/check_thresholds.py \
                 --results build/release-bench \
                 --thresholds tools/benchmark/thresholds
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: benchmark-results
          path: sdk/runanywhere-commons/build/release-bench/*.json
```

### Threshold files

`tools/benchmark/thresholds/voice_agent_latency.json`:

```json
{
  "name": "voice_agent_latency",
  "description": "End-of-utterance to first audible PCM frame",
  "metric": "first_audio_ms",
  "p50_ms": 80,
  "p90_ms": 120,
  "p99_ms": 180,
  "tolerance_pct": 10
}
```

`tools/benchmark/thresholds/rag_retrieval_latency.json`:

```json
{
  "name": "rag_retrieval_latency",
  "description": "Top-6 retrieval over 10K chunks including reranker",
  "metric": "retrieval_ms",
  "p50_ms": 5,
  "p90_ms": 8,
  "p99_ms": 12,
  "tolerance_pct": 10
}
```

`tools/benchmark/thresholds/abi_encode_cost.json`:

```json
{
  "name": "abi_encode_cost",
  "description": "Token proto encode+decode round-trip",
  "metric": "roundtrip_ns",
  "p50_ms": 0.0005,
  "p90_ms": 0.001,
  "p99_ms": 0.002,
  "tolerance_pct": 20
}
```

`tools/benchmark/thresholds/llm_first_token.json`:

```json
{
  "name": "llm_first_token",
  "description": "LLM stream first-token latency with tiny-llama",
  "metric": "first_token_ms",
  "p50_ms": 120,
  "p90_ms": 200,
  "p99_ms": 350,
  "tolerance_pct": 15
}
```

### Threshold checker

`tools/ci/check_thresholds.py` — minimal, exits nonzero if any p50 /
p90 / p99 exceeds its ceiling by more than `tolerance_pct`. Reads the
benchmark output JSON and the matching threshold JSON by filename stem.
Prints a human-readable table on failure.

### Benchmark harness stubs (from earlier phases, formalised here)

```text
sdk/runanywhere-commons/tools/benchmark/
├── CMakeLists.txt
├── common.h                    NEW — Percentile<T>, BenchResult, JSON writer
├── voice_agent_latency.cpp     Phase 3
├── rag_retrieval_latency.cpp   Phase 4
├── abi_encode_cost.cpp         Phase 5
├── llm_first_token.cpp         NEW
└── fixtures/
    ├── voice_agent.wav         (committed LFS)
    ├── rag_10k_chunks.bin      (committed LFS)
    └── tiny-llama-q4.gguf      (fetched by setup-bench.sh, not in git)
```

### Fetch script for large fixtures

`tools/ci/setup-bench.sh` — downloads the ~200 MB tiny-llama model from
a pinned HuggingFace revision into the runner cache, caches by commit
of the thresholds file so upgrades invalidate.

### Tests added in this phase

```text
tests/unit/sanitizer_build_smoke_test.cpp
  — trivial test; only there to ensure the sanitizer flag pipeline
    actually compiles and links the test binary end-to-end. Catches
    accidental flag typos.

tests/integration/bench_harness_test.cpp
  — runs the benchmark common.h Percentile<T> class under 1000
    synthetic samples; asserts p50/p90/p99 math matches a reference
    implementation to within a ULP.
```

---

## Implementation order

1. **Land the `cmake/Sanitizers.cmake` function call** under an off
   default. Verify a normal build is unaffected.

2. **Add CMakePresets.json** with the three presets. Build each locally
   on a dev MacBook to prove they work.

3. **Wire ASan+UBSan workflow.** Expect two or three new suppressions
   from third-party libs; capture them in `asan.supp` / `ubsan.supp`.

4. **Wire TSan workflow.** Voice agent and RAG concurrent tests are
   the stressors; if TSan flags something in our code, fix it rather
   than suppress.

5. **Formalise the benchmark harness** (`common.h` with the Percentile
   helper and the JSON writer). Port each of the benchmark binaries
   from Phase 2–5 to use the harness.

6. **Write the threshold JSONs.** Populate with measured values from
   a quiet local run; document which machine the numbers came from.

7. **Land `check_thresholds.py`.** Gate on the four benchmarks above.

8. **Run for a week with the gate in warning mode** (job succeeds but
   prints `::warning::` on threshold violations). Confirm stable
   before flipping to `::error::`.

9. **Flip to hard fail.** Any future regression blocks the merge until
   the threshold is adjusted or the regression is fixed.

---

## API changes

None. Phase 6 adds build configurations and CI; public and internal
APIs are untouched.

---

## Acceptance criteria

- [ ] `cmake --preset commons-asan-ubsan && cmake --build ... && ctest ...`
      green on a fresh clone of main.
- [ ] `cmake --preset commons-tsan && ... && ctest ...` green.
- [ ] `commons-sanitizers.yml` workflow has a green run on a PR that
      includes a deliberate `UNINITIALIZED_READ` canary (reverted before
      merge). Verifies the sanitizer actually fires, not just that the
      job ran.
- [ ] `commons-bench.yml` gates a deliberate +30 % voice-agent latency
      regression PR (reverted). Confirms the threshold check fires.
- [ ] Sanitizer log artifacts attach to the workflow run on failure.
- [ ] Threshold JSONs checked into `tools/benchmark/thresholds/`;
      changes require PR review.
- [ ] Benchmark harness percentile math has a unit test (`bench_harness_test`).

## Validation checkpoint

See `testing_strategy.md`. Phase 6 is itself the testing
infrastructure, so its checkpoint is a meta-check: the gates
themselves must work.

- **Deliberate regression canary.** Land a throw-away PR that
  injects a 30 % latency regression into voice_agent_latency.cpp
  and verify `commons-bench.yml` fails. Revert before merge.
- **Deliberate sanitizer canary.** Land a throw-away PR with an
  intentional uninitialised read and verify `commons-sanitizers.yml`
  catches it with a red run. Revert before merge.
- **CMake preset parity.** `cmake --preset commons-asan-ubsan` on
  a clean clone builds identically on macOS + Linux runners.
- **Feature preservation matrix re-run** under the new gates as a
  final sanity; no row regressed since Phase 5.
- **Suppression review.** Every entry in
  `tools/ci/sanitizer-suppressions/*.supp` has a comment
  explaining why (which dep, which known issue, link to upstream
  tracker where possible).
- **Benchmark thresholds calibrated.** Thresholds match observed
  values with ≥10 % headroom. Three independent clean runs on
  `macos-14-large` to establish the baseline; noise documented.

**Sign-off before Phase 7**: both canaries tested in CI; confirmed
that the gates would block a real regression.

---

## What this phase does NOT do

- No Linux runner coverage yet — we gate on macOS-14 only because our
  CI fleet is Mac-heavy and our primary perf target is M-series. A
  Linux job can be added in a follow-up.
- No Android / iOS sanitizer runs — that's an SDK-frontend concern,
  handled in the per-frontend plan.
- No MSan (memory sanitizer). Linking protobuf + sherpa-onnx + USearch
  under MSan means rebuilding every dep with MSan instrumentation —
  large engineering cost, small marginal value on top of ASan. Revisit
  only if we see real uninitialised-read bugs that ASan misses.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| TSan flags legitimate races inside the llama.cpp / sherpa-onnx binaries we can't fix | High | Suppress by regex on third-party path prefix in `tsan.supp`. Document every added suppression with the source PR so we remember why |
| Benchmark runner variance causes flaky threshold failures | Medium | `tolerance_pct` in threshold files absorbs ~10 % noise. Use `macos-14-large` which is more deterministic. If still noisy, switch to median-of-N-runs in `check_thresholds.py` |
| ASan doubles memory use, OOM-kills the runner on model-loading tests | Medium | Gate the model-loading benchmark to the Release job, not the ASan job. ASan job runs only unit + integration tests that don't load real models |
| Combined ASan+UBSan+TSan into one job is tempting but invalid (TSan is exclusive) | Certain | `ra_apply_sanitizers` in CMake errors out if both sets are on. Documented in the function |
| Fixtures bloat the repo | Medium | ~200 MB model binaries fetched by `setup-bench.sh`, not committed. Only the small `.wav` and `.bin` fixtures go via git-LFS |
| Path-filter causes sanitizer job to skip when it should run (e.g. CMakeLists change outside commons) | Low | Add the `cmake/` tree and `.github/workflows/commons-*.yml` themselves to the path-filter list |
| Threshold drift: engineers loosen thresholds rather than fix regressions | Medium | Require an explicit "performance-waiver" label on any PR that bumps a p-value. CODEOWNERS for `tools/benchmark/thresholds/` set to the perf reviewers group |
