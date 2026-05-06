# React Native SDK — Current Inconsistencies

Updated: 2026-05-05 (Discovery I)
Branch: `feat/v2-architecture` @ `6217d9e67`

## Typecheck status

| Package | Result |
|---------|--------|
| `@runanywhere/core` | PASS (`tsc --noEmit`) |
| `@runanywhere/llamacpp` | PASS (`tsc --noEmit`) |
| `@runanywhere/onnx` | PASS (`tsc --noEmit`) |

## Current state summary

Yarn Berry 3.6.1 monorepo, three workspaces (`packages/core`, `packages/llamacpp`, `packages/onnx`) + `../runanywhere-proto-ts`. The core package exposes a Nitro HybridObject spec
(`packages/core/src/specs/RunAnywhereCore.nitro.ts`, 979 lines, **134 method slots: 74 `*Proto` + 60 non-proto**) plus 20 extension files under `Public/Extensions/` (~5.7K lines).

**Backend packages**: `@runanywhere/llamacpp` and `@runanywhere/onnx` ship full native plumbing — Nitro spec + C++ HybridObject + iOS podspec + XCFrameworks (`packages/*/ios/Frameworks/`) + `.so` files (`packages/*/android/src/main/jniLibs/`) + JNI adapters. Registration APIs are proto-canonical (`registerBackend()` / `unregisterBackend()` / `isBackendRegistered()`).

**Proto canonicalisation**: Types in `packages/core/src/types/index.ts` re-export from `@runanywhere/proto-ts/*`. The only RN-local types are `FrameworkModality`, `PrivacyMode`, `ModelCategoryDisplayNames`, and `SDKInitOptions`.

## Confirmed open gaps

### RN-TEST-HARNESS-RELAND: Re-introduce RN streaming-parity harness (LOW — future wave)

**Context**: Wave 3d Row 6 deleted the phantom Jest harness (`test` script + `jest`/`ts-jest`/`@types/jest` devDeps) from `packages/core/package.json` and corrected `sdk/runanywhere-react-native/CLAUDE.md`. No `jest.config.*` file existed at delete-time and no `tests/streaming/*.rn.test.ts` fixtures existed either — pure dead weight.

**Acceptance (future)**: rebuild `tests/streaming/*.rn.test.ts` consuming the shared C++ golden fixtures (see `tests/streaming/cancel_parity/` and `tests/streaming/perf_bench/`) to match Swift/Kotlin/Flutter/Web parity tests. Re-add `jest` + `ts-jest` + `@types/jest` devDeps + root-level `jest.config.js` with `--passWithNoTests` safety net.

### RN-JSON-PROTO-MIGRATE: Migrate 7 JSON-string Nitro surfaces to proto (LOW — future iteration)

**Context**: Wave 3d Row 9 documented the JSON-string subset as a canonical cross-SDK exception in `docs/CPP_PROTO_OWNERSHIP.md` (section "JSON String Surfaces (Cross-SDK)", classification `compat`). The 7 surfaces below all round-trip through `JSON.parse` on the TS side and carry the same JSON shape across Swift, Kotlin, Flutter, React Native, and Web SDKs — so there is no cross-SDK drift today, only a violation of the "all wire types are proto" rule.

**Surfaces** (all on `RunAnywhereCore.nitro.ts`):
- `initialize(configJson: string): Promise<boolean>` (line 48)
- `registerDevice(environmentJson: string): Promise<boolean>` (line 97)
- `httpRequest(method, url, headersJson, bodyJson, timeoutMs): Promise<string>` (line 371)
- `authAuthenticate(apiKey, baseURL, deviceId, platform, sdkVersion): Promise<string>` (line 390)
- `authRefreshToken(baseURL: string): Promise<string>` (line 405)
- `getBackendInfo(): Promise<string>` (line 63)
- `getDeviceCapabilities(): Promise<string>` (line 427)

**Acceptance (future)**: add the following proto messages under `idl/` and migrate each surface end-to-end across all 5 SDKs in the same iteration:
- `SDKInitConfig` (replaces `initialize(configJson)`)
- `DeviceRegisterRequest` (replaces `registerDevice(environmentJson)`)
- `HTTPRequestEnvelope` / `HTTPResponseEnvelope` (replaces `httpRequest`)
- `AuthRequest` / `AuthResponse` (replaces `authAuthenticate` / `authRefreshToken`)
- `BackendInfo` (replaces `getBackendInfo`)
- `DeviceCapabilities` (replaces `getDeviceCapabilities`)

