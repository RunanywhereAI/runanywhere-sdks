import Foundation

// MARK: - Bundled Models Service

class BundledModelsService {
    static let shared = BundledModelsService()
    
    private init() {}
    
    // Pre-defined sample models that come with the app
    let bundledModels: [ModelInfo] = [
        // Tiny test models for each framework
        ModelInfo(
            id: "test-llama-tiny",
            name: "Tiny Test Model (llama.cpp)",
            format: .gguf,
            size: "5 MB",
            framework: .llamaCpp,
            quantization: "Q4_0",
            contextLength: 512,
            isLocal: true,
            description: "Ultra-small test model for llama.cpp framework testing"
        ),
        
        ModelInfo(
            id: "test-coreml-tiny",
            name: "Tiny Test Model (Core ML)",
            format: .coreML,
            size: "10 MB",
            framework: .coreML,
            quantization: "FP16",
            contextLength: 512,
            isLocal: true,
            description: "Small Core ML model for testing Apple Neural Engine"
        ),
        
        ModelInfo(
            id: "test-mlx-tiny",
            name: "Tiny Test Model (MLX)",
            format: .mlx,
            size: "8 MB",
            framework: .mlx,
            quantization: "INT4",
            contextLength: 512,
            isLocal: true,
            description: "Compact MLX model optimized for Apple Silicon"
        ),
        
        // Medium demo models
        ModelInfo(
            id: "demo-phi-mini",
            name: "Phi Mini Demo",
            format: .gguf,
            size: "150 MB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 2048,
            isLocal: false,
            downloadURL: URL(string: "https://huggingface.co/models/phi-mini-demo.gguf"),
            description: "Microsoft Phi mini model for demonstrations"
        ),
        
        ModelInfo(
            id: "demo-tinyllama",
            name: "TinyLlama 1.1B Demo",
            format: .gguf,
            size: "550 MB",
            framework: .llamaCpp,
            quantization: "Q5_K_M",
            contextLength: 2048,
            isLocal: false,
            downloadURL: URL(string: "https://huggingface.co/models/tinyllama-1.1b.gguf"),
            description: "Compact but capable language model"
        )
    ]
    
    // Copy bundled models to app's documents directory
    func installBundledModels() async throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDirectory = documentsURL.appendingPathComponent("Models")
        
        // Create models directory if it doesn't exist
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        for model in bundledModels where model.isLocal {
            let destinationURL = modelsDirectory.appendingPathComponent("\(model.id).\(model.format.fileExtension)")
            
            // Skip if already installed
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                continue
            }
            
