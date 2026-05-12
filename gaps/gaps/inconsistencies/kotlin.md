# Kotlin / Android+JVM SDK — Open Inconsistencies

Updated: 2026-05-12 (post-Wave 1..6 + Audit Waves V1+V2 + B9 deep audit + Wave C 8-agent audit + Wave E2E physical-device pass)
Branch: `feat/v2-architecture`
Latest commit: `4fb4caafa` (Wave E2E: VLM rotation + TTS Float32→Int16 + STT VAD gate + VAD screen + tool-call UI; pushed to origin)
Working tree state: clean.

This document lists ONLY what is still open. Closed items have been removed — see git log + `gaps/gaps/PR review/kotlin.md` for history.

Source-of-truth baseline: `sdk/runanywhere-swift/Sources/RunAnywhere/` (Swift, post-Wave-7).

---

## Build status

| Target | Status |
|---|---|
| `./gradlew clean compileKotlinJvm` | PASS (warnings only) |
| `./gradlew compileDebugKotlinAndroid` | PASS (warnings only) |
| `./gradlew assembleDebug` | PASS (AAR built) |
| `./gradlew :modules:runanywhere-core-llamacpp:assembleDebug` | PASS |
| `./gradlew :modules:runanywhere-core-onnx:assembleDebug` | PASS |

Warnings remaining (all pre-existing, no Wave 1..6 introductions):
- `expect`/`actual` classes in Beta (Kotlin Multiplatform).
- `EventBus` unchecked cast on `Flow<SDKEvent>` -> `Flow<T>`.
- `NativeLoader` nullable receiver warning.

---

## Audit 2026-05-11

Eight parallel audit agents verified Kotlin SDK alignment against Swift `ARCHITECTURE.md`. Verdict: **~97% aligned.** Four areas returned FULLY ALIGNED; four returned MOSTLY ALIGNED with small drift items.

### Audit verdicts (8 agents)

| Agent | Scope | Verdict |
|---|---|---|
| 1 | Folder layout vs Swift `Sources/RunAnywhere/` | FULLY ALIGNED |
| 2 | Public API surface (commonMain extensions + RunAnywhere entry point) | MOSTLY ALIGNED (drift: SwiftAliases count, SDKConstants strings) |
| 3 | CppBridge layer (40 files) | FULLY ALIGNED |
| 4 | Foundation layer (errors, constants, core, security) | MOSTLY ALIGNED (drift: SDKConstants canonical strings; RASDKError.from(rcResult:) missing; SDKException.validationFailed factory missing) |
| 5 | Adapters + streaming layer | FULLY ALIGNED |
| 6 | Infrastructure layer (logging, device, filemanagement, download) | MOSTLY ALIGNED (drift: DeviceInfo port question) |
| 7 | Features layer (TTS Services/System, multi-platform actuals) | FULLY ALIGNED |
| 8 | JNI surface (`RunAnywhereBridge.kt`, orphan thunks) | MOSTLY ALIGNED (drift: 7 racDiffusion_* orphan thunks; 32 unannotated orphans) |

### Drift items resolved (V1+V2 cleanup waves)

| Wave | Action | Result | LOC |
|---|---|---|---|
| V1.1 | Verify `VoiceAgentStreamAdapter.kt` | Confirmed present in `jvmAndroidMain/adapters/` (187 LOC) | 0 |
| V1.2 | Verify `CppBridgeEmbeddings.kt` | KEEP — JNI plumbing distinct from `EmbeddingsProtoHelpers.kt` | 0 |
| V1.3 | Verify `CppBridgeSDKEventStream.kt` | KEEP — lower-level than `CppBridgeSDKEvents.kt` | 0 |
| V2.1 | SDKConstants canonicalization | `SDK_NAME` -> `"RunAnywhere SDK"`, added `PRODUCTION_LOG_LEVEL`, updated `USER_AGENT` format. Builds PASS. | +11 |
| V2.2 | `RASDKError.Companion.from(rcResult:)` + JNI thunk `racResultToProtoError` | Added factory + JNI thunk. Builds PASS. | +60 |
| V2.3 | `SDKException.validationFailed` factory | Added. Builds PASS. | +9 |
| V2.4 | DeviceInfo port question | NOT NEEDED — Swift DeviceInfo.swift is mostly Apple-specific; Kotlin equivalent already exists via `CppBridgeDevice.DeviceInfoProvider` + `CppBridgeHardware` + `PhysicalMemoryProbe` | 0 |
| V2.5 | Orphan JNI thunk cleanup | 7 `racDiffusion_*` orphan thunks DELETED; 32 remaining orphans annotated `CALLBACK_TARGET` / `UTILITY` / `PENDING` | net +12 |

**Net LOC impact of V1+V2:** +92 LOC (+80 commonMain, +12 jvmAndroidMain net after diffusion deletes).

**Build verification:** `./gradlew clean compileKotlinJvm compileDebugKotlinAndroid assembleDebug` PASS after each V2 sub-wave.

All architectural drift identified by the 8-agent audit is now resolved. Remaining open items are LOW severity, pending commons-side C ABI / commons JNI work, pre-existing cosmetic warnings, or deferred testing/migration passes — see below.

---

## Open items

### KOTLIN-VOICE-AGENT-CREATE-4HANDLE (LOW, pending commons JNI)

- **Status:** Wave 3 chose **Option B** — `CppBridgeVoiceAgent` continues using `racVoiceAgentCreateStandalone` + `racVoiceAgentInitializeWithLoadedModels`. The composite `getHandle()` suspend gathers handles from 4 child `ComponentActor`s.
- **Blocker:** The 4-handle JNI binding for `rac_voice_agent_create(llm, stt, tts, vad)` is not yet declared in `RunAnywhereBridge.kt`. The commons C ABI `rac_voice_agent_create` is itself DEPRECATED, so the right move is to un-deprecate (or replace) commons-side before exposing the JNI thunk.
- **TODO marker:** `KOT-VOICE-AGENT-COMPOSITE` — switch to Path A (single 4-handle create) once the JNI thunk + commons C ABI land.

### KOTLIN-VLM-CANCEL-LIFECYCLE-JNI (LOW, pending commons JNI)

- **Status:** `CppBridgeVLM` cancel routes through new `racVlmCancelLifecycleProto` JNI thunk declared in `RunAnywhereBridge.kt`. Kotlin code is ready; commons side may not yet wire the C ABI back to the cpp `rac_vlm_cancel_lifecycle_proto`. Fallback to handle-based cancel works in the interim.
- **Action:** Confirm commons-side cpp + verify end-to-end on physical device once one is available.

### KOTLIN-DEVICE-PERSISTENT-ID-JNI (LOW, pending commons JNI)

- **Status:** `rac_device_get_or_create_persistent_id` JNI binding is missing from `RunAnywhereBridge.kt`. Wave 5 slimmed `CppBridgeDevice` 1,226 -> 510 LOC; the persistent-id path is the only feature the Kotlin bridge still cannot drive.
- **Action:** Add the JNI thunk + Kotlin wrapper when commons-side stabilizes (or confirm the Swift implementation as the canonical reference).

### KOTLIN-LLM-STREAMING-SINGLE-CALL (INFO)

- **Status:** Matches Swift behavior — LLM streaming continues to be single-call (one callback registration per `generateStream` invocation). `LLMStreamAdapter` was added in Wave 2 as a forward-looking abstraction for fan-out **if/when** a set/unset proto-callback JNI lands and the SDK wants multiple subscribers per handle.
- **Action:** None today. Adapter file is harmless (120 LOC); flip to fan-out path when commons exposes the per-handle subscribe/unsubscribe ABI.

### KOTLIN-ANDROID-EXAMPLE-APP-MIGRATION (HIGH, deferred)

- **Status:** Wave 1 substantially changed the SDK API surface (modality-specific load/unload/current accessors collapsed onto unified `loadModel`/`currentModel`/`componentLifecycleSnapshot`; VAD orchestration helpers, VoiceAgent per-step primitives, Storage availability/plan, embed/diffusion/auth-as-namespace surfaces all removed).
- **Blocker:** `examples/android/RunAnywhereAI/` consumers reference deleted symbols (10+ files under `presentation/` already partially modified in the working tree). The example app is INTENTIONALLY left to a separate pass per the user directive ("SDK-only refactor; consumers later").
- **Action:** A dedicated example-app migration pass (separate commit group) should be run AFTER Waves 1..6 commit. Re-run `:app:assembleDebug` to identify all unresolved references and migrate to the new API surface, then re-launch on emulator + physical device.

### KOTLIN-PHYSICAL-DEVICE-E2E (deferred)

- **Status:** All per-modality drills (LLM, VLM, STT, TTS, VAD, Voice Agent, RAG, LoRA, Tool Calling, Structured Output, Benchmarks, Solutions) are UNTESTED on physical Android device or Android emulator post Waves 1..6.
- **Blocker:** Requires a connected device + working example app (`KOTLIN-ANDROID-EXAMPLE-APP-MIGRATION` must close first).
- **Action:** User to run validation drills per `test_workflows/instructions/kotlin/README.md` once the example app builds clean against the Wave 1..6 surface.

### KOTLIN-DETEKT-KTLINT (LOW)

- **Status:** Detekt + ktlint not yet run against the Wave 1..6 working tree. Only `compileKotlinJvm` + `compileDebugKotlinAndroid` + `assembleDebug` have been gated.
- **Action:** Run `./gradlew detekt ktlintCheck` once the working tree is committed in wave groups; address any new findings introduced by the refactor.

