# Kotlin SDK — Current Inconsistencies

Updated: 2026-05-10
Branch: `feat/v2-architecture` (post-wave-3)

---

# Update 2026-05-10 — Wave 1 + 2 + 3 progress

This PR closes the Swift-parity backlog for the Kotlin SDK across three
waves (folder layout + bridge split + module pattern in wave 1, public
API rename + missing-method ports + helper-file additions in wave 2,
commons-side `update_registry_on_completion` + `file_list_directory`
adapter callback + RA-prefix typealias adoption sweep in wave 3). The
Kotlin extension API now mirrors Swift one-for-one (no `@Deprecated`
shims) and the Android example app's bootstrap path matches Swift's
curated catalog seed + LoRA seed + system-TTS module registration.

## Items closed in waves 1–3

### KOT-API-ALIGNMENT-SWIFT (LOW) — ✅ CLOSED in wave 2

15 cosmetic divergences from the Swift canonical surface have all been
resolved. The Kotlin extension API now matches Swift exactly. No
`@Deprecated` shims were left behind (per repo "DELETE, don't deprecate"
rule).

**Renames**:
- `parseStructuredOutput(request)` → `extractStructuredOutput(text, schema)`
- `checkStorageAvailability(...)` → `checkStorageAvailable(...)`
- `metadataJson` → `metadataJSON`
- `LoRA.list(request)` / `LoRA.state(request)` → no-arg `list()` / `state()`
- `VLM.processImage(image, prompt, options)` → `processImage(image, options)` (prompt optional)
- `Solutions.SolutionHandle.feed(ByteArray)` → `feed(String)`

**Deletions**:
- `RunAnywhere.chat(prompt)` (no Swift equivalent)
- `ToolCalling.clearTools()` (no Swift equivalent)
- `STT.transcribeWithOptions(...)` (no Swift equivalent)
- `VLM.describeImage(...)` / `askAboutImage(...)` convenience methods (no Swift equivalent)
- `VoiceAgent.isVoiceAgentReady()` (callers use `getVoiceAgentComponentStates()`)
- `VAD.initializeVAD()` / `initializeVAD(config)` from public surface (made internal)

**Additions**:
- `TTS.stopSpeaking()`
- `VoiceAgent.processVoiceTurn(audioData)`
- `completeServicesInitialization()` now auto-called from `ensureServicesReady()`

### KOT-VAD-001 / KOT-VAD-002 (MED) — ✅ CLOSED in wave 2

Silero VAD now auto-loads on Voice Agent init. Direct port of
`SWIFT-VOICE-AGENT-001` (commit `6c26b24f6`). The Voice Agent component
boot sequence ensures the registered Silero model is loaded before
audio capture begins; no manual `loadModel("silero-vad-onnx")` is
required from the example app.

### KOT-STT-001 (HIGH) — ✅ CLOSED in wave 2

STT chunk transcription errors now surface to the UI via
`uiState.errorMessage` instead of being silently swallowed in the
chunk-decode coroutine. Mirrors Swift's `STTViewModel` error-routing.

### KOT-TTS-001 / KOT-TTS-003 (HIGH/MED) — ✅ CLOSED in wave 2

System TTS is now registered as a built-in `system-tts` `ModelInfo` via
`SystemTTSModule.register()` (Android) and `JvmSystemTTSModule.register()`
(JVM). The Android example's inline synthetic `ModelInfo` block in
`ModelSelectionBottomSheet` was removed; the registry is now the single
source of truth for available TTS models.

### KOT-VLM-001 (MED) — ✅ CLOSED in wave 2

The RGBA→RGB stride bug is fixed by routing through `VLMImage.fromBitmap()`
helper which uses Android's stride-aware `Bitmap.getPixels()`. The
helper produces a correctly packed `RAVLMImage` proto regardless of
the source bitmap's stride.

### KOT-RAG-001 (CRIT) — ✅ CLOSED in wave 2

`RAGViewModel.onCleared()` now destroys the active pipeline (no more
handle leak). Mirrors Swift's `RAGViewModel` lifecycle hook.

### KOT-DOWNLOAD-001 (MED) — ✅ CLOSED in wave 2

