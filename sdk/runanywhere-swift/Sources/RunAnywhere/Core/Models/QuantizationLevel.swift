import Foundation

/// Quantization level
public enum QuantizationLevel: String {
    case full = "fp32"
    case half = "fp16"
    case int8 = "int8"
    case int4 = "int4"
    case int2 = "int2"
    case mixed = "mixed"
}
