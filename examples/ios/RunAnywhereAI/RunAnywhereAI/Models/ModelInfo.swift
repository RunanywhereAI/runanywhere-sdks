//
//  ModelInfo.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

// MARK: - Model Format

enum ModelFormat: String, CaseIterable, Codable {
    case gguf = "GGUF"
    case onnx = "ONNX"
    case coreML = "CoreML"
    case mlx = "MLX"
    case mlc = "MLC"
    case pte = "PTE"
    case tflite = "TFLite"
    case other = "Other"
    
    var displayName: String {
        return rawValue
    }
    
    var fileExtension: String {
        switch self {
        case .gguf:
            return "gguf"
        case .onnx:
            return "onnx"
        case .coreML:
            return "mlpackage"
        case .mlx:
            return "mlx"
        case .mlc:
            return "mlc"
        case .pte:
            return "pte"
        case .tflite:
            return "tflite"
        case .other:
            return "bin"
        }
    }
}

// MARK: - LLM Framework

enum LLMFramework: String, CaseIterable, Codable {
    case mock = "Mock"
    case llamaCpp = "llama.cpp"
    case coreML = "Core ML"
    case mlx = "MLX"
    case mlc = "MLC-LLM"
    case onnx = "ONNX Runtime"
    case execuTorch = "ExecuTorch"
    case tfLite = "TensorFlow Lite"
    case picoLLM = "picoLLM"
    case swiftTransformers = "Swift Transformers"
    
    var displayName: String {
        return rawValue
    }
}

// MARK: - Model Info

struct ModelInfo: Identifiable, Codable {
    let id: String
    let name: String
    let path: String
    let format: ModelFormat
    let size: String
    let framework: LLMFramework
    let quantization: String?
    let contextLength: Int?
    
    // Legacy support
    let description: String
    let minimumMemory: Int64
    let recommendedMemory: Int64
    
    init(id: String = UUID().uuidString,
         name: String,
         path: String = "",
         format: ModelFormat,
         size: String,
         framework: LLMFramework,
         quantization: String? = nil,
         contextLength: Int? = nil,
         description: String = "",
         minimumMemory: Int64 = 2_000_000_000,
         recommendedMemory: Int64 = 4_000_000_000) {
        self.id = id
        self.name = name
        self.path = path
        self.format = format
        self.size = size
        self.framework = framework
        self.quantization = quantization
        self.contextLength = contextLength
        self.description = description
        self.minimumMemory = minimumMemory
        self.recommendedMemory = recommendedMemory
    }
    
    var displaySize: String {
        return size
    }
    
    var isCompatible: Bool {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        return availableMemory >= minimumMemory
    }
}