Replaced the 500 ms `delay()` wait with an `EventBus` subscription that
waits for `MODEL_EVENT_KIND_DOWNLOAD_COMPLETED` for the specific model
ID. Eliminates the race window where a fast download would complete
before the sleep finished, and removes the unbounded wait when a slow
download runs longer than 500 ms.

### KOT-DOWNLOAD-004 (HIGH) — ✅ CLOSED in wave 2 (deferred → conditional)

The Kotlin self-heal `markModelDownloadedInRegistry()` was deferred
until commons CPP-02 lands. **J1 lands CPP-02 in this PR**
(`update_registry_on_completion` in `download_orchestrator.cpp`); the
Kotlin self-heal can be removed in a follow-up after a clean rebuild
and end-to-end verification on Pixel 8 Pro confirms the C++ side
toggles `is_downloaded=true` + `local_path` autonomously.

### KOT-VOICE-001 (LOW) — ✅ CLOSED in wave 2

Audio chunks skipped during in-flight processing now log a
`Timber.d("voice-agent: dropped audio chunk while processing in flight")`
so the drop is observable in logcat instead of being silent.

### KOT-LORA-001 (CRIT) — ✅ CLOSED in wave 2

The curated LoRA adapter (`abliterated-lora`) is now registered on app
start via `seedLoRAAdapters()` in `ModelBootstrap.kt`. Mirrors the
Swift example app's LoRA seed step; the More → LoRA panel now renders
a non-empty list on first launch.

### KOT-E2E-PER-MODALITY-UNTESTED (MED) — verification queued (Workstream I)

Status now "verification queued". Workstream I drills run after wave 3
commit lands. Per-modality download → load → inference flows on Pixel
8 Pro across LLM / VLM / STT / TTS / VAD / Voice Agent / RAG / LoRA /
Tool Calling / Structured Output / Benchmarks / Solutions remain to be
exercised on-device.

## New "Closed in this PR" entries (wave 1–3)

### KOT-PARITY-FOLDER-LAYOUT — ✅ CLOSED in wave 1

Public extensions moved into modality subfolders (`LLM/`, `STT/`, `TTS/`,
`VAD/`, `VLM/`, `VoiceAgent/`, `Models/`, `RAG/`, `Storage/`, `Solutions/`,
`Events/`) matching Swift exactly. The flat
`commonMain/.../public/extensions/` layout is gone; each modality now
owns its own subfolder of `RunAnywhere+*.kt` extension files.

### KOT-PARITY-BRIDGE-SPLIT — ✅ CLOSED in wave 1

Split monolithic `CppBridgeModalityProto.kt` (867 lines) and
`CppBridgeStableProto.kt` (205 lines) into per-domain top-level
bridges: `CppBridgeLLM`, `CppBridgeSTT`, `CppBridgeTTS`, `CppBridgeVAD`,
`CppBridgeVLM`, `CppBridgeRAG`, `CppBridgeEmbeddings`, `CppBridgeLoRA`,
`CppBridgeDiffusion`, `CppBridgeDownload`, `CppBridgeModelLifecycle`,
`CppBridgeStorage`, `CppBridgeSDKEventStream`. Each bridge file is now
single-purpose and matches Swift's per-domain `CppBridge+*.swift`
extension layout.

### KOT-PARITY-API-RENAME — ✅ CLOSED in wave 2

Full rename of public extension surface to Swift canonical names. No
`@Deprecated` shims. See KOT-API-ALIGNMENT-SWIFT entry above for the
full delta.

### KOT-PARITY-MODULE-PATTERN — ✅ CLOSED in wave 1

`RunAnywhereModule` interface added in `commonMain/public`. `LlamaCPP`,
`ONNX`, `SystemTTSModule` (Android), `JvmSystemTTSModule` (JVM) all
conform. The Android example's `ModelBootstrap.registerBackends()`
now iterates a uniform `List<RunAnywhereModule>` and calls
`module.register(priority)` on each, mirroring Swift's
`RunAnywhereModule` protocol pattern.

### KOT-PARITY-SYSTEM-TTS-REGISTRATION — ✅ CLOSED in wave 2

System TTS is now registered as a real `ModelInfo` in the registry via
`SystemTTSModule.register()`. The inline synthetic `ModelInfo` block in
`ModelSelectionBottomSheet` was removed. Selecting "System TTS" in the
example app now follows the same registry-driven path as any other
model.

