//
//  BenchmarkLaunchHandler.swift
//  RunAnywhereAI
//
//  Handles auto-launch benchmark from CLI
//  Supports passing model URLs for automatic download and benchmark
//

import Foundation
import SwiftUI
import RunAnywhere

/// Handles benchmark auto-launch from CLI
@MainActor
class BenchmarkLaunchHandler: ObservableObject {
    static let shared = BenchmarkLaunchHandler()
    
    @Published var shouldAutoStart = false
    @Published var autoConfig: BenchmarkConfig?
    @Published var autoModelIds: [String]?
    @Published var navigateToBenchmark = false
    
    // For dynamic model download
    @Published var pendingModelURL: URL?
    @Published var pendingModelName: String?
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?
    
    private init() {
        checkLaunchArguments()
    }
    
    /// Handle deep link URL for benchmark automation
    /// Format: runanywhere://benchmark?config=quick&model_url=https://...
    func handleURL(_ url: URL) {
        guard url.scheme == "runanywhere", url.host == "benchmark" else { return }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        
        var config = "quick"
        var modelURL: String?
        var modelName: String?
        
        for item in queryItems {
            switch item.name {
            case "config":
                config = item.value ?? "quick"
            case "model_url":
                modelURL = item.value?.removingPercentEncoding
            case "model_name":
                modelName = item.value?.removingPercentEncoding
            default:
                break
            }
        }
        
        print("📲 Received benchmark URL:")
        print("   Config: \(config)")
        print("   Model URL: \(modelURL ?? "none")")
        
        // Set config
        autoConfig = parseConfig(config)
        
        // If model URL provided, register and download it
        if let urlString = modelURL, let url = URL(string: urlString) {
            pendingModelURL = url
            pendingModelName = modelName ?? extractModelName(from: url)
            navigateToBenchmark = true
            shouldAutoStart = true
        } else {
            // No model URL, just start with existing models
            navigateToBenchmark = true
            shouldAutoStart = true
        }
    }
    
    /// Register and download a model from URL
    func downloadAndBenchmarkModel() async -> String? {
        guard let url = pendingModelURL else { return nil }
        
        let modelName = pendingModelName ?? extractModelName(from: url)
        let modelId = "cli-\(modelName.lowercased().replacingOccurrences(of: " ", with: "-"))"
        
        print("📥 Registering model: \(modelName)")
        print("   URL: \(url)")
        print("   ID: \(modelId)")
        
        isDownloadingModel = true
        downloadProgress = 0
        downloadError = nil
        
        do {
            // Register the model with the SDK
            RunAnywhere.registerModel(
                id: modelId,
                name: modelName,
                url: url,
                framework: .llamaCpp,  // Assume GGUF = LlamaCpp
                memoryRequirement: 500_000_000  // Default estimate
            )
            
            print("✅ Model registered: \(modelId)")
            
            // Download the model
            print("📥 Starting download...")
            
            // Use the SDK's download functionality
            try await RunAnywhere.downloadModel(modelId) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                    print("   Download: \(Int(progress * 100))%")
                }
            }
            
            print("✅ Model downloaded!")
            isDownloadingModel = false
            
            // Clear pending
            pendingModelURL = nil
            pendingModelName = nil
            
            return modelId
            
        } catch {
            print("❌ Download failed: \(error)")
            downloadError = error.localizedDescription
            isDownloadingModel = false
            return nil
        }
    }
    
    /// Extract model name from URL
    private func extractModelName(from url: URL) -> String {
        let filename = url.lastPathComponent
        // Remove extension like .gguf
        let name = filename.replacingOccurrences(of: ".gguf", with: "")
            .replacingOccurrences(of: ".GGUF", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return name.isEmpty ? "Custom Model" : name
    }
    
    /// Trigger auto-benchmark from URL scheme (for physical devices)
    func triggerAutoBenchmark(config: String, models: String?) {
        shouldAutoStart = true
        navigateToBenchmark = true
        autoConfig = parseConfig(config)
        
        if let models = models, models != "all" {
            autoModelIds = models.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        } else {
            autoModelIds = nil // nil means "all"
        }
        
        print("🚀 Auto-benchmark triggered!")
        print("   Config: \(autoConfig?.warmupIterations ?? 0) warmups, \(autoConfig?.testIterations ?? 0) iterations")
        print("   Models: \(autoModelIds?.joined(separator: ", ") ?? "all")")
    }
    
    /// Check if app was launched with benchmark arguments from CLI
    func checkLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        
        // Log all arguments for debugging
        print("📋 Launch arguments received: \(args)")
        
        // Check for auto-benchmark flag (multiple formats for compatibility)
        let hasBenchmarkAuto = args.contains("-benchmark_auto") || 
                               args.contains("--benchmark_auto") ||
                               args.contains("benchmark_auto")
        
        // Check if "true" follows the flag
        var shouldStart = false
        for (index, arg) in args.enumerated() {
            if arg.contains("benchmark_auto") && index + 1 < args.count {
                let nextArg = args[index + 1].lowercased()
                if nextArg == "true" || nextArg == "1" || nextArg == "yes" {
                    shouldStart = true
                    break
                }
            }
            // Also check for combined format like "-benchmark_auto=true"
            if arg.contains("benchmark_auto=true") || arg.contains("benchmark_auto=1") {
                shouldStart = true
                break
            }
        }
        
        if shouldStart || hasBenchmarkAuto {
            shouldAutoStart = true
            navigateToBenchmark = true
            
            // Parse config
            for (index, arg) in args.enumerated() {
                if arg.contains("benchmark_config") && index + 1 < args.count {
                    let configStr = args[index + 1]
                    autoConfig = parseConfig(configStr)
                    break
                }
            }
            if autoConfig == nil {
                autoConfig = .default
            }
            
            // Parse models
            for (index, arg) in args.enumerated() {
                if arg.contains("benchmark_models") && index + 1 < args.count {
                    let modelsStr = args[index + 1]
                    if modelsStr != "all" {
                        autoModelIds = modelsStr.split(separator: ",").map { String($0) }
                    }
                    break
                }
            }
            
            print("🚀 Auto-benchmark mode activated!")
            print("   Config: \(autoConfig?.warmupIterations ?? 0) warmups, \(autoConfig?.testIterations ?? 0) iterations")
            print("   Models: \(autoModelIds?.joined(separator: ", ") ?? "all")")
        } else {
            print("ℹ️ Normal launch (no auto-benchmark)")
        }
    }
    
    private func parseConfig(_ configStr: String) -> BenchmarkConfig {
        // Try to parse JSON config, fallback to presets
        if configStr.contains("warmupIterations") {
            if let data = configStr.data(using: .utf8),
               let config = try? JSONDecoder().decode(BenchmarkConfig.self, from: data) {
                return config
            }
        }
        
        // Check for preset names
        switch configStr.lowercased() {
        case "quick":
            return .quick
        case "comprehensive":
            return .comprehensive
        default:
            return .default
        }
    }
}

/// View modifier that auto-navigates to benchmark tab and starts benchmark
struct AutoBenchmarkModifier: ViewModifier {
    @ObservedObject var handler = BenchmarkLaunchHandler.shared
    @Binding var selectedTab: Int
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                if handler.shouldAutoStart {
                    // Navigate to benchmark tab (index 4)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        selectedTab = 4
                    }
                }
            }
    }
}

extension View {
    func handleAutoBenchmark(selectedTab: Binding<Int>) -> some View {
        modifier(AutoBenchmarkModifier(selectedTab: selectedTab))
    }
}
