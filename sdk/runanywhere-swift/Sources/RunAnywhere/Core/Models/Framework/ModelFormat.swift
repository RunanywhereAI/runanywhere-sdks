import Foundation

/// Model formats supported
public enum ModelFormat: String, CaseIterable, Codable, Sendable {
    case mlmodel
    case mlpackage
    case tflite
    case onnx
    case ort
    case safetensors
    case gguf
    case ggml
    case mlx
    case pte
    case bin
    case weights
    case checkpoint
    case unknown
}
