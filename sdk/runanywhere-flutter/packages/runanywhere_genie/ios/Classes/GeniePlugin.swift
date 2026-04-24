import Flutter
import UIKit

/// RunAnywhere Genie Flutter Plugin - iOS Implementation
///
/// Genie NPU backend is Android/Snapdragon only. On iOS this plugin exists so
/// the Flutter package can register cleanly and expose backend metadata without
/// claiming runtime NPU support on an unsupported platform.
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