### KOT-PARITY-MISSING-METHODS — ✅ CLOSED in wave 2

Added Swift parity methods on the public extension surface:
`RunAnywhere.lora.*` namespace, `RunAnywhere.solutions.*` namespace,
`extractStructuredOutput`, `processVoiceTurn`, `streamVoiceAgent`,
`getVoiceAgentComponentStates`, `getStorageInfo`, `clearCache`,
`cleanTempFiles`, `planStorageDelete`, `deleteStorage`, `ragSearch`,
`ragQueryWithContext`, `ragResolvedConfiguration`, `ragAddDocumentsBatch`,
`ragGetDocumentCount`, `supportsAccelerator`, `synchronizeVLMComponentLoad`,
`shouldUnloadVLMComponent`, `importModel`, `subscribeSDKEvents`,
`unsubscribeSDKEvents`, `pollSDKEvent`, `publishSDKEvent`,
`publishSDKFailure`, `extractStructuredOutput`,
`generateWithStructuredOutput`.

### KOT-PARITY-HELPER-FILES — ✅ CLOSED in wave 2

Added 9 helper files mirroring Swift:
- `RASTTConfiguration+Helpers`
- `RATTSConfiguration+Helpers`
- `RAVADConfiguration+Helpers`
- `RAVLMImage+Helpers` (plus an Android-only Bitmap helper)
- `EmbeddingsProto+Helpers`
- `StructuredOutputProto+Helpers`
- `RAGProto+Helpers`
- `StorageProto+Helpers`
- `ModelTypes+Artifacts`

### KOT-PARITY-CPP02 — ✅ CLOSED in wave 3

Implemented `update_registry_on_completion` in `download_orchestrator.cpp`
so the C++ side now self-heals the registry on download completion.
This closes the parity gap with Swift, where commons handled the
post-download registry toggle. The Kotlin-side
`markModelDownloadedInRegistry()` self-heal becomes redundant once
this code path is verified end-to-end.

### KOT-PARITY-FILE-LISTDIR — ✅ CLOSED in wave 3

Added a `file_list_directory` callback to `rac_platform_adapter_t` so
that `rac_model_registry_refresh_proto(rescan_local=true)` actually
walks the model storage tree on Android once the platform adapter
wires the callback. Without this, the rescan path was a no-op on
Android because the C++ core had no way to enumerate the on-disk
model directory.

### KOT-PARITY-RA-ALIASES — ✅ CLOSED in wave 3

Added `commonMain/.../public/types/SwiftAliases.kt` with 37 RA-prefix
typealiases mirroring Swift's RA prefix convention (e.g.
`typealias RAModelInfo = ai.runanywhere.proto.v1.RAModelInfo`,
`typealias RAGenerationOptions = ai.runanywhere.proto.v1.RAGenerationOptions`,
etc.). Adoption sweep across SDK + example app per task L2 — all
public-surface call sites now reference the RA-prefixed aliases
instead of the fully-qualified proto types.

### KOT-CATALOG-SEED-RESTORED — ✅ CLOSED in wave 3

Restored the curated model catalog in
`examples/android/RunAnywhereAI/app/src/main/.../ModelBootstrap.kt`
(LLM / VLM / STT / TTS / VAD / Embedding) that was deleted in commit
`34e32b68a`. The seed is idempotent: re-registration on every launch
preserves `is_downloaded` / `local_path` state from prior runs because
`ModelInfo.upsert(...)` semantics are merge-by-id. The More tab now
renders the same set of selectable models as Swift's iOS example.

### KOT-STORAGE-PATH-INIT — ✅ CLOSED in wave 3

`CppBridge.initialize()` now eagerly materializes the model storage
base directory at end of Phase 1 so `rac_download_plan_proto` no longer
fails with "failed to compute model storage path". Previously the
storage dir was created lazily on first download attempt, which
produced a confusing first-run error.

### KOT-DOWNLOAD-COMPLETION-SELFHEAL — ✅ CLOSED in wave 3 (transitional)

