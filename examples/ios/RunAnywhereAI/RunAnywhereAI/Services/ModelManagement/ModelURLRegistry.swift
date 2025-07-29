import Foundation

// MARK: - Model URL Registry

/// Centralized registry for all model download URLs
/// This provides a single place to manage and update model URLs
@MainActor
class ModelURLRegistry: ObservableObject {
    static let shared = ModelURLRegistry()

    private init() {}

    // MARK: - Foundation Models (Built-in iOS/macOS)
    // 📍 These models use Apple's built-in Foundation Models framework
    // ✅ No download required - available directly on device
    // 💡 Requires iOS 18.0+ or macOS 15.0+

    private var _foundationModels: [ModelDownloadInfo] = [
        // Note: Foundation Models are built into the OS, so no download URLs needed
        // These entries are for UI purposes to show available models
        ModelDownloadInfo(
            id: "apple-intelligence-summary",
            name: "Apple Intelligence - Text Summarization",
            url: URL(string: "builtin://foundation-models/summarization")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Built-in model for text summarization (iOS 18+)"
        ),
        ModelDownloadInfo(
            id: "apple-intelligence-writing",
            name: "Apple Intelligence - Writing Tools",
            url: URL(string: "builtin://foundation-models/writing")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Built-in model for writing assistance (iOS 18+)"
        )
    ]

    // MARK: - Core ML Models
    // 📍 SINGLE SOURCE OF TRUTH: All URLs in this file are verified by scripts/verify_urls.sh
    // 🔄 To verify URLs: Run `./scripts/verify_urls.sh` from the project root
    // ⚠️  Most Core ML models need conversion from PyTorch/TensorFlow
    // 💡 Use: python3 -m exporters.coreml --model=model-name exported/

    private var _coreMLModels: [ModelDownloadInfo] = [
        // Note: Most Core ML models need to be converted from PyTorch/TensorFlow
        // Use the exporters tool: python3 -m exporters.coreml --model=gpt2 exported/
        ModelDownloadInfo(
            id: "stable-diffusion-coreml",
            name: "coreml-stable-diffusion-v1-5",
            url: URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_original_compiled.zip")!,
            sha256: nil,
            requiresUnzip: true,
            requiresAuth: false,
            notes: "Image Generation Model - Text-to-Image support coming soon!",
            modelType: .image
        ),
        ModelDownloadInfo(
            id: "openelm-270m-coreml",
            name: "OpenELM-270M-CoreML",
            url: URL(string: "https://unavailable-url.example.com/openelm-270m.mlpackage")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Original URL not available. Use 'Add Custom URL' to provide an alternative download link."
        )
    ]

    // MARK: - MLX Models
    // 📍 SINGLE SOURCE OF TRUTH: Verified by scripts/verify_urls.sh
    // ⚠️  MLX models require multiple files (weights, config.json, tokenizer)
    // 💡 Best downloaded with: huggingface-cli download --local-dir model-name mlx-community/model-name

    private var _mlxModels: [ModelDownloadInfo] = [
        // MLX models require multiple files. Best to use git clone or huggingface-cli
        // Example: huggingface-cli download --local-dir model-name mlx-community/model-name
        ModelDownloadInfo(
            id: "mistral-7b-mlx",
            name: "Mistral-7B-Instruct-v0.3-4bit",
            url: URL(string: "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.3-4bit/resolve/main/model.safetensors")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            alternativeURLs: [],
            notes: "4-bit quantized MLX model. Use huggingface-cli for full download"
        ),
        ModelDownloadInfo(
            id: "phi-2-mlx",
            name: "phi-2",
            url: URL(string: "https://huggingface.co/mlx-community/phi-2/resolve/main/weights.npz")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "MLX version of Phi-2 (note: requires config.json and tokenizer separately)"
        ),
        ModelDownloadInfo(
            id: "quantized-gemma-2b-mlx",
            name: "quantized-gemma-2b-it",
            url: URL(string: "https://huggingface.co/mlx-community/quantized-gemma-2b-it/resolve/main/model.safetensors")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "4-bit quantized Gemma 2B MLX model - single file version"
        )
    ]

    // MARK: - ONNX Runtime Models
    // 📍 SINGLE SOURCE OF TRUTH: Verified by scripts/verify_urls.sh
    // ✅ Microsoft provides excellent mobile-optimized versions
    // 💡 Look for "cpu-int4" variants for best mobile performance

    private var _onnxModels: [ModelDownloadInfo] = [
        ModelDownloadInfo(
            id: "phi-3-mini-onnx",
            name: "Phi-3-mini-4k-instruct-onnx",
            url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32/phi3-mini-4k-instruct-cpu-int4-rtn-block-32.onnx")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "phi-3-mini-128k-onnx",
            name: "Phi-3-mini-128k-instruct-onnx",
            url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-128k-instruct-onnx/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32-acc-level-4/phi3-mini-128k-instruct-cpu-int4-rtn-block-32-acc-level-4.onnx")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "CPU-optimized ONNX model"
        ),
        ModelDownloadInfo(
            id: "phi-2-gguf",
            name: "phi-2.Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "No official ONNX version - using GGUF format instead"
        )
    ]

