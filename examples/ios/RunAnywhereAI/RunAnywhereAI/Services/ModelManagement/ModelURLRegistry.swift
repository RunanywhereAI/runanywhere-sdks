import Foundation

// MARK: - Model URL Registry

/// Centralized registry for ALL model information across all frameworks
/// This is the SINGLE SOURCE OF TRUTH for model metadata, download URLs, and requirements
@MainActor
class ModelURLRegistry: ObservableObject {
    static let shared = ModelURLRegistry()
    
    private init() {}
    
    // MARK: - All Models by Framework
    // 📍 SINGLE SOURCE OF TRUTH: All model information is defined here
    // 🔄 To verify URLs: Run `./scripts/verify_urls.sh` from the project root
    
    // MARK: Foundation Models (Built-in iOS/macOS)
    private var _foundationModels: [ModelInfo] = [
        ModelInfo(
            id: "apple-intelligence-summary",
            name: "Apple Intelligence - Text Summarization",
            downloadURL: URL(string: "builtin://foundation-models/summarization"),
            format: .other,
            size: "Built-in",
            framework: .foundationModels,
            quantization: nil,
            contextLength: nil,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Built-in model for text summarization (iOS 18+)",
            modelType: .text,
            description: "Apple's built-in text summarization model",
            minimumMemory: 0,
            recommendedMemory: 0
        ),
        ModelInfo(
            id: "apple-intelligence-writing",
            name: "Apple Intelligence - Writing Tools",
            downloadURL: URL(string: "builtin://foundation-models/writing"),
            format: .other,
            size: "Built-in",
            framework: .foundationModels,
            quantization: nil,
            contextLength: nil,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Built-in model for writing assistance (iOS 18+)",
            modelType: .text,
            description: "Apple's built-in writing assistance model",
            minimumMemory: 0,
            recommendedMemory: 0
        )
    ]
    
    // MARK: Core ML Models
    private var _coreMLModels: [ModelInfo] = [
        ModelInfo(
            id: "stable-diffusion-coreml",
            name: "coreml-stable-diffusion-v1-5",
            downloadURL: URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_original_compiled.zip"),
            format: .mlPackage,
            size: "1.2GB",
            framework: .coreML,
            quantization: "Palettized",
            contextLength: nil,
            sha256: nil,
            requiresUnzip: true,
            requiresAuth: false,
            notes: "Image Generation Model - Text-to-Image support",
            modelType: .image,
            description: "Stable Diffusion v1.5 optimized for Core ML with palettization",
            minimumMemory: 2_000_000_000,
            recommendedMemory: 4_000_000_000
        ),
        ModelInfo(
            id: "gpt2-coreml",
            name: "gpt2.mlmodel",
            downloadURL: URL(string: "https://github.com/huggingface/swift-coreml-transformers/raw/master/Resources/gpt2.mlmodel"),
            format: .coreML,
            size: "150MB",
            framework: .coreML,
            quantization: "Float16",
            contextLength: 256,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "GPT-2 text generation model (124M params) - requires Git LFS",
            modelType: .text,
            description: "GPT-2 model converted to Core ML format with Neural Engine acceleration",
            minimumMemory: 300_000_000,
            recommendedMemory: 500_000_000
        ),
        ModelInfo(
            id: "gpt2-512-coreml",
            name: "gpt2-512.mlmodel",
            downloadURL: URL(string: "https://github.com/huggingface/swift-coreml-transformers/raw/master/Resources/gpt2-512.mlmodel"),
            format: .coreML,
            size: "646MB",
            framework: .coreML,
            quantization: "Float16",
            contextLength: 512,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "GPT-2 with 512 context length (646MB) - requires Git LFS",
            modelType: .text,
            description: "GPT-2 model with extended 512 token context",
            minimumMemory: 800_000_000,
            recommendedMemory: 1_200_000_000
        )
    ]
    
