# Testing strategy and validation checkpoints

> This plan is an **in-place refactor**, not a rewrite. Every feature
> that works today must still work at every phase boundary. Nothing
> is "skipped for now" and patched later. This document is the
> umbrella discipline that every phase doc points back to.

---

## Principles

1. **Feature preservation is mandatory.** The refactor changes how
   components talk to each other, not what they do. If a phase lands
   and a previously-working feature stops working, the phase is not
   done — regardless of what its "phase-specific" acceptance criteria
   say.

2. **Every phase leaves the repo shippable.** `cmake --build` green,
   `ctest` green, sanitizers green, frontend builds green (where
   relevant to that phase). No phase merges with a red gate.

3. **Sanitizers catch what unit tests miss.** Every integration test
   runs under ASan + UBSan at minimum; concurrency-heavy tests
   additionally under TSan. See Phase 6.

4. **Testing is upstream, not downstream.** If code is introduced in
   a phase, the test for it lands in the same PR, not a follow-up.
   "Tests come in Phase N+1" is not acceptable.

5. **Frontend migrations gate on real compile + lint + run.** Not
   just "tests pass" — the example app must build and run to smoke
   the behaviour end-to-end.

---

## The feature preservation matrix

These are the capabilities that must keep working at every phase
boundary. At every validation checkpoint each row is either
exercised directly by an automated test or spot-checked manually
with the dev CLI.

### L3 primitives

| Feature | Smoke fixture | Test scope |
| --- | --- | --- |
| LLM text generation | `qwen3-4b-q4_k_m.gguf` + sample prompt | First-token latency, stream terminates, text non-empty, tokens look coherent |
| LLM tool calling | `hermes-pro` or equivalent with tool JSON | Tool-call event parses, args JSON valid |
| LLM structured output | JSON-schema constrained prompt | Output validates against schema |
| STT transcription | `sample-utterance.wav` | Final transcript matches expected text within 1-word edit distance |
| STT partial transcripts | streaming WAV | Partial chunks emit before final |
| TTS synthesis | short string "hello world" | PCM output length ≈ expected duration |
| VAD detection | silence→speech→silence WAV | `VOICE_START`, `VOICE_END_OF_UTTERANCE` events in order |
| Wake word detection | hotword WAV + negative WAV | Positive triggers detect=true; negative stays detect=false |
| Embedding generation | fixed text | Vector dim matches config; dot product with self ≈ 1.0 |
| VLM image → text | sample image + prompt | Output references content visible in the image |
| Diffusion text → image | short prompt | At least N denoising steps emitted; final image non-empty |

### L5 solutions

| Feature | Smoke fixture | Test scope |
| --- | --- | --- |
| Voice agent full pipeline | `sample-utterance.wav` | End-of-utterance → first PCM within target latency; non-empty reply |
| Voice agent barge-in | WAV + synthetic VAD interrupt | No PCM after barge-in for ≥100 ms; fresh LLM kicks in after |
| RAG ingest + query | 10-doc fixture + known query | Top-K results contain the ground-truth doc |
| RAG hybrid retrieval | 10K-chunk corpus | BM25+vector+RRF ordering differs from single-path on an ambiguous query |
| RAG neural reranker | misordering fixture | Reranker reorders so expected doc wins top-1 |
| Wake word + STT chain | WAV with hotword followed by speech | Wake detected → STT runs → transcript matches |
| OpenAI HTTP server — `/chat/completions` | curl against localhost | 200 OK; streamed `text/event-stream` chunks parse as OpenAI events |
| OpenAI HTTP server — `/embeddings` | curl against localhost | 200 OK; vector shape matches |
| OpenAI HTTP server — `/audio/transcriptions` | multipart WAV | 200 OK; text field populated |

### Infrastructure

| Feature | Test scope |
| --- | --- |
| Model downloader | Given a pinned fixture URL, downloads + extracts + registers; re-invocation with same URL is idempotent (no re-download) |
| Model extraction | GGUF / zip / tar extraction produces expected file layout |
| File management | App-data paths resolve correctly on each platform; removing a model frees disk |
| LoRA registry | Can register + load + unload a LoRA adapter |
| Network / HTTP client | Basic GET with retry on 5xx; respects timeout |
| Device metadata | Reports RAM, CPU core count, GPU availability correctly |
| Telemetry / observability | Emits metric samples under a normal LLM run; spans have start/end times |
| Storage abstraction | Put/get/delete round-trip per supported platform |

### SDK surfaces

| Feature | Test scope |
| --- | --- |
| Swift SDK bootstrap | `RunAnywhere.bootstrap()` succeeds on iOS + macOS |
| Kotlin KMP bootstrap | `RunAnywhere.bootstrap(ctx)` succeeds on Android + JVM |
| Flutter SDK bootstrap | FFI loader opens the library on iOS + Android |
| RN SDK bootstrap | TurboModule registers + `installJSI()` returns true |
| Web SDK bootstrap | WASM loads + exports `ra_*` symbols |

