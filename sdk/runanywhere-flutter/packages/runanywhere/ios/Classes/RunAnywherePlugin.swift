import Flutter
import UIKit

// NOTE: @_silgen_name symbol declarations removed.
// The -all_load and -export_dynamic linker flags in the podspec
// ensure all symbols from RACommons.xcframework are included and
// visible to Dart FFI without needing explicit Swift references.

/// RunAnywhere Flutter Plugin - iOS Implementation
///
/// This plugin provides the native bridge for the RunAnywhere SDK on iOS.
/// The actual AI functionality is provided by RACommons.xcframework.
public class RunAnywherePlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Install the URLSession-backed platform HTTP transport BEFORE any
        // Dart FFI call has a chance to fire HTTP through libcurl. Routes
        // every `rac_http_request_*` through URLSession so iOS consumers
        // inherit the system trust store, proxies, HTTP/2, and ATS instead
        // of libcurl. Idempotent.
        URLSessionHttpTransport.register()

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
