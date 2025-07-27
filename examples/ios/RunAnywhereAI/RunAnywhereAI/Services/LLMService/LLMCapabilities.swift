//
//  LLMCapabilities.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

/// Defines the capabilities of an LLM framework
protocol LLMCapabilities {
    /// Whether the framework supports streaming generation
    var supportsStreaming: Bool { get }
    
    /// Whether the framework supports model quantization
    var supportsQuantization: Bool { get }
    
    /// Whether the framework supports batch processing
    var supportsBatching: Bool { get }
    
    /// Whether the framework supports multi-modal inputs (text, image, audio)
    var supportsMultiModal: Bool { get }
    
    /// Available quantization formats
    var quantizationFormats: [QuantizationFormat] { get }
    
    /// Maximum context length supported
    var maxContextLength: Int { get }
    
    /// Whether the framework supports custom operators
    var supportsCustomOperators: Bool { get }
    
    /// Hardware acceleration options
    var hardwareAcceleration: [HardwareAcceleration] { get }
}

/// Quantization formats supported by frameworks
enum QuantizationFormat: String, CaseIterable {
    case int8 = "INT8"
    case int4 = "INT4"
    case fp16 = "FP16"
    case qInt8 = "Q8_0"
    case qInt4_0 = "Q4_0"
    case qInt4_1 = "Q4_1"
    case qInt5_0 = "Q5_0"
    case qInt5_1 = "Q5_1"
    case qInt2 = "Q2_K"
    case qInt3 = "Q3_K"
    case qInt4K = "Q4_K"
    case qInt5K = "Q5_K"
    case qInt6K = "Q6_K"
    case xBit = "X-BIT"
    case dynamic = "DYNAMIC"
}

/// Hardware acceleration options
enum HardwareAcceleration: String, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case neuralEngine = "ANE"
    case metal = "Metal"
    case coreML = "CoreML"
    case mps = "MPS"
    case cuda = "CUDA"
    case webGPU = "WebGPU"
}