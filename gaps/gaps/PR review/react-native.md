# React Native SDK - Swift Alignment PR Review Guide

Updated: 2026-05-13
Ownership: this document and `gaps/gaps/inconsistencies/react-native.md` only.

Review RN alignment as convergence to Swift plus C++/proto truth, not as compatibility preservation. A good PR removes stale RN-owned API and business logic when Swift/proto-shaped replacements exist, keeps TypeScript as a facade, and proves behavior with real validation. Do not review or modify Kotlin, Flutter, Swift, Web, or unrelated commons changes in this lane unless the task is explicitly widened.

## Current Review Position

Based on the current tree, React Native appears mid-alignment:

- The root `@runanywhere/core` surface is small and Swift-shaped, with provider/internal plumbing moved to `@runanywhere/core/internal`.
- `@runanywhere/proto-ts` is the shared generated TS source and intentionally uses subpath imports instead of root star exports.
- Many RN bridge methods use generated proto bytes, but initialization/auth/device/plugin-loader still include JSON, string, boolean, or ad hoc shapes.
- RN still has TypeScript orchestration or helper ownership in RAG, media playback/capture, stream fan-out, logging, network normalization, and some modality wrappers.
- Tool calling now routes the multi-iteration run loop through native/proto `toolRunLoopProto`; TypeScript should remain limited to registered tool callback execution.
- Swift remains the reference for public extension names and native ownership; C++/proto remains the reference for business logic and payload shapes.
- Build/install/launch evidence must be treated as `SMOKE_PASS` only until the all-modality matrix has real download/load/inference evidence.

## Required PR Shape

- Public API matches Swift `RunAnywhere` and `Public/Extensions/**` names unless an RN-native exception is documented.
- Domain types, enums, request/result messages, lifecycle state, events, and model metadata come from `@runanywhere/proto-ts/*`.
- Root `@runanywhere/core` exports only the public facade and unavoidable RN call-site types.
- `@runanywhere/core/internal` is used only by sibling backend packages, examples, and package plumbing.
- Native bridge calls use generated proto request/result bytes wherever Swift/C++ has proto ABI support.
- Phase 1 and Phase 2 initialization align with Swift's native ownership of platform adapter registration, HTTP/logging/device hooks, commons init, auth/device/model assignment/discovery, and offline-tolerant service init.
- TypeScript owns only ergonomic overloads, proto encode/decode at the bridge boundary, subscriptions, JS callback trampolines, and RN platform media glue that cannot live in commons.
- LlamaCPP and ONNX packages remain thin backend registration/runtime packages and do not expose provider internals as public SDK API.
- Packaging keeps generated TS in `@runanywhere/proto-ts`, not copied or regenerated into RN-local type aliases.

## Blocker Checklist

| Area | Block PR If |
| --- | --- |
| Scope | Kotlin, Flutter, Swift, Web, commons, or unrelated files are changed without explicit task ownership. |
| Source of truth | A public API or behavior conflicts with Swift without documenting an RN-native exception. |
| Proto truth | RN invents local DTOs/enums/lifecycle states already defined in `idl/*.proto`. |
| Root exports | Root leaks `Foundation`, `Features`, `Adapters`, `native`, `services`, `specs`, generated Nitro internals, or provider classes. |
| Internal subpath | `@runanywhere/core/internal` is documented or marketed as user-facing API. |
| Compatibility | Old RN aliases remain public after a Swift/proto canonical API exists. |
| Initialization | JSON/ad hoc init is expanded instead of being replaced or explicitly justified. |
| Auth/device | JS storage or JS state becomes source of truth for auth, user, org, or device identity. |
| Network | JS endpoint tables, telemetry batching, or routing behavior become SDK business logic. |
| Bridge | New native methods return JSON/string/boolean shapes where generated proto bytes or typed Nitro objects are available. |
| Streaming | Multiple subscribers silently replace each other without documented ABI limitation or fan-out fix. |
| Tool calling | JS owns the multi-iteration run loop instead of limiting itself to registered callback execution. |
| RAG/LoRA | JS metadata migration, catalog semantics, compatibility checks, or ingestion/query business rules duplicate commons/proto. |
| Modalities | LLM, STT, TTS, VAD, VLM, VoiceAgent, structured output, tool calling, RAG, embeddings, diffusion, LoRA, solutions, or PluginLoader behavior is claimed complete without matching runtime evidence or `N/A` proof. |
| Errors | Unsupported native features no-op or throw generic `Error` instead of typed SDK exceptions. |
| Logging | Logs can forward credentials, tokens, user data, or unredacted metadata. |
| Backends | LlamaCPP/ONNX expose provider internals or omit required registration parity. |
| Packaging | `@runanywhere/proto-ts` root starts star-exporting generated files, or RN gets a separate generated proto package. |
| Docs | Docs/examples mention deleted aliases such as `RunAnywhere.Audio`, `chat`, `isModelLoaded`, `transcribeFile`, `deleteModel`, `cancelDownload`, `continueWithToolResult`, `extractEntities`, `classify`, or `describeImage`. |
| Evidence | Smoke validation is reported as full E2E `PASS`. |

