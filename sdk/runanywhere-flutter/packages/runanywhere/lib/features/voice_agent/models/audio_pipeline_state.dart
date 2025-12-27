import 'dart:async';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Represents the current state of the audio pipeline to prevent feedback loops
/// Matches iOS AudioPipelineState from Features/VoiceAgent/Models/AudioPipelineState.swift
enum AudioPipelineState {
  /// System is idle, ready to start listening
  idle,

  /// Actively listening for speech via VAD
  listening,

  /// Processing detected speech with STT
  processingSpeech,

  /// Generating response with LLM
  generatingResponse,

  /// Playing TTS output
  playingTTS,

  /// Cooldown period after TTS to prevent feedback
  cooldown,

  /// Error state requiring reset
  error;

  String get value => name;
}

/// Configuration for audio pipeline state manager
class AudioPipelineStateConfiguration {
  /// Duration to wait after TTS before allowing microphone (seconds)
  final double cooldownDuration;

  /// Whether to enforce strict state transitions
  final bool strictTransitions;

  /// Maximum TTS duration before forced timeout (seconds)
  final double maxTTSDuration;

  const AudioPipelineStateConfiguration({
    this.cooldownDuration = 0.8,
    this.strictTransitions = true,
    this.maxTTSDuration = 30.0,
  });
}

/// Manages audio pipeline state transitions and feedback prevention
/// Matches iOS AudioPipelineStateManager from Features/VoiceAgent/Models/AudioPipelineState.swift
class AudioPipelineStateManager {
  final SDKLogger _logger = SDKLogger(category: 'AudioPipelineState');

  AudioPipelineState _currentState = AudioPipelineState.idle;
  DateTime? _lastTTSEndTime;
  final AudioPipelineStateConfiguration configuration;

  /// State change callback
  void Function(AudioPipelineState oldState, AudioPipelineState newState)?
      _stateChangeHandler;

  /// Timer for cooldown
  Timer? _cooldownTimer;

  AudioPipelineStateManager({
    this.configuration = const AudioPipelineStateConfiguration(),
  });

  /// Get the current state
  AudioPipelineState get state => _currentState;

  /// Set a handler for state changes
  void setStateChangeHandler(
      void Function(AudioPipelineState, AudioPipelineState) handler) {
    _stateChangeHandler = handler;
  }

  /// Check if microphone can be activated
  bool canActivateMicrophone() {
    switch (_currentState) {
      case AudioPipelineState.idle:
      case AudioPipelineState.listening:
        // Check cooldown if we recently finished TTS
        if (_lastTTSEndTime != null) {
          final timeSinceTTS =
              DateTime.now().difference(_lastTTSEndTime!).inMilliseconds / 1000;
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
    return _currentState == AudioPipelineState.generatingResponse;
  }

  /// Transition to a new state with validation
  bool transition(AudioPipelineState newState) {
    final oldState = _currentState;

    // Validate transition
    if (!_isValidTransition(oldState, newState)) {
      if (configuration.strictTransitions) {
        _logger.warning(
            'Invalid state transition from ${oldState.value} to ${newState.value}');
        return false;
      }
    }

    // Update state
    _currentState = newState;
    _logger.debug('State transition: ${oldState.value} → ${newState.value}');

    // Handle special state actions
    switch (newState) {
      case AudioPipelineState.playingTTS:
        // TTS manages its own completion
        break;

      case AudioPipelineState.cooldown:
        _lastTTSEndTime = DateTime.now();
        // Automatically transition to idle after cooldown
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer(
          Duration(
              milliseconds: (configuration.cooldownDuration * 1000).toInt()),
          () {
            if (_currentState == AudioPipelineState.cooldown) {
              transition(AudioPipelineState.idle);
            }
          },
        );
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
    _currentState = AudioPipelineState.idle;
    _lastTTSEndTime = null;
  }

  /// Check if a state transition is valid
  bool _isValidTransition(AudioPipelineState from, AudioPipelineState to) {
    switch (from) {
      case AudioPipelineState.idle:
        return to == AudioPipelineState.listening ||
            to == AudioPipelineState.cooldown;

      case AudioPipelineState.listening:
        return to == AudioPipelineState.idle ||
            to == AudioPipelineState.processingSpeech;

      case AudioPipelineState.processingSpeech:
        return to == AudioPipelineState.idle ||
            to == AudioPipelineState.generatingResponse ||
            to == AudioPipelineState.listening;

      case AudioPipelineState.generatingResponse:
        return to == AudioPipelineState.playingTTS ||
            to == AudioPipelineState.idle ||
            to == AudioPipelineState.cooldown;

      case AudioPipelineState.playingTTS:
        return to == AudioPipelineState.cooldown ||
            to == AudioPipelineState.idle;

      case AudioPipelineState.cooldown:
        return to == AudioPipelineState.idle;

      case AudioPipelineState.error:
        return to == AudioPipelineState.idle;
    }
  }

  /// Dispose resources
  void dispose() {
    _cooldownTimer?.cancel();
  }
}
