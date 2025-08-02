//
//  UnifiedModelError.swift
//  RunAnywhere SDK
//
//  Unified error types for model operations
//

import Foundation

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