Until migration, the JSON wire form is the canonical contract (see `docs/CPP_PROTO_OWNERSHIP.md` → "JSON String Surfaces (Cross-SDK)"). Scope: L (proto design + C++ ABI + 5-SDK migration + TS migration).

### RN-09: *Deferred* (diffusion helper shim)

User deferred diffusion support entirely. No action until the diffusion track resumes.

## Resolved since Discovery H

| Gap | Commit / Evidence |
|-----|-------------------|
| RN-05 / RN-10 (`transcribeFile` JSON path) | `RunAnywhere+STT.ts:276` now reads audio via `react-native-fs` and routes through `sttTranscribeProto`. Nitro spec contains zero `transcribeFile` declarations. |
| RN-11 (RAGScreen inline defaults) | `c9fbc3e2a` — `examples/react-native/RunAnywhereAI/src/screens/RAGScreen.tsx:177` spreads `...helpers.ragHelpers.defaultRAGConfig()`. |
| RN-13 (stale `lib/` in git) | `.gitignore` at `packages/core/.gitignore` contains `lib/` + `*.tsbuildinfo`. `git ls-files sdk/runanywhere-react-native/packages/core/lib/` → 0 entries (untracked). |
| RN-14 (EventBus slim) | `5ceeaada9` — `Internal/Events/EventBus.ts` reduced to 43 LOC publish-only façade. **Doc drift opened → RN-15**. |
| RN-02 (duplicate backend podspecs) | `323843061` — deleted `packages/llamacpp/ios/LlamaCPPBackend.podspec` and `packages/onnx/ios/ONNXBackend.podspec`. Canonical podspecs at package roots (`RunAnywhereLlama.podspec`, `RunAnywhereONNX.podspec`) are the only ones referenced by `react-native.config.js`. |
| RN-12 (Hermes streaming caveat in READMEs) | `71e142ee5` — added "Hermes streaming" section to `sdk/runanywhere-react-native/README.md` and `packages/core/README.md` with the manual `Symbol.asyncIterator` loop pattern. Replaced the misleading `for await` example in the top-level Quick Start. Lists every affected `AsyncIterable` surface. |
| RN-15 (EventBus README drift) | `2b8862f25` — rewrote `packages/core/README.md` EventBus section as "SDK Events" describing `RunAnywhere.subscribeSDKEvents((event) => ...)`. Deleted `EventBus.on`, `RunAnywhere.events.*`, and the Event Categories table. |
| RN-07 (hardware preference setter wired) | Wave 3d Row 7 — added `setAcceleratorPreferenceProto(requestBytes)` Nitro method in `RunAnywhereCore.nitro.ts`, `HybridRunAnywhereCore+Hardware.cpp` impl calls `rac_hardware_set_accelerator_preference`, `RunAnywhere+Hardware.ts` renamed `setAccelerationPreference` → `setAcceleratorPreference` and the `_acceleratorPreference` JS cache is gone. |
| RN-08 (NPU chip resolver) | Wave 3d Row 8 — `RunAnywhere+Hardware.ts` now exports `getNPUChip(): Promise<NPUChip>` + `mapChipStringToNPUChip()` helper (~6 vendor families covered). `Hardware` namespace exposes `RunAnywhere.hardware.getNPUChip()`. JS-only string matcher over `hardwareProfileProto` chip field — no commons changes. |

## Items to DELETE

_(none — tracked items resolved or moved to reland rows)_

## Cross-SDK naming alignment gaps

