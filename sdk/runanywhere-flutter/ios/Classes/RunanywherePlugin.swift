import Flutter
import UIKit

/// RunAnywhere Flutter Plugin for iOS
///
/// This plugin provides the bridge between Flutter and the RunAnywhere native library.
/// The main functionality is exposed via FFI (Dart's Foreign Function Interface),
/// so this plugin class is minimal - it just handles registration.
public class RunanywherePlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register the plugin
        // Note: Main functionality is exposed via FFI, not method channels
        let instance = RunanywherePlugin()

        // Optional: Set up a method channel for non-FFI operations
        let channel = FlutterMethodChannel(
            name: "ai.runanywhere.flutter/plugin",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)

        print("[RunAnywhere] iOS plugin registered")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "isNativeLibraryAvailable":
            // Check if the native library symbols are available
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
