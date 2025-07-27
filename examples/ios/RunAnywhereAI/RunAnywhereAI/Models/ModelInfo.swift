//
//  ModelInfo.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

// MARK: - Model Format

enum ModelFormat: String, CaseIterable, Codable {
    case gguf = "GGUF"
    case onnx = "ONNX"
    case onnxRuntime = "ONNX Runtime"
    case coreML = "CoreML"
    case mlPackage = "mlpackage"
    case mlx = "MLX"
    case mlc = "MLC"
    case pte = "PTE"
    case tflite = "TFLite"
    case ggml = "GGML"
    case pytorch = "PyTorch"
    case safetensors = "SafeTensors"
    case picoLLM = "picoLLM"
    case other = "Other"
    
    var displayName: String {
        rawValue
    }
    
    var fileExtension: String {
        switch self {
        case .gguf:
            return "gguf"
        case .onnx:
            return "onnx"
        case .onnxRuntime:
            return "onnxRuntime"
        case .coreML:
            return "mlmodel"
        case .mlPackage:
            return "mlpackage"
        case .mlx:
            return "mlx"
        case .mlc:
            return "mlc"
        case .pte:
            return "pte"
        case .tflite:
            return "tflite"
        case .ggml:
            return "ggml"
        case .pytorch:
            return "pt"
        case .safetensors:
            return "safetensors"
        case .picoLLM:
            return "picollm"
        case .other:
            return "bin"
        }
    }
    
    static func from(extension ext: String) -> ModelFormat {
        switch ext.lowercased() {
        case "gguf": return .gguf
        case "onnx": return .onnx
        case "onnxruntime", "ort": return .onnxRuntime
        case "mlmodel": return .coreML
        case "mlpackage": return .mlPackage
        case "mlx": return .mlx
        case "mlc": return .mlc
        case "pte": return .pte
        case "tflite": return .tflite
        case "ggml": return .ggml
        case "pt", "pth": return .pytorch
        case "safetensors": return .safetensors
        case "picollm": return .picoLLM
        default: return .other
        }
    }
}

// MARK: - LLM Framework

enum LLMFramework: String, CaseIterable, Codable {
    case mock = "Mock"
    case foundationModels = "Foundation Models"
    case llamaCpp = "llama.cpp"
    case coreML = "Core ML"
    case mlx = "MLX"
    case mlc = "MLC-LLM"
    case onnxRuntime = "ONNX Runtime"
    case execuTorch = "ExecuTorch"
    case tensorFlowLite = "TensorFlow Lite"
    case picoLLM = "picoLLM"
    case swiftTransformers = "Swift Transformers"
    
    var displayName: String {
        rawValue
    }
    
    static func forFormat(_ format: ModelFormat) -> LLMFramework {
        switch format {
        case .gguf, .ggml: return .llamaCpp
        case .coreML, .mlPackage: return .coreML
        case .mlx, .safetensors: return .mlx
        case .mlc: return .mlc
        case .onnx, .onnxRuntime: return .onnxRuntime
        case .pte: return .execuTorch
        case .tflite: return .tensorFlowLite
        case .picoLLM: return .picoLLM
        case .pytorch: return .execuTorch
        default: return .mock
        }
    }
}

// MARK: - Model Info

struct ModelInfo: Identifiable, Codable {
    let id: String
    let name: String
    var path: String?
    let format: ModelFormat
    let size: String
    let framework: LLMFramework
    let quantization: String?
    let contextLength: Int?
    var isLocal: Bool = false
    let downloadURL: URL?
    
    // Legacy support
    let description: String
    let minimumMemory: Int64
    let recommendedMemory: Int64
    
    init(id: String = UUID().uuidString,
         name: String,
         path: String? = nil,
         format: ModelFormat,
         size: String,
         framework: LLMFramework,
         quantization: String? = nil,
         contextLength: Int? = nil,
         isLocal: Bool = false,
         downloadURL: URL? = nil,
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
        self.isLocal = isLocal
        self.downloadURL = downloadURL
        self.description = description
        self.minimumMemory = minimumMemory
        self.recommendedMemory = recommendedMemory
    }
    
    var displaySize: String {
        size
    }
    
    var isCompatible: Bool {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        return availableMemory >= minimumMemory
    }
}
