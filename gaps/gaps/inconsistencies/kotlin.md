# Kotlin SDK — Current Inconsistencies

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
