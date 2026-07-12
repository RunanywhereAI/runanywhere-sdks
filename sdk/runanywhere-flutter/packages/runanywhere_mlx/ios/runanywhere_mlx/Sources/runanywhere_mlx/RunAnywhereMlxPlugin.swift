@preconcurrency import Flutter
import Foundation

// Stable C ABI linker anchor. Dart owns runtime registration through dlsym;
// this direct reference only prevents the runtime artifact from being dropped.
@_silgen_name("ra_mlx_runtime_is_available")
private func raMLXRuntimeIsAvailableLinkerAnchor() -> Int32

/// Flutter registration hook for the Apple MLX runtime.
///
/// Dart invokes the backend through exported C entrypoints and FFI. Touching
/// the canonical Swift runtime here gives the linker a direct module reference
/// so its registration symbols cannot be discarded as apparently unused.
public final class RunAnywhereMlxPlugin: NSObject, FlutterPlugin {
    public static func register(with _: FlutterPluginRegistrar) {
        _ = raMLXRuntimeIsAvailableLinkerAnchor()
    }
}