### KOTLIN-EVENTBUS-UNCHECKED-CAST (LOW, pre-existing)

- **Status:** `EventBus.kt` has `'Type 'SDKEvent' is final, so the value of the type parameter is predetermined'` + `'Unchecked cast of 'Flow<SDKEvent>' to 'Flow<T>'`. Predates Wave 1..6.
- **Action:** Narrow the generic to `T : SDKEvent` properly, or drop the generic since `SDKEvent` is final. Cosmetic.

---

## Open items — Wave B9 audit (2026-05-11)

Five parallel deep-audit agents (B9.1 through B9.5) executed today. **B9.5 (folder/naming) returned FULLY ALIGNED with zero drift items.** B9.1–B9.4 identified ~900+ LOC of dead code across ~75+ items plus 5 JNI silent time-bombs (declared `external fun` whose C++ `Java_*` export is missing — will throw `UnsatisfiedLinkError` at first call).

Severity legend:
- **HIGH**: Zero callers AND entire file dead, OR runtime time-bomb (silent crash).
- **MED**: Zero callers but used internally / partial dead surface / stale duplicate.
- **LOW**: Cosmetic / refactor opportunity (no functional impact).

### Public API legacy (B9.1)

#### KOTLIN-PUBLIC-API-IS-MODEL-DUPLICATES (MED)

- **Location:** `commonMain/.../public/extensions/Models/ModelTypes.kt`
- **Finding:** 3 duplicate `is*Model` accessor extensions on `RAModelInfo` (e.g., `isLLMModel`, `isSTTModel`, `isTTSModel` overlap categorization already exposed by `category` proto field).
- **Action:** Delete the 3 `is*Model` accessors; let callers compare `category == MODEL_CATEGORY_*`.

#### KOTLIN-PUBLIC-API-INFERENCE-FRAMEWORK-SWITCH (MED)

- **Location:** Hand-rolled `when (framework) { ... }` switch tables in `ModelTypes.kt` / `ModelTypesArtifacts.kt`.
- **Finding:** Switches duplicate codegen — proto already provides string mapping via `wireString`-style extensions.
- **Action:** Delete hand-rolled switches and route through generated `wireString` / `inferenceFrameworkOf(...)` helpers.

#### KOTLIN-PUBLIC-API-LOADMODEL-OVERLOAD (HIGH)

- **Location:** `commonMain/.../public/extensions/Models/RunAnywhereModelLifecycle.kt`
- **Finding:** `loadModel(modelId: String)` convenience overload exists alongside canonical `loadModel(RAModelLoadRequest)`. Zero callers in SDK.
- **Action:** Delete the `String`-arg overload + its jvmAndroid actual.

#### KOTLIN-PUBLIC-API-CONFIGURE-TELEMETRY-BASEURL (HIGH)

- **Location:** `commonMain/.../public/RunAnywhere.kt` — `configureTelemetryBaseUrl(...)` expect.
- **Finding:** Swift parity-target API was deprecated; Kotlin has zero callers.
- **Action:** Delete the expect + jvmAndroid actual + jvmAndroid bridge thunk.

#### KOTLIN-PUBLIC-API-DUPLICATE-PROTO-TYPEALIASES (MED, 2 sites)

- **Locations:** `commonMain/.../public/types/SwiftAliases.kt` and various per-modality `*Types.kt` files (e.g., `LLM/ToolCallingTypes.kt`).
- **Finding:** Two typealias declarations point to the same generated proto type — duplicate aliases (D5, D6 from audit).
- **Action:** Pick the RA-prefixed alias in `SwiftAliases.kt` as canonical; delete the per-modality duplicates.

#### KOTLIN-PUBLIC-API-STALE-TODOS (LOW)

- **Location:** `commonMain/.../public/RunAnywhere.kt` — 5 stale TODO comments marked `B5.x` (W3 vintage).
- **Finding:** All referenced work is complete; comments are orphaned navigation hints.
- **Action:** Delete the 5 TODOs in `RunAnywhere.kt`.

### CppBridge dead surfaces (B9.2)

#### KOTLIN-DEAD-CPPBRIDGE-SDKINIT (HIGH)

- **Location:** `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeSdkInit.kt` (~150 LOC, post-Wave-5 rename from `CppBridgeServices.kt`).
- **Finding:** Entire file is unwired — no call sites from `CppBridge.kt`, `PlatformBridge.kt`, or any modality bridge. Phase 1/2 init coordinator lives entirely in `CppBridge.kt`.
- **Action:** Delete the file.

#### KOTLIN-DEAD-CPPBRIDGE-STRATEGY (HIGH)

- **Location:** `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeStrategy.kt` (~120 LOC).
- **Finding:** File body is unwired stubs — ArchiveType conversions superseded by codegen. Zero callers.
- **Action:** Delete the file.

#### KOTLIN-DEAD-CPPBRIDGE-SERVICES (HIGH)

- **Location:** `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeServices.kt` (~85 LOC).
- **Finding:** Stale stub file (predates Wave-5 rename to `CppBridgeSdkInit.kt`). Zero callers.
- **Action:** Delete the file.

#### KOTLIN-DEAD-CPPBRIDGE-PLATFORM (HIGH)

- **Location:** `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgePlatform.kt` (~52 LOC).
- **Finding:** No-op object — Phase 2 lifecycle placeholder; real platform-adapter registration is in `CppBridgePlatformAdapter.kt`. Zero callers.
- **Action:** Delete the file.

#### KOTLIN-DEAD-CPPBRIDGE-ENDPOINTS (HIGH)

- **Location:** `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeEnvironment.kt` — internal `object CppBridgeEndpoints` (~80 LOC).
- **Finding:** Inner object inside `CppBridgeEnvironment.kt`; zero callers anywhere in tree.
- **Action:** Delete the `CppBridgeEndpoints` inner object (keep the rest of `CppBridgeEnvironment.kt`).

#### KOTLIN-DEAD-CPPBRIDGE-DOC-ONLY-FILES (LOW)

- **Locations:** `CppBridgeNativeProtoABI.kt` (170 LOC), `CppBridgeModalityProtoABI.kt` (192 LOC).
- **Finding:** Pure documentation files with empty/no-op `assertAvailable` guards. May be retained as living architectural docs.
- **Action:** Either delete or annotate `@file:Suppress` and add a banner comment marking documentation-only.

#### KOTLIN-VOICEAGENT-DUAL-PATH (MED)

- **Location:** `jvmAndroidMain/.../foundation/bridge/extensions/CppBridgeVoiceAgent.kt`.
- **Finding:** Standalone path (`getRawHandle` via `racVoiceAgentCreateStandalone`) coexists with composite path (`getHandle` from 4 child ComponentActors). Option B chose composite; standalone should be deleted.
- **Action:** Delete `getRawHandle` + `racVoiceAgentCreateStandalone` + `racVoiceAgentInitializeWithLoadedModels` once `KOTLIN-VOICE-AGENT-CREATE-4HANDLE` lands.

### Foundation / Adapters / Infrastructure (B9.3)

#### KOTLIN-DEAD-RASDKERRORHELPERS (HIGH)

- **Location:** `commonMain/.../foundation/errors/RASDKErrorHelpers.kt` (entire file, 145 LOC).
- **Finding:** All 6 helper extensions have zero callers in the tree. Direct Swift port without actual Kotlin uptake.
- **Action:** Delete the file.

#### KOTLIN-DEAD-SDKEXCEPTION-FACTORIES (MED)

- **Location:** `commonMain/.../foundation/errors/SDKException.kt` — 22 of the 40+ companion-object factory methods (~250 LOC).
- **Finding:** 22 factories have zero callers. Examples include speculative error variants that mirror Swift but were never used in Kotlin call sites.
- **Action:** Audit factory-by-factory; delete the 22 zero-caller factories.

#### KOTLIN-DEAD-SDKLOGGER-EXTRAS (MED)

- **Location:** `commonMain/.../infrastructure/logging/SDKLogger.kt` — 7 convenience `LogLogger` accessors: `core`, `onnx`, `vlm`, `download`, `llamacpp`, `genie`, `network`.
- **Finding:** All 7 have zero callers. Were ported from Swift's per-domain loggers but Kotlin uses a single `SDKLogger.shared` everywhere.
- **Action:** Delete the 7 convenience loggers.

#### KOTLIN-DEAD-LLMSTREAMADAPTER (HIGH)

- **Location:** `commonMain/.../adapters/LLMStreamAdapter.kt` (entire file, 121 LOC).
- **Finding:** File self-documents as "not currently wired" (forward-looking abstraction). LLM streaming is single-call through `CppBridgeLLM`. Zero callers.
- **Action:** Delete the file. Reintroduce when commons exposes per-handle subscribe/unsubscribe ABI (tracked by `KOTLIN-LLM-STREAMING-SINGLE-CALL`).

#### KOTLIN-DEAD-RASDKCOMPONENTDISPLAYNAME (HIGH)

- **Location:** `commonMain/.../foundation/core/RASDKComponentDisplayName.kt` (entire file, 29 LOC).
- **Finding:** Extension properties on `RASDKComponent` for display-name strings. Zero callers — Swift counterpart is used by UI layer but Kotlin example app doesn't import it.
- **Action:** Delete the file.

#### KOTLIN-DEAD-BUILDTOKEN (HIGH)

