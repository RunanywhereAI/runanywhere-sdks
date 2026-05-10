# React Native SDK — Current Inconsistencies

Updated: 2026-05-06
Branch: `feat/v2-architecture` @ `bb63158d6`

## Typecheck status

| Package | Result |
|---------|--------|
| `@runanywhere/core` | PASS (`tsc --noEmit`) |
| `@runanywhere/llamacpp` | PASS (`tsc --noEmit`) |
| `@runanywhere/onnx` | PASS (`tsc --noEmit`) |

## Deferred backend RN packages (stub or exclude OK)

Genie / MetalRT / WhisperKit / WhisperKit-CoreML / WhisperCPP / Diffusion — no RN package exists for any of these under `sdk/runanywhere-react-native/packages/`. Only `core`, `llamacpp`, `onnx` ship. No work tracked here for deferred-backend RN surfaces.

## Open inconsistencies

### RN-E2E-R2-001: Every model download fails — `rac_model_paths_get_model_folder` non-SUCCESS (HIGH)

Every RN Android model download (LlamaCPP + Sherpa, framework-agnostic) fails with:

> `rac_model_paths_get_model_folder returned non-SUCCESS → failed to compute model storage path`

Origin: `sdk/runanywhere-commons/src/infrastructure/download/download_orchestrator.cpp:1265`.

Root cause (confirmed): RN TypeScript `initialize()` never passes `documentsPath` in its configJson, so the C++ bridge's `InitBridge::setBaseDirectory()` call is skipped and `rac_model_paths_set_base_dir` is never invoked. The C++ bridge at `sdk/runanywhere-react-native/packages/core/cpp/HybridRunAnywhereCore.cpp:99-103` reads `extractStringValue(configJson, "documentsPath")` and bails silently when empty.

**Next action**: edit `sdk/runanywhere-react-native/packages/core/src/Public/RunAnywhere.ts` `initialize()` (the `configJson` assembly around line 243) to include a `documentsPath` field resolved from the platform (iOS: `NSDocumentDirectory`; Android: `Context.getFilesDir()`). Likely need a new Nitro spec method `getDocumentsPath()` on `RunAnywhereCore.nitro.ts` that returns the platform documents dir, or populate it in the C++ bridge side via the platform adapter before falling back on the JSON field. Mirror the Swift path in `sdk/runanywhere-swift/.../CppBridge+ModelPaths.swift`.

### RN-E2E-R2-002: iOS LLM "Get" button never transitions to Ready/Use/Loaded (MEDIUM)

On RN iOS sim, tapping "Get" on an LLM card shrinks the button into a progress indicator but never transitions to Ready/Use/Loaded within a 90+s observation window. Model names are also missing from the accessibility tree, so the test harness can't inspect state.

Could be a11y-only (state present but unreachable by AX queries) OR an actual download hang. Fix: add model name + state to a11y labels in `examples/react-native/RunAnywhereAI/`; instrument the Nitro ModelManagement download progress callback on iOS simulator to confirm progress events arrive.

### RN-E2E-R2-003: Test instruction doc lists wrong iOS bundle ID (LOW)

`test_workflows/instructions/react_native/ios.md` lists `org.reactjs.native.example.RunAnywhereAI`; the actual installed app bundle ID is `com.runanywhere.runanywhereai`. Update the instruction doc. (`test_workflows/` is gitignored, noted here for context.)

### RN-THINKING-MIGRATE: `LlmThinking` + C++ bridge bind 3 now-internal helpers (MEDIUM)

- **TS facade**: `packages/core/src/Features/LLM/LlmThinking.ts` still calls Nitro RPCs `llmExtractThinking` / `llmStripThinking` / `llmSplitThinkingTokens`.
- **C++ bridge**: `packages/core/cpp/HybridRunAnywhereCore+Voice.cpp:481,513,527` implements those 3 RPCs via `rac_llm_extract_thinking`, `rac_llm_strip_thinking`, `rac_llm_split_thinking_tokens`.
- **Nitro spec**: `packages/core/src/specs/RunAnywhereCore.nitro.ts:490,499,511`.
- **Callers**: `packages/core/src/Public/Extensions/RunAnywhere+TextGeneration.ts:301,314`.

These 3 C helpers were downgraded from `RAC_API` to `@internal` under CPP-05 and removed from `exports/RACommons.exports`. The next `RACommons.xcframework` rebuild will break the Apple link of `HybridRunAnywhereCore+Voice.cpp`. Commons now populates `LLMGenerationResult.thinking_content` / `.thinking_tokens` / `.response_tokens` / `.text` in proto generate + stream, so the TS layer can read them off `LLMGenerationResult` / `LLMStreamEvent` proto bytes.

