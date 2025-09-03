import Foundation

// MARK: - LLM Component Implementation

/// Language Model component implementation
@MainActor
public final class LLMComponent: BaseComponent, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .llm }

    private nonisolated(unsafe) var llmService: LLMService?

    // MARK: - Service Access

    public func getService() -> LLMService? {
        return llmService
    }

    // MARK: - Component Initialization

    public override func initialize(with parameters: any ComponentInitParameters) async throws {
        // Ensure we have LLM-specific parameters
        guard let llmParams = parameters as? LLMInitParameters else {
            throw SDKError.validationFailed("Invalid parameters type for LLM component")
        }

        // Call base initialization
        try await super.initialize(with: parameters)

        guard let container = serviceContainer else {
            throw SDKError.notInitialized
        }

        // Find appropriate adapter for LLM
        let frameworks = container.adapterRegistry.getFrameworks(for: .textToText)
        guard let framework = frameworks.first,
              let adapter = container.adapterRegistry.getAdapter(for: framework) else {
            throw SDKError.validationFailed("No LLM adapter available")
        }

        // Configure adapter with default hardware config
        let hardwareConfig = HardwareConfiguration()
        await adapter.configure(with: hardwareConfig)

        // Initialize component through adapter
        guard let service = try await adapter.initializeComponent(with: llmParams, for: .textToText) as? LLMService else {
            throw SDKError.validationFailed("Adapter did not return LLMService")
        }
        llmService = service

        // Mark as ready
        await transitionTo(state: .ready)
    }

    // MARK: - Cleanup

    public override func cleanup() async throws {
        llmService = nil
        try await super.cleanup()
    }
}
