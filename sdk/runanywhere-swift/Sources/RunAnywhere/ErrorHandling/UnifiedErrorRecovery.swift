import Foundation

/// Unified error recovery coordinator
public class UnifiedErrorRecovery {
    // MARK: - Properties
    
    private var strategies: [ErrorType: ErrorRecoveryStrategy] = [:]
    private let strategyLock = NSLock()
    
    // MARK: - Initialization
    
    public init() {
        registerDefaultStrategies()
    }
    
    // MARK: - Public API
    
    /// Register a recovery strategy for an error type
    public func registerStrategy(_ strategy: ErrorRecoveryStrategy, for errorType: ErrorType) {
        strategyLock.lock()
        defer { strategyLock.unlock() }
        strategies[errorType] = strategy
    }
    
    /// Attempt to recover from an error
    public func attemptRecovery(from error: Error, in context: RecoveryContext) async throws {
        let errorType = ErrorType(from: error)
        
        strategyLock.lock()
        let strategy = strategies[errorType]
        strategyLock.unlock()
        
        if let strategy = strategy, strategy.canRecover(from: error) {
            try await strategy.recover(from: error, context: context)
        } else {
            throw UnifiedModelError.unrecoverable(error)
        }
    }
    
    /// Get recovery suggestions for an error
    public func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        let errorType = ErrorType(from: error)
        
        strategyLock.lock()
        let strategy = strategies[errorType]
        strategyLock.unlock()
        
        return strategy?.getRecoverySuggestions(for: error) ?? getDefaultSuggestions(for: error)
    }
    
    // MARK: - Private Methods
    
    private func registerDefaultStrategies() {
        registerStrategy(DownloadErrorRecovery(), for: .download)
        registerStrategy(MemoryErrorRecovery(), for: .memory)
        registerStrategy(ValidationErrorRecovery(), for: .validation)
        registerStrategy(FrameworkErrorRecovery(), for: .framework)
        registerStrategy(NetworkErrorRecovery(), for: .network)
    }
    
    private func getDefaultSuggestions(for error: Error) -> [RecoverySuggestion] {
        [
            RecoverySuggestion(
                action: .retry,
                description: "Retry the operation",
                priority: .medium
            ),
            RecoverySuggestion(
                action: .contactSupport,
                description: "Contact support if the issue persists",
                priority: .low
            )
        ]
    }
}

// MARK: - Default Recovery Strategies

/// Download error recovery strategy
class DownloadErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        if error is DownloadError { return true }
        if error is URLError { return true }
        return false
    }
    
    func recover(from error: Error, context: RecoveryContext) async throws {
        // Check attempt count
        guard context.attemptCount < context.options.maxRetryAttempts else {
            throw UnifiedModelError.unrecoverable(error)
        }
        
        // Apply exponential backoff
        if context.options.exponentialBackoff {
            let delay = pow(2.0, Double(context.attemptCount)) * context.options.retryDelay
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } else {
            try await Task.sleep(nanoseconds: UInt64(context.options.retryDelay * 1_000_000_000))
        }
        
        // Try alternative URLs if available
        if let alternativeURLs = context.model.alternativeDownloadURLs,
           !alternativeURLs.isEmpty {
            // Retry with alternative URL would be handled by the download manager
            throw UnifiedModelError.retryRequired("Retry with alternative URL")
        }
        
        // Clear partial downloads if needed
        if case DownloadError.partialDownload = error {
            // Cleanup would be handled by the download manager
            throw UnifiedModelError.retryRequired("Clear partial download and retry")
        }
    }
    
    func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        var suggestions: [RecoverySuggestion] = []
        
        suggestions.append(RecoverySuggestion(
            action: .retryWithDelay(2.0),
            description: "Retry download after network stabilizes",
            priority: .high
        ))
        
        if error.localizedDescription.contains("timeout") {
            suggestions.append(RecoverySuggestion(
                action: .updateConfiguration,
                description: "Increase download timeout in configuration",
                priority: .medium
            ))
        }
        
        suggestions.append(RecoverySuggestion(
            action: .downloadAlternative,
            description: "Try downloading from alternative source",
            priority: .medium
        ))
        
        return suggestions
    }
}

