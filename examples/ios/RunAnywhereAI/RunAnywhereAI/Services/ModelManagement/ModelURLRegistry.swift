import Foundation

// MARK: - Model URL Registry

/// Centralized registry for all model download URLs
/// This provides a single place to manage and update model URLs
class ModelURLRegistry {
    static let shared = ModelURLRegistry()
    
    private init() {}
    
    // MARK: - Core ML Models
    
    let coreMLModels = [
        // Core ML models for LLMs typically require authentication on HuggingFace
        // Users should add their own models via custom URLs after obtaining access
        // Example format for adding custom Core ML models:
        // ModelDownloadInfo(
        //     id: "your-model-id",
        //     name: "YourModel.mlpackage",
        //     url: URL(string: "https://your-url/model.mlpackage.zip")!,
        //     sha256: nil,
        //     requiresUnzip: true
        // )
    ]
    
    // MARK: - MLX Models
    
    let mlxModels = [
        // MLX models are typically distributed as git repositories with multiple files
        // Recommended approach: git clone https://huggingface.co/mlx-community/model-name
        // Then point the app to the cloned directory
    ]
    
    // MARK: - ONNX Runtime Models
    
    let onnxModels = [
        ModelDownloadInfo(
            id: "phi-3-mini-onnx",
            name: "phi3-mini-4k-instruct-cpu-int4.onnx",
            url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32/phi3-mini-4k-instruct-cpu-int4-rtn-block-32.onnx")!,
            sha256: nil,
            requiresUnzip: false
        )
    ]
    
    // MARK: - TensorFlow Lite Models
    
    let tfliteModels = [
        // TFLite models typically require manual download from TensorFlow Hub or Kaggle
        // Add custom URLs after downloading models locally
    ]
    
    // MARK: - llama.cpp Models (GGUF format)
    
    let llamaCppModels = [
        ModelDownloadInfo(
            id: "tinyllama-1.1b-gguf",
            name: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "phi-3-mini-gguf",
            name: "Phi-3-mini-4k-instruct-q4.gguf",
            url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "llama-3.2-3b-gguf",
            name: "llama-3.2-3b-instruct-q4_k_m.gguf",
            url: URL(string: "https://huggingface.co/lmstudio-community/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "mistral-7b-gguf",
            name: "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false
        )
    ]
    
    // MARK: - Tokenizer Files
    
    let tokenizerFiles = [
        TokenizerDownloadInfo(
            modelId: "gpt2",
            files: [
                TokenizerFile(
                    name: "tokenizer.json",
                    url: URL(string: "https://huggingface.co/gpt2/resolve/main/tokenizer.json")!
                ),
                TokenizerFile(
                    name: "vocab.json",
                    url: URL(string: "https://huggingface.co/gpt2/resolve/main/vocab.json")!
                ),
                TokenizerFile(
                    name: "merges.txt",
                    url: URL(string: "https://huggingface.co/gpt2/resolve/main/merges.txt")!
                )
            ]
        ),
        TokenizerDownloadInfo(
            modelId: "bert-base",
            files: [
                TokenizerFile(
                    name: "tokenizer.json",
                    url: URL(string: "https://huggingface.co/bert-base-uncased/resolve/main/tokenizer.json")!
                ),
                TokenizerFile(
                    name: "vocab.txt",
                    url: URL(string: "https://huggingface.co/bert-base-uncased/resolve/main/vocab.txt")!
                )
            ]
        )
        // Note: Llama tokenizer requires authentication
    ]
    
    // MARK: - Convenience Methods
    
    func getAllModels(for framework: LLMFramework) -> [ModelDownloadInfo] {
        switch framework {
        case .coreML:
            return coreMLModels
        case .mlx:
            return mlxModels
        case .onnxRuntime:
            return onnxModels
        case .tensorFlowLite:
            return tfliteModels
        case .llamaCpp:
            return llamaCppModels
        default:
            return []
        }
    }
    
    func getModelInfo(id: String) -> ModelDownloadInfo? {
        let allModels = coreMLModels + mlxModels + onnxModels + tfliteModels + llamaCppModels
        return allModels.first { $0.id == id }
    }
    
    func getTokenizerFiles(for modelId: String) -> [TokenizerFile] {
        return tokenizerFiles.first { $0.modelId == modelId }?.files ?? []
    }
    
    // MARK: - Custom Model URLs
    
    private var customModels: [ModelDownloadInfo] = []
    
    func addCustomModel(_ model: ModelDownloadInfo) {
        customModels.append(model)
    }
    
    func removeCustomModel(id: String) {
        customModels.removeAll { $0.id == id }
    }
    
    func getCustomModels() -> [ModelDownloadInfo] {
        return customModels
    }
}

// MARK: - Supporting Types

struct ModelDownloadInfo: Codable {
    let id: String
    let name: String
    let url: URL
    let sha256: String?
    let requiresUnzip: Bool
    let requiresAuth: Bool
    let alternativeURLs: [URL]
    
    init(id: String, name: String, url: URL, sha256: String? = nil, requiresUnzip: Bool, requiresAuth: Bool = false, alternativeURLs: [URL] = []) {
        self.id = id
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.requiresUnzip = requiresUnzip
        self.requiresAuth = requiresAuth
        self.alternativeURLs = alternativeURLs
    }
}

struct TokenizerDownloadInfo: Codable {
    let modelId: String
    let files: [TokenizerFile]
}

struct TokenizerFile: Codable {
    let name: String
    let url: URL
}

// MARK: - Configuration

extension ModelURLRegistry {
    /// Update a model URL (useful for when URLs change)
    func updateModelURL(id: String, newURL: URL) {
        // This would need to be implemented with proper storage
        // For now, it's a placeholder for the API
    }
    
    /// Load custom URLs from a configuration file
    func loadCustomURLs(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let customURLs = try decoder.decode([ModelDownloadInfo].self, from: data)
        customModels = customURLs
    }
    
    /// Save current URL registry to a file
    func saveRegistry(to url: URL) throws {
        let allModels = [
            "coreML": coreMLModels,
            "mlx": mlxModels,
            "onnx": onnxModels,
            "tflite": tfliteModels,
            "llamaCpp": llamaCppModels,
            "custom": customModels
        ]
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(allModels)
        try data.write(to: url)
    }
}