## Proto-TS Review Rule

Approve the shared package organization only when:

- Generated TypeScript protos live in `sdk/shared/proto-ts`.
- Consumers import message modules through subpaths, for example `@runanywhere/proto-ts/model_types`.
- The root `src/index.ts` stays intentionally empty unless generation changes remove duplicate helper-name collisions.
- `exports` includes `./*`, `./streams/*`, and package metadata.
- RN code does not create local duplicate aliases for generated enums/messages.
- Release checks build `@runanywhere/proto-ts` before RN package checks.

## High-Risk Files

- `sdk/runanywhere-react-native/packages/core/src/index.ts`
- `sdk/runanywhere-react-native/packages/core/src/internal.ts`
- `sdk/runanywhere-react-native/packages/core/src/Public/RunAnywhere.ts`
- `sdk/runanywhere-react-native/packages/core/src/Public/Extensions/**`
- `sdk/runanywhere-react-native/packages/core/src/Public/Events/**`
- `sdk/runanywhere-react-native/packages/core/src/Foundation/**`
- `sdk/runanywhere-react-native/packages/core/src/Features/**`
- `sdk/runanywhere-react-native/packages/core/src/Adapters/**`
- `sdk/runanywhere-react-native/packages/core/src/Internal/**`
- `sdk/runanywhere-react-native/packages/core/src/native/**`
- `sdk/runanywhere-react-native/packages/core/src/services/**`
- `sdk/runanywhere-react-native/packages/core/src/specs/**`
- `sdk/runanywhere-react-native/packages/core/cpp/**`
- `sdk/runanywhere-react-native/packages/core/ios/**`
- `sdk/runanywhere-react-native/packages/core/android/**`
- `sdk/runanywhere-react-native/packages/llamacpp/**`
- `sdk/runanywhere-react-native/packages/onnx/**`
- `sdk/runanywhere-react-native/scripts/package-sdk.sh`
- `sdk/shared/proto-ts/package.json`
- `sdk/shared/proto-ts/src/index.ts`
- `idl/codegen/generate_ts.sh`
- `idl/codegen/generate_rn_streams.sh`
- `examples/react-native/RunAnywhereAI/**`

## Modality Review Matrix

| Modality | Reviewer Must Verify |
| --- | --- |
| LLM | Generated request/result types, lifecycle load, stream events, cancellation, non-empty real output. |
| Structured output | Schema request/result types, stream event semantics, parse/extract behavior, invalid-schema errors. |
| Tool calling | Native/proto parse/format/validate/run-loop ownership; JS only executes registered callbacks; deterministic runtime proof on both platforms. |
| STT | Generated audio request, loaded model guard, partial/final transcript, fixed phrase evidence. |
| TTS | Generated synthesis request/result, loaded voice guard, stop/cancel, playback ownership. |
| VAD | Generated process request/result, lifecycle service use, speech/silence transitions, stats. |
| VoiceAgent | Shared STT/LLM/TTS/VAD components, component states, process turn, stream/cancel/cleanup. |
| VLM | Generated image/request/result, loaded model guard, stream event mapping, cancel. |
| RAG | Native/proto create/ingest/query/clear/stats ownership, no JS semantic duplication. |
| Embeddings/search | Source-backed `N/A` or real embed/query result count and dimensions. |
| Diffusion | Source-backed `N/A` or real image generation evidence. |
| LoRA/adapters | Runtime apply/remove/list/state, compatibility, catalog, import/download completion. |
| Solutions | Config bytes/typed config/YAML paths, handle lifecycle, feed/close/cancel/stop/destroy. |
| PluginLoader | API version, load/unload/list/registered names, typed unavailable behavior. |
| Hardware/profile | Generated profile/accelerator types and no contradictory fallback business logic. |
| Download/storage/lifecycle | UI download, progress, load/current/unload/delete/retry/resume/cancel where exposed. |
| Events/logging/telemetry | Proto payloads, subscription lifecycle, redaction, severity/destination mapping. |
| Permissions/media | Mic/camera/file allowed and denied paths where app surfaces them. |

