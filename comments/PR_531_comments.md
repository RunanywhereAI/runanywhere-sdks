# PR #531 — Full Comment Triage, Design Review, and Release Readiness

- Repository: `RunanywhereAI/runanywhere-sdks`
- Pull request: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531
- Base/head: `main` (`92b9f447`) ← `siddhesh/sdk-audit-fixes-v2` (`c9f95005` live remote head)
- Review baseline: 842 files, +77,739 / -16,963, 104 commits
- Live GitHub inventory: **13 inline review comments + 1 issue comment + 3 submitted
  reviews = 17/17 discussion objects captured**; the 13 review threads are 9 resolved and
  4 unresolved (3 current CodeQL threads and 1 outdated snapshot thread)
- GitHub issue creation: prohibited by the user; no issue may be used to defer a valid finding
- Live snapshot: `2026-07-12T06:37:03Z`; the remote branch is 104 commits ahead of and
  0 commits behind `main`
- Remote checks at this snapshot: **41 total = 36 passed + 4 in progress + 1 failed**;
  the in-progress jobs are two `ios-device` and two `kotlin-android` jobs across duplicate
  PR-build runs, and the failed aggregate `CodeQL` check reflects open alerts 116–118 even
  though all four CodeQL analyzer jobs passed
- Remote merge state: `BLOCKED` / `REVIEW_REQUIRED`; branch protection requires two approving
  reviews including code-owner review, and the live PR has no approvals or requested reviewers
- Document status: local corrective implementation continues; final release-artifact, thread,
  push, and CI proof are pending

This is the single source of truth for the complete PR review. It records the live GitHub
comments, current-code verification, subsystem findings, system-design conclusions, applied
resolutions, and release validation. The normalized disposition register is followed by a verbatim
raw GitHub archive containing every submitted review, issue comment, inline comment, AI-agent prompt,
thread ID/state, timestamp, location, URL, analysis chain, suggestion, and operational checkbox.

## Executive assessment

The branch is not a narrow “restore MetalRT / labels / lockfile” patch. It is a release-train
aggregation spanning the native C++ core, canonical protobuf IDL and all generated bindings,
RAG retrieval, seven engine/runtime primitives, QHexRT private-prebuilt integration, five platform
SDKs, five example applications, native artifact packaging, and CI/release automation.

The architectural direction is sound where the branch keeps business logic in commons, exposes
structured proto contracts, treats engines as modality op-table adapters, and keeps private QHexRT
implementation and DSP skels outside the public repository. The initial head was not merge-ready,
however. The detailed review found merge-blocking CodeQL alerts, ignored RAG contract semantics,
cancellation paths that could report success, public packaging paths capable of absorbing private
natives, plaintext example credentials, stale release artifact versions, non-reproducible Swift
archives, incomplete App Privacy disclosure, and duplicated CI execution. Those findings are addressed
with localized changes and deletion of obsolete/test-only private ABI mirrors.

## System design review

### 1. Ownership and layering

The intended dependency direction remains:

`example UI → platform SDK facade → proto/C ABI bridge → commons lifecycle/service → engine/runtime`.

- Commons remains the correct owner of model lifecycle, routing, RAG orchestration, downloads,
  storage, events, telemetry, and error translation.
- Platform SDKs should remain typed async adapters. They must not add independent model-selection,
  persistence, or inference policy that can diverge across Swift/Kotlin/Flutter/RN/Web.
- Examples may own presentation state, but pipeline and model policy must move down when it becomes
  reusable. Existing large example view models are a maintainability risk; this review does not
  manufacture a second abstraction layer merely to move lines during a release fix.
- Kotlin's new QHexRT diffusion facade is platform-specific today. It is retained because it is the
  device acceptance surface, but the blocking JNI call must execute on `Dispatchers.IO`, and it
  must not be presented as cross-SDK parity until a canonical Swift facade exists.

### 2. Public/private and open-source boundary

- The public repo may contain the QHexRT engine adapter, catalog identities, C ABI declarations,
  and prebuilt validation/staging logic. Private QHexRT source, approximate copies of its private
  header, private archives, QNN host libraries, and DSP skels must not be committed or included by
  default in public packages.
- The checked-in fake `qhexrt_c.h` duplicated a private ABI and enabled host tests against an
  approximation rather than the staged receipt/header. It and the dependent host tests are
  deleted; real prebuilt contract validation and the private QHexRT build remain authoritative.
- Flutter/RN package scripts must use per-package allowlists. QHexRT inclusion must require an
  explicit internal opt-in and stale private outputs must be removed before public packaging.
- QHexRT DSP skels remain app-private code-cache material and are not promoted into the public SDK
  artifact set.

### 3. Contract and generated-code integrity

- Protobuf IDL is canonical. `multi_query_count` was clamped to eight only in native code, while
  generated SDK validators accepted any positive value. The IDL now declares the same maximum and
  all bindings are regenerated.
- Generator-owned validation grammar is fixed at the generator, not hand-edited in one emitted
  language. Single-ended bounds say `must be >= N`; closed ranges say `must be in A...B`.
- `LLMGenerateRequest.options` is the sole generation-settings envelope. Nineteen deprecated inline
  duplicates are deleted at the IDL, their numeric tags are reserved, every generated binding is
  refreshed, and native/platform adapters no longer dual-populate or fall back to removed fields.
- Platform defaults and validators come from generated convenience APIs. Redundant Kotlin RAG,
  Embeddings, VAD, STT, and TTS helpers are deleted so hand-written values cannot override IDL
  defaults or accept inputs rejected by the canonical contract.
- Retired framework wire slots remain gaps in the canonical proto. The obsolete MetalRT source
  constant is deleted as well: there is no selectable engine, public compatibility alias, or revived
  wire value.
- Sentry is deleted from the canonical IDL and every generated/hand-written platform API. Field
  number 6 remains numerically reserved only to prevent unsafe wire-tag reuse; there is no deprecated
  field, shim, no-op method, type member, implementation dependency, or tracked documentation surface.
- Deprecated implementation paths are not retained as compatibility fallbacks. The Web synchronous
  XHR transport, its C++ function-table trampoline ABI, WASM export, TypeScript surface, and tests are
  deleted; current Emscripten fetch and the async platform download contract remain the only Web HTTP
  paths. Build scripts likewise no longer seed deprecated FindZLIB result variables.
- Tool calling now has one generated contract: `ToolCall.id`, `ToolResult.tool_call_id`, typed
  `ToolCallFormatName`, and `max_tool_calls`. The string format hint, duplicate iteration limit,
  duplicate custom-system-prompt field, no-handle run-loop ABI, public enum-to-string helper, and
  per-SDK resolver shims are deleted. Session/run-loop requests carry the enum directly.
- `ModelInfo.description` is deleted in favor of `ModelInfo.metadata.description`. Partial registry
  updates merge supplied metadata fields into the stored metadata object so changing a description
  cannot silently erase tags, author, license, or version.
- Removed proto fields retain numeric reservations only. Retired source names are not emitted into
  generated descriptors or presented as callable compatibility APIs.

### 4. Lifecycle, concurrency, and cancellation

- Existing rerank rebuild comments are transactionally resolved: Android serializes rebuilds and
  rolls state back; Flutter catches teardown failure and notifies; RN commits state after teardown.
- RAG content-hash reservation is atomic under the backend mutex, preventing duplicate concurrent
  ingestion.
- QHexRT STT/TTS/diffusion callback-stop paths must return `RAC_ERROR_CANCELLED` even when the private
  runtime treats callback stop as a clean status. Success after cancellation is semantically wrong.
- Kotlin Flow cleanup must call native cancellation only when collection ends early. Normal terminal
  completion must not cancel a request that has already completed or race the next request.
- Voice-agent cancellation is keyed by the exact turn request ID, latches cancels that arrive before
  worker admission, interrupts only the matching active LLM/TTS stage, emits structured
  APP_STOP/STOPPED/IDLE/CANCELLED events, and does not leak cancellation into the successor turn.
- Backend interrupt dispatch must never run while holding the voice cancellation mutex. The turn
  waits for an in-flight interrupt before advancing stages, avoiding lock inversion while retaining
  request/stage identity.
- One QHexRT session remains serialized by its operation mutex because output aliases session-owned
  buffers and reset/generate/copy are not independent operations.

### 5. RAG retrieval semantics

- `similarity_threshold` is a public, validated configuration contract. The graph previously logged
  that it intentionally ignored the value; this made an explicit query/session override ineffective
  and contradicted the E2E test. Dense retrieval now passes the configured floor to USearch.
- BM25 remains independently eligible for lexical matches; RRF fuses available dense and sparse
  rankings. A high dense floor does not incorrectly erase an exact lexical result.
- Snapshot persistence was removed earlier in the branch. The old overflow and quadratic-save
  comments are therefore obsolete on current code; remaining proto compatibility fields cannot
  activate persistence.
- Multi-query expansion is bounded at the wire validator and the native ABI. Scope filtering still
  widens the candidate pool before filtering to preserve `top_k` where possible.

### 6. Security, privacy, and credential handling

- All three open CodeQL alerts are valid release blockers: incomplete multi-character sanitization
  and two polynomial regexes. Fixes use token filtering or linear index/scan logic.
- HTTP logs must not include query strings, fragments, response bodies, or credentials. Structured
  error parsing may still consume the body without printing it.
- The RN example no longer persists Hugging Face bearer tokens in AsyncStorage. Tokens are applied
  to commons for the current process, and legacy plaintext values are deleted on Settings load.
- Build-time RunAnywhere credentials are acceptable only if they are publishable client credentials;
  a server/service-role secret must never be compiled into an app. No raw secret value is committed.
- The iOS example's telemetry includes a persistent device ID plus linked product-interaction,
  performance, and diagnostic events. Its privacy manifest now declares those categories for
  app functionality/analytics with tracking disabled.
- Secret scanning must not exempt the entire `thoughts/` tree or whole commits. A known public
  control-plane URL can be allowlisted by its exact value instead.

### 7. Storage and platform behavior

- Web's WASM modules do not share MEMFS. Without OPFS or an approved local directory, downloading
  into commons MEMFS cannot make the model visible to a separate inference WASM instance. The SDK
  now rejects this unsupported path before network activity instead of claiming a usable fallback.
- QHexRT embeddings accept text through the embeddings primitive. Inferring that arbitrary text is
  a local image path based on extension/readability crossed an undocumented file-access boundary
  and is removed until an explicit typed image-embedding contract exists.

### 8. Release and CI design

- Native release archives must be deterministic and their checksums must already match the tagged
  `Package.swift`. A post-tag `Package.swift.updated` cannot repair a tag and is removed in favor of
  a read-only hard gate.
- Release consumer jobs must prove the artifacts produced in the same workflow. Swift uses the five
  staged XCFrameworks through an explicit local-native package override; Kotlin resolves and dexes
  the exact core/LlamaCPP/ONNX coordinates from the workflow's local Maven bundle; Flutter stages
  package-owned native inventories; Web and React
  Native install their complete tarball families only after registry dependencies and assert the
  resolved versions. Downloading a candidate without wiring it into the dependency graph is not a
  consumer test.
- The long-lived PR head branch was configured for both `push` and `pull_request`, creating duplicate
  matrices for every commit. The head-specific trigger is removed locally; the current remote baseline
  still ran both matrices (`29171555281` push and `29171556138` pull request), so the next pushed SHA
  must prove that only the intended PR matrix remains.
- RN CI must validate the whole workspace, not only core. Core declarations are built first so
  composite dependents do not consume stale `lib/internal.d.ts`.
- The final Android/QHexRT gate is the documented receipt-driven build, staging into this checkout,
  AAR/app packaging, and final 16 KiB ELF `LOAD` alignment verification.

## Live GitHub comment capture and disposition

Scores use Likelihood/User-impact/Scope (LUS) and Change Scope (CS), each 1–5.

The paginated REST inventory reconciles exactly to 13 inline comments and one issue comment.
GraphQL adds the authoritative thread state and the three submitted review objects. Every thread
contains one root comment and no replies. Nine threads are resolved; four remain unresolved:

- `PRRT_kwDOPQhgos6OwmK5` / comment `3532871064` is outdated because snapshot loading was deleted,
  but still needs an evidence reply and explicit resolution.
- `PRRT_kwDOPQhgos6PaCgA` / comment `3547888090` is current and unresolved pending the CodeQL 116
  rescan on the pushed fix.
- `PRRT_kwDOPQhgos6QJjRc` / comment `3565166744` is current and unresolved pending the CodeQL 117
  rescan on the pushed fix.
- `PRRT_kwDOPQhgos6QJjRh` / comment `3565166749` is current and unresolved pending the CodeQL 118
  rescan on the pushed fix.

### GH-01 — `3532871035` — Android rerank rebuild transaction

