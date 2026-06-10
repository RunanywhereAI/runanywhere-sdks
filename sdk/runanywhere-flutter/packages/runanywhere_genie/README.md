# RunAnywhere Genie Backend

Experimental Qualcomm Genie NPU backend shell for the RunAnywhere Flutter SDK.

This package provides Flutter plugin registration and Dart FFI bindings for the
Genie backend entry points. Functional LLM routing is Android/Snapdragon-only
and requires native binaries built with the Qualcomm Genie SDK. Without those
binaries, the backend remains unavailable and the core SDK will route to other
registered backends.

## Installation

Add the core SDK and this backend package:

```yaml
dependencies:
  runanywhere: ^0.19.13
  runanywhere_genie: ^0.19.13
```

Then resolve dependencies:

```bash
flutter pub get
```

## Usage

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_genie/runanywhere_genie.dart';

Future<void> initializeSdk() async {
  await RunAnywhere.initialize();
  await Genie.register();
}
```

`Genie.register()` is safe to call when the native backend is unavailable. The
package reports LLM capability only after native registration succeeds.

## Platform Support

| Platform | Status |
| --- | --- |
| Android/Snapdragon | Experimental; requires Qualcomm Genie SDK-backed native binaries |
| iOS | Plugin shell only; backend unavailable |

## Notes

- Model registration stays in the core `runanywhere` package.
- The Genie backend is not selected by the native router unless registration
  succeeds.
- Public builds can include this package without Genie binaries; missing native
  libraries are handled as a runtime capability gate.
