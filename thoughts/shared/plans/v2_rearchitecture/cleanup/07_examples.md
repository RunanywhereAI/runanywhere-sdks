# examples/ — v1/v2 cleanup audit

_Scope_: `examples/android/`, `examples/ios/`, `examples/flutter/`,
`examples/react-native/`, `examples/web/`, `examples/intellij-plugin-demo/`

_Reference_: `docs/v2-migration.md`, `thoughts/shared/plans/v2_rearchitecture/MASTER_PLAN.md`,
`thoughts/shared/plans/v2_rearchitecture/implementation_plan.md`

---

## 1. DELETE-NOW

| Path | Reason |
|------|--------|
| `examples/ios/RunAnywhereAI/build/` | Committed build artifacts: `.xcarchive`, `.app` bundle, `RACommons.framework`, `RABackendLLAMACPP.framework`, `RABackendONNX.framework`, `onnxruntime.framework`, `Sentry.framework`. Binary blobs in git history; framework names are v1-specific and will not exist in v2. |
| `examples/android/RunAnywhereAI/app/src/main/jniLibs/arm64-v8a/libQnnHtpV81.so` | 14 MB Qualcomm HTP binary committed to git. Device-specific library for Genie NPU backend; should be fetched at runtime or delivered via the Genie AAR, not committed. |
| `examples/android/RunAnywhereAI/app/detekt-baseline.xml` | References `ModelsScreen.kt`, `ChatScreen.kt`, `MediaPipeService.kt`, `ModelRepository.kt`, `ONNXRuntimeService.kt` — none of these files exist in the current source tree. The baseline is actively suppressing Detekt warnings against phantom files. |

---

## 2. REWRITE-FOR-V2

All six example apps are v1-only at this point. Per `docs/v2-migration.md`: "Port of
the existing v1 examples to use the v2 adapters" is explicitly out of scope for the
bootstrap PR; v1 examples continue to work against v1 SDKs unchanged until Phase 1–3
gates land.

### 2a. Android (`examples/android/RunAnywhereAI/`)

**Why v1-only**

- `app/build.gradle.kts` depends on `project(":runanywhere-kotlin")`,
  `project(":runanywhere-core-llamacpp")`, `project(":runanywhere-core-onnx")`,
  and `io.github.sanchitmonga22:runanywhere-genie-android:0.2.1` — all v1 artifacts.
- `data/ModelList.kt` (394 lines) calls `RunAnywhere.registerModel()`,
  `RunAnywhere.registerMultiFileModel()`, `RunAnywhere.registerLoraAdapter()` with
  `InferenceFramework.LLAMA_CPP`, `.ONNX`, `.GENIE` — v1 API surface.
- `RunAnywhereApplication.kt` calls `RunAnywhere.initialize()` +
  `RunAnywhere.completeServicesInitialization()` — replaced by
  `RunAnywhere.solution(.voiceAgent(...))` in v2.

**Target (Phase 2 gate)**: Replace dependencies with `frontends/kotlin/` v2 adapter;
replace model catalog with `core/model_registry/` lookup; replace init with v2
`VoiceSession` / `Flow<VoiceEvent>` API.

### 2b. iOS (`examples/ios/RunAnywhereAI/`)

**Why v1-only**

- `Package.swift` depends on `path: "../../.."` (repo root) resolving to
  `sdk/runanywhere-swift/` products: `RunAnywhere`, `RunAnywhereONNX`,
  `RunAnywhereLlamaCPP`, `RunAnywhereWhisperKit` — all v1 Swift SDK targets.
- `RunAnywhereAIApp.swift` lines 196–676 (~480 lines) call `RunAnywhere.registerModel()`
  for LLM, MetalRT, VLM, ONNX STT/TTS/VAD, WhisperKit, embedding, CoreML diffusion,
  and LoRA adapters — v1 API surface.
- `DemoLoRAAdapter.swift`: `LoRAAdapterCatalog.registerAll()` calls
  `RunAnywhere.registerLoraAdapter()` (v1) with five hardcoded HuggingFace adapters.

**Target (Phase 1 gate)**: Swap `Package.swift` dependency from `sdk/runanywhere-swift/`
to `frontends/swift/`; replace model registration with `core/model_registry/` catalog;
replace init with v2 `VoiceSession` / `AsyncThrowingStream<VoiceEvent, Error>` API.

### 2c. Flutter (`examples/flutter/RunAnywhereAI/`)

**Why v1-only**

- `pubspec.yaml` depends on local path `../../../sdk/runanywhere-flutter/packages/runanywhere`,
  `runanywhere_llamacpp`, `runanywhere_genie`, `runanywhere_onnx` — v1 Flutter SDK (22,838
  LOC Dart FFI bridge, per implementation_plan.md Phase 3A).
