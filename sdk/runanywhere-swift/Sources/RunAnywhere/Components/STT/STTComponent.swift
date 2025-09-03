import Foundation

/// Speech-to-Text component implementation
@MainActor
public final class STTComponent: BaseComponent, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .stt }

    private nonisolated(unsafe) var sttService: STTService?

    // MARK: - Component Implementation

    public override func initialize(with parameters: any ComponentInitParameters) async throws {
        guard let sttParams = parameters as? STTInitParameters else {
            throw SDKError.validationFailed("Invalid parameters type for STT component")
        }

        try await super.initialize(with: parameters)

        guard let container = serviceContainer else {
            throw SDKError.notInitialized
        }

        // Find appropriate adapter for STT
        let frameworks = container.adapterRegistry.getFrameworks(for: .voiceToText)
        guard let framework = frameworks.first,
              let adapter = container.adapterRegistry.getAdapter(for: framework) else {
            throw SDKError.validationFailed("No STT adapter available")
        }

        // Configure adapter with default hardware config
        let hardwareConfig = HardwareConfiguration()
        await adapter.configure(with: hardwareConfig)

        // Initialize component through adapter
        guard let service = try await adapter.initializeComponent(with: sttParams, for: .voiceToText) as? STTService else {
            throw SDKError.validationFailed("Adapter did not return STTService")
        }
        sttService = service

        await transitionTo(state: .ready)
    }

    public override func cleanup() async throws {
        sttService = nil
        try await super.cleanup()
    }

    // Public accessor for the service
    public func getService() -> STTService? {
        return sttService
    }
}
