# Flutter Example App (RunAnywhereAI)

## Info

Flutter reference app for the RunAnywhere SDK: LLM chat (streaming), STT, TTS, voice pipeline, VLM camera, tool calling, RAG with PDF ingestion, structured output, solutions YAML runner. Eight tabs via `NavigationBar` + `IndexedStack` in `ContentView`; startup/init lives in `runanywhere_ai_app.dart`.

Example apps are UI-only: thin `RunAnywhere.*` SDK calls, no business logic, no workarounds, no SDK-internal knowledge. Global rules: see repo-root AGENTS.md.

- Depends on 4 local SDK packages via `path:` in `pubspec.yaml` → `../../../sdk/runanywhere-flutter/packages/{runanywhere,runanywhere_llamacpp,runanywhere_onnx,runanywhere_genie}` (Dart FFI, no platform channels).
- State: singleton `ChangeNotifier` + `ListenableBuilder` for feature state; local `setState` for per-screen UI.
- Core services in `core/services/`: audio recording/playback, `ConversationStore` (JSON under Documents/), keychain/secure storage, permissions.

## Build Info

```bash
# From examples/flutter/RunAnywhereAI/
flutter pub get                 # must run first
flutter analyze                 # strict: dead_code/unused_import are errors
flutter run                     # or: flutter run -d "iPhone 16 Pro"
flutter build apk --debug
flutter build ios --simulator --debug
dart format lib/ test/

# Verification (scripts live under repo-root scripts/)
../../../scripts/examples/flutter/smoke.sh     # SDK API coverage grep + analyze
../../../scripts/examples/flutter/verify.sh    # pub get + analyze + APK build
RUN_IOS=1 ../../../scripts/examples/flutter/verify.sh
# verify.sh env: RUN_ANDROID / RUN_IOS / REFRESH_ANDROID_NATIVE / REFRESH_IOS_NATIVE

# From repo root
./run example flutter build     # flutter build apk
./run example flutter clean

# Rebuild native binaries after C++ changes (repo root)
./run sdk commons build-android     # scripts/build/android.sh
./run sdk commons build-ios         # scripts/build/ios-xcframework.sh (macOS only)
```

iOS: after `pub get`, `cd ios && pod install` if Pods are stale. Requires Flutter 3.10+, iOS 15.1+ (Podfile-enforced), arm64 device recommended.

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: Android needs `pickFirst '**/libc++_shared.so'` and `'**/libomp.so'` (each SDK plugin bundles them) plus `extractNativeLibs="true"` + optional `libcdsprpc.so` for Genie NPU — don't remove.
- 2026-07-05: iOS Podfile post_install forces `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` (local xcframeworks are arm64-sim only) and sets `PERMISSION_MICROPHONE/SPEECH_RECOGNIZER/CAMERA=1` for permission_handler.
- 2026-07-05: Never re-query `currentModel()` inside a modelLifecycle event handler — infinite event loop (past ANR).
- 2026-07-05: Android 15/16 — Flutter `statusBarColor` is a no-op; set bar color natively in styles.xml.
