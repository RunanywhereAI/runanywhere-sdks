import Foundation

/// Voice Activity Detection component implementation
@MainActor
public final class VADComponent: BaseComponent, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .vad }

    private nonisolated(unsafe) var vadService: VADService?

    // MARK: - Component Implementation

    public override func initialize(with parameters: any ComponentInitParameters) async throws {
        guard let vadParams = parameters as? VADInitParameters else {
            throw SDKError.validationFailed("Invalid parameters type for VAD component")
        }

        try await super.initialize(with: parameters)

        // Create SimpleEnergyVAD directly - no adapter needed
        vadService = SimpleEnergyVAD(
            sampleRate: vadParams.sampleRate,
            frameLength: Float(vadParams.frameLength),
            energyThreshold: Float(vadParams.energyThreshold)
        )

        await transitionTo(state: .ready)
    }

    public override func cleanup() async throws {
        vadService = nil
        try await super.cleanup()
    }

    // Public accessor for the service
    public func getService() -> VADService? {
        return vadService
    }
}
