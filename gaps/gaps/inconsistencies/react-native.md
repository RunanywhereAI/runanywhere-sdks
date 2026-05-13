# React Native SDK - Swift Alignment Gap Status

Updated: 2026-05-13
Ownership: this document and `gaps/gaps/PR review/react-native.md` only.
Audit scope: `sdk/runanywhere-react-native/`, `examples/react-native/RunAnywhereAI/`, `sdk/runanywhere-swift/`, `sdk/shared/proto-ts/`, `idl/`, and `test_workflows/instructions/`.

React Native must align to Swift for public API shape, folder organization, bridge slices, two-phase initialization, native ownership, packaging, iOS deployment expectations, and validation. C++ commons plus `idl/*.proto` remain the source of truth for domain types, lifecycle contracts, request/result payloads, events, model state, and SDK business logic.

This is a current-plan/status document. It records what was observed in the tree during this audit, but does not claim runtime completion unless evidence is cited in the validation section. Do not edit Kotlin, Flutter, Swift, Web, commons, or RN code from this lane. Do not revert or overwrite other workers' changes.

## Current Audit Snapshot

- Swift source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md` says Swift is the canonical cross-SDK reference; `RunAnywhere` is a single public namespace with `Public/Extensions/**`, generated `RA*` proto types, `CppBridge`, and `NativeProtoABI`.
- Swift public extensions currently cover hardware, logging, plugin loader, LLM generation/stream/cancel, structured output, tool calling, LoRA, model registry/lifecycle/storage/download, STT, TTS, VAD, VLM, VoiceAgent, events, and solutions.
- RN root package currently exports a small `@runanywhere/core` facade: `RunAnywhere`, `SDKEnvironment`, `SDKInitOptions`, SDK errors, `EventBus`, plugin-loader types, and `ToolExecutor`.
- RN has an intentional `@runanywhere/core/internal` subpath for Nitro/global init, native module access, logging, proto byte helpers, and audio helpers used by sibling backend packages and examples.
- RN has generated proto consumption through `@runanywhere/proto-ts/*`; `sdk/shared/proto-ts/src/index.ts` intentionally exports nothing because generated files define colliding helpers such as `DeepPartial`, `Exact`, and `protobufPackage`.
- `@runanywhere/proto-ts` is a workspace package with subpath exports for `./*` and `./streams/*`. It should remain the single TypeScript proto package consumed by RN and Web, not be split into RN-local generated packages.
- RN still has TypeScript folders that need keep/delete/internal-location review: `Foundation/**`, `Features/**`, `Adapters/**`, `Internal/**`, `native/**`, `services/**`, `specs/**`, and generated `lib/**` output.
- RN native specs still expose some non-proto or ad hoc bridge shapes, including `initialize(configJson: string)`, `completeServicesInitialization(): Promise<boolean>`, auth/device string and boolean getters, and PluginLoader JSON string returns.
- RN native specs also expose many proto-byte methods for registry, download, storage, lifecycle, events, LLM, STT, TTS, VAD, VLM, RAG, structured output, LoRA, hardware, and solutions.
- RN streaming specs document an ABI limitation: LLM and VoiceAgent native callback slots are one-per-handle, so multiple concurrent subscribers on the same handle replace each other. That must be accepted as a documented native ABI limitation or fixed below RN in commons.
- RN public extension code still performs some facade/orchestration work in TypeScript, especially RAG text ingestion metadata normalization, VAD chunk streaming, TTS playback wrapper behavior, VLM stream queueing/cancel glue, and VoiceAgent handle retrieval.
- Tool calling now has a native-backed `toolRunLoopProto` Nitro/C++ bridge that calls `rac_tool_calling_run_loop_proto`; TypeScript owns tool callback dispatch only. Runtime evidence is still required.
- RN package metadata still includes optional `react-native-blob-util`, `react-native-device-info`, and `react-native-fs` peer dependencies; verify whether each remains RN-native glue or stale SDK ownership.
- LlamaCPP and ONNX RN packages depend on `@runanywhere/proto-ts` and should stay thin runtime registration packages, not public provider-class SDKs.

## Proto-TS Organization And Publishing Decision

Decision: keep `@runanywhere/proto-ts` as the shared generated TypeScript proto package for React Native and Web, now housed at `sdk/shared/proto-ts`.

- Publish/import generated DTOs and enums through subpaths such as `@runanywhere/proto-ts/model_types`, `@runanywhere/proto-ts/llm_service`, and `@runanywhere/proto-ts/streams/llm_service_stream`.
- Keep the root `@runanywhere/proto-ts` export intentionally empty. Do not add star exports at the root because ts-proto emits repeated helper names in each generated file.
- Do not create a separate RN-only proto package. RN-specific code should live in `@runanywhere/core` or `@runanywhere/core/internal`; generated domain types belong in `@runanywhere/proto-ts`.
- Keep `@runanywhere/proto-ts` versioned and published before RN/Web SDK releases, with `dist` and subpath exports included in the npm artifact.
- If RN needs ergonomic helpers that Swift has in `RAConvenience.swift`, generate or place them as clearly named helper modules without changing canonical message/enum ownership.
- Add drift checks for `idl/codegen/generate_ts.sh`, `generate_rn_streams.sh`, package `exports`, and generated `dist` before release.

## Modality Gap Matrix

| Surface | Observed RN State | Gap To Close | Required Evidence |
| --- | --- | --- | --- |
| LLM chat | RN exposes proto-byte `generate`, stream, and cancel paths. | Prove lifecycle load, stream cancellation, final result, and callback-slot behavior on Android and iOS. | Download/load chat model; run fixed LLM prompt; screenshots and logs. |
| Structured output | RN exposes schema generation, stream parsing, extraction, and prompt preparation wrappers. | Align stream event result type with Swift and prove invalid-schema/parse errors map to typed SDK errors. | Fixed schema run; parseable JSON; invalid schema path. |
| Tool calling | RN uses generated proto types and native parse/format/validate helpers. The multi-iteration run loop now routes through native/proto `toolRunLoopProto`; JS owns the callback trampoline for registered tools. | Prove timeout/error mapping, deterministic executor dispatch, and follow-up output on Android and iOS. | Deterministic tool call with arguments, result, follow-up, and logs proving proto/native loop. |
| STT | RN exposes `transcribe` and `transcribeStream` over generated STT protos. | Prove model-loaded guard, partial/final event semantics, audio encoding, and typed error paths against Swift. | Download/load STT model; fixed audio phrase; partial/final transcript evidence. |
| TTS | RN exposes `synthesize`, `synthesizeStream`, `speak`, stop/cancel, and JS playback wrapper. | Decide whether playback wrapper is RN-native glue or example code; prove voice lifecycle and output duration/path parity. | Download/load TTS voice; synthesize fixed text; audio output/log evidence. |
| VAD | RN exposes `detectVoiceActivity`, reset, and chunked JS `streamVAD`. | Align lifecycle service usage and streaming semantics with Swift; verify silence/speech transitions and statistics. | Speech-then-silence fixture; start/end confidence/log evidence. |
| VoiceAgent | RN exposes init, init-with-loaded-models, component states, process turn, stream, and cleanup. | Prove shared STT/LLM/TTS/VAD handles, component-state shapes, stream cancellation, and typed not-ready errors. | Full VAD -> STT -> LLM -> TTS turn with component-state evidence. |
| VLM | RN exposes `processImage`, stream, and cancel over generated VLM protos. | Prove image payload formats, loaded-model guard, stream event mapping, and cancel behavior against Swift. | Deterministic image fixture; fixed image question; visible answer/log evidence. |
| RAG | RN exposes create/add/query/clear/stats paths with generated protos. | Remove or justify JS metadata/text normalization; align create/destroy/ingest/query names and ownership with Swift/commons. | Ingest fixed text; query fixed question; retrieval and answer evidence. |
| Embeddings/search | No standalone RN public embeddings surface was confirmed in the quick audit; RAG likely depends on embeddings underneath. | Mark `N/A` only if source review confirms no example/API surface; otherwise expose or validate generated embeddings flow. | Source citation for `N/A`, or embed/query dimensions/result evidence. |
| Diffusion | Proto and Swift generated surfaces exist; no RN public diffusion extension was confirmed in the quick audit. | Decide whether RN exposes diffusion now, plans it later, or marks it `N/A` with source evidence. | Source citation for `N/A`, or download/load/generate image evidence. |
| LoRA/adapters | RN exposes `RunAnywhere.lora` runtime and catalog methods over generated protos. | Verify handle ownership, catalog persistence, compatibility checks, import/download completion, and Swift naming. | Compatible adapter load/list/remove or documented `N/A/BLOCKED` with typed error. |
| Solutions | RN exposes `RunAnywhere.solutions.run` with config bytes, typed config, or YAML. | Prove handle lifecycle, feed/close/cancel/stop/destroy, and proto/YAML error conversion. | Run or typed unavailable evidence for one solution pipeline. |
| PluginLoader | RN exposes native-backed API version, registered count/names, loaded list, load, and unload, but returns JSON strings from native. | Convert or document JSON return exception; prove load/unload/list or typed unavailable behavior on Android and iOS. | Plugin runtime checks or typed unavailable logs/screenshots. |
| Hardware/profile | RN exposes generated hardware profile and accelerator methods with fallbacks. | Confirm fallback code is platform glue only, not contradictory SDK business logic. | Profile/settings screenshot and native/proto log evidence. |
| Download/storage/lifecycle | RN exposes proto-byte download, storage, registry, import, load/unload/current/snapshot paths. | Prove all modality model flows use SDK-owned download, load, current state, unload/delete, retry/resume/cancel where exposed. | Per-modality download/load/inference evidence plus storage cleanup path. |
| Events/telemetry/logging | RN exposes SDK event proto subscribe/publish/poll and TypeScript logging configuration. | Verify event payloads, redaction, destinations, severity mapping, and no raw credential forwarding. | Event log excerpts and redaction review. |
| Permissions/media | RN has audio helpers and platform dependencies. | Validate mic/camera/file permission allowed and denied paths where screens expose them. | Permission screenshots/logs, or source-backed `N/A`. |

## Validation Matrix Requirements

Full RN acceptance requires Android and iOS lanes to follow `test_workflows/instructions/common/run_contract.md` and `modality_matrix.md`.

- Start from a clean install: record target identity, uninstall old app, clear logs, build current source, install, launch, capture launch screenshot.
- Capture continuous logs from before launch through each tested flow.
- For every exposed modality, perform model download through the UI, load the model into memory, run real inference on the target, capture screenshots for start/progress/completion/load/output, and review logs after each action group.
- Use fixed inputs from the modality matrix: LLM prompt, STT phrase, TTS text, VAD speech/silence, VoiceAgent spoken request, VLM image question, RAG ingest/query, deterministic tool call, structured-output JSON schema, embeddings query, diffusion prompt, adapter load where exposed, hardware profile, download/storage, lifecycle, events, and permission paths.
- Status values must be limited to `PASS`, `FAIL`, `BLOCKED`, `LIMITED`, `N/A`, and `SMOKE_PASS`.
- Build/install/launch evidence is only `SMOKE_PASS`. Do not roll it up as full `PASS`.
- `N/A` requires source or screenshot evidence that the app/API does not expose the feature.
- Each lane report must include `actions.jsonl`, `command_summary.tsv`, `modality_table.tsv`, screenshots, log paths, model IDs, model category, format/framework, inputs, outputs, status, and failure/root cause when applicable.
- Android RN validation must not run concurrently with another Android lane on the same target unless the run documents serial execution, unique Metro ports, or separate devices.

## Completed In Current Implementation Pass

- RN-DONE-001: Rehomed shared generated TypeScript protos from `sdk/runanywhere-proto-ts` to `sdk/shared/proto-ts`.
- RN-DONE-002: Kept `@runanywhere/proto-ts` as a workspace/publishable package with dist-only npm contents and subpath exports.
- RN-DONE-003: Updated RN and Web consumers to import/build against `sdk/shared/proto-ts`.
- RN-DONE-004: Removed RN package `prepare` side effects; package publication now uses explicit `prepublishOnly` checks.
- RN-DONE-005: Added native-backed tool-calling run-loop bridge through Nitro/C++ and `rac_tool_calling_run_loop_proto`.
- RN-DONE-006: Regenerated the RN Nitro spec for the new `toolRunLoopProto` ABI.
- RN-DONE-007: Added the RN example validation harness tab for structured output, deterministic tool calling, synthetic VAD, LoRA, and PluginLoader checks.
- RN-DONE-008: Updated RN/Web/proto package documentation and React Native validation workflow docs.
- RN-DONE-009: Re-ran static checks, package checks, Android native build, Android example build, and iOS simulator build.

## Remaining Implementation Checklist

### 1. Public Surface

- RN-1001: Diff `packages/core/src/index.ts` against Swift `Public/RunAnywhere.swift` and every Swift `Public/Extensions/**` file.
- RN-1002: Keep root exports limited to `RunAnywhere`, generated/proto config, SDK errors, `EventBus`, plugin types, and unavoidable RN callback types.
- RN-1003: Move `SDKInitOptions` out of `src/types/models.ts` or document it as an RN-only call-site type.
- RN-1004: Decide whether `Public/Configuration/SDKEnvironment.ts` is a real public wrapper or stale now that root exports proto `SDKEnvironment`.
- RN-1005: Verify SDK errors and `SDKException` naming/category mapping against Swift `RASDKError`/`SDKException`.
- RN-1006: Verify `EventBus` names, cancellation, subscription IDs, and event payloads against Swift.
- RN-1007: Verify plugin-loader type names and method names against Swift `PluginLoaderNamespace`.
- RN-1008: Keep `ToolExecutor` as the only expected RN-local public type if it is needed for JS function references.
- RN-1009: Scan for stale public aliases after every API change.
- RN-1010: Update README/example imports whenever root exports change.

### 2. Internal File And Barrel Cleanup

- RN-2001: Audit `Foundation/index.ts`, `Foundation/DependencyInjection/index.ts`, `Features/index.ts`, `services/index.ts`, and `services/Network/index.ts`; delete if they only preserve old import paths.
- RN-2002: Audit `Foundation/Security/**` and `DeviceIdentity.ts` for native-auth/device ownership duplication.
- RN-2003: Audit `Foundation/Logging/**` for redaction, destination, severity, and native forwarding parity.
- RN-2004: Audit `Features/VoiceSession/AudioCaptureManager.ts` and `AudioPlaybackManager.ts`; keep only RN media glue that Swift keeps platform-native.
- RN-2005: Audit `Adapters/LLMStreamAdapter.ts` and `VoiceAgentStreamAdapter.ts` against the documented one-callback-slot ABI limitation.
- RN-2006: Audit `Internal/AudioFileReader.ts` and `Internal/Audio/**` for example-only behavior.
- RN-2007: Remove stale generated `lib/**` artifacts from packaging if source-of-truth publishing does not require checked-in build output.
- RN-2008: Run typechecks after each deletion batch.

### 3. Initialization, Auth, Device, Network

- RN-3001: Replace or justify `native.initialize(configJson)` versus Swift's `rac_sdk_init_phase1_proto` path.
- RN-3002: Replace or justify `completeServicesInitialization(): boolean` versus generated Phase 2 result/state.
- RN-3003: Move JS initialization state ownership native-side or prove the JS mirror cannot drift.
- RN-3004: Convert auth/device string and boolean getters to generated proto request/result bytes when commons exposes them.
- RN-3005: Confirm device ID persistence is native-owned and not duplicated in JS storage.
- RN-3006: Confirm network config contains only RN call-site normalization and no endpoint routing table or SDK business logic.
- RN-3007: Verify telemetry/log upload ownership and retry behavior against Swift.

### 4. Native Bridge ABI

- RN-4001: Introduce a central RN C++ proto ABI helper equivalent in intent to Swift `NativeProtoABI`.
- RN-4002: Route lifecycle, registry, download, storage, events, hardware, STT, TTS, VAD, VLM, RAG, structured output, tool calling, LoRA, solutions, and PluginLoader error conversion through the central helper.
- RN-4003: Replace JSON string return values from native where generated proto bytes or typed Nitro objects are available.
- RN-4004: Ensure unsupported native paths throw typed `SDKException` equivalents.
- RN-4005: Regenerate Nitro after spec changes and review generated diffs only for expected changes.
- RN-4006: Rebuild Android and iOS after bridge changes.

### 5. Modalities And Business Logic Ownership

- RN-5001: Prove native/proto tool-calling run loop end to end on Android and iOS with deterministic tool execution, timeout, and typed error cases.
- RN-5002: Delete any remaining RN-local recursive ToolValue conversion once source review confirms commons/proto helpers cover every exposed value shape.
- RN-5003: Remove or justify JS RAG metadata/text normalization; native/proto should own ingestion/query semantics.
- RN-5004: Align LoRA runtime and catalog methods exactly to Swift names and generated request/result shapes.
- RN-5005: Prove STT/TTS/VAD/VLM/VoiceAgent loaded-model guards use lifecycle state rather than per-extension JS state.
- RN-5006: Prove LLM, structured-output, VLM, STT, TTS, VAD, and VoiceAgent stream cancellation and final-event semantics.
- RN-5007: Decide diffusion and embeddings/search exposure; document `N/A` with source evidence or implement/validate.
- RN-5008: Prove PluginLoader runtime load/unload/list or typed unavailable behavior on both platforms.
- RN-5009: Convert remaining generic `Error` throws in public extension paths to typed SDK exceptions.

### 6. Backend Packages And Publishing

- RN-6001: Keep `@runanywhere/llamacpp` and `@runanywhere/onnx` as thin registration/runtime facade packages.
- RN-6002: Keep provider classes and native plumbing out of public package roots.
- RN-6003: Verify ONNX exposes Sherpa-backed STT/TTS/VAD registration parity without local SDK business logic.
- RN-6004: Audit package `files`, podspec globs, Android CMake globs, and `scripts/package-sdk.sh` after bridge/file changes.
- RN-6005: Keep `@runanywhere/proto-ts` subpath imports as the only generated TS DTO source.

### 7. Example App Lane

- RN-7001: Treat the example app as a validation and migration lane, not backwards-compatibility protection.
- RN-7002: Remove example wrappers that hide canonical `RunAnywhere` public names once direct calls are clear.
- RN-7003: Audit model selection screens for generated proto enum names only.
- RN-7004: Audit Chat, STT, TTS, VAD, VoiceAgent, VLM, RAG, Settings, Storage, Hardware, and Plugin screens against Swift-shaped calls.
- RN-7005: Ensure example UI supports evidence capture for every exposed modality.

### 8. Verification

- RN-8001: `yarn workspace @runanywhere/proto-ts build`.
- RN-8002: `yarn workspace @runanywhere/core nitrogen` after spec changes.
- RN-8003: `yarn workspace @runanywhere/core typecheck`.
- RN-8004: `./node_modules/.bin/tsc -b sdk/runanywhere-react-native/packages/core`.
- RN-8005: `yarn workspace @runanywhere/llamacpp typecheck`.
- RN-8006: `yarn workspace @runanywhere/onnx typecheck`.
- RN-8007: RN example typecheck and lint.
- RN-8008: Core package-local eslint until workspace lint wiring is proven.
- RN-8009: Android core native build and Android example debug build. Current pass: `./gradlew :app:assembleDebug` passed.
- RN-8010: `pod install` and iOS simulator build when iOS source/podspec/globs change. Current pass: `xcodebuild -workspace ios/RunAnywhereAI.xcworkspace -scheme RunAnywhereAI ... build` passed on iPhone 17 Pro simulator.
- RN-8011: Scoped `git diff --check` for RN SDK, RN example, and these two gap docs.
- RN-8012: Full Android and iOS clean-install all-modality E2E matrix with screenshots, logs, and report files before final `PASS`.