Fix steps:
1. Delete `packages/core/src/Features/LLM/LlmThinking.ts`.
2. Delete the three RPC blocks in `HybridRunAnywhereCore+Voice.cpp` + `HybridRunAnywhereCore.hpp:233-237` + `RunAnywhereCore.nitro.ts:490-522`.
3. Regenerate nitrogen (`yarn core:nitrogen`).
4. Update `RunAnywhere+TextGeneration.ts` callers to read `thinkingContent` / `text` off the proto-typed `generate()` result.
5. Sync header copy at `packages/core/cpp/`.

Scope: S (~200 LOC delete across TS + C++ + Nitro spec + 2 TS call-site edits).

### RN-TEST-HARNESS-RELAND: Re-introduce RN streaming-parity harness (LOW — future wave)

Wave 3d Row 6 deleted the phantom Jest harness (`test` script + `jest`/`ts-jest`/`@types/jest` devDeps) from `packages/core/package.json`. No `jest.config.*` + no `tests/streaming/*.rn.test.ts` fixtures exist — pure dead weight currently.

**Acceptance (future)**: rebuild `tests/streaming/*.rn.test.ts` consuming the shared C++ golden fixtures (`tests/streaming/cancel_parity/`, `tests/streaming/perf_bench/`) to match Swift/Kotlin/Flutter/Web parity. Re-add `jest` + `ts-jest` + `@types/jest` devDeps + root-level `jest.config.js` with `--passWithNoTests`.

### RN-JSON-PROTO-MIGRATE: Migrate 7 JSON-string Nitro surfaces to proto (LOW — future iteration)

Documented as canonical cross-SDK exception in `docs/CPP_PROTO_OWNERSHIP.md` ("JSON String Surfaces (Cross-SDK)", classification `compat`). All 7 surfaces round-trip through `JSON.parse` on the TS side and carry identical JSON shape across Swift/Kotlin/Flutter/RN/Web — no cross-SDK drift today, only a violation of the "all wire types are proto" rule.

**Surfaces** (all on `RunAnywhereCore.nitro.ts`):
- `initialize(configJson)` (line 48)
- `registerDevice(environmentJson)` (line 97)
- `httpRequest(method, url, headersJson, bodyJson, timeoutMs)` (line 371)
- `authAuthenticate(apiKey, baseURL, deviceId, platform, sdkVersion)` (line 390)
- `authRefreshToken(baseURL)` (line 405)
- `getBackendInfo()` (line 63)
- `getDeviceCapabilities()` (line 427)

**Acceptance**: add proto messages under `idl/` (`SDKInitConfig`, `DeviceRegisterRequest`, `HTTPRequestEnvelope`/`HTTPResponseEnvelope`, `AuthRequest`/`AuthResponse`, `BackendInfo`, `DeviceCapabilities`) and migrate each surface end-to-end across all 5 SDKs in the same iteration. Scope: L.

## Example app (RN) inconsistencies

| Issue | Files | Notes |
|-------|-------|-------|
| Local `STTMode` / `VoicePipelineStatus` enums | `examples/react-native/RunAnywhereAI/src/types/voice.ts:7,12` | UI-side state machines; `VoicePipelineStatus` overlaps `VoiceEventKind`. Low priority. |
| Local `GenerationSettings` / `AppSettings` | `examples/react-native/RunAnywhereAI/src/types/settings.ts:23,40` | Fields overlap with `LLMGenerationOptions` — consider `Pick<LLMGenerationOptions, ...>`. Low priority. |

## Cross-SDK naming alignment

| Concern | Swift | Kotlin | Flutter | Web | **React Native** | Drift? |
|---------|-------|--------|---------|-----|------------------|--------|
| Entry | `enum RunAnywhere` | `object RunAnywhere` | `RunAnywhereSDK.instance` | `RunAnywhere` object | `const RunAnywhere` object | OK |
| Init | two-phase | same | same | same | same | OK |
| LLM stream | `AsyncStream` | `Flow` | `Stream` | `AsyncIterable` | `AsyncIterable` (manual `iterator.next()` for Hermes) | OK |
| Errors | `SDKException` proto-backed | same | same | same | same | OK |
| Hardware preference setter | `setAcceleratorPreference(_:)` | same | — | — | `setAcceleratorPreference(p)` | OK |
| NPU chip resolver | `NPUChipDetector.chip() -> NPUChip` | Android structured chip ID | — | — | `Hardware.getNPUChip() -> NPUChip` | OK |
| `initialize(config)` wire | proto/plist | proto | proto | JSON string | JSON string (RN-JSON-PROTO-MIGRATE) | Consistent with Web |
| HTTP transport | URLSession | OkHttp | URLSession/OkHttp | `emscripten_fetch` | URLSession/OkHttp | OK |