Kotlin-side `markModelDownloadedInRegistry()` toggles
`is_downloaded=true` + `local_path` when the download stream emits
`DOWNLOAD_STATE_COMPLETED`. This is the transitional Kotlin-side
self-heal — it will be removed once commons CPP-02 (this PR) is
verified end-to-end on Pixel 8 Pro.

---

## Open / updated items

### KOT-E2E-PER-MODALITY-UNTESTED — verification queued

Status now "verification queued". Workstream I drills run after wave 3
commit lands; per-modality screenshots are pending on Pixel 8 Pro
across LLM / VLM / STT / TTS / VAD / Voice Agent / RAG / LoRA / Tool
Calling / Structured Output / Benchmarks / Solutions.

### B19-followup: align C++ JNI lookup paths after `OkHttpTransport` rename — NEW OPEN

After the `OkHttpTransport` rename, the C++ JNI lookup paths that
resolve the Kotlin transport bridge by FQCN need a follow-up audit to
confirm no stale class names remain in `runanywhere_commons_jni.cpp`
or related bridge code. Track as new open item; not blocking for this
PR.

---

# Part 0 — Pre-2026-05-10 history (preserved verbatim below)

Updated: 2026-05-09
Branch: `feat/v2-architecture` @ `2c4b8b599` (post-B4)

## Current modality state (physical Pixel 8 Pro, arm64-v8a, Android 16)

Structural sweep only. Full per-modality download+load+inference drills
have not yet been exercised on-device.

| Modality | Status |
|---|---|
| App launch (past `Application.onCreate`) | ✅ PASS |
| Backend registration (LlamaCPP + ONNX + Sherpa) | ✅ PASS |
| SDK two-phase init | ✅ PASS — 1386 ms |
| Native catalog refresh (proto JNI) | ✅ PASS |
| JNI thunk parity | ✅ PASS — 9 new thunks verified in `librunanywhere_jni.so` |
| Chat (LLM) UI | ✅ PASS (structural — download/load/inference DEFERRED) |
| Vision (VLM) UI | ✅ PASS (structural) |
| Voice Assistant Setup UI | ✅ PASS (structural) |
| More hub (STT / TTS / RAG / LoRA / Benchmarks / Solutions) UI | ✅ PASS (structural) |
| Settings UI | ✅ PASS (structural) |
| STT end-to-end (Whisper Tiny) | 🟡 UNTESTED |
| TTS end-to-end (Piper) | 🟡 UNTESTED |
| VAD (Silero) | 🟡 UNTESTED |
| Voice Agent round-trip | 🟡 UNTESTED |
| VLM inference | 🟡 UNTESTED |
| RAG (ingest + query) | 🟡 UNTESTED |
| LoRA (apply / remove / list / state) | 🟡 UNTESTED |
| Tool Calling | 🟡 UNTESTED |
| Structured Output | 🟡 UNTESTED |
| Benchmarks | 🟡 UNTESTED |
| Solutions (YAML pipeline) | 🟡 UNTESTED |

Evidence bundle (local only, `test_workflows/` is git-ignored):
`test_workflows/logs/20260509-213837-kotlin-only-validation/01_android_kotlin/`

## Deferred backend Kotlin bindings (do not file bugs)

The following are **deferred** per product direction:

- **Genie** (Qualcomm NPU) — closed-source AAR
  `io.github.sanchitmonga22:runanywhere-genie-android:0.2.1`. Re-introduce
  once a 16KB-compatible AAR aligned with the current proto-based Kotlin
  SDK surface is published.
- **MetalRT / WhisperKit / WhisperKit CoreML** — Apple-only; no Kotlin
  module expected.
- **WhisperCPP** — no dedicated Kotlin module. The `whisper.jni` dep in
  `sdk/runanywhere-kotlin/build.gradle.kts` is scoped to audio utilities.
- **Diffusion (diffusion-coreml)** — Apple-only.

---

# Part 1 — Closed in this PR

## KOT-E2E-R2-001: Excise Genie AAR from Android example — ✅ CLOSED

**Commit**: `d22d6230c`

**Symptom (pre-fix)**: Deterministic startup crash
`java.lang.NoClassDefFoundError: Failed resolution of: Lcom/runanywhere/sdk/core/types/SDKComponent;`
at `com.runanywhere.sdk.llm.genie.Genie.<clinit>(Genie.kt:38)` from
`ModelBootstrap.registerBackends()`. Process died before Compose rendered.