| Concern | Swift | Kotlin | Flutter | Web | **React Native** | Drift? |
|---------|-------|--------|---------|-----|------------------|--------|
| Entry | `enum RunAnywhere` | `object RunAnywhere` | `RunAnywhereSDK.instance` | `RunAnywhere` object | `const RunAnywhere` object | OK |
| Init | `initialize()` + `completeServicesInitialization()` | same | same | same | same | OK |
| LLM stream | `AsyncStream` | `Flow` | `Stream` | `AsyncIterable` | `AsyncIterable` (manual `iterator.next()` for Hermes) | OK |
| Errors | `SDKException` proto-backed | same | same | same | same | OK |
| Hardware preference setter | `setAcceleratorPreference(_:)` | `setAcceleratorPreference(...)` | — | — | `setAcceleratorPreference(p)` | OK |
| Hardware preference sink | C ABI `rac_hardware_set_accelerator_preference` | same | — | — | C ABI (via Nitro `setAcceleratorPreferenceProto`) | OK |
| NPU chip resolver | `NPUChipDetector.chip() -> NPUChip` | Android structured chip ID | — | — | `Hardware.getNPUChip() -> NPUChip` (JS string matcher) | OK |
| Diffusion | `RunAnywhere+Diffusion.swift` | — | — | — | **MISSING — deferred** (RN-09) | Deferred |
| `initialize(config)` wire | proto/plist | proto | proto | JSON string | JSON string (RN-06) | Consistent with Web |
| `transcribeFile` path | proto-byte | proto-byte | proto-byte | proto-byte | proto-byte (RN-05 resolved) | OK |
| HTTP transport | URLSession | OkHttp | URLSession/OkHttp | `emscripten_fetch` | URLSession/OkHttp | OK |

### RN-THINKING-MIGRATE: `LlmThinking` + C++ bridge bind 3 now-internal helpers (MEDIUM)

- **TS facade**: `packages/core/src/Features/LLM/LlmThinking.ts` still calls the Nitro RPCs `core.llmExtractThinking/llmStripThinking/llmSplitThinkingTokens`.
- **C++ bridge**: `packages/core/cpp/HybridRunAnywhereCore+Voice.cpp:476,506,523` implements those 3 RPCs by calling `rac_llm_extract_thinking`, `rac_llm_strip_thinking`, `rac_llm_split_thinking_tokens` directly.
- **Nitro spec**: `packages/core/src/specs/RunAnywhereCore.nitro.ts:497,506,518` declares the 3 methods.
- **Callers**: `packages/core/src/Public/Extensions/RunAnywhere+TextGeneration.ts:302,315,326`.

These 3 C helpers were downgraded from `RAC_API` to `@internal` on 2026-05-05 under CPP-05 (Wave 1 Row 12, cpp-layer.md) and removed from `exports/RACommons.exports`. The NEXT `RACommons.xcframework` rebuild will break the Apple link of `HybridRunAnywhereCore+Voice.cpp`. Commons now populates `LLMGenerationResult.thinking_content` / `.thinking_tokens` / `.response_tokens` / `.text` in proto generate + stream, so the RN TS layer can read them off `LLMGenerationResult` / `LLMStreamEvent` proto bytes.

Fix steps:
1. Delete `packages/core/src/Features/LLM/LlmThinking.ts`.
2. Delete the `llmExtractThinking` / `llmStripThinking` / `llmSplitThinkingTokens` blocks in `HybridRunAnywhereCore+Voice.cpp:469-537` + `HybridRunAnywhereCore.hpp:233-237` + `RunAnywhereCore.nitro.ts:497-522`.
3. Regenerate nitrogen (`yarn core:nitrogen`).
4. Update `RunAnywhere+TextGeneration.ts:302,315,326` to read `result.thinkingContent` / `result.text` from the generated proto type returned by `RunAnywhere.generate(...)`.
5. Sync the header copy at `packages/core/cpp/` (if mirrored).

Validation: `yarn typecheck` green; `grep -rn "rac_llm_extract_thinking\|rac_llm_strip_thinking\|rac_llm_split_thinking_tokens\|llmExtractThinking\|llmStripThinking\|llmSplitThinkingTokens" sdk/runanywhere-react-native/packages` returns 0 hits (except in the XCFramework Header copies, which are auto-synced on the next `core:download-ios`).

Scope: S (~200 LOC delete across TS + C++ + Nitro spec + 3 TS call-site edits).

## Example app (RN) inconsistencies

| Issue | Files | Notes |
|-------|-------|-------|
| Local `STTMode` / `VoicePipelineStatus` enums | `examples/react-native/RunAnywhereAI/src/types/voice.ts:7-19` | UI-side state machines; `VoicePipelineStatus` overlaps `VoiceEventKind`. Low priority. |
| Local `GenerationSettings` / `AppSettings` | `examples/react-native/RunAnywhereAI/src/types/settings.ts:20-54` | Fields overlap with `LLMGenerationOptions` — consider `Pick<LLMGenerationOptions, ...>`. Low priority. |