    // MARK: MLX Models
    private var _mlxModels: [ModelInfo] = [
        ModelInfo(
            id: "mistral-7b-mlx",
            name: "Mistral-7B-Instruct-v0.3-4bit",
            downloadURL: URL(string: "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.3-4bit/resolve/main/model.safetensors"),
            format: .safetensors,
            size: "3.8GB",
            framework: .mlx,
            quantization: "4-bit",
            contextLength: 32768,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            alternativeURLs: [],
            notes: "4-bit quantized MLX model. Use huggingface-cli for full download",
            modelType: .text,
            description: "Mistral 7B Instruct v0.3 - 4-bit quantized for MLX",
            minimumMemory: 4_000_000_000,
            recommendedMemory: 8_000_000_000
        ),
        ModelInfo(
            id: "phi-2-mlx",
            name: "phi-2",
            downloadURL: URL(string: "https://huggingface.co/mlx-community/phi-2/resolve/main/weights.npz"),
            format: .mlx,
            size: "2.7GB",
            framework: .mlx,
            quantization: "Float16",
            contextLength: 2048,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "MLX version of Phi-2 (note: requires config.json and tokenizer separately)",
            modelType: .text,
            description: "Microsoft Phi-2 2.7B parameter model for MLX",
            minimumMemory: 3_000_000_000,
            recommendedMemory: 6_000_000_000
        ),
        ModelInfo(
            id: "quantized-gemma-2b-mlx",
            name: "quantized-gemma-2b-it",
            downloadURL: URL(string: "https://huggingface.co/mlx-community/quantized-gemma-2b-it/resolve/main/model.safetensors"),
            format: .safetensors,
            size: "1.2GB",
            framework: .mlx,
            quantization: "4-bit",
            contextLength: 8192,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "4-bit quantized Gemma 2B MLX model - single file version",
            modelType: .text,
            description: "Google Gemma 2B instruction-tuned, 4-bit quantized",
            minimumMemory: 2_000_000_000,
            recommendedMemory: 4_000_000_000
        )
    ]
    