- **Location:** `commonMain/.../foundation/constants/BuildToken.kt` (entire file, 33 LOC).
- **Finding:** Auto-generated dev-token placeholder. Zero callers. **Verify** no release-script overwrites this file at packaging time before deleting.
- **Action:** Confirm no `scripts/*.sh` or `gradle.properties` references `BuildToken`, then delete.

#### KOTLIN-DEAD-DOWNLOADPROGRESS-SUGAR (HIGH)

- **Location:** `commonMain/.../infrastructure/download/models/output/DownloadProgress.kt` (entire file, 137 LOC).
- **Finding:** Wrapper data class + helpers around the raw Wire proto type. SDK call sites use only the raw proto type — the sugar layer has zero callers.
- **Action:** Delete the file.

#### KOTLIN-DEAD-KEYCHAIN-MIGRATION (HIGH)

- **Location:** `androidMain/.../foundation/security/AndroidKeychainManager.kt` — legacy migration block (~70 LOC).
- **Finding:** Block migrates from SDK ≤ 0.19.x storage layout. Current SDK is 0.19.13; the migration window is closed (no remaining ≤ 0.19.x consumers in this branch).
- **Action:** Delete the migration block.

#### KOTLIN-DEAD-SENTRYMANAGER-METHODS (MED)

- **Location:** `jvmAndroidMain/.../infrastructure/logging/SentryManager.kt` — 5 dead methods.
- **Finding:** `captureError`, `captureMessage`, `setUser`, `clearUser`, `addBreadcrumb` all have zero callers. Sentry init + auto-breadcrumbs are exercised; manual capture methods are not.
- **Action:** Delete the 5 methods.

#### KOTLIN-DEAD-COMMONS-ERROR-HELPERS (LOW)

- **Location:** `commonMain/.../foundation/errors/CommonsErrorMapping.kt` — `CommonsErrorCode.isSuccess` / `.isError` extension properties.
- **Finding:** Zero callers.
- **Action:** Delete the 2 helper properties; keep the underlying `RAC_SUCCESS` const.

#### KOTLIN-REFACTOR-HOIST-PLATFORM (LOW)

- **Locations:** 5 sites hardcode the string `"android"` (platform identifier) + 1 site hardcodes `MIN_CREDENTIAL_LENGTH`.
- **Finding:** Should reference `SDKConstants.SDK_PLATFORM` and `SDKConstants.MIN_CREDENTIAL_LENGTH`.
- **Action:** Hoist the 5 string literals to `SDKConstants` and add `MIN_CREDENTIAL_LENGTH` const.

### JNI surface (B9.4)

#### KOTLIN-DEAD-NATIVEFILEMANAGER-DUPLICATES (HIGH)

- **Location:** `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt` — 9 `external fun nativeFileManager*(...)` declarations.
- **Finding:** 9 zero-caller thunks superseded by `racFileManager*` (post-Wave 4 proto-canonical naming). Annotated as `// UTILITY` in V2.5 audit but actually dead.
- **Action:** Delete the 9 `nativeFileManager*` external funs + their C++ `Java_*` exports.

#### KOTLIN-DEAD-NATIVEEXTRACTARCHIVE (HIGH)

- **Location:** `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt` — 5 `external fun nativeExtract*(...)` declarations.
- **Finding:** 5 zero-caller archive-extraction thunks. Superseded by proto-canonical extract path (handled C++-side after V2.5 cleanup).
- **Action:** Delete the 5 thunks + C++ `Java_*` exports.

#### KOTLIN-JNI-TIMEBOMBS (HIGH)

- **Location:** `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt`.
- **Finding:** 5 `external fun` declarations have call sites in Kotlin but their corresponding C++ `Java_*` exports are MISSING. First call throws `UnsatisfiedLinkError` at runtime — silent time-bomb. The 5 thunks are:
  1. `racResultToProtoError` — V2.2 added Kotlin side; C++ side never landed.
  2. `racSdkInitPhase1Proto` — Phase 1 init via proto bytes; called by `CppBridge.initialize()`.
  3. `racSdkInitPhase2Proto` — Phase 2 init via proto bytes; called by `CppBridge.completeServicesInitialization()`.
  4. `racSdkRetryHttpProto` — HTTP retry helper; called by `HTTPClientAdapter`.
  5. `racVlmCancelLifecycleProto` — VLM cancel; called by `CppBridgeVLM.cancel()` (with fallback to handle-based cancel).
- **Action:** Either add C++ `Java_*` exports OR delete the Kotlin `external fun` + call sites. `KOTLIN-VLM-CANCEL-LIFECYCLE-JNI` already tracks (5); the other 4 are net-new from B9.4.

#### KOTLIN-CPPBRIDGE-MODELPATHS-DUPLICATE (LOW)

- **Location:** `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt` — `racModelPathsSetBaseDir` vs `racModelPathsSetBaseDirectory`.
- **Finding:** Two `external fun` declarations point to the same C++ function (one is a renamed alias from a prior wave). One has 0 callers; the other has 1+.
- **Action:** Delete the unused name; keep the one with callers.

#### KOTLIN-JNI-CATCH-FALLBACKS (MED)

- **Locations:** ~25 sites across `CppBridgeLLM/STT/TTS/VAD/VLM/VoiceAgent/Telemetry/Auth/Device/Storage/...` (any bridge file that introduced a JNI call during the proto-byte migration).
- **Finding:** `try { /* JNI call */ } catch (e: UnsatisfiedLinkError) { /* fallback */ }` or `catch (e: Throwable) { /* swallow */ }` blocks were added when JNI was being progressively wired. JNI is now fully wired for all 25 sites — the fallback blocks are unreachable.
- **Action:** Delete the 25 catch-blocks. Keep a single top-level safety net only in `CppBridge.initialize()`.

### Summary table — B9 DELETE candidates

| Severity | Count | LOC range | Risk if unaddressed |
|---|---:|---:|---|
| HIGH (zero callers, entire file dead OR runtime time-bomb) | 14 | ~600+ | Silent runtime crashes (5 time-bombs); ongoing maintenance cost of dead code |
| MED (zero callers OR partial dead surface OR stale duplicate) | 8 | ~300 | Code review confusion; refactor blockers |
| LOW (cosmetic / refactor / doc-only) | 4 | ~50 | None functional; cleanup opportunity |
| **TOTAL** | **26** | **~950 LOC** | — |

Plus 5 JNI time-bombs (`KOTLIN-JNI-TIMEBOMBS`) and 1 stale duplicate pair (`KOTLIN-CPPBRIDGE-MODELPATHS-DUPLICATE`) tracked under HIGH/LOW.

---

## Wave C deep audit (2026-05-11)

Eight parallel audit agents (C1 through C8) executed today against the post-B9 working tree to verify JNI surface, catch-Throwable hygiene, public-API parity, CppBridge to-dos, backend modules, test parity, Gradle/tooling drift, and example-app blockers.

### Agent verdicts (8 agents)

| Agent | Scope | Headline result |
|---|---|---|
| C1 | JNI time-bombs / orphans (`RunAnywhereBridge.kt` vs C++ `Java_*` exports) | **8 confirmed time-bombs** + 1 dead declaration + 13 C++-only orphans (intentional placeholders). 249 Kotlin extern fun, 253 C++ exports, 240 matched, 9 Kotlin-only |
| C2 | `catch (Throwable)` blocks (126 total) | **30 OBSOLETE-FALLBACK** (cleanup available) + 96 LEGITIMATE-DEFENSIVE (keep) |
| C3 | Public API surface vs Swift parity | **5 HIGH-MISSING APIs**, 4 DELETE candidates, 3 RENAME candidates (require example-app migration) |
| C4 | CppBridge to-dos (40 bridge files) | **14 to-dos** — file deletes, boot-boolean duplication, typed-param fixes, telemetry env type loss, auth/state split, ModelPaths hardcoded table, ModelRegistry framework consts |
| C5 | Backend modules (`runanywhere-core-llamacpp`, `runanywhere-core-onnx`) | **11 to-dos** — missing Sherpa plugin auto-registration, defaultPriority unused, dual register overloads, unused JNI externs, namespace mismatch, abiFilters drift |
| C6 | Tests (9 Kotlin vs 6 Swift) | **3 BROKEN tests** (compile errors) + 3 GAPS (StructuredOutput, ModelImport, AudioCapture) |
| C7 | Gradle / tooling drift | **18 cleanups** — dead `testLocal` alias, dead version properties, ~14 unused catalog entries, detekt paths, compileSdk inconsistency, dead script references |
| C8 | Example-app migration blockers | Migration is small (~13 LOC across 4 files): ChatViewModel, ModelSelectionBottomSheet, DocumentRAGScreen, BenchmarkRunner. `displayName` is canonical (no migration). **Recommendation: MIGRATE NOW** |

### C1 — JNI time-bombs (HIGH PRIORITY)

#### KOTLIN-JNI-TIMEBOMBS-WAVE-C (HIGH)