Any phase that touches a row above must either run its matching
test or manually confirm behaviour. A phase that silently regresses
any row fails the checkpoint.

---

## Per-phase validation template — C++ (phases 0–8)

Every C++ phase, before it is considered complete, runs this template
plus any phase-specific gates in its own doc:

### Build gates

```bash
# From sdk/runanywhere-commons/
cmake --preset commons-asan-ubsan && cmake --build --preset commons-asan-ubsan
cmake --preset commons-tsan       && cmake --build --preset commons-tsan
cmake --preset commons-release-bench && cmake --build --preset commons-release-bench
```

All three must be green.

### Test gates

```bash
ctest --preset commons-asan-ubsan --output-on-failure
ctest --preset commons-tsan       --output-on-failure
```

Both green. Suppressions only where a deps-level race / leak is
verified and documented.

### Feature preservation smoke

A single test binary
`tests/integration/feature_preservation_smoke.cpp` (introduced in
Phase 0, grows each phase) walks every row of the feature
preservation matrix using the dev CLI or direct C++ API calls.
Green means every feature above still works.

### Benchmark gates (phase 6 onwards)

```bash
./build/release-bench/tools/benchmark/voice_agent_latency --out voice.json
./build/release-bench/tools/benchmark/rag_retrieval_latency --out rag.json
./build/release-bench/tools/benchmark/llm_first_token --out llm.json
./build/release-bench/tools/benchmark/abi_encode_cost --out abi.json
python tools/ci/check_thresholds.py --results build/release-bench \
       --thresholds tools/benchmark/thresholds
```

All thresholds met within tolerance.

### Grep gates

Each phase's acceptance criteria lists banned strings that must
return zero matches under `grep -rn` — removed symbols, deleted BC
shims, etc.

### Dev-CLI smoke

```bash
# From the commons build tree
./build/tools/dev-cli/ra-cli llm --model tiny.gguf --prompt "hi"
./build/tools/dev-cli/ra-cli tts --text "hello world" --out /tmp/out.wav
./build/tools/dev-cli/ra-cli stt --wav tests/fixtures/sample.wav
./build/tools/dev-cli/ra-cli voice --wav tests/fixtures/voice.wav
./build/tools/dev-cli/ra-cli rag  --corpus tests/fixtures/docs/  --query "what is foo"
```

Each command exits 0 with sane output. Failure means the phase
broke a feature.

### Checkpoint phases

The checkpoint is **deeper** at these phase boundaries — a full
sweep of the feature preservation matrix, a manual spot-check on
device where meaningful, and explicit sign-off before moving on:

- End of **Phase 1** (plugin backends) — engines reachable through
  the new registry must produce identical outputs to pre-Phase-1.
- End of **Phase 2** (streaming primitives) — every callback-using
  caller now on streams; no semantic drift.
- End of **Phase 3** (voice agent DAG) — full voice agent run with
  real models on dev MacBook; barge-in tested interactively.
- End of **Phase 4** (RAG hybrid) — RAG quality numbers measured
  against a fixed eval set; no drop from the v1 baseline.
- End of **Phase 5** (proto3 ABI) — every feature exercised through
  the new C ABI end-to-end.
- End of **Phase 8** (cleanup) — the whole feature matrix green,
  benchmark thresholds green, `cleanup/` bucket empty.

---

## Per-phase validation template — frontends (phases 9–13)

Frontend phases run this template plus their phase-specific gates:

### Compilation gate

Every target for the SDK must build cleanly:

- **Swift (Phase 9):**
  ```bash
  swift build                                         # macOS host
  xcodebuild -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 15'
  xcodebuild -scheme RunAnywhere -destination 'platform=macOS'
  xcodebuild -scheme RunAnywhere -destination 'platform=tvOS Simulator,name=Apple TV'
  xcodebuild -scheme RunAnywhere -destination 'platform=watchOS Simulator,name=Apple Watch Series 9'
  ```
- **Kotlin KMP (Phase 10):**
  ```bash
  ./scripts/sdk.sh build-all --clean
  # produces RunAnywhereKotlinSDK-jvm-*.jar and RunAnywhereKotlinSDK-android-*.aar
  ```
- **Flutter (Phase 11):**
  ```bash
  melos bootstrap
  melos run build           # per-package build
  flutter build ios --no-codesign   # in the example app
  flutter build apk
  ```
- **React Native (Phase 12):**
  ```bash
  yarn && yarn build
  (cd examples/react-native/runanywhere_ai && yarn ios --no-install)
  (cd examples/react-native/runanywhere_ai && yarn android)
  ```
- **Web (Phase 13):**
  ```bash
  ./scripts/build-web.sh --setup        # wasm + typescript
  (cd examples/web/runanywhere_ai && npm run build)
  ```

