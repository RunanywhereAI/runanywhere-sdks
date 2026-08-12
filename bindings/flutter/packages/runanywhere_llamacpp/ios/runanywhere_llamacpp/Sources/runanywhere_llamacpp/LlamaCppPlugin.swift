import Flutter

/// RunAnywhere LlamaCPP Flutter Plugin - iOS Implementation
///
/// This plugin only participates in Flutter plugin registration. Dart talks to
/// the backend through FFI registration symbols from RABackendLLAMACPP.
public class LlamaCppPlugin: NSObject, FlutterPlugin {

    public static func register(with _: FlutterPluginRegistrar) {}
}
