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

/// Protocol for model validation
public protocol ModelValidator {
    /// Validate a model
    /// - Parameters:
    ///   - model: Model information
    ///   - path: Path to the model file
    /// - Returns: Validation result
    func validateModel(_ model: ModelInfo, at path: URL) async throws -> ValidationResult
    
    /// Validate checksum
    /// - Parameters:
    ///   - file: File to validate
    ///   - expected: Expected checksum
    /// - Returns: Whether checksum is valid
    func validateChecksum(_ file: URL, expected: String) async throws -> Bool
    
    /// Validate model format
    /// - Parameters:
    ///   - file: File to validate
    ///   - expectedFormat: Expected format
    /// - Returns: Whether format is valid
    func validateFormat(_ file: URL, expectedFormat: ModelFormat) async throws -> Bool
    
    /// Validate dependencies
    /// - Parameter model: Model to validate
    /// - Returns: Missing dependencies
    func validateDependencies(_ model: ModelInfo) async throws -> [MissingDependency]
}

/// Validation result
public struct ValidationResult {
    public let isValid: Bool
    public let warnings: [ValidationWarning]
    public let errors: [ValidationError]
    public let metadata: ModelMetadata?
    
    public init(
        isValid: Bool,
        warnings: [ValidationWarning] = [],
        errors: [ValidationError] = [],
        metadata: ModelMetadata? = nil
    ) {
        self.isValid = isValid
        self.warnings = warnings
        self.errors = errors
        self.metadata = metadata
    }
}

/// Validation warning
public struct ValidationWarning {
    public let code: String
    public let message: String
    public let severity: Severity
    
    public enum Severity {
        case low
        case medium
        case high
    }
    
    public init(code: String, message: String, severity: Severity = .medium) {
        self.code = code
        self.message = message
        self.severity = severity
    }
}

/// Validation error
public enum ValidationError: LocalizedError {
    case checksumMismatch
    case invalidFormat
    case missingDependencies([MissingDependency])
    case corruptedFile
    case incompatibleVersion
    case invalidMetadata(String)
    
    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Model checksum does not match expected value"
        case .invalidFormat:
            return "Model format is invalid or unsupported"
        case .missingDependencies(let deps):
            return "Missing dependencies: \(deps.map { $0.name }.joined(separator: ", "))"
        case .corruptedFile:
            return "Model file appears to be corrupted"
        case .incompatibleVersion:
            return "Model version is incompatible with current SDK"
        case .invalidMetadata(let reason):
            return "Invalid metadata: \(reason)"
        }
    }
}

/// Missing dependency
public struct MissingDependency {
    public let name: String
    public let version: String?
    public let type: DependencyType
    
    public enum DependencyType {
        case framework
        case library
        case model
        case tokenizer
        case configuration
    }
    
    public init(name: String, version: String? = nil, type: DependencyType) {
        self.name = name
        self.version = version
        self.type = type
    }
}
