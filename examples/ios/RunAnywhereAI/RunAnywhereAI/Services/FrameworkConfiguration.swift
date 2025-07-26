import Foundation
import SwiftUI

// MARK: - Framework Configuration

protocol FrameworkConfiguration: Codable {
    var framework: LLMFramework { get }
    func apply(to service: LLMService)
}

// MARK: - llama.cpp Configuration

struct LlamaCppLegacyConfiguration: FrameworkConfiguration, Equatable {
    let framework = LLMFramework.llamaCpp
    
    var contextSize: Int32 = 2048
    var batchSize: Int32 = 512
    var threads: Int32 = 4
    var gpuLayers: Int32 = 0
    var useMMap: Bool = true
    var useMlock: Bool = false
    var numa: Bool = false
    var f16KV: Bool = true
    var logitsAll: Bool = false
    var vocabOnly: Bool = false
    var embedding: Bool = false
    
    func apply(to service: LLMService) {
        // Apply configuration to llama.cpp service
        // In real implementation, this would configure the actual service
    }
}

// MARK: - Core ML Configuration

struct CoreMLLegacyConfiguration: FrameworkConfiguration, Equatable {
    let framework = LLMFramework.coreML
    
    enum ComputeUnits: String, CaseIterable, Codable {
        case cpuOnly = "CPU Only"
        case cpuAndGPU = "CPU & GPU"
        case all = "All (CPU, GPU & Neural Engine)"
        case cpuAndNeuralEngine = "CPU & Neural Engine"
    }
    
    var computeUnits: ComputeUnits = .all
    var enableLowPrecision: Bool = true
    var maxConcurrentRequests: Int = 1
    var memoryKeyPath: String = "auto"
    
    func apply(to service: LLMService) {
        // Apply configuration to Core ML service
    }
}

// MARK: - MLX Configuration

struct MLXLegacyConfiguration: FrameworkConfiguration, Equatable {
    let framework = LLMFramework.mlx
    
    var maxBatchSize: Int = 256
    var useMemoryMapping: Bool = true
    var metalOptimization: Bool = true
    var quantizationBits: Int = 4
    var groupSize: Int = 64
    var streamBufferSize: Int = 1024
    
    func apply(to service: LLMService) {
        // Apply configuration to MLX service
    }
}

// MARK: - ONNX Runtime Configuration

struct ONNXLegacyConfiguration: FrameworkConfiguration, Equatable {
    let framework = LLMFramework.onnxRuntime
    
    enum ExecutionProvider: String, CaseIterable, Codable {
        case cpu = "CPU"
        case coreML = "CoreML"
        case xnnpack = "XNNPACK"
    }
    
    enum GraphOptimizationLevel: String, CaseIterable, Codable {
        case disabled = "Disabled"
        case basic = "Basic"
        case extended = "Extended"
        case all = "All"
    }
    
    var executionProvider: ExecutionProvider = .coreML
    var graphOptimizationLevel: GraphOptimizationLevel = .all
    var interOpNumThreads: Int = 0 // 0 = auto
    var intraOpNumThreads: Int = 0 // 0 = auto
    var enableMemoryPattern: Bool = true
    var enableProfiling: Bool = false
    
    func apply(to service: LLMService) {
        // Apply configuration to ONNX Runtime service
    }
}

// MARK: - Configuration Manager

@MainActor
class FrameworkConfigurationManager: ObservableObject {
    static let shared = FrameworkConfigurationManager()
    
    @Published var configurations: [LLMFramework: any LLMFrameworkConfiguration] = [:]
    
    private let configsKey = "framework_configurations"
    
    init() {
        loadConfigurations()
        
        // Set defaults if not loaded
        if configurations.isEmpty {
            setDefaultConfigurations()
        }
    }
    
    private func setDefaultConfigurations() {
        configurations[.llamaCpp] = LlamaCppConfiguration.default
        configurations[.coreML] = CoreMLConfiguration.default
        configurations[.mlx] = MLXConfiguration.default
        configurations[.onnxRuntime] = ONNXConfiguration.default
    }
    
    func configuration(for framework: LLMFramework) -> any LLMFrameworkConfiguration {
        if let config = configurations[framework] {
            return config
        }
        
        // Return default configuration
        switch framework {
        case .llamaCpp:
            return LlamaCppConfiguration.default
        case .coreML:
            return CoreMLConfiguration.default
        case .mlx:
            return MLXConfiguration.default
        case .onnxRuntime:
            return ONNXConfiguration.default
        default:
            // Return a generic configuration for other frameworks
            return GenericLLMConfiguration(framework: framework)
        }
    }
    
    func updateConfiguration(_ config: any LLMFrameworkConfiguration, for framework: LLMFramework) {
        configurations[framework] = config
        saveConfigurations()
    }
    
