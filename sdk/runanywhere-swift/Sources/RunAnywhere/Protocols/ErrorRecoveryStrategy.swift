import Foundation

/// Protocol for error recovery strategies
public protocol ErrorRecoveryStrategy {
    /// Check if this strategy can recover from the error
    /// - Parameter error: The error to check
    /// - Returns: Whether recovery is possible
    func canRecover(from error: Error) -> Bool

    /// Attempt to recover from the error
    /// - Parameters:
    ///   - error: The error to recover from
    ///   - context: Recovery context
    func recover(from error: Error, context: RecoveryContext) async throws

    /// Get recovery suggestions
    /// - Parameter error: The error
    /// - Returns: Suggested recovery actions
    func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion]
}

/// Context for error recovery
public struct RecoveryContext {
    public let model: ModelInfo
    public let stage: LifecycleStage
    public let attemptCount: Int
    public let previousErrors: [Error]
    public let availableResources: ResourceAvailability
    public let options: RecoveryOptions

    public init(
        model: ModelInfo,
        stage: LifecycleStage,
        attemptCount: Int = 1,
        previousErrors: [Error] = [],
        availableResources: ResourceAvailability,
        options: RecoveryOptions = RecoveryOptions()
    ) {
        self.model = model
        self.stage = stage
        self.attemptCount = attemptCount
        self.previousErrors = previousErrors
        self.availableResources = availableResources
        self.options = options
    }
}

/// Recovery options
public struct RecoveryOptions {
    public let maxRetryAttempts: Int
    public let retryDelay: TimeInterval
    public let exponentialBackoff: Bool
    public let allowFrameworkSwitch: Bool
    public let allowQualityReduction: Bool
    public let allowMemoryOptimization: Bool

    public init(
        maxRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 1.0,
        exponentialBackoff: Bool = true,
        allowFrameworkSwitch: Bool = true,
        allowQualityReduction: Bool = false,
        allowMemoryOptimization: Bool = true
    ) {
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
        self.exponentialBackoff = exponentialBackoff
        self.allowFrameworkSwitch = allowFrameworkSwitch
        self.allowQualityReduction = allowQualityReduction
        self.allowMemoryOptimization = allowMemoryOptimization
    }
}

/// Recovery suggestion
public struct RecoverySuggestion {
    public let action: RecoveryAction
    public let description: String
    public let priority: Priority
    public let estimatedDuration: TimeInterval?

    public enum RecoveryAction {
        case retry
        case retryWithDelay(TimeInterval)
        case switchFramework(LLMFramework)
        case reduceQuality
        case clearCache
        case freeMemory
        case downloadAlternative
        case updateConfiguration
        case contactSupport
    }

    public enum Priority {
        case low
        case medium
        case high
        case critical
    }

    public init(
        action: RecoveryAction,
        description: String,
        priority: Priority = .medium,
        estimatedDuration: TimeInterval? = nil
    ) {
        self.action = action
        self.description = description
        self.priority = priority
        self.estimatedDuration = estimatedDuration
    }
}

/// Error types for categorization
public enum ErrorType {
    case download
    case network
    case memory
    case validation
    case framework
    case hardware
    case configuration
    case authentication
    case unknown

    /// Initialize from an error
    public init(from error: Error) {
        // Categorize based on error type
        switch error {
        case is URLError:
            self = .network
        case let nsError as NSError:
            switch nsError.domain {
            case NSURLErrorDomain:
                self = .network
            case NSPOSIXErrorDomain where nsError.code == ENOMEM:
                self = .memory
            default:
                self = .unknown
            }
        default:
            // Check error description for hints
            let description = error.localizedDescription.lowercased()
            if description.contains("memory") {
                self = .memory
            } else if description.contains("download") {
                self = .download
            } else if description.contains("validation") || description.contains("checksum") {
                self = .validation
            } else if description.contains("hardware") || description.contains("device") {
                self = .hardware
            } else if description.contains("auth") || description.contains("credential") {
                self = .authentication
            } else {
                self = .unknown
            }
        }
    }
}

/// Unified model errors
public enum UnifiedModelError: LocalizedError {
    case lifecycle(ModelLifecycleError)
    case framework(FrameworkError)
    case insufficientMemory(required: Int64, available: Int64)
    case deviceNotSupported(String)
    case authRequired(String)
    case retryRequired(String)
    case retryWithFramework(LLMFramework)
    case noAlternativeFramework
    case unrecoverable(Error)

    public var errorDescription: String? {
        switch self {
        case .lifecycle(let error):
            return error.errorDescription
        case .framework(let error):
            return error.errorDescription
        case .insufficientMemory(let required, let available):
            let neededStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .memory)
            let availStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .memory)
            return "Insufficient memory: need \(neededStr), have \(availStr)"
        case .deviceNotSupported(let reason):
            return "Device not supported: \(reason)"
        case .authRequired(let provider):
            return "Authentication required for \(provider)"
        case .retryRequired(let reason):
            return "Retry required: \(reason)"
        case .retryWithFramework(let framework):
            return "Retry with \(framework.rawValue) framework"
        case .noAlternativeFramework:
            return "No alternative framework available"
        case .unrecoverable(let error):
            return "Unrecoverable error: \(error.localizedDescription)"
        }
    }
}

/// Download errors
public enum DownloadError: LocalizedError {
    case networkError(Error)
    case timeout
    case partialDownload
    case checksumMismatch
    case unsupportedArchive(String)
    case extractionFailed(Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Download timeout"
        case .partialDownload:
            return "Partial download detected"
        case .checksumMismatch:
            return "Downloaded file checksum mismatch"
        case .unsupportedArchive(let format):
            return "Unsupported archive format: \(format)"
        case .extractionFailed(let error):
            return "Archive extraction failed: \(error.localizedDescription)"
        case .unknown:
            return "Unknown download error"
        }
    }
}
