//
//  ModelFormatManager.swift
//  RunAnywhereAI
//
//  Manages model format handlers for different frameworks
//

import Foundation

// MARK: - Model Format Manager

class ModelFormatManager {
    static let shared = ModelFormatManager()

    private var handlers: [String: ModelFormatHandler] = [:]

    private init() {
        // Register default handlers
        registerDefaultHandlers()
    }

    private func registerDefaultHandlers() {
        // Register framework-specific handlers
        registerHandler(SwiftTransformersModelHandler(), for: "SwiftTransformers")
        registerHandler(CoreMLFormatHandler(), for: "CoreML")
        registerHandler(MLPackageFormatHandler(), for: "MLPackage")
        registerHandler(BaseModelFormatHandler(), for: "Default")
    }

    /// Register a custom handler for a specific key
    func registerHandler(_ handler: ModelFormatHandler, for key: String) {
        handlers[key] = handler
    }

    /// Get the appropriate handler for a given URL and format
    func getHandler(for url: URL, format: ModelFormat) -> ModelFormatHandler {
        // First check if we have a framework-specific handler based on the path
        if url.path.contains("/SwiftTransformers/") {
            if let handler = handlers["SwiftTransformers"] {
                return handler
            }
        } else if url.path.contains("/CoreML/") {
            if let handler = handlers["CoreML"] {
                return handler
            }
        }

        // Then check by format
        switch format {
        case .mlPackage:
            return handlers["MLPackage"] ?? handlers["Default"]!
        case .coreML:
            return handlers["CoreML"] ?? handlers["Default"]!
        default:
            return handlers["Default"]!
        }
    }

    /// Get handler for a specific framework
    func getHandler(for framework: LLMFramework) -> ModelFormatHandler {
        switch framework {
        case .swiftTransformers:
            return handlers["SwiftTransformers"] ?? handlers["Default"]!
        case .coreML:
            return handlers["CoreML"] ?? handlers["Default"]!
        default:
            return handlers["Default"]!
        }
    }

    /// Check if a download requires special handling
    func requiresSpecialDownload(_ url: URL, format: ModelFormat) -> Bool {
        let handler = getHandler(for: url, format: format)
        return handler.requiresSpecialDownload(url: url)
    }
}
