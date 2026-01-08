import Foundation

/// WhisperCPP Runtime module for RunAnywhere SDK
///
/// This module provides whisper.cpp backend support for:
/// - Speech-to-Text (STT) using GGML whisper models
///
/// ## Usage
///
/// ```swift
/// import RunAnywhere
/// import WhisperCPPRuntime
///
/// // In your app initialization:
/// await WhisperCPPSTTServiceProvider.register()
///
/// // Create STT component with a whisper model
/// let sttConfig = STTConfiguration(modelId: "whisper-tiny-ggml")
/// let stt = STTComponent(configuration: sttConfig)
/// try await stt.initialize()
///
/// // Transcribe audio
/// let result = try await stt.transcribe(audioData, format: .pcm)
/// print("Transcription: \(result.text)")
/// ```
public enum WhisperCPPRuntime {
    /// Current version of the WhisperCPP Runtime module
    public static let version = "1.0.0"

    /// whisper.cpp library version
    public static let whisperCppVersion = "1.7.2"
}
