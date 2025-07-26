//
//  ModelLoader.swift
//  RunAnywhereAI
//

import Foundation
import CoreML
import UniformTypeIdentifiers

// MARK: - Model Loader

@MainActor
class ModelLoader: ObservableObject {
    @MainActor static let shared = ModelLoader()
    
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var loadingStatus: String = ""
    @Published var error: Error?
    
    private let modelManager = ModelManager.shared
    private let memoryManager = MemoryManager.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    func loadModel(
        at path: String,
        format: ModelFormat,
        framework: LLMFramework
    ) async throws -> Bool {
        isLoading = true
        loadingProgress = 0
        loadingStatus = "Preparing to load model..."
        error = nil
        
        defer {
            isLoading = false
            loadingStatus = ""
        }
        
        do {
            // Verify file exists
            guard FileManager.default.fileExists(atPath: path) else {
                throw LLMError.modelNotFound
            }
            
            // Verify format
            try verifyModelFormat(at: path, expectedFormat: format)
            
            // Check memory availability
            let modelSize = try getModelSize(at: path)
            guard memoryManager.canLoadModel(estimatedSize: modelSize) else {
                throw LLMError.insufficientMemory
            }
            
            // Load model based on format
            switch format {
            case .gguf:
                return try await loadGGUFModel(at: path, framework: framework)
            case .onnx, .onnxRuntime:
                return try await loadONNXModel(at: path, framework: framework)
            case .coreML, .mlPackage:
                return try await loadCoreMLModel(at: path, framework: framework)
            case .mlx:
                return try await loadMLXModel(at: path, framework: framework)
            case .mlc:
                return try await loadMLCModel(at: path, framework: framework)
            case .pte:
                return try await loadPTEModel(at: path, framework: framework)
            case .tflite:
                return try await loadTFLiteModel(at: path, framework: framework)
            case .picoLLM:
                return try await loadPicoLLMModel(at: path, framework: framework)
            case .ggml:
                return try await loadGGUFModel(at: path, framework: framework) // Use GGUF loader for GGML
            case .pytorch, .safetensors, .other:
                throw LLMError.unsupportedFormat
            }
        } catch {
            self.error = error
            throw error
        }
    }
    
    // MARK: - Format-Specific Loaders
    
    private func loadGGUFModel(at path: String, framework: LLMFramework) async throws -> Bool {
        loadingStatus = "Loading GGUF model..."
        
        // Verify GGUF magic number
        guard isValidGGUFFile(at: path) else {
            throw LLMError.unsupportedFormat
        }
        
        // Parse GGUF metadata
        let metadata = try parseGGUFMetadata(at: path)
        updateProgress(0.3, status: "Parsed model metadata")
        
        // Verify compatibility with framework
        guard framework == .llamaCpp else {
            throw LLMError.inferenceError("GGUF models are only supported by llama.cpp")
        }
        
        // Initialize llama.cpp service
        let service = await UnifiedLLMService.shared.availableServices.first { $0.name == "llama.cpp" }
        guard let llamaService = service else {
            throw LLMError.serviceNotAvailable("llama.cpp")
        }
        
        updateProgress(0.5, status: "Initializing llama.cpp...")
        
        // Load model
        try await llamaService.initialize(modelPath: path)
        updateProgress(0.9, status: "Model loaded successfully")
        
        // Select the service
        await UnifiedLLMService.shared.selectService(named: llamaService.name)
        updateProgress(1.0, status: "Ready")
        
        return true
    }
    
    private func loadONNXModel(at path: String, framework: LLMFramework) async throws -> Bool {
        loadingStatus = "Loading ONNX model..."
        
        // Verify ONNX format
        guard path.hasSuffix(".onnxRuntime") else {
            throw LLMError.unsupportedFormat
        }
        
        updateProgress(0.2, status: "Verifying ONNX model...")
        
        // Verify compatibility
        guard framework == .onnxRuntime else {
            throw LLMError.inferenceError("ONNX models require ONNX Runtime framework")
        }
        
        // Initialize ONNX Runtime service
        let service = await UnifiedLLMService.shared.availableServices.first { $0.name == "ONNX Runtime" }
        guard let onnxService = service else {
            throw LLMError.serviceNotAvailable("ONNX Runtime")
        }
        
        updateProgress(0.5, status: "Initializing ONNX Runtime...")
        
        // Load model
        try await onnxService.initialize(modelPath: path)
        updateProgress(0.9, status: "Model loaded successfully")
        
        // Select the service
        await UnifiedLLMService.shared.selectService(named: onnxService.name)
        updateProgress(1.0, status: "Ready")
        
        return true
    }
    
