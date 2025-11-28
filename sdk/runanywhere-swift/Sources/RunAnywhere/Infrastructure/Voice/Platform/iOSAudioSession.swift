import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import AVFoundation

/// iOS-specific audio session management for voice processing
public class IOSAudioSession {
    private let logger = SDKLogger(category: "IOSAudioSession")
    private let audioSession = AVAudioSession.sharedInstance()

    // Audio session state
    private var isConfigured = false
    private var isActive = false

    public init() {}

    /// Configure audio session for voice processing
    /// - Parameter mode: Voice processing mode (recording, playback, both)
    public func configure(for mode: VoiceProcessingMode) throws {
        logger.debug("Configuring audio session for mode: \(mode)")

        // Set category based on mode
        let category: AVAudioSession.Category
        let options: AVAudioSession.CategoryOptions

        switch mode {
        case .recording:
            category = .record
            options = [.allowBluetooth]

        case .playback:
            category = .playback
            options = [.allowBluetooth, .allowAirPlay]

        case .conversation:
            category = .playAndRecord
            // Use .duckOthers for echo cancellation to prevent mic from capturing TTS output
            options = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .duckOthers]
        }

        // Configure audio session
        try audioSession.setCategory(category, mode: .voiceChat, options: options)

        // Set preferred sample rate for voice
        try audioSession.setPreferredSampleRate(16000)

        // Set buffer duration for low latency
        try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer

        isConfigured = true
        logger.info("Audio session configured for \(mode)")
    }

    /// Activate the audio session
    public func activate() throws {
        guard isConfigured else {
            throw STTError.audioSessionNotConfigured
        }

        try audioSession.setActive(true)
        isActive = true
        logger.debug("Audio session activated")
    }

    /// Deactivate the audio session
    public func deactivate() throws {
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
        logger.debug("Audio session deactivated")
    }

    /// Request microphone permission
    public func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            #if os(iOS)
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                self.logger.info("Microphone permission \(granted ? "granted" : "denied")")
                continuation.resume(returning: granted)
            }
            #else
            // tvOS and watchOS handle permissions differently
            continuation.resume(returning: true)
            #endif
        }
    }

    /// Check if microphone permission is granted
    public var hasMicrophonePermission: Bool {
        #if os(iOS)
        return AVAudioSession.sharedInstance().recordPermission == .granted
        #else
        return true // tvOS and watchOS handle differently
        #endif
    }

    /// Handle audio route changes
    public func setupRouteChangeNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .newDeviceAvailable:
            logger.info("New audio device available")
        case .oldDeviceUnavailable:
            logger.info("Audio device became unavailable")
        case .categoryChange:
            logger.info("Audio category changed")
        default:
            break
        }
    }

    /// Handle audio interruptions
    public func setupInterruptionNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            logger.info("Audio session interrupted")
            // Handle interruption began
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    logger.info("Audio session interruption ended, should resume")
                    // Resume audio processing
                }
            }
        @unknown default:
            break
        }
    }

    /// Get current audio route
    public var currentRoute: String {
        let outputs = audioSession.currentRoute.outputs
        return outputs.map { $0.portName }.joined(separator: ", ")
    }

    /// Check if headphones are connected
    public var hasHeadphones: Bool {
        audioSession.currentRoute.outputs.contains { output in
            output.portType == .headphones || output.portType == .bluetoothA2DP
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}


#endif