- **Location:** `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt`.
- **Finding:** **8 confirmed time-bombs** (`external fun` with callers in Kotlin but no C++ `Java_*` export). First call will throw `UnsatisfiedLinkError` at runtime:

  | # | Thunk | Caller location |
  |---|---|---|
  | 1 | `racHttpDefaultHeaders` | HTTP transport adapter (jvmAndroidMain) |
  | 2 | `racHttpRequestExecuteWithUpsert` | HTTP transport adapter (jvmAndroidMain) |
  | 3 | `racApiErrorFromResponse` | HTTP error mapping (jvmAndroidMain) |
  | 4 | `racVadConfigureLifecycleProto` | `CppBridgeVAD` |
  | 5 | `racVadStartLifecycleProto` | `CppBridgeVAD` |
  | 6 | `racVadStopLifecycleProto` | `CppBridgeVAD` |
  | 7 | `racVadResetLifecycleProto` | `CppBridgeVAD` |
  | 8 | `racVlmCancelLifecycleProto` | `CppBridgeVLM.cancel()` (already tracked in `KOTLIN-VLM-CANCEL-LIFECYCLE-JNI`) |

- **Action:** Either add C++ `Java_*` exports OR delete Kotlin `external fun` + migrate call sites. Note: B9.4 had identified 5 different time-bombs (`racSdkInitPhase1Proto`/`Phase2Proto`/`racSdkRetryHttpProto`/`racResultToProtoError`/`racVlmCancelLifecycleProto`). Wave C re-audit finds those 4 may have been verified resolved or were inaccurate; remaining HIGH-pending JNI thunks are the 5 listed above plus the 3 HTTP thunks. **Net new from Wave C: HTTP (3) + VAD lifecycle (4) = 7 thunks beyond `KOTLIN-VLM-CANCEL-LIFECYCLE-JNI`**.

#### KOTLIN-DEAD-RAC-RESULT-TO-PROTO-ERROR (HIGH)

- **Location:** `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt` — `external fun racResultToProtoError(...)`.
- **Finding:** Zero callers in Kotlin tree AND no C++ `Java_*` export. Originally added in V2.2 alongside `RASDKError.Companion.from(rcResult:)`, but no SDK consumer has wired it. Pure dead declaration — SAFE DELETE.
- **Action:** Delete the `external fun` declaration. If `RASDKError.Companion.from(rcResult:)` factory is also unused (per B9.3 KOTLIN-DEAD-RASDKERRORHELPERS), delete it too.

### C2 — Catch-Throwable cleanup

#### KOTLIN-CATCH-THROWABLE-OBSOLETE (MED)

- **Total:** 126 `catch (Throwable)` blocks across the SDK. **30 OBSOLETE-FALLBACK** (cleanup available) + **96 LEGITIMATE-DEFENSIVE** (keep).
- **OBSOLETE blocks identified by file:**
  - `CppBridgeEnvironment.kt`: ~13 blocks
  - `CppBridgeState.kt`: ~8 blocks
  - `CppBridgeModelAssignment.kt`: 4 blocks
  - `CppBridgePlatformAdapter.kt`: 1 block
  - `CppBridge.kt`: 2 helper blocks
  - `CppBridgeLoraRegistry.kt`: 4 blocks (pending verification)
- **LEGITIMATE blocks (keep):**
  - Reflection-based calls (Android `Build` class introspection)
  - Pre-thunk HTTP TODOs (before transport landed)
  - Proto-decode translation (broad exception surface from generated Wire code)
  - Shutdown best-effort cleanup
  - Native-lib bring-up (`System.loadLibrary` fallback paths)
- **Action:** Audit 30 OBSOLETE blocks file-by-file; replace with specific exception types or delete entirely.

### C3 — Public API parity

#### KOTLIN-MISSING-STORAGE-API (HIGH)

- **Locations:** `commonMain/.../public/extensions/Storage/RunAnywhereStorage.kt`, `Models/RunAnywhereModelRegistry.kt`.
- **Finding:** Swift exposes `registerModel(...)` (3 overloads), `downloadModel(...)`, `importModel(...)`. Kotlin is missing these public APIs.
- **Action:** Port all 3 `registerModel` overloads + `downloadModel` + `importModel` from Swift `RunAnywhere.swift` and corresponding `Public/Extensions/Storage/` files. Wire via `CppBridgeDownload` / `CppBridgeModelRegistry`.

#### KOTLIN-MISSING-VOICE-AGENT-PROCESS-TURN (HIGH)

- **Location:** `commonMain/.../public/extensions/VoiceAgent/RunAnywhereVoiceAgent.kt`.
- **Finding:** Swift has `processVoiceTurn(audioData: Data)` synchronous API. Kotlin deleted it in K2 (per K2-D in PR review). Audit confirms it should be RE-ADDED to match Swift surface.
- **Action:** Add `expect fun processVoiceTurn(audioData: ByteArray): VoiceAgentResult` + jvmAndroid actual. Route through `CppBridgeVoiceAgent` composite path.

#### KOTLIN-MISSING-PLUGIN-LOADER-LIST (MED)

- **Location:** `commonMain/.../public/extensions/RunAnywherePluginLoader.kt`.
- **Finding:** Swift exposes `pluginLoader.listLoaded(): [PluginInfo]`. Kotlin's `PluginLoader` class doesn't have this accessor.
- **Action:** Add `expect fun listLoaded(): List<PluginInfo>` + actual.

#### KOTLIN-DEAD-RUNANYWHERE-CONVENIENCE (MED)

- **Locations:** `commonMain/.../public/RunAnywhere.kt` + various extension files.
- **Finding:** 4 DELETE candidates:
  - `initializeForDevelopment(...)` — Swift removed; Kotlin has stale stub.
  - `cleanup()` — Swift removed; Kotlin has empty stub.
  - `loadModel(modelId: String)` — single-string overload (also flagged in B9.1 as KOTLIN-PUBLIC-API-LOADMODEL-OVERLOAD).
  - `ragCreatePipeline(RAGConfig)` — old non-proto signature; canonical is `ragCreatePipeline(RAGConfiguration)`.
- **Action:** Delete all 4 expects + jvmAndroid actuals.

#### KOTLIN-RENAME-IS-MODEL-PROPS (MED, requires example-app migration)

- **Location:** `commonMain/.../public/extensions/Models/ModelTypes.kt`.
- **Finding:** 3 `is*` accessor extension properties on `RAModelInfo` have non-canonical names vs Swift:
  - `isDownloadedModel` → should be `isDownloadedOnDisk`
  - `isBuiltInModel` → should be `isBuiltIn`
  - `isAvailableModel` → should be `isAvailableForUse`
- **Action:** Rename all 3 with example-app callers migrated (~13 LOC across 4 files per C8).

### C4 — CppBridge to-dos

#### KOTLIN-DEAD-CPPBRIDGE-DOC-FILES (HIGH)

- **Locations:** `CppBridgeNativeProtoABI.kt` (170 LOC), `CppBridgeModalityProtoABI.kt` (192 LOC).
- **Finding:** Both files are documentation-only with zero callers (matches B9.2 `KOTLIN-DEAD-CPPBRIDGE-DOC-ONLY-FILES` — promoting to HIGH for Wave C since deletion is now confirmed safe).
- **Action:** Delete both files (-362 LOC).

#### KOTLIN-BOOT-BOOLEAN-DUPLICATION (MED)

- **Location:** `CppBridge.kt` vs `CppBridgeState.kt` — both maintain boot/init boolean flags (`isInitialized`, `servicesInitialized`).
- **Finding:** Duplicated state machine across two files; single source-of-truth missing.
- **Action:** Retire boot booleans from one file (recommend keeping them in `CppBridgeState.kt`, removing from `CppBridge.kt`).

#### KOTLIN-MODELASSIGNMENT-TYPED-PARAMS (MED)

- **Location:** `CppBridgeModelAssignment.kt`.
- **Finding:** Fetch/apply methods take `Int` for `inferenceFramework` and `category` params. Should be the proto enum types `InferenceFramework` and `ModelCategory`.
- **Action:** Replace `Int` params with proto enums.

#### KOTLIN-MODELASSIGNMENT-FETCH-SYNC (MED)

- **Location:** `CppBridgeModelAssignment.kt` — `fetch(...)` method.
- **Finding:** Synchronous body though it does an HTTP/network call (via `OkHttpHttpTransport`). Swift parity equivalent is `async`.
- **Action:** Make `fetch(...)` a `suspend fun`.

#### KOTLIN-TELEMETRY-ENV-TYPE-LOSS (LOW)

- **Location:** `CppBridgeTelemetry.kt` — `@Volatile var currentEnvironment: Int`.
- **Finding:** Typed as `Int` rather than `SDKEnvironment?` (the proto enum). Loses type-safety.
- **Action:** Change type to `SDKEnvironment?`.

#### KOTLIN-AUTH-STATE-SPLIT (MED)

- **Location:** `CppBridgeAuth.kt` currently holds `accessToken`, `userId`, `organizationId` accessors.
- **Finding:** These are authentication STATE, not auth OPERATIONS. They belong in `CppBridgeState.kt` (state queries) rather than `CppBridgeAuth.kt` (login/logout/refresh).
- **Action:** Move 3 accessor properties from `CppBridgeAuth.kt` → `CppBridgeState.kt`.

#### KOTLIN-VOICEAGENT-SYNC-PRIMITIVE (LOW)

- **Location:** `CppBridgeVoiceAgent.kt`.
- **Finding:** Mixes `@Synchronized` on some methods with `Mutex.withLock` on others. Should be consistent (recommend `Mutex` everywhere for KMP idiom).
- **Action:** Clarify @Synchronized vs Mutex usage; standardize on Mutex.

#### KOTLIN-MODELPATHS-HARDCODED-FALLBACK (MED)

- **Location:** `CppBridgeModelPaths.kt`.
- **Finding:** 14-case hardcoded `when` table mapping framework names → paths. Codegen (proto enum + wireString extension) should replace this.
- **Action:** Delete the 14-case `when` table; route through `inferenceFrameworkOf(...)` / `wireString` codegen.

