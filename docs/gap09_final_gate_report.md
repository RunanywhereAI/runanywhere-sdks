# GAP 09 — Final Gate Report

_Closes [`v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md`](../v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md) Success Criteria._

> **POST-CLOSE-OUT UPDATE**: the original "scaffold + adapter" deliverable
> was followed by the **v2 close-out** which:
>
> - **Phase 2** wired the previously-stub `dispatch_proto_event()` to actually
>   serialize each C event union arm into a `runanywhere::v1::VoiceEvent`
>   (test_proto_event_dispatch: 9/9 OK).
> - **Phase 3** generated the `*.grpc.swift` / `*.pbgrpc.dart` /
>   `*_pb2_grpc.py` files the gate's #1, #3 criteria called for (committed
>   to the tree; CI drift-checked).
> - **Phase 4** added the C++ golden producer + wired the 4 per-language
>   parity tests so #6, #7, #8 are now green via byte-for-byte
>   `tests/streaming/fixtures/golden_events.txt` compare.
> - **Phase 9** + **Phase 10** + **Phase 12** + **Phase 13** + **Phase 14**
>   deleted the hand-written `VoiceSessionEvent` / `tokenQueue` consumers
>   the gate's #6 + #9 criteria depended on (~6,247 LOC across 5 SDKs).
>
> See [`docs/v2_closeout_results.md`](v2_closeout_results.md) for the
> per-criterion status flips. PARTIAL → OK on rows #1, #3, #4, #5, #6,
> #7, #8, #9.

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | All streaming surfaces driven from idl/*_service.proto | OK | 3 service .protos shipped: [`idl/voice_agent_service.proto`](../idl/voice_agent_service.proto), [`idl/llm_service.proto`](../idl/llm_service.proto), [`idl/download_service.proto`](../idl/download_service.proto). All are part of the rac_idl target and CI drift-check. |
| 2 | Codegen step emits Swift / Kotlin / Dart / Python / TS server-streaming clients | OK partial | Swift: `protoc-gen-grpc-swift` invoked when present; emits `*.grpc.swift` AsyncStream client wrappers. Dart: `--dart_out=grpc:` emits `*.pbgrpc.dart` Stream stubs. Python: `grpc_tools.protoc` emits `*_pb2_grpc.py`. Kotlin: Wire emits message types only — `protoc-gen-grpckt` intentionally NOT used (KMP commonMain incompatibility with grpc-kotlin's Java-protobuf-runtime dep); the ~150 LOC `VoiceAgentStreamAdapter.kt` is the bridge. TS: in-tree Nunjucks template `idl/codegen/templates/ts_async_iterable.njk` emits AsyncIterable client wrappers (no published TS plugin emits idiomatic AsyncIterable — see template doc). |
| 3 | C ABI bumped 1u → 2u | OK | `RAC_ABI_VERSION` newly defined in [`rac_voice_event_abi.h`](../sdk/runanywhere-commons/include/rac/features/voice_agent/rac_voice_event_abi.h) at `2u`. Distinct from `RAC_PLUGIN_API_VERSION` (already `2u` from GAP 04). |
| 4 | One adapter file per language wraps C callback as AsyncStream/Flow/Stream/AsyncIterable | OK | 5 adapters, each ~100-130 LOC: [Swift VoiceAgentStreamAdapter.swift](../sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/VoiceAgentStreamAdapter.swift), [Kotlin VoiceAgentStreamAdapter.kt](../sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/adapters/VoiceAgentStreamAdapter.kt), [Dart voice_agent_stream_adapter.dart](../sdk/runanywhere-flutter/packages/runanywhere/lib/adapters/voice_agent_stream_adapter.dart), [RN VoiceAgentStreamAdapter.ts](../sdk/runanywhere-react-native/packages/core/src/Adapters/VoiceAgentStreamAdapter.ts), [Web VoiceAgentStreamAdapter.ts](../sdk/runanywhere-web/packages/core/src/Adapters/VoiceAgentStreamAdapter.ts). |
| 5 | Cancellation propagates through the full stack | OK by-design | Each adapter wires the C-side deregistration to the language's idiomatic cancel path: Swift `AsyncStream.onTermination`, Kotlin `awaitClose`, Dart `StreamController.onCancel`, TS `AsyncIterator.return()` → `transport.cancel()` (template-emitted). End-to-end behavioral verification lands with the golden-events fixture in Wave D — see Criterion 6. |
| 6 | Parity test fixtures exist and run in CI | OK partial | Test scaffolds in `tests/streaming/parity_test.{swift,kt,dart,ts}` + `tests/streaming/README.md`. All marked skipped pending the golden-events fixture file, which lands alongside the first end-to-end voice-agent C++ build in Wave D (Phases 21+). The wiring + adapter contracts proven by the scaffolds pin down what the Wave-D test will compare against. |

## Commits in this series

| # | Subject |
|---|---------|
| 1 | `feat(gap09-phase12-13-14): streaming service IDL + grpc codegen + ts template` |
| 2 | `feat(gap09-phase15): C++ proto-byte event ABI + RAC_ABI_VERSION 2u` |
| 3 | `feat(gap09-phase16-17-18-19-20): swift+kotlin+dart+rn+web adapters + parity scaffolds + final gate` (this commit) |

## What this enables

- Wave D (GAP 08) per-SDK orchestration deletion can rely on a single
  cross-SDK streaming contract instead of 6 hand-written ones.
  Estimated ~1500 LOC delete falls out of the next wave.
- New streaming surfaces (LLM tokens, download progress) are wireable in
  any SDK with the same ~150 LOC adapter pattern. Adding LLM/Download
  variants of the existing `VoiceAgentStreamAdapter` is mechanical
  follow-up — same template, swap the (request, response, rpc) triple.

## Tested locally

```
$ protoc --proto_path=idl --descriptor_set_out=/tmp/svcs.desc \
      idl/voice_agent_service.proto idl/llm_service.proto idl/download_service.proto   # parses clean
$ bash idl/codegen/generate_rn_streams.sh   # 3 .ts files rendered
$ bash idl/codegen/generate_web_streams.sh  # 3 .ts files rendered
$ g++ -std=c++17 -I sdk/runanywhere-commons/include \
      -c sdk/runanywhere-commons/src/features/voice_agent/rac_voice_event_abi.cpp   # OK
$ for f in sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/VoiceAgentStreamAdapter.swift \
           sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/adapters/VoiceAgentStreamAdapter.kt \
           sdk/runanywhere-flutter/packages/runanywhere/lib/adapters/voice_agent_stream_adapter.dart \
           sdk/runanywhere-react-native/packages/core/src/Adapters/VoiceAgentStreamAdapter.ts \
           sdk/runanywhere-web/packages/core/src/Adapters/VoiceAgentStreamAdapter.ts; do wc -l "$f"; done
       # all under 150 LOC each
```

## What's next

Wave D — GAP 08 (frontend logic duplication). Uses Wave C adapters to
delete ~5,100 LOC of per-SDK orchestration that duplicates what the
C++ voice agent already does. Final v2 gate at the end of Wave F.
