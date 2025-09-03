import Foundation

/// Text-to-Speech component implementation
@MainActor
public final class TTSComponent: BaseComponent, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .tts }

    private nonisolated(unsafe) var ttsService: TextToSpeechService?

    // MARK: - Component Implementation

    public override func initialize(with parameters: any ComponentInitParameters) async throws {
        guard let ttsParams = parameters as? TTSInitParameters else {
            throw SDKError.validationFailed("Invalid parameters type for TTS component")
        }

        try await super.initialize(with: parameters)

        guard let container = serviceContainer else {
            throw SDKError.notInitialized
        }

        // Find appropriate adapter for TTS (optional - can use system TTS)
        let frameworks = container.adapterRegistry.getFrameworks(for: .textToVoice)
        if let framework = frameworks.first,
           let adapter = container.adapterRegistry.getAdapter(for: framework) {

            // Configure adapter with default hardware config
            let hardwareConfig = HardwareConfiguration()
            await adapter.configure(with: hardwareConfig)

            // Initialize component through adapter
            guard let service = try await adapter.initializeComponent(with: ttsParams, for: .textToVoice) as? TextToSpeechService else {
                throw SDKError.validationFailed("Adapter did not return TextToSpeechService")
            }
            ttsService = service
        } else {
            // Use system TTS as fallback
            logger.info("Using system TTS - no adapter available")
        }

        await transitionTo(state: .ready)
    }

    public override func cleanup() async throws {
        ttsService = nil
        try await super.cleanup()
    }

    // Public accessor for the service
    public func getService() -> TextToSpeechService? {
        return ttsService
    }
}
