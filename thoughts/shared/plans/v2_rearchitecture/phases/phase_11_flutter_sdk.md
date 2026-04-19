# Phase 11 — Flutter SDK migration + Flutter example app

> Goal: rewire `sdk/runanywhere-flutter/` (melos-managed Dart
> monorepo) onto the new commons C ABI through Dart FFI + proto3.
> Generate Dart bindings via `protoc_plugin`. Rewrite the Flutter
> example app. Runs on Android + iOS; macOS / Linux / Windows
> desktop is supported on a best-effort basis.

---

## Prerequisites

- Phase 9 (Swift SDK) + Phase 10 (Kotlin SDK) complete — we reuse
  their native artifact pipelines (the Swift XCFramework for iOS,
  Android `.so`s from the Kotlin build for Android).
- `sdk/runanywhere-commons/idl/*.proto` stable.

---

## What this phase delivers

1. **Dart proto3 codegen** from commons `idl/` using `protoc_plugin`
   into `packages/runanywhere/lib/src/proto/`. Regenerated on CI,
   not hand-edited.

2. **Dart FFI bindings** (via `package:ffi` + `ffigen`) to the new
   `ra_*` C ABI. Generated from `sdk/runanywhere-commons/include/rac/abi/*.h`.

3. **Idiomatic Dart public API** — every streaming primitive exposes
   `Stream<Event>`; every one-shot is `Future<Result>`. Dart isolates
   for heavy work.

4. **Platform channel retirement** — the v1 SDK probably bridged via
   `MethodChannel`/`EventChannel` to per-platform code. With FFI we
   call the shared library directly; platform channels go away for
   anything reachable through the C ABI. (Platform channels stay for
   things genuinely platform-native like microphone permission.)

5. **Rewritten Flutter example app** at `examples/flutter/` consuming
   the new SDK.

6. **Pub publishing pipeline** — release script publishes each
   package to pub.dev (or internal pub server).

---

## Exact file-level deliverables

### Dart package structure (melos)

```text
sdk/runanywhere-flutter/
├── melos.yaml                              UPDATED — new package layout
├── packages/
│   ├── runanywhere/                        public SDK
│   │   ├── pubspec.yaml                    UPDATED — ffi, protobuf, path_provider
│   │   ├── lib/
│   │   │   ├── runanywhere.dart            public surface re-exports
│   │   │   └── src/
│   │   │       ├── run_anywhere.dart       top-level singleton, bootstrap()
│   │   │       ├── ffi/
│   │   │       │   ├── ra_bindings.dart    ffigen output (gitignored, regenerated)
│   │   │       │   └── library_loader.dart DynamicLibrary.open per-platform
│   │   │       ├── proto/                  protoc_plugin output (gitignored)
│   │   │       │   └── ra_idl/*.pb.dart
│   │   │       ├── llm/
│   │   │       │   ├── llm_session.dart
│   │   │       │   └── llm_event.dart      sealed class
│   │   │       ├── stt/, tts/, vad/, vlm/, rag/, voice_agent/
│   │   │       ├── download/
│   │   │       └── errors/
│   │   │           └── ra_error.dart
│   │   ├── test/
│   │   ├── android/
│   │   │   ├── build.gradle               pulls commons AAR from the Kotlin build
│   │   │   └── src/main/                  contains no Kotlin code — plugin is pure Dart FFI
│   │   ├── ios/
│   │   │   ├── runanywhere.podspec        depends on RACCommonsStatic.xcframework
│   │   │   └── Classes/                   Swift shim only if a platform-native capability
│   │   │                                  is needed (e.g., microphone permission)
│   │   ├── macos/                         symlinks to ios/ where sensible
│   │   ├── linux/                         CMakeLists that bundles libcommons.so
│   │   └── windows/                       (optional, best-effort)
│   └── runanywhere_test_support/
│       └── …                              shared test helpers
├── scripts/
│   ├── codegen-proto.sh                   NEW — protoc_plugin invocation
│   ├── codegen-ffi.sh                     NEW — ffigen invocation
│   ├── build-commons-ios.sh               sources XCFramework from phase 9
│   ├── build-commons-android.sh           sources .so from phase 10
│   └── release.sh
└── docs/
    ├── README.md                          UPDATED
    ├── migration_guide.md                 new; v1 → v2 migration
    └── architecture.md                    new
```

