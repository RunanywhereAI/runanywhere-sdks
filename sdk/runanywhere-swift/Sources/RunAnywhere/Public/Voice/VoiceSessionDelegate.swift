import Foundation

/// Delegate protocol for VoiceSessionManager events (LiveKit-style)
public protocol VoiceSessionDelegate: AnyObject {
    /// Called when session state changes
    func voiceSession(_ session: VoiceSessionManager, didChangeState state: VoiceSessionManager.SessionState)

    /// Called when transcription is received (partial or final)
    func voiceSession(_ session: VoiceSessionManager, didReceiveTranscript text: String, isFinal: Bool)

    /// Called when AI response is received
    func voiceSession(_ session: VoiceSessionManager, didReceiveResponse text: String)

    /// Called when audio data is available (for TTS playback)
    func voiceSession(_ session: VoiceSessionManager, didReceiveAudio data: Data)

    /// Called when an error occurs
    func voiceSession(_ session: VoiceSessionManager, didEncounterError error: Error)
}

// Optional methods with default implementation
public extension VoiceSessionDelegate {
    func voiceSession(_ session: VoiceSessionManager, didReceiveAudio data: Data) {
        // Default: no-op
    }
}
