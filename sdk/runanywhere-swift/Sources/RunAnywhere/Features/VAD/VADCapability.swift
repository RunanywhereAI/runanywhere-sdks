//
//  VADCapability.swift
//  RunAnywhere SDK
//
//  Thin Swift wrapper over rac_vad_component_* C API.
//  All business logic is in the C++ layer; this is just a Swift interface.
//
//  ⚠️ WARNING: This is a direct wrapper. Do NOT add custom logic here.
//  The C++ layer (runanywhere-commons) is the source of truth.
//

import CRACommons
import Foundation

/// Actor-based VAD capability that provides voice activity detection.
/// This is a thin wrapper over the C++ rac_vad_component API.
public actor VADCapability: Capability {
    public typealias Configuration = VADConfiguration

    // MARK: - State

    /// Handle to the C++ VAD component
    private var handle: rac_handle_t?

    /// Current configuration
    private var config: VADConfiguration?

    /// Whether VAD is currently active
    private var isActive = false

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "VADCapability")
    private let analyticsService: VADAnalyticsService

    // MARK: - Callbacks

    private var onSpeechActivity: ((SpeechActivityEvent) -> Void)?
    private var onAudioBuffer: (([Float]) -> Void)?

    // MARK: - Initialization

    public init(analyticsService: VADAnalyticsService = VADAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    deinit {
        if let handle = handle {
            rac_vad_component_destroy(handle)
        }
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: VADConfiguration) {
        self.config = config
    }

    // MARK: - Handle Access (for VoiceAgent)

    /// Get or create the internal handle (for voice agent to share)
    internal func getOrCreateHandle() throws -> rac_handle_t {
        if let handle = handle {
            return handle
        }

        var newHandle: rac_handle_t?
        let createResult = rac_vad_component_create(&newHandle)
        guard createResult == RAC_SUCCESS, let createdHandle = newHandle else {
            throw SDKError.vad(.initializationFailed, "Failed to create VAD component: \(createResult)")
        }
        handle = createdHandle
        return createdHandle
    }

    // MARK: - Lifecycle

    public var isReady: Bool {
        get async {
            guard let handle = handle else { return false }
            return rac_vad_component_is_initialized(handle) == RAC_TRUE
        }
    }

    /// Initialize the VAD
    public func initialize() async throws {
        // Create component if needed
        if handle == nil {
            var newHandle: rac_handle_t?
            let createResult = rac_vad_component_create(&newHandle)
            guard createResult == RAC_SUCCESS, let newVADHandle = newHandle else {
                throw SDKError.vad(.initializationFailed, "Failed to create VAD component: \(createResult)")
            }
            handle = newVADHandle
        }

        guard let handle = handle else {
            throw SDKError.vad(.initializationFailed, "No VAD component handle")
        }

        // Configure if we have config
        if let config = config {
            var cConfig = rac_vad_config_t()
            cConfig.sample_rate = Int32(config.sampleRate)
            cConfig.frame_length = Float(config.frameLength)
            cConfig.energy_threshold = Float(config.energyThreshold)

            let configResult = rac_vad_component_configure(handle, &cConfig)
            if configResult != RAC_SUCCESS {
                logger.warning("VAD configure returned: \(configResult)")
            }
        }

        // Initialize
        let result = rac_vad_component_initialize(handle)
        guard result == RAC_SUCCESS else {
            throw SDKError.vad(.initializationFailed, "VAD initialization failed: \(result)")
        }

        logger.info("VAD initialized")
    }

    public func cleanup() async {
        if let handle = handle {
            rac_vad_component_cleanup(handle)
            rac_vad_component_destroy(handle)
        }
        handle = nil
        isActive = false
        onSpeechActivity = nil
        onAudioBuffer = nil
    }

    // MARK: - VAD Operations

    /// Start voice activity detection
    public func start() async throws {
        guard let handle = handle else {
            throw SDKError.vad(.notInitialized, "VAD not initialized")
        }

        let result = rac_vad_component_start(handle)
        guard result == RAC_SUCCESS else {
            throw SDKError.vad(.startFailed, "Failed to start VAD: \(result)")
        }

        isActive = true
        logger.info("VAD started")
        await analyticsService.trackStarted()
    }

    /// Stop voice activity detection
    public func stop() async throws {
        guard let handle = handle else { return }

        let result = rac_vad_component_stop(handle)
        if result != RAC_SUCCESS {
            logger.warning("VAD stop returned: \(result)")
        }

        isActive = false
        logger.info("VAD stopped")
        await analyticsService.trackStopped()
    }

    /// Pause VAD processing (not implemented in C API, no-op)
    public func pause() async {
        logger.debug("VAD pause requested (no-op)")
    }

    /// Resume VAD processing (not implemented in C API, no-op)
    public func resume() async {
        logger.debug("VAD resume requested (no-op)")
    }

    /// Process audio samples
    public func processSamples(_ samples: [Float]) async throws -> Bool {
        guard let handle = handle else {
            throw SDKError.vad(.notInitialized, "VAD not initialized")
        }

        var hasVoice: rac_bool_t = RAC_FALSE
        let result = samples.withUnsafeBufferPointer { buffer in
            rac_vad_component_process(
                handle,
                buffer.baseAddress,
                buffer.count,
                &hasVoice
            )
        }

        guard result == RAC_SUCCESS else {
            throw SDKError.vad(.processingFailed, "Failed to process samples: \(result)")
        }

        let detected = hasVoice == RAC_TRUE

        // Forward to audio buffer callback if set
        if let onAudioBuffer = onAudioBuffer {
            onAudioBuffer(samples)
        }

        return detected
    }

    // MARK: - Callbacks

    /// Set speech activity callback
    public func setOnSpeechActivity(_ callback: @escaping (SpeechActivityEvent) -> Void) {
        self.onSpeechActivity = callback

        guard let handle = handle else { return }

        // Create callback context
        let context = VADCallbackContext(onActivity: callback, analyticsService: analyticsService)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        rac_vad_component_set_activity_callback(
            handle,
            { activity, userData in
                guard let userData = userData else { return }
                let ctx = Unmanaged<VADCallbackContext>.fromOpaque(userData).takeUnretainedValue()
                let event: SpeechActivityEvent = activity == RAC_SPEECH_STARTED ? .started : .ended
                ctx.onActivity(event)
                Task {
                    if event == .started {
                        await ctx.analyticsService.trackSpeechStart()
                    } else {
                        await ctx.analyticsService.trackSpeechEnd()
                    }
                }
            },
            contextPtr
        )
    }

    /// Set audio buffer callback
    public func setOnAudioBuffer(_ callback: @escaping ([Float]) -> Void) {
        self.onAudioBuffer = callback
    }

    // MARK: - State Query

    /// Check if speech is currently active
    public var isSpeechActive: Bool {
        get async {
            guard let handle = handle else { return false }
            var active: rac_bool_t = RAC_FALSE
            // Use process samples with empty array to check state
            // Or implement a dedicated query in C++
            return active == RAC_TRUE
        }
    }

    /// Get VAD statistics
    public func getStatistics() async -> VADStatistics {
        guard let handle = handle else {
            return VADStatistics(current: 0, threshold: 0, ambient: 0, recentAvg: 0, recentMax: 0)
        }

        // Would need to add a C API for getting statistics
        return VADStatistics(current: 0, threshold: 0, ambient: 0, recentAvg: 0, recentMax: 0)
    }

    // MARK: - Analytics

    public func getAnalyticsMetrics() async -> VADMetrics {
        await analyticsService.getMetrics()
    }
}

// MARK: - Callback Context

private final class VADCallbackContext: @unchecked Sendable {
    let onActivity: (SpeechActivityEvent) -> Void
    let analyticsService: VADAnalyticsService

    init(onActivity: @escaping (SpeechActivityEvent) -> Void, analyticsService: VADAnalyticsService) {
        self.onActivity = onActivity
        self.analyticsService = analyticsService
    }
}
