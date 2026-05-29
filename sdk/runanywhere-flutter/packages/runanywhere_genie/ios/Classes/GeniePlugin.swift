import Flutter

/// RunAnywhere Genie Flutter Plugin - iOS Implementation
///
/// Genie NPU routing is Android/Snapdragon only and requires SDK-backed native
/// ops. On iOS this plugin exists so the Flutter package can register cleanly
/// without claiming runtime NPU support on an unsupported platform.
public class GeniePlugin: NSObject, FlutterPlugin {

    public static func register(with _: FlutterPluginRegistrar) {}
}
