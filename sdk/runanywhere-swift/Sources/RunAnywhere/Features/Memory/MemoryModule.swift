//
//  MemoryModule.swift
//  RunAnywhere SDK
//
//  Module registration for vector memory / RAG capability.
//

import Foundation

/// Memory module for vector similarity search
public enum MemoryModule: RunAnywhereModule {
    public static let moduleId = "memory"
    public static let moduleName = "Vector Memory"
    public static let capabilities: Set<SDKComponent> = [.memory]
    public static let defaultPriority: Int = 100
    public static let inferenceFramework: InferenceFramework = .builtIn
}