            // In a real app, these files would be in the app bundle
            if let bundleURL = Bundle.main.url(forResource: model.id, withExtension: model.format.fileExtension) {
                try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
                
                // Update model path
                await ModelManager.shared.updateModelPath(modelId: model.id, path: destinationURL.path)
            }
        }
    }
    
    // Generate sample model files for testing
    func generateSampleModels() async throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDirectory = documentsURL.appendingPathComponent("Models")
        
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        // Generate tiny GGUF file
        let ggufModel = bundledModels.first { $0.id == "test-llama-tiny" }!
        try await generateGGUFSample(
            at: modelsDirectory.appendingPathComponent("\(ggufModel.id).gguf"),
            modelInfo: ggufModel
        )
        
        // Generate tiny Core ML model package
        let coreMLModel = bundledModels.first { $0.id == "test-coreml-tiny" }!
        try await generateCoreMLSample(
            at: modelsDirectory.appendingPathComponent("\(coreMLModel.id).mlpackage"),
            modelInfo: coreMLModel
        )
        
        // Generate tiny MLX model directory
        let mlxModel = bundledModels.first { $0.id == "test-mlx-tiny" }!
        try await generateMLXSample(
            at: modelsDirectory.appendingPathComponent(mlxModel.id),
            modelInfo: mlxModel
        )
    }
    
    private func generateGGUFSample(at url: URL, modelInfo: ModelInfo) async throws {
        // GGUF file format has a specific header
        var data = Data()
        
        // GGUF magic number
        data.append(contentsOf: [0x47, 0x47, 0x55, 0x46]) // "GGUF"
        
        // Version
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Array($0) })
        
        // Tensor count (simplified)
        data.append(contentsOf: withUnsafeBytes(of: UInt64(10).littleEndian) { Array($0) })
        
        // Metadata count
        data.append(contentsOf: withUnsafeBytes(of: UInt64(5).littleEndian) { Array($0) })
        
        // Add some mock metadata
        // This is a simplified version - real GGUF has complex metadata
        let metadata = [
            "general.architecture": "llama",
            "general.name": modelInfo.name,
            "general.quantization": modelInfo.quantization ?? "Q4_0",
            "llama.context_length": String(modelInfo.contextLength ?? 512),
            "llama.embedding_length": "128"
        ]
        
        // Add random data to reach target size (5MB)
        let targetSize = 5 * 1024 * 1024 // 5MB
        let randomData = Data((0..<targetSize).map { _ in UInt8.random(in: 0...255) })
        data.append(randomData)
        
        try data.write(to: url)
    }
    
    private func generateCoreMLSample(at url: URL, modelInfo: ModelInfo) async throws {
        // Create mlpackage directory structure
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        
        // Create manifest.json
        let manifest = [
            "fileFormatVersion": "1.0.0",
            "itemInfoEntries": [
                "model.mlmodel": [
                    "author": "com.runanywhere.ai",
                    "description": modelInfo.description ?? "Test Core ML model",
                    "name": modelInfo.name,
                    "path": "model.mlmodel"
                ]
            ],
            "rootModelIdentifier": "model.mlmodel"
        ] as [String: Any]
        
        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        try manifestData.write(to: url.appendingPathComponent("Manifest.json"))
        
        // Create a simple model file (mock)
        let modelData = Data((0..<1024 * 1024).map { _ in UInt8.random(in: 0...255) }) // 1MB
        try modelData.write(to: url.appendingPathComponent("model.mlmodel"))
    }
    
    private func generateMLXSample(at url: URL, modelInfo: ModelInfo) async throws {
        // Create MLX model directory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        
        // Create config.json
        let config = [
            "model_type": "mlx_lm",
            "hidden_size": 128,
            "num_hidden_layers": 4,
            "num_attention_heads": 4,
            "intermediate_size": 512,
            "vocab_size": 1000,
            "max_position_embeddings": modelInfo.contextLength ?? 512
        ] as [String: Any]
        
        let configData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try configData.write(to: url.appendingPathComponent("config.json"))
        
        // Create weights.npz (mock)
        let weightsData = Data((0..<1024 * 1024).map { _ in UInt8.random(in: 0...255) }) // 1MB
        try weightsData.write(to: url.appendingPathComponent("weights.npz"))
        
        // Create tokenizer.json (mock)
        let tokenizer = [
            "type": "BPE",
            "vocab_size": 1000,
            "unk_token": "<unk>",
            "bos_token": "<s>",
            "eos_token": "</s>"
        ] as [String: Any]
        
        let tokenizerData = try JSONSerialization.data(withJSONObject: tokenizer, options: .prettyPrinted)
        try tokenizerData.write(to: url.appendingPathComponent("tokenizer.json"))
    }
}

// MARK: - Model Info Extensions

extension ModelInfo {
    init(id: String, name: String, format: ModelFormat, size: String,
         framework: LLMFramework, quantization: String? = nil, contextLength: Int? = nil,
         isLocal: Bool = false, downloadURL: URL? = nil, description: String? = nil,
         minimumMemory: Int64 = 2_000_000_000,
         recommendedMemory: Int64 = 4_000_000_000) {
        self.id = id
        self.name = name
        self.format = format
        self.size = size
        self.framework = framework
        self.quantization = quantization
        self.contextLength = contextLength
        self.isLocal = isLocal
        self.path = nil
        self.downloadURL = downloadURL
        self.description = description ?? ""
        self.minimumMemory = minimumMemory
        self.recommendedMemory = recommendedMemory
    }
}

// MARK: - Model Format Extensions
