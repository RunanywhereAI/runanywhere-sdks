//
//  PlatformPluginBridge.swift
//  RunAnywhere Flutter Plugin
//
//  Swift façade around the ObjC++ implementation in
//  `PlatformPluginBridge.mm`. The ObjC++ file owns the
//  `rac_platform_tts_callbacks_t` + `rac_platform_llm_callbacks_t`
//  vtables, the AVSpeechSynthesizer machinery, and the plugin
//  registration sequence; this file exposes
//  `PlatformPluginBridge.register()` so the Flutter plugin can install
//  the adapter from `RunAnywherePlugin.register(with:)`.
//
//  Mirrors the Swift SDK reference in
//    sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Platform.swift
//  but is split between Swift+ObjC++ because the Flutter plugin does NOT
//  ship a `CRACommons` Swift module map — we cannot import the C ABI
//  from Swift directly.
//
//  Apple-only. Android has no commons-level platform-TTS plugin (the
//  commons `platform` backend is gated behind `if(APPLE AND RAC_BUILD_PLATFORM)`),
//  so the Flutter Android pod intentionally has no counterpart to this file.
//

import Foundation

/// AVSpeechSynthesizer-backed System TTS plugin + Apple Foundation Models
/// LLM stub registration.
///
/// Wires the commons `platform` engine plugin into the unified plugin
/// router so `tts.loadVoice("system-tts")` resolves on iOS and so
/// `foundation-models-default` (and any other `framework ==
/// .foundationModels` model) gets a deterministic availability response
/// instead of "Swift callbacks not registered". Safe to call
/// `register()` multiple times — subsequent calls are no-ops (the ObjC++
/// implementation guards with an atomic flag).
public enum PlatformPluginBridge {

    /// Install the AVSpeechSynthesizer-backed System TTS adapter and the
    /// Apple Foundation Models LLM availability adapter, then register the
    /// platform engine plugin with the commons router. Idempotent.
    public static func register() {
        RAFlutterRegisterPlatformTTS()
    }
}

// MARK: - Bridge to ObjC++ implementation
//
// The symbol is implemented in PlatformPluginBridge.mm. It cannot be
// declared in an ObjC header consumed by Swift unless the pod ships a
// module map, so we declare it here with `@_silgen_name` and match the C
// ABI in the .mm file.

@_silgen_name("ra_flutter_register_platform_tts")
private func RAFlutterRegisterPlatformTTS()