### `pubspec.yaml` key deps

```yaml
name: runanywhere
version: 2.0.0
environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.24.0'

dependencies:
  flutter: { sdk: flutter }
  ffi: ^2.1.0
  protobuf: ^4.1.0
  path_provider: ^2.1.0
  collection: ^1.18.0

dev_dependencies:
  ffigen: ^13.0.0
  build_runner: ^2.4.0
  test: ^1.25.0
  flutter_test: { sdk: flutter }
```

### FFI binding shape

`ffigen.yaml`:

```yaml
name: RaBindings
description: FFI bindings to the RunAnywhere C ABI
output: 'lib/src/ffi/ra_bindings.dart'
headers:
  entry-points:
    - '../../../runanywhere-commons/include/rac/abi/ra_llm.h'
    - '../../../runanywhere-commons/include/rac/abi/ra_stt.h'
    - '../../../runanywhere-commons/include/rac/abi/ra_tts.h'
    - '../../../runanywhere-commons/include/rac/abi/ra_vad.h'
    - '../../../runanywhere-commons/include/rac/abi/ra_vlm.h'
    - '../../../runanywhere-commons/include/rac/abi/ra_rag.h'
    - '../../../runanywhere-commons/include/rac/abi/ra_voice_agent.h'
    - '../../../runanywhere-commons/include/rac/abi/ra_status.h'
  include-directives:
    - '**/rac/abi/**.h'
preamble: |
  // GENERATED — do not edit. Re-run scripts/codegen-ffi.sh.
```

`library_loader.dart`:

```dart
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

ffi.DynamicLibrary openCommonsLibrary() {
  if (Platform.isAndroid) return ffi.DynamicLibrary.open('libcommons.so');
  if (Platform.isIOS)     return ffi.DynamicLibrary.process();
  if (Platform.isMacOS)   return ffi.DynamicLibrary.open('libcommons.dylib');
  if (Platform.isLinux)   return ffi.DynamicLibrary.open('libcommons.so');
  if (Platform.isWindows) return ffi.DynamicLibrary.open('commons.dll');
  throw UnsupportedError('No RunAnywhere build for ${Platform.operatingSystem}');
}

final raBindings = RaBindings(openCommonsLibrary());
```

### Public Dart API shape

```dart
class LLMSession {
  final int _handle;
  LLMSession._(this._handle);

  static Future<LLMSession> create(LLMConfiguration configuration) async {
    final cfgBytes = configuration.toProto().writeToBuffer();
    final handle = await Isolate.run(() {
      final out = calloc<ffi.Pointer<ffi.Void>>();
      final status = raBindings.ra_llm_create(
        cfgBytes.allocateFFI(),
        cfgBytes.length,
        out,
      );
      RAError.check(status);
      return out.value.address;
    });
    return LLMSession._(handle);
  }

  Stream<LLMEvent> generate(Prompt prompt) async* {
    final promptBytes = prompt.toProto().writeToBuffer();
    final startStatus = raBindings.ra_llm_start(
      ffi.Pointer.fromAddress(_handle).cast(),
      promptBytes.allocateFFI(),
      promptBytes.length,
    );
    RAError.check(startStatus);

    var bufCap = 1024;
    final buf = calloc.allocate<ffi.Uint8>(bufCap);
    try {
      while (true) {
        final len = calloc<ffi.Size>();
        len.value = bufCap;
        final st = raBindings.ra_llm_next(
          ffi.Pointer.fromAddress(_handle).cast(),
          buf,
          bufCap,
          len,
        );
        if (st == RA_STATUS_BUFFER_TOO_SMALL) {
          bufCap = len.value;
          // reallocate and retry
          continue;
        }
        RAError.check(st);
        final bytes = buf.asTypedList(len.value);
        final proto = Ra_Idl_LlmEvent.fromBuffer(bytes);
        final ev = LLMEvent.fromProto(proto);
        if (ev == null) continue;
        yield ev;
        if (ev is LLMEventEnd) break;
      }
    } finally {
      calloc.free(buf);
    }
  }

  void cancel() {
    raBindings.ra_llm_cancel(ffi.Pointer.fromAddress(_handle).cast());
  }

  Future<void> close() async {
    raBindings.ra_llm_destroy(ffi.Pointer.fromAddress(_handle).cast());
  }
}
```

