import Foundation

/// Model formats supported
public enum ModelFormat: String, CaseIterable {
    case mlmodel = "mlmodel"
    case mlpackage = "mlpackage"
    case tflite = "tflite"
    case onnx = "onnx"
    case ort = "ort"
    case safetensors = "safetensors"
    case gguf = "gguf"
    case ggml = "ggml"
    case pte = "pte"
    case bin = "bin"
    case weights = "weights"
    case checkpoint = "checkpoint"
}
