//
//  ModelRepository.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation
import Combine

/// Model repository for managing LLM model downloads, caching, and lifecycle
class ModelRepository: ObservableObject {
    static let shared = ModelRepository()
    
    // MARK: - Published Properties
    @Published var availableModels: [ModelInfo] = []
    @Published var downloadedModels: [ModelInfo] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isRefreshing = false
    
    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let urlSession: URLSession
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Model directory structure
    private var modelsDirectory: URL {
        let documentsPath = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsPath.appendingPathComponent("Models")
    }
    
    // MARK: - Model Catalog
    private let modelCatalog = [
        ModelInfo(
            id: "llama-3.2-3b-instruct",
            name: "Llama 3.2 3B Instruct",
            format: .gguf,
            size: "1.7GB",
            framework: .llamaCpp,
            quantization: "Q4_K_M",
            contextLength: 8192,
            downloadURL: URL(string: "https://huggingface.co/TheBloke/Llama-3.2-3B-Instruct-GGUF/resolve/main/llama-3.2-3b-instruct.Q4_K_M.gguf")!
        ),
        ModelInfo(
            id: "mistral-7b-instruct",
            name: "Mistral 7B Instruct v0.3",
            format: .gguf,
            size: "3.8GB",
            framework: .llamaCpp,
            quantization: "Q4_0",
            contextLength: 32768,
            downloadURL: URL(string: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/mistral-7b-instruct-v0.3.Q4_0.gguf")!
        ),
        ModelInfo(
            id: "phi-3-mini-coreml",
            name: "Phi-3 Mini 4k",
            format: .coreML,
            size: "2.7GB",
            framework: .coreML,
            quantization: "INT4",
            contextLength: 4096,
            downloadURL: URL(string: "https://huggingface.co/apple/coreml-phi-3-mini/resolve/main/phi-3-mini-4k-instruct.mlpackage.zip")!
        ),
        ModelInfo(
            id: "tinyllama-1.1b",
            name: "TinyLlama 1.1B",
            format: .gguf,
            size: "640MB",
            framework: .llamaCpp,
            quantization: "Q5_K_M",
            contextLength: 2048,
            downloadURL: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q5_K_M.gguf")!
        ),
        ModelInfo(
            id: "qwen2.5-1.5b-mlx",
            name: "Qwen2.5 1.5B Instruct",
            format: .mlx,
            size: "900MB",
            framework: .mlx,
            quantization: "Q4_0",
            contextLength: 32768,
            downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit/resolve/main/model.safetensors")!
        )
    ]
    
    // MARK: - Initialization
    init() {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = false
        config.isDiscretionary = true
        urlSession = URLSession(configuration: config)
        
        setupModelDirectory()
        loadDownloadedModels()
    }
    
    // MARK: - Public Methods
    
    /// Refresh available models from catalog
    func refreshAvailableModels() {
        isRefreshing = true
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.availableModels = self.modelCatalog
            self.isRefreshing = false
        }
    }
    
    /// Download a model
    func downloadModel(_ model: ModelInfo) async throws -> URL {
        // Check if already downloaded
        if let existingPath = getModelPath(for: model),
           fileManager.fileExists(atPath: existingPath.path) {
            return existingPath
        }
        
        // Create download URL
        guard let downloadURL = model.downloadURL else {
            throw ModelError.invalidFile
        }
        
        // Create destination path
        let destinationPath = try createModelPath(for: model)
        
        // Start download
        return try await withCheckedThrowingContinuation { continuation in
            let task = urlSession.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: ModelError.downloadFailed)
                    return
                }
                
                do {
                    // Move file to destination
                    try self.fileManager.moveItem(at: tempURL, to: destinationPath)
                    
                    // Update downloaded models
                    DispatchQueue.main.async {
                        self.loadDownloadedModels()
                        self.downloadProgress[model.id] = nil
                    }
                    
                    continuation.resume(returning: destinationPath)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            // Track progress
            downloadTasks[model.id] = task
            observeDownloadProgress(for: task, modelId: model.id)
            
            task.resume()
        }
    }
    
    /// Cancel download
    func cancelDownload(for modelId: String) {
        downloadTasks[modelId]?.cancel()
        downloadTasks[modelId] = nil
        downloadProgress[modelId] = nil
    }
    
    /// Delete downloaded model
    func deleteModel(_ model: ModelInfo) throws {
        guard let modelPath = getModelPath(for: model) else {
            throw ModelError.invalidFile
        }
        
        try fileManager.removeItem(at: modelPath)
        loadDownloadedModels()
    }
    
    /// Get path for downloaded model
    func getModelPath(for model: ModelInfo) -> URL? {
        let frameworkDir = modelsDirectory.appendingPathComponent(model.framework.rawValue)
        let modelFile = frameworkDir.appendingPathComponent("\(model.id).\(model.format.fileExtension)")
        
        if fileManager.fileExists(atPath: modelFile.path) {
            return modelFile
        }
        
        return nil
    }
    
    /// Check if model is downloaded
    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        return getModelPath(for: model) != nil
    }
    
    /// Get storage size used by models
    func getStorageUsed() -> Int64 {
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
    
    /// Clear model cache
    func clearCache() throws {
        if fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.removeItem(at: modelsDirectory)
        }
        setupModelDirectory()
        loadDownloadedModels()
    }
    
    // MARK: - Private Methods
    
    private func setupModelDirectory() {
        try? fileManager.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
        
        // Create framework subdirectories
        for framework in LLMFramework.allCases {
            let frameworkDir = modelsDirectory.appendingPathComponent(framework.rawValue)
            try? fileManager.createDirectory(
                at: frameworkDir,
                withIntermediateDirectories: true
            )
        }
    }
    
    private func loadDownloadedModels() {
        var downloaded: [ModelInfo] = []
        
        for model in modelCatalog {
            if isModelDownloaded(model) {
                downloaded.append(model)
            }
        }
        
        DispatchQueue.main.async {
            self.downloadedModels = downloaded
        }
    }
    
    private func createModelPath(for model: ModelInfo) throws -> URL {
        let frameworkDir = modelsDirectory.appendingPathComponent(model.framework.rawValue)
        return frameworkDir.appendingPathComponent("\(model.id).\(model.format.fileExtension)")
    }
    
    private func observeDownloadProgress(for task: URLSessionDownloadTask, modelId: String) {
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress[modelId] = progress.fractionCompleted
            }
        }
        
        // Store observation
        observation.invalidate()
    }
}

// MARK: - Supporting Types

enum QuantizationType: String, Codable, CaseIterable {
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
    
    var displayName: String {
        rawValue
    }
}

// Using ModelError from ModelManager.swift

// DeviceRequirement removed - using ModelInfo's isCompatible property instead