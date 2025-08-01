//
//  BundledModelsService.swift
//  RunAnywhereAI
//
//  Minimal stub for bundled models management
//

import Foundation
import RunAnywhereSDK

@MainActor
class BundledModelsService: ObservableObject {
    static let shared = BundledModelsService()

    @Published var installedModels: [String] = []
    @Published var isInstalling = false

    private init() {
        // Initialize with some default bundled models
        installedModels = ["phi-3-mini", "gemma-2b"]
    }

    // MARK: - Installation Methods

    func installBundledModels() async -> Bool {
        isInstalling = true
        defer { isInstalling = false }

        // Simulate installation process
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // In a real implementation, this would:
        // 1. Copy models from app bundle to documents directory
        // 2. Register them with the SDK
        // 3. Update installedModels list

        return true
    }

    func getBundledModelPaths() -> [String: URL] {
        var paths: [String: URL] = [:]

        // Check if models exist in app bundle
        if let bundlePath = Bundle.main.path(forResource: "phi-3-mini", ofType: "gguf") {
            paths["phi-3-mini"] = URL(fileURLWithPath: bundlePath)
        }

        if let bundlePath = Bundle.main.path(forResource: "gemma-2b", ofType: "gguf") {
            paths["gemma-2b"] = URL(fileURLWithPath: bundlePath)
        }

        return paths
    }

    func isModelInstalled(_ modelName: String) -> Bool {
        return installedModels.contains(modelName)
    }

    func getInstalledModelCount() -> Int {
        return installedModels.count
    }
}
