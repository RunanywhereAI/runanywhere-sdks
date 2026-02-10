import Foundation

// MARK: - Model Management

extension RunAnywhere {

    /// Load an LLM model by ID
    /// - Parameter modelId: The model identifier
    public static func loadModel(_ modelId: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        // Resolve model ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == modelId }) else {
            throw SDKError.llm(.modelNotFound, "Model '\(modelId)' not found in registry")
        }

        // Handle built-in models (Foundation Models, System TTS) - no file path needed
        // These are platform services that don't require downloaded model files
        if modelInfo.isBuiltIn {
            // For built-in models, just pass the model ID to C++
            // The service registry will route to the correct platform provider
            try await CppBridge.LLM.shared.loadModel(modelId, modelId: modelId, modelName: modelInfo.name)
            return
        }

        // For downloaded models, verify they exist and resolve the file path
        guard modelInfo.localPath != nil else {
            throw SDKError.llm(.modelNotFound, "Model '\(modelId)' is not downloaded")
        }

        // Log model info for debugging
        let logger = SDKLogger(category: "ModelManagement")
        logger.info("Loading model: id=\(modelId), framework=\(modelInfo.framework), format=\(modelInfo.format), localPath=\(modelInfo.localPath?.path ?? "nil")")

        // Resolve actual model file path
        let modelPath = try resolveModelFilePath(for: modelInfo)
        logger.info("Resolved model path: \(modelPath.path)")
        try await CppBridge.LLM.shared.loadModel(modelPath.path, modelId: modelId, modelName: modelInfo.name)
    }

    // MARK: - Private: Model Path Resolution

    /// Resolve the actual model file path for loading.
    /// For single-file models (LlamaCpp), finds the actual .gguf file in the folder.
    /// For directory-based models (ONNX), returns the folder containing the model files.
    private static func resolveModelFilePath(for model: ModelInfo) throws -> URL {
        let modelFolder = try CppBridge.ModelPaths.getModelFolder(modelId: model.id, framework: model.framework)

        // For ONNX models (directory-based), we need to find the actual model directory
        // Archives often create a nested folder with the model name inside
        if model.framework == .onnx {
            return resolveONNXModelPath(modelFolder: modelFolder, modelId: model.id)
        }

        // For single-file models (LlamaCpp), find the actual model file
        return try resolveSingleFileModelPath(modelFolder: modelFolder, model: model)
    }

    /// Resolve ONNX model directory path (handles nested archive extraction)
    private static func resolveONNXModelPath(modelFolder: URL, modelId: String) -> URL {
        let logger = SDKLogger(category: "ModelPathResolver")

        // Check if there's a nested folder with the model name (from archive extraction)
        let nestedFolder = modelFolder.appendingPathComponent(modelId)
        logger.debug("Checking nested folder: \(nestedFolder.path)")

        if FileManager.default.fileExists(atPath: nestedFolder.path) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: nestedFolder.path, isDirectory: &isDir), isDir.boolValue {
                // Check if this nested folder contains model files
                if hasONNXModelFiles(at: nestedFolder) {
                    logger.info("Found ONNX model at nested path: \(nestedFolder.path)")
                    return nestedFolder
                }
            }
        }

        // Check if model files exist directly in the model folder
        if hasONNXModelFiles(at: modelFolder) {
            logger.info("Found ONNX model at folder: \(modelFolder.path)")
            return modelFolder
        }

        // Scan for any subdirectory that contains model files
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: [.isDirectoryKey]) {
            logger.debug("Scanning \(contents.count) items in model folder")
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    if hasONNXModelFiles(at: item) {
                        logger.info("Found ONNX model in subdirectory: \(item.path)")
                        return item
                    }
                }
            }
        }

        // Fallback to model folder
        logger.warning("No ONNX model files found, falling back to: \(modelFolder.path)")
        return modelFolder
    }

    /// Check if a directory contains ONNX model files
    private static func hasONNXModelFiles(at directory: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }

        // Check for any .onnx files (handles various naming conventions)
        let hasOnnxFiles = contents.contains { url in
            url.pathExtension.lowercased() == "onnx"
        }

        // Also check for tokens.txt which is common to both STT and TTS
        let hasTokensFile = contents.contains { url in
            url.lastPathComponent.lowercased().contains("tokens")
        }

        return hasOnnxFiles || hasTokensFile
    }

    /// Resolve single-file model path (LlamaCpp .gguf files)
    private static func resolveSingleFileModelPath(modelFolder: URL, model: ModelInfo) throws -> URL {
        let logger = SDKLogger(category: "ModelPathResolver")
        
        // Log model metadata for debugging
        logger.info("Resolving path for model: id=\(model.id), framework=\(model.framework), format=\(model.format)")
        
        // Get the expected path from C++
        let expectedPath = try CppBridge.ModelPaths.getExpectedModelPath(
            modelId: model.id,
            framework: model.framework,
            format: model.format
        )

        logger.debug("Expected model path: \(expectedPath.path)")

        // If expected path exists, use it
        if FileManager.default.fileExists(atPath: expectedPath.path) {
            logger.info("Found model at expected path: \(expectedPath.path)")
            return expectedPath
        }

        // Find files with the expected extension in model folder
        let expectedExtension = model.format.rawValue.lowercased()
        if let modelFile = findModelFile(in: modelFolder, extensions: [expectedExtension, "gguf", "bin"]) {
            logger.info("Found model file: \(modelFile.path)")
            return modelFile
        }
        
        // Search in nested subdirectories (archives often create nested folders)
        logger.debug("Searching nested directories in: \(modelFolder.path)")
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    if let modelFile = findModelFile(in: item, extensions: [expectedExtension, "gguf", "bin"]) {
                        logger.info("Found model file in nested directory: \(modelFile.path)")
                        return modelFile
                    }
                }
            }
        }

        // Fallback to expected path
        logger.warning("Model file not found, falling back to: \(expectedPath.path)")
        return expectedPath
    }
    
    /// Find a model file with specific extensions in a directory
    private static func findModelFile(in directory: URL, extensions: [String]) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        // Look for files with the expected extensions
        let modelFiles = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return extensions.contains(ext)
        }
        
        // Prefer .gguf files if multiple matches
        if let ggufFile = modelFiles.first(where: { $0.pathExtension.lowercased() == "gguf" }) {
            return ggufFile
        }
        
        return modelFiles.first
    }

    /// Unload the currently loaded LLM model
    public static func unloadModel() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await CppBridge.LLM.shared.unload()
    }

    /// Check if an LLM model is loaded
    public static var isModelLoaded: Bool {
        get async {
            await CppBridge.LLM.shared.isLoaded
        }
    }

    /// Check if the currently loaded LLM model supports streaming generation
    ///
    /// Some models (like Apple Foundation Models) don't support streaming and require
    /// non-streaming generation via `generate()` instead of `generateStream()`.
    ///
    /// - Returns: `true` if streaming is supported, `false` if you should use `generate()` instead
    /// - Note: Returns `false` if no model is loaded
    public static var supportsLLMStreaming: Bool {
        get async {
            true  // C++ layer supports streaming
        }
    }

    /// Load an STT (Speech-to-Text) model by ID
    /// This loads the model into the STT component
    /// - Parameter modelId: The model identifier (e.g., "whisper-base")
    public static func loadSTTModel(_ modelId: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        // Resolve model ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == modelId }) else {
            throw SDKError.stt(.modelNotFound, "Model '\(modelId)' not found in registry")
        }
        guard modelInfo.localPath != nil else {
            throw SDKError.stt(.modelNotFound, "Model '\(modelId)' is not downloaded")
        }

        // Resolve actual model path
        let modelPath = try resolveModelFilePath(for: modelInfo)
        let logger = SDKLogger(category: "RunAnywhere.STT")
        logger.info("Loading STT model from resolved path: \(modelPath.path)")
        try await CppBridge.STT.shared.loadModel(modelPath.path, modelId: modelId, modelName: modelInfo.name)
    }

    /// Load a TTS (Text-to-Speech) voice by ID
    /// This loads the voice into the TTS component
    /// - Parameter voiceId: The voice identifier
    public static func loadTTSModel(_ voiceId: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        // Resolve voice ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == voiceId }) else {
            throw SDKError.tts(.modelNotFound, "Voice '\(voiceId)' not found in registry")
        }

        // Handle built-in voices (System TTS) - no file path needed
        if modelInfo.isBuiltIn {
            let logger = SDKLogger(category: "RunAnywhere.TTS")
            logger.info("Loading built-in TTS voice: \(voiceId)")
            try await CppBridge.TTS.shared.loadVoice(voiceId, voiceId: voiceId, voiceName: modelInfo.name)
            return
        }

        guard modelInfo.localPath != nil else {
            throw SDKError.tts(.modelNotFound, "Voice '\(voiceId)' is not downloaded")
        }

        // Resolve actual model path
        let modelPath = try resolveModelFilePath(for: modelInfo)
        let logger = SDKLogger(category: "RunAnywhere.TTS")
        logger.info("Loading TTS voice from resolved path: \(modelPath.path)")
        try await CppBridge.TTS.shared.loadVoice(modelPath.path, voiceId: voiceId, voiceName: modelInfo.name)
    }

    /// Get available models
    /// - Returns: Array of available models
    public static func availableModels() async throws -> [ModelInfo] {
        guard isInitialized else { throw SDKError.general(.notInitialized, "SDK not initialized") }
        // Ensure services are initialized (including Platform backend registration)
        try await ensureServicesReady()
        return await CppBridge.ModelRegistry.shared.getAll()
    }

    /// Get currently loaded LLM model ID
    /// - Returns: Currently loaded model ID if any
    public static func getCurrentModelId() async -> String? {
        guard isInitialized else { return nil }
        return await CppBridge.LLM.shared.currentModelId
    }

    /// Get the currently loaded LLM model as ModelInfo
    ///
    /// This is a convenience property that combines `getCurrentModelId()` with
    /// a lookup in the available models registry.
    ///
    /// - Returns: The currently loaded ModelInfo, or nil if no model is loaded
    public static var currentLLMModel: ModelInfo? {
        get async {
            guard let modelId = await getCurrentModelId() else { return nil }
            let models = (try? await availableModels()) ?? []
            return models.first { $0.id == modelId }
        }
    }

    /// Get the currently loaded STT model as ModelInfo
    ///
    /// - Returns: The currently loaded STT ModelInfo, or nil if no STT model is loaded
    public static var currentSTTModel: ModelInfo? {
        get async {
            guard isInitialized else { return nil }
            guard let modelId = await CppBridge.STT.shared.currentModelId else { return nil }
            let models = (try? await availableModels()) ?? []
            return models.first { $0.id == modelId }
        }
    }

    /// Get the currently loaded TTS voice ID
    ///
    /// Note: TTS uses voices (not models), so this returns the voice identifier string.
    /// - Returns: The TTS voice ID if one is loaded, nil otherwise
    public static var currentTTSVoiceId: String? {
        get async {
            guard isInitialized else { return nil }
            return await CppBridge.TTS.shared.currentVoiceId
        }
    }

    /// Cancel the current text generation
    ///
    /// Use this to stop an ongoing generation when the user navigates away
    /// or explicitly requests cancellation.
    public static func cancelGeneration() async {
        guard isInitialized else { return }
        await CppBridge.LLM.shared.cancel()
    }
}
