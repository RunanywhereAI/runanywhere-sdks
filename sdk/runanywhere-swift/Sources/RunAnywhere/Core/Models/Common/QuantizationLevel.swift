import Foundation

/// Quantization level
public enum QuantizationLevel: String, Codable, Sendable {
    case full = "fp32"
    case f32 = "f32"
    case half = "fp16"
    case f16 = "f16"
    case int8 = "int8"
    case q8v0 = "q8_0"
    case int4 = "int4"
    case q4v0 = "q4_0"
    case q4KS = "q4_K_S"
    case q4KM = "q4_K_M"
    case q5v0 = "q5_0"
    case q5KS = "q5_K_S"
    case q5KM = "q5_K_M"
    case q6K = "q6_K"
    case q3KS = "q3_K_S"
    case q3KM = "q3_K_M"
    case q3KL = "q3_K_L"
    case q2K = "q2_K"
    case int2 = "int2"
    case mixed = "mixed"
}
