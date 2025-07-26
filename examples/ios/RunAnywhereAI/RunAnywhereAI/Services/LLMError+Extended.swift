//
//  LLMError+Extended.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

// MARK: - Extended Error Types

extension LLMError {
    
    /// Create error with additional context
    static func withContext(
        _ error: LLMError,
        framework: String? = nil,
        operation: String? = nil,
        additionalInfo: [String: Any]? = nil
    ) -> ErrorContext {
        ErrorContext(
            error: error,
            framework: framework,
            operation: operation,
            additionalInfo: additionalInfo
        )
    }
    
    /// Check if error is recoverable
    var isRecoverable: Bool {
        switch self {
        case .notInitialized, .modelNotFound, .noServiceSelected,
             .downloadFailed, .networkUnavailable:
            return true
        case .initializationFailed, .unsupportedFormat, .frameworkNotSupported,
             .memoryAllocationFailed:
            return false
        default:
            return true
        }
    }
    
    /// Get error severity
    var severity: ErrorSeverity {
        switch self {
        case .notInitialized, .noServiceSelected:
            return .warning
        case .modelNotFound, .unsupportedFormat, .invalidModelPath:
            return .error
        case .initializationFailed, .memoryAllocationFailed:
            return .critical
        case .notImplemented:
            return .info
        default:
            return .error
        }
    }
    
    /// Get error category
    var category: ErrorCategory {
        switch self {
        case .notInitialized, .initializationFailed, .modelNotFound,
             .unsupportedFormat, .invalidModelPath:
            return .initialization
        case .noServiceSelected, .serviceNotAvailable, .frameworkNotSupported:
            return .service
        case .inferenceError, .decodeFailed, .tokenizationFailed, .contextLengthExceeded:
            return .inference
        case .insufficientMemory, .memoryAllocationFailed:
            return .memory
        case .downloadFailed, .networkUnavailable:
            return .network
        case .notImplemented, .unknown:
            return .other
        }
    }
}

// MARK: - Error Context

/// Additional context for errors
struct ErrorContext {
    let error: LLMError
    let timestamp: Date
    let framework: String?
    let operation: String?
    let additionalInfo: [String: Any]?
    
    init(
        error: LLMError,
        framework: String? = nil,
        operation: String? = nil,
        additionalInfo: [String: Any]? = nil
    ) {
        self.error = error
        self.timestamp = Date()
        self.framework = framework
        self.operation = operation
        self.additionalInfo = additionalInfo
    }
    
    /// Convert to dictionary for logging
    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "error": error.localizedDescription,
            "timestamp": timestamp.timeIntervalSince1970,
            "category": error.category.rawValue,
            "severity": error.severity.rawValue
        ]
        
        if let framework = framework {
            dict["framework"] = framework
        }
        
        if let operation = operation {
            dict["operation"] = operation
        }
        
        if let info = additionalInfo {
            dict["additionalInfo"] = info
        }
        
        return dict
    }
}

// MARK: - Error Types

enum ErrorSeverity: String {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}

enum ErrorCategory: String {
    case initialization = "INITIALIZATION"
    case service = "SERVICE"
    case inference = "INFERENCE"
    case memory = "MEMORY"
    case network = "NETWORK"
    case other = "OTHER"
}

// MARK: - Error Recovery Strategies

/// Default error recovery implementation
class DefaultErrorRecoveryStrategy: ErrorRecoverable {
    func canRecover(from error: LLMError) -> Bool {
        error.isRecoverable
    }
    
    func attemptRecovery(from error: LLMError) async throws {
        switch error {
        case .notInitialized:
            // Attempt to reinitialize with default model
            throw error // Placeholder - actual implementation depends on service
            
        case .networkUnavailable:
            // Wait and retry
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
        case .insufficientMemory:
            // Trigger memory cleanup
            await MemoryManager.shared.performCleanup()
            
        default:
            throw error
        }
    }
}

// MARK: - Error Reporting

/// Protocol for error reporting
protocol ErrorReporter {
    func report(_ context: ErrorContext)
    func reportBatch(_ contexts: [ErrorContext])
}

/// Default error reporter for logging
class LoggingErrorReporter: ErrorReporter {
    static let shared = LoggingErrorReporter()
    
    func report(_ context: ErrorContext) {
        print("[LLM Error] \(context.error.category) - \(context.error.localizedDescription)")
        if let framework = context.framework {
            print("  Framework: \(framework)")
        }
        if let operation = context.operation {
            print("  Operation: \(operation)")
        }
    }
    
    func reportBatch(_ contexts: [ErrorContext]) {
        contexts.forEach { report($0) }
    }
}

// MARK: - Error Aggregation

/// Aggregate multiple errors
struct AggregatedError: LocalizedError {
    let errors: [Error]
    let primaryError: Error
    
    init(errors: [Error]) {
        self.errors = errors
        self.primaryError = errors.first ?? LLMError.unknown("No errors provided")
    }
    
    var errorDescription: String? {
        if errors.count == 1 {
            return primaryError.localizedDescription
        }
        return "Multiple errors occurred: \(errors.map { $0.localizedDescription }.joined(separator: "; "))"
    }
    
    var recoverySuggestion: String? {
        if let llmError = primaryError as? LLMError {
            return llmError.recoverySuggestion
        }
        return nil
    }
}