#### KOTLIN-MODELREGISTRY-FRAMEWORK-CONSTS (LOW)

- **Location:** `CppBridgeModelRegistry.kt` — `ModelRegistry.Framework` constant object.
- **Finding:** Duplicates the proto `InferenceFramework` enum values.
- **Action:** Delete the constants object; use proto enum directly.

### C5 — Backend modules

#### KOTLIN-ONNX-SHERPA-AUTO-REG (HIGH)

- **Location:** `modules/runanywhere-core-onnx/src/main/kotlin/.../ONNX.kt`.
- **Finding:** Swift has explicit `rac_plugin_entry_sherpa` + `rac_plugin_register` call. Kotlin ONNX module currently relies on ELF constructor (`__attribute__((constructor))`) auto-registration. Brittle — registration may not run before first `loadModel` call.
- **Action:** Add explicit `nativeRegisterSherpa()` JNI call inside `ONNX.kt` `register()` method.

#### KOTLIN-BACKEND-DEFAULT-PRIORITY (LOW)

- **Locations:** `runanywhere-core-llamacpp/src/main/kotlin/.../LlamaCPP.kt`, `runanywhere-core-onnx/src/main/kotlin/.../ONNX.kt`.
- **Finding:** Both modules have `defaultPriority` constant. Unused — priority is now exclusively set C++-side in plugin registration.
- **Action:** Delete `defaultPriority` constant from both modules.

#### KOTLIN-BACKEND-DUAL-REGISTER (LOW)

- **Locations:** Same 2 modules.
- **Finding:** Both have 2 `register(...)` overloads — one no-arg, one with priority. The priority overload is dead (priority set C++-side).
- **Action:** Delete the priority overload from both modules.

#### KOTLIN-BACKEND-UNUSED-JNI-EXTERNS (LOW)

- **Locations:** `LlamaCPPBridge.kt`, `ONNXBridge.kt`.
- **Finding:** Both have `external fun nativeIsRegistered(): Boolean` + `external fun nativeGetVersion(): String`. Zero callers.
- **Action:** Delete both extern funs from both bridges.

#### KOTLIN-BACKEND-NAMESPACE-LIE (LOW)

- **Location:** `runanywhere-core-llamacpp/build.gradle.kts` — `android.namespace`.
- **Finding:** Namespace value inconsistent with package path. Mismatch with sibling onnx module.
- **Action:** Align namespace to match the actual package directory.

#### KOTLIN-BACKEND-ABIFILTERS-DROP-ARMV7 (LOW)

- **Location:** Backend modules `build.gradle.kts` — `abiFilters`.
- **Finding:** Backend modules drop `armeabi-v7a`. Parent SDK includes it. Inconsistent.
- **Action:** Align backend `abiFilters` to parent SDK.

#### KOTLIN-BACKEND-RUNANYWHERE-MODULE-PROTOCOL (LOW, info)

- **Finding:** Both backend modules conform to `RunAnywhereModule` interface. Swift has no equivalent protocol — backends self-register without a protocol.
- **Action:** Decide whether to keep `RunAnywhereModule` (matches KMP idiom) or align with Swift (no protocol). Current state is more rigorous than Swift.

### C6 — Tests

#### KOTLIN-TESTS-BROKEN (HIGH)

- **Locations:** `commonTest/`.
- **Finding:** **3 tests fail to compile** against current API surface:
  1. `ToolCallingProtoAdaptersTest.kt` — `executor` signature mismatch
  2. `STTGeneratedStreamSurfaceTest.kt` — `transcribeStream` return type mismatch
  3. `VLMGeneratedStreamSurfaceTest.kt` — `processImageStream` params mismatch
- **Action:** Fix signatures to match current proto-canonical API. **Blocks `./gradlew jvmTest` clean run.**

#### KOTLIN-TEST-KEEP (info)

- **Kotlin-only tests (KEEP — Swift has no equivalent):**
  - VAD stream surface test
  - TTS stream surface test
  - VoiceAgent stream surface test
  - Fan-out adapter test (`HandleStreamAdapter`)

#### KOTLIN-TEST-GAPS (MED)

- **Finding:** Missing Kotlin parity for 3 Swift test files:
  - `StructuredOutputProtoHelpersTests.swift` — no Kotlin equivalent
  - `ModelImportProtoSurfaceTests.swift` — no Kotlin equivalent
  - `AudioCaptureManagerTests.swift` — no Kotlin equivalent (would need Android instrumented test)
- **Action:** Port the 3 test files to Kotlin (latter as Android instrumented test).

### C7 — Gradle / tooling

#### KOTLIN-GRADLE-DEAD-CATALOG (MED)

- **Location:** `gradle/libs.versions.toml`.
- **Finding:** ~14 unused catalog entries:
  - `mockito`, `slf4j`, `logback`, `commons-compress`
  - `room`, `sqldelight`, `datastore`, `hilt`
  - `android-core`, `kotlin-stdlib`
  - `ktor-client-serialization`, `ktor-client-okhttp`, `ktor-client-darwin`
  - `okhttp-logging-interceptor`
  - `intellij` plugin
  - `wire` plugin
- **Action:** Remove all 14 unused catalog entries.

#### KOTLIN-GRADLE-LEGACY-ALIASES (LOW)

- **Location:** `sdk.sh` + `build.gradle.kts`.
- **Finding:**
  - `testLocal` legacy alias (~70 LOC in `sdk.sh`) — superseded by `testJvm`.
  - `coreVersion` / `commonsVersion` properties — stale, no callers.
- **Action:** Delete `testLocal` alias from `sdk.sh`; remove `coreVersion` and `commonsVersion` properties.

#### KOTLIN-GRADLE-DETEKT-PATH (LOW)

- **Location:** Root `build.gradle.kts` (detekt config).
- **Finding:** Detekt paths reference non-existent `jvmMain` directories under SDK module. KMP layout uses `src/jvmMain/kotlin/` but detekt config points to bare `jvmMain/`.
- **Action:** Fix detekt source paths to use `src/jvmMain/kotlin/` (and similar for android/common).

#### KOTLIN-GRADLE-COMPILESDK-INCONSISTENCY (LOW)

- **Location:** Backend modules vs parent SDK `build.gradle.kts`.
- **Finding:** Submodule `compileSdk = 36` vs parent `compileSdk = 35`.
- **Action:** Align to one version (recommend 36 across the board).

#### KOTLIN-GRADLE-CATALOG-OMISSIONS (LOW)

- **Locations:** Build files reference `org.json:json` and `junit-vintage-engine` directly.
- **Finding:** Both should be in the version catalog.
- **Action:** Add both to `libs.versions.toml` and reference via `libs.*`.

#### KOTLIN-GRADLE-BUILD-EMOJI (LOW)

- **Location:** `build.gradle.kts` — `buildLocalJniLibs` task.
- **Finding:** Output prints contain emoji characters. Per repo guidelines, avoid emoji unless requested.
- **Action:** Strip emoji from task output strings.

#### KOTLIN-GRADLE-TOML-TYPOS (LOW)

- **Location:** `libs.versions.toml`.
- **Finding:** Typos in 2 catalog entries (verified by Wave C C7 audit).
- **Action:** Fix the typos.

#### KOTLIN-DOC-DEAD-SCRIPT-REFS (LOW)

- **Locations:** `CLAUDE.md`, module READMEs.
- **Finding:** References to non-existent build scripts (`build-kotlin.sh`, `build-sdk.sh` — both deleted in earlier waves).
- **Action:** Update `CLAUDE.md` + READMEs to reference current scripts (`scripts/build-core-android.sh`, `scripts/sdk.sh`).

### Wave C summary table

| Severity | Item count | LOC range | Risk if unaddressed |
|---|---:|---:|---|
| HIGH | 7 | ~600+ | 8 silent runtime crashes (time-bombs); 1 dead JNI declaration; missing Swift-parity public APIs; broken tests block CI |
| MED | 14 | ~400 | Code review confusion; type-safety regressions; auth/state organization mismatch; test parity gaps |
| LOW | 12 | ~150 | Cosmetic; tooling consistency |
| **TOTAL** | **33** | **~1,150 LOC** | — |

Plus 30 OBSOLETE-FALLBACK catch-blocks (KOTLIN-CATCH-THROWABLE-OBSOLETE) and 14 unused gradle catalog entries (KOTLIN-GRADLE-DEAD-CATALOG) for full sweep.

---

## Wave E2E (2026-05-12) — physical-device test pass on Pixel 8 Pro

Goal: drive every modality through the Android example app, identify every gap vs iOS Swift behavior, fix what we can without leaving the SDK contract, and record what remains.

### Modality verification matrix

