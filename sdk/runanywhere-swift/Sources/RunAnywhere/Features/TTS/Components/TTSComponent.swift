// swiftlint:disable file_length
//
//  TTSComponent.swift
//  RunAnywhere SDK
//
//  Text-to-Speech component with lifecycle management and analytics
//

import AVFoundation
import Foundation

/// Text-to-Speech component following the clean architecture
///
/// This component integrates with the SDK's lifecycle management system
/// and provides analytics tracking for TTS operations.
@MainActor
public final class TTSComponent: BaseComponent<TTSServiceWrapper>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .tts }

    private let logger = SDKLogger(category: "TTSComponent")
    private let ttsConfiguration: TTSConfiguration

    // MARK: - Initialization

    public init(configuration: TTSConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.ttsConfiguration = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    // swiftlint:disable:next function_body_length
    public override func createService() async throws -> TTSServiceWrapper {
        let modelId = ttsConfiguration.voice
        let modelName = modelId

        logger.info("Creating TTS service for modelId: \(modelId)")

        // Check if we already have a cached service via the lifecycle tracker
        if let cachedService = await ModelLifecycleTracker.shared.ttsService(for: modelId) {
            logger.info("Reusing cached TTS service for model: \(modelId)")
            return TTSServiceWrapper(cachedService)
        }

        // Try to get a registered TTS provider from central registry
        let provider = await MainActor.run {
            let ttsProvider = ModuleRegistry.shared.ttsProvider(for: modelId)
            if let ttsProvider = ttsProvider {
                logger.info("Found TTS provider: \(ttsProvider.name) for modelId: \(modelId)")
            } else {
                logger.info("No TTS provider found for modelId: \(modelId), will use system TTS fallback")
            }
            return ttsProvider
        }

        // Determine framework based on provider availability
        let framework: LLMFramework = provider != nil ? .onnx : .systemTTS
        logger.info("Determined framework: \(framework.displayName)")

        // Notify lifecycle manager
        await MainActor.run {
            ModelLifecycleTracker.shared.modelWillLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: .tts
            )
        }

        do {
            let ttsService: any TTSService

            if let provider = provider {
                logger.info("Creating TTS service via provider: \(provider.name)")
                ttsService = try await provider.createTTSService(configuration: ttsConfiguration)
                logger.info("TTS service created successfully via provider")
            } else {
                logger.info("Creating TTS service via DefaultTTSAdapter (system TTS)")
                let defaultAdapter = DefaultTTSAdapter()
                ttsService = try await defaultAdapter.createTTSService(configuration: ttsConfiguration)
                logger.info("TTS service created successfully via DefaultTTSAdapter")
            }

            // Wrap the service
            let wrapper = TTSServiceWrapper(ttsService)

            // Store service in lifecycle tracker for reuse
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .tts,
                    ttsService: ttsService
                )
            }

            logger.info("TTS component service creation completed successfully")
            return wrapper
        } catch {
            logger.error("TTS service creation failed: \(error)")
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: .tts,
                    error: error.localizedDescription
                )
            }
            throw error
        }
    }

    public override func initializeService() async throws {
        guard let wrappedService = service?.wrappedService else { return }

        // Track initialization
        eventBus.publish(ComponentInitializationEvent.componentInitializing(
            component: Self.componentType,
            modelId: nil
        ))

        try await wrappedService.initialize()
    }

    // MARK: - Public API

    /// Synthesize speech from text
    public func synthesize(_ text: String, voice: String? = nil, language: String? = nil) async throws -> TTSOutput {
        try ensureReady()

        let input = TTSInput(
            text: text,
            voiceId: voice,
            language: language
        )
        return try await process(input)
    }

    /// Synthesize with SSML markup
    public func synthesizeSSML(_ ssml: String, voice: String? = nil, language: String? = nil) async throws -> TTSOutput {
        try ensureReady()

        let input = TTSInput(
            text: "",
            ssml: ssml,
            voiceId: voice,
            language: language
        )
        return try await process(input)
    }

    /// Process TTS input
    public func process(_ input: TTSInput) async throws -> TTSOutput { // swiftlint:disable:this function_body_length
        try ensureReady()

        guard let ttsService = service?.wrappedService else {
            throw TTSError.notInitialized
        }

        // Validate input
        try input.validate()

        // Get text to synthesize
        let textToSynthesize = input.ssml ?? input.text

        // Create options from input or use defaults
        let options = input.options ?? TTSOptions(
            voice: input.voiceId ?? ttsConfiguration.voice,
            language: input.language ?? ttsConfiguration.language,
            rate: ttsConfiguration.speakingRate,
            pitch: ttsConfiguration.pitch,
            volume: ttsConfiguration.volume,
            audioFormat: ttsConfiguration.audioFormat,
            sampleRate: ttsConfiguration.audioFormat == .pcm ? 16000 : 44100,
            useSSML: input.ssml != nil
        )

        // Track processing time
        let startTime = Date()

        // Perform synthesis with error telemetry
        let audioData: Data
        do {
            audioData = try await ttsService.synthesize(text: textToSynthesize, options: options)
        } catch {
            // Submit failure telemetry
            let processingTime = Date().timeIntervalSince(startTime)
            Task.detached(priority: .background) {
                let deviceInfo = TelemetryDeviceInfo.current
                let eventData = TTSSynthesisTelemetryData(
                    modelId: self.ttsConfiguration.voice,
                    modelName: self.ttsConfiguration.voice,
                    framework: "ONNX",
                    device: deviceInfo.device,
                    osVersion: deviceInfo.osVersion,
                    platform: deviceInfo.platform,
                    sdkVersion: SDKConstants.version,
                    processingTimeMs: processingTime * 1000,
                    success: false,
                    errorMessage: error.localizedDescription,
                    characterCount: textToSynthesize.count,
                    charactersPerSecond: nil,
                    audioSizeBytes: nil,
                    sampleRate: options.sampleRate,
                    voice: options.voice,
                    outputDurationMs: nil
                )
                let event = TTSEvent(type: .synthesisCompleted, eventData: eventData)
                await AnalyticsQueueManager.shared.enqueue(event)
                await AnalyticsQueueManager.shared.flush()
            }
            throw error
        }

        let processingTime = Date().timeIntervalSince(startTime)

        // Calculate audio duration
        let duration = estimateAudioDuration(dataSize: audioData.count, format: ttsConfiguration.audioFormat)

        let metadata = TTSSynthesisMetadata(
            voice: options.voice ?? ttsConfiguration.voice,
            language: options.language,
            processingTime: processingTime,
            characterCount: textToSynthesize.count
        )

        let output = TTSOutput(
            audioData: audioData,
            format: ttsConfiguration.audioFormat,
            duration: duration,
            phonemeTimestamps: nil,
            metadata: metadata
        )

        // Submit telemetry for TTS synthesis completion
        Task.detached(priority: .background) {
            let deviceInfo = TelemetryDeviceInfo.current
            let processingTimeMs = processingTime * 1000
            let charactersPerSecond = processingTime > 0 ? Double(textToSynthesize.count) / processingTime : 0

            let eventData = TTSSynthesisTelemetryData(
                modelId: self.ttsConfiguration.voice,
                modelName: self.ttsConfiguration.voice,
                framework: "ONNX",
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                platform: deviceInfo.platform,
                sdkVersion: SDKConstants.version,
                processingTimeMs: processingTimeMs,
                success: true,
                characterCount: textToSynthesize.count,
                charactersPerSecond: charactersPerSecond,
                audioSizeBytes: audioData.count,
                sampleRate: options.sampleRate,
                voice: options.voice,
                outputDurationMs: duration * 1000
            )
            let event = TTSEvent(type: .synthesisCompleted, eventData: eventData)
            await AnalyticsQueueManager.shared.enqueue(event)
            await AnalyticsQueueManager.shared.flush()
        }

        return output
    }

    /// Stream synthesis for long text
    public func streamSynthesize(
        _ text: String,
        voice: String? = nil,
        language: String? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try ensureReady()

                    guard let ttsService = service?.wrappedService else {
                        continuation.finish(throwing: TTSError.notInitialized)
                        return
                    }

                    let options = TTSOptions(
                        voice: voice ?? ttsConfiguration.voice,
                        language: language ?? ttsConfiguration.language,
                        rate: ttsConfiguration.speakingRate,
                        pitch: ttsConfiguration.pitch,
                        volume: ttsConfiguration.volume,
                        audioFormat: ttsConfiguration.audioFormat,
                        sampleRate: 16000,
                        useSSML: false
                    )

                    try await ttsService.synthesizeStream(
                        text: text,
                        options: options
                    ) { chunk in
                        continuation.yield(chunk)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get available voices
    public func getAvailableVoices() -> [String] {
        return service?.wrappedService?.availableVoices ?? []
    }

    /// Stop current synthesis
    public func stopSynthesis() {
        service?.wrappedService?.stop()
    }

    /// Check if currently synthesizing
    public var isSynthesizing: Bool {
        return service?.wrappedService?.isSynthesizing ?? false
    }

    /// Get service for compatibility
    public func getService() -> (any TTSService)? {
        return service?.wrappedService
    }

    // MARK: - Cleanup

    public override func performCleanup() async throws {
        service?.wrappedService?.stop()
        await service?.wrappedService?.cleanup()
    }

    // MARK: - Private Helpers

    private func estimateAudioDuration(dataSize: Int, format: AudioFormat) -> TimeInterval {
        // Rough estimation based on format and typical bitrates
        let bytesPerSecond: Int
        switch format {
        case .pcm, .wav:
            bytesPerSecond = 32000 // 16-bit PCM at 16kHz
        case .mp3:
            bytesPerSecond = 16000 // 128kbps MP3
        default:
            bytesPerSecond = 32000
        }

        return TimeInterval(dataSize) / TimeInterval(bytesPerSecond)
    }
}