- Path: `examples/android/RunAnywhereAI/.../RagViewModel.kt`
- Author: `coderabbitai[bot]`
- Original finding: “Handle rerank rebuild failures instead of only logging them. If
  `ragDestroyPipeline()` succeeds and `ragCreatePipeline()` fails, the pipeline is left torn down
  while `rerankEnabled` stays flipped; rapid toggles can also overlap rebuilds. Roll back the toggle
  and surface an error so the UI can recover.”
- AI prompt: capture previous state, guard overlapping rebuilds, restore state/surface an error on
  destroy/create failure, preserve statistics refresh on success.
- Historical/current: valid originally (LUS 5, CS 2); fixed on current head.
- Evidence: existing commits through `05596e5b`; focused Android RAG tests pass (11 tests).
- Disposition: **addressed before this pass; retain and resolve with evidence**.

### GH-02 — `3532871041` — Flutter rerank teardown error

- Path: `examples/flutter/RunAnywhereAI/lib/features/rag/rag_view_model.dart`
- Original finding: `_rerankEnabled` changed before awaited teardown; an unhandled failure could
  leave stale document state and omit `notifyListeners()`.
- AI prompt: use the existing try/catch + `_error` pattern, roll back or preserve coherent state,
  and always notify listeners.
- Historical/current: valid originally (LUS 3, CS 1); fixed by `05596e5b`.
- Validation: Dart formatting and analysis passed.
- Disposition: **addressed before this pass**.

### GH-03 — `3532871047` — React Native rerank teardown rejection

- Path: `examples/react-native/RunAnywhereAI/src/screens/RAGScreen.tsx`
- Original finding: direct Switch callback awaited `handleClearAll()` without catching a rejected
  `ragDestroyPipeline()`, risking an unhandled rejection and inconsistent optimistic UI state.
- AI prompt: catch teardown failure, surface through `setError`, and only keep optimistic state if
  clean recovery exists.
- Historical/current: valid originally (LUS 4, CS 1); fixed by `05596e5b`.
- Validation: example typecheck and targeted lint passed.
- Disposition: **addressed before this pass**.

### GH-04 — `3532871052` — unbounded `multi_query_count`

- Path: `sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp`
- Original finding: a very large positive value could drive an arbitrary number of rewrite and
  retrieval passes; clamp or reject before the graph.
- AI prompt: localize the upper-bound check to query override construction so downstream graph
  inputs are always bounded.
- Historical/current: valid originally; native clamp to 8 exists in `83b4cf789` (current LUS 1,
  CS 1). The IDL/generated-validator mismatch remained valid as a design-contract finding.
- Resolution in this pass: add canonical `rac_max = 8` and regenerate every SDK binding.
- Disposition: **fully addressed**.

### GH-05 — `3532871055` — duplicate concurrent RAG ingest

- Path: `sdk/runanywhere-commons/src/features/rag/rag_backend.cpp`
- Original finding: content-hash check and insert used separate lock scopes, so concurrent identical
  ingests could both embed and append duplicate chunks.
- AI prompt: reserve the hash under the same lock as the existence check or serialize the ingest.
- Historical/current: valid (LUS 5, CS 2); fixed in `83b4cf789` by atomic reservation with explicit
  rollback on failure.
- Validation: RAG target built; 5/5 focused RAG ctests passed.
- Disposition: **addressed before this pass**.

### GH-06 — `3532871056` — quadratic persistence rewrite

- Path: `sdk/runanywhere-commons/src/features/rag/rag_backend.cpp`
- Original finding: `add_document()` rewrote the full vector snapshot on each ingest.
- AI prompt: coalesce per batch or expose an explicit flush.
- Historical/current: historically valid (LUS 4, CS 4), now obsolete. `83b4cf789` removed snapshot
  persistence and vector serialization; current ingest is in-memory USearch/BM25 only.
- Validation: RAG and advanced modality ABI targets build; focused ctest passes.
- Disposition: **invalid/outdated on current head; no replacement code added**.

### GH-07 — `3532871058` — leading numeric query corruption

- Path: `sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp`
- Original finding: bare digits such as `2024 tax deadlines` and `3D printing basics` were stripped
  as if they were list markers.
- AI prompt: strip only explicit `N.` / `N)` prefixes, preserving bare leading digits.
- Historical/current: valid (LUS 4, CS 1); fixed in `83b4cf789`.
- Validation: fusion executable, nine checks, and focused ctest pass.
- Disposition: **addressed before this pass**.

### GH-08 — `3532871064` — vector snapshot overflow/reset

- Path: `sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp`
- Original finding: `pos + length` could wrap and several load failures did not clear prior state.
- AI prompt: compare against remaining bytes and reset on every failure.
- Historical/current: historically valid (LUS 4, CS 2), now obsolete because serialization/load
  APIs were deleted in `83b4cf789`.
- Disposition: **invalid/outdated; vulnerable code no longer exists**.

### GH-09 — `3532871065` — negative `tellg()` conversion

- Path: `sdk/runanywhere-commons/tests/test_rag_e2e.cpp`
- Original finding: `tellg() == -1` could be cast to a huge `size_t` after a one-byte allocation.
- AI prompt: detect a negative position before allocating or assigning output parameters.
- Historical/current: valid (LUS 4, CS 1); fixed in `83b4cf789`.
- Additional resolution: remove the committed developer-specific `/home/.../Downloads` fallback
  paths; real-model E2E is environment-only and otherwise skips.
- Disposition: **fully addressed**.

### GH-10 — `3532871068` — TypeScript validation grammar

- Path: `sdk/shared/proto-ts/src/convenience/rag_convenience.ts`
- Original finding: “`must be in >= 1` reads awkwardly; drop the stray `in`.”
- AI prompt: change only the emitted message while preserving validation.
- Historical/current: valid cosmetic finding (LUS 2, CS 1); TS was fixed by `05596e5b`.
- Additional resolution: correct the Swift/Kotlin/Dart generators too, then regenerate outputs, so
  grammar does not diverge by platform.
- Disposition: **fully addressed at generator level**.

### GH-11 — `3547888090` — CodeQL incomplete sanitization

- Path: `examples/web/RunAnywhereAI/src/services/model-display.ts`
- Original comment: “This string may still contain `on`, which may cause an HTML attribute
  injection vulnerability.” Alert 116.
- Current score: LUS 4, CS 1, security/CI blocker.
- Resolution: replace multi-character substring deletion with exact whitespace-token filtering for
  `(ONNX)`, `(GGUF)`, and `(MLX)`. Existing sinks also escape HTML.
- Validation: lint, typecheck, 9 tests, representative smoke cases, and production build pass.
- Disposition: **fixed locally; await push/CodeQL rescan**.

### GH-12 — `3565166744` — CodeQL trailing-slash ReDoS

- Path: `sdk/runanywhere-web/packages/core/src/Adapters/DeviceRegistrationAdapter.ts`
- Original comment: trailing-slash regex can run slowly on uncontrolled repeated `/`. Alert 117.
- Current score: LUS 5, CS 1, high-severity security/CI blocker.
- Resolution: replace regex backtracking with a right-to-left linear scan and one `slice`.
- Validation: 7/7 adapter tests, core typecheck, and ESLint pass.
- Disposition: **fixed locally; await push/CodeQL rescan**.

### GH-13 — `3565166749` — CodeQL query/fragment ReDoS

- Path: `sdk/runanywhere-web/packages/core/src/Foundation/BackendContract.ts`
- Original comment: `/[?#].*$/` can run slowly on uncontrolled input; five taint flows. Alert 118.
- Current score: LUS 5, CS 1, high-severity security/CI blocker.
- Resolution: find the earliest `?`/`#` with `indexOf`/`Math.min`, then `slice` once.
- Validation: 4/4 targeted tests, core typecheck, and ESLint pass.
- Disposition: **fixed locally; await push/CodeQL rescan**.

### GH-14 — issue comment `4891148296` — CodeRabbit walkthrough/operations

- Author: `coderabbitai[bot]`
- Created/updated: 2026-07-06 / 2026-07-12
- Exact-body evidence: 130 lines, 9,347 bytes, SHA-256
  `c5a25e0a417f2f66a612d5b3522d341797ab0afe8d57152198160168c48f4015`.
- Operational actions captured:
  1. Auto-pause configuration — optional preference, no defect (LUS 1, CS 1).
  2. `@coderabbitai resume` — defer during active fixes (LUS 3, CS 1).
  3. `@coderabbitai review` — trigger once after the final push (LUS 4, CS 1).
  4. Title omits the principal RAG/system scope — valid; update title/body (LUS 4, CS 1).
  5. “Create PR with unit tests” — generic beta control, declined; no separate PR.
  6. “Commit unit tests in branch” — generic control, declined unless a concrete fix needs coverage.
- Walkthrough accuracy: partially stale. It describes snapshot persistence that was later removed,
  a badge-color implementation that changed, and MetalRT as an active framework even though the
  retired framework is now absent from the public API. It is not copied into the new PR description.
- Disposition: **fully triaged; final review command pending final push**.

### GH-R1 — review `4640749607` — duplicate restore enumeration nitpick

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#pullrequestreview-4640749607
- Author: `coderabbitai[bot]`
- Historical location: `sdk/runanywhere-commons/src/features/rag/rag_backend.cpp:670-691`
- Original finding: materialize `vector_store_->all_chunk_texts()` once and reuse it for the BM25
  rebuild and content-hash restoration instead of enumerating the complete store twice.
- Historical/current: reasonable performance nitpick when submitted (LUS 2, CS 1), now obsolete.
  Snapshot load/restore and the affected `all_chunk_texts()` path were deleted from current code.
- Disposition: **invalid/outdated on current head; explicitly accounted for without replacement code**.

### GH-R2 — review `4640749607` — IDL upper-bound nitpick

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#pullrequestreview-4640749607
- Author: `coderabbitai[bot]`
- Historical location: `idl/rag.proto:216-224`
- Original finding: declare a `rac_max` for `multi_query_count` so generated validators document and
  enforce the native fan-out limit.
- Disposition: **duplicate of GH-04/DR-13 and fully addressed** with canonical `rac_max = 8` plus
  regeneration of every language binding.

### Submitted review inventory

| Review ID | Author | State | Submitted | Commit | Body |
|---|---|---|---|---|---|
| `4640749607` | `coderabbitai[bot]` | COMMENTED | `2026-07-07T00:47:30Z` | `1bcb98bad2bb412e11fb186eaef4f6a5c0692853` | Nonempty; 10 inline findings, 2 review-level nitpicks, aggregate AI prompt, and autofix controls |
| `4658642592` | `github-advanced-security[bot]` | COMMENTED | `2026-07-08T23:37:37Z` | `c3512eb87f0acc953c405f20e4322fec08665ddd` | Empty; owns CodeQL inline comment 3547888090 |
| `4678873846` | `github-advanced-security[bot]` | COMMENTED | `2026-07-11T22:41:14Z` | `4834d7bc2eeb5e75ea187ed544b03e48bf64672b` | Empty; owns CodeQL inline comments 3565166744 and 3565166749 |

There are no approvals, change-request reviews, requested reviewers, review replies, labels, or
assignees on the live PR. GitHub reports `MERGEABLE` code state but `BLOCKED` merge state and
`REVIEW_REQUIRED` review decision.

## Detailed finding register

