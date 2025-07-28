//
//  ModelManager.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
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

    func modelPath(for modelName: String, framework: LLMFramework? = nil) -> URL {
        if let framework = framework {
            return Self.modelsDirectory
                .appendingPathComponent(framework.displayName)
                .appendingPathComponent(modelName)
        }
        return Self.modelsDirectory.appendingPathComponent(modelName)
    }

    func isModelDownloaded(_ modelName: String, framework: LLMFramework? = nil) -> Bool {
        // Check with framework subdirectory first
        if let framework = framework {
            let frameworkPath = Self.modelsDirectory
                .appendingPathComponent(framework.displayName)
                .appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: frameworkPath.path) {
                return true
            }
        }
        
        // Check all framework directories
        do {
            let frameworkDirs = try FileManager.default.contentsOfDirectory(
                at: Self.modelsDirectory,
                includingPropertiesForKeys: nil
            )
            
            for frameworkDir in frameworkDirs {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: frameworkDir.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    let modelPath = frameworkDir.appendingPathComponent(modelName)
                    if FileManager.default.fileExists(atPath: modelPath.path) {
                        return true
                    }
                }
            }
        } catch {
            print("Error checking for downloaded models: \(error)")
        }
        
        // Legacy check - direct path
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

    func deleteModel(_ modelName: String, framework: LLMFramework? = nil) throws {
        // Try framework-specific path first
        if let framework = framework {
            let frameworkPath = Self.modelsDirectory
                .appendingPathComponent(framework.displayName)
                .appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: frameworkPath.path) {
                try FileManager.default.removeItem(at: frameworkPath)
                return
            }
        }
        
        // Try all framework directories
        do {
            let frameworkDirs = try FileManager.default.contentsOfDirectory(
                at: Self.modelsDirectory,
                includingPropertiesForKeys: nil
            )
            
            for frameworkDir in frameworkDirs {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: frameworkDir.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    let modelPath = frameworkDir.appendingPathComponent(modelName)
                    if FileManager.default.fileExists(atPath: modelPath.path) {
                        try FileManager.default.removeItem(at: modelPath)
                        return
                    }
                }
            }
        } catch {
            print("Error searching for model to delete: \(error)")
        }
        
        // Legacy path
        let path = modelPath(for: modelName)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
    
    func verifyModelExists(_ modelName: String, framework: LLMFramework? = nil) -> Bool {
        return isModelDownloaded(modelName, framework: framework)
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
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        // This is a framework directory, check for models inside
                        let frameworkName = url.lastPathComponent
                        if let framework = LLMFramework.allCases.first(where: { $0.displayName == frameworkName }) {
                            let frameworkContents = try FileManager.default.contentsOfDirectory(
                                at: url,
                                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
                            )
                            
                            for modelURL in frameworkContents {
                                if modelURL.lastPathComponent.hasPrefix(".") { continue }
                                if let modelInfo = await createModelInfo(from: modelURL, framework: framework) {
                                    models.append(modelInfo)
                                }
                            }
                        }
                    } else {
                        // Legacy: direct file in Models directory
                        if let modelInfo = await createModelInfo(from: url) {
                            models.append(modelInfo)
                        }
                    }
                }
            }
        } catch {
            print("Error listing models: \(error)")
        }

        // Update the isLocal property for available models
        for i in 0..<availableModels.count {
            let modelName = availableModels[i].name
            let framework = availableModels[i].framework
            availableModels[i].isLocal = isModelDownloaded(modelName, framework: framework)
        }

        downloadedModels = models
    }

    private func createModelInfo(from url: URL, framework: LLMFramework? = nil) async -> ModelInfo? {
        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension

        // Try to match with bundled models first
        if let bundled = availableModels.first(where: { 
            $0.name == fileName || 
            $0.id == url.deletingPathExtension().lastPathComponent ||
            isModelNameMatch($0.name, fileName)
        }) {
            var model = bundled
            model.path = url.path
            model.isLocal = true
            model.downloadedFileName = fileName
            return model
        }

        // Create new model info from file
        let format = ModelFormat.from(extension: fileExtension)
        let inferredFramework = framework ?? LLMFramework.forFormat(format)

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0
        let sizeString = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

        // Try to find model type from registry
        let registry = ModelURLRegistry.shared
        var modelType: ModelType = .text
        if let downloadInfo = registry.getModelInfo(id: fileName) {
            modelType = downloadInfo.modelType
        } else if let frameworkInfo = framework {
            // Check all models in this framework for a match
            let frameworkModels = registry.getAllModels(for: frameworkInfo)
            if let matchingModel = frameworkModels.first(where: { 
                isModelNameMatch($0.name, fileName) 
            }) {
                modelType = matchingModel.modelType
            }
        }

        return ModelInfo(
            id: UUID().uuidString,
            name: fileName,
            path: url.path,
            format: format,
            size: sizeString,
            framework: inferredFramework,
            isLocal: true,
            downloadedFileName: fileName,
            modelType: modelType
        )
    }
    
    private func isModelNameMatch(_ modelName: String, _ fileName: String) -> Bool {
        let modelLower = modelName.lowercased()
        let fileLower = fileName.lowercased()
        
        // Remove extensions for comparison
        let fileBase = fileLower.replacingOccurrences(of: ".gguf", with: "")
            .replacingOccurrences(of: ".onnx", with: "")
            .replacingOccurrences(of: ".mlpackage", with: "")
            .replacingOccurrences(of: ".tflite", with: "")
            .replacingOccurrences(of: ".mlmodelc", with: "")
        
        // Check for exact match first
        if modelLower == fileBase || modelName == fileName {
            return true
        }
        
        // Check if file is a temporary download file that might match this model
        // Pattern: download_<number>_<UUID>.tmp or similar
        if fileLower.hasPrefix("download_") && fileLower.contains("tmp") {
            // For temp files, we can't reliably match by name
            return false
        }
        
        // Check for partial matches
        return modelLower.contains(fileBase) || fileBase.contains(modelLower)
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
        case .onnxRuntime:
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
