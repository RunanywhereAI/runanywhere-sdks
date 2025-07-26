import Foundation
import SwiftUI

// MARK: - Framework Configuration

protocol FrameworkConfiguration: Codable {
    var framework: LLMFramework { get }
    func apply(to service: LLMProtocol)
}

// MARK: - llama.cpp Configuration

struct LlamaCppConfiguration: FrameworkConfiguration {
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
    
    func apply(to service: LLMProtocol) {
        // Apply configuration to llama.cpp service
        // In real implementation, this would configure the actual service
    }
}

// MARK: - Core ML Configuration

struct CoreMLConfiguration: FrameworkConfiguration {
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
    
    func apply(to service: LLMProtocol) {
        // Apply configuration to Core ML service
    }
}

// MARK: - MLX Configuration

struct MLXConfiguration: FrameworkConfiguration {
    let framework = LLMFramework.mlx
    
    var maxBatchSize: Int = 256
    var useMemoryMapping: Bool = true
    var metalOptimization: Bool = true
    var quantizationBits: Int = 4
    var groupSize: Int = 64
    var streamBufferSize: Int = 1024
    
    func apply(to service: LLMProtocol) {
        // Apply configuration to MLX service
    }
}

// MARK: - ONNX Runtime Configuration

struct ONNXConfiguration: FrameworkConfiguration {
    let framework = LLMFramework.onnx
    
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
    
    func apply(to service: LLMProtocol) {
        // Apply configuration to ONNX Runtime service
    }
}

// MARK: - Configuration Manager

@MainActor
class FrameworkConfigurationManager: ObservableObject {
    static let shared = FrameworkConfigurationManager()
    
    @Published var configurations: [LLMFramework: any FrameworkConfiguration] = [:]
    
    private let configsKey = "framework_configurations"
    
    init() {
        loadConfigurations()
        
        // Set defaults if not loaded
        if configurations.isEmpty {
            setDefaultConfigurations()
        }
    }
    
    private func setDefaultConfigurations() {
        configurations[.llamaCpp] = LlamaCppConfiguration()
        configurations[.coreML] = CoreMLConfiguration()
        configurations[.mlx] = MLXConfiguration()
        configurations[.onnx] = ONNXConfiguration()
    }
    
    func configuration(for framework: LLMFramework) -> any FrameworkConfiguration {
        if let config = configurations[framework] {
            return config
        }
        
        // Return default configuration
        switch framework {
        case .llamaCpp:
            return LlamaCppConfiguration()
        case .coreML:
            return CoreMLConfiguration()
        case .mlx:
            return MLXConfiguration()
        case .onnx:
            return ONNXConfiguration()
        default:
            // Return a generic configuration for other frameworks
            return GenericConfiguration(framework: framework)
        }
    }
    
    func updateConfiguration(_ config: any FrameworkConfiguration) {
        configurations[config.framework] = config
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

struct GenericConfiguration: FrameworkConfiguration {
    let framework: LLMFramework
    
    func apply(to service: LLMProtocol) {
        // No specific configuration for generic frameworks
    }
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
                case .onnx:
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
    @State private var config = LlamaCppConfiguration()
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Context Settings") {
            Stepper("Context Size: \(config.contextSize)", value: $config.contextSize, in: 512...8192, step: 512)
            Stepper("Batch Size: \(config.batchSize)", value: $config.batchSize, in: 128...2048, step: 128)
        }
        
        Section("Performance") {
            Stepper("Threads: \(config.threads)", value: $config.threads, in: 1...16)
            Stepper("GPU Layers: \(config.gpuLayers)", value: $config.gpuLayers, in: 0...100)
        }
        
        Section("Memory Options") {
            Toggle("Use Memory Mapping", isOn: $config.useMMap)
            Toggle("Lock Memory", isOn: $config.useMlock)
            Toggle("NUMA Optimization", isOn: $config.numa)
        }
        
        Section("Advanced") {
            Toggle("F16 KV Cache", isOn: $config.f16KV)
            Toggle("Logits All", isOn: $config.logitsAll)
            Toggle("Embedding Mode", isOn: $config.embedding)
        }
        .onChange(of: config) { newConfig in
            configManager.updateConfiguration(newConfig)
        }
        .onAppear {
            if let loaded = configManager.configuration(for: .llamaCpp) as? LlamaCppConfiguration {
                config = loaded
            }
        }
    }
}

struct CoreMLConfigView: View {
    @State private var config = CoreMLConfiguration()
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Compute Units") {
            Picker("Compute Units", selection: $config.computeUnits) {
                ForEach(CoreMLConfiguration.ComputeUnits.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
        }
        
        Section("Performance") {
            Toggle("Enable Low Precision", isOn: $config.enableLowPrecision)
            Stepper("Max Concurrent Requests: \(config.maxConcurrentRequests)", 
                   value: $config.maxConcurrentRequests, in: 1...4)
        }
        
        Section("Memory") {
            TextField("Memory Key Path", text: $config.memoryKeyPath)
                .autocapitalization(.none)
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
    @State private var config = MLXConfiguration()
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Batch Processing") {
            Stepper("Max Batch Size: \(config.maxBatchSize)", 
                   value: $config.maxBatchSize, in: 32...1024, step: 32)
            Stepper("Stream Buffer Size: \(config.streamBufferSize)", 
                   value: $config.streamBufferSize, in: 256...4096, step: 256)
        }
        
        Section("Optimization") {
            Toggle("Use Memory Mapping", isOn: $config.useMemoryMapping)
            Toggle("Metal Optimization", isOn: $config.metalOptimization)
        }
        
        Section("Quantization") {
            Stepper("Quantization Bits: \(config.quantizationBits)", 
                   value: $config.quantizationBits, in: 2...8)
            Stepper("Group Size: \(config.groupSize)", 
                   value: $config.groupSize, in: 32...256, step: 32)
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
    @State private var config = ONNXConfiguration()
    @StateObject private var configManager = FrameworkConfigurationManager.shared
    
    var body: some View {
        Section("Execution Provider") {
            Picker("Provider", selection: $config.executionProvider) {
                ForEach(ONNXConfiguration.ExecutionProvider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        
        Section("Graph Optimization") {
            Picker("Optimization Level", selection: $config.graphOptimizationLevel) {
                ForEach(ONNXConfiguration.GraphOptimizationLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
        }
        
        Section("Threading") {
            Stepper("Inter-Op Threads: \(config.interOpNumThreads == 0 ? "Auto" : "\(config.interOpNumThreads)")", 
                   value: $config.interOpNumThreads, in: 0...16)
            Stepper("Intra-Op Threads: \(config.intraOpNumThreads == 0 ? "Auto" : "\(config.intraOpNumThreads)")", 
                   value: $config.intraOpNumThreads, in: 0...16)
        }
        
        Section("Advanced") {
            Toggle("Enable Memory Pattern", isOn: $config.enableMemoryPattern)
            Toggle("Enable Profiling", isOn: $config.enableProfiling)
        }
        .onChange(of: config) { newConfig in
            configManager.updateConfiguration(newConfig)
        }
        .onAppear {
            if let loaded = configManager.configuration(for: .onnx) as? ONNXConfiguration {
                config = loaded
            }
        }
    }
}