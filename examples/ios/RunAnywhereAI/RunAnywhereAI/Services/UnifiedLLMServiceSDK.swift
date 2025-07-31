//
//  UnifiedLLMServiceSDK.swift
//  RunAnywhereAI
//
//  Main service that integrates with RunAnywhere SDK
//

import Foundation
import SwiftUI
import Combine
import RunAnywhereSDK
import Metal

@MainActor
class UnifiedLLMServiceSDK: ObservableObject {
    static let shared = UnifiedLLMServiceSDK()

    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentModel: ModelInfo?
    @Published var progress: ProgressInfo?
    @Published var availableModels: [ModelInfo] = []
    @Published var currentFramework: LLMFramework?

    private let sdk = RunAnywhereSDK.RunAnywhereSDK.shared
    private var cancellables = Set<AnyCancellable>()

    // SDK components that will be registered
    private var registeredAdapters = false

    private init() {
        Task {
            await initializeSDK()
        }
    }

    private func initializeSDK() async {
        do {
            // Get API key from keychain
            let apiKey = KeychainService.shared.getRunAnywhereAPIKey() ?? "demo-api-key"

            // Create SDK configuration
            let config = RunAnywhereSDK.Configuration(
                apiKey: apiKey,
                debugMode: true,
                routingPolicy: .preferDevice,
                memoryThreshold: 500_000_000 // 500MB
            )

            // Initialize SDK
            try await sdk.initialize(with: config)

            // Register our components
            registerSDKComponents()

            // Discover available models
            if let registry = sdk.modelRegistry {
                let sdkModels = await registry.discoverModels()
                availableModels = sdkModels.compactMap { sdkModel in
                    // Convert SDK ModelInfo to sample app ModelInfo
                    ModelInfo.fromSDK(sdkModel)
                }
            }

        } catch {
            self.error = error
            print("Failed to initialize SDK: \(error)")
        }
    }

    private func registerFrameworkAdapters() {
        // Get all adapters from the registry
        let adapters = FrameworkAdapterRegistry.shared.getAllAdapters()

        print("Ready to register \(adapters.count) framework adapters when SDK is integrated")
    }

    private func registerSDKComponents() {
        guard !registeredAdapters else { return }

        // Register our custom framework adapter registry
        sdk.registerAdapterRegistry(FrameworkAdapterRegistrySDK.shared)

        // Register hardware detector for iOS
        let hardwareDetector = iOSHardwareDetector()
        sdk.registerHardwareDetector(hardwareDetector)

        // Register download manager if we have custom implementation
        // sdk.registerDownloadManager(customDownloadManager)

        // Register memory manager if we have custom implementation
        // sdk.registerMemoryManager(customMemoryManager)

        registeredAdapters = true
        print("SDK components registered successfully")
    }

    // MARK: - Public API

    func loadModel(_ identifier: String, framework: LLMFramework? = nil) async {
        isLoading = true
        error = nil

        do {
            // Convert sample app framework to SDK framework if needed
            let sdkFramework: RunAnywhereSDK.LLMFramework? = framework?.toSDKFramework

            // Load model through SDK
            try await sdk.loadModel(identifier, preferredFramework: sdkFramework)

            // Update our state from SDK
            if let model = await sdk.currentModel {
                currentModel = ModelInfo.fromSDK(model)
                currentFramework = currentModel?.framework
            }

            // Subscribe to SDK progress updates
            subscribeToProgress()
        } catch {
            self.error = error
            print("Failed to load model: \(error)")
        }

        isLoading = false
    }

    func generate(_ prompt: String, options: GenerationOptions = .default) async throws -> String {
        // Convert sample app options to SDK options
        let sdkOptions = RunAnywhereSDK.GenerationOptions(
            temperature: options.temperature,
            topK: options.topK,
            topP: options.topP,
            maxTokens: options.maxTokens,
            repetitionPenalty: options.repetitionPenalty,
            stopSequences: options.stopSequences,
            context: nil // Would convert context if needed
        )

        // Generate through SDK
        let result = try await sdk.generate(prompt, options: sdkOptions)

        // Return the generated text
        return result.text
    }

    func streamGenerate(
        _ prompt: String,
        options: GenerationOptions = .default,
        onToken: @escaping (String) -> Void
    ) async throws {
        // Convert options
        let sdkOptions = RunAnywhereSDK.GenerationOptions(
            temperature: options.temperature,
            topK: options.topK,
            topP: options.topP,
            maxTokens: options.maxTokens,
            repetitionPenalty: options.repetitionPenalty,
            stopSequences: options.stopSequences,
            streamingEnabled: true
        )

        // Stream generate through SDK
        let stream = sdk.streamGenerate(prompt, options: sdkOptions)

        // Forward tokens to callback
        for try await token in stream {
            onToken(token)
        }
    }

