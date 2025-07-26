//
//  ModelManager.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

// MARK: - Model Errors

enum ModelError: LocalizedError {
    case insufficientSpace
    case downloadFailed
    case invalidFile
    case unsupportedFormat
    case verificationFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientSpace:
            return "Not enough storage space to download the model"
        case .downloadFailed:
            return "Failed to download the model"
        case .invalidFile:
            return "The downloaded file is invalid or corrupted"
        case .unsupportedFormat:
            return "This model format is not supported"
        case .verificationFailed:
            return "Model verification failed"
        }
    }
}

// MARK: - Download Delegate

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: (Double) -> Void
    
    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
        super.init()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            progressHandler(progress)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled in the async download method
    }
}

// MARK: - Model Manager

@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    @Published var downloadedModels: [ModelInfo] = []
    @Published var availableModels: [ModelInfo] = []
    
    static let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    static let modelsDirectory = documentsDirectory.appendingPathComponent("Models")
    
    private init() {
        // Create models directory if it doesn't exist
        try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
        
        // Load bundled models
        Task {
            await loadBundledModels()
            await refreshModelList()
        }
    }
    
    func modelPath(for modelName: String) -> URL {
        Self.modelsDirectory.appendingPathComponent(modelName)
    }
    
    func isModelDownloaded(_ modelName: String) -> Bool {
        let path = modelPath(for: modelName)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    func downloadModel(
        from url: URL,
        modelName: String,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = modelPath(for: modelName)
        
        // If model already exists, return its path
        if isModelDownloaded(modelName) {
            progress(1.0)
            return destination
        }
        
        // Check available space
        let availableSpace = getAvailableSpace()
        guard availableSpace > 5_000_000_000 else { // Require at least 5GB free
            throw ModelError.insufficientSpace
        }
        
        // Create URLSession with delegate for progress tracking
        let delegate = DownloadDelegate(progressHandler: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        
        do {
            let (tempURL, response) = try await session.download(from: url)
            
            // Verify response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ModelError.downloadFailed
            }
            
            // Verify file exists and has content
            let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                throw ModelError.invalidFile
            }
            
            // Move to final destination
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            
            progress(1.0)
            return destination
        } catch {
            // Clean up partial download if exists
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    
    func deleteModel(_ modelName: String) throws {
        let path = modelPath(for: modelName)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
    
    func listDownloadedModels() -> [String] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: Self.modelsDirectory,
                includingPropertiesForKeys: nil
            )
            return contents.map { $0.lastPathComponent }
        } catch {
            return []
        }
    }
    
    func getModelSize(_ modelName: String) -> Int64? {
        let path = modelPath(for: modelName)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    func getAvailableSpace() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(
                forPath: Self.documentsDirectory.path
            )
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // MARK: - Bundled Models Integration
    
    func loadBundledModels() async {
        // Add bundled models to available models
        availableModels = BundledModelsService.shared.bundledModels
        
        // Generate sample models if in debug mode
        #if DEBUG
        do {
            try await BundledModelsService.shared.generateSampleModels()
        } catch {
            print("Failed to generate sample models: \(error)")
        }
        #endif
    }
    
    func refreshModelList() async {
        // Get all downloaded models
        var models: [ModelInfo] = []
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: Self.modelsDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            
            for url in contents {
                // Skip hidden files
                if url.lastPathComponent.hasPrefix(".") { continue }
                
                // Determine model info from file
                if let modelInfo = await createModelInfo(from: url) {
                    models.append(modelInfo)
                }
            }
        } catch {
            print("Error listing models: \(error)")
        }
        
        downloadedModels = models
    }
    
    private func createModelInfo(from url: URL) async -> ModelInfo? {
        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        
        // Try to match with bundled models first
        if let bundled = availableModels.first(where: { $0.id == url.deletingPathExtension().lastPathComponent }) {
            var model = bundled
            model.path = url.path
            model.isLocal = true
            return model
        }
        
        // Create new model info from file
        let format = ModelFormat.from(extension: fileExtension)
        let framework = LLMFramework.forFormat(format)
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0
        let sizeString = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        
        return ModelInfo(
            id: UUID().uuidString,
            name: fileName,
            path: url.path,
            format: format,
            size: sizeString,
            framework: framework,
            isLocal: true
        )
    }
    
    func updateModelPath(modelId: String, path: String) async {
        if let index = downloadedModels.firstIndex(where: { $0.id == modelId }) {
            downloadedModels[index].path = path
        }
    }
    
    func addImportedModel(_ model: ModelInfo) async {
        downloadedModels.append(model)
    }
    
    // MARK: - Model Verification
    
    func verifyModel(at path: URL, format: ModelFormat) throws {
        // Verify file exists and has content
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
            throw ModelError.invalidFile
        }
        
        // Format-specific verification
        switch format {
        case .gguf:
            try verifyGGUFModel(at: path)
        case .coreML:
            try verifyCoreMLModel(at: path)
        case .onnx:
            try verifyONNXModel(at: path)
        case .mlx:
            try verifyMLXModel(at: path)
        default:
            // Basic verification passed
            break
        }
    }
    
    private func verifyGGUFModel(at url: URL) throws {
        guard let file = FileHandle(forReadingAtPath: url.path) else {
            throw ModelError.invalidFile
        }
        defer { file.closeFile() }
        
        // Read GGUF magic number
        let magicData = file.readData(ofLength: 4)
        guard magicData.count == 4 else {
            throw ModelError.verificationFailed
        }
        
        let magic = magicData.withUnsafeBytes { buffer in
            buffer.load(as: UInt32.self)
        }
        
        // GGUF magic: "GGUF" (0x46554747 in little-endian)
        guard magic == 0x46554747 else {
            throw ModelError.verificationFailed
        }
    }
    
    private func verifyCoreMLModel(at url: URL) throws {
        // For .mlpackage, check if it's a valid directory
        if url.pathExtension == "mlpackage" {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ModelError.verificationFailed
            }
            
            // Check for required files
            let manifestPath = url.appendingPathComponent("Manifest.json")
            guard FileManager.default.fileExists(atPath: manifestPath.path) else {
                throw ModelError.verificationFailed
            }
        }
    }
    
    private func verifyONNXModel(at url: URL) throws {
        // Basic check for ONNX file
        guard url.pathExtension == "onnx" else {
            throw ModelError.unsupportedFormat
        }
        
        // Could add more sophisticated ONNX protobuf verification here
    }
    
    private func verifyMLXModel(at url: URL) throws {
        // MLX models are typically directories with weights
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ModelError.verificationFailed
        }
        
        // Check for config file
        let configPath = url.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw ModelError.verificationFailed
        }
    }
    
    // MARK: - Model Import
    
    func importModel(from sourceURL: URL, as modelName: String, format: ModelFormat) async throws -> URL {
        let destination = modelPath(for: modelName)
        
        // Start accessing security-scoped resource if needed
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Verify the model before copying
        try verifyModel(at: sourceURL, format: format)
        
        // Copy to app's model directory
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        
        return destination
    }
}
