import Foundation

/// Service for checking model dependencies
public class DependencyChecker {

    // MARK: - Properties

    private let logger = SDKLogger(category: "DependencyChecker")
    private let frameworkRegistry: FrameworkAdapterRegistry

    // MARK: - Initialization

    public init(frameworkRegistry: FrameworkAdapterRegistry) {
        self.frameworkRegistry = frameworkRegistry
    }

    // MARK: - Public Methods

    /// Validates that all required dependencies for a model are available
    /// - Parameter model: The model to check dependencies for
    /// - Returns: Array of missing dependencies, empty if all dependencies are satisfied
    public func checkDependencies(for model: ModelInfo) async throws -> [MissingDependency] {
        var missing: [MissingDependency] = []

        logger.debug("Checking dependencies for model: \(model.id)")

        // Check tokenizer dependencies
        if let tokenizerFormat = model.tokenizerFormat {
            let available = await isTokenizerAvailable(tokenizerFormat)
            if !available {
                missing.append(MissingDependency(
                    name: "\(tokenizerFormat.rawValue) tokenizer",
                    type: .tokenizer
                ))
                logger.warning("Missing tokenizer: \(tokenizerFormat.rawValue)")
            }
        }

        // Check framework dependencies
        for framework in model.compatibleFrameworks {
            if !isFrameworkAvailable(framework) {
                missing.append(MissingDependency(
                    name: framework.rawValue,
                    type: .framework
                ))
                logger.warning("Missing framework: \(framework.rawValue)")
            }
        }

        // Check for required configuration files
        if let configDeps = await checkConfigurationDependencies(for: model) {
            missing.append(contentsOf: configDeps)
        }

        // Check for companion models (e.g., encoder/decoder pairs)
        if let companionDeps = await checkCompanionModels(for: model) {
            missing.append(contentsOf: companionDeps)
        }

        logger.info("Dependency check complete. Missing: \(missing.count)")

        return missing
    }

    // MARK: - Private Methods

    private func isTokenizerAvailable(_ format: TokenizerFormat) async -> Bool {
        // Check if tokenizer adapter is registered
        // In a real implementation, this would check UnifiedTokenizerManager
        switch format {
        case .sentencePiece, .bpe, .wordPiece:
            return true // These are commonly available
        default:
            return false
        }
    }

    private func isFrameworkAvailable(_ framework: LLMFramework) -> Bool {
        // Check if framework adapter is registered
        // For now, checking against known frameworks
        switch framework {
        #if canImport(CoreML)
        case .coreML:
            return true
        #endif
        case .tensorFlowLite:
            return Bundle.main.path(forResource: "TensorFlowLiteC", ofType: "framework") != nil
        default:
            return true // Placeholder for other frameworks
        }
    }

    private func checkConfigurationDependencies(for model: ModelInfo) async -> [MissingDependency]? {
        var missing: [MissingDependency] = []

        // Check for required configuration files based on model metadata
        if let tags = model.metadata?.tags, tags.contains("diffusion") {
            // Diffusion models often need scheduler configs
            let exists = await configurationExists("scheduler_config.json", for: model)
            if !exists {
                missing.append(MissingDependency(
                    name: "scheduler_config.json",
                    type: .configuration
                ))
            }
        }

        return missing.isEmpty ? nil : missing
    }

    private func checkCompanionModels(for model: ModelInfo) async -> [MissingDependency]? {
        var missing: [MissingDependency] = []

        // Check for encoder/decoder pairs
        if let tags = model.metadata?.tags, tags.contains("encoder") {
            let decoderName = model.id.replacingOccurrences(of: "encoder", with: "decoder")
            let exists = await companionModelExists(decoderName)
            if !exists {
                missing.append(MissingDependency(
                    name: decoderName,
                    type: .model
                ))
            }
        }

        return missing.isEmpty ? nil : missing
    }

    private func configurationExists(_ configName: String, for model: ModelInfo) async -> Bool {
        // Check if configuration file exists
        // This is a placeholder - real implementation would check storage
        return true
    }

    private func companionModelExists(_ modelName: String) async -> Bool {
        // Check if companion model exists
        // This is a placeholder - real implementation would check registry
        return true
    }
}
