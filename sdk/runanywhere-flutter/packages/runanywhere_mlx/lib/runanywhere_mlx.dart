/// MLX backend for RunAnywhere Flutter SDK.
///
/// The MLX implementation lives in the Swift `RunAnywhereMLX` product. This
/// Dart package exposes the backend registration call and uses FFI to invoke
/// the Swift runtime's exported C entrypoints on iOS/macOS.
library;

export 'mlx.dart';
