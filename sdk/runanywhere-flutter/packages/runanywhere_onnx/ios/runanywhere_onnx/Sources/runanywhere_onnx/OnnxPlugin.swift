import Flutter

/// RunAnywhere ONNX Flutter Plugin - iOS Implementation
///
/// This plugin only participates in Flutter plugin registration. Dart talks to
/// the backend through FFI registration symbols from RABackendONNX.
public class OnnxPlugin: NSObject, FlutterPlugin {

    public static func register(with _: FlutterPluginRegistrar) {}
}