Each of these must be **zero errors, zero new warnings**. Warnings
that predate the phase are grandfathered only if explicitly noted
in the phase doc; anything else has to be fixed in the same PR.

### Lint gate

Every SDK has a language-specific linter that must be green:

| SDK | Tool | Invocation |
| --- | --- | --- |
| Swift | SwiftLint | `swiftlint` in `sdk/runanywhere-swift/` |
| Kotlin | detekt + ktlint | `./gradlew detekt` |
| Flutter | `dart analyze` + `flutter analyze` | `melos run analyze` |
| React Native | ESLint + TypeScript-strict | `yarn lint && yarn typecheck` |
| Web | ESLint + TypeScript-strict | `npm run lint && npm run typecheck` |

### Test gate

Unit tests green in-process:

```bash
swift test                             # Swift
./gradlew test                         # Kotlin JVM
./gradlew connectedAndroidTest         # Kotlin Android (instrumented; needs emulator)
melos run test                         # Flutter
yarn test                              # RN
npm test                               # Web
```

### Example app gate

Every example app must build and launch to its first screen on at
least one runner. Frontend phases are explicitly **not done** if the
example app broke:

- iOS example: build + run on `iPhone 15` simulator, verify chat
  screen renders, send one prompt, receive streaming tokens.
- Android example: build + install on emulator, same smoke.
- Flutter example: `flutter run` on iOS sim + Android emulator.
- RN example: `yarn ios` + `yarn android`, chat smoke.
- Web example: `npm run dev` + browser nav to localhost, chat smoke.

For iOS and Android, when a physical device is available, the phase
sign-off includes a run on device for latency numbers (≤120 ms
first-audio in voice agent).

### Fix-as-you-go rule

**You do not defer broken warnings or broken builds to a cleanup
phase.** If a frontend phase touches a file and the compiler emits
a warning, or the linter flags an issue, fix it in the same PR. The
phase doc's acceptance criteria enforce this by requiring zero
warnings; a PR that has "let's fix these later" warnings fails the
checkpoint.

---

## Regression protocol

If a checkpoint fails:

1. **Revert or block.** If `main` is red, revert the offending PR;
   don't try to stack fixes on a broken base.
2. **Root-cause.** Before landing a fix, articulate what the
   regression was, why it happened, and what check would have caught
   it earlier. Add that check to the phase's acceptance criteria
   (or the preservation matrix) for future phases.
3. **Triage the matrix.** If the preservation matrix missed a
   feature that ended up broken, the matrix is incomplete. Update
   this doc + the matching smoke test.

No "we'll fix it in the next phase" justifications. Regressions
don't age well.

---

## Fixture policy

Fixtures live in one of three places:

- `sdk/runanywhere-commons/tests/fixtures/` — small, committable
  (≤1 MB each). Audio samples, text snippets, proto blobs.
- `sdk/runanywhere-commons/tools/benchmark/fixtures/` — medium
  (≤10 MB), committed via git-LFS.
- Large models (≥50 MB) — fetched by `tools/ci/setup-bench.sh` from
  a pinned HuggingFace revision. Never committed. Cached in the CI
  runner between runs.

Every test that uses a fixture must name it in a comment (path
relative to the fixture root) so the test is trivially
reproducible.

---

## What "green" means

- All compiles exit 0 with zero warnings.
- All tests pass with exit code 0.
- All sanitizers pass with no suppressions added in the same PR.
- Every feature preservation row exercised by the relevant
  checkpoint is green.
- The example app (where applicable to the phase) builds and runs
  to its first interactive screen without error.

Partial green is not green.

---

## How this doc is consumed

- Each phase doc has a **Validation checkpoint** section that
  points back here and lists the *additional* phase-specific gates.
- The common gates above are not duplicated into every phase doc;
  they're inherited by reference.
- If a new gate becomes standard (e.g. a new benchmark), it's added
  here once and every future phase picks it up automatically.

---

## Dev-CLI — the smoke-test swiss army knife

A small commons-hosted CLI binary used across phases for feature
smokes without spinning up a full SDK frontend:

```text
sdk/runanywhere-commons/tools/dev-cli/
├── main.cpp
├── cmd_llm.cpp
├── cmd_stt.cpp
├── cmd_tts.cpp
├── cmd_vad.cpp
├── cmd_vlm.cpp
├── cmd_diffusion.cpp
├── cmd_rag.cpp
├── cmd_voice.cpp
├── cmd_wakeword.cpp
├── cmd_download.cpp
└── CMakeLists.txt
```

Introduced in Phase 0 as a stub; each phase fills in the commands
that its primitives enable. By Phase 8 every feature matrix row is
exercisable via `ra-cli <verb>`. This gives any engineer a way to
manually confirm "yes this still works" in under 30 seconds per
feature, and gives CI a uniform way to run the feature preservation
smoke suite.