## Required Static Evidence

```bash
yarn workspace @runanywhere/proto-ts build
yarn workspace @runanywhere/core nitrogen
yarn workspace @runanywhere/core typecheck
./node_modules/.bin/tsc -b sdk/runanywhere-react-native/packages/core
yarn workspace @runanywhere/llamacpp typecheck
yarn workspace @runanywhere/onnx typecheck
yarn workspace runanywhere-ai-example typecheck
(cd examples/react-native/RunAnywhereAI && yarn typecheck)
(cd sdk/runanywhere-react-native && node_modules/.bin/eslint "packages/core/src/**/*.ts")
(cd examples/react-native/RunAnywhereAI && yarn lint)
git diff --check -- sdk/runanywhere-react-native examples/react-native/RunAnywhereAI 'gaps/gaps/inconsistencies/react-native.md' 'gaps/gaps/PR review/react-native.md'
```

Run Nitro generation whenever `packages/core/src/specs/**`, `packages/llamacpp/src/specs/**`, or `packages/onnx/src/specs/**` changes. Review generated files for expected method additions/removals only.

## Required Native And Runtime Evidence

- Android core native build passes.
- Android example debug APK builds.
- iOS Pods are refreshed after podspec/source changes.
- iOS simulator build passes when iOS source, podspecs, or generated Nitro iOS files change.
- Android and iOS start from fresh uninstall/install.
- Continuous logs start before launch.
- Launch screen has no crash, redbox, missing-symbol error, compatibility dialog, or stale build warning.
- Every exposed modality follows download through UI, load into memory, real inference, screenshots, and logs.
- `N/A`, `BLOCKED`, `LIMITED`, and `FAIL` statuses include evidence and root cause.

## Full E2E Acceptance Bar

Do not approve final RN alignment as `PASS` until both Android and iOS have:

- Current-source build/install/launch from a clean target.
- Continuous logs reviewed for native crashes, bridge exceptions, JS redboxes, proto encode/decode errors, missing symbols, model failures, and silent no-op behavior.
- Model download, model load, and real inference evidence for every exposed modality.
- Fixed modality-matrix inputs for LLM, STT, TTS, VAD, VoiceAgent, VLM, RAG, tool calling, structured output, embeddings/search, diffusion, LoRA/adapters, hardware/profile, download/storage, lifecycle, events, and permissions where exposed.
- Screenshots for launch, download start/progress/completion, loaded state, inference input, and inference output.
- Report artifacts: `actions.jsonl`, `command_summary.tsv`, `modality_table.tsv`, screenshot paths, log paths, model IDs/categories/frameworks, status, and failures.

Build/install/launch without real model download/load/inference is `SMOKE_PASS`, never final `PASS`.

## Expected Agent Breakdown

- Public API agent: root exports, `Public/**`, Swift extension naming, `internal.ts`, stale alias scans.
- Foundation agent: initialization, state, secure storage, device identity, network config, logging, errors, unused barrel deletion.
- Bridge agent: central RN proto ABI helper, Nitro specs, generated output, init/auth/device/registry/lifecycle proto shapes.
- Modality agent: LLM, structured output, tool calling, STT, TTS, VAD, VLM, VoiceAgent, RAG, embeddings, diffusion, LoRA, solutions, PluginLoader.
- Backend agent: LlamaCPP/ONNX public surface, registration parity, package metadata, native binary staging.
- Proto package agent: `@runanywhere/proto-ts` build, exports, generated stream wrappers, drift checks.
- Example agent: RN example import migration, model selection, real modality UI flows, evidence capture.
- Verification agent: static checks, native builds, install/launch/log capture, all-modality runtime matrix.

## Reviewer Disposition

Approve only when a PR moves RN closer to Swift/C++/proto truth, deletes stale compatibility surface, keeps generated types in `@runanywhere/proto-ts`, and includes evidence proportional to the changed behavior. Request changes when a PR preserves stale RN aliases, invents local domain types, expands JS-owned SDK business logic, changes adjacent platform lanes, or reports smoke validation as full end-to-end success.
