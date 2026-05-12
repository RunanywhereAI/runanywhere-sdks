# React Native SDK - Swift Alignment Inconsistencies

Updated: 2026-05-11
Scope: `sdk/runanywhere-react-native/`
Source of truth: `sdk/runanywhere-swift/Sources/RunAnywhere/`

This is the current React Native backlog for matching Swift end to end. Each item is intended to be small enough for one implementation agent. Agents may split their item further, but must not touch Kotlin, Flutter, or unrelated work from other agents.

## Baseline

Current React Native TypeScript baseline before this alignment work:

| Package | Command | Status |
|---|---|---|
| `@runanywhere/core` | `yarn workspace @runanywhere/core typecheck` | PASS |
| `@runanywhere/llamacpp` | `yarn workspace @runanywhere/llamacpp typecheck` | PASS |
| `@runanywhere/onnx` | `yarn workspace @runanywhere/onnx typecheck` | PASS |
| RN example | `yarn workspace runanywhere-ai-example typecheck` | PASS |

Run workspace commands from the monorepo root. Running `yarn typecheck` inside `sdk/runanywhere-react-native/` is not the canonical check because the root workspace owns the Yarn project.

## High-Priority Inconsistencies

### RN-SWIFT-001: Gap docs are stale

The RN gap docs still describe PR-review state and point fixes. Update file organization, inconsistencies, and PR review docs before code changes. Verify by direct file reads because `gaps/` is gitignored.

### RN-SWIFT-002: Public folder layout does not mirror Swift

React Native still uses a flat `Public/Extensions/RunAnywhere+*.ts` layout. Move capability files into Swift-mirrored folders and update barrels/imports.

### RN-SWIFT-003: Environment default differs from Swift

React Native initialization defaults to production-like behavior in places where Swift defaults to development. Align `SDKEnvironment` and initialization defaults to Swift.

### RN-SWIFT-004: Initialization is not Swift two-phase SDK init

Swift uses native phase 1 and phase 2 initialization through `rac_sdk_init_*`. RN still performs too much JS orchestration. Add native phase methods, serialize phase 2 readiness, and require services-ready for model/inference paths.

### RN-SWIFT-005: Model storage base directory is not reliably set

RN model downloads can fail when `documentsPath` is absent and `rac_model_paths_set_base_dir` is skipped. Add native document-directory resolution and set model paths before registry/discovery.

### RN-SWIFT-006: Auth state is duplicated in JS and native

Swift routes auth through native commons-backed auth state. RN still has duplicate JS token persistence and stale bridge behavior. Native should own token/auth state, with TS exposing typed status methods only.

### RN-SWIFT-007: Device registration is JS-fire-and-forget

Move registration into native phase 2, use platform device callbacks, and match Swift build-token/dev-mode semantics.

### RN-SWIFT-008: Model registry names are RN-specific

Current RN work is deleting the old `getAvailableModels` / `getDownloadedModels` surface and keeping the Swift-canonical `listModels`, `queryModels`, `getModel`, `downloadedModels`, `registerModel`, `importModel`, and `loadModel(ModelLoadRequest)` names.

### RN-SWIFT-009: Download completion does not mirror Swift import flow

RN should plan/start/poll/cancel like Swift and explicitly import completed artifacts with the same managed-storage flags. Remove implicit registry update assumptions.

### RN-SWIFT-010: `deleteModel` encodes the wrong proto requests

`deleteModel` must encode `ModelUnloadRequest` for unload and `StorageDeleteRequest` for storage delete. Add native delete-path support so files are actually removed.

### RN-SWIFT-011: Hardware fallback behavior hides native failures

Swift surfaces typed errors for unavailable hardware paths. RN should remove silent fallback behavior unless Swift has the same fallback.

### RN-SWIFT-012: Events do not match Swift naming or ownership

Rename RN event extension toward `SDKEvents`/`EventBus` vocabulary and delete dormant legacy event bridge code once the proto SDK event path owns the surface.

### RN-SWIFT-013: Logging surface is incomplete and has a method mismatch

RN facade calls `setLogLevel`, while the manager exposes `setMinLogLevel`. Expose Swift-equivalent logging controls and route native logs through the RN logging bridge.

### RN-SWIFT-014: Error folder and mapping do not match Swift

Rename `Foundation/ErrorTypes` to `Foundation/Errors`. Map native `rac_result_t`/proto errors into `SDKException` instead of boolean/last-error flows.

### RN-SWIFT-015: LLM API still exposes old thinking helpers

Delete `LlmThinking.ts`, Nitro thinking helper RPCs, and C++ helper methods. Read `thinkingContent`, `thinkingTokens`, `responseTokens`, and `text` from proto generation results/events.

### RN-SWIFT-016: Structured output orchestration still lives in JS

Swift delegates structured-output orchestration to native commons. RN should expose native proto methods and keep JS as encode/decode only.

### RN-SWIFT-017: Tool-calling run loop still lives in JS

Swift uses native run-loop orchestration. RN should keep JS tool executors but move parse/format/validate/follow-up orchestration to native.

### RN-SWIFT-018: RAG lacks Swift resolved-configuration parity

Add resolved configuration helpers and model-info/model-id overloads. Remove duplicated helper defaults where generated proto defaults exist.

### RN-SWIFT-019: TTS playback/cancellation does not match Swift

TTS `speak` should use generated synthesis output, convert/play WAV with returned format, and wire cancellation/stop to native where available.

### RN-SWIFT-020: STT/VAD/VLM readiness and streaming differ from Swift

Align readiness with lifecycle current model/category, use Swift-like streaming semantics, and surface invalid/unavailable states as typed errors.

### RN-SWIFT-021: VoiceAgent accepts a higher-level RN config instead of Swift compose config

Expose full Swift-equivalent compose config as canonical. Convenience config may remain only as a thin wrapper.

### RN-SWIFT-022: LoRA public API is nested and RN-specific

Flatten LoRA to Swift names for apply/remove/list/state/compatibility/catalog/import/download completion APIs.

### RN-SWIFT-023: Solutions overloads are not Swift-shaped

Add Swift-style `run(configBytes)`, `run(config)`, and `run(yaml)` overloads while keeping handle cleanup idempotent.

### RN-SWIFT-024: Plugin loader is missing

Add `RunAnywhere+PluginLoader.ts`. If dynamic loading is not supported on mobile RN, throw the same typed unavailable error Swift uses.

### RN-SWIFT-025: Docs and workflows are stale after API movement

Update RN `CLAUDE.md`, SDK docs, architecture docs, example docs, and React Native workflow instructions after code moves. Fix the iOS bundle id in workflow docs.

## Verification Requirements

Minimum static gates:

```bash
yarn workspace @runanywhere/core typecheck
yarn workspace @runanywhere/llamacpp typecheck
yarn workspace @runanywhere/onnx typecheck
yarn workspace runanywhere-ai-example typecheck
```

Full pass requires clean install, logs, model download, model load, real inference, screenshots, and log review for React Native Android and iOS. Build/install/launch alone is smoke validation only.
