import Flutter
import UIKit

// MARK: - C Symbol Declarations
// These declarations force the linker to include symbols from RACommons.xcframework
// that are only called via FFI/dlsym. Without these references, the linker would
// strip the symbols as "unused" since they're not called from native code.

// LLM Component symbols
@_silgen_name("rac_llm_component_create")
private func _rac_llm_component_create() -> UnsafeMutableRawPointer?

@_silgen_name("rac_llm_component_destroy")
private func _rac_llm_component_destroy(_: UnsafeMutableRawPointer?)

@_silgen_name("rac_llm_component_configure")
private func _rac_llm_component_configure(_: UnsafeMutableRawPointer?, _: UnsafePointer<CChar>?, _: UnsafePointer<CChar>?, _: UInt32, _: UInt32, _: Float, _: Float) -> Int32

@_silgen_name("rac_llm_component_generate")
private func _rac_llm_component_generate(_: UnsafeMutableRawPointer?, _: UnsafePointer<CChar>?, _: UnsafeMutablePointer<CChar>?, _: Int) -> Int32

@_silgen_name("rac_llm_component_cleanup")
private func _rac_llm_component_cleanup(_: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("rac_llm_component_cancel")
private func _rac_llm_component_cancel(_: UnsafeMutableRawPointer?) -> Int32

// STT Component symbols
@_silgen_name("rac_stt_component_create")
private func _rac_stt_component_create() -> UnsafeMutableRawPointer?

@_silgen_name("rac_stt_component_destroy")
private func _rac_stt_component_destroy(_: UnsafeMutableRawPointer?)

// TTS Component symbols
@_silgen_name("rac_tts_component_create")
private func _rac_tts_component_create() -> UnsafeMutableRawPointer?

@_silgen_name("rac_tts_component_destroy")
private func _rac_tts_component_destroy(_: UnsafeMutableRawPointer?)

// VAD Component symbols
@_silgen_name("rac_vad_component_create")
private func _rac_vad_component_create() -> UnsafeMutableRawPointer?

@_silgen_name("rac_vad_component_destroy")
private func _rac_vad_component_destroy(_: UnsafeMutableRawPointer?)

// Model Registry symbols
@_silgen_name("rac_model_registry_create")
private func _rac_model_registry_create() -> UnsafeMutableRawPointer?

@_silgen_name("rac_model_registry_destroy")
private func _rac_model_registry_destroy(_: UnsafeMutableRawPointer?)

// Download Manager symbols
@_silgen_name("rac_download_manager_create")
private func _rac_download_manager_create(_: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?

@_silgen_name("rac_download_manager_destroy")
private func _rac_download_manager_destroy(_: UnsafeMutableRawPointer?)

// Init symbol
@_silgen_name("rac_init")
private func _rac_init()

/// Force symbol linkage by referencing C symbols.
/// This function is never called but its existence forces the linker to include
/// all referenced symbols from the static framework.
@_optimize(none)
private func _forceSymbolLinkage() {
    // These pointer references prevent the compiler from optimizing away the symbols
    _ = unsafeBitCast(_rac_llm_component_create as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_llm_component_destroy as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_llm_component_configure as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_llm_component_generate as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_llm_component_cleanup as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_llm_component_cancel as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_stt_component_create as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_stt_component_destroy as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_tts_component_create as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_tts_component_destroy as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_vad_component_create as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_vad_component_destroy as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_model_registry_create as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_model_registry_destroy as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_download_manager_create as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_download_manager_destroy as Any, to: UnsafeRawPointer.self)
    _ = unsafeBitCast(_rac_init as Any, to: UnsafeRawPointer.self)
}

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
