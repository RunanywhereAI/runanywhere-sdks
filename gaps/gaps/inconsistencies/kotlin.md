# Kotlin / Android+JVM SDK — Open Inconsistencies

Updated: 2026-05-11 (post-Wave 1..6 + Audit Waves V1+V2)
Branch: `feat/v2-architecture`
Latest commit: `40c668d86` (Wave K1 file rename, drop `+` suffix)
Working tree state: Waves 1..6 + V1+V2 applied uncommitted; build green.

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

## Deferred / not bugs

- **Genie** (Qualcomm NPU): closed-source AAR. Excised from example app in `d22d6230c`. Re-introduce once a 16KB-compatible AAR aligned with the proto-based Kotlin SDK surface is published.
- **MetalRT / WhisperKit / WhisperKit CoreML**: Apple-only; no Kotlin module expected.
- **WhisperCPP**: no dedicated Kotlin module. The `whisper.jni` dep is scoped to audio utilities.
- **Diffusion** (diffusion-coreml): Apple-only at runtime; Kotlin Diffusion surface (file + bridge) deleted in Wave 1. Re-introduce later if/when commons exports the relevant C ABI.

---

## Summary

**Open items: 7 total — all LOW severity or deferred.**

- **HIGH (deferred):** 1 — `KOTLIN-ANDROID-EXAMPLE-APP-MIGRATION` (separate pass, by directive)
- **LOW (pending commons JNI):** 3 — `KOTLIN-VOICE-AGENT-CREATE-4HANDLE`, `KOTLIN-VLM-CANCEL-LIFECYCLE-JNI`, `KOTLIN-DEVICE-PERSISTENT-ID-JNI`
- **LOW (pre-existing):** 1 — `KOTLIN-EVENTBUS-UNCHECKED-CAST`
- **LOW (tooling):** 1 — `KOTLIN-DETEKT-KTLINT`
- **INFO:** 1 — `KOTLIN-LLM-STREAMING-SINGLE-CALL` (matches Swift behavior)
- **Deferred (testing):** 1 — `KOTLIN-PHYSICAL-DEVICE-E2E`

**All architectural drift is resolved as of the 2026-05-11 audit.** The 8-agent audit verified ~97% alignment with Swift `ARCHITECTURE.md`; the 4 drift items identified by MOSTLY-ALIGNED audits were resolved by V1+V2 cleanup waves (SDKConstants canonicalized; `RASDKError.from(rcResult:)` + `racResultToProtoError` JNI thunk added; `SDKException.validationFailed` factory added; DeviceInfo port verified NOT NEEDED; 7 `racDiffusion_*` orphan JNI thunks deleted + 32 remaining orphans annotated). All builds PASS post-V2.

All previously-tracked architectural and folder-layout gaps (`KOTLIN-NO-COMPONENTACTOR`, `KOTLIN-NO-HANDLESTREAMADAPTER-COMMON`, `KOTLIN-NO-LLMSTREAMADAPTER`, `KOTLIN-VOICEAGENT-ADAPTER-WRONG-SOURCESET`, `KOTLIN-MODALITY-BRIDGE-NO-ACTOR`, `KOTLIN-FOLDER-MISMATCH-INFRASTRUCTURE-*`, `KOTLIN-FOLDER-MISMATCH-HTTPTRANSPORT`, `KOTLIN-TYPE-NAMING-RA-PREFIX`, `KOTLIN-TYPE-NAMING-RASTTOUTPUT-VS-RATRANSCRIPTIONRESULT`, `KOTLIN-TYPE-NAMING-VOICEAGENT-EVENTS`, `KOTLIN-DUP-FILENAME-RUNANYWHERETOOLCALLING`, `KOTLIN-MISSING-APIS`, `KOTLIN-EXTRA-APIS`, `KOTLIN-BUILD-K2-MERGE`, `KOTLIN-RUNANYWHERE-DOCSTRING-DRIFT`) are CLOSED as of Wave 6. See `gaps/gaps/PR review/kotlin.md` for the closure trail.