| ID | Sev | Subsystem | Finding | Resolution / status |
|---|---:|---|---|---|
| DR-01 | P1 | Web security | CodeQL alerts 116–118 | Fixed with token/linear parsing; rescan pending |
| DR-02 | P1 | RAG | Similarity threshold ignored by graph | Fixed: pass validated floor to USearch |
| DR-03 | P1 | QHexRT lifecycle | STT/TTS/diffusion cancel could return success | Fixed: request callback records cancel independent of status |
| DR-04 | P1 | Kotlin streaming | Normal Flow close always invoked native cancel | Fixed: cancel only before normal completion |
| DR-05 | P1 | Public release | Public packagers could absorb private QHexRT natives | Fixed: explicit allowlists, exact public package validation, internal-only opt-in |
| DR-06 | P1 | Release | Rebuilt Swift ZIP checksums could differ from tagged manifest | Deterministic ZIP + read-only checksum gate implemented |
| DR-07 | P1 | Privacy | Empty App Privacy collection list despite linked telemetry | Fixed manifest; App Store disclosure must match |
| DR-08 | P1 | Credentials | RN stored HF bearer token in AsyncStorage | Fixed: session-only; legacy value removed |
| DR-09 | P1 | Web storage | MEMFS fallback unusable across multiple WASM instances | Fixed: structured pre-download rejection without OPFS/local dir |
| DR-10 | P1 | CI | Duplicate push + PR matrices and aggregate CodeQL failure | Fixed locally; remote baseline still has duplicate matrices and three open alerts, so next-SHA trigger proof and CodeQL rescan are pending |
| DR-11 | P1 | RN CI | Only core checked; workspace failed on stale declarations | Core declaration build + whole-workspace CI gate fixed |
| DR-12 | P1 | OSS boundary | Fake private QHexRT ABI header committed | Deleted header and dependent approximation tests |
| DR-13 | P2 | IDL | Native multi-query max absent from platform validators | Fixed at canonical IDL; regenerated |
| DR-14 | P2 | QHexRT embeddings | Text API performed implicit local image-path access | Removed heuristic; text stays text |
| DR-15 | P2 | QHexRT bundles | Manifest choice depended on directory iteration order | Fixed: sorted policy-consistent candidates |
| DR-16 | P2 | QAIRT | Discovery could select wrong installed SDK then fail identity | Fixed fail-closed identity-aware discovery; 7 guard tests pass |
| DR-17 | P2 | ABI preflight | Numeric minor check did not express required header symbols | Fixed: compile exact header contract and verify 15 required symbols with `nm` |
| DR-18 | P2 | Secrets | Gitleaks exempted thoughts and whole commits | Fixed: exact public endpoint allowlist only; PR-range scan pending final commit |
| DR-19 | P2 | Legacy enum | Retired MetalRT constant survived in the C API | Deleted; canonical proto slot remains retired and no platform exposes it |
| DR-20 | P2 | HTTP logging | Kotlin printed full URL and response prefix | Fixed: sanitized URL, no body logging |
| DR-21 | P2 | Telemetry | Process-global HTTP-disable flag survived reinit | Reset at initialize/unregister |
| DR-22 | P2 | Obsolete API | Sentry field and compatibility shims survived dependency removal | Deleted from IDL, generated bindings, hand-written APIs, tests, and docs; tag 6 reserved numerically |
| DR-23 | P2 | Native versions | RN/Flutter fallback versions were 0.19.13 | Derive canonical version; fallback 0.19.15 |
| DR-24 | P2 | Catalog | Canary Qwen manifest URL named nonexistent file | Corrected all platform examples/tests to verified `v81/canary-qwen-2.5b.json` |
| DR-25 | P2 | Runtime docs | Contributor guide described deleted +40 router scoring | Corrected to priority selection/advisory runtime metadata |
| DR-26 | P2 | Test privacy | RAG E2E committed a developer home path | Removed; environment-only model paths |
| DR-27 | P2 | Example layers | Large platform view models own reusable policy | Documented risk; no release-time parallel abstraction added |
| DR-28 | P2 | Build credentials | API key can be compiled into example apps | Accepted only for publishable client credential; scan pending |
| DR-29 | P3 | Web docs | Deleted stream-design doc still has references | Fixed: stale references removed |
| DR-30 | P2 | Flutter API | Voice turn stream cancellation stopped only Dart delivery | Fixed: request IDs + exported native cancel ABI + isolation tests |
| DR-31 | P1 | MLX concurrency | Voice cancel could invert locks or miss pre-start inference | Fixed: state/operation locks split, admission handshake + drain, 20-run deterministic stress proof |
| DR-32 | P1 | Android startup | QHexRT registered before Android platform context/skel installation | Fixed: public initialize establishes context first; release instrumentation + device cold-launch pass |
| DR-33 | P2 | Flutter release | Packaging swallowed bootstrap/pub validation failures | Fixed locally: validation now fails closed in every mode; there is no warning-only local escape path |
| DR-34 | P1 | Swift distribution | Root Package.swift defaulted to local binaries and carried a zero MLX checksum | Fixed: remote-by-default env-gated local mode; all five deterministic release checksums generated and verified |
| DR-35 | P1 | Release consumers | Candidate artifacts were downloaded but Swift/Kotlin/RN/Web consumers could still compile older registry/tag pins | Fixed: every consumer is rewired to exact workflow candidates and asserts the resolved graph/version before build |
| DR-36 | P1 | Kotlin OSS boundary | Public packager assembled every module, could copy a stale private QHexRT AAR, and emitted an Android-dependent pseudo-JVM JAR without dependency metadata | Fixed: one deterministic Maven repository ZIP contains only the exact core/LlamaCPP/ONNX AAR, POM, Gradle module metadata, and sources publications; native/class/archive leak guards, private staging deletion, and exact-coordinate consumer hash/dex proof pass |
| DR-37 | P1 | Flutter distribution | Remote native URLs/layouts were stale and the release consumer staged all binaries into the core plugin | Fixed: canonical versioned URLs, package-owned native inventories, public/private split, Android+iOS starter builds |
| DR-38 | P1 | RN distribution | npm tarballs exposed `workspace:*` and could not install outside the monorepo | Fixed: atomic packed-manifest rewrite to exact release pins; validator + five-tarball clean-consumer proof |
| DR-39 | P1 | Kotlin API drift | Hand-written RAG/STT/TTS/VAD/Embeddings defaults and validators overrode canonical generated behavior | Fixed: redundant helpers deleted; consumers use generated defaults/validation; regression tests cover IDL values |
| DR-40 | P1 | LLM contract | LLMGenerateRequest duplicated 19 deprecated inline settings alongside canonical options | Fixed: removed fields, reserved tags, regenerated every SDK, and deleted dual-population/fallback paths |
| DR-41 | P1 | Release automation | Auto-tag calculated from a stale ref and relied on a `GITHUB_TOKEN` tag push to trigger release | Fixed: tag the exact reviewed merge SHA and explicitly dispatch `release.yml` after the tag is pushed |
| DR-42 | P1 | CI signal | Swift/Kotlin/RN/Web gates were advisory and the streaming workflow suppressed every failure while referencing deleted targets | Fixed locally: quality gates are required and the no-op workflow is deleted; remote baseline still ran `streaming-perf`, so next-SHA proof is pending |
| DR-43 | P2 | Toolchains | CI mixed stale action/tool versions and an obsolete Sherpa TTS entry point | Fixed: centralized current toolchains/actions; use the current generation-config TTS API and pinned official source revisions |
| DR-44 | P1 | Apple privacy | Package manifests omitted required-reason DiskSpace API use and were not distributed consistently | Fixed: one canonical manifest is bundled by Swift, RN, Flutter, and the iOS example with matching declarations |
| DR-45 | P1 | Artifact privacy | Published/staged native and WASM artifacts embedded absolute developer checkout paths | Fixed at build recipes with prefix maps; every final package validator rejects host build paths and the release candidates are rebuilt cleanly |
| DR-46 | P1 | Example security | RN persisted a control-plane key and permitted non-loopback plaintext transport; iOS/Android transport settings were too broad | Fixed: session-only key, legacy plaintext deletion, HTTPS enforcement with explicit development loopback, and release cleartext disabled |
| DR-47 | P1 | Public API | Voice/VLM/device/NPU/proto-buffer/vector/archive/module compatibility aliases survived after their replacements | Fixed: deleted across C ABI, exports, JNI/WASM, generated contracts, all five SDKs, examples, and tests |
| DR-48 | P1 | Web lifecycle | Shutdown could overlap initialization and a pre-init services call could permanently suppress Phase 2 | Fixed: lifecycle generation checks, initialize/shutdown serialization, retryable deferred Phase 2, and race tests |
| DR-49 | P1 | Web cancellation | Abort could be lost across awaited admission; VLM leaked listeners; backend unregister left stale lifecycle/registry adapters | Fixed: recheck after awaits, already-aborted handling, stream cleanup, deterministic live-module re-election; unsupported flat STT cancellation parameter removed |
| DR-50 | P1 | Native link ownership | RunAnywhere protobuf v35.1 collided with protobuf objects embedded in Sherpa's static ONNX Runtime archive | Fixed: the private runtime is namespace-isolated as `runanywhere_internal::protobuf`; native/Apple/WASM link gates reject unshaded overlap instead of suppressing duplicate symbols |
| DR-51 | P1 | Android supply chain | Sherpa archive/header cache was mutable and unchecked; declared ORT 1.24.4 did not match the bundled 1.24.3 runtime | Fixed: immutable revision/digest provenance, safe extraction, complete header identity, strict every-ELF/every-`PT_LOAD` checks, and corrected 1.24.3 runtime metadata |
| DR-52 | P1 | Swift concurrency | Swift 6.2 exposed unsafely shared handles, callbacks, timers, and mutable bridge state | Fixed: actor-contained handles, scoped locked state, lifetime barriers, and narrowly justified opaque-handle Sendability; no global concurrency downgrade or compatibility escape hatch |
| DR-53 | P1 | Web supply chain | WASM vendor scripts attempted personal-fork prebuilts before falling back to source | Fixed: official upstream-only source builds pinned to exact ORT/Sherpa commits with recipe provenance |
| DR-54 | P1 | Tool-calling contract | New IDL simultaneously exposed string/enum formats, two max-call fields, a duplicate system-prompt override, and multiple run-loop ABI shapes | Fixed: one typed format, one max-tool-calls field, canonical prompt semantics, and one callback-published cancellable ABI; regenerated and migrated all SDKs |
| DR-55 | P1 | Model metadata | Removing top-level ModelInfo.description made partial description updates replace the complete metadata message and erase tags | Fixed: canonical metadata field plus field-wise partial merge; registry regression test proves tags survive |
| DR-56 | P1 | Android packaging | Compatibility `unified/` native copies duplicated every Android ELF and encouraged package consumers to ignore component ownership | Fixed: canonical per-ABI `{jni,llamacpp,onnx}` roots only; strict allowlists, private rejection, deterministic archives, and all SDK packagers migrated |
| DR-57 | P2 | Release entry points | iOS/Android/Linux wrapper scripts accepted ignored or obsolete selectors and docs/Playgrounds consumed stale output layouts | Fixed: one current invocation per platform/ABI, all consumers/docs migrated, Linux staging made clean and deterministic |
| DR-58 | P1 | Tool-calling policy | `max_tool_calls` was implemented as a generation-turn cap, so the loop could stop immediately after the last permitted side effect without synthesizing a final answer | Fixed: count executor invocations, disable tools at the cap, permit the final synthesis generation, and reject any extra requested side effect before dispatch |
| DR-59 | P1 | Tool result integrity | Follow-up synthesis received only the most recent tool result, so multi-tool turns could lose earlier evidence and produce a final answer from incomplete context | Fixed: both orchestration drivers format the complete ordered result history; regression coverage proves distinct first/second results reach synthesis |
| DR-60 | P1 | Cancellation linearizability | Tool-loop cancellation only toggled lifecycle state, did not invoke the active backend cancel operation, and could race host side-effect admission | Fixed: active generation publication is synchronized, pre-start cancel is latched, backend `ops->cancel` is invoked, and a recursive admission boundary establishes whether cancel or tool dispatch wins |
| DR-61 | P1 | Session teardown | Process-global callback draining and re-entrant destroy could deadlock, publish later queued callbacks after user-data release, or couple unrelated sessions | Fixed: per-session in-flight accounting, thread-local nested dispatch depth, destroy latching, callback nulling, and queued-event suppression provide isolated quiescent teardown |
| DR-62 | P1 | Executor boundary | A successful executor callback could return empty/malformed bytes, a buffer-level error, or a mismatched tool identity; generated call IDs also used a shared unsynchronized PRNG with a small collision space | Fixed: fail-closed decoding/status/identity checks canonicalize result identity, and atomic monotonic IDs replace the shared PRNG; sync/session regressions cover non-mutation and deterministic failures |
| DR-63 | P2 | Tool option surface | The generated API advertised parallel execution and five formats that commons did not implement consistently, while session requests dropped three live policy flags | Fixed: portable formats are JSON and LFM2 only, unsupported parallel execution is deleted, and auto-execute/system-prompt/JSON-argument policy is forwarded by every SDK |
| DR-64 | P1 | Initial-turn cancellation | Flutter could not learn the session handle until blocking session creation returned, making the first generation effectively uncancellable | Fixed: session creation requires a synchronous handle-publication callback before generation; C/JNI, Flutter, and Web consumers use the same callback contract and no output-slot compatibility path remains |
| DR-65 | P2 | Native test isolation | The non-LLM lifecycle fixture registered nonexistent model files directly under the shared system temp root, causing artifact resolution to recursively scan unrelated workspaces (126 seconds and over 1 GB locally) | Fixed: each process creates real placeholder models in an isolated temporary directory and removes it by RAII; the test now completes in under one second |
| DR-66 | P1 | Tool telemetry | A multi-step tool session published generation telemetry per backend step, fragmenting one logical request and risking missing/duplicate terminal publication | Fixed locally: the session owns one aggregate, an RAII terminal scope publishes it exactly once, and destroy publishes a suspended partial aggregate; final native regression pass pending |
| DR-67 | P1 | Public tool ABI | Raw parser structs/helpers and duplicate Apple/WASM exports leaked implementation detail alongside the canonical proto contract | Fixed locally: the public header is proto-only, raw parsing moved to a private internal header, old Apple/WASM exports were removed, and consumers use generated requests; final native/server builds pending |
| DR-68 | P1 | Package publication | Flutter/RN validators could fail open locally and private QHexRT package entrypoints were publishable by ordinary commands | Fixed locally: validation always exits nonzero, RN QHexRT is `private`, Flutter QHexRT is `publish_to: none`, and Kotlin QHexRT has no Maven publication/signing/public repository path; final clean package proofs pending |
| DR-69 | P1 | Web artifact contract | Web accepted older/incomplete WASM registries and treated a primary-module success as a successful multi-module broadcast | Fixed locally: current registry exports are required at module admission, incomplete artifacts fail fast, and broadcasts succeed only when every live module succeeds; targeted tests pass, full final package proof pending |
| DR-70 | P1 | VAD API | Public headers and Apple/WASM export lists advertised a never-implemented flat VAD service lifecycle | Fixed locally: only the live engine service types and canonical lifecycle-proto APIs remain; false declarations/exports and the stale README example were removed; final native/Apple/WASM validation pending |
| DR-71 | P1 | Native API surface | Dead structured-output, diffusion, embeddings, LLM helper, and modality exports remained public after all consumers moved | **In progress**: safe zero-consumer headers/implementations/exports are being deleted or made private while live service/plugin contracts are retained; full native and cross-SDK rebuilds required after the cleanup lands |
| DR-72 | P1 | Deprecated-surface gate | The allowlist accepted path-only entries, allowing any deprecated category in an allowed file to evade the release gate | Fixed locally: allowlist entries must match exact `path|category` pairs and the current 50 structured JSON/type boundaries are explicit; rerun after final cleanup pending |
| DR-73 | P1 | Optional server | The server used removed raw tool structs and debug-logged prompts/messages that may contain user content | Fixed locally: server translation uses generated tool parse/prompt-format requests, requires protobuf, and no longer logs prompt/message bodies; `RAC_BUILD_SERVER=ON` compile validation pending |
| DR-74 | P2 | CMake/Apple build | `LoadVersions.cmake` emitted bare compatibility aliases and the iOS toolchain retained an obsolete bitcode option | **In progress**: the dead bitcode knob/status is removed locally; remaining CMake consumers are being migrated to `RAC_*` version variables before bare aliases are deleted, with Zlib's numeric `FindZLIB` integration kept only where required; fresh configure/build proof pending |
| DR-75 | P1 | Web audio | Microphone capture used deprecated main-thread `ScriptProcessorNode`, risking callback stalls and browser removal | **In progress**: migration to an `AudioWorkletProcessor`/`AudioWorkletNode` with off-main-thread render-quantum aggregation and deterministic teardown is underway; typecheck/tests/package validation pending |
| DR-76 | P1 | Web HTTP / deprecated API | A public JavaScript transport and C++ trampoline ABI depended on synchronous `XMLHttpRequest`, a deprecated main-thread browser primitive retained as an optional fallback | Fixed locally by deleting 1,347 lines of adapter/test code plus the C++ fanout, WASM export, TS types, and stale references; current Emscripten fetch and async platform download paths remain. Web typecheck/lint/build and 173/173 core tests pass; clean Emscripten 6.0.2 artifact validation pending |
| DR-77 | P1 | Apple / dependency ABI | The SwiftPM MLX CLI compiled protobuf 35.1 generated consumers against Homebrew Abseil `lts_20260107`, while packaged RACommons embedded the protobuf fallback's `lts_20250512`, causing unresolved generated-message symbols at final link | Fixed locally by centralizing `ABSEIL_VERSION=20260107.1`, prefetching that exact static source before protobuf, skipping host-Abseil discovery under namespace isolation, and retaining the private protobuf namespace without host dylib rpaths; clean five-framework, CLI, and package validation in progress |
| DR-78 | P1 | Flutter iOS distribution | Apple artifact sync wrote XCFrameworks to `ios/Frameworks`, but current podspec and SwiftPM consumers resolve `ios/<package>/Frameworks`, so clean consumers would not find their native binary | Fixed locally by making the canonical sync use package-owned paths, deleting stale old-layout copies, and checking byte identity; final package and clean-consumer proof pending rebuilt Apple artifacts |
| DR-79 | P2 | RN Android distribution | Public core/LlamaCPP/ONNX packages forced legacy JNI extraction even though only private QHexRT FastRPC skels require on-disk extraction | Fixed locally: public packages use modern JNI packaging; the private QHexRT package and QHex-enabled examples retain extraction solely for the documented DSP-skel filesystem requirement; final public package proof pending rebuilt Android artifacts |
| DR-80 | P2 | Dependency metadata | Public Swift/Kotlin/Flutter/RN ONNX constants and multiple release docs still advertised 1.23.2 after the canonical iOS/Android runtime moved to 1.24.3; the commons README also advertised an obsolete llama.cpp revision | Fixed locally across all consumers/docs, with the release-coherence gate now deriving platform ONNX pins from `VERSIONS` and checking every SDK constant; final gate awaits the concurrent Swift source update |
| DR-81 | P1 | Native CLI / protobuf ABI | CMake `rcli_core` reattached generated protobuf headers and `RAC_HAVE_PROTOBUF` but not the private `google=runanywhere_internal` namespace definition, so its generated constructors could not link to namespace-isolated RACommons | Fixed locally by applying the namespace rewrite to `rcli_core` and every consumer through its public compile contract; fresh rcli configure/build/link proof in progress |
| DR-82 | P1 | RN Android ABI parity | Public core/LlamaCPP/ONNX packages declared a three-ABI release inventory but hard-coded the Nitro bridge's NDK/CMake filters to arm64, yielding arm64-only bridge code beside armv7/x86_64 backend payloads | Fixed locally: both bridge filters consume the exact public arm64/armv7/x86_64 set and Gradle exposes all three CMake task families; private QHexRT remains intentionally arm64-only pending final package rebuild |
| DR-83 | P2 | CLI toolchain | CLI11's default C++20 encoding path instantiated `std::wstring_convert`/`<codecvt>`, deprecated since C++17, in every native and SwiftPM CLI translation unit | Fixed and validated by selecting CLI11's non-codecvt locale-conversion implementation in both `rcli_core` and SwiftPM `RCLIHost`; the incremental `rcli-macos-release` rebuild completed without the warning, and `rcli --version`/`--help` smoke tests pass |
| DR-84 | P1 | Flutter iOS publication | Clean pub.dev archives intentionally omitted XCFrameworks, but CocoaPods and nested SwiftPM manifests only referenced local framework paths; the core ObjC++ wrapper also included an implementation through a monorepo-only relative path. A published package therefore passed dry-run validation yet could not install or compile on iOS. | Fixed and validated with checksum-pinned CocoaPods and SwiftPM release resolution, local-framework preference for monorepo development, one package-local transport mirror guarded byte-for-byte against the canonical source, release version/checksum synchronization gates, and Swift 6-safe Flutter import handling. Clean path-pod installation, corrupt-archive rejection, fixed-HTTPS/local SwiftPM selection, pub archive inventory, and a fully clean Flutter 3.44.6 CocoaPods simulator consumer build all pass. The final current-tree Apple artifact rebuilds, deterministic repacks, and checksum synchronization also pass. |
| DR-85 | P1 | Apple artifact determinism | Repeated `xcodebuild -create-xcframework` invocations reordered `AvailableLibraries` nondeterministically, changing SwiftPM ZIP checksums even when every library and header byte was identical. | Fixed by sorting each XCFramework's library entries by `LibraryIdentifier`, serializing deterministic XML with sorted dictionary keys, and validating the canonical plist before packaging. Two independent current-tree five-framework build/repack runs produced byte-identical ZIPs and checksum sidecars; every root and Flutter SwiftPM checksum matches those archives. |

