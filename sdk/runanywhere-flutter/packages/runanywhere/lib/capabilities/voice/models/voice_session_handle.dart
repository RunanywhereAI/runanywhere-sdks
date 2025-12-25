/// Voice Session Handle
///
/// Matches iOS VoiceSessionHandle from RunAnywhere+VoiceSession.swift
/// Provides a handle to control an active voice session
library voice_session_handle;

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/capabilities/voice/models/voice_session.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Handle to control an active voice session
/// Matches iOS VoiceSessionHandle from RunAnywhere+VoiceSession.swift
class VoiceSessionHandle {
  final SDKLogger _logger = SDKLogger(category: 'VoiceSessionHandle');
  final VoiceSessionConfig config;

  bool _isRunning = false;
  Uint8List _audioBuffer = Uint8List(0);
  DateTime? _lastSpeechTime;
  bool _isSpeechActive = false;

  final StreamController<VoiceSessionEvent> _eventController =
      StreamController<VoiceSessionEvent>.broadcast();

  // Callback for processing audio (injected from RunAnywhere)
  final Future<VoiceAgentProcessResult> Function(Uint8List audioData)?
      _processAudioCallback;

  // Callback for permission request
  final Future<bool> Function()? _requestPermissionCallback;

  // Callback for voice agent readiness check
  final Future<bool> Function()? _isVoiceAgentReadyCallback;

  // Callback for initializing voice agent with loaded models
  final Future<void> Function()? _initializeVoiceAgentCallback;

  VoiceSessionHandle({
    VoiceSessionConfig? config,
    Future<VoiceAgentProcessResult> Function(Uint8List audioData)?
        processAudioCallback,
    Future<bool> Function()? requestPermissionCallback,
    Future<bool> Function()? isVoiceAgentReadyCallback,
    Future<void> Function()? initializeVoiceAgentCallback,
  })  : config = config ?? VoiceSessionConfig.defaultConfig,
        _processAudioCallback = processAudioCallback,
        _requestPermissionCallback = requestPermissionCallback,
        _isVoiceAgentReadyCallback = isVoiceAgentReadyCallback,
        _initializeVoiceAgentCallback = initializeVoiceAgentCallback;

  /// Stream of session events
  /// Matches iOS VoiceSessionHandle.events
  Stream<VoiceSessionEvent> get events => _eventController.stream;

  /// Whether the session is currently running
  bool get isRunning => _isRunning;

  /// Start the voice session
  Future<void> start() async {
    if (_isRunning) return;

    // Verify voice agent is ready, or try to initialize
    final isReady = await _isVoiceAgentReadyCallback?.call() ?? false;
    if (!isReady) {
      try {
        await _initializeVoiceAgentCallback?.call();
      } catch (e) {
        _emit(VoiceSessionError(message: 'Voice agent not ready: $e'));
        rethrow;
      }
    }

    // Request mic permission
    final hasPermission = await _requestPermissionCallback?.call() ?? true;
    if (!hasPermission) {
      _emit(const VoiceSessionError(message: 'Microphone permission denied'));
      throw const VoiceSessionException(
        VoiceSessionErrorType.microphonePermissionDenied,
        'Microphone permission denied',
      );
    }

    _isRunning = true;
    _emit(const VoiceSessionStarted());

    _logger.info('Voice session started');
  }

  /// Stop the voice session
  /// Matches iOS VoiceSessionHandle.stop()
  void stop() {
    if (!_isRunning) return;

    _isRunning = false;
    _audioBuffer = Uint8List(0);
    _isSpeechActive = false;
    _lastSpeechTime = null;

    _emit(const VoiceSessionStopped());
    unawaited(_eventController.close());

    _logger.info('Voice session stopped');
  }

  /// Force process current audio (push-to-talk)
  /// Matches iOS VoiceSessionHandle.sendNow()
  Future<void> sendNow() async {
    if (!_isRunning) return;
    _isSpeechActive = false;
    await _processCurrentAudio();
  }

  /// Feed audio data to the session (called by audio capture)
  void feedAudio(Uint8List data, double audioLevel) {
    if (!_isRunning) return;

    // Append to buffer
    final newBuffer = Uint8List(_audioBuffer.length + data.length);
    newBuffer.setRange(0, _audioBuffer.length, _audioBuffer);
    newBuffer.setRange(_audioBuffer.length, newBuffer.length, data);
    _audioBuffer = newBuffer;

    // Check speech state
    _checkSpeechState(audioLevel);
  }

  void _emit(VoiceSessionEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _checkSpeechState(double level) {
    _emit(VoiceSessionListening(audioLevel: level));

    if (level > config.speechThreshold) {
      if (!_isSpeechActive) {
        _logger.debug('Speech started');
        _isSpeechActive = true;
        _emit(const VoiceSessionSpeechStarted());
      }
      _lastSpeechTime = DateTime.now();
    } else if (_isSpeechActive) {
      final lastTime = _lastSpeechTime;
      if (lastTime != null) {
        final silenceDuration = DateTime.now().difference(lastTime).inSeconds;
        if (silenceDuration >= config.silenceDuration) {
          _logger.debug('Speech ended');
          _isSpeechActive = false;

          // Only process if we have enough audio (~0.5s at 16kHz = 16000 samples)
          if (_audioBuffer.length > 16000) {
            unawaited(_processCurrentAudio());
          } else {
            _audioBuffer = Uint8List(0);
          }
        }
      }
    }
  }

  Future<void> _processCurrentAudio() async {
    final audio = _audioBuffer;
    _audioBuffer = Uint8List(0);

    if (audio.isEmpty || !_isRunning) return;

    _emit(const VoiceSessionProcessing());

    try {
      final result = await _processAudioCallback?.call(audio);
      if (result == null) {
        _logger.warning('No processing callback available');
        return;
      }

      if (!result.speechDetected) {
        _logger.info('No speech detected');
        if (config.continuousMode && _isRunning) {
          // Ready to listen again
        }
        return;
      }

      // Emit intermediate results
      if (result.transcription != null) {
        _emit(VoiceSessionTranscribed(text: result.transcription!));
      }

      if (result.response != null) {
        _emit(VoiceSessionResponded(text: result.response!));
      }

      // Mark speaking if TTS audio available
      if (config.autoPlayTTS &&
          result.synthesizedAudio != null &&
          result.synthesizedAudio!.isNotEmpty) {
        _emit(const VoiceSessionSpeaking());
        // TTS playback would be handled by audio player
      }

      // Emit complete result
      _emit(VoiceSessionTurnCompleted(
        transcript: result.transcription ?? '',
        response: result.response ?? '',
        audio: result.synthesizedAudio,
      ));
    } catch (e) {
      _logger.error('Processing failed: $e');
      _emit(VoiceSessionError(message: e.toString()));
    }
  }
}

/// Result from voice agent processing
class VoiceAgentProcessResult {
  final bool speechDetected;
  final String? transcription;
  final String? response;
  final Uint8List? synthesizedAudio;

  const VoiceAgentProcessResult({
    required this.speechDetected,
    this.transcription,
    this.response,
    this.synthesizedAudio,
  });
}