    private func loadConfigurations() {
        // Load from UserDefaults
        // In a real app, this would properly decode the configurations
    }
    
    private func saveConfigurations() {
        // Save to UserDefaults
        // In a real app, this would properly encode the configurations
    }
}

// MARK: - Generic Configuration

struct GenericConfiguration: FrameworkConfiguration, Equatable {
    let framework: LLMFramework
    
    func apply(to service: LLMService) {
        // No specific configuration for generic frameworks
    }
}

// Generic configuration conforming to LLMFrameworkConfiguration
struct GenericLLMConfiguration: LLMFrameworkConfiguration {
    let framework: LLMFramework
    let enableLogging = true
    let logLevel = LogLevel.info
    let performanceTracking = true
    let memoryLimit: Int64? = nil
}

// MARK: - Configuration Views

struct FrameworkConfigurationView: View {
    let framework: LLMFramework
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                switch framework {
                case .llamaCpp:
                    LlamaCppConfigView()
                case .coreML:
                    CoreMLConfigView()
                case .mlx:
                    MLXConfigView()
                case .onnxRuntime:
                    ONNXConfigView()
                default:
                    Text("No configuration options available for \(framework.displayName)")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("\(framework.displayName) Settings")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Done") { dismiss() }
            )
        }
    }
}

// MARK: - Framework-Specific Config Views

struct LlamaCppConfigView: View {
    @State private var config = LlamaCppConfiguration.default
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Context Settings") {
            Stepper("Context Size: \(config.contextSize)", value: .constant(config.contextSize), in: 512...8192, step: 512)
            Stepper("Batch Size: \(config.batchSize)", value: .constant(config.batchSize), in: 128...2048, step: 128)
        }
        
        Section("Performance") {
            Stepper("Threads: \(config.numberOfThreads)", value: .constant(config.numberOfThreads), in: 1...16)
            Stepper("GPU Layers: \(config.numberOfGPULayers)", value: .constant(config.numberOfGPULayers), in: 0...100)
        }
        
        Section("Memory Options") {
            Toggle("Use Memory Mapping", isOn: .constant(config.mmap))
            Toggle("Lock Memory", isOn: .constant(config.mlock))
        }
        .onChange(of: config) { newConfig in
            configManager.updateConfiguration(newConfig, for: .llamaCpp)
        }
        .onAppear {
            if let loaded = configManager.configuration(for: .llamaCpp) as? LlamaCppConfiguration {
                config = loaded
            }
        }
    }
}

struct CoreMLConfigView: View {
    @State private var config = CoreMLConfiguration.default
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Compute Units") {
            Picker("Compute Units", selection: $config.computeUnits) {
                ForEach(CoreMLConfiguration.ComputeUnits.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
        }
        
        Section("Configuration") {
            HStack {
                Text("Allow Low Precision")
                Spacer()
                Text(config.allowLowPrecision ? "Yes" : "No")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Enable Batching")
                Spacer()
                Text(config.enableBatching ? "Yes" : "No")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Max Batch Size")
                Spacer()
                Text("\(config.maxBatchSize)")
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: config) { newConfig in
            configManager.updateConfiguration(newConfig)
        }
        .onAppear {
            if let loaded = configManager.configuration(for: .coreML) as? CoreMLConfiguration {
                config = loaded
            }
        }
    }
}

struct MLXConfigView: View {
    @State private var config = MLXConfiguration.default
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Configuration") {
            HStack {
                Text("Device")
                Spacer()
                Text(String(describing: config.device))
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Lazy Evaluation")
                Spacer()
                Text(config.lazyEvaluation ? "Yes" : "No")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Unified Memory")
                Spacer()
                Text(config.unifiedMemory ? "Yes" : "No")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Custom Kernels")
                Spacer()
                Text(config.customKernels ? "Yes" : "No")
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: config) { newConfig in
            configManager.updateConfiguration(newConfig)
        }
        .onAppear {
            if let loaded = configManager.configuration(for: .mlx) as? MLXConfiguration {
                config = loaded
            }
        }
    }
}

struct ONNXConfigView: View {
    @State private var config = ONNXConfiguration.default
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Configuration") {
            HStack {
                Text("Execution Provider")
                Spacer()
                Text(String(describing: config.executionProvider))
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Graph Optimization Level")
                Spacer()
                Text("\(config.graphOptimizationLevel)")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Enable Profiling")
                Spacer()
                Text(config.enableProfiling ? "Yes" : "No")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Inter-Op Threads")
                Spacer()
                Text("\(config.interOpNumThreads)")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Intra-Op Threads")
                Spacer()
                Text("\(config.intraOpNumThreads)")
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: config) { newConfig in
            configManager.updateConfiguration(newConfig)
        }
        .onAppear {
            if let loaded = configManager.configuration(for: .onnxRuntime) as? ONNXConfiguration {
                config = loaded
            }
        }
    }
}
