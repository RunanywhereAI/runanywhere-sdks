import Foundation

/// Model formats supported
public enum ModelFormat: String, CaseIterable, Codable, Sendable {
    case onnx
    case ort
    case gguf
    case bin
    case unknown
}
