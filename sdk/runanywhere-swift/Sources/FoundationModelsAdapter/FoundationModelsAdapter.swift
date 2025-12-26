import Foundation
import RunAnywhere
import OSLog

// Import FoundationModels with conditional compilation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Adapter for Apple's native Foundation Models framework (iOS 26.0+)
/// Uses Apple's built-in language models without requiring external model files
/// Note: Foundation Models (Apple Intelligence) requires iOS 26.0+ or macOS 26.0+
@available(iOS 26.0, *)
public class FoundationModelsAdapter: UnifiedFrameworkAdapter {
    public var framework: LLMFramework { .foundationModels }
    public let supportedModalities: Set<FrameworkModality> = [.textToText]
    public var supportedFormats: [ModelFormat] {
        // Foundation Models doesn't use file formats - it's built-in
        [.mlmodel, .mlpackage]
    }

    private var hardwareConfig: HardwareConfiguration?
    private let logger = Logger(subsystem: "com.runanywhere.FoundationModels", category: "FoundationModelsAdapter")

    public init() {}

    /// Register the Foundation Models service provider with ModuleRegistry
    @MainActor
    public func onRegistration() {
        logger.info("📝 Registering Foundation Models adapter...")
        
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            logger.warning("⚠️ Foundation Models not available: iOS 26.0+ (or macOS 26.0+) required")
            return
        }
        
        ModuleRegistry.shared.registerLLM(FoundationModelsServiceProvider.shared)
        logger.info("✅ Registered FoundationModelsServiceProvider with ModuleRegistry")
        #else
        logger.warning("⚠️ FoundationModels framework not available - adapter will not function")
        #endif
    }

    public func canHandle(model: ModelInfo) -> Bool {
        // Foundation Models doesn't need external model files
        // It can handle any request as it uses Apple's built-in models
        guard #available(iOS 26.0, macOS 26.0, *) else {
            logger.debug("Foundation Models not available: iOS 26.0+ (or macOS 26.0+) required")
            return false
        }

        // Check if the model name indicates it's for Foundation Models
        let canHandle = model.name.lowercased().contains("foundation") ||
               model.name.lowercased().contains("apple") ||
               model.id == "foundation-models-default" ||
               model.preferredFramework == .foundationModels ||
               model.compatibleFrameworks.contains(.foundationModels)
        
        if canHandle {
            logger.info("✅ Foundation Models adapter can handle model: \(model.id) (\(model.name))")
        } else {
            logger.debug("❌ Foundation Models adapter cannot handle model: \(model.id) (\(model.name))")
        }
        
        return canHandle
    }

    public func createService(for modality: FrameworkModality) -> Any? {
        guard modality == .textToText else { return nil }
        return FoundationModelsService(hardwareConfig: hardwareConfig)
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        guard modality == .textToText else {
            logger.error("❌ Foundation Models only supports text-to-text modality")
            throw LLMServiceError.modelNotFound("modality not supported")
        }
        
        logger.info("🚀 Loading Foundation Models for model: \(model.id) (\(model.name))")
        
        // Foundation Models doesn't need to load external models
        // It uses Apple's built-in models
        let service = FoundationModelsService(hardwareConfig: hardwareConfig)
        
        do {
            logger.info("Initializing Foundation Models service...")
            try await service.initialize(modelPath: "built-in")
            logger.info("✅ Foundation Models service initialized successfully")
            return service
        } catch {
            logger.error("❌ Failed to initialize Foundation Models: \(error.localizedDescription)")
            if let llmError = error as? LLMServiceError {
                throw llmError
            }
            throw LLMServiceError.generationFailed(error)
        }
    }

    public func configure(with hardware: HardwareConfiguration) async {
        self.hardwareConfig = hardware
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        // Foundation Models memory is managed by the system
        // Estimate based on typical usage
        return 500_000_000 // 500MB typical for system models
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        return HardwareConfiguration(
            primaryAccelerator: .neuralEngine,
            memoryMode: .balanced,
            threadCount: 2
        )
    }

    /// Get a built-in model info for Foundation Models
    public func getProvidedModels() -> [ModelInfo] {
        // Return a built-in model that represents Foundation Models
        return [
            ModelInfo(
                id: "foundation-models-default",
                name: "Apple Foundation Models",
                category: .language,  // Language model category for LLM context filtering
                format: .mlmodel,
                downloadURL: nil,  // No download needed - built-in
                localPath: URL(string: "builtin://foundation-models"),  // Mark as built-in for ModelLoadingService
                downloadSize: nil,
                memoryRequired: 500_000_000,  // 500MB estimated
                compatibleFrameworks: [.foundationModels],
                preferredFramework: .foundationModels,
                contextLength: 4096,  // Estimated context length
                supportsThinking: false,
                thinkingPattern: nil,
                metadata: ModelInfoMetadata(
                    author: "Apple",
                    license: "Apple EULA",
                    description: "Apple's built-in on-device language model (requires iOS 26.0+ or macOS 26.0+ with Apple Intelligence enabled)"
                ),
                source: .defaults  // Built-in, not from remote
            )
        ]
    }
}
