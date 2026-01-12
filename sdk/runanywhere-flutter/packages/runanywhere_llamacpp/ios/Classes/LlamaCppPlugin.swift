import Flutter
import UIKit

/// RunAnywhere LlamaCPP Flutter Plugin - iOS Implementation
///
/// This plugin provides the native bridge for the LlamaCPP backend on iOS.
/// The actual LLM functionality is provided by RABackendLLAMACPP.xcframework.
public class LlamaCppPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "runanywhere_llamacpp",
            binaryMessenger: registrar.messenger()
        )
        let instance = LlamaCppPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getBackendVersion":
            result("0.1.4")
        case "getBackendName":
            result("LlamaCPP")
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
