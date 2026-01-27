import Foundation

// MARK: - Model Registration API

public extension RunAnywhere {

    /// Register a model from a download URL
    /// Use this to add models for development or offline use
    /// - Parameters:
    ///   - id: Explicit model ID. If nil, a stable ID is generated from the URL filename.
    ///   - name: Display name for the model
    ///   - url: Download URL for the model (e.g., HuggingFace)
    ///   - framework: Target inference framework
    ///   - modality: Model category (default: .language for LLMs)
    ///   - artifactType: How the model is packaged (archive, single file, etc.). If nil, inferred from URL.
    ///   - memoryRequirement: Estimated memory usage in bytes
    ///   - supportsThinking: Whether the model supports reasoning/thinking
    /// - Returns: The created ModelInfo
    @discardableResult
    static func registerModel(
        id: String? = nil,
        name: String,
        url: URL,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        artifactType: ModelArtifactType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false
    ) -> ModelInfo {
        // Generate model ID from URL filename if not provided
        let modelId = id ?? generateModelId(from: url)

        // Detect format from URL extension
        let format = detectFormat(from: url)

        // Create ModelInfo with nil localPath initially
        // The actual localPath will be preserved from existing registry if available
        let modelInfo = ModelInfo(
            id: modelId,
            name: name,
            category: modality,
            format: format,
            framework: framework,
            downloadURL: url,
            localPath: nil,
            artifactType: artifactType,
            downloadSize: memoryRequirement,
            contextLength: modality.requiresContextLength ? 2048 : nil,
            supportsThinking: supportsThinking,
            description: "User-added model",
            source: .local
        )

        // Save to C++ registry using synchronous C API directly
        // This avoids async/await which could cause timing issues with discovery
        // Discovery will update the localPath if the model was previously downloaded
        let logger = SDKLogger(category: "RunAnywhere.Models")
        
        do {
            // Use synchronous save via the bridge
            // Note: Discovery runs later and will update localPath if model exists on disk
            try CppBridge.ModelRegistry.shared.saveSync(modelInfo)
            logger.debug("Model registered: \(modelId)")
        } catch {
            logger.error("Failed to register model: \(error)")
        }

        return modelInfo
    }

    /// Register a model from a URL string
    /// - Parameters:
    ///   - id: Explicit model ID. If nil, a stable ID is generated from the URL filename.
    ///   - name: Display name for the model
    ///   - urlString: Download URL string for the model
    ///   - framework: Target inference framework
    ///   - modality: Model category (default: .language for LLMs)
    ///   - artifactType: How the model is packaged (archive, single file, etc.). If nil, inferred from URL.
    ///   - memoryRequirement: Estimated memory usage in bytes
    ///   - supportsThinking: Whether the model supports reasoning/thinking
    /// - Returns: The created ModelInfo, or nil if URL is invalid
    @discardableResult
    static func registerModel(
        id: String? = nil,
        name: String,
        urlString: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        artifactType: ModelArtifactType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false
    ) -> ModelInfo? {
        guard let url = URL(string: urlString) else {
            SDKLogger(category: "RunAnywhere.Models").error("Invalid URL: \(urlString)")
            return nil
        }
        return registerModel(
            id: id,
            name: name,
            url: url,
            framework: framework,
            modality: modality,
            artifactType: artifactType,
            memoryRequirement: memoryRequirement,
            supportsThinking: supportsThinking
        )
    }

    // MARK: - Private Helpers

    private static func generateModelId(from url: URL) -> String {
        var filename = url.lastPathComponent
        let knownExtensions = ["gz", "bz2", "tar", "zip", "gguf", "onnx", "ort", "bin"]
        while let ext = filename.split(separator: ".").last, knownExtensions.contains(String(ext).lowercased()) {
            filename = String(filename.dropLast(ext.count + 1))
        }
        return filename
    }

    private static func detectFormat(from url: URL) -> ModelFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "onnx": return .onnx
        case "ort": return .ort
        case "gguf": return .gguf
        case "bin": return .bin
        default: return .unknown
        }
    }
}

// MARK: - Model Assignments API

extension RunAnywhere {

    /// Fetch model assignments for the current device from the backend
    /// This method fetches models assigned to this device based on device type and platform
    /// - Parameter forceRefresh: Force refresh even if cached models are available
    /// - Returns: Array of ModelInfo objects assigned to this device
    /// - Throws: SDKError if fetching fails
    public static func fetchModelAssignments(forceRefresh: Bool = false) async throws -> [ModelInfo] {
        let logger = SDKLogger(category: "RunAnywhere.ModelAssignments")

        // Ensure SDK is initialized
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Ensure network services are initialized
        try await ensureServicesReady()

        logger.info("Fetching model assignments...")

        // Delegate to C++ model assignment manager via bridge
        let models = try await CppBridge.ModelAssignment.fetch(forceRefresh: forceRefresh)
        logger.info("Successfully fetched \(models.count) model assignments")

        return models
    }

    /// Get available models for a specific framework
    /// - Parameter framework: The LLM framework to filter models for
    /// - Returns: Array of ModelInfo objects compatible with the specified framework
    public static func getModelsForFramework(_ framework: InferenceFramework) async throws -> [ModelInfo] {
        // Ensure SDK is initialized
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Ensure network services are initialized
        try await ensureServicesReady()

        // Use C++ bridge for filtering (uses cached data)
        return CppBridge.ModelAssignment.getByFramework(framework)
    }

    /// Get available models for a specific category
    /// - Parameter category: The model category to filter models for
    /// - Returns: Array of ModelInfo objects in the specified category
    public static func getModelsForCategory(_ category: ModelCategory) async throws -> [ModelInfo] {
        // Ensure SDK is initialized
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Ensure network services are initialized
        try await ensureServicesReady()

        // Use C++ bridge for filtering (uses cached data)
        return CppBridge.ModelAssignment.getByCategory(category)
    }
}
