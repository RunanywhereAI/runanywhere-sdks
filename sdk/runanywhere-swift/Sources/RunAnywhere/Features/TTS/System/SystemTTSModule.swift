//
//  SystemTTSModule.swift
//  RunAnywhere SDK
//
//  Built-in System TTS namespace using AVSpeechSynthesizer.
//  The C++ platform backend drives `SystemTTSService` through registered
//  callbacks in `CppBridge+Platform.swift`; there is no Swift-side module
//  protocol to conform to. This file remains as a discovery namespace so
//  example apps and docs can reference `SystemTTS` as a feature name.
//

import Foundation

/// Built-in System TTS namespace using Apple's AVSpeechSynthesizer.
///
/// Platform-specific (iOS/macOS) TTS provider. Serves as a fallback when no
/// other TTS backend (e.g. Sherpa Piper) is loaded, and can be targeted
/// explicitly via the "system-tts" voice ID.
///
/// ## Usage
///
/// ```swift
/// // Use system TTS explicitly
/// try await RunAnywhere.speak("Hello", voiceId: "system-tts")
///
/// // Or as automatic fallback when no other TTS is available
/// try await RunAnywhere.speak("Hello")
/// ```
public enum SystemTTS {}
