/// Audio Pipeline State Management
///
/// Matches iOS AudioPipelineState.swift from Capabilities/Voice/
library audio_pipeline_state;

import 'dart:async';
import '../../foundation/logging/sdk_logger.dart';

/// Represents the current state of the audio pipeline to prevent feedback loops
/// Matches iOS AudioPipelineState enum from AudioPipelineState.swift
enum AudioPipelineState {
  /// System is idle, ready to start listening
  idle('idle'),

  /// Actively listening for speech via VAD
  listening('listening'),

  /// Processing detected speech with STT
  processingSpeech('processingSpeech'),

  /// Generating response with LLM
  generatingResponse('generatingResponse'),

  /// Playing TTS output
  playingTTS('playingTTS'),

  /// Cooldown period after TTS to prevent feedback
  cooldown('cooldown'),

  /// Error state requiring reset
  error('error');

  final String value;
  const AudioPipelineState(this.value);

  static AudioPipelineState fromString(String value) {
    return AudioPipelineState.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AudioPipelineState.idle,
    );
  }
}

/// Configuration for feedback prevention
/// Matches iOS AudioPipelineStateManager.Configuration from AudioPipelineState.swift
class AudioPipelineConfiguration {
  /// Duration to wait after TTS before allowing microphone (seconds)
  final Duration cooldownDuration;

  /// Whether to enforce strict state transitions
  final bool strictTransitions;

  /// Maximum TTS duration before forced timeout (seconds)
  final Duration maxTTSDuration;

  const AudioPipelineConfiguration({
    this.cooldownDuration = const Duration(milliseconds: 800),
    this.strictTransitions = true,
    this.maxTTSDuration = const Duration(seconds: 30),
  });
}

/// Callback for state changes
typedef StateChangeHandler = void Function(
  AudioPipelineState oldState,
  AudioPipelineState newState,
);

/// Manages audio pipeline state transitions and feedback prevention
/// Matches iOS AudioPipelineStateManager actor from AudioPipelineState.swift
///
/// Note: Dart is single-threaded, so we don't need actor isolation.
/// Using a simple class with proper state management.
class AudioPipelineStateManager {
  final SDKLogger _logger = SDKLogger(category: 'AudioPipelineState');

  AudioPipelineState _currentState = AudioPipelineState.idle;
  DateTime? _lastTTSEndTime;
  final AudioPipelineConfiguration configuration;
  StateChangeHandler? _stateChangeHandler;
  Timer? _cooldownTimer;

  AudioPipelineStateManager({
    this.configuration = const AudioPipelineConfiguration(),
  });

  /// Get the current state
  AudioPipelineState get state => _currentState;

  /// Set a handler for state changes
  void setStateChangeHandler(StateChangeHandler handler) {
    _stateChangeHandler = handler;
  }

  /// Check if microphone can be activated
  bool canActivateMicrophone() {
    switch (_currentState) {
      case AudioPipelineState.idle:
      case AudioPipelineState.listening:
        // Check cooldown if we recently finished TTS
        if (_lastTTSEndTime != null) {
          final timeSinceTTS = DateTime.now().difference(_lastTTSEndTime!);
          return timeSinceTTS >= configuration.cooldownDuration;
        }
        return true;
      case AudioPipelineState.processingSpeech:
      case AudioPipelineState.generatingResponse:
      case AudioPipelineState.playingTTS:
      case AudioPipelineState.cooldown:
      case AudioPipelineState.error:
        return false;
    }
  }

  /// Check if TTS can be played
  bool canPlayTTS() {
    switch (_currentState) {
      case AudioPipelineState.generatingResponse:
        return true;
      default:
        return false;
    }
  }

  /// Transition to a new state with validation
  bool transition(AudioPipelineState newState) {
    final oldState = _currentState;

    // Validate transition
    if (!_isValidTransition(from: oldState, to: newState)) {
      if (configuration.strictTransitions) {
        _logger.warning(
          'Invalid state transition from ${oldState.value} to ${newState.value}',
        );
        return false;
      }
    }

    // Update state
    _currentState = newState;
    _logger.debug('State transition: ${oldState.value} -> ${newState.value}');

    // Handle special state actions
    switch (newState) {
      case AudioPipelineState.playingTTS:
        // Don't use timeout for System TTS as it manages its own completion
        break;

      case AudioPipelineState.cooldown:
        _lastTTSEndTime = DateTime.now();
        // Automatically transition to idle after cooldown
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer(configuration.cooldownDuration, () {
          if (_currentState == AudioPipelineState.cooldown) {
            transition(AudioPipelineState.idle);
          }
        });
        break;

      default:
        break;
    }

    // Notify handler
    _stateChangeHandler?.call(oldState, newState);

    return true;
  }

  /// Force reset to idle state (use in error recovery)
  void reset() {
    _logger.info('Force resetting audio pipeline state to idle');
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _currentState = AudioPipelineState.idle;
    _lastTTSEndTime = null;
  }

  /// Dispose resources
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }

  /// Check if a state transition is valid
  bool _isValidTransition({
    required AudioPipelineState from,
    required AudioPipelineState to,
  }) {
    switch ((from, to)) {
      // From idle
      case (AudioPipelineState.idle, AudioPipelineState.listening):
      case (AudioPipelineState.idle, AudioPipelineState.cooldown):
        return true;

      // From listening
      case (AudioPipelineState.listening, AudioPipelineState.idle):
      case (AudioPipelineState.listening, AudioPipelineState.processingSpeech):
        return true;

      // From processing speech
      case (AudioPipelineState.processingSpeech, AudioPipelineState.idle):
      case (
          AudioPipelineState.processingSpeech,
          AudioPipelineState.generatingResponse
        ):
      case (AudioPipelineState.processingSpeech, AudioPipelineState.listening):
        return true;

      // From generating response
      case (AudioPipelineState.generatingResponse, AudioPipelineState.playingTTS):
      case (AudioPipelineState.generatingResponse, AudioPipelineState.idle):
      case (AudioPipelineState.generatingResponse, AudioPipelineState.cooldown):
        return true;

      // From playing TTS
      case (AudioPipelineState.playingTTS, AudioPipelineState.cooldown):
      case (AudioPipelineState.playingTTS, AudioPipelineState.idle):
        return true;

      // From cooldown
      case (AudioPipelineState.cooldown, AudioPipelineState.idle):
        return true;

      // Error state can transition to idle
      case (AudioPipelineState.error, AudioPipelineState.idle):
        return true;

      // Any state can transition to error
      case (_, AudioPipelineState.error):
        return true;

      default:
        return false;
    }
  }
}

/// Protocol for components that need to respond to pipeline state changes
/// Matches iOS AudioPipelineStateObserver protocol from AudioPipelineState.swift
abstract class AudioPipelineStateObserver {
  void audioStateDidChange({
    required AudioPipelineState oldState,
    required AudioPipelineState newState,
  });
}