    private func loadCoreMLModel(at path: String, framework: LLMFramework) async throws -> Bool {
        loadingStatus = "Loading Core ML model..."
        
        // Verify Core ML format
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" else {
            throw LLMError.unsupportedFormat
        }
        
        updateProgress(0.2, status: "Verifying Core ML model...")
        
        // Check iOS version
        guard #available(iOS 17.0, *) else {
            throw LLMError.frameworkNotSupported
        }
        
        // Verify compatibility
        guard framework == .coreML else {
            throw LLMError.inferenceError("Core ML models require Core ML framework")
        }
        
        // Try to compile model
        updateProgress(0.3, status: "Compiling Core ML model...")
        let compiledURL = try await compileMLModel(at: url)
        
        // Initialize Core ML service
        let service = await UnifiedLLMService.shared.availableServices.first { $0.name == "Core ML" }
        guard let coreMLService = service else {
            throw LLMError.serviceNotAvailable("Core ML")
        }
        
        updateProgress(0.6, status: "Initializing Core ML...")
        
        // Load model
        try await coreMLService.initialize(modelPath: compiledURL.path)
        updateProgress(0.9, status: "Model loaded successfully")
        
        // Select the service
        await UnifiedLLMService.shared.selectService(named: coreMLService.name)
        updateProgress(1.0, status: "Ready")
        
        return true
    }
    
    private func loadMLXModel(at path: String, framework: LLMFramework) async throws -> Bool {
        loadingStatus = "Loading MLX model..."
        
        // MLX models are typically directories with weight files
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LLMError.unsupportedFormat
        }
        
        updateProgress(0.2, status: "Verifying MLX model structure...")
        
        // Check for required files
        let requiredFiles = ["config.json", "model.safetensors"] // or "pytorch_model.bin"
        let url = URL(fileURLWithPath: path)
        
        for file in requiredFiles {
            let fileURL = url.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                // Check alternative formats
                if file == "model.safetensors" {
                    let altURL = url.appendingPathComponent("pytorch_model.bin")
                    if !FileManager.default.fileExists(atPath: altURL.path) {
                        throw LLMError.invalidModelPath
                    }
                }
            }
        }
        
        updateProgress(0.4, status: "Model structure verified")
        
        // Verify compatibility
        guard framework == .mlx else {
            throw LLMError.inferenceError("MLX models require MLX framework")
        }
        
        // Initialize MLX service
        let service = await UnifiedLLMService.shared.availableServices.first { $0.name == "MLX" }
        guard let mlxService = service else {
            throw LLMError.serviceNotAvailable("MLX")
        }
        
        updateProgress(0.6, status: "Initializing MLX...")
        
        // Load model
        try await mlxService.initialize(modelPath: path)
        updateProgress(0.9, status: "Model loaded successfully")
        
        // Select the service
        await UnifiedLLMService.shared.selectService(named: mlxService.name)
        updateProgress(1.0, status: "Ready")
        
        return true
    }
    
    private func loadMLCModel(at path: String, framework: LLMFramework) async throws -> Bool {
        // Similar implementation for MLC-LLM format
        throw LLMError.notImplemented
    }
    
    private func loadPTEModel(at path: String, framework: LLMFramework) async throws -> Bool {
        // Similar implementation for ExecuTorch PTE format
        throw LLMError.notImplemented
    }
    
    private func loadTFLiteModel(at path: String, framework: LLMFramework) async throws -> Bool {
        loadingStatus = "Loading TensorFlow Lite model..."
        
        // Verify TFLite format
        guard path.hasSuffix(".tflite") else {
            throw LLMError.unsupportedFormat
        }
        
        updateProgress(0.2, status: "Verifying TFLite model...")
        
        // Verify compatibility
        guard framework == .tensorFlowLite else {
            throw LLMError.inferenceError("TFLite models require TensorFlow Lite framework")
        }
        
        // Initialize TFLite service
        let service = await UnifiedLLMService.shared.availableServices.first { $0.name == "TensorFlow Lite" }
        guard let tfliteService = service else {
            throw LLMError.serviceNotAvailable("TensorFlow Lite")
        }
        
        updateProgress(0.5, status: "Initializing TensorFlow Lite...")
        
        // Load model
        try await tfliteService.initialize(modelPath: path)
        updateProgress(0.9, status: "Model loaded successfully")
        
        // Select the service
        await UnifiedLLMService.shared.selectService(named: tfliteService.name)
        updateProgress(1.0, status: "Ready")
        
        return true
    }
    
    private func loadPicoLLMModel(at path: String, framework: LLMFramework) async throws -> Bool {
        updateProgress(0.1, status: "Loading picoLLM model...")
        
        // Get service from UnifiedLLMService
        guard let service = await UnifiedLLMService.shared.availableServices.first(where: { $0.name == "picoLLM" }) else {
            throw LLMError.serviceNotAvailable("picoLLM")
        }
        
        // Load model
        try await service.initialize(modelPath: path)
        updateProgress(0.9, status: "Model loaded successfully")
        
        // Select the service
        await UnifiedLLMService.shared.selectService(named: service.name)
        updateProgress(1.0, status: "Ready")
        
        return true
    }
    
    // MARK: - Helper Methods
    
    private func verifyModelFormat(at path: String, expectedFormat: ModelFormat) throws {
        let url = URL(fileURLWithPath: path)
        
        switch expectedFormat {
        case .gguf:
            guard path.hasSuffix(".gguf") else {
                throw LLMError.unsupportedFormat
            }
        case .onnxRuntime:
            guard path.hasSuffix(".onnxRuntime") else {
                throw LLMError.unsupportedFormat
            }
        case .coreML:
            guard url.pathExtension == "mlpackage" || url.pathExtension == "mlmodel" else {
                throw LLMError.unsupportedFormat
            }
        case .mlx:
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw LLMError.unsupportedFormat
            }
        case .tflite:
            guard path.hasSuffix(".tflite") else {
                throw LLMError.unsupportedFormat
            }
        default:
            break
        }
    }
    
    private func getModelSize(at path: String) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        var totalSize: Int64 = 0
        
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            // Calculate directory size
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
        } else {
            // Single file
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            if let fileSize = attributes[.size] as? Int64 {
                totalSize = fileSize
            }
        }
        
        return totalSize
    }
    
    private func updateProgress(_ progress: Double, status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.loadingProgress = progress
            self?.loadingStatus = status
        }
    }
    
    // MARK: - GGUF Parsing
    
    private func isValidGGUFFile(at path: String) -> Bool {
        guard let file = FileHandle(forReadingAtPath: path) else {
            return false
        }
        defer { file.closeFile() }
        
        // GGUF magic number: "GGUF" (0x46554747 in little-endian)
        let magicData = file.readData(ofLength: 4)
        guard magicData.count == 4 else { return false }
        
        let magic = magicData.withUnsafeBytes { buffer in
            buffer.load(as: UInt32.self)
        }
        
        return magic == 0x46554747
    }
    
    private func parseGGUFMetadata(at path: String) throws -> [String: Any] {
        // Simplified GGUF header parsing
        // In real implementation, would parse the full GGUF header structure
        
        guard let file = FileHandle(forReadingAtPath: path) else {
            throw LLMError.invalidModelPath
        }
        defer { file.closeFile() }
        
        // Skip magic number (already verified)
        file.seek(toFileOffset: 4)
        
        // Read version
        let versionData = file.readData(ofLength: 4)
        let version = versionData.withUnsafeBytes { buffer in
            buffer.load(as: UInt32.self)
        }
        
        return [
            "version": version,
            "format": "GGUF",
            "verified": true
        ]
    }
    
    // MARK: - Core ML Compilation
    
    @available(iOS 17.0, *)
    private func compileMLModel(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            MLModel.compileModel(at: url) { result in
                switch result {
                case .success(let compiledURL):
                    continuation.resume(returning: compiledURL)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
