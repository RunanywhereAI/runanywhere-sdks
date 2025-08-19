import Foundation

/// Configuration for Text-to-Speech processing
public struct VoiceTTSConfig {
    /// Voice identifier for synthesis
    public let voice: String

    /// Speech rate (0.5 to 2.0, 1.0 is normal)
    public let rate: Float

    /// Voice pitch (0.5 to 2.0, 1.0 is normal)
    public let pitch: Float

    /// Volume (0.0 to 1.0)
    public let volume: Float

    public init(
        voice: String = "system",
        rate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0
    ) {
        self.voice = voice
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
    }
}