## Validation ledger

The checked rows below are **pre-final checkpoints**, not proof for the latest native/API cleanup.
Their recorded hashes and counts are preserved as historical evidence and must be refreshed, not
silently reused, after the working tree is stable. The final pass must replace stale values and
remove all “pending” entries.

- [x] Paginated GitHub inventory: 13 inline comments + 1 issue comment + 3 submitted reviews;
  13/13 threads captured, with live state 9 resolved / 4 unresolved and verbatim bodies archived below
- [x] Existing focused Android/Flutter/RN/RAG thread checks
- [x] CodeQL-local focused Web checks
- [x] Generated all Swift/Kotlin/Dart/TS/C++ proto outputs
- [x] React Native full workspace typecheck
- [x] Swift release deterministic-ZIP/checksum fixtures
- [x] Web no-OPFS focused tests/typecheck/lint/build
- [x] Diff hygiene, formatting, and full generator drift (secret scan waits for final commit)
- [x] Commons debug/release configure and build; full debug ctest 97/97
- [x] Swift build/test (41/41) and deterministic archive fixture
- [x] Kotlin full build/test (67/67), ktlint, lint, and module assembly
- [x] Kotlin public Maven repository from three real Android ABIs: 211,048,499 bytes; SHA-256 `180a62eff7cab41b35e870d11dce48e322284b6b61c66a7dff20aaa793ece45a`; identical across two independent packaging invocations and canonical `--natives-from` staging
- [x] Kotlin public artifact validator 10/10: exact repository/coordinate/metadata graph, AAR classes, source publications, ABI-native inventories and ELF architectures, checksum/reproducibility metadata, and QHexRT/QNN rejection
- [x] Pinned Kotlin starter `56423adb3f94768d51968698c4604308b673b4da` resolved all three exact `0.19.15` workflow candidates through the extracted exclusive Maven repository, matched resolved AAR hashes, and assembled its debug APK
- [x] Flutter packages + example tests and debug APK build (final public release candidate rerun pending)
- [x] React Native packages + example tests/typecheck/lint/build; exact four-package public tarball validation
- [x] Web packages + example tests/typecheck/lint/build (179 tests total)
- [x] Latest QHexRT `main` (`1e777794`) receipt build and SDK staging (`5f592a41...`)
- [x] Android SDK AARs + release example APK (197,580,604 bytes; SHA-256 `ff90269576ca40d409fea5640cbcd2d879daaddeef4f8a38636b914d44eb6658`)
- [x] APK inventory and 16 KiB native `LOAD` alignment (31/31 arm64 ELFs; minimum `LOAD` 0x4000; `zipalign -P 16` pass)
- [x] Connected-device compatible in-place install, 127 ms cold launch, top-resumed/process-live/log smoke
- [ ] PR title/description updated
- [ ] Four unresolved threads replied to/resolved (one outdated snapshot thread plus CodeQL
  116–118) and final CodeRabbit review requested
- [ ] Required CI/CD green at final pushed SHA

## Final completion record

Pending final implementation convergence, refreshed artifact hashes/counts, commit/push, four GitHub
thread replies/resolutions, PR title/description, final CodeRabbit review, and green final-SHA CI.

## Verbatim GitHub discussion archive

Snapshot: `2026-07-12T06:37:03Z`. Bodies between six-tilde fences are reproduced verbatim
from the paginated GitHub responses, including bot analysis chains, code suggestions, embedded
AI-agent prompts, fingerprint markers, and checkboxes. The surrounding metadata records the
authoritative IDs, URLs, timestamps, locations, and GraphQL resolution/outdated state.

### Submitted reviews

