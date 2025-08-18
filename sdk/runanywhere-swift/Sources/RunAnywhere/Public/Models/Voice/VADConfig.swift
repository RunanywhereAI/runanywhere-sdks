import Foundation

/// Configuration for Voice Activity Detection
public struct VADConfig {
    /// Energy threshold for voice detection
    public let energyThreshold: Float

    /// Timeout before considering speech ended
    public let silenceTimeout: TimeInterval

    /// Number of frames for hysteresis
    public let voiceHysteresis: Int

    public init(
        energyThreshold: Float = 0.02,
        silenceTimeout: TimeInterval = 2.0,
        voiceHysteresis: Int = 3
    ) {
        self.energyThreshold = energyThreshold
        self.silenceTimeout = silenceTimeout
        self.voiceHysteresis = voiceHysteresis
    }
}
