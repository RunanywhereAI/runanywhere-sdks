# Flutter SDK PR Review — Current Plan Snapshot

> Updated: 2026-05-13
> Branch: `feat/v2-architecture`
> Audit point: HEAD `6bafade0d`; Flutter implementation commit `894f821a1`.
> State: implementation pass landed. Treat this as pending runtime validation, not a final merge verdict.
> Scope: Flutter SDK and Flutter docs only.

## Review verdict

Flutter is now much closer to the Swift-shaped SDK: a thin Dart API over generated proto types and C++ commons ABIs, with stale compatibility shims and duplicate hand-written mirrors removed from the active surface. This review is current-only for HEAD `6bafade0d`.

The remaining risk is no longer the public API rewrite. The code now uses the Swift-shaped `RunAnywhere` static namespace, generated-proto request/result surfaces, C++ tool-value JSON conversion, `NativeCallable.listener` event callbacks, and download-to-registry refresh. The PR should still be described as pending validation until Android and iOS runtime lanes prove download, load, inference, events, and logs end to end.

## HEAD-vs-Swift diff

| Area | HEAD `6bafade0d` Flutter state | Swift comparison | Review action |
|---|---|---|---|
| Aligned public shape | `RunAnywhere` is the static namespace; generated-proto LLM request/results, structured output, tool values, RAG helpers, artifact-path helpers, event subscriptions, storage/model APIs, logging, and error behavior were moved toward the Swift contract. | Matches the intended Swift direction where the user-facing SDK contract is shared. | Keep reviewing new Flutter API additions against Swift public extensions before declaring parity complete. |
| Misaligned runtime proof | Flutter still lacks real Android + iOS evidence for fresh install, continuous logs, model download, model load, real inference, events, and screenshot/log review. | Swift's API shape can be used as the design source, but Flutter's isolate/event path needs its own runtime proof. | Keep validation `PENDING`; build/install/launch evidence is only smoke evidence. |
| Deletion candidates | Deleted symbols should stay gone: old singleton access, stale voice-agent wrapper, stale download adapter, unused FFI typedef aliases, dead barrels, and current-doc rows for already-closed bugs. | Swift simplification favored deletion over compatibility layers; Flutter should follow that posture. | Do not re-add deprecated wrappers unless a concrete consumer break requires a deliberate migration path. |
| Generated-code status | Dart generated output now keeps the v1 runtime proto tree only: `router.pb.dart`/`router.pbenum.dart` are present, descriptor/server/gRPC stubs are stripped, and `runanywhere_protos.dart` exports only generated runtime proto files. | Swift still carries `RAConvenience.swift` for string Codable compatibility/default factories, but Flutter does not need that extra generated companion at HEAD. | Keep IDL drift check green after schema changes; do not hand-write mirrors for generated messages. |
| Backend-package drift | `runanywhere`, `runanywhere_llamacpp`, `runanywhere_onnx`, and `runanywhere_genie` are all versioned `0.19.13`; backend packages depend on `runanywhere: ^0.19.0`. `runanywhere_genie` remains skipped/deferred for this lane. | Swift does not have the same pub package split, so version/dependency drift is Flutter-specific. | Watch backend package constraints and native bundle coverage; do not open active gaps for deferred Genie unless policy changes. |
| Example-app noise | The example app now uses local path dependencies and imports the active backends, but it still contains validation-looking UI/log strings and Genie registration paths that can be mistaken for full proof. Its `dependency_overrides` omit `runanywhere_llamacpp` while dependencies include it by path. | Swift example churn is not proof for Flutter; Flutter example behavior must be validated on its own lanes. | Treat example-app output as evidence only when backed by the repo validation workflow logs/screenshots. |
| Validation status | Latest recorded Flutter evidence is smoke-only: `test_workflows/logs/20260513T114452-flutter-smoke`. | Swift parity does not convert smoke evidence into Flutter runtime success. | Keep Android and iOS `PENDING` until real full E2E evidence exists. |

## Required implementation checks

| Area | Expected outcome | Review focus |
|---|---|---|
| Swift parity | Public Flutter names, lifecycle semantics, storage/model APIs, structured output helpers, event subscriptions, logging, and error behavior match Swift where the shared SDK contract is visible. | Implementation landed; review the new `RunAnywhere` flat methods and capability helpers against Swift public extensions. |
| Aggressive deletion | Dead bridge slices, unused error wrappers, duplicate type mirrors, stale barrels, and already-closed workaround rows are removed from active code/docs. | Removed-symbol sweeps should stay clean outside generated/historical references. |
| Commons event publish | Flutter's isolate model is respected by the C++ event publisher. | Dart callback registration now uses `NativeCallable.listener`; device logs must prove commons event fan-out no longer aborts during model load. |
| Registry refresh | Download completion updates the in-memory registry. | Implementation landed; freshly downloaded models must appear without app restart and load immediately. |
| Docs | Gap docs list current open items only. | No stale closed-history tables, no closed rows, no platform-specific language from other SDK lanes. |

## Current open risks

| ID | Risk | Why it matters | Required evidence before close |
|---|---|---|---|
| FLT-RUNTIME-001 | Final Flutter runtime E2E is pending. | Build/analyze is not proof of runtime success. | Fresh install, logs, download, load, real inference, screenshots/log review for Flutter Android and iOS. |
| FLT-COMMONS-EVENT-001 | Commons event publishing previously crashed Dart when emitted from the wrong isolate/thread. | The Dart callback path now uses `NativeCallable.listener`, but this needs real event traffic proof. | Android + iOS model load logs with event publication and no Dart VM abort. |
| FLT-IOS-TTS-001 | iOS TTS load/speak needs re-validation after event-publish changes. | Previous Dart-side isolate wrapping was reverted; the durable fix belongs at the event boundary. | iOS System TTS and Piper download, load, synthesize/speak, logs reviewed. |
| FLT-REGISTRY-001 | Download success registry refresh is implemented but unproven on devices. | The app should not require restart before newly downloaded models are visible. | Downloaded model appears in the registry immediately on both Flutter lanes. |
| FLT-IOS-KEYCHAIN-001 | Residual iOS `-34018` warnings may still appear. | Low severity if fallback is graceful, but should not hide auth/device-registration failure. | Simulator logs, and real-device logs if available. |

## Review guidance

- Prefer removing stale Flutter APIs over adding deprecated wrappers.
- Treat generated proto types and C++ ABI wrappers as the canonical data path.
- Keep deferred backends out of active Flutter bug lists.
- Keep closed historical findings out of the live PR review except when they explain a current open risk.
- Report validation as `PENDING` until both Flutter lanes have real download, load, and inference evidence.

## Suggested verification

Run the light checks while code is in progress:

```bash
cd sdk/runanywhere-flutter
flutter analyze packages/runanywhere
flutter analyze packages/runanywhere_llamacpp
flutter analyze packages/runanywhere_onnx
```

Then run the full Flutter validation lanes through the repo validation workflow after implementation is ready. The final report should distinguish smoke/build success from full runtime `PASS`.

Latest smoke evidence: `test_workflows/logs/20260513T114452-flutter-smoke`
contains clean Android and iOS build/install/launch reports and screenshots.
It is intentionally recorded as `SMOKE_PASS` only.

Latest static evidence from this cleanup pass:
`flutter analyze packages/runanywhere`,
`flutter analyze packages/runanywhere_llamacpp packages/runanywhere_onnx`,
`flutter analyze` in `examples/flutter/RunAnywhereAI`,
`flutter test` in `examples/flutter/RunAnywhereAI`, and scoped
`git diff --check` all pass. Full Android/iOS runtime E2E is still required.
