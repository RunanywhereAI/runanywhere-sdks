# Federated Flutter packages

Matches the main-branch `sdk/runanywhere-flutter/packages/*` layout so
pub.dev consumers can mix-and-match backends.

```
sdk/dart/packages/
├── runanywhere/              — core adapter, FFI bindings to libracommons_core
├── runanywhere_llamacpp/     — llama.cpp engine registration hook
├── runanywhere_onnx/         — ONNX Runtime engine registration hook
└── runanywhere_genie/        — Qualcomm Genie engine registration hook
```

Each engine sub-package:

- Depends on `runanywhere: ^2.0.0-dev.1` for the core API surface.
- Declares a Flutter plugin binding (Android + iOS pluginClass).
- Exposes `RunanywhereXxx.register({priority: 100})` that sample apps
  call at startup. Real engine registration happens via C++ ctor-init
  in the shared library; this Dart call is a UI-gating signal.

## Installing in a sample app

```yaml
# pubspec.yaml
dependencies:
  runanywhere: ^2.0.0-dev.1
  runanywhere_llamacpp: ^2.0.0-dev.1
  runanywhere_onnx: ^2.0.0-dev.1
```

```dart
// lib/main.dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

await RunAnywhereSDK.initialize(apiKey: '...');
RunanywhereLlamacpp.register();
```

## Status

Scaffold matches main. The single package at `sdk/dart/` remains the
canonical source; these federated packages re-export `runanywhere.dart`
so there's only one implementation. Splitting out per-package iOS
Podspec + Android Gradle still TBD when publishing to pub.dev.
