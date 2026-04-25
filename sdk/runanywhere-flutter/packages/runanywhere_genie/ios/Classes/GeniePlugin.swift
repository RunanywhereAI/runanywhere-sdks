import Flutter
import UIKit

/// RunAnywhere Genie Flutter Plugin - iOS Implementation
///
/// Genie NPU routing is Android/Snapdragon only and requires SDK-backed native
/// ops. On iOS this plugin exists so the Flutter package can register cleanly
/// without claiming runtime NPU support on an unsupported platform.
public class GeniePlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "runanywhere_genie",
            binaryMessenger: registrar.messenger()
        )
        let instance = GeniePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getBackendVersion":
            result("0.1.6")
        case "getBackendName":
            result("Genie")
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
