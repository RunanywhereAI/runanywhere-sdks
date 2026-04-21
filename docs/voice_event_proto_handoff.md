# Voice Event Proto — Handoff to GAP 09

_This document is the output of **GAP 01 Phase 6** and the entry point
for GAP 09 (voice event streaming migration). See
[`v2_gap_specs/GAP_01_IDL_AND_CODEGEN.md`](../v2_gap_specs/GAP_01_IDL_AND_CODEGEN.md)
for the umbrella spec._

## Current state (after GAP 01 Phase 6)

* **IDL schema.** `idl/voice_events.proto` defines the canonical
  `VoiceEvent` oneof — the single source of truth for every streaming
  event that the voice agent emits (`UserSaidEvent`,
  `AssistantTokenEvent`, `AudioFrameEvent`, `VADEvent`, …).

* **Language bindings, committed and drift-guarded.**
  | Language   | Path                                                                                                     | Generator                  |
  |------------|----------------------------------------------------------------------------------------------------------|----------------------------|
  | Swift      | `sdk/runanywhere-swift/Sources/RunAnywhere/Generated/voice_events.pb.swift`                              | swift-protobuf 1.27        |
  | Kotlin     | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/*` | Wire 4.9.9                 |
  | Dart       | `sdk/runanywhere-flutter/packages/runanywhere/lib/generated/voice_events.pb.dart`                        | protoc_plugin 21.1.2       |
  | TypeScript | `sdk/runanywhere-react-native/packages/core/src/generated/voice_events.ts`                               | ts-proto 1.181 (env=node)  |
  | TypeScript | `sdk/runanywhere-web/packages/core/src/generated/voice_events.ts`                                        | ts-proto 1.181 (env=browser)|
  | C++        | `sdk/runanywhere-commons/src/generated/proto/voice_events.pb.{h,cc}`                                     | protoc --cpp_out           |
  | Python     | `sdk/runanywhere-python/src/runanywhere/generated/voice_events_pb2.{py,pyi}`                             | protoc --python_out        |

  The CI drift check (`.github/workflows/idl-drift-check.yml`) re-runs every
  codegen on every PR and fails if `git diff --exit-code` shows any change,
  so these files cannot silently drift from `idl/voice_events.proto`.

* **Existing struct-based event path unchanged.**
  The live voice agent still uses `rac_voice_agent_event_t` declared in
  `sdk/runanywhere-commons/include/rac/features/voice_agent/rac_voice_agent.h`
  and its associated callbacks. No SDK has been cut over yet; every frontend
  continues to decode the struct variant via its existing `CppBridge+VoiceAgent`
  / `CppBridgeVoiceAgent.kt` / `dart_bridge_voice_agent.dart` plumbing.

## What GAP 09 must do

1. **Add a second emission path in the C++ voice agent.** Alongside the
   existing struct callback, serialize every event through
   `runanywhere::v1::VoiceEvent` and publish a
   `(const uint8_t* bytes, size_t len)` buffer via a new C ABI callback:

   ```c
   /* sdk/runanywhere-commons/include/rac/features/voice_agent/rac_voice_event_abi.h */
   typedef void (*rac_voice_event_proto_callback_fn)(
       void*          user_data,
       const uint8_t* bytes,
       size_t         len);

   rac_result_t rac_voice_agent_set_proto_callback(
       rac_voice_agent_handle          handle,
       rac_voice_event_proto_callback_fn callback,
       void*                            user_data);
   ```

   The implementation fills a `VoiceEvent` message (uses `rac_idl` from
   `idl/CMakeLists.txt`) and calls
   `message.SerializeToArray(out_buf, out_len)`.

2. **Add thin stream adapters in each frontend** that decode the byte
   buffer using the committed per-language `VoiceEvent` type:

   ```swift
   // sdk/runanywhere-swift/Sources/RunAnywhere/Features/VoiceAgent/
   // VoiceEventProtoDecoder.swift
   public enum VoiceEventProtoDecoder {
       public static func decode(_ data: Data) throws -> RAVoiceEvent {
           try RAVoiceEvent(serializedData: data)
       }
   }
   ```

   ```kotlin
   // sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/
   // features/voice_agent/VoiceEventProtoDecoder.kt
   object VoiceEventProtoDecoder {
       fun decode(bytes: ByteArray): ai.runanywhere.proto.v1.VoiceEvent =
           ai.runanywhere.proto.v1.VoiceEvent.ADAPTER.decode(bytes)
   }
   ```

   ```dart
   // sdk/runanywhere-flutter/packages/runanywhere/lib/features/voice_agent/
   // voice_event_proto_decoder.dart
   import 'package:runanywhere/generated/voice_events.pb.dart' as pb;
   class VoiceEventProtoDecoder {
     static pb.VoiceEvent decode(Uint8List bytes) =>
         pb.VoiceEvent.fromBuffer(bytes);
   }
   ```

   ```typescript
   // sdk/runanywhere-react-native/packages/core/src/features/voice/VoiceEventProtoDecoder.ts
   import * as proto from '../../generated/voice_events';
   export const VoiceEventProtoDecoder = {
     decode(bytes: Uint8Array): proto.VoiceEvent {
       return proto.VoiceEvent.decode(bytes);
     },
   };
   ```

3. **Migrate the existing 1,821 LOC of hand-written event plumbing**
   in `CppBridgeVoiceAgent.kt`, `CppBridge+VoiceAgent.swift`, and
   `dart_bridge_voice_agent.dart` to these adapters. Each
   `UserSaidEvent`, `AssistantTokenEvent`, etc. becomes a simple
   pattern-match on the generated `VoiceEvent.oneof_payload`. The
   struct callback path is deprecated but not removed — downstream
   consumers will have a release cycle to cut over.

4. **Bump `RAC_ABI_VERSION`** in
   `sdk/runanywhere-commons/include/rac/core/rac_version.h` when the
   new callback entry point ships (per the compatibility policy in
   `idl/README.md`).

## Constraints inherited from GAP 01

* Never remove an existing field number from `voice_events.proto`.
* Never repurpose a field number — always pick a fresh one.
* Every oneof arm added forces an `RAC_ABI_VERSION` bump.
* The C ABI carries the message as length-prefixed bytes; frontends
  copy the bytes out on callback entry.

## What is explicitly NOT in GAP 01 Phase 6

| Deferred to | Work                                                           |
|-------------|----------------------------------------------------------------|
| GAP 09      | New `rac_voice_event_abi.{h,cpp}` emitting proto bytes          |
| GAP 09      | Rewriting `CppBridge+VoiceAgent.swift` to consume proto bytes   |
| GAP 09      | Rewriting `CppBridgeVoiceAgent.kt` (1,821 LOC) to consume proto bytes |
| GAP 09      | Rewriting `dart_bridge_voice_agent.dart` to consume proto bytes |
| GAP 09      | End-to-end round-trip latency benchmark vs. struct callback     |
| GAP 09      | Deprecation + removal schedule for the struct callback          |

Phase 6 closes with the above **infrastructure** ready: the proto schemas,
the generated code, the drift gate, and this handoff contract.