### Isolate strategy

Streaming primitives read `ra_*_next` on the main isolate's event
loop — `ra_llm_next` is blocking in C but the Dart scheduler yields
between emissions naturally when the underlying `Stream` is consumed
asynchronously. For latency-sensitive work (RAG retrieval, LLM
prompt prefill), spin up a short-lived `Isolate.run(...)` so the UI
thread isn't blocked.

### Flutter example app (examples/flutter/)

```text
examples/flutter/runanywhere_ai/
├── pubspec.yaml                      UPDATED — depends on sdk/runanywhere-flutter locally
├── lib/
│   ├── main.dart                     bootstraps RunAnywhere, runs app
│   ├── screens/
│   │   ├── chat_screen.dart
│   │   ├── voice_agent_screen.dart
│   │   └── settings_screen.dart
│   ├── viewmodels/
│   └── widgets/
├── android/                          configures .so distribution
├── ios/                              configures XCFramework inclusion
└── integration_test/
    └── app_test.dart
```

### Deletions

```text
sdk/runanywhere-flutter/packages/*/lib/src/platform_channels/   DELETE
sdk/runanywhere-flutter/packages/*/android/src/main/kotlin/     SHRINK — delete kotlin bridge code; keep only permission shim if any
sdk/runanywhere-flutter/packages/*/ios/Classes/RAChannel*.swift DELETE
sdk/runanywhere-flutter/packages/*/lib/src/old_callback_api/    DELETE
examples/flutter/**/*.old                                       DELETE
```

### Tests

```text
packages/runanywhere/test/
  ├── llm_session_test.dart
  ├── rag_pipeline_test.dart
  ├── voice_agent_test.dart
  └── proto_roundtrip_test.dart

examples/flutter/runanywhere_ai/integration_test/
  └── app_test.dart                    — flutter_driver / patrol
```

---

## Implementation order

1. **Get the commons library into Flutter's per-platform build**:
   iOS pulls from Phase 9's XCFramework, Android from Phase 10's AAR
   `.so`s, macOS/Linux from a desktop host build, Windows optional.

2. **Run `ffigen`** once, inspect output, confirm the generated
   signatures are sane.

3. **Run `protoc_plugin`** once, inspect one message, confirm the
   Dart class names align.

4. **Write the load helper** (`library_loader.dart`). Test from a
   throwaway `main()` that calls `raBindings.ra_status_string(0)`.

5. **Write the public Dart classes** one primitive at a time. Reuse
   the `Stream<T>`/`Isolate.run` pattern.

6. **Rewrite the Flutter example app** in Flutter 3.24+. Material 3,
   Navigator 2.0 (or go_router — keep whatever the v1 used if
   convenient).

7. **CI gate**: add a workflow that runs `flutter test` + build
   across iOS Simulator + Android emulator.

8. **Publishing**: configure `melos publish` or per-package
   publishing. Decide whether we publish to pub.dev or internal pub
   mirror — Decision 08 followup.

---

## API changes

### New public Dart API

All classes exposed from `package:runanywhere`:

```dart
RunAnywhere.bootstrap(config)         // Future<void>
RunAnywhere.llmSession(config)        // Future<LLMSession>
RunAnywhere.voiceAgent(config)        // Future<VoiceAgent>
RunAnywhere.ragPipeline(config)       // Future<RAGPipeline>
RunAnywhere.modelDownloader()         // ModelDownloader

session.generate(prompt) → Stream<LLMEvent>
session.cancel()
session.close()

voiceAgent.events() → Stream<VoiceAgentEvent>
voiceAgent.pause()
voiceAgent.resume()

ragPipeline.ingest(document)          // Future<void>
ragPipeline.query(text)               // Future<RagResult>
```

### Removed

- Every MethodChannel / EventChannel reachable through the C ABI.
- `Completer`-based one-shot APIs — everything is `async`/`await`.
- V1 plugin-registration Dart code (`RunAnywherePlugin.register()` in
  `android/`/`ios/`) — FFI doesn't need platform registration.

---

## Acceptance criteria