    func discoverModels() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let registry = sdk.modelRegistry {
                let sdkModels = await registry.discoverModels()
                availableModels = sdkModels.compactMap { ModelInfo.fromSDK($0) }
            }
        } catch {
            self.error = error
            print("Failed to discover models: \(error)")
        }
    }

    func unloadModel() async {
        await sdk.unloadCurrentModel()
        currentModel = nil
        currentFramework = nil
    }

    // MARK: - Model Management

    func downloadModel(_ model: ModelInfo) async throws {
        try await sdk.downloadModel(model.id)
    }

    func deleteModel(_ model: ModelInfo) async throws {
        try await sdk.deleteModel(model.id)
    }

    // MARK: - Configuration

    func configureForProduction() {
        // When SDK is available:
        // sdk.configuration.telemetryEnabled = true
        // sdk.configuration.cacheEnabled = true
        // sdk.configuration.maxMemoryUsage = 4_000_000_000 // 4GB
    }

    func configureForDevelopment() {
        // When SDK is available:
        // sdk.configuration.telemetryEnabled = false
        // sdk.configuration.debugLogging = true
        // sdk.configuration.cacheEnabled = false
    }
}

// MARK: - Progress Info

struct ProgressInfo {
    let stage: String
    let percentage: Double
    let message: String
    let estimatedTimeRemaining: TimeInterval?
}

// MARK: - SDK Integration Extensions

extension UnifiedLLMServiceSDK {
    private func subscribeToProgress() {
        // Subscribe to SDK's progress tracker
        sdk.progressTracker.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sdkProgress in
                self?.progress = ProgressInfo(
                    stage: sdkProgress.currentStage?.rawValue ?? "Unknown",
                    percentage: sdkProgress.percentage,
                    message: sdkProgress.message,
                    estimatedTimeRemaining: sdkProgress.estimatedTimeRemaining
                )
            }
            .store(in: &cancellables)
    }

    private func subscribeToErrors() {
        // Subscribe to SDK error events if available
        NotificationCenter.default.publisher(for: .sdkErrorOccurred)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let error = notification.object as? Error {
                    self?.error = error
                }
            }
            .store(in: &cancellables)
    }
}

// Custom iOS Hardware Detector for SDK
class iOSHardwareDetector: RunAnywhereSDK.HardwareDetector {
    func detectCapabilities() -> RunAnywhereSDK.DeviceCapabilities {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = getAvailableMemory()
        let hasNeuralEngine = detectNeuralEngine()
        let hasGPU = detectGPU()
        let processorCount = ProcessInfo.processInfo.processorCount

        return RunAnywhereSDK.DeviceCapabilities(
            totalMemory: Int64(totalMemory),
            availableMemory: availableMemory,
            hasNeuralEngine: hasNeuralEngine,
            hasGPU: hasGPU,
            processorCount: processorCount
        )
    }

    private func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    private func detectNeuralEngine() -> Bool {
        // Check for Neural Engine availability
        if #available(iOS 14.0, *) {
            // A12 Bionic and later have Neural Engine
            return isDeviceCapable()
        }
        return false
    }

    private func detectGPU() -> Bool {
        // Metal is available on all iOS devices
        return MTLCreateSystemDefaultDevice() != nil
    }

    private func isDeviceCapable() -> Bool {
        // Check device model for Neural Engine support
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }

        // A12 Bionic and later have Neural Engine
        // This is a simplified check - in production, use a comprehensive model list
        if let model = modelCode {
            // iPhone XS, XR and later
            if model.contains("iPhone11") || model.contains("iPhone12") ||
               model.contains("iPhone13") || model.contains("iPhone14") ||
               model.contains("iPhone15") || model.contains("iPhone16") {
                return true
            }
            // iPad Pro 3rd gen and later, iPad Air 4th gen and later
            if model.contains("iPad8") || model.contains("iPad11") ||
               model.contains("iPad13") || model.contains("iPad14") {
                return true
            }
        }

        return false
    }
}

// Framework Adapter Registry that implements SDK protocol
class FrameworkAdapterRegistrySDK: RunAnywhereSDK.FrameworkAdapterRegistry {
    static let shared = FrameworkAdapterRegistrySDK()

    private let localRegistry = FrameworkAdapterRegistry.shared

    func getAdapter(for framework: RunAnywhereSDK.LLMFramework) -> RunAnywhereSDK.FrameworkAdapter? {
        // Convert SDK framework to local framework
        guard let localFramework = LLMFramework(rawValue: framework.rawValue) else { return nil }

        // Get local adapter and wrap it
        guard let localAdapter = localRegistry.getAdapter(for: localFramework) else { return nil }

        // Return wrapped adapter that implements SDK protocol
        // This would need proper implementation when SDK is integrated
        return nil
    }

    func findBestAdapter(for model: RunAnywhereSDK.ModelInfo) -> RunAnywhereSDK.FrameworkAdapter? {
        // Implementation would score adapters and return best match
        return nil
    }

    func register(_ adapter: RunAnywhereSDK.FrameworkAdapter) {
        // Implementation would store SDK adapters
    }
}

// Notification names for SDK events
extension Notification.Name {
    static let sdkErrorOccurred = Notification.Name("RunAnywhereSDKErrorOccurred")
    static let sdkProgressUpdated = Notification.Name("RunAnywhereSDKProgressUpdated")
}