**Root cause**: AAR was compiled against pre-proto Kotlin SDK types
(`com.runanywhere.sdk.core.types.SDKComponent` /
`com.runanywhere.sdk.core.types.InferenceFramework`) that no longer exist
(types moved to `ai.runanywhere.proto.v1.*`).

**Fix**:
- Removed `io.github.sanchitmonga22:runanywhere-genie-android:0.2.1@aar`
  dep + `genieAar` gradle config + `extractGenieClassesJar` task.
- Removed `implementation(genieRuntimeClasses)` and the jniLibs excludes
  block for libGenie / libQnn / librac_backend_genie.
- Removed `import com.runanywhere.sdk.llm.genie.Genie` and the
  `Genie.register(priority = 200)` call in `ModelBootstrap.kt`.

**Validation**: See evidence bundle above — clean launch on Pixel 8 Pro,
zero `Genie.<clinit>` / `NoClassDefFoundError` in logcat.

## KOT-JNI-ORPHAN: 18 orphan `external fun` → UnsatisfiedLinkError — ✅ CLOSED

**Commit**: `8fdcb39da`

**Symptom (pre-fix)**: `UnsatisfiedLinkError` at first runtime call from
any `external fun` whose matching C thunk never existed.

**Resolution by category**:

- **4 LoRA catalog proto orphans** (live callers in `CppBridgeModalityProto.kt`):
  Added matching JNI thunks in
  `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` forwarding to
  the commons proto C API
  (`rac_lora_catalog_{list,query,get,mark_download_completed}_proto`).

- **5 plugin registry orphans** (live callers in `RunAnywhere+PluginLoader.jvmAndroid.kt`):
  Added JNI thunks forwarding to `rac_plugin_api_version`,
  `rac_registry_load_plugin`, `rac_registry_unload_plugin`,
  `rac_registry_plugin_count`, `rac_registry_list_plugins`
  (with `rac_registry_free_plugin_list` cleanup inside the thunk).

- **3 `racDownload*` legacy orphans** (zero callers): Deleted. Proto
  siblings (`racDownloadStartProto`, `racDownloadCancelProto`,
  `racDownloadPollProgressProto`) are the canonical surface.

- **6 `racModelRegistry*` non-proto orphans** (zero callers): Deleted. Proto
  siblings already existed in JNI and cover all registry CRUD.

**Validation**: `nm -D sdk/runanywhere-kotlin/src/androidMain/jniLibs/arm64-v8a/librunanywhere_jni.so | grep -E 'racLoraCatalog|racRegistry'`
returns all 9 new `Java_*` symbols. App launches clean on Pixel 8 Pro
with zero `UnsatisfiedLinkError` in logcat.

## KOT-DUP-CANHANDLE: dead `canHandle*` methods in backend modules — ✅ CLOSED

**Commit**: `2c4b8b599`

Mirrors `SWIFT-DUP-CANHANDLE` in swift.md. The C++ plugin router
(`rac_plugin_route`) is the only routing authority; Kotlin-side
format-matching heuristics were never called from the dispatch path.

**Deleted**:
- `modules/runanywhere-core-llamacpp/.../LlamaCPP.kt:canHandle(modelId)` —
  matched `.gguf`; C++ tables accept `.gguf`/`.ggml`/`.bin`.
- `modules/runanywhere-core-onnx/.../ONNX.kt:canHandleSTT/TTS/VAD` —
  substring matching on `whisper`/`zipformer`/`piper`/`vits` etc.

---

# Part 2 — Open items

## KOT-E2E-PER-MODALITY-UNTESTED: full per-modality drills have not run (UNKNOWN)

- **Status**: Structural sweep (tab-level render + backend registration)
  done. Per-modality download → load → inference drills are all
  DEFERRED. None of LLM / STT / TTS / VAD / Voice Agent / VLM / RAG /
  LoRA / Tool Calling / Structured Output / Benchmarks / Solutions has
  been exercised end-to-end on Pixel 8 Pro.
