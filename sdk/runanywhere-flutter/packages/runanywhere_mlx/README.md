# RunAnywhere MLX for Flutter

Optional Apple MLX backend for the RunAnywhere Flutter SDK. The package uses
the canonical Swift `RunAnywhereMLX` runtime and supports LLM, VLM, embedding,
speech-recognition, and speech-synthesis models on physical iOS 17.5 or newer
devices. The arm64 iOS Simulator slice is provided only for package, compile,
link, and startup validation; MLX registration returns `false` there.

The iOS plugin intentionally uses CocoaPods. Its precompiled Hub/Crypto
dependencies look for named bundles at the application root, and CocoaPods
preserves that required layout without introducing SwiftPM module collisions.

## Requirements

- Flutter 3.44+
- Xcode 26+ with the Swift 6.2 toolchain
- A physical Apple device running iOS 17.5+ for MLX execution

```yaml
dependencies:
  runanywhere: ^0.20.10
  runanywhere_mlx: ^0.20.10
```

Register the backend before initializing the core SDK:

```dart
import 'package:runanywhere_mlx/runanywhere_mlx.dart';

final mlxRegistered = await MLX.register();
```

`MLX.register()` is idempotent and returns `false` when the runtime is not
available. Model registration, download, loading, and inference use the normal
`RunAnywhere` core APIs.