    // MARK: - TensorFlow Lite Models
    // 📍 SINGLE SOURCE OF TRUTH: Verified by scripts/verify_urls.sh
    // ⚠️  Many models now require Kaggle authentication
    // 🔄 Alternative: Convert from TensorFlow models yourself

    private var _tfliteModels: [ModelDownloadInfo] = [
        ModelDownloadInfo(
            id: "gemma-2b-tflite",
            name: "gemma-2b-it-gpu-int4.tar.gz",
            url: URL(string: "https://www.kaggle.com/models/google/gemma/tfLite/gemma-2b-it-gpu-int4/3/download")!,
            sha256: nil,
            requiresUnzip: true,
            requiresAuth: true, // Requires Kaggle account
            alternativeURLs: []
        ),
        ModelDownloadInfo(
            id: "mobilebert-tflite",
            name: "mobilebert_1_default_1.tflite",
            url: URL(string: "https://www.kaggle.com/models/google/mobilebert/tfLite/default")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: true,
            notes: "Now hosted on Kaggle - requires authentication"
        ),
        ModelDownloadInfo(
            id: "efficientnet-lite-tflite",
            name: "efficientnet-lite0-int8.tflite",
            url: URL(string: "https://www.kaggle.com/models/tensorflow/efficientnet/tfLite/lite0-int8")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: true,
            notes: "EfficientNet Lite - optimized for mobile. Kaggle account required"
        )
    ]

    // MARK: - llama.cpp Models (GGUF format)
    // 📍 SINGLE SOURCE OF TRUTH: Verified by scripts/verify_urls.sh
    // ✅ Most reliable format for direct download
    // 💡 Single file contains everything needed - no additional files required

    private var _llamaCppModels: [ModelDownloadInfo] = [
        ModelDownloadInfo(
            id: "tinyllama-1.1b-q4",
            name: "TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "phi-3-mini-q4",
            name: "Phi-3-mini-4k-instruct-q4.gguf",
            url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "qwen2.5-0.5b-q5",
            name: "qwen2.5-0.5b-instruct-q5_k_m.gguf",
            url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q5_k_m.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "qwen2.5-1.5b-q4",
            name: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "llama-3.2-3b-gguf",
            name: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/lmstudio-community/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "mistral-7b-gguf",
            name: "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "gemma-2b-gguf",
            name: "gemma-2b-it-q4_k_m.gguf",
            url: URL(string: "https://huggingface.co/lmstudio-ai/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_k_m.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
        ),
        ModelDownloadInfo(
            id: "stablelm-zephyr-3b-gguf",
            name: "stablelm-zephyr-3b.Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/TheBloke/stablelm-zephyr-3b-GGUF/resolve/main/stablelm-zephyr-3b.Q4_K_M.gguf")!,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false
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
            modelId: "phi-3",
            files: [
                TokenizerFile(
                    name: "tokenizer.json",
                    url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct/resolve/main/tokenizer.json")!
                ),
                TokenizerFile(
                    name: "tokenizer_config.json",
                    url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct/resolve/main/tokenizer_config.json")!
                )
            ]
        ),
        TokenizerDownloadInfo(
            modelId: "llama",
            files: [
                TokenizerFile(
                    name: "tokenizer.json",
                    url: URL(string: "https://huggingface.co/meta-llama/Llama-2-7b-hf/resolve/main/tokenizer.json")!
                ),
                TokenizerFile(
                    name: "tokenizer_config.json",
                    url: URL(string: "https://huggingface.co/meta-llama/Llama-2-7b-hf/resolve/main/tokenizer_config.json")!
                )
            ]
        )
    ]

    // MARK: - Computed Properties

    var foundationModels: [ModelDownloadInfo] { _foundationModels }
    var coreMLModels: [ModelDownloadInfo] { _coreMLModels }
    var mlxModels: [ModelDownloadInfo] { _mlxModels }
    var onnxModels: [ModelDownloadInfo] { _onnxModels }
    var tfliteModels: [ModelDownloadInfo] { _tfliteModels }
    var llamaCppModels: [ModelDownloadInfo] { _llamaCppModels }

    // MARK: - Convenience Methods