    // MARK: ONNX Runtime Models
    private var _onnxModels: [ModelInfo] = [
        ModelInfo(
            id: "phi-3-mini-onnx",
            name: "Phi-3-mini-4k-instruct-onnx",
            downloadURL: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32/phi3-mini-4k-instruct-cpu-int4-rtn-block-32.onnx"),
            format: .onnx,
            size: "236MB",
            framework: .onnxRuntime,
            quantization: "INT4",
            contextLength: 4096,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "CPU-optimized ONNX model with INT4 quantization",
            modelType: .text,
            description: "Microsoft Phi-3 Mini 4k - mobile optimized with INT4 quantization",
            minimumMemory: 500_000_000,
            recommendedMemory: 1_000_000_000
        ),
        ModelInfo(
            id: "phi-3-mini-128k-onnx",
            name: "Phi-3-mini-128k-instruct-onnx",
            downloadURL: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-128k-instruct-onnx/resolve/main/cpu_and_mobile/cpu-int4-rtn-block-32-acc-level-4/phi3-mini-128k-instruct-cpu-int4-rtn-block-32-acc-level-4.onnx"),
            format: .onnx,
            size: "236MB",
            framework: .onnxRuntime,
            quantization: "INT4",
            contextLength: 128000,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "CPU-optimized ONNX model with 128k context",
            modelType: .text,
            description: "Microsoft Phi-3 Mini 128k - extended context with INT4 quantization",
            minimumMemory: 500_000_000,
            recommendedMemory: 1_000_000_000
        ),
        ModelInfo(
            id: "phi-2-gguf",
            name: "phi-2.Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf"),
            format: .gguf,
            size: "1.6GB",
            framework: .llamaCpp, // Note: This is actually GGUF format, not ONNX
            quantization: "Q4_K_M",
            contextLength: 2048,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "No official ONNX version - using GGUF format instead",
            modelType: .text,
            description: "Microsoft Phi-2 in GGUF format (not ONNX)",
            minimumMemory: 2_000_000_000,
            recommendedMemory: 4_000_000_000
        )
    ]
    
    // MARK: TensorFlow Lite Models
    private var _tfliteModels: [ModelInfo] = [
        ModelInfo(
            id: "gemma-2b-tflite",
            name: "gemma-2b-it-gpu-int4.tar.gz",
            downloadURL: URL(string: "https://www.kaggle.com/models/google/gemma/tfLite/gemma-2b-it-gpu-int4/3/download"),
            format: .tflite,
            size: "1.35GB",
            framework: .tensorFlowLite,
            quantization: "INT4",
            contextLength: 8192,
            sha256: nil,
            requiresUnzip: true,
            requiresAuth: true,
            notes: "Requires Kaggle account for download",
            modelType: .text,
            description: "Google Gemma 2B instruction-tuned, GPU-optimized with INT4",
            minimumMemory: 2_000_000_000,
            recommendedMemory: 4_000_000_000
        ),
        ModelInfo(
            id: "mobilebert-tflite",
            name: "mobilebert_1_default_1.tflite",
            downloadURL: URL(string: "https://www.kaggle.com/models/google/mobilebert/tfLite/default"),
            format: .tflite,
            size: "100MB",
            framework: .tensorFlowLite,
            quantization: "Float16",
            contextLength: 512,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: true,
            notes: "Now hosted on Kaggle - requires authentication",
            modelType: .text,
            description: "MobileBERT - BERT optimized for mobile devices",
            minimumMemory: 200_000_000,
            recommendedMemory: 500_000_000
        ),
        ModelInfo(
            id: "efficientnet-lite-tflite",
            name: "efficientnet-lite0-int8.tflite",
            downloadURL: URL(string: "https://www.kaggle.com/models/tensorflow/efficientnet/tfLite/lite0-int8"),
            format: .tflite,
            size: "5MB",
            framework: .tensorFlowLite,
            quantization: "INT8",
            contextLength: nil,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: true,
            notes: "EfficientNet Lite - optimized for mobile. Kaggle account required",
            modelType: .image,
            description: "EfficientNet-Lite0 for image classification, INT8 quantized",
            minimumMemory: 50_000_000,
            recommendedMemory: 100_000_000
        )
    ]
    
    // MARK: llama.cpp Models (GGUF format)
    private var _llamaCppModels: [ModelInfo] = [
        ModelInfo(
            id: "tinyllama-1.1b-q4",
            name: "TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"),
            format: .gguf,
            size: "669MB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 2048,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Compact model perfect for testing",
            modelType: .text,
            description: "TinyLlama 1.1B Chat - compact yet capable model",
            minimumMemory: 1_000_000_000,
            recommendedMemory: 2_000_000_000
        ),
        ModelInfo(
            id: "phi-3-mini-q4",
            name: "Phi-3-mini-4k-instruct-q4.gguf",
            downloadURL: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf"),
            format: .gguf,
            size: "2.3GB",
            framework: .llamaCpp,
            quantization: "Q4",
            contextLength: 4096,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Microsoft's efficient model in GGUF format",
            modelType: .text,
            description: "Microsoft Phi-3 Mini 4k - efficient 3.8B parameter model",
            minimumMemory: 3_000_000_000,
            recommendedMemory: 4_000_000_000
        ),
        ModelInfo(
            id: "qwen2.5-0.5b-q5",
            name: "qwen2.5-0.5b-instruct-q5_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q5_k_m.gguf"),
            format: .gguf,
            size: "397MB",
            framework: .llamaCpp,
            quantization: "Q5_K_M",
            contextLength: 32768,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Ultra-lightweight model with good performance",
            modelType: .text,
            description: "Qwen 2.5 0.5B - ultra-lightweight with 32k context",
            minimumMemory: 600_000_000,
            recommendedMemory: 1_000_000_000
        ),
        ModelInfo(
            id: "qwen2.5-1.5b-q4",
            name: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"),
            format: .gguf,
            size: "999MB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 32768,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Balanced size and performance",
            modelType: .text,
            description: "Qwen 2.5 1.5B - balanced model with 32k context",
            minimumMemory: 1_500_000_000,
            recommendedMemory: 2_500_000_000
        ),
        ModelInfo(
            id: "llama-3.2-3b-gguf",
            name: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"),
            format: .gguf,
            size: "2.0GB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 128000,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Meta's latest small language model",
            modelType: .text,
            description: "Meta Llama 3.2 3B - latest generation with 128k context",
            minimumMemory: 3_000_000_000,
            recommendedMemory: 4_000_000_000
        ),
        ModelInfo(
            id: "mistral-7b-gguf",
            name: "mistral-7b-instruct-v0.2.Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf"),
            format: .gguf,
            size: "4.4GB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 32768,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Popular open-source model",
            modelType: .text,
            description: "Mistral 7B Instruct v0.2 - powerful open model",
            minimumMemory: 5_000_000_000,
            recommendedMemory: 8_000_000_000
        ),
        ModelInfo(
            id: "gemma-2b-gguf",
            name: "gemma-2b-it-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/lmstudio-ai/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_k_m.gguf"),
            format: .gguf,
            size: "1.5GB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 8192,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "Google's Gemma in GGUF format",
            modelType: .text,
            description: "Google Gemma 2B instruction-tuned in GGUF",
            minimumMemory: 2_000_000_000,
            recommendedMemory: 3_000_000_000
        ),
        ModelInfo(
            id: "stablelm-zephyr-3b-gguf",
            name: "stablelm-zephyr-3b.Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/TheBloke/stablelm-zephyr-3b-GGUF/resolve/main/stablelm-zephyr-3b.Q4_K_M.gguf"),
            format: .gguf,
            size: "1.8GB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 4096,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "StableLM Zephyr 3B - instruction-following model",
            modelType: .text,
            description: "Stability AI's StableLM Zephyr 3B",
            minimumMemory: 2_500_000_000,
            recommendedMemory: 4_000_000_000
        ),
        ModelInfo(
            id: "smollm-135m-gguf",
            name: "SmolLM-135M-Instruct.Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/QuantFactory/SmolLM-135M-Instruct-GGUF/resolve/main/SmolLM-135M-Instruct.Q4_K_M.gguf"),
            format: .gguf,
            size: "105MB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 2048,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "SmolLM 135M - Ultra-small language model",
            modelType: .text,
            description: "SmolLM 135M - Tiny but functional language model",
            minimumMemory: 200_000_000,
            recommendedMemory: 500_000_000
        ),
        ModelInfo(
            id: "smollm-360m-gguf",
            name: "SmolLM-360M-Instruct.Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/QuantFactory/SmolLM-360M-Instruct-GGUF/resolve/main/SmolLM-360M-Instruct.Q4_K_M.gguf"),
            format: .gguf,
            size: "270MB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 2048,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "SmolLM 360M - Small but capable model",
            modelType: .text,
            description: "SmolLM 360M - Balanced tiny model",
            minimumMemory: 500_000_000,
            recommendedMemory: 1_000_000_000
        ),
        ModelInfo(
            id: "smollm-1.7b-gguf",
            name: "SmolLM-1.7B-Instruct.Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/QuantFactory/SmolLM-1.7B-Instruct-GGUF/resolve/main/SmolLM-1.7B-Instruct.Q4_K_M.gguf"),
            format: .gguf,
            size: "1.03GB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 2048,
            sha256: nil,
            requiresUnzip: false,
            requiresAuth: false,
            notes: "SmolLM 1.7B - Larger variant",
            modelType: .text,
            description: "SmolLM 1.7B - Larger small language model",
            minimumMemory: 1_500_000_000,
            recommendedMemory: 2_500_000_000
        )
    ]
    
    // MARK: - Custom Models
    private var customModels: [ModelInfo] = []
    
    // MARK: - Computed Properties
    
    var foundationModels: [ModelInfo] { _foundationModels }
    var coreMLModels: [ModelInfo] { _coreMLModels }
    var mlxModels: [ModelInfo] { _mlxModels }
    var onnxModels: [ModelInfo] { _onnxModels }
    var tfliteModels: [ModelInfo] { _tfliteModels }
    var llamaCppModels: [ModelInfo] { _llamaCppModels }
    
    // MARK: - Public Methods
    
    /// Get all models for a specific framework
    func getAllModels(for framework: LLMFramework) -> [ModelInfo] {
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
    
    /// Get all models across all frameworks
    func getAllModels() -> [ModelInfo] {
        var allModels: [ModelInfo] = []
        allModels.append(contentsOf: foundationModels)
        allModels.append(contentsOf: coreMLModels)
        allModels.append(contentsOf: mlxModels)
        allModels.append(contentsOf: onnxModels)
        allModels.append(contentsOf: tfliteModels)
        allModels.append(contentsOf: llamaCppModels)
        allModels.append(contentsOf: customModels)
        return allModels
    }
    
    /// Get a specific model by ID
    func getModelInfo(id: String) -> ModelInfo? {
        getAllModels().first { $0.id == id }
    }
    
    /// Get models by type (text, image, etc)
    func getModels(ofType type: ModelType) -> [ModelInfo] {
        getAllModels().filter { $0.modelType == type }
    }
    
    /// Get models that support a specific context length
    func getModels(withMinContextLength minLength: Int) -> [ModelInfo] {
        getAllModels().filter { model in
            guard let contextLength = model.contextLength else { return false }
            return contextLength >= minLength
        }
    }
    
    /// Get models within a size range
    func getModels(maxSizeGB: Double) -> [ModelInfo] {
        getAllModels().filter { model in
            // Parse size string (e.g., "1.5GB", "150MB")
            let sizeStr = model.size.lowercased()
            if sizeStr.contains("gb") {
                let value = Double(sizeStr.replacingOccurrences(of: "gb", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                return value <= maxSizeGB
            } else if sizeStr.contains("mb") {
                let value = Double(sizeStr.replacingOccurrences(of: "mb", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                return (value / 1000.0) <= maxSizeGB
            }
            return false
        }
    }
    
    // MARK: - Custom Model Management
    
    func addCustomModel(_ model: ModelInfo) {
        customModels.append(model)
        objectWillChange.send()
    }
    
    func removeCustomModel(id: String) {
        customModels.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func getCustomModels() -> [ModelInfo] {
        customModels
    }
    
    // MARK: - Tokenizer Support
    
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
            modelId: "gpt2-coreml",
            files: [
                TokenizerFile(
                    name: "gpt2-vocab.json",
                    url: URL(string: "https://github.com/huggingface/swift-coreml-transformers/raw/master/Resources/gpt2-vocab.json")!
                ),
                TokenizerFile(
                    name: "gpt2-merges.txt",
                    url: URL(string: "https://github.com/huggingface/swift-coreml-transformers/raw/master/Resources/gpt2-merges.txt")!
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
    
    func getTokenizerFiles(for modelId: String) -> [TokenizerFile] {
        tokenizerFiles.first { $0.modelId == modelId }?.files ?? []
    }
    
    // MARK: - URL Validation
    
    func validateURLs(for framework: LLMFramework) async {
        var models = getAllModels(for: framework)
        
        for i in 0..<models.count {
            // Skip built-in models
            if models[i].isBuiltIn {
                models[i].isURLValid = true
                models[i].lastVerified = Date()
                continue
            }
            
            // Validate URL
            models[i].isURLValid = await validateURL(models[i].downloadURL)
            models[i].lastVerified = Date()
        }
        
        // Update the internal collections
        updateModelsCollection(for: framework, with: models)
    }
    
    private func validateURL(_ url: URL?) async -> Bool {
        guard let url = url else { return false }
        
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
    
    private func updateModelsCollection(for framework: LLMFramework, with models: [ModelInfo]) {
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
        
        objectWillChange.send()
    }
}

// MARK: - Supporting Types

struct TokenizerDownloadInfo: Codable {
    let modelId: String
    let files: [TokenizerFile]
}

struct TokenizerFile: Codable {
    let name: String
    let url: URL
}

// MARK: - Usage Notes

extension ModelURLRegistry {
    static let usageNotes = """
    MODEL URL REGISTRY - SINGLE SOURCE OF TRUTH
    
    This registry contains ALL model information for the entire app:
    - Download URLs and requirements
    - Model metadata (size, format, quantization)
    - Framework compatibility
    - Memory requirements
    - Context lengths
    
    To add a new model:
    1. Add it to the appropriate framework array above
    2. Include ALL ModelInfo fields
    3. Run ./scripts/verify_urls.sh to verify the URL works
    
    To use models in a service:
    1. Get models: ModelURLRegistry.shared.getAllModels(for: .yourFramework)
    2. No need to duplicate model definitions in services
    3. Services should focus on model loading/inference logic only
    """
}

// MARK: - Notification Extension

extension Notification.Name {
    static let modelURLsValidated = Notification.Name("modelURLsValidated")
}