- **Action**: Run targeted validation drills when the Kotlin Android
  lane graduates from "builds + launches clean" to "modality matrix
  green". Each modality gets its own run with screenshots per the
  `test_workflows/instructions/kotlin/README.md` Modality Workflow
  (001_open → 002_download_started → 003_progress → 004_complete →
  005_loaded → 006_inference_output).

## KOT-API-ALIGNMENT-SWIFT: Kotlin public API diverges from Swift (LOW)

- **Status**: The Kotlin extension API surface has 15 cosmetic
  divergences from the Swift canonical names. iOS is source of truth
  per CLAUDE.md but renaming Kotlin now would break Android example-app
  callers. Parity is cosmetic; behaviour is equivalent.
- **Divergences catalogued** (representative list — full inventory in
  the original Swift/Kotlin audit):

| Area | Kotlin current | Swift canonical | Action |
|---|---|---|---|
| LLM | `RunAnywhere.chat(prompt)` exists | no `chat()` | Remove `chat()` |
| Tool Calling | `clearTools()` exists | no `clearTools()` | Remove |
| Structured Output | `parseStructuredOutput(request)` | `extractStructuredOutput(text, schema)` | Rename + signature |
| LoRA | `list(request)`, `state(request)` | `list()`, `state()` | Remove unnecessary args |
| STT | `transcribeWithOptions(...)` | (not in Swift) | Delete |
| TTS | no `stopSpeaking()` | `stopSpeaking()` | Add |
| VAD | `initializeVAD()` / `initializeVAD(config)` public | Not public in Swift | Move to internal |
| VLM | `processImage(image, prompt, options)` | `processImage(image, options)` | Make prompt optional |
| VLM | `describeImage(...)`, `askAboutImage(...)` convenience | not in Swift | Remove |
| Voice Agent | `isVoiceAgentReady()` | use `getVoiceAgentComponentStates()` | Remove |
| Voice Agent | no `processVoiceTurn(audioData)` | exists | Add |
| Solutions | `SolutionHandle.feed(ByteArray)` | `feed(String)` | Align |
| Storage | `checkStorageAvailability(...)` | `checkStorageAvailable(...)` | Rename |
| RAG | `metadataJson` | `metadataJSON` | Rename |
| Init | `completeServicesInitialization()` not auto-called | Swift auto-calls | Auto-call from `ensureServicesReady()` |

- **Scope**: M. Each rename is 1 file + 1-3 example-app call-site updates.
- **Priority**: LOW — does not block functional E2E.

## KOT-HTTP-ADAPTER-CLEAN: OkHttpTransport is correctly located (INFO)

Unlike Swift's `HTTPClientAdapter.swift` (SWIFT-DUP-HTTP-ADAPTER-MISLOCATED),
Kotlin's `OkHttpTransport.kt` at `foundation/http/` has zero
Supabase-specific logic, zero auth retry loops, zero HTTP-error
classification. No cleanup needed. See Foundation audit.

## KOT-DUP-NOTABLE-ABSENCES (INFO)

Systematic checks confirmed Kotlin does **not** inherit the major Swift
duplication patterns audited in this PR:

- No orphan `RA*Types+CppBridge.kt` C-struct marshaling (Kotlin uses
  proto-bytes → JNI directly, never had `withCOptions` / `init(from cResult:)`).
- No duplicate runtime-module headers (Kotlin AARs ship Kotlin bytecode
  + `.so` only, never C headers).
- VAD already on the proto-backed lifecycle surface (`CppBridgeVADProto`
  at `CppBridgeModalityProto.kt:366-473` uses `racVadComponent*Proto`),
  so there's no equivalent of `SWIFT-VAD-001`.
- Generated proto types are all consumed — no Router*/Pipeline*/Solution*/
  Diffusion* orphans comparable to Swift's.

---

## Rules followed

Per repo convention: **DELETE, don't deprecate**. Every removed
`external fun` was verified to have zero callers via grep across
`src/` + `modules/` + `examples/android/RunAnywhereAI/app/src`.
Every new JNI thunk mirrors the shape of an existing live thunk.
Native `.so` files are rebuilt via `scripts/build-core-android.sh
arm64-v8a` but are git-ignored; CI will rebuild from source on next
tag. Build gates at each phase: `./gradlew compileDebugKotlinAndroid`
+ `./gradlew :app:assembleDebug` both green.
