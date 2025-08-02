import Foundation

/// Quantization level
public enum QuantizationLevel: String {
    case full = "fp32"
    case f32 = "f32"
    case half = "fp16"
    case f16 = "f16"
    case int8 = "int8"
    case q8_0 = "q8_0"
    case int4 = "int4"
    case q4_0 = "q4_0"
    case q4_K_S = "q4_K_S"
    case q4_K_M = "q4_K_M"
    case q5_0 = "q5_0"
    case q5_K_S = "q5_K_S"
    case q5_K_M = "q5_K_M"
    case q6_K = "q6_K"
    case q3_K_S = "q3_K_S"
    case q3_K_M = "q3_K_M"
    case q3_K_L = "q3_K_L"
    case q2_K = "q2_K"
    case int2 = "int2"
    case mixed = "mixed"
}
