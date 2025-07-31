import Foundation

/// Protocol for model providers (HuggingFace, Kaggle, etc.)
public protocol ModelProvider {
    /// Name of the provider
    var name: String { get }
    
    /// Whether authentication is required
    var requiresAuthentication: Bool { get }
    
    /// Search for models
    /// - Parameters:
    ///   - query: Search query
    ///   - filters: Additional filters
    /// - Returns: Array of discovered models
    func searchModels(query: String, filters: ModelSearchFilters?) async throws -> [ModelInfo]
    
    /// Get model details
    /// - Parameter modelId: The model identifier
    /// - Returns: Detailed model information
    func getModelDetails(modelId: String) async throws -> ModelInfo
    
    /// Get download URL for a model
    /// - Parameter model: The model to download
    /// - Returns: Download URL
    func getDownloadURL(for model: ModelInfo) async throws -> URL
    
    /// Authenticate with the provider
    /// - Parameter credentials: Authentication credentials
    func authenticate(with credentials: ProviderCredentials) async throws
    
    /// Check if authenticated
    /// - Returns: Whether the provider is authenticated
    func isAuthenticated() -> Bool
    
    /// List available models
    /// - Parameter limit: Maximum number of models to return
    /// - Returns: Array of available models
    func listAvailableModels(limit: Int) async throws -> [ModelInfo]
}

/// Search filters for models
public struct ModelSearchFilters {
    public let format: ModelFormat?
    public let framework: LLMFramework?
    public let maxSize: Int64?
    public let minContextLength: Int?
    public let tags: [String]?
    public let author: String?
    public let sortBy: SortOption?
    
    public enum SortOption {
        case relevance
        case downloads
        case likes
        case recent
        case alphabetical
    }
    
    public init(
        format: ModelFormat? = nil,
        framework: LLMFramework? = nil,
        maxSize: Int64? = nil,
        minContextLength: Int? = nil,
        tags: [String]? = nil,
        author: String? = nil,
        sortBy: SortOption? = nil
    ) {
        self.format = format
        self.framework = framework
        self.maxSize = maxSize
        self.minContextLength = minContextLength
        self.tags = tags
        self.author = author
        self.sortBy = sortBy
    }
}

/// Provider credentials
public enum ProviderCredentials {
    case apiKey(String)
    case usernamePassword(username: String, password: String)
    case token(String)
    case oauth(token: String, refreshToken: String?)
}

/// Protocol for metadata extraction
public protocol MetadataExtractorProtocol {
    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }
    
    /// Extract metadata from a model file
    /// - Parameter url: URL to the model file
    /// - Returns: Extracted metadata
    func extractMetadata(from url: URL) async throws -> ModelMetadata
    
    /// Validate model file
    /// - Parameter url: URL to the model file
    /// - Returns: Whether the model is valid
    func validateModel(at url: URL) async throws -> Bool
    
    /// Get model requirements
    /// - Parameter url: URL to the model file
    /// - Returns: Model requirements
    func getRequirements(for url: URL) async throws -> ModelRequirements
}