| Modality | Verified on device | Outcome |
|---|---|---|
| Chat / LLM (Qwen 2.5 0.5B Q8_0) | YES | "2 + 2 equals 4" @ ~10 tok/s. Streaming + thinking-content parser working. |
| Vision / VLM (LFM2-VL 450M + mmproj) | PARTIAL | Loads, runs, returns text. Accuracy still imperfect — see KOTLIN-VLM-PREPROCESS-PARITY below. |
| STT (Sherpa Whisper Tiny ONNX) | YES | VAD-gated live mode now matches iOS: 0.02 amplitude threshold, 1.5 s silence trigger, 16 KB min buffer. Whisper hallucinations on silence are now suppressed by the gate. |
| TTS (Piper VITS en_GB / en_US) | YES | Float32 PCM @ 22050 Hz now converted to Int16 PCM and AudioTrack is configured with the proto's `sample_rate`. Audio is clean. |
| VAD (Silero) | YES | New `presentation/vad/VADScreen.kt` + `VADViewModel.kt` mirroring iOS Features/Voice/VoiceActivityDetectionView. Wired into More tab between TTS and STT. |
| RAG (MiniLM L6 v2 + Qwen 0.5B) | YES | Document ingested + queried; response generated end-to-end. |
| Tool calling (LFM2 350M / 1.2B-Tool) | YES (UI) | Tool indicator + detail sheet renders; pretty-printed args + result JSON; `<think>` content stripped. See `KOTLIN-LFM2-TOOL-FORMAT-PARITY` for a follow-up: format detection returns `default` for base LFM2 (correct in both platforms), but the user should be steered to `lfm2-1.2b-tool-q4_k_m` for the LFM2 native format. |
| Voice Agent (STT + LLM + TTS) | NOT TESTED | Pipeline initializes (`streamVoiceAgent()` started, `userSaid` flow active). End-to-end conversation not yet validated on physical device. |
| LoRA (Abliterated Qwen 0.5B F16) | BROKEN | Download is intentionally disabled in `LoraViewModel.downloadAdapter()` with `RunAnywhere.downloadModel() was removed in the V2 storage-plan refactor`. See KOTLIN-LORA-DOWNLOAD-DISABLED below. |
| Solutions (YAML pipeline) | NOT TESTED | Public surface present; demo not exercised on device. |
| Benchmarks (LLM/STT/TTS/VLM/Diffusion) | NOT TESTED | UI renders; `Run All Benchmarks` not exercised with a selected model. |

### Bugs fixed and committed during Wave E2E

All landed on `feat/v2-architecture` and pushed to origin. iOS Swift is the source of truth for every change.

