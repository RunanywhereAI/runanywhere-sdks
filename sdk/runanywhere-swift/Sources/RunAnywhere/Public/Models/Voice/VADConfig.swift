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
        energyThreshold: Float = 0.01,  // Lower threshold for better sensitivity
        silenceTimeout: TimeInterval = 1.0,  // Shorter timeout for quicker response
        voiceHysteresis: Int = 2  // Reduced hysteresis for faster detection
    ) {
        self.energyThreshold = energyThreshold
        self.silenceTimeout = silenceTimeout
        self.voiceHysteresis = voiceHysteresis
    }
}
