//
//  RAG.swift
//  RAGRuntime Module
//
//  Unified RAG module - thin wrapper that calls C++ backend registration.
//

import CRACommons
import Foundation
import RAGBackend
import RunAnywhere

// MARK: - RAG Module

/// RAG Runtime module for Retrieval-Augmented Generation.
///
/// Provides document chunking, embedding, vector search, and
/// LLM generation with context capabilities.
///
/// ## Registration
///
/// ```swift
/// import RAGRuntime
///
/// // Register the backend
/// try RAGModule.register()
/// ```
public enum RAGModule: RunAnywhereModule {
    private static let logger = SDKLogger(category: "RAG")

    // MARK: - Module Info

    /// Current version of the RAG Runtime module
    public static let version = "1.0.0"

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "rag"
    public static let moduleName = "RAG"
    public static let capabilities: Set<SDKComponent> = [.llm]
    public static let defaultPriority: Int = 100

    /// RAG uses ONNX for embeddings and LlamaCPP for generation
    public static let inferenceFramework: InferenceFramework = .onnx

    // MARK: - Registration State

    private static var isRegistered = false

    // MARK: - Registration

    /// Register RAG backend with the C++ service registry.
    ///
    /// This calls `rac_backend_rag_register()` to register the
    /// RAG service provider with the C++ commons layer.
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// - Parameter priority: Ignored (C++ uses its own priority system)
    @MainActor
    public static func register(priority _: Int = 100) {
        guard !isRegistered else {
            logger.debug("RAG already registered, returning")
            return
        }

        logger.info("Registering RAG backend with C++ registry...")

        let result = rac_backend_rag_register()

        // RAC_ERROR_MODULE_ALREADY_REGISTERED is OK
        if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            let errorMsg = String(cString: rac_error_message(result))
            logger.error("RAG registration failed: \(errorMsg)")
            return
        }

        isRegistered = true
        logger.info("RAG backend registered successfully")
    }

    /// Unregister the RAG backend from C++ registry.
    public static func unregister() {
        guard isRegistered else { return }

        _ = rac_backend_rag_unregister()
        isRegistered = false
        logger.info("RAG backend unregistered")
    }
}

// MARK: - Auto-Registration

extension RAGModule {
    /// Enable auto-registration for this module.
    /// Access this property to trigger C++ backend registration.
    public static let autoRegister: Void = {
        Task { @MainActor in
            RAGModule.register()
        }
    }()
}
