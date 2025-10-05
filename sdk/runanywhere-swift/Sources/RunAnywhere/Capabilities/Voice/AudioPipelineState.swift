import Foundation
import os

/// Represents the current state of the audio pipeline to prevent feedback loops
public enum AudioPipelineState: String, CaseIterable {
    /// System is idle, ready to start listening
    case idle

    /// Actively listening for speech via VAD
    case listening

    /// Processing detected speech with STT
    case processingSpeech

    /// Generating response with LLM
    case generatingResponse

    /// Playing TTS output
    case playingTTS

    /// Cooldown period after TTS to prevent feedback
    case cooldown

    /// Error state requiring reset
    case error
}

/// Manages audio pipeline state transitions and feedback prevention
public actor AudioPipelineStateManager {
    private var currentState: AudioPipelineState = .idle
    private var lastTTSEndTime: Date?
    private let cooldownDuration: TimeInterval
    private var stateChangeHandler: ((AudioPipelineState, AudioPipelineState) -> Void)?

    /// Configuration for feedback prevention
    public struct Configuration {
        /// Duration to wait after TTS before allowing microphone (seconds)
        public let cooldownDuration: TimeInterval

        /// Whether to enforce strict state transitions
        public let strictTransitions: Bool

        /// Maximum TTS duration before forced timeout (seconds)
        public let maxTTSDuration: TimeInterval

        public init(
            cooldownDuration: TimeInterval = 0.8,  // 800ms - better feedback prevention while maintaining responsiveness
            strictTransitions: Bool = true,
            maxTTSDuration: TimeInterval = 30.0
        ) {
            self.cooldownDuration = cooldownDuration
            self.strictTransitions = strictTransitions
            self.maxTTSDuration = maxTTSDuration
        }
    }

    private let configuration: Configuration
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "AudioPipelineState")

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.cooldownDuration = configuration.cooldownDuration
    }

    /// Get the current state
    public var state: AudioPipelineState {
        currentState
    }

    /// Set a handler for state changes
    public func setStateChangeHandler(_ handler: @escaping (AudioPipelineState, AudioPipelineState) -> Void) {
        self.stateChangeHandler = handler
    }

    /// Check if microphone can be activated
    public func canActivateMicrophone() -> Bool {
        switch currentState {
        case .idle, .listening:
            // Check cooldown if we recently finished TTS
            if let lastTTSEnd = lastTTSEndTime {
                let timeSinceTTS = Date().timeIntervalSince(lastTTSEnd)
                return timeSinceTTS >= cooldownDuration
            }
            return true
        case .processingSpeech, .generatingResponse, .playingTTS, .cooldown:
            return false
        case .error:
            return false
        }
    }

    /// Check if TTS can be played
    public func canPlayTTS() -> Bool {
        switch currentState {
        case .generatingResponse:
            return true
        default:
            return false
        }
    }

    /// Transition to a new state with validation
    @discardableResult
    public func transition(to newState: AudioPipelineState) -> Bool {
        let oldState = currentState

        // Validate transition
        if !isValidTransition(from: oldState, to: newState) {
            if configuration.strictTransitions {
                logger.warning("Invalid state transition from \(oldState.rawValue) to \(newState.rawValue)")
                return false
            }
        }

        // Update state
        currentState = newState
        logger.debug("State transition: \(oldState.rawValue) → \(newState.rawValue)")

        // Handle special state actions
        switch newState {
        case .playingTTS:
            // Don't use timeout for System TTS as it manages its own completion
            break

        case .cooldown:
            lastTTSEndTime = Date()
            // Automatically transition to idle after cooldown
            Task {
                try? await Task.sleep(nanoseconds: UInt64(cooldownDuration * 1_000_000_000))
                if self.currentState == .cooldown {
                    _ = self.transition(to: .idle)
                }
            }

        default:
            break
        }

        // Notify handler
        stateChangeHandler?(oldState, newState)

        return true
    }

    /// Force reset to idle state (use in error recovery)
    public func reset() {
        logger.info("Force resetting audio pipeline state to idle")
        currentState = .idle
        lastTTSEndTime = nil
    }

    /// Check if a state transition is valid
    private func isValidTransition(from: AudioPipelineState, to: AudioPipelineState) -> Bool {
        switch (from, to) {
        // From idle
        case (.idle, .listening):
            return true
        case (.idle, .cooldown):
            // Allow idle to cooldown for cases where TTS completes quickly
            // or when we need to enforce cooldown after other operations
            return true

        // From listening
        case (.listening, .idle),
             (.listening, .processingSpeech):
            return true

        // From processing speech
        case (.processingSpeech, .idle),
             (.processingSpeech, .generatingResponse),
             (.processingSpeech, .listening):
            return true

        // From generating response
        case (.generatingResponse, .playingTTS),
             (.generatingResponse, .idle),
             (.generatingResponse, .cooldown):
            // Allow direct transition to cooldown if TTS is skipped
            return true

        // From playing TTS
        case (.playingTTS, .cooldown),
             (.playingTTS, .idle):
            // Allow transition to idle if cooldown is not needed
            return true

        // From cooldown
        case (.cooldown, .idle):
            return true

        // Error state can transition to idle
        case (.error, .idle):
            return true

        // Any state can transition to error
        case (_, .error):
            return true

        default:
            return false
        }
    }
}

/// Protocol for components that need to respond to pipeline state changes
public protocol AudioPipelineStateObserver: AnyObject {
    func audioStateDidChange(from oldState: AudioPipelineState, to newState: AudioPipelineState)
}