- [ ] `melos bootstrap && melos run test` green.
- [ ] `flutter test` green per package.
- [ ] `flutter build ios` + `flutter build apk` green for the
      example app.
- [ ] Example app runs on iOS Simulator, iPhone physical, Android
      emulator, Android physical arm64. Chat + voice agent flows
      work.
- [ ] `integration_test/app_test.dart` green on both simulator
      platforms.
- [ ] FFI binding compile: changes to commons headers propagate on
      `codegen-ffi.sh` run; no hand-patched generated code.
- [ ] `.github/workflows/flutter-sdk.yml` + `flutter-app.yml` (new)
      green.
- [ ] No `MethodChannel` reference for anything a primitive can
      reach via FFI — grep gated.

## Validation checkpoint — frontend major

See `testing_strategy.md`. Phase 11 runs:

- **Compilation.**
  ```bash
  cd sdk/runanywhere-flutter
  melos bootstrap
  melos run analyze                                             # dart analyze
  melos run test                                                # package tests
  melos run build                                               # per-package builds
  (cd ../../examples/flutter/runanywhere_ai
    && flutter build ios --no-codesign
    && flutter build apk)
  ```
  All exit 0 with **zero analyzer issues**. Fix warnings in-PR.
- **dart analyze + flutter analyze green** across every package.
  Strict mode where the v1 code already uses it; tighten where
  feasible in this phase.
- **ffigen / protoc_plugin reproducibility.** Regenerate bindings
  on a clean checkout; no diff from what's in the PR.
- **FFI library-load smoke.** `DynamicLibrary.open()` returns
  non-null on iOS sim + Android emulator + macOS desktop.
- **Example app runs on iOS + Android.** `flutter run` launches
  to first screen; chat + voice agent flows work end-to-end.
- **Integration test suite green** via `flutter drive` /
  integration_test on both sim platforms.
- **Feature parity.** Every Flutter SDK feature from pre-Phase-11
  works post-Phase-11.
- **Binary sizes.** iOS Runner.app ≤ 120 MB arm64; Android APK
  ≤ 90 MB per ABI. Reported by CI as soft warnings if exceeded.
- **CI.** `.github/workflows/flutter-sdk.yml` +
  `flutter-app.yml` green.

**Fix-as-you-go**: if FFI codegen produces a signature the SDK
can't cleanly consume, fix the header in commons (with a coordinated
commons patch release) rather than papering over in Dart.

---

## What this phase does NOT do

- Desktop (macOS / Linux / Windows) support stays on best-effort.
  Primary targets are iOS + Android. We accept that desktop builds
  may need per-PR rebasing while we stabilise.
- Web Flutter (`flutter web`) is not in scope. The web SDK covers
  browsers through a different architecture (Phase 13).
- No Firebase / Crashlytics integration beyond what the v1 app
  already had.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| `dart:ffi` allocation / free on every `next` call burns perf | Medium | Cache the buffer in an instance field. Only reallocate on `BUFFER_TOO_SMALL`. Same pattern as Swift SDK |
| iOS XCFramework packaging inside Flutter podspec is fiddly | Medium | Pin the XCFramework into the podspec's `vendored_frameworks`; shell out to the commons build during pod install. Existing pattern in the Dart community (ex: mlkit) |
| Android AAR vs raw `.so` — how does Flutter include commons | Medium | Vendor the `.so` files in `android/src/main/jniLibs/<abi>/`; Gradle picks them up. No need to publish a separate AAR |
| Isolate-based blocking on `ra_llm_next` freezes the Dart scheduler if the stream stalls | Medium | Wrap `next` calls in `Isolate.run` for long-running gens. For short interactions, use a timeout + microtask yield |
| Wire type collision when a proto field named `context` clashes with Dart keyword | Low | `protoc_plugin` appends `_` automatically; confirm by diff |
| Flutter plugin hot-reload breaks when `DynamicLibrary` is loaded multiple times | Medium | `library_loader.dart` returns a cached `DynamicLibrary` — one load per process |
| Physical-device runs on Android show garbled audio output for TTS | Medium | Sample-rate mismatch between commons TTS (22050 Hz default) and the platform `AudioTrack` — verify and resample if needed inside the SDK before returning the PCM to Dart |
