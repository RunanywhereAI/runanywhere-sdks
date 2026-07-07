import Flutter

/// RunAnywhere QHexRT Flutter Plugin - iOS Implementation.
///
/// QHexRT is Android/Snapdragon only. On iOS this plugin exists so the Flutter
/// package registers cleanly without claiming NPU support on an unsupported
/// platform.
public class QhexrtPlugin: NSObject, FlutterPlugin {
    public static func register(with _: FlutterPluginRegistrar) {}
}