- `lib/app/runanywhere_ai_app.dart` `_registerModulesAndModels()` (lines 142–342) calls
  `LlamaCpp.addModel()`, `Genie.register()`, `RunAnywhere.registerModel()`,
  `Onnx.register()`, `RAGModule.register()` — all v1.
- `lib/features/voice/voice_assistant_view.dart` uses v1 voice APIs:
  `sdk.RunAnywhere.startVoiceSession()`, `VoiceSessionHandle`, `VoiceSessionListening`,
  `VoiceSessionTranscribed`, `VoiceSessionResponded`, `VoiceSessionSpeaking`,
  `VoiceSessionTurnCompleted`, `VoiceSessionError`, `VoiceSessionStopped`.
- `ios/Podfile` + `ios/Runner.xcworkspace/` present (Flutter iOS standard;
  expected for v1 but incompatible with v2 Phase 1 gate for iOS-native usage).

**Target (Phase 3A gate)**: Replace 22,838 LOC Dart FFI bridge with `frontends/dart/`
v2 adapter; replace voice event types with proto3-generated Dart classes.

### 2d. React Native (`examples/react-native/RunAnywhereAI/`)

**Why v1-only**

- Depends on v1 Nitro bridge (21,250 LOC, per implementation_plan.md Phase 3B).
- `src/types/model.ts:183` declares `sizeOnDisk: number` — a TypeScript interface field
  that references an unimplemented SDK property.
- `src/screens/SettingsScreen.tsx:684` has `// TODO: Replace with actual disk size once
  SDK exposes it (e.g., sizeOnDisk or actualSize)` confirming the field is dead.
- `ios/Podfile` + `ios/RunAnywhereAI.xcworkspace/` present (RN standard CocoaPods with
  `ENV['RCT_NEW_ARCH_ENABLED'] = '1'`; incompatible with v2 zero-CocoaPods gate for
  iOS-native usage).

**Target (Phase 3B gate)**: Replace Nitro bridge with v2 JSI bridge (~300 LOC); remove
`sizeOnDisk` dead field or bind it to actual `core/model_registry/` size metadata.

### 2e. Web (`examples/web/RunAnywhereAI/`)

**Why v1-only**

- `src/main.ts` imports from
  `../../../../sdk/runanywhere-web/packages/core/src/index` — hardcoded relative path
  to v1 Web SDK source tree.
- Uses `SDKEnvironment.Development` (v1 init surface).

**Target (Phase 3 / Web gate)**: Re-point import to `frontends/web/` v2 package; replace
init with v2 session API.

### 2f. IntelliJ Plugin Demo (`examples/intellij-plugin-demo/`)

**Why v1-only**

- `plugin/build.gradle.kts` depends on
  `io.github.sanchitmonga22:runanywhere-sdk-jvm:0.16.1` — v1 KMP JVM artifact from
  Maven Local/Maven Central.
- `RunAnywherePlugin.kt` calls `RunAnywhere.initialize()` and
  `RunAnywhere.completeServicesInitialization()` (v1 init); uses `GlobalScope.launch`
  (unstructured concurrency).
- Will break when v1 KMP API changes under Phase 2 gate.

**Target (Phase 2 gate)**: Re-depend on `frontends/kotlin/` JVM target; replace with
v2 structured session API; replace `GlobalScope.launch` with plugin-scoped
`CoroutineScope`.

---

## 3. KEEP-AS-IS

| Path | Reason |
|------|--------|
| `examples/web/RunAnywhereAI/` (webpack/vite config, HTML, CSS) | Non-SDK scaffolding that is framework-neutral; will transfer to v2 unchanged. |
| `examples/android/RunAnywhereAI/app/src/main/res/` | UI assets, layouts, drawables — platform-neutral; no v1 API calls. |
| `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/Views/` | SwiftUI view layer — no SDK calls; reusable in v2 example. |

---

## 4. KEEP-AFTER-FIX

### 4a. Placeholder API Keys (IMM-4)

Four hard-coded placeholder strings across three files must be replaced before any
non-development build is distributed:

| File | Line | Value |
|------|------|-------|
| `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/RunAnywhereApplication.kt` | 153 | `"YOUR_PRODUCTION_API_KEY"` |
| `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/RunAnywhereApplication.kt` | 154 | `"YOUR_PRODUCTION_BASE_URL"` |
| `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift` | 166 | `"YOUR_API_KEY_HERE"` and `"YOUR_BASE_URL_HERE"` (in `#else` release branch) |
| `examples/intellij-plugin-demo/plugin/src/main/kotlin/com/runanywhere/plugin/RunAnywherePlugin.kt` | 59 | `"demo-api-key"` (literal in `if (SDK_ENVIRONMENT == SDKEnvironment.DEVELOPMENT)`) |

Note: `RunAnywhereApplication.kt:157-163` has a self-guard that detects the placeholder
and falls back to DEVELOPMENT mode, so the Android case does not crash — but any release
build shipped with this value silently degrades to development endpoints.

