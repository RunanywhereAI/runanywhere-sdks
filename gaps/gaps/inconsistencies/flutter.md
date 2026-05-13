# Flutter SDK — Current Execution Plan & Open Items

> Updated: 2026-05-13
> Branch: `feat/v2-architecture`
> Audit point: HEAD `6bafade0d`; Flutter implementation commit `894f821a1`.
> State: Flutter implementation pass landed; runtime E2E remains pending.
> Scope: Flutter SDK gaps only. `runanywhere_genie` remains deferred unless the deferred-backends policy changes.

## Current direction

Flutter should converge on the Swift SDK shape as the source of truth, with exact API/bridge parity where it is observable by users or required by the shared C++ ABI. This file is current-only: active rows must describe gaps still open at HEAD `6bafade0d`, not previously closed investigation history.

Commons event publishing is in scope for Flutter because it blocks safe Dart isolate usage. Flutter's callback registration now uses `NativeCallable.listener`; heavy lifecycle `Isolate.run` wraps should still wait until Android and iOS logs prove model-load event fan-out is clean.

## Implementation landed in this pass

| Area | What changed | Remaining proof |
|---|---|---|
| Static entry point | The legacy singleton entry point was removed in favor of Swift-shaped `RunAnywhere` static access. The Flutter example app was migrated to the new entry point. | Full example-app runtime validation on Android and iOS. |
| Deletion-forward cleanup | Stale wrappers/barrels and dead bridge slices were removed instead of preserved as compatibility shims. | Old-symbol sweeps should stay clean after follow-up edits. |
| Commons event delivery | Flutter event callbacks now use `NativeCallable.listener`, so commons event fan-out is isolate-safe from Dart's side. | Model-load/download/registry events must be observed in real Android + iOS logs. |
| Registry refresh | Download completion refreshes the model registry, resolves local model paths, and publishes a generated model download-completed SDK event. | Fresh download should appear in the picker without app restart. |
| Swift API parity | Added generated-proto LLM request methods, structured-output helpers, typed `ToolValue` helpers backed by C++ JSON ABIs, RAG Swift-shaped helpers, and artifact path accessors for tokenizer/config/vocabulary/merges/labels. | Cross-check Swift public extension list after E2E. |
| Generated proto status | Flutter now keeps only runtime proto bindings in `lib/generated`: 29 `*.pb.dart` and 29 `*.pbenum.dart`; `*.pbjson.dart`, `*.pbserver.dart`, and `*.pbgrpc.dart` are stripped by Dart codegen. No Dart `RAConvenience` clone is carried because the current Flutter surface can use generated types directly. | Keep IDL drift check green after any schema/codegen edits. |

## Open implementation / validation items

| ID | Priority | Area | Current plan | Validation needed |
|---|---|---|---|---|
| FLT-RUNTIME-001 | HIGH | Runtime E2E | Run the full Flutter Android and iOS validation lanes after this implementation pass. | Fresh install, continuous logs, model download, model load, real inference, screenshots/log review. |
| FLT-IOS-TTS-001 | HIGH | iOS TTS load | Re-validate iOS System TTS and Piper load after the event-publish fix. The previous Dart-side isolate wrapper was reverted because it exposed the cross-isolate callback bug; the next fix belongs at the event-publish boundary, not in an ad hoc Flutter workaround. | Full Flutter iOS lane: download, registry refresh, load, synthesize/speak, logs reviewed. |
| FLT-IOS-KEYCHAIN-001 | LOW | iOS secure storage | Investigate residual `-34018` entitlement/keychain warnings. Keep severity low while SDK fallback remains graceful. | Simulator and real-device logs, if available; confirm no auth/device-registration failure is hidden behind fallback. |

## Open architectural drift

| Concern | Target | Current stance |
|---|---|---|
| Entry point naming | Swift uses `RunAnywhere`; Flutter now uses `RunAnywhere`. | CLOSED in this pass; do not reintroduce the legacy singleton entry point. |
| Capability shape | Swift public extensions are the parity source. | Remove Flutter-only aliases and convenience surfaces that do not have a Swift-equivalent purpose. |
| Event publishing | Swift can receive commons events without Dart isolate restrictions. | Flutter now registers event callbacks with `NativeCallable.listener`; keep runtime validation open until model-load events prove clean on device. |
| Deferred backends | Deferred backends must not define active Flutter gaps. | Keep `runanywhere_genie` skipped/deferred unless the policy changes. |
| Example-app waits/workarounds | Example app should exercise the SDK, not compensate for SDK state bugs. | Remove waits after SDK registry refresh and lifecycle events are validated. |

## Removed from active tracking

Closed history is intentionally absent from this document. Already-resolved transport, proto flood, plugin-routing, native packaging, and reverted workaround findings belong in logs or git history, not in the current open-items tracker.

## Pending validation report shape

When the Flutter implementation pass is ready, report results as:

| Lane | Status | Evidence required |
|---|---|---|
| Flutter Android | PENDING | Fresh install, continuous logs, model download, model load, real inference, screenshots/log review. |
| Flutter iOS | PENDING | Fresh install, continuous logs, model download, model load, real inference, screenshots/log review. |

Do not mark this document as success-only until validation has completed on both lanes.

Latest smoke evidence: `test_workflows/logs/20260513T114452-flutter-smoke`
has current-source Android and iOS build/install/launch screenshots and clean
launch-log scans. Both lanes remain `SMOKE_PASS`, not full `PASS`, because the
model download/load/inference UI workflow has not been completed.

Latest static evidence from this cleanup pass:
`flutter analyze packages/runanywhere`,
`flutter analyze packages/runanywhere_llamacpp packages/runanywhere_onnx`,
`flutter analyze` in `examples/flutter/RunAnywhereAI`,
`flutter test` in `examples/flutter/RunAnywhereAI`, and scoped
`git diff --check` all pass. Runtime E2E remains pending.