#### Review `4640749607`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#pullrequestreview-4640749607
- Author: `coderabbitai[bot]`
- State: `COMMENTED`
- Submitted: `2026-07-07T00:47:30Z`
- Commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`
- Author association: `NONE`

**Exact body:**

~~~~~~markdown
**Actionable comments posted: 10**

<details>
<summary>🧹 Nitpick comments (2)</summary><blockquote>

<details>
<summary>sdk/runanywhere-commons/src/features/rag/rag_backend.cpp (1)</summary><blockquote>

`670-691`: _🚀 Performance & Scalability_ | _🔵 Trivial_ | _⚡ Quick win_

**Redundant `all_chunk_texts()` enumeration.**

`vector_store_->all_chunk_texts()` is called at Line 673 (BM25 rebuild) and again at Line 683 (dedup rebuild), re-materializing every chunk id/text twice on load. Enumerate once and reuse.




<details>
<summary>♻️ Reuse a single enumeration</summary>

```diff
-        if (bm25_index_) {
-            bm25_index_->clear();
-            const auto texts = vector_store_->all_chunk_texts();
-            if (!texts.empty())
-                bm25_index_->add_chunks_batch(texts);
-        }
+        const auto texts = vector_store_->all_chunk_texts();
+        if (bm25_index_) {
+            bm25_index_->clear();
+            if (!texts.empty())
+                bm25_index_->add_chunks_batch(texts);
+        }
         {
             std::lock_guard<std::mutex> lock(mutex_);
             next_chunk_id_ = static_cast<size_t>(nid);
             // Rebuild the content-addressed dedup set from restored chunk metadata
             // so a re-ingest after restart is still skipped.
             ingested_content_hashes_.clear();
-            for (const auto& [id, text] : vector_store_->all_chunk_texts()) {
+            for (const auto& [id, text] : texts) {
                 (void)text;
```
</details>

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/runanywhere-commons/src/features/rag/rag_backend.cpp` around lines 670 -
691, The restore path in rag_backend.cpp is enumerating
vector_store_->all_chunk_texts() twice: once for rebuilding bm25_index_ and
again for rebuilding ingested_content_hashes_. Change the rebuild logic in the
same restore block to materialize the chunk id/text list once and reuse that
cached collection for both BM25 rebuild and dedup metadata restoration, keeping
the existing behavior in bm25_index_->add_chunks_batch and the
ingested_content_hashes_ loop.
```

</details>

<!-- cr-comment:v1:0c873ce47d87f18f5a49dda6 -->

</blockquote></details>
<details>
<summary>idl/rag.proto (1)</summary><blockquote>

`216-224`: _🚀 Performance & Scalability_ | _🔵 Trivial_

**Missing upper bound on `multi_query_count`.**

`rac_min = 1` is declared but there's no `rac_max`. Combined with `rac_rag_proto_abi.cpp` passing this value through unclamped (see comment there), a caller can request an arbitrarily large fan-out of query rewrites/retrievals. Consider adding a `rac_max` annotation here for documentation/codegen parity with `RAGConfiguration.top_k`-style bounded fields.
[recommended_refactor_low_effort_high_reward]

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@idl/rag.proto` around lines 216 - 224, The multi-query count field is only
bounded on the minimum side, so add an upper-limit annotation to the
multi_query_count definition to match other bounded configuration fields. Update
the rag.proto declaration for multi_query_count to include a rac_max value
alongside rac_default and rac_min, keeping the limit consistent with the rest of
the RAG config and allowing codegen to enforce the cap.
```

</details>

<!-- cr-comment:v1:f4cf900772987490e000dd1a -->

</blockquote></details>

</blockquote></details>

<details>
<summary>🤖 Prompt for all review comments with AI agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

Inline comments:
In
`@examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/rag/RagViewModel.kt`:
- Around line 93-112: The rerank toggle rebuild in updateRerank only logs
failures, so a failed ragCreatePipeline can leave the pipeline torn down while
rerankEnabled remains changed. Update updateRerank to treat the rebuild as
transactional: capture the previous rerank state, guard against overlapping
rebuilds, and if ragDestroyPipeline()/ragCreatePipeline() fails, restore the old
toggle state and surface an error the UI can react to. Keep the successful path
that refreshes chunkCount from ragGetStatistics(), and use the existing
RACLog/error handling around the rebuild flow.

In `@examples/flutter/RunAnywhereAI/lib/features/rag/rag_view_model.dart`:
- Around line 82-94: The rerank toggle path in setRerankEnabled mutates
_rerankEnabled before awaiting RunAnywhere.rag.destroyPipeline(), so add the
same try/catch and _error handling pattern used in loadDocument to keep state
consistent if pipeline teardown fails. Make sure setRerankEnabled either rolls
back the flag or leaves the model in a coherent error state, sets _error, and
still calls notifyListeners so the UI can react when destroyPipeline throws.

In `@examples/react-native/RunAnywhereAI/src/screens/RAGScreen.tsx`:
- Around line 221-229: `handleRerankChange` currently awaits `handleClearAll()`
without guarding failures, so a rejected pipeline teardown can leave
`rerankEnabled` updated while the UI state is stale. Update the
`handleRerankChange` callback in `RAGScreen` to wrap the `handleClearAll()` call
in try/catch, and on failure surface the error with `setError` the same way
`handleSelectDocument` and `handleAskQuestion` do. Keep the optimistic
`setRerankEnabled` behavior only if you can recover cleanly, and ensure any
teardown error is handled so `RunAnywhere.ragDestroyPipeline()` rejection does
not become unhandled.

In `@sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp`:
- Around line 617-625: Clamp or validate the value assigned to
RAGBackend::QueryOverrides::multi_query_count before it is copied from
query_proto in rac_rag_proto_abi.cpp. The current parsing path in the query
override setup accepts any large caller-provided value when enable_multi_query
is enabled, so add an upper bound check or reject out-of-range inputs before
forwarding the value to the graph. Keep the fix localized to the overrides
construction around query_proto.multi_query_count() so the downstream
RAGGraphInputs::multi_query_count never receives an unbounded count.

In `@sdk/runanywhere-commons/src/features/rag/rag_backend.cpp`:
- Around line 281-287: The add_document() path in rag_backend.cpp is rewriting
the full RAG snapshot on every ingest by calling save_index() after each
document, which makes bulk ingestion quadratic. Change the persistence flow
around add_document() and save_index() so writes are coalesced per batch or
exposed through an explicit flush/save step, and only serialize the vector store
once after a batch of documents has been ingested when config_.persist_index and
config_.index_path are enabled.
- Around line 180-193: `rag_backend::add_document` currently checks
`ingested_content_hashes_` under `mutex_` but reserves the hash only later,
allowing concurrent same-content ingests to both proceed. Move the content-hash
reservation into the same locked section as the `count()` check, or keep the
lock held through the ingest path, so a second call sees the hash as already
claimed before any re-chunking or embedding starts.

In `@sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp`:
- Around line 74-84: The prefix-trimming logic in rag_fusion.cpp is too
aggressive because it strips any leading digit from query variants, which
removes valid content like numbered terms and acronyms. Update the trimming in
the variant parsing block that builds v so it only removes explicit list markers
such as N. or N) (and the existing whitespace/punctuation), and do not treat
bare leading digits as removable numbering.

In `@sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp`:
- Around line 332-345: In load_from_bytes, replace the truncation checks around
idx_len and js_len with overflow-safe bounds validation that compares each
decoded length against the remaining buffer space instead of using pos + length,
and make sure every failure path clears the current store state. On both the
truncated-section returns and the USearch load error path, reset the existing
index/chunks before returning false so the function’s failure behavior matches
its contract.

In `@sdk/runanywhere-commons/tests/test_rag_e2e.cpp`:
- Around line 78-92: `adapter_file_read` does not handle a failed
`std::ifstream::tellg()` result, so a `-1` length can be converted into a huge
`size_t` while still allocating only a 1-byte buffer. Update the logic in
`adapter_file_read` to detect `tellg()` failure before allocating, return an
error when the stream position is invalid, and only assign `out_data`/`out_size`
after confirming a non-negative size so the reported size always matches the
allocated buffer.

In `@sdk/shared/proto-ts/src/convenience/rag_convenience.ts`:
- Line 75: The validation message in the `rag_convenience.ts` logic is awkward
because it says “must be in >= 1”; update the error text used for
`multi_query_count` to remove the stray “in” and keep the wording grammatically
correct. Locate the message in the `m.multiQueryCount` check and adjust only the
string while preserving the same validation behavior.

---

Nitpick comments:
In `@idl/rag.proto`:
- Around line 216-224: The multi-query count field is only bounded on the
minimum side, so add an upper-limit annotation to the multi_query_count
definition to match other bounded configuration fields. Update the rag.proto
declaration for multi_query_count to include a rac_max value alongside
rac_default and rac_min, keeping the limit consistent with the rest of the RAG
config and allowing codegen to enforce the cap.

In `@sdk/runanywhere-commons/src/features/rag/rag_backend.cpp`:
- Around line 670-691: The restore path in rag_backend.cpp is enumerating
vector_store_->all_chunk_texts() twice: once for rebuilding bm25_index_ and
again for rebuilding ingested_content_hashes_. Change the rebuild logic in the
same restore block to materialize the chunk id/text list once and reuse that
cached collection for both BM25 rebuild and dedup metadata restoration, keeping
the existing behavior in bm25_index_->add_chunks_batch and the
ingested_content_hashes_ loop.
```

</details>

<details>
<summary>🪄 Autofix (Beta)</summary>

Fix all unresolved CodeRabbit comments on this PR:

- [ ] <!-- {"checkboxId": "4b0d0e0a-96d7-4f10-b296-3a18ea78f0b9"} --> Push a commit to this branch (recommended)
- [ ] <!-- {"checkboxId": "ff5b1114-7d8c-49e6-8ac1-43f82af23a33"} --> Create a new PR with the fixes

</details>

---

<details>
<summary>ℹ️ Review info</summary>

<details>
<summary>⚙️ Run configuration</summary>

**Configuration used**: defaults

**Review profile**: CHILL

**Plan**: Pro

**Run ID**: `0cb843d0-3226-47a2-86d8-2807e6305baa`

</details>

<details>
<summary>📥 Commits</summary>

Reviewing files that changed from the base of the PR and between 498421605fda557304a1a27990953f6b3451d9be and 1bcb98bad2bb412e11fb186eaef4f6a5c0692853.

</details>

<details>
<summary>⛔ Files ignored due to path filters (11)</summary>

* `sdk/runanywhere-commons/src/generated/proto/rag.pb.cc` is excluded by `!**/generated/**`
* `sdk/runanywhere-commons/src/generated/proto/rag.pb.h` is excluded by `!**/generated/**`
* `sdk/runanywhere-flutter/packages/runanywhere/lib/generated/convenience/ra_convenience.dart` is excluded by `!**/generated/**`
* `sdk/runanywhere-flutter/packages/runanywhere/lib/generated/rag.pb.dart` is excluded by `!**/generated/**`
* `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/RAGConfiguration.kt` is excluded by `!**/generated/**`
* `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/RAGQueryOptions.kt` is excluded by `!**/generated/**`
* `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/convenience/RAConvenience.kt` is excluded by `!**/generated/**`
* `sdk/shared/proto-ts/dist/convenience/rag_convenience.d.ts` is excluded by `!**/dist/**`
* `sdk/shared/proto-ts/dist/convenience/rag_convenience.js` is excluded by `!**/dist/**`
* `sdk/shared/proto-ts/dist/rag.d.ts` is excluded by `!**/dist/**`
* `sdk/shared/proto-ts/dist/rag.js` is excluded by `!**/dist/**`

</details>

<details>
<summary>📒 Files selected for processing (31)</summary>

* `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/rag/RagScreen.kt`
* `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/rag/RagViewModel.kt`
* `examples/flutter/RunAnywhereAI/lib/features/rag/rag_demo_view.dart`
* `examples/flutter/RunAnywhereAI/lib/features/rag/rag_view_model.dart`
* `examples/react-native/RunAnywhereAI/src/screens/RAGScreen.tsx`
* `idl/rag.proto`
* `sdk/runanywhere-commons/AGENTS.md`
* `sdk/runanywhere-commons/CMakeLists.txt`
* `sdk/runanywhere-commons/include/rac/foundation/rac_sha256.h`
* `sdk/runanywhere-commons/src/features/rag/CMakeLists.txt`
* `sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp`
* `sdk/runanywhere-commons/src/features/rag/rag_backend.cpp`
* `sdk/runanywhere-commons/src/features/rag/rag_backend.h`
* `sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp`
* `sdk/runanywhere-commons/src/features/rag/rag_fusion.h`
* `sdk/runanywhere-commons/src/features/rag/rag_pipeline_graph.cpp`
* `sdk/runanywhere-commons/src/features/rag/rag_pipeline_graph.h`
* `sdk/runanywhere-commons/src/features/rag/rag_rerank.cpp`
* `sdk/runanywhere-commons/src/features/rag/rag_rerank.h`
* `sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp`
* `sdk/runanywhere-commons/src/features/rag/vector_store_usearch.h`
* `sdk/runanywhere-commons/src/foundation/rac_sha256.cpp`
* `sdk/runanywhere-commons/src/infrastructure/http/rac_http_download.cpp`
* `sdk/runanywhere-commons/tests/CMakeLists.txt`
* `sdk/runanywhere-commons/tests/data/rag_sample.md`
* `sdk/runanywhere-commons/tests/test_rag_e2e.cpp`
* `sdk/runanywhere-commons/tests/test_rag_fusion.cpp`
* `sdk/runanywhere-commons/tests/test_rag_rerank.cpp`
* `sdk/runanywhere-commons/tests/test_sha256.cpp`
* `sdk/shared/proto-ts/src/convenience/rag_convenience.ts`
* `sdk/shared/proto-ts/src/rag.ts`

</details>

<details>
<summary>✅ Files skipped from review due to trivial changes (3)</summary>

* sdk/runanywhere-commons/tests/data/rag_sample.md
* sdk/runanywhere-commons/AGENTS.md
* sdk/runanywhere-commons/src/features/rag/rag_rerank.cpp

</details>

</details>

<!-- This is an auto-generated comment by CodeRabbit for review status -->
~~~~~~

#### Review `4658642592`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#pullrequestreview-4658642592
- Author: `github-advanced-security[bot]`
- State: `COMMENTED`
- Submitted: `2026-07-08T23:37:37Z`
- Commit: `c3512eb87f0acc953c405f20e4322fec08665ddd`
- Author association: `CONTRIBUTOR`

**Exact body:**

~~~~~~markdown

~~~~~~

#### Review `4678873846`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#pullrequestreview-4678873846
- Author: `github-advanced-security[bot]`
- State: `COMMENTED`
- Submitted: `2026-07-11T22:41:14Z`
- Commit: `4834d7bc2eeb5e75ea187ed544b03e48bf64672b`
- Author association: `CONTRIBUTOR`

**Exact body:**

~~~~~~markdown

~~~~~~

### Issue comments

#### Issue comment `4891148296`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#issuecomment-4891148296
- Author: `coderabbitai[bot]`
- Created: `2026-07-06T09:22:36Z`
- Updated: `2026-07-12T06:23:11Z`
- Author association: `NONE`

**Exact body:**

~~~~~~markdown
<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- review_stack_entry_start -->

[![Review Change Stack](https://storage.googleapis.com/coderabbit_public_assets/review-stack-in-coderabbit-ui.svg)](https://app.coderabbit.ai/change-stack/RunanywhereAI/runanywhere-sdks/pull/531?utm_source=github_walkthrough&utm_medium=github&utm_campaign=change_stack)

<!-- review_stack_entry_end -->
<!-- This is an auto-generated comment: review paused by coderabbit.ai -->

> [!NOTE]
> ## Reviews paused
> 
> It looks like this branch is under active development. To avoid overwhelming you with review comments due to an influx of new commits, CodeRabbit has automatically paused this review. You can configure this behavior by changing the `reviews.auto_review.auto_pause_after_reviewed_commits` setting.
> 
> Use the following commands to manage reviews:
> - `@coderabbitai resume` to resume automatic reviews.
> - `@coderabbitai review` to trigger a single review.
> 
> Use the checkboxes below for quick actions:
> - [ ] <!-- {"checkboxId": "7f6cc2e2-2e4e-497a-8c31-c9e4573e93d1"} --> ▶️ Resume reviews
> - [ ] <!-- {"checkboxId": "e9bb8d72-00e8-4f67-9cb2-caf3b22574fe"} --> 🔍 Trigger review

<!-- end of auto-generated comment: review paused by coderabbit.ai -->
<!-- walkthrough_start -->

<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

The PR updates RAG query contracts, backend snapshot/dedup behavior, retrieval fusion and reranking, client toggles, validation tests, and Android model display mappings. It also adds a React Native package build script.

### Changes

**Inference Framework UI Mapping and Enum Documentation**

|Layer / File(s)|Summary|
|---|---|
|**Update backend badge and label/icon mappings** <br> `examples/android/.../BackendBadge.kt`, `examples/android/.../ModelDisplay.kt`|`backendBadgeColor()` maps `INFERENCE_FRAMEWORK_BUILT_IN` to `primaryGreen`, and `shortLabel()`, `consumerBackendLabel()`, and `backendIcon()` remove explicit GENIE and METALRT cases so those frameworks use fallback mappings.|
|**Clarify retired enum values in native header** <br> `sdk/runanywhere-commons/include/rac/infrastructure/model_management/rac_model_types.h`|Comment above `RAC_FRAMEWORK_METALRT` is updated to explicitly name retired values 9 and 11 while preserving the numeric gap.|

**RAG Retrieval Controls, Persistence, and Hashing**

|Layer / File(s)|Summary|
|---|---|
|**Extend RAG query contracts** <br> `idl/rag.proto`, `sdk/shared/proto-ts/src/rag.ts`, `sdk/shared/proto-ts/src/convenience/rag_convenience.ts`|`RAGQueryOptions` makes `similarity_threshold` optional and adds `enable_multi_query`, `multi_query_count`, and `scope_prefix`; generated bindings, defaults, and validation are updated to match.|
|**Add snapshot, dedup, and hashing support** <br> `sdk/runanywhere-commons/.../rag_backend.*`, `vector_store_usearch.*`, `rac_sha256.*`, `rac_http_download.cpp`, `CMakeLists.txt`, `AGENTS.md`|The backend tracks content hashes, persists and restores index snapshots, fingerprints snapshot validity, forwards rerank and query overrides, and switches to shared SHA-256 plus byte-based vector-store serialization.|
|**Add fusion, rerank, and multi-query graph flow** <br> `sdk/runanywhere-commons/src/features/rag/rag_fusion.*`, `rag_rerank.*`, `rag_pipeline_graph.*`, `sdk/runanywhere-commons/src/features/rag/CMakeLists.txt`|Reciprocal Rank Fusion, LLM pointwise reranking, and multi-query expansion are added to the retrieval graph and wired into the build.|
|**Expose retrieval toggles in client UIs** <br> `examples/android/.../RagScreen.kt`, `examples/android/.../RagViewModel.kt`, `examples/flutter/.../rag_demo_view.dart`, `examples/flutter/.../rag_view_model.dart`, `examples/react-native/.../RAGScreen.tsx`|Android, Flutter, and React Native screens add rerank and multi-query toggles, and their view models pass the settings into pipeline creation and query execution.|
|**Add RAG tests, sample data, and build wiring** <br> `sdk/runanywhere-commons/tests/*`|New SHA-256, fusion, rerank, and end-to-end RAG tests are added, along with a sample markdown corpus and CTest targets for the new executables.|

**React Native Package Build Script**

|Layer / File(s)|Summary|
|---|---|
|**Add package build script** <br> `sdk/runanywhere-react-native/packages/core/package.json`|The package scripts section now includes a build command that runs `tsc -b`.|

**Estimated code review effort:** 5 (Critical) | ~120 minutes

**Possibly related PRs**
- [RunanywhereAI/runanywhere-sdks#419](https://github.com/RunanywhereAI/runanywhere-sdks/pull/419): Adds the Flutter RAG screen and view model foundation that this PR extends with rerank and multi-query controls.
- [RunanywhereAI/runanywhere-sdks#447](https://github.com/RunanywhereAI/runanywhere-sdks/pull/447): Touches the same `vector_store_usearch.cpp` RAG storage path that this PR changes for byte-based persistence.
- [RunanywhereAI/runanywhere-sdks#470](https://github.com/RunanywhereAI/runanywhere-sdks/pull/470): Modifies the `RAGBackend` class declaration in the same header this PR extends with persistence and query override fields.

</details>

<!-- walkthrough_end -->
<!-- pre_merge_checks_walkthrough_start -->

<details>
<summary>🚥 Pre-merge checks | ✅ 5</summary>

<details>
<summary>✅ Passed checks (5 passed)</summary>

|         Check name         | Status   | Explanation                                                                                                                                                 |
| :------------------------: | :------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------- |
|     Docstring Coverage     | ✅ Passed | No functions found in the changed files to evaluate docstring coverage. Skipping docstring coverage check.                                                  |
|     Linked Issues check    | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                                                                    |
| Out of Scope Changes check | ✅ Passed | Check skipped because no linked issues were found for this pull request.                                                                                    |
|         Title check        | ✅ Passed | The title is concise and covers the main change set across SDKs, RAG, packaging, and CI.                                                                    |
|      Description check     | ✅ Passed | The description covers the main sections and change types, but it does not fully match the template headings or platform-specific testing checklist format. |

</details>

</details>

<!-- pre_merge_checks_walkthrough_end -->
<!-- finishing_touch_checkbox_start -->

<details>
<summary>✨ Finishing Touches</summary>

<details>
<summary>📝 Generate docstrings</summary>

- [ ] <!-- {"checkboxId": "7962f53c-55bc-4827-bfbf-6a18da830691"} --> Create stacked PR
- [ ] <!-- {"checkboxId": "3e1879ae-f29b-4d0d-8e06-d12b7ba33d98"} --> Commit on current branch

</details>
<details>
<summary>🧪 Generate unit tests (beta)</summary>

- [ ] <!-- {"checkboxId": "f47ac10b-58cc-4372-a567-0e02b2c3d479", "radioGroupId": "utg-output-choice-group-unknown_comment_id"} -->   Create PR with unit tests
- [ ] <!-- {"checkboxId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "radioGroupId": "utg-output-choice-group-unknown_comment_id"} -->   Commit unit tests in branch `siddhesh/sdk-audit-fixes-v2`

</details>

</details>

<!-- finishing_touch_checkbox_end -->
<!-- tips_start -->

---

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=RunanywhereAI/runanywhere-sdks&utm_content=531)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

<details>
<summary>❤️ Share</summary>

- [X](https://twitter.com/intent/tweet?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A&url=https%3A//coderabbit.ai)
- [Mastodon](https://mastodon.social/share?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A%20https%3A%2F%2Fcoderabbit.ai)
- [Reddit](https://www.reddit.com/submit?title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&text=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code.%20Check%20it%20out%3A%20https%3A//coderabbit.ai)
- [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fcoderabbit.ai&mini=true&title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&summary=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code)

</details>


<sub>Comment `@coderabbitai help` to get the list of available commands.</sub>

<!-- tips_end -->
~~~~~~

### Inline review comments and threads

#### Inline comment `3532871035`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871035
- Thread ID: `PRRT_kwDOPQhgos6OwmKl`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T06:47:36Z`
- Path: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/rag/RagViewModel.kt`
- Current range: start `93`, end `189`, side `RIGHT`
- Original range: start `93`, end `112`
- Resolved: `true`
- Outdated: `false`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🩺 Stability & Availability_ | _🟠 Major_ | _⚡ Quick win_

<details>
<summary>🧩 Analysis chain</summary>

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

# Locate the ViewModel and any RAG clear/persistence bindings.
git ls-files | rg 'RagViewModel\.kt|rag|RAG|clear.*snapshot|delete_snapshot|persist_index|index_path|ragClearDocuments|ragDestroyPipeline|ragCreatePipeline'

# Show the relevant ViewModel section with line numbers.
sed -n '1,260p' examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/rag/RagViewModel.kt

# Search for native bindings and backend snapshot lifecycle.
rg -n 'ragClearDocuments|delete_snapshot|persist_index|index_path|save_index|load_index|clear\(' examples/android/RunAnywhereAI app src . -g '!**/build/**' -g '!**/.gradle/**'
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 50386

---

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

# Native clear path: does ragClearDocuments delete the persisted snapshot?
sed -n '720,760p' sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp

# Backend persistence lifecycle around clear/load/save/delete.
sed -n '540,700p' sdk/runanywhere-commons/src/features/rag/rag_backend.cpp

# Kotlin bridge for ragClearDocuments, if present.
sed -n '1,240p' sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/public/extensions/RAG/RunAnywhereRAG.kt

# Search for any explicit error/state rollback around rerank toggles or pipeline recreation.
rg -n 'ragDestroyPipeline|ragCreatePipeline|updateRerank|pipelineKey|error =|onFailure|rerank' examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/rag/RagViewModel.kt sdk/runanywhere-commons/src/features/rag -g '!**/build/**'
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 24825

---



</details>

**Handle rerank rebuild failures instead of only logging them.** If `ragDestroyPipeline()` succeeds and `ragCreatePipeline()` fails, the pipeline is left torn down while `rerankEnabled` stays flipped; rapid toggles can also overlap rebuilds. Roll back the toggle and surface an error so the UI can recover.

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In
`@examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/rag/RagViewModel.kt`
around lines 93 - 112, The rerank toggle rebuild in updateRerank only logs
failures, so a failed ragCreatePipeline can leave the pipeline torn down while
rerankEnabled remains changed. Update updateRerank to treat the rebuild as
transactional: capture the previous rerank state, guard against overlapping
rebuilds, and if ragDestroyPipeline()/ragCreatePipeline() fails, restore the old
toggle state and surface an error the UI can react to. Keep the successful path
that refreshes chunkCount from ragGetStatistics(), and use the existing
RACLog/error handling around the rebuild flow.
```

</details>

<!-- fingerprinting:phantom:poseidon:beignet -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:a076ef7d2e6ac54c22762fec -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 33e223e to 035f026
~~~~~~

#### Inline comment `3532871041`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871041
- Thread ID: `PRRT_kwDOPQhgos6OwmKo`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T20:03:22Z`
- Path: `examples/flutter/RunAnywhereAI/lib/features/rag/rag_view_model.dart`
- Current range: start `82`, end `102`, side `RIGHT`
- Original range: start `82`, end `94`
- Resolved: `true`
- Outdated: `false`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🩺 Stability & Availability_ | _🟡 Minor_ | _⚡ Quick win_

**Missing error handling around pipeline rebuild on rerank toggle.**

`_rerankEnabled` is mutated before `await RunAnywhere.rag.destroyPipeline()`. If that call throws, the exception is unhandled (caller does `unawaited(...)`), and `notifyListeners()` is never called — leaving `_rerankEnabled` flipped while `_isDocumentLoaded`/`_documentName` are stale, with no user-visible error. `loadDocument()` right below already establishes the try/catch + `_error` pattern; apply it here too.



<details>
<summary>🐛 Proposed fix</summary>

```diff
   Future<void> setRerankEnabled(bool value) async {
     if (_rerankEnabled == value) return;
-    _rerankEnabled = value;
-    if (_isDocumentLoaded) {
-      await RunAnywhere.rag.destroyPipeline();
-      _isDocumentLoaded = false;
-      _documentName = null;
-      _messages = [];
-    }
-    notifyListeners();
+    final previous = _rerankEnabled;
+    _rerankEnabled = value;
+    if (_isDocumentLoaded) {
+      try {
+        await RunAnywhere.rag.destroyPipeline();
+        _isDocumentLoaded = false;
+        _documentName = null;
+        _messages = [];
+      } catch (e) {
+        _rerankEnabled = previous;
+        _error = e.toString();
+      }
+    }
+    notifyListeners();
   }
```
</details>

<!-- suggestion_start -->

<details>
<summary>📝 Committable suggestion</summary>

> ‼️ **IMPORTANT**
> Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

```suggestion
  // Rerank rebuilds the pipeline, so changing it after a document is loaded
  // resets the session (re-add the document), matching a model change.
  Future<void> setRerankEnabled(bool value) async {
    if (_rerankEnabled == value) return;
    final previous = _rerankEnabled;
    _rerankEnabled = value;
    if (_isDocumentLoaded) {
      try {
        await RunAnywhere.rag.destroyPipeline();
        _isDocumentLoaded = false;
        _documentName = null;
        _messages = [];
      } catch (e) {
        _rerankEnabled = previous;
        _error = e.toString();
      }
    }
    notifyListeners();
  }
```

</details>

<!-- suggestion_end -->

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@examples/flutter/RunAnywhereAI/lib/features/rag/rag_view_model.dart` around
lines 82 - 94, The rerank toggle path in setRerankEnabled mutates _rerankEnabled
before awaiting RunAnywhere.rag.destroyPipeline(), so add the same try/catch and
_error handling pattern used in loadDocument to keep state consistent if
pipeline teardown fails. Make sure setRerankEnabled either rolls back the flag
or leaves the model in a coherent error state, sets _error, and still calls
notifyListeners so the UI can react when destroyPipeline throws.
```

</details>

<!-- fingerprinting:phantom:poseidon:beignet -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:c3801833a49e907ff51a8a24 -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 20ad990 to 05596e5
~~~~~~

#### Inline comment `3532871047`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871047
- Thread ID: `PRRT_kwDOPQhgos6OwmKs`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T06:57:38Z`
- Path: `examples/react-native/RunAnywhereAI/src/screens/RAGScreen.tsx`
- Current range: start `221`, end `252`, side `RIGHT`
- Original range: start `221`, end `229`
- Resolved: `true`
- Outdated: `false`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🩺 Stability & Availability_ | _🟡 Minor_ | _⚡ Quick win_

**`handleRerankChange` has no error handling for pipeline teardown.**

`handleClearAll()` (called here) awaits `RunAnywhere.ragDestroyPipeline()` without a try/catch, and this handler is wired directly to `Switch.onValueChange`. If the destroy call rejects, it becomes an unhandled promise rejection, `rerankEnabled` has already been optimistically flipped, and `documents`/`messages` are never cleared — leaving the UI referencing a pipeline that may already be gone. Other handlers in this file (`handleSelectDocument`, `handleAskQuestion`) consistently catch and surface errors via `setError`; apply the same pattern here.



<details>
<summary>🐛 Proposed fix</summary>

```diff
   const handleRerankChange = useCallback(async (value: boolean) => {
-    setRerankEnabled(value);
-    if (documents.length > 0) {
-      await handleClearAll();
-    }
-  }, [documents.length, handleClearAll]);
+    try {
+      if (documents.length > 0) {
+        await handleClearAll();
+      }
+      setRerankEnabled(value);
+    } catch (err) {
+      const msg = err instanceof Error ? err.message : 'Failed to update rerank setting';
+      setError(msg);
+    }
+  }, [documents.length, handleClearAll]);
```
</details>

<!-- suggestion_start -->

<details>
<summary>📝 Committable suggestion</summary>

> ‼️ **IMPORTANT**
> Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

```suggestion
  // Rerank is a pipeline-level setting, so changing it rebuilds the pipeline.
  // The current corpus is dropped (re-add documents), matching a model change.
  const handleRerankChange = useCallback(async (value: boolean) => {
    try {
      if (documents.length > 0) {
        await handleClearAll();
      }
      setRerankEnabled(value);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to update rerank setting';
      setError(msg);
    }
  }, [documents.length, handleClearAll]);
```

</details>

<!-- suggestion_end -->

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@examples/react-native/RunAnywhereAI/src/screens/RAGScreen.tsx` around lines
221 - 229, `handleRerankChange` currently awaits `handleClearAll()` without
guarding failures, so a rejected pipeline teardown can leave `rerankEnabled`
updated while the UI state is stale. Update the `handleRerankChange` callback in
`RAGScreen` to wrap the `handleClearAll()` call in try/catch, and on failure
surface the error with `setError` the same way `handleSelectDocument` and
`handleAskQuestion` do. Keep the optimistic `setRerankEnabled` behavior only if
you can recover cleanly, and ensure any teardown error is handled so
`RunAnywhere.ragDestroyPipeline()` rejection does not become unhandled.
```

</details>

<!-- fingerprinting:phantom:poseidon:beignet -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:0ac5fbd8a7d683b2256c3836 -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 33e223e to 0d2aafc
~~~~~~

#### Inline comment `3532871052`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871052
- Thread ID: `PRRT_kwDOPQhgos6OwmKv`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T06:47:47Z`
- Path: `sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp`
- Current range: start `617`, end `710`, side `RIGHT`
- Original range: start `617`, end `625`
- Resolved: `true`
- Outdated: `false`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🚀 Performance & Scalability_ | _🟠 Major_ | _⚡ Quick win_

<details>
<summary>🧩 Analysis chain</summary>

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

# Locate the relevant proto, validation, and query override code.
rg -n --hidden --glob '!**/node_modules/**' \
  'multi_query_count|enable_multi_query|similarity_threshold|validate_rag_configuration|QueryOverrides|RAGQueryOptions|RAGConfiguration' \
  sdk/runanywhere-commons idl . || true

# Map the target implementation file.
ast-grep outline sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp --view expanded || true
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 50387

---

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

# Read the proto definition and any nearby validation code in smaller slices.
for f in \
  sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp \
  sdk/runanywhere-commons/src/features/rag/rac_rag_configuration.cpp \
  sdk/runanywhere-commons/src/features/rag/rac_rag_configuration.h \
  idl/*.proto
do
  [ -f "$f" ] && { echo "### $f"; wc -l "$f"; }
done

# Show the specific regions likely relevant to the concern.
sed -n '600,660p' sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp
sed -n '1,220p' sdk/runanywhere-commons/src/features/rag/rac_rag_configuration.h 2>/dev/null || true
sed -n '1,260p' sdk/runanywhere-commons/src/features/rag/rac_rag_configuration.cpp 2>/dev/null || true
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 5417

---

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

# Find the exact proto message definitions.
rg -n --hidden 'message (RAGQueryOptions|RAGConfiguration)|multi_query_count|enable_multi_query|similarity_threshold' idl sdk/runanywhere-commons/src/features/rag -g '*.proto' -g '*.h' -g '*.cpp'

# If the query path is wired through additional validation, locate it.
rg -n --hidden 'validate_rag_configuration|validate.*query|QueryOverrides|RAGGraphInputs|multi_query_count' sdk/runanywhere-commons/src/features/rag -g '*.cpp' -g '*.h'
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 8204

---



</details>

**Clamp `multi_query_count` before passing it to the graph** `RAGQueryOptions.multi_query_count` has only a minimum bound, so a caller can send a very large value here. When `enable_multi_query` is on, that feeds straight into `RAGGraphInputs::multi_query_count` and can trigger an arbitrary number of LLM rewrites/retrieval passes. Clamp it to a documented ceiling or reject out-of-range values before copying it into `overrides`.

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp` around lines
617 - 625, Clamp or validate the value assigned to
RAGBackend::QueryOverrides::multi_query_count before it is copied from
query_proto in rac_rag_proto_abi.cpp. The current parsing path in the query
override setup accepts any large caller-provided value when enable_multi_query
is enabled, so add an upper bound check or reject out-of-range inputs before
forwarding the value to the graph. Keep the fix localized to the overrides
construction around query_proto.multi_query_count() so the downstream
RAGGraphInputs::multi_query_count never receives an unbounded count.
```

</details>

<!-- fingerprinting:phantom:poseidon:beignet -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:de1317b031b84ebb8cc50563 -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 33e223e to 035f026
~~~~~~

#### Inline comment `3532871055`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871055
- Thread ID: `PRRT_kwDOPQhgos6OwmKy`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T06:48:00Z`
- Path: `sdk/runanywhere-commons/src/features/rag/rag_backend.cpp`
- Current range: start `180`, end `233`, side `RIGHT`
- Original range: start `180`, end `193`
- Resolved: `true`
- Outdated: `false`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🗄️ Data Integrity & Integration_ | _🟠 Major_ | _🏗️ Heavy lift_

<details>
<summary>🧩 Analysis chain</summary>

🏁 Script executed:

```shell
#!/bin/bash
# Is add_document reachable from concurrent callers on the same session?
rg -nP -C4 'add_document|ingest' sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 4529

---

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

# Inspect the backend implementation around add_document and its locking.
file=sdk/runanywhere-commons/src/features/rag/rag_backend.cpp
ast-grep outline "$file" --view expanded || true

echo '--- add_document references ---'
rg -n -C 6 'add_document|ingested_content_hashes_|mutex_|chunk|embed|insert' "$file"
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 22240

---



</details>

**Serialize the content-hash reservation in `add_document`.** The check and insert on `ingested_content_hashes_` are split across two lock scopes, so two same-content ingests on one session can both pass, embed, and append duplicate chunks. The session ABI does not impose a single-session restriction, so reserve the hash under the lock before releasing it, or guard the whole ingest path.

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/runanywhere-commons/src/features/rag/rag_backend.cpp` around lines 180 -
193, `rag_backend::add_document` currently checks `ingested_content_hashes_`
under `mutex_` but reserves the hash only later, allowing concurrent
same-content ingests to both proceed. Move the content-hash reservation into the
same locked section as the `count()` check, or keep the lock held through the
ingest path, so a second call sees the hash as already claimed before any
re-chunking or embedding starts.
```

</details>

<!-- fingerprinting:phantom:medusa:capybara -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:3682757be402a7d58d57ff9c -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 33e223e to 035f026
~~~~~~

#### Inline comment `3532871056`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871056
- Thread ID: `PRRT_kwDOPQhgos6OwmK0`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T06:57:43Z`
- Path: `sdk/runanywhere-commons/src/features/rag/rag_backend.cpp`
- Current range: start `null`, end `null`, side `RIGHT`
- Original range: start `281`, end `287`
- Resolved: `true`
- Outdated: `true`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `33e223e58afc406259f911dd7e50549f847c2133`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🚀 Performance & Scalability_ | _🟠 Major_ | _🏗️ Heavy lift_

<details>
<summary>🧩 Analysis chain</summary>

🏁 Script executed:

```shell
#!/bin/bash
# How is add_document invoked during ingest? Per-document or batched?
rg -nP -C3 '\badd_document\s*\(' sdk/runanywhere-commons/src
# Any existing batch/flush entry point that could own persistence instead?
rg -nP -C2 '\b(save_index|ingest_batch|add_documents)\b' sdk/runanywhere-commons/src
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 6790

---

🏁 Script executed:

```shell
#!/bin/bash
sed -n '174,290p' sdk/runanywhere-commons/src/features/rag/rag_backend.cpp
printf '\n---\n'
sed -n '520,545p' sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp
printf '\n---\n'
rg -n '\bsave_index\s*\(' sdk/runanywhere-commons/src/features/rag
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 6218

---



</details>

**Avoid rewriting the entire RAG snapshot on every ingest.**

`add_document()` calls `save_index()` once per request, and `save_index()` serializes and rewrites the entire vector store each time. With persistence enabled, bulk ingest becomes quadratic. Coalesce persistence or add an explicit flush/save path so the snapshot is written once per batch instead of once per document.

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/runanywhere-commons/src/features/rag/rag_backend.cpp` around lines 281 -
287, The add_document() path in rag_backend.cpp is rewriting the full RAG
snapshot on every ingest by calling save_index() after each document, which
makes bulk ingestion quadratic. Change the persistence flow around
add_document() and save_index() so writes are coalesced per batch or exposed
through an explicit flush/save step, and only serialize the vector store once
after a batch of documents has been ingested when config_.persist_index and
config_.index_path are enabled.
```

</details>

<!-- fingerprinting:phantom:medusa:capybara -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:85f819828dc012e08a71bba0 -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 33e223e to 0d2aafc
~~~~~~

#### Inline comment `3532871058`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871058
- Thread ID: `PRRT_kwDOPQhgos6OwmK1`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T06:48:13Z`
- Path: `sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp`
- Current range: start `74`, end `93`, side `RIGHT`
- Original range: start `74`, end `84`
- Resolved: `true`
- Outdated: `false`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🎯 Functional Correctness_ | _🟡 Minor_ | _⚡ Quick win_

<details>
<summary>🧩 Analysis chain</summary>

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

git ls-files 'sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp' 'sdk/runanywhere-commons/src/features/rag/*' | sed 's#^`#FILE` #'
echo '--- outline ---'
ast-grep outline sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp --view expanded || true
echo '--- relevant lines ---'
sed -n '1,220p' sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp
echo '--- search parse_query_variants usages ---'
rg -n "parse_query_variants|query variants|fuse_rankings" sdk/runanywhere-commons/src/features/rag -S
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 5781

---

🏁 Script executed:

```shell
#!/bin/bash
set -euo pipefail

# Look for tests or documentation describing the accepted format for query variants.
rg -n "2024 tax deadlines|3D printing basics|leading list marker|numbered list|bullet" sdk/runanywhere-commons -S || true

# Show surrounding implementation if parse_query_variants is in a smaller section.
sed -n '1,140p' sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 3689

---

🏁 Script executed:

```shell
python3 - <<'PY'
import string

def strip(line):
    s = 0
    while s < len(line) and (line[s].isspace() or line[s] in "-*.)" or line[s].isdigit()):
        s += 1
    e = len(line)
    while e > s and line[e-1].isspace():
        e -= 1
    return line[s:e]

samples = [
    "2024 tax deadlines",
    "3D printing basics",
    "1. tax deadlines",
    "  - hello",
    "  12) hello",
]
for x in samples:
    print(f"{x!r} -> {strip(x)!r}")
PY
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 338

---



</details>

**Don't strip bare leading digits from query variants.** `2024 tax deadlines` and `3D printing basics` lose real content here because any leading digit is treated as numbering. Limit stripping to an explicit `N.` / `N)` prefix.

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/runanywhere-commons/src/features/rag/rag_fusion.cpp` around lines 74 -
84, The prefix-trimming logic in rag_fusion.cpp is too aggressive because it
strips any leading digit from query variants, which removes valid content like
numbered terms and acronyms. Update the trimming in the variant parsing block
that builds v so it only removes explicit list markers such as N. or N) (and the
existing whitespace/punctuation), and do not treat bare leading digits as
removable numbering.
```

</details>

<!-- fingerprinting:phantom:medusa:capybara -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:f0caef4580b6042a2e6b6781 -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 33e223e to 035f026
~~~~~~

#### Inline comment `3532871064`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871064
- Thread ID: `PRRT_kwDOPQhgos6OwmK5`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T00:47:31Z`
- Path: `sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp`
- Current range: start `null`, end `null`, side `RIGHT`
- Original range: start `332`, end `345`
- Resolved: `false`
- Outdated: `true`
- Resolved by: `null`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `33e223e58afc406259f911dd7e50549f847c2133`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🩺 Stability & Availability_ | _🟠 Major_ | _⚡ Quick win_

<details>
<summary>🧩 Analysis chain</summary>

🏁 Script executed:

```shell
sed -n '280,390p' sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 4451

---

🏁 Script executed:

```shell
rg -n "reset-to-empty|load:|clear\(\)|load_from_bytes|load\(" sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp sdk/runanywhere-commons/src/features/rag -g '!**/build/**'
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 7041

---

🏁 Script executed:

```shell
sed -n '1,220p' sdk/runanywhere-commons/src/features/rag/vector_store_usearch.h && printf '\n---\n' && sed -n '620,710p' sdk/runanywhere-commons/src/features/rag/rag_backend.cpp
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 7944

---

🏁 Script executed:

```shell
rg -n "load_index\(" sdk/runanywhere-commons/src/features/rag -g '!**/build/**' && printf '\n---\n' && sed -n '1,180p' sdk/runanywhere-commons/src/features/rag/rag_backend.cpp
```

Repository: RunanywhereAI/runanywhere-sdks

Length of output: 6662

---



</details>

**Use overflow-safe length checks and clear state on all load failures.** `sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp:332-345`

`pos + idx_len` / `pos + js_len` can wrap on crafted lengths, so compare against the remaining space instead. Also, `load_from_bytes()` promises to reset the store on any failure, but the truncation and USearch-load error paths return without clearing the existing index/chunks.

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/runanywhere-commons/src/features/rag/vector_store_usearch.cpp` around
lines 332 - 345, In load_from_bytes, replace the truncation checks around
idx_len and js_len with overflow-safe bounds validation that compares each
decoded length against the remaining buffer space instead of using pos + length,
and make sure every failure path clears the current store state. On both the
truncated-section returns and the USearch load error path, reset the existing
index/chunks before returning false so the function’s failure behavior matches
its contract.
```

</details>

<!-- fingerprinting:phantom:medusa:capybara -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:617f1175fa4adb4e6559c3b6 -->

<!-- This is an auto-generated comment by CodeRabbit -->
~~~~~~

#### Inline comment `3532871065`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871065
- Thread ID: `PRRT_kwDOPQhgos6OwmK6`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:28Z`
- Updated: `2026-07-07T06:48:41Z`
- Path: `sdk/runanywhere-commons/tests/test_rag_e2e.cpp`
- Current range: start `78`, end `94`, side `RIGHT`
- Original range: start `78`, end `92`
- Resolved: `true`
- Outdated: `false`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_🩺 Stability & Availability_ | _🟡 Minor_ | _⚡ Quick win_

**Guard against negative `tellg()` result in `adapter_file_read`.**

If `f.tellg()` returns -1 (stream failure), `n > 0 ? ... : 1` correctly allocates a 1-byte buffer, but `*out_size = static_cast<size_t>(n)` still casts -1 to a huge `size_t`, leaving `out_data`/`out_size` inconsistent (1-byte buffer, huge reported size).



<details>
<summary>🐛 Proposed fix</summary>

```diff
-    const std::streamsize n = f.tellg();
+    const std::streamsize n = std::max<std::streamsize>(f.tellg(), 0);
     f.seekg(0);
     auto* buf = static_cast<uint8_t*>(std::malloc(n > 0 ? static_cast<size_t>(n) : 1));
```
</details>

<!-- suggestion_start -->

<details>
<summary>📝 Committable suggestion</summary>

> ‼️ **IMPORTANT**
> Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

```suggestion
rac_result_t adapter_file_read(const char* path, void** out_data, size_t* out_size, void*) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f)
        return RAC_ERROR_FILE_NOT_FOUND;
    const std::streamsize n = std::max<std::streamsize>(f.tellg(), 0);
    f.seekg(0);
    auto* buf = static_cast<uint8_t*>(std::malloc(n > 0 ? static_cast<size_t>(n) : 1));
    if (!buf)
        return RAC_ERROR_OUT_OF_MEMORY;
    if (n > 0)
        f.read(reinterpret_cast<char*>(buf), n);
    *out_data = buf;
    *out_size = static_cast<size_t>(n);
    return RAC_SUCCESS;
}
```

</details>

<!-- suggestion_end -->

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/runanywhere-commons/tests/test_rag_e2e.cpp` around lines 78 - 92,
`adapter_file_read` does not handle a failed `std::ifstream::tellg()` result, so
a `-1` length can be converted into a huge `size_t` while still allocating only
a 1-byte buffer. Update the logic in `adapter_file_read` to detect `tellg()`
failure before allocating, return an error when the stream position is invalid,
and only assign `out_data`/`out_size` after confirming a non-negative size so
the reported size always matches the allocated buffer.
```

</details>

<!-- fingerprinting:phantom:poseidon:beignet -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:6162a91dd3676da0d20d22fc -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 33e223e to 035f026
~~~~~~

#### Inline comment `3532871068`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3532871068
- Thread ID: `PRRT_kwDOPQhgos6OwmK8`
- Review ID: `4640749607`
- Author: `coderabbitai[bot]`
- Created: `2026-07-07T00:47:29Z`
- Updated: `2026-07-07T20:03:28Z`
- Path: `sdk/shared/proto-ts/src/convenience/rag_convenience.ts`
- Current range: start `null`, end `null`, side `RIGHT`
- Original range: start `null`, end `75`
- Resolved: `true`
- Outdated: `true`
- Resolved by: `coderabbitai[bot]`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `70dadcbbf76248aeed1bea113d3653659f2d8cfb`
- Original commit: `1bcb98bad2bb412e11fb186eaef4f6a5c0692853`

**Exact body:**

~~~~~~markdown
_📐 Maintainability & Code Quality_ | _🟡 Minor_ | _⚡ Quick win_

**Fix error message grammar.**

`must be in >= 1` reads awkwardly; drop the stray `in`.




<details>
<summary>✏️ Proposed wording</summary>

```diff
-      message: `multi_query_count must be in >= 1 (got ${m.multiQueryCount})`,
+      message: `multi_query_count must be >= 1 (got ${m.multiQueryCount})`,
```
</details>

<!-- suggestion_start -->

<details>
<summary>📝 Committable suggestion</summary>

> ‼️ **IMPORTANT**
> Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

```suggestion
      message: `multi_query_count must be >= 1 (got ${m.multiQueryCount})`,
```

</details>

<!-- suggestion_end -->

<details>
<summary>🤖 Prompt for AI Agents</summary>

```
Verify each finding against current code. Fix only still-valid issues, skip the
rest with a brief reason, keep changes minimal, and validate.

In `@sdk/shared/proto-ts/src/convenience/rag_convenience.ts` at line 75, The
validation message in the `rag_convenience.ts` logic is awkward because it says
“must be in >= 1”; update the error text used for `multi_query_count` to remove
the stray “in” and keep the wording grammatically correct. Locate the message in
the `m.multiQueryCount` check and adjust only the string while preserving the
same validation behavior.
```

</details>

<!-- fingerprinting:phantom:medusa:capybara -->

<!-- cr-indicator-types:potential_issue -->

<!-- cr-comment:v1:37e7c320a383c25065183b53 -->

<!-- This is an auto-generated comment by CodeRabbit -->

✅ Addressed in commits 20ad990 to 05596e5
~~~~~~

#### Inline comment `3547888090`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3547888090
- Thread ID: `PRRT_kwDOPQhgos6PaCgA`
- Review ID: `4658642592`
- Author: `github-advanced-security[bot]`
- Created: `2026-07-08T23:37:37Z`
- Updated: `2026-07-08T23:37:37Z`
- Path: `examples/web/RunAnywhereAI/src/services/model-display.ts`
- Current range: start `66`, end `70`, side `RIGHT`
- Original range: start `66`, end `70`
- Resolved: `false`
- Outdated: `false`
- Resolved by: `null`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `c3512eb87f0acc953c405f20e4322fec08665ddd`

**Exact body:**

~~~~~~markdown
## CodeQL / Incomplete multi-character sanitization

This string may still contain [on](1), which may cause an HTML attribute injection vulnerability.

[Show more details](https://github.com/RunanywhereAI/runanywhere-sdks/security/code-scanning/116)
~~~~~~

#### Inline comment `3565166744`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3565166744
- Thread ID: `PRRT_kwDOPQhgos6QJjRc`
- Review ID: `4678873846`
- Author: `github-advanced-security[bot]`
- Created: `2026-07-11T22:41:14Z`
- Updated: `2026-07-11T22:41:14Z`
- Path: `sdk/runanywhere-web/packages/core/src/Adapters/DeviceRegistrationAdapter.ts`
- Current range: start `190`, end `190`, side `RIGHT`
- Original range: start `null`, end `190`
- Resolved: `false`
- Outdated: `false`
- Resolved by: `null`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `4834d7bc2eeb5e75ea187ed544b03e48bf64672b`

**Exact body:**

~~~~~~markdown
## CodeQL / Polynomial regular expression used on uncontrolled data

This [regular expression](1) that depends on [library input](2) may run slow on strings with many repetitions of '/'.

[Show more details](https://github.com/RunanywhereAI/runanywhere-sdks/security/code-scanning/117)
~~~~~~

#### Inline comment `3565166749`

- URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/531#discussion_r3565166749
- Thread ID: `PRRT_kwDOPQhgos6QJjRh`
- Review ID: `4678873846`
- Author: `github-advanced-security[bot]`
- Created: `2026-07-11T22:41:14Z`
- Updated: `2026-07-11T22:41:14Z`
- Path: `sdk/runanywhere-web/packages/core/src/Foundation/BackendContract.ts`
- Current range: start `29`, end `29`, side `RIGHT`
- Original range: start `null`, end `29`
- Resolved: `false`
- Outdated: `false`
- Resolved by: `null`
- Reply-to comment: `null`
- Review state: `COMMENTED`
- Comment state: `SUBMITTED`
- Current commit: `c9f950058b9b8b29b8f03d221288a0ef8fbcaa22`
- Original commit: `4834d7bc2eeb5e75ea187ed544b03e48bf64672b`

**Exact body:**

~~~~~~markdown
## CodeQL / Polynomial regular expression used on uncontrolled data

This [regular expression](1) that depends on [library input](2) may run slow on strings starting with '#' and with many repetitions of '#'.
This [regular expression](1) that depends on [library input](3) may run slow on strings starting with '#' and with many repetitions of '#'.
This [regular expression](1) that depends on [library input](4) may run slow on strings starting with '#' and with many repetitions of '#'.
This [regular expression](1) that depends on [library input](5) may run slow on strings starting with '#' and with many repetitions of '#'.
This [regular expression](1) that depends on [library input](6) may run slow on strings starting with '#' and with many repetitions of '#'.

[Show more details](https://github.com/RunanywhereAI/runanywhere-sdks/security/code-scanning/118)
~~~~~~
