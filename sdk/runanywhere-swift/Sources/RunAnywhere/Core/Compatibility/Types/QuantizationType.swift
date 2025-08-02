//
//  QuantizationType.swift
//  RunAnywhere SDK
//
//  Quantization types for models
//

import Foundation

/// Quantization types for models
public enum QuantizationType: String, CaseIterable {
    case none = "none"
    case q2_K = "Q2_K"
    case q3_K_S = "Q3_K_S"
    case q3_K_M = "Q3_K_M"
    case q3_K_L = "Q3_K_L"
    case q4_0 = "Q4_0"
    case q4_K_S = "Q4_K_S"
    case q4_K_M = "Q4_K_M"
    case q5_0 = "Q5_0"
    case q5_K_S = "Q5_K_S"
    case q5_K_M = "Q5_K_M"
    case q6_K = "Q6_K"
    case q8_0 = "Q8_0"
    case f16 = "F16"
    case f32 = "F32"

    public var displayName: String {
        rawValue
    }

    /// Memory multiplier for this quantization
    public var memoryMultiplier: Double {
        switch self {
        case .none, .f32: return 1.0
        case .f16: return 0.5
        case .q8_0: return 0.25
        case .q6_K: return 0.20
        case .q5_0, .q5_K_S, .q5_K_M: return 0.16
        case .q4_0, .q4_K_S, .q4_K_M: return 0.125
        case .q3_K_S, .q3_K_M, .q3_K_L: return 0.10
        case .q2_K: return 0.0625
        }
    }
}
