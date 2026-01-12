import Flutter
import UIKit

/// RunAnywhere ONNX Flutter Plugin - iOS Implementation
///
/// This plugin provides the native bridge for the ONNX backend on iOS.
/// The actual STT/TTS/VAD functionality is provided by RABackendONNX.xcframework.
public class OnnxPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "runanywhere_onnx",
            binaryMessenger: registrar.messenger()
        )
        let instance = OnnxPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getBackendVersion":
            result("0.1.4")
        case "getBackendName":
            result("ONNX")
        case "getCapabilities":
            result(["stt", "tts", "vad"])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