### 4b. Hardcoded NDK Version (IMM-5)

`examples/android/RunAnywhereAI/app/build.gradle.kts:14`
```
ndkVersion = "27.0.12077973"
```
Should be read from a central version catalog or `gradle.properties` shared with
`sdk/runanywhere-kotlin/`.

### 4c. Lint Baseline (active suppressions)

`examples/android/RunAnywhereAI/app/lint-baseline.xml`:
- `UnknownIssueId` for `LeakCanary` (3 entries) — suppresses unknown lint IDs that
  disappear when LeakCanary debug dependency is absent.
- `MissingPermission` for `AudioRecord` in `AudioCaptureService.kt` — suppresses a
  real missing `RECORD_AUDIO` permission declaration that should be fixed, not baselined.

---

## 5. INSPECT

### 5a. Duplicated Model Catalogs

Four per-platform copies of essentially the same model catalog exist. All four call v1
registration APIs and will need to be replaced by `core/model_registry/` lookups:

| File | LOC | Notable content |
|------|-----|-----------------|
| `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/ModelList.kt` | 394 | LLM, STT, TTS, embedding, LoRA, Genie NPU, VLM |
| `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift` | lines 196–676 (~480 lines in file) | LLM, MetalRT, VLM, ONNX STT/TTS/VAD, WhisperKit, embedding, CoreML diffusion, LoRA |
| `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/Models/DemoLoRAAdapter.swift` | 107 | LoRA only (code-assistant, reasoning-logic, medical-qa, creative-writing, abliterated) |
| `examples/flutter/RunAnywhereAI/lib/app/runanywhere_ai_app.dart` | lines 142–342 (~200 lines in file) | LLM, STT, TTS, Genie, ONNX, RAG |

The React Native example has no explicit catalog registration file visible; model
selection appears handled differently (via the `sizeOnDisk` unimplemented property in
`src/types/model.ts`).

### 5b. CocoaPods / SwiftPM Migration Status

| Example | Status | Notes |
|---------|--------|-------|
| `examples/ios/RunAnywhereAI/` | **SwiftPM only** — no Podfile | `Package.swift` present; v2 Phase 1 gate (zero `pod install`) is already satisfied for this example at the dependency-management level. The `CLAUDE.md` README still documents `pod install` / `fix_pods_sandbox.sh` steps, but those are stale for this example. |
| `examples/flutter/RunAnywhereAI/ios/` | CocoaPods present | Flutter iOS plugins require CocoaPods; this is expected for a Flutter app and is not a migration gap for v2 (Flutter frontend is Phase 3A). |
| `examples/react-native/RunAnywhereAI/ios/` | CocoaPods present | RN iOS requires CocoaPods (`ENV['RCT_NEW_ARCH_ENABLED'] = '1'`); expected for v1 RN; Phase 3B will replace with v2 JSI bridge. |

### 5c. Flutter / RN Voice API Shape vs v2 Target

The v1 voice session event types in Flutter (`VoiceSessionListening`,
`VoiceSessionTranscribed`, `VoiceSessionResponded`, `VoiceSessionSpeaking`,
`VoiceSessionTurnCompleted`, `VoiceSessionError`, `VoiceSessionStopped`) are defined in
the v1 `sdk/runanywhere-flutter/` package. The v2 target event type set is generated
from `idl/voice_events.proto` and will be emitted as a `Flow<VoiceEvent>` (Kotlin) or
`AsyncThrowingStream<VoiceEvent, Error>` (Swift) with different field names and
granularity. The RN `src/types/model.ts` interface including `sizeOnDisk` will need a
full audit against the proto3-generated TS types once `idl/codegen/generate_ts.sh` runs.

### 5d. IntelliJ Plugin Demo — Scope Ambiguity

The plugin demo (`examples/intellij-plugin-demo/`) targets IntelliJ IC `2024.1` with
plugin Gradle `1.17.4` (current as of Q1 2025). It is not referenced from any CI
workflow in `.github/workflows/`. It is unclear whether this demo is expected to remain
a shipping artifact or will be superseded by a JetBrains Marketplace plugin built
directly on `frontends/kotlin/`. Needs product decision before Phase 2 gate.

---

## 6. Summary Counts

| Category | Count |
|----------|-------|
| DELETE-NOW entries | 3 |
| REWRITE-FOR-V2 apps | 6 |
| KEEP-AFTER-FIX items | 7 (4 placeholder keys + 1 NDK + 2 lint entries) |
| Duplicated model catalogs | 4 platform copies |
| CocoaPods still present | 2 (Flutter, RN — expected) |
| CocoaPods eliminated | 1 (iOS — already SwiftPM) |
| Unimplemented SDK fields in RN types | 1 (`sizeOnDisk`) |
