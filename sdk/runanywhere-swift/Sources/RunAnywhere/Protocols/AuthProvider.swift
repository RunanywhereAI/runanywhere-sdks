import Foundation

/// Protocol for authentication providers
public protocol AuthProvider {
    /// Provider name
    var providerName: String { get }
    
    /// Check if credentials are stored
    /// - Returns: Whether valid credentials exist
    func hasStoredCredentials() -> Bool
    
    /// Store credentials securely
    /// - Parameter credentials: Credentials to store
    func storeCredentials(_ credentials: ProviderCredentials) async throws
    
    /// Retrieve stored credentials
    /// - Returns: Stored credentials if available
    func retrieveCredentials() async throws -> ProviderCredentials?
    
    /// Remove stored credentials
    func removeCredentials() async throws
    
    /// Validate credentials
    /// - Parameter credentials: Credentials to validate
    /// - Returns: Whether credentials are valid
    func validateCredentials(_ credentials: ProviderCredentials) async throws -> Bool
    
    /// Get authentication headers
    /// - Returns: Headers to include in requests
    func getAuthHeaders() async throws -> [String: String]
    
    /// Refresh authentication if needed
    func refreshAuthenticationIfNeeded() async throws
    
    /// Check if authentication is expired
    /// - Returns: Whether authentication has expired
    func isAuthenticationExpired() -> Bool
}

/// Protocol for model storage management
public protocol ModelStorageManager {
    /// Get storage directory for models
    /// - Returns: URL to models directory
    func getModelsDirectory() -> URL
    
    /// Get path for a specific model
    /// - Parameter modelId: Model identifier
    /// - Returns: Path where model should be stored
    func getModelPath(for modelId: String) -> URL
    
    /// Check if model exists locally
    /// - Parameter modelId: Model identifier
    /// - Returns: Whether model exists
    func modelExists(_ modelId: String) -> Bool
    
    /// Get model size on disk
    /// - Parameter modelId: Model identifier
    /// - Returns: Size in bytes
    func getModelSize(_ modelId: String) -> Int64?
    
    /// Delete a model
    /// - Parameter modelId: Model identifier
    func deleteModel(_ modelId: String) async throws
    
    /// Get available storage space
    /// - Returns: Available space in bytes
    func getAvailableSpace() -> Int64
    
    /// List all stored models
    /// - Returns: Array of stored model identifiers
    func listStoredModels() -> [String]
    
    /// Clean up temporary files
    func cleanupTemporaryFiles() async throws
    
    /// Move model from temporary to permanent storage
    /// - Parameters:
    ///   - temporaryPath: Temporary file path
    ///   - modelId: Model identifier
    /// - Returns: Final storage path
    func moveToStorage(from temporaryPath: URL, modelId: String) async throws -> URL
}

/// Download task representation
public struct DownloadTask {
    public let id: String
    public let modelId: String
    public let progress: AsyncStream<DownloadProgress>
    public let result: Task<URL, Error>
    
    public init(
        id: String,
        modelId: String,
        progress: AsyncStream<DownloadProgress>,
        result: Task<URL, Error>
    ) {
        self.id = id
        self.modelId = modelId
        self.progress = progress
        self.result = result
    }
}

/// Download progress information
public struct DownloadProgress {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let percentComplete: Double
    public let estimatedTimeRemaining: TimeInterval?
    public let downloadSpeed: Double // bytes per second
    public let status: DownloadStatus
    
    public enum DownloadStatus {
        case pending
        case downloading
        case extracting
        case completed
        case failed(Error)
        case cancelled
        case retrying(attempt: Int)
    }
    
    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        percentComplete: Double,
        estimatedTimeRemaining: TimeInterval? = nil,
        downloadSpeed: Double = 0,
        status: DownloadStatus = .downloading
    ) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.percentComplete = percentComplete
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.downloadSpeed = downloadSpeed
        self.status = status
    }
}

/// Model criteria for filtering
public struct ModelCriteria {
    public let framework: LLMFramework?
    public let format: ModelFormat?
    public let maxSize: Int64?
    public let minContextLength: Int?
    public let maxContextLength: Int?
    public let requiresNeuralEngine: Bool?
    public let requiresGPU: Bool?
    public let tags: [String]
    public let quantization: String?
    public let search: String?
    
    public init(
        framework: LLMFramework? = nil,
        format: ModelFormat? = nil,
        maxSize: Int64? = nil,
        minContextLength: Int? = nil,
        maxContextLength: Int? = nil,
        requiresNeuralEngine: Bool? = nil,
        requiresGPU: Bool? = nil,
        tags: [String] = [],
        quantization: String? = nil,
        search: String? = nil
    ) {
        self.framework = framework
        self.format = format
        self.maxSize = maxSize
        self.minContextLength = minContextLength
        self.maxContextLength = maxContextLength
        self.requiresNeuralEngine = requiresNeuralEngine
        self.requiresGPU = requiresGPU
        self.tags = tags
        self.quantization = quantization
        self.search = search
    }
}

/// Model registry protocol
public protocol ModelRegistry {
    /// Discover available models
    /// - Returns: Array of discovered models
    func discoverModels() async -> [ModelInfo]
    
    /// Register a model
    /// - Parameter model: Model to register
    func registerModel(_ model: ModelInfo)
    
    /// Get model by ID
    /// - Parameter id: Model identifier
    /// - Returns: Model information if found
    func getModel(by id: String) -> ModelInfo?
    
    /// Filter models by criteria
    /// - Parameter criteria: Filter criteria
    /// - Returns: Filtered models
    func filterModels(by criteria: ModelCriteria) -> [ModelInfo]
    
    /// Update model information
    /// - Parameter model: Updated model information
    func updateModel(_ model: ModelInfo)
    
    /// Remove a model
    /// - Parameter id: Model identifier
    func removeModel(_ id: String)
}
