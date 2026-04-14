import Flutter
import UIKit

/// RunAnywhere Genie Flutter Plugin - iOS Implementation
///
/// This is a stub plugin for the Flutter plugin system.
/// Genie NPU backend is Android/Snapdragon only - this plugin provides
/// platform channel compatibility but no actual NPU functionality on iOS.
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
