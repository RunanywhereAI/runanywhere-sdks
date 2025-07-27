import Foundation

// MARK: - Model URL Registry

/// Centralized registry for all model download URLs
/// This provides a single place to manage and update model URLs
class ModelURLRegistry {
    static let shared = ModelURLRegistry()
    
    private init() {}
    
    // MARK: - Core ML Models
    
    let coreMLModels = [
        ModelDownloadInfo(
            id: "gpt2-coreml",
            name: "GPT2-CoreML.mlpackage",
            url: URL(string: "https://huggingface.co/coreml-community/gpt2-coreml/resolve/main/GPT2.mlpackage.zip")!,
            sha256: nil, // Add SHA256 hashes for verification
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "distilgpt2-coreml",
            name: "DistilGPT2-CoreML.mlpackage",
            url: URL(string: "https://huggingface.co/coreml-community/distilgpt2-coreml/resolve/main/DistilGPT2.mlpackage.zip")!,
            sha256: nil,
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "openelm-270m-coreml",
            name: "OpenELM-270M.mlpackage",
            url: URL(string: "https://huggingface.co/apple/OpenELM-270M-Instruct/resolve/main/OpenELM-270M-Instruct-coreml.zip")!,
            sha256: nil,
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "openelm-450m-coreml",
            name: "OpenELM-450M.mlpackage",
            url: URL(string: "https://huggingface.co/apple/OpenELM-450M-Instruct/resolve/main/OpenELM-450M-Instruct-coreml.zip")!,
            sha256: nil,
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "bert-base-coreml",
            name: "BERT-Base.mlpackage",
            url: URL(string: "https://huggingface.co/coreml-community/bert-base-uncased/resolve/main/BERT.mlpackage.zip")!,
            sha256: nil,
            requiresUnzip: true
        )
    ]
    
    // MARK: - MLX Models
    
    let mlxModels = [
        ModelDownloadInfo(
            id: "mistral-7b-mlx-4bit",
            name: "Mistral-7B-Instruct-v0.2-4bit",
            url: URL(string: "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.2-4bit/resolve/main/mistral-7b-instruct-v0.2-4bit.tar.gz")!,
            sha256: nil,
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "llama-3.2-3b-mlx",
            name: "Llama-3.2-3B-Instruct-4bit",
            url: URL(string: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit/resolve/main/llama-3.2-3b-instruct-4bit.tar.gz")!,
            sha256: nil,
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "gemma-2b-mlx",
            name: "gemma-2b-it-4bit",
            url: URL(string: "https://huggingface.co/mlx-community/gemma-2b-it-4bit/resolve/main/gemma-2b-it-4bit.tar.gz")!,
            sha256: nil,
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "phi-3-mini-mlx",
            name: "phi-3-mini-4k-instruct-4bit",
            url: URL(string: "https://huggingface.co/mlx-community/phi-3-mini-4k-instruct-4bit/resolve/main/phi-3-mini-4k-instruct-4bit.tar.gz")!,
            sha256: nil,
            requiresUnzip: true
        ),
        ModelDownloadInfo(
            id: "qwen2-0.5b-mlx",
            name: "Qwen2-0.5B-Instruct-4bit",
            url: URL(string: "https://huggingface.co/mlx-community/Qwen2-0.5B-Instruct-4bit/resolve/main/qwen2-0.5b-instruct-4bit.tar.gz")!,
            sha256: nil,
            requiresUnzip: true
        )
    ]
    
    // MARK: - ONNX Runtime Models
    
    let onnxModels = [
        ModelDownloadInfo(
            id: "phi-3-mini-onnx",
            name: "phi3-mini-4k-instruct.onnx",
            url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32/phi3-mini-4k-instruct-cpu-int4-rtn-block-32.onnx")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "llama-2-7b-onnx",
            name: "llama-2-7b-chat.onnx",
            url: URL(string: "https://huggingface.co/microsoft/Llama-2-7b-chat-hf-onnx/resolve/main/Llama-2-7b-chat-hf-int8.onnx")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "gpt2-onnx",
            name: "gpt2.onnx",
            url: URL(string: "https://huggingface.co/onnx-community/gpt2/resolve/main/onnx/model.onnx")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "distilbert-onnx",
            name: "distilbert-base.onnx",
            url: URL(string: "https://huggingface.co/onnx-community/distilbert-base-uncased/resolve/main/model.onnx")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "t5-small-onnx",
            name: "t5-small.onnx",
            url: URL(string: "https://huggingface.co/onnx-community/t5-small/resolve/main/model.onnx")!,
            sha256: nil,
            requiresUnzip: false
        )
    ]
    
    // MARK: - TensorFlow Lite Models
    
    let tfliteModels = [
        ModelDownloadInfo(
            id: "gemma-2b-tflite",
            name: "gemma-2b-it.tflite",
            url: URL(string: "https://www.kaggle.com/api/v1/models/google/gemma/tfLite/gemma-2b-it-gpu-int4/1/download/gemma-2b-it-gpu-int4.tflite")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: true // Kaggle requires authentication
        ),
        ModelDownloadInfo(
            id: "mobilebert-tflite",
            name: "mobilebert.tflite",
            url: URL(string: "https://tfhub.dev/tensorflow/lite-model/mobilebert/1/default/1?lite-format=tflite")!,
            sha256: nil,
            requiresUnzip: false
        ),
        ModelDownloadInfo(
            id: "albert-lite-tflite",
            name: "albert_lite_base.tflite",
            url: URL(string: "https://tfhub.dev/tensorflow/lite-model/albert_lite_base/squadv1/1?lite-format=tflite")!,
            sha256: nil,
            requiresUnzip: false
        )
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
        ),
        TokenizerDownloadInfo(
            modelId: "llama",
            files: [
                TokenizerFile(
                    name: "tokenizer.model",
                    url: URL(string: "https://huggingface.co/meta-llama/Llama-2-7b-hf/resolve/main/tokenizer.model")!
                )
            ]
        )
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