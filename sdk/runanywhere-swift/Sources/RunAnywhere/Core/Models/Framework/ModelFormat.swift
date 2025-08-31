import Foundation

/// Model formats supported
public enum ModelFormat: String, CaseIterable, Codable, Sendable {
    case mlmodel = "mlmodel"
    case mlpackage = "mlpackage"
    case tflite = "tflite"
    case onnx = "onnx"
    case ort = "ort"
    case safetensors = "safetensors"
    case gguf = "gguf"
    case ggml = "ggml"
    case mlx = "mlx"
    case pte = "pte"
    case bin = "bin"
    case weights = "weights"
    case checkpoint = "checkpoint"
    case unknown = "unknown"
}