| ID | Title | Files | Commit |
|---|---|---|---|
| Bug-1 | `ModelBootstrap.tryRegisterSingle` / `tryRegisterMultiFile` no-op stubs replaced with real `CppBridgeModelRegistry.save(info)` wiring | `examples/android/.../data/ModelBootstrap.kt` | `dbf1724b1` |
| Bug-2 | `ModelSelectionViewModel.startDownload` no-op stub replaced with `RunAnywhere.downloadModel(model).collect { progress }` | `examples/android/.../presentation/models/ModelSelectionViewModel.kt` | `dbf1724b1` |
| Bug-3 | Add `RunAnywhere.downloadModel(model: RAModelInfo): Flow<DownloadProgress>` mirroring Swift `RunAnywhere+Storage.swift:downloadModel(...)` — plan → start → poll → persist | `sdk/runanywhere-kotlin/src/{commonMain,jvmAndroidMain}/.../public/extensions/Storage/RunAnywhereDownload*.kt` | `dbf1724b1` |
| Bug-4 | OkHttp transport JNI class-lookup mismatch (`com/runanywhere/sdk/foundation/http/OkHttpTransport` → `com/runanywhere/sdk/httptransport/OkHttpHttpTransport`); also fix `Java_*_deliverChunkNative` export symbol | `sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp` | `dbf1724b1` |
| Bug-5 | LlamaCPP LLM + VLM plugin route registration on Android dynamic-plugin hosts — the carrier `librunanywhere_llamacpp.so` was never dlopened, so the static-register ctor never fired. Add explicit `rac_plugin_register(rac_plugin_entry_llamacpp{,_vlm}())` after module registration | `engines/llamacpp/rac_backend_llamacpp{,_vlm}_register.cpp` | `80feae082` |
| Bug-6 | Multi-file model download rejected — C++ download planner only walks `model.expected_files.files`, not the `multi_file` artifact oneof. `ModelBootstrap.tryRegisterMultiFile` now seeds `expected_files` from descriptors (mirrors Swift `RAModelInfo.setArtifact`) | `examples/android/.../data/ModelBootstrap.kt` | `80feae082` |
| Bug-7 | VLM `processStream` rejected `handle == 0` despite C lifecycle fallback. Removed Kotlin `requireHandle()` check in `CppBridgeVLM` | `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../bridge/extensions/CppBridgeVLM.kt` | `80feae082` |
| Bug-8 | `Java_*_racVlmProcess[Stream]Proto` JNI guards rejected `handle == 0` despite `rac_vlm_process[_stream]_proto` having lifecycle fallback (Phase 6j). Relaxed the JNI guard | `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` | `80feae082` |
| Bug-9 | STT/TTS sherpa `.tar.gz` archive models registered as `SingleFileArtifact` — no extraction metadata. New `ArchiveModel` data class in `ModelBootstrap` sets `ArchiveArtifact{type=TAR_GZ, structure=NESTED_DIRECTORY}` + `artifact_type=TAR_GZ_ARCHIVE`. Verified: encoder.onnx + tokens.txt + test_wavs/ now extract correctly | `examples/android/.../data/ModelBootstrap.kt` | `80feae082` |
| Bug-10 | Sherpa plugin missing from `rac_plugin_registry` on Android — ONNX JNI's `dlsym(RTLD_DEFAULT, "rac_backend_sherpa_register")` couldn't see symbols in `librac_backend_sherpa.so` (different Android linker namespace). Fix: explicit `dlopen("librac_backend_sherpa.so", RTLD_NOW \| RTLD_GLOBAL)` before dlsym. Plugin registry post-fix: `sherpa, onnx, llamacpp_vlm, llamacpp` (was missing `sherpa`). | `engines/onnx/jni/rac_backend_onnx_jni.cpp` | `ad03b541e` |
| Bug-11 | Kotlin SDK STT/TTS used `rac_stt_component_transcribe_proto` and `rac_tts_component_synthesize_proto` (which require a handle with a loaded model). iOS Swift uses `rac_stt_transcribe_lifecycle_proto` and `rac_tts_synthesize_lifecycle_proto` (lifecycle-only, no handle). Added new JNI thunks + switched `CppBridgeSTT` / `CppBridgeTTS` to the lifecycle path. Swift parity restored. | `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`, `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../bridge/extensions/CppBridge{STT,TTS}.kt`, `.../native/bridge/RunAnywhereBridge.kt` | `ad03b541e` |
| Bug-11-cleanup | Deleted the now-dead component-handle JNI exports `Java_*_racSttComponentTranscribe[Stream]Proto` and `Java_*_racTtsComponent{ListVoices,Synthesize,SynthesizeStream}Proto` + the corresponding Kotlin `external fun` declarations. C++ `rac_*_component_*_proto` functions remain (still consumed by tests + WASM exports + iOS C ABI headers). | `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`, `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt` | `ad03b541e` |
| Bug-12 | VLM camera frame not rotated. Android's `LifecycleCameraController` + `OUTPUT_IMAGE_FORMAT_RGBA_8888` returns the sensor's landscape buffer; `rotationDegrees` was reported via `ImageInfo` but never baked into pixels. LFM2-VL was being asked to describe a sideways frame. Fix: `Matrix.postRotate(imageInfo.rotationDegrees)` in `VLMViewModel.captureFrame()` before extracting RGB. iOS gets pre-rotated frames from AVCaptureSession for free. | `examples/android/.../presentation/vision/VLMViewModel.kt` | `4fb4caafa` |
| Bug-13 | TTS noise on Piper. `TextToSpeechViewModel` was feeding raw Float32 PCM (4 bytes/sample @ 22050 Hz) into AudioTrack configured with `ENCODING_PCM_16BIT` → 4-byte float reinterpreted as two consecutive Int16 samples → double-speed garbled noise. Also never read `TTSOutput.sample_rate` from the proto. Fix: read proto sample_rate (three-tier fallback proto → options → 22050), convert Float32 → Int16 via clamped scaling (port of `rac_audio_float32_to_wav`'s `clamp(s × 32767, -32768, 32767)`), feed AudioTrack at the proto-reported rate. | `examples/android/.../presentation/tts/TextToSpeechViewModel.kt` | `4fb4caafa` |
| Bug-14 | STT too sensitive — no VAD gating on live mode. Whisper hallucinated `[BLANK_AUDIO]` / `[SIDE CONVERSATION]` tokens on ambient noise. Fix: ported iOS `SpeechToTextViewModel`'s VAD gate exactly — 50 ms polling, 0.02 amplitude threshold, 1.5 s silence trigger, 16 KB min buffer, transcribe-then-clear. STT options now match `RASTTOptions.defaults()` (EN + punctuation + word timestamps). | `examples/android/.../presentation/stt/SpeechToTextViewModel.kt` | `4fb4caafa` |
| Bug-15 | Tool calling: `ToolCallingOrchestrator.jvmAndroid.kt` referenced `kotlinx.coroutines.runBlocking` without an import → stale AAR, JNI tool-call callback silently no-op'd. Also `MessageBubbleView`'s `if (content.isNotEmpty())` guard hid the assistant bubble when the model only emitted a tool call. Fix: added import, populate `toolCallInfo` before content in `ChatViewModel`, fall back to `error_message` → synthesized "Ran <tool>" summary, run `ThinkingContentParser.extract()` on the tool-calling path, pretty-print args + result JSON. | `sdk/runanywhere-kotlin/src/jvmAndroidMain/.../public/extensions/LLM/ToolCallingOrchestrator.jvmAndroid.kt`, `examples/android/.../presentation/chat/ChatViewModel.kt` | `4fb4caafa` |
| Bug-16 | `scripts/build-core-android.sh` invoked `cmake --preset android-arm64` without `cd`-ing to repo root. Gradle's `buildLocalJniLibs` task runs with `workingDir = sdk/runanywhere-kotlin/`, breaking CMake preset resolution. Fix: `cd "${REPO_ROOT}"` at top of script. | `scripts/build-core-android.sh` | `4fb4caafa` |
| VAD-screen | No standalone VAD demo in Android example app. Added `presentation/vad/VADViewModel.kt` (30 ms polling, 1024-byte / 512 Int16 / 32 ms @ 16 kHz frames, calls `RunAnywhere.detectVoiceActivity`, 50-entry activity log) + `VADScreen.kt` (Compose UX mirroring iOS `VoiceActivityDetectionView.swift`). Wired into More tab between TTS and STT, new `NavigationRoute.VAD`. | `examples/android/.../presentation/vad/{VADViewModel,VADScreen}.kt`, `.../models/ModelSelectionContext.kt`, `.../navigation/{AppNavigation,MoreHubScreen}.kt`, `.../chat/components/ModelRequiredOverlay.kt` | `4fb4caafa` |

### Open items from Wave E2E

#### KOTLIN-VLM-PREPROCESS-PARITY (MED — VLM)

VLM rotation fix (Bug-12) landed, but on-device output is still less accurate than iOS for the same model + scene. User report: pointed phone at a laptop, model still mentioned "people". Need a second pass comparing the Android image-preprocessing path to iOS byte-for-byte:

1. **Color channel order** — RGBA → RGB extraction in `VLMImage.fromBitmap()` uses `Bitmap.getPixels()` and packs RGB. Verify the byte order matches what `rac_vlm_llamacpp_process_proto` / mtmd's CLIP preprocessor expects. iOS uses BGRA → RGB via Accelerate; subtle ARGB↔RGBA bit-shift mismatches are a common pitfall.
2. **Stride / padding** — `Bitmap.getPixels()` returns tightly packed ints regardless of native stride, but `ImageProxy.toBitmap()` may produce a bitmap whose underlying buffer has row-stride padding. Validate that the bytes leaving Kotlin are width × height × 3 with no padding.
3. **Resize policy** — iOS may downsample large camera frames before sending; mtmd CLIP-encoder has a 384×384 (or 448×448) native input. If Android sends a 1920×1440 frame and mtmd has to resize internally, the down-scaling kernel may differ from iOS's CoreImage path.
4. **JPEG vs raw RGB path** — gallery-image flow uses `VLM_IMAGE_FORMAT_FILE_PATH` (mtmd decodes the JPEG container with EXIF rotation built in); camera flow uses raw RGB. Make sure both paths land at the same preprocessed tensor.
5. **Auto-stream cadence** — auto-stream every 2.5 s (Android) vs iOS auto-stream interval — confirm both match.

Acceptance: pick a fixed scene (laptop, mug, room), photograph it, run the SAME model on iOS and Android, and compare token outputs. They should be substantively similar.

#### KOTLIN-LORA-DOWNLOAD-DISABLED (HIGH — LoRA)

`LoraViewModel.downloadAdapter()` emits an error every time the Download button is tapped:

```
LoraViewModel$downloadAdapter: LoRA download is temporarily disabled:
  RunAnywhere.downloadModel() was removed in the V2 storage-plan refactor (entry=abliterated-lora).
```

LoRA catalog entries register correctly (`lora-adapter:abliterated-lora` saved to C++ registry, listed in the manager UI), but the download path was deleted during the V2 storage-plan refactor and never re-wired. To unblock:

1. Decide whether LoRA artifacts flow through (a) the new `downloadModel(RAModelInfo)` path with `RAModelInfo` synthesized from the `LoraAdapterCatalogEntry`, or (b) a dedicated `RunAnywhere.lora.download(entry)` SDK call. iOS Swift `RunAnywhere.lora.*` namespace is the reference — port whatever it does.
2. Once download lands, verify `RunAnywhere.lora.apply(LoRAApplyRequest)` actually attaches the adapter to the loaded LLM and changes behavior (e.g. abliterated Qwen answers a prompt the base would refuse).
3. UI: surface apply / remove / scale-slider controls already present in `LoraScreen.kt` — they're inert until download works.

Files: `examples/android/.../presentation/lora/LoraViewModel.kt`, `sdk/runanywhere-kotlin/src/.../public/extensions/LLM/RunAnywhereLoRA.kt`.

#### KOTLIN-VOICE-AGENT-E2E-UNTESTED (MED — Voice Agent)

`VoiceAssistantViewModel.startSession()` invokes `RunAnywhere.streamVoiceAgent()` and the camera/audio pipeline initializes (`Voice session started — events flow from streamVoiceAgent()` in logs). Full STT → LLM → TTS round-trip with real speech has NOT been validated on device.

Acceptance: load `sherpa-onnx-whisper-tiny.en` + `qwen2.5-0.5b-instruct-q8_0` + `vits-piper-en_US-lessac-medium`, tap Start, speak a question, verify (a) `userSaid` event with correct transcript, (b) `assistantToken` stream, (c) `audio` events playing through AudioTrack, (d) state transitions match iOS pipeline state machine (`IDLE → LISTENING → PROCESSING_SPEECH → GENERATING_RESPONSE → PLAYING_TTS → COOLDOWN → IDLE`).

Known concern from earlier audit: `VoiceAssistantViewModel` uses an audio-level threshold of `0.1f` and 1500 ms silence; `STTViewModel` (Bug-14) uses `0.02f` / 1500 ms. The mismatch may produce different sensitivity in the two flows — verify against iOS `VoiceAgentViewModel.swift`.

Files: `examples/android/.../presentation/voice/VoiceAssistantViewModel.kt`, `sdk/runanywhere-kotlin/src/.../public/extensions/VoiceAgent/RunAnywhereVoiceAgent.kt`.

#### KOTLIN-SOLUTIONS-E2E-UNTESTED (LOW — Solutions)

`RunAnywhere.solutions.run(yaml:)` API present; `presentation/solutions/SolutionsScreen.kt` renders the two iOS demo YAMLs (voice agent + RAG). Not exercised on device. Acceptance: submit each YAML, watch lifecycle events fire in order. Test with `assembleDebug` build + emulator/device.

#### KOTLIN-BENCHMARKS-E2E-UNTESTED (LOW — Benchmarks)

`BenchmarkScreen.kt` + `BenchmarkRunner` present. Tapping "Run All Benchmarks" without a model selected currently no-ops. Acceptance: select Qwen 2.5 0.5B for LLM, run benchmarks, verify TTFT + tok/s + decode-time appear in `BenchmarkStore` history and export-as-CSV/JSON works.

#### KOTLIN-LFM2-TOOL-FORMAT-PARITY (LOW — Tool calling)

`generateWithTools(...)` format detection returns `default` for any model whose name doesn't contain `"tool"`. For LFM2 base models (350M / 1.2B without "-Tool"), this is correct (matches iOS behavior). But the user expected the LFM2 *native* format. Two follow-ups:

1. Make the model picker either (a) auto-pick `lfm2-1.2b-tool-q4_k_m` when the user enables Tools, or (b) show an in-UI warning that the base model may not produce reliable structured tool-call output.
2. Verify against iOS `LLMViewModel+ToolCalling.swift` that the LFM2 family detection regex matches exactly (`lfm2-tool` vs `lfm2-1.2b-tool` vs `lfm2.*tool`).

#### KOTLIN-VLM-CANCEL-LIFECYCLE-JNI (LOW — already tracked, recurring)

The pre-existing `racVlmCancelLifecycleProto` JNI symbol is still missing in commons. Two stack traces in the Wave E2E logs:

```
No implementation found for byte[] com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racVlmCancelLifecycleProto()
```

Tracked in `KOTLIN-VLM-CANCEL-LIFECYCLE-JNI` (LOW, pending commons JNI). Does not block VLM inference because `VLMViewModel.cancel()` swallows the `UnsatisfiedLinkError`; surfaces only on auto-stream coroutine cancellation.

### Wave E2E summary

| Category | Count |
|---|---:|
| Bugs fixed and committed (Bug-1 .. Bug-16 + VAD-screen) | 17 |
| Open items from Wave E2E (KOTLIN-VLM-PREPROCESS-PARITY, KOTLIN-LORA-DOWNLOAD-DISABLED, KOTLIN-VOICE-AGENT-E2E-UNTESTED, KOTLIN-SOLUTIONS-E2E-UNTESTED, KOTLIN-BENCHMARKS-E2E-UNTESTED, KOTLIN-LFM2-TOOL-FORMAT-PARITY) | 6 |
| Severity breakdown of open items | 1 HIGH (LoRA), 2 MED, 3 LOW |

All Wave E2E commits pushed to `origin/feat/v2-architecture` at `4fb4caafa`. Working tree clean.

---

## Deferred / not bugs

- **Genie** (Qualcomm NPU): closed-source AAR. Excised from example app in `d22d6230c`. Re-introduce once a 16KB-compatible AAR aligned with the proto-based Kotlin SDK surface is published.
- **MetalRT / WhisperKit / WhisperKit CoreML**: Apple-only; no Kotlin module expected.
- **WhisperCPP**: no dedicated Kotlin module. The `whisper.jni` dep is scoped to audio utilities.
- **Diffusion** (diffusion-coreml): Apple-only at runtime; Kotlin Diffusion surface (file + bridge) deleted in Wave 1. Re-introduce later if/when commons exports the relevant C ABI.

---

## Summary

**Pre-B9 open items: 7 (carry-over) + Wave B9 audit: 26 DELETE candidates + 5 JNI time-bombs + Wave C audit: 33 items + 8 JNI time-bombs = 66 actionable items today.**

Pre-B9 carry-over (architectural / deferred / cosmetic):

- **HIGH (deferred):** 1 — `KOTLIN-ANDROID-EXAMPLE-APP-MIGRATION` (separate pass, by directive)
- **LOW (pending commons JNI):** 3 — `KOTLIN-VOICE-AGENT-CREATE-4HANDLE`, `KOTLIN-VLM-CANCEL-LIFECYCLE-JNI`, `KOTLIN-DEVICE-PERSISTENT-ID-JNI`
- **LOW (pre-existing):** 1 — `KOTLIN-EVENTBUS-UNCHECKED-CAST`
- **LOW (tooling):** 1 — `KOTLIN-DETEKT-KTLINT`
- **INFO:** 1 — `KOTLIN-LLM-STREAMING-SINGLE-CALL` (matches Swift behavior; B9.3 actually promotes this to HIGH-DELETE — see `KOTLIN-DEAD-LLMSTREAMADAPTER`)
- **Deferred (testing):** 1 — `KOTLIN-PHYSICAL-DEVICE-E2E`

Wave B9 new findings (2026-05-11):

- **HIGH (entire-file DELETE candidates):** 8 — `KOTLIN-DEAD-CPPBRIDGE-SDKINIT`, `-STRATEGY`, `-SERVICES`, `-PLATFORM`, `-ENDPOINTS`, `KOTLIN-DEAD-RASDKERRORHELPERS`, `KOTLIN-DEAD-LLMSTREAMADAPTER`, `KOTLIN-DEAD-RASDKCOMPONENTDISPLAYNAME`.
- **HIGH (other DELETE candidates):** 6 — `KOTLIN-PUBLIC-API-LOADMODEL-OVERLOAD`, `KOTLIN-PUBLIC-API-CONFIGURE-TELEMETRY-BASEURL`, `KOTLIN-DEAD-BUILDTOKEN`, `KOTLIN-DEAD-DOWNLOADPROGRESS-SUGAR`, `KOTLIN-DEAD-KEYCHAIN-MIGRATION`, `KOTLIN-DEAD-NATIVEFILEMANAGER-DUPLICATES`, `KOTLIN-DEAD-NATIVEEXTRACTARCHIVE`.
- **HIGH (runtime time-bomb):** 1 — `KOTLIN-JNI-TIMEBOMBS` (5 thunks: `racResultToProtoError`, `racSdkInitPhase1Proto`, `racSdkInitPhase2Proto`, `racSdkRetryHttpProto`, `racVlmCancelLifecycleProto`).
- **MED:** 8 — `KOTLIN-PUBLIC-API-IS-MODEL-DUPLICATES`, `KOTLIN-PUBLIC-API-INFERENCE-FRAMEWORK-SWITCH`, `KOTLIN-PUBLIC-API-DUPLICATE-PROTO-TYPEALIASES`, `KOTLIN-VOICEAGENT-DUAL-PATH`, `KOTLIN-DEAD-SDKEXCEPTION-FACTORIES`, `KOTLIN-DEAD-SDKLOGGER-EXTRAS`, `KOTLIN-DEAD-SENTRYMANAGER-METHODS`, `KOTLIN-JNI-CATCH-FALLBACKS`.
- **LOW:** 5 — `KOTLIN-PUBLIC-API-STALE-TODOS`, `KOTLIN-DEAD-CPPBRIDGE-DOC-ONLY-FILES`, `KOTLIN-DEAD-COMMONS-ERROR-HELPERS`, `KOTLIN-REFACTOR-HOIST-PLATFORM`, `KOTLIN-CPPBRIDGE-MODELPATHS-DUPLICATE`.

**Aggregate B9 dead-code impact:** ~950 LOC across 26 DELETE candidates + 5 silent JNI time-bombs (HIGH-severity runtime risk).

Wave C new findings (2026-05-11):

- **HIGH (8 JNI time-bombs):** `KOTLIN-JNI-TIMEBOMBS-WAVE-C` — `racHttpDefaultHeaders`, `racHttpRequestExecuteWithUpsert`, `racApiErrorFromResponse`, `racVad{Configure,Start,Stop,Reset}LifecycleProto`, `racVlmCancelLifecycleProto` (last one tracked separately too).
- **HIGH:** `KOTLIN-DEAD-RAC-RESULT-TO-PROTO-ERROR`, `KOTLIN-MISSING-STORAGE-API` (3 registerModel + downloadModel + importModel), `KOTLIN-MISSING-VOICE-AGENT-PROCESS-TURN`, `KOTLIN-DEAD-CPPBRIDGE-DOC-FILES` (362 LOC), `KOTLIN-TESTS-BROKEN` (3 tests).
- **MED:** `KOTLIN-CATCH-THROWABLE-OBSOLETE` (30 blocks), `KOTLIN-MISSING-PLUGIN-LOADER-LIST`, `KOTLIN-DEAD-RUNANYWHERE-CONVENIENCE` (4 deletes), `KOTLIN-RENAME-IS-MODEL-PROPS` (3 renames), `KOTLIN-BOOT-BOOLEAN-DUPLICATION`, `KOTLIN-MODELASSIGNMENT-TYPED-PARAMS`, `KOTLIN-MODELASSIGNMENT-FETCH-SYNC`, `KOTLIN-AUTH-STATE-SPLIT`, `KOTLIN-MODELPATHS-HARDCODED-FALLBACK`, `KOTLIN-TEST-GAPS` (3 missing tests), `KOTLIN-GRADLE-DEAD-CATALOG` (~14 entries).
- **LOW:** `KOTLIN-TELEMETRY-ENV-TYPE-LOSS`, `KOTLIN-VOICEAGENT-SYNC-PRIMITIVE`, `KOTLIN-MODELREGISTRY-FRAMEWORK-CONSTS`, `KOTLIN-ONNX-SHERPA-AUTO-REG` (HIGH actually), `KOTLIN-BACKEND-DEFAULT-PRIORITY`, `KOTLIN-BACKEND-DUAL-REGISTER`, `KOTLIN-BACKEND-UNUSED-JNI-EXTERNS`, `KOTLIN-BACKEND-NAMESPACE-LIE`, `KOTLIN-BACKEND-ABIFILTERS-DROP-ARMV7`, `KOTLIN-GRADLE-LEGACY-ALIASES`, `KOTLIN-GRADLE-DETEKT-PATH`, `KOTLIN-GRADLE-COMPILESDK-INCONSISTENCY`, `KOTLIN-GRADLE-CATALOG-OMISSIONS`, `KOTLIN-GRADLE-BUILD-EMOJI`, `KOTLIN-GRADLE-TOML-TYPOS`, `KOTLIN-DOC-DEAD-SCRIPT-REFS`.

**Aggregate Wave C impact:** ~1,150 LOC delete-candidate, 8 new HIGH JNI time-bombs, 5 HIGH missing public APIs, 3 BROKEN tests, 18 gradle/tooling cleanups, 30 obsolete catch-blocks.

**Wave C example-app verdict (C8):** Migration is small (~13 LOC across 4 files) and semantically improving (covers FoundationModels/SystemTTS via `isBuiltIn` check). **Recommendation: MIGRATE NOW**, then delete 3 duplicate ModelTypes accessors (KOTLIN-RENAME-IS-MODEL-PROPS).

**Folder + naming verdict (B9.5):** **FULLY ALIGNED** — zero `+` files, zero lowercase `Ra*`, zero singular `*Helper.kt`, SwiftAliases.kt has 42 RA-prefixed typealiases (B9.5 ground-truth count).

**Architectural drift status:** All architectural drift identified by prior audits (8-agent 2026-05-11 + V1+V2 cleanup) is resolved. Wave B9 findings are pure dead-code/JNI hygiene — no new architectural gaps. All builds PASS.

All previously-tracked architectural and folder-layout gaps (`KOTLIN-NO-COMPONENTACTOR`, `KOTLIN-NO-HANDLESTREAMADAPTER-COMMON`, `KOTLIN-NO-LLMSTREAMADAPTER`, `KOTLIN-VOICEAGENT-ADAPTER-WRONG-SOURCESET`, `KOTLIN-MODALITY-BRIDGE-NO-ACTOR`, `KOTLIN-FOLDER-MISMATCH-INFRASTRUCTURE-*`, `KOTLIN-FOLDER-MISMATCH-HTTPTRANSPORT`, `KOTLIN-TYPE-NAMING-RA-PREFIX`, `KOTLIN-TYPE-NAMING-RASTTOUTPUT-VS-RATRANSCRIPTIONRESULT`, `KOTLIN-TYPE-NAMING-VOICEAGENT-EVENTS`, `KOTLIN-DUP-FILENAME-RUNANYWHERETOOLCALLING`, `KOTLIN-MISSING-APIS`, `KOTLIN-EXTRA-APIS`, `KOTLIN-BUILD-K2-MERGE`, `KOTLIN-RUNANYWHERE-DOCSTRING-DRIFT`) are CLOSED as of Wave 6. See `gaps/gaps/PR review/kotlin.md` for the closure trail.
