import Foundation
#if os(macOS)
import AVFoundation

/// macOS-specific audio session management for voice processing
public class MacOSAudioSession {
    private let logger = SDKLogger(category: "MacOSAudioSession")

    // Audio engine for macOS
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var outputNode: AVAudioOutputNode?

    // Audio state
    private var isConfigured = false
    private var isRunning = false

    public init() {
        self.inputNode = audioEngine.inputNode
        self.outputNode = audioEngine.outputNode
    }

    /// Configure audio session for voice processing
    /// - Parameter mode: Voice processing mode (recording, playback, both)
    public func configure(for mode: VoiceProcessingMode) throws {
        logger.debug("Configuring audio engine for mode: \(mode)")

        // Configure audio format
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )

        guard let audioFormat = format else {
            throw STTError.audioSessionActivationFailed
        }

        // Configure based on mode
        switch mode {
        case .recording:
            configureForRecording(format: audioFormat)

        case .playback:
            configureForPlayback(format: audioFormat)

        case .conversation:
            configureForConversation(format: audioFormat)
        }

        isConfigured = true
        logger.info("Audio engine configured for \(mode)")
    }

    /// Start the audio engine
    public func start() throws {
        guard isConfigured else {
            throw STTError.audioSessionNotConfigured
        }

        // Prepare the engine
        audioEngine.prepare()

        // Start the engine
        try audioEngine.start()
        isRunning = true
        logger.debug("Audio engine started")
    }

    /// Stop the audio engine
    public func stop() {
        audioEngine.stop()
        isRunning = false
        logger.debug("Audio engine stopped")
    }

    /// Request microphone permission
    public func requestMicrophonePermission() async -> Bool {
        // macOS 10.14+ requires microphone permission
        if #available(macOS 10.14, *) {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    self.logger.info("Microphone permission \(granted ? "granted" : "denied")")
                    continuation.resume(returning: granted)
                }
            }
        } else {
            // Earlier versions don't require permission
            return true
        }
    }

    /// Check if microphone permission is granted
    public var hasMicrophonePermission: Bool {
        if #available(macOS 10.14, *) {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        } else {
            return true
        }
    }

    /// Get available audio input devices
    public var availableInputDevices: [AudioDevice] {
        if #available(macOS 14.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .builtInMicrophone],
                mediaType: .audio,
                position: .unspecified
            )
            return discoverySession.devices.map { device in
                AudioDevice(
                    id: device.uniqueID,
                    name: device.localizedName,
                    isDefault: device == AVCaptureDevice.default(for: .audio)
                )
            }
        } else {
            // Fallback for older macOS versions
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInMicrophone],
                mediaType: .audio,
                position: .unspecified
            )
            return discoverySession.devices.map { device in
                AudioDevice(
                    id: device.uniqueID,
                    name: device.localizedName,
                    isDefault: device == AVCaptureDevice.default(for: .audio)
                )
            }
        }
    }

    /// Get available audio output devices
    public var availableOutputDevices: [AudioDevice] {
        // For output devices, we'd need to use Core Audio APIs
        // Simplified implementation for now
        return [
            AudioDevice(
                id: "default",
                name: "Default Output",
                isDefault: true
            )
        ]
    }

    /// Set the audio input device
    public func setInputDevice(_ deviceID: String) throws {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw STTError.audioSessionActivationFailed
        }

        // In a real implementation, we'd configure the audio engine's input
        // to use the specified device
        logger.info("Set input device to: \(device.localizedName)")
    }

    /// Get current input level (0.0 to 1.0)
    public var inputLevel: Float {
        guard isRunning, inputNode != nil else { return 0 }

        // Install tap to measure level if needed
        // This is a simplified implementation
        return 0.5 // Placeholder
    }

    // MARK: - Private Methods

    private func configureForRecording(format: AVAudioFormat) {
        // Configure input node for recording
        guard let input = inputNode else { return }

        // Remove any existing taps
        input.removeTap(onBus: 0)

        logger.debug("Configured audio engine for recording")
    }

    private func configureForPlayback(format: AVAudioFormat) {
        // Configure output node for playback
        guard outputNode != nil else { return }

        logger.debug("Configured audio engine for playback")
    }

    private func configureForConversation(format: AVAudioFormat) {
        // Configure both input and output for conversation
        configureForRecording(format: format)
        configureForPlayback(format: format)

        logger.debug("Configured audio engine for conversation")
    }

    /// Install audio tap for processing
    public func installTap(
        bufferSize: AVAudioFrameCount = 1024,
        format: AVAudioFormat? = nil,
        block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        guard let input = inputNode else { return }

        let recordingFormat = format ?? input.outputFormat(forBus: 0)

        input.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: recordingFormat,
            block: block
        )

        logger.debug("Installed audio tap with buffer size: \(bufferSize)")
    }

    /// Remove audio tap
    public func removeTap() {
        inputNode?.removeTap(onBus: 0)
        logger.debug("Removed audio tap")
    }
}

/// Audio device information
public struct AudioDevice {
    public let id: String
    public let name: String
    public let isDefault: Bool
}
#endif