    func getAllModels(for framework: LLMFramework) -> [ModelDownloadInfo] {
        switch framework {
        case .foundationModels:
            return foundationModels
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
        let allModels = foundationModels + coreMLModels + mlxModels + onnxModels + tfliteModels + llamaCppModels + customModels
        return allModels.first { $0.id == id }
    }

    func getTokenizerFiles(for modelId: String) -> [TokenizerFile] {
        tokenizerFiles.first { $0.modelId == modelId }?.files ?? []
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
        customModels
    }
}

// MARK: - Supporting Types

struct ModelDownloadInfo: Codable, Identifiable {
    let id: String
    let name: String
    let url: URL
    let sha256: String?
    let requiresUnzip: Bool
    let requiresAuth: Bool
    let alternativeURLs: [URL]
    let notes: String?
    let modelType: ModelType

    // Runtime properties (not encoded)
    var isURLValid: Bool = true
    var lastVerified: Date?
    var isBuiltIn: Bool { url.scheme == "builtin" }
    var isUnavailable: Bool { !isURLValid && !isBuiltIn && !requiresAuth }

    init(id: String, name: String, url: URL, sha256: String? = nil, requiresUnzip: Bool, requiresAuth: Bool = false, alternativeURLs: [URL] = [], notes: String? = nil, modelType: ModelType = .text) {
        self.id = id
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.requiresUnzip = requiresUnzip
        self.requiresAuth = requiresAuth
        self.alternativeURLs = alternativeURLs
        self.notes = notes
        self.modelType = modelType
    }

    // Custom Codable implementation to exclude runtime properties
    enum CodingKeys: String, CodingKey {
        case id, name, url, sha256, requiresUnzip, requiresAuth, alternativeURLs, notes, modelType
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
            "foundationModels": foundationModels,
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

    // MARK: - URL Validation

    /// Validate URLs for a specific framework
    func validateURLs(for framework: LLMFramework) async {
        var models = getAllModels(for: framework)

        for i in 0..<models.count {
            // Skip built-in models
            if models[i].isBuiltIn {
                models[i].isURLValid = true
                models[i].lastVerified = Date()
                continue
            }

            // Mark example/unavailable URLs as invalid
            if models[i].url.host?.contains("example.com") == true ||
                models[i].url.host?.contains("unavailable-url") == true {
                models[i].isURLValid = false
                models[i].lastVerified = Date()
                continue
            }

            // Skip Kaggle URLs that require auth
            if models[i].requiresAuth && models[i].url.host?.contains("kaggle") == true {
                models[i].isURLValid = true // Assume valid since auth is expected
                models[i].lastVerified = Date()
                continue
            }

            // Validate HTTP/HTTPS URLs
            models[i].isURLValid = await validateURL(models[i].url)
            models[i].lastVerified = Date()
        }

        // Update the internal collections
        updateModelsCollection(for: framework, with: models)
    }

    /// Validate all URLs across all frameworks
    func validateAllURLs() async {
        await withTaskGroup(of: Void.self) { group in
            for framework in LLMFramework.availableFrameworks {
                group.addTask {
                    await self.validateURLs(for: framework)
                }
            }
        }
    }

    private func validateURL(_ url: URL) async -> Bool {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10
            request.setValue("RunAnywhereAI-URLVerifier/1.0", forHTTPHeaderField: "User-Agent")

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200 || httpResponse.statusCode == 302
            }
            return false
        } catch {
            print("URL validation failed for \(url): \(error)")
            return false
        }
    }

    private func updateModelsCollection(for framework: LLMFramework, with models: [ModelDownloadInfo]) {
        switch framework {
        case .foundationModels:
            _foundationModels = models
        case .coreML:
            _coreMLModels = models
        case .mlx:
            _mlxModels = models
        case .onnxRuntime:
            _onnxModels = models
        case .tensorFlowLite:
            _tfliteModels = models
        case .llamaCpp:
            _llamaCppModels = models
        default:
            break
        }

        // Notify UI of validation completion
        NotificationCenter.default.post(name: .modelURLsValidated, object: nil, userInfo: [
            "framework": framework,
            "validatedModels": models
        ])
    }

    /// Important Notes for Users
    static let usageNotes = """
    IMPORTANT NOTES:

    1. Core ML Models:
       - Most models need conversion from PyTorch/TensorFlow
       - Use: python3 -m exporters.coreml --model=model-name exported/
       - Apple provides limited pre-converted models

    2. MLX Models:
       - Require multiple files (weights, config.json, tokenizer)
       - Best downloaded using: huggingface-cli download --local-dir model-name mlx-community/model-name
       - Or use mlx-lm directly: mlx_lm.generate --model mlx-community/model-name

    3. ONNX Models:
       - Microsoft provides good mobile-optimized versions
       - Look for "cpu-int4" variants for best mobile performance

    4. TensorFlow Lite:
       - Many require Kaggle account for download
       - Alternative: convert from TensorFlow models

    5. GGUF (llama.cpp):
       - Most reliable format for direct download
       - Single file contains everything needed
       - TheBloke and other quantizers provide many options
    """
}

// MARK: - Notification Extension

extension Notification.Name {
    static let modelURLsValidated = Notification.Name("modelURLsValidated")
}
