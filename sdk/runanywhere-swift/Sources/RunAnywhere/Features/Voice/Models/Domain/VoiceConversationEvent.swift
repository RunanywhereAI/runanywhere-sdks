import Foundation

// MARK: - Voice Conversation Events

/// Events emitted during a voice conversation
public enum VoiceConversationEvent {
    case initialized
    case transcribing
    case transcribed(String)
    case generating
    case generated(String)
    case synthesizing
    case synthesized(Data)
    case error(Error)
}