/// Memory error recovery strategy
class MemoryErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        if case UnifiedModelError.insufficientMemory = error { return true }
        if error.localizedDescription.lowercased().contains("memory") { return true }
        return false
    }
    
    func recover(from error: Error, context: RecoveryContext) async throws {
        // Wait for memory to be freed
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Check if we have enough memory now
        let available = context.availableResources.memoryAvailable
        if context.model.estimatedMemory > available {
            // Try memory optimization strategies
            if context.options.allowMemoryOptimization {
                throw UnifiedModelError.retryRequired("Apply memory optimization")
            }
            
            // Try switching to more memory-efficient framework
            if context.options.allowFrameworkSwitch {
                if let efficientFramework = findMemoryEfficientFramework(for: context.model) {
                    throw UnifiedModelError.retryWithFramework(efficientFramework)
                }
            }
            
            throw UnifiedModelError.unrecoverable(error)
        }
    }
    
    func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        [
            RecoverySuggestion(
                action: .freeMemory,
                description: "Close other applications to free memory",
                priority: .critical
            ),
            RecoverySuggestion(
                action: .reduceQuality,
                description: "Use a smaller or quantized model",
                priority: .high
            ),
            RecoverySuggestion(
                action: .switchFramework(.tensorFlowLite),
                description: "Try TensorFlow Lite for better memory efficiency",
                priority: .medium
            )
        ]
    }
    
    private func findMemoryEfficientFramework(for model: ModelInfo) -> LLMFramework? {
        // Order frameworks by typical memory efficiency
        let efficientFrameworks: [LLMFramework] = [
            .tensorFlowLite,
            .execuTorch,
            .onnx,
            .coreML
        ]
        
        for framework in efficientFrameworks {
            if model.compatibleFrameworks.contains(framework) {
                return framework
            }
        }
        
        return nil
    }
}

/// Validation error recovery strategy
class ValidationErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        if error is ValidationError { return true }
        return false
    }
    
    func recover(from error: Error, context: RecoveryContext) async throws {
        guard let validationError = error as? ValidationError else {
            throw UnifiedModelError.unrecoverable(error)
        }
        
        switch validationError {
        case .checksumMismatch, .corruptedFile:
            // Re-download the model
            if let localPath = context.model.localPath {
                try? FileManager.default.removeItem(at: localPath)
            }
            throw UnifiedModelError.retryRequired("Model corrupted, re-download required")
            
        case .missingDependencies(let deps):
            // Provide information about missing dependencies
            let depList = deps.map { $0.name }.joined(separator: ", ")
            throw UnifiedModelError.retryRequired("Install missing dependencies: \(depList)")
            
        default:
            throw UnifiedModelError.unrecoverable(error)
        }
    }
    
    func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        [
            RecoverySuggestion(
                action: .downloadAlternative,
                description: "Re-download the model",
                priority: .high
            ),
            RecoverySuggestion(
                action: .clearCache,
                description: "Clear model cache and retry",
                priority: .medium
            )
        ]
    }
}

/// Framework error recovery strategy
class FrameworkErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        // Most framework errors can potentially be recovered by switching frameworks
        true
    }
    
    func recover(from error: Error, context: RecoveryContext) async throws {
        guard context.options.allowFrameworkSwitch else {
            throw UnifiedModelError.unrecoverable(error)
        }
        
        // Find alternative framework
        let currentFramework = context.model.preferredFramework
        let alternatives = context.model.compatibleFrameworks.filter { $0 != currentFramework }
        
        if let alternative = alternatives.first {
            throw UnifiedModelError.retryWithFramework(alternative)
        }
        
        throw UnifiedModelError.noAlternativeFramework
    }
    
    func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        var suggestions: [RecoverySuggestion] = []
        
        // Suggest alternative frameworks
        suggestions.append(RecoverySuggestion(
            action: .switchFramework(.coreML),
            description: "Try Core ML framework",
            priority: .high
        ))
        
        suggestions.append(RecoverySuggestion(
            action: .updateConfiguration,
            description: "Update framework configuration",
            priority: .medium
        ))
        
        return suggestions
    }
}

/// Network error recovery strategy
class NetworkErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        if error is URLError { return true }
        if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
            return true
        }
        return false
    }
    
    func recover(from error: Error, context: RecoveryContext) async throws {
        // Check network connectivity
        if !isNetworkAvailable() {
            throw UnifiedModelError.unrecoverable(error)
        }
        
        // Apply retry with backoff
        let delay = pow(2.0, Double(context.attemptCount)) * context.options.retryDelay
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        throw UnifiedModelError.retryRequired("Retry after network delay")
    }
    
    func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        [
            RecoverySuggestion(
                action: .retry,
                description: "Check network connection and retry",
                priority: .critical
            ),
            RecoverySuggestion(
                action: .downloadAlternative,
                description: "Try alternative download source",
                priority: .high
            )
        ]
    }
    
    private func isNetworkAvailable() -> Bool {
        // Simplified network check
        // In production, use proper reachability check
        true
    }
}
