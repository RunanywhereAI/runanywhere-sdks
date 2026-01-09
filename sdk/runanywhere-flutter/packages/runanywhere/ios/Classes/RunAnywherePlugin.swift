import Flutter
import UIKit

/// RunAnywhere Flutter Plugin - iOS Implementation
///
/// This plugin provides the native bridge for the RunAnywhere SDK on iOS.
/// The actual AI functionality is provided by RACommons.xcframework.
public class RunAnywherePlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "runanywhere",
            binaryMessenger: registrar.messenger()
        )
        let instance = RunAnywherePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getSDKVersion":
            result("0.15.8")
        case "getCommonsVersion":
            result("0.1.4")
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
