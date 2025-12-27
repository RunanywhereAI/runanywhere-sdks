import Foundation

/// ONNXRuntime module for RunAnywhere SDK
///
/// This module provides ONNX Runtime backend support for:
/// - Speech-to-Text (ASR) using Whisper and other ONNX models
/// - Text Generation (LLM) - Future support
///
/// ## Usage
///
/// ### Initialize and Register
/// ```swift
/// import RunAnywhere
/// import ONNXRuntime
///
/// // Register service provider with ModuleRegistry
/// await ONNXServiceProvider.register()
///
/// // Register framework adapter with model
/// try await RunAnywhere.registerFrameworkAdapter(
///     ONNXAdapter.shared,
///     models: [
///         try! ModelRegistration(
///             url: "https://huggingface.co/.../whisper-tiny.onnx",
///             framework: .onnx,
///             id: "whisper-tiny-onnx",
///             name: "Whisper Tiny (ONNX)",
///             format: .onnx,
///             memoryRequirement: 39_000_000
///         )
///     ]
/// )
/// ```
///
/// ### Direct Usage
/// ```swift
/// let service = ONNXSTTService()
/// try await service.initialize(modelPath: "/path/to/model.onnx")
///
/// let audioData = // ... load audio data
/// let result = try await service.transcribe(
///     audioData: audioData,
///     options: STTOptions(sampleRate: 16000, language: "en")
/// )
/// print("Transcribed: \(result.text)")
/// ```
public enum ONNXRuntime {
    /// Current version of the ONNX Runtime module
    /// Note: Should be kept in sync with SDK version in VERSION file
    public static let version = "0.16.0"

    /// ONNX Runtime library version (underlying C library)
    public static let onnxRuntimeVersion = "1.23.2"
}
