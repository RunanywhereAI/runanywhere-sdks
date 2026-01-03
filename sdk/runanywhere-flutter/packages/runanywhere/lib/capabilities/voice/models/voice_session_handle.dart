/// Voice Session Handle
///
/// Matches iOS VoiceSessionHandle from RunAnywhere+VoiceSession.swift
/// Provides a handle to control an active voice session with built-in audio capture
library voice_session_handle;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:runanywhere/capabilities/voice/models/voice_session.dart';
import 'package:runanywhere/features/stt/services/audio_capture_manager.dart';
import 'package:runanywhere/features/tts/services/audio_playback_manager.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Handle to control an active voice session
/// Matches iOS VoiceSessionHandle from RunAnywhere+VoiceSession.swift
class VoiceSessionHandle {
  final SDKLogger _logger = SDKLogger('VoiceSessionHandle');
  final VoiceSessionConfig config;

  bool _isRunning = false;
  bool _isProcessing = false;
  Uint8List _audioBuffer = Uint8List(0);
  DateTime? _lastSpeechTime;
  bool _isSpeechActive = false;

  final StreamController<VoiceSessionEvent> _eventController =
      StreamController<VoiceSessionEvent>.broadcast();

  // Audio capture manager for recording
  final AudioCaptureManager _audioCapture = AudioCaptureManager();

  // Audio playback manager for TTS output
  final AudioPlaybackManager _audioPlayback = AudioPlaybackManager();

  // Callback for processing audio (injected from RunAnywhere)
  final Future<VoiceAgentProcessResult> Function(Uint8List audioData)?
      _processAudioCallback;

  // Callback for voice agent readiness check
  final Future<bool> Function()? _isVoiceAgentReadyCallback;

  // Callback for initializing voice agent with loaded models
  final Future<void> Function()? _initializeVoiceAgentCallback;

  VoiceSessionHandle({
    VoiceSessionConfig? config,
    Future<VoiceAgentProcessResult> Function(Uint8List audioData)?
        processAudioCallback,
    @Deprecated('Permission is now handled internally by AudioCaptureManager')
    Future<bool> Function()? requestPermissionCallback,
    Future<bool> Function()? isVoiceAgentReadyCallback,
    Future<void> Function()? initializeVoiceAgentCallback,
  })  : config = config ?? VoiceSessionConfig.defaultConfig,
        _processAudioCallback = processAudioCallback,
        _isVoiceAgentReadyCallback = isVoiceAgentReadyCallback,
        _initializeVoiceAgentCallback = initializeVoiceAgentCallback;

  /// Stream of session events
  /// Matches iOS VoiceSessionHandle.events
  Stream<VoiceSessionEvent> get events => _eventController.stream;

  /// Whether the session is currently running
  bool get isRunning => _isRunning;

  /// Whether the session is currently processing audio or playing TTS
  bool get isProcessing => _isProcessing;

  /// Start the voice session
  /// Matches iOS VoiceSessionHandle.start()
  Future<void> start() async {
    if (_isRunning) {
      _logger.warning('Voice session already running');
      return;
    }

    _logger.info('🚀 Starting voice session...');

    // Verify voice agent is ready, or try to initialize
    _logger.info('Checking if voice agent is ready...');
    final isReady = await _isVoiceAgentReadyCallback?.call() ?? false;
    _logger.info('Voice agent ready: $isReady');

    if (!isReady) {
      try {
        _logger.info(
            'Voice agent not ready, attempting to initialize with loaded models...');
        await _initializeVoiceAgentCallback?.call();
        _logger.info('✅ Voice agent initialized successfully');
      } catch (e) {
        _logger.error('❌ Failed to initialize voice agent: $e');
        final errorMsg =
            'Voice agent not ready: $e. Make sure STT, LLM, and TTS models are loaded.';
        _emit(VoiceSessionError(message: errorMsg));
        rethrow;
      }
    }

    // Request mic permission via audio capture manager
    _logger.info('Requesting microphone permission...');
    final hasPermission = await _audioCapture.requestPermission();
    if (!hasPermission) {
      _logger.error('❌ Microphone permission denied');
      _emit(const VoiceSessionError(message: 'Microphone permission denied'));
      throw const VoiceSessionException(
        VoiceSessionErrorType.microphonePermissionDenied,
        'Microphone permission denied',
      );
    }
    _logger.info('✅ Microphone permission granted');

    _isRunning = true;
    _emit(const VoiceSessionStarted());

    // Start listening - this starts the audio capture loop
    await _startListening();

    _logger.info('✅ Voice session started with audio capture');
  }

  /// Start audio capture loop
  /// Matches iOS VoiceSessionHandle.startListening()
  Future<void> _startListening() async {
    if (_isProcessing) {
      _logger.warning('⚠️ Cannot start listening while processing');
      return;
    }

    _audioBuffer = Uint8List(0);
    _lastSpeechTime = null;
    _isSpeechActive = false;

    _logger.info('🎙️ Starting audio capture...');
    _logger.info(
        '📋 Config: speechThreshold=${config.speechThreshold}, silenceDuration=${config.silenceDuration}s');

    try {
      int chunkCount = 0;
      double maxLevelSeen = 0.0;
      await _audioCapture.startRecording((Uint8List audioData) {
        if (!_isRunning || _isProcessing) {
          return;
        }
        chunkCount++;

        // Log first few chunks and then periodically
        if (chunkCount <= 5 || chunkCount % 50 == 0) {
          final audioLevel = _calculateAudioLevel(audioData);
          if (audioLevel > maxLevelSeen) maxLevelSeen = audioLevel;
          _logger.info(
              '📊 Audio chunk #$chunkCount: ${audioData.length} bytes, level=${audioLevel.toStringAsFixed(4)}, max=${maxLevelSeen.toStringAsFixed(4)}, threshold=${config.speechThreshold}');
        }
        _handleAudioChunk(audioData);
      });
      _logger.info(
          '✅ Audio capture started successfully - waiting for audio data...');
    } catch (e) {
      _logger.error('❌ Failed to start audio capture: $e');
      _emit(VoiceSessionError(message: 'Failed to start audio capture: $e'));
      _isRunning = false;
      rethrow;
    }
  }

  /// Stop audio capture (used during processing/playback to prevent feedback)
  void _stopListening() {
    unawaited(_audioCapture.stopRecording());
    _audioBuffer = Uint8List(0);
    _isSpeechActive = false;
    _lastSpeechTime = null;
    _logger.info('🔇 Audio capture stopped');
  }

  /// Handle incoming audio chunk from capture
  void _handleAudioChunk(Uint8List data) {
    if (!_isRunning || _isProcessing) return;

    // Calculate audio level from the audio data
    final audioLevel = _calculateAudioLevel(data);

    // Append to buffer
    final newBuffer = Uint8List(_audioBuffer.length + data.length);
    newBuffer.setRange(0, _audioBuffer.length, _audioBuffer);
    newBuffer.setRange(_audioBuffer.length, newBuffer.length, data);
    _audioBuffer = newBuffer;

    // Check speech state with calculated audio level
    _checkSpeechState(audioLevel);
  }

  /// Calculate audio level (RMS) from audio data
  /// Returns 0.0 to 1.0
  double _calculateAudioLevel(Uint8List data) {
    if (data.isEmpty) return 0.0;

    // Audio is 16-bit PCM, so read as Int16
    final samples = data.length ~/ 2;
    if (samples == 0) return 0.0;

    double sumSquares = 0.0;
    for (int i = 0; i < samples; i++) {
      // Read little-endian Int16
      final int low = data[i * 2];
      final int high = data[i * 2 + 1];
      int sample = (high << 8) | low;
      // Handle sign extension for negative values
      if (sample > 32767) sample -= 65536;

      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
    }

    final rms = math.sqrt(sumSquares / samples);
    // Scale to 0-1 range (RMS of full-scale sine is ~0.707)
    return math.min(1.0, rms * 1.4);
  }

  /// Stop the voice session
  /// Matches iOS VoiceSessionHandle.stop()
  void stop() {
    if (!_isRunning) return;

    _isRunning = false;
    _isProcessing = false;

    // Stop audio capture and playback
    unawaited(_audioCapture.stopRecording());
    unawaited(_audioPlayback.stop());

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

  /// Feed audio data to the session (for external audio sources)
  /// Can be used for custom audio capture or testing
  void feedAudio(Uint8List data, double audioLevel) {
    if (!_isRunning || _isProcessing) return;

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
    if (_isProcessing) return;

    _emit(VoiceSessionListening(audioLevel: level));

    if (level > config.speechThreshold) {
      if (!_isSpeechActive) {
        _logger.info(
            '🎤 Speech STARTED! level=${level.toStringAsFixed(4)} > threshold=${config.speechThreshold}');
        _isSpeechActive = true;
        _emit(const VoiceSessionSpeechStarted());
      }
      _lastSpeechTime = DateTime.now();
    } else if (_isSpeechActive) {
      final lastTime = _lastSpeechTime;
      if (lastTime != null) {
        // Use milliseconds for accurate comparison with fractional seconds
        final silenceMs = DateTime.now().difference(lastTime).inMilliseconds;
        final thresholdMs = (config.silenceDuration * 1000).toInt();

        if (silenceMs >= thresholdMs) {
          _logger.info(
              '🔇 Speech ENDED after ${silenceMs}ms silence, buffer: ${_audioBuffer.length} bytes');
          _isSpeechActive = false;

          // Only process if we have enough audio (~0.5s at 16kHz = 16000 bytes)
          if (_audioBuffer.length > 16000) {
            _logger.info(
                '📤 Processing ${_audioBuffer.length} bytes of audio (~${(_audioBuffer.length / 32000).toStringAsFixed(1)}s)...');
            unawaited(_processCurrentAudio());
          } else {
            _logger.warning(
                '⚠️ Audio buffer too small (${_audioBuffer.length} bytes < 16000), discarding');
            _audioBuffer = Uint8List(0);
          }
        }
      }
    }
  }

  Future<void> _processCurrentAudio() async {
    final audio = _audioBuffer;
    _audioBuffer = Uint8List(0);

    if (audio.isEmpty) {
      _logger.warning('⚠️ Cannot process: audio buffer is empty');
      return;
    }

    if (!_isRunning) {
      _logger.warning('⚠️ Cannot process: session not running');
      return;
    }

    // IMPORTANT: Stop listening during processing to prevent feedback loop
    _isProcessing = true;
    _stopListening();

    final audioDuration = audio.length / 32000; // 16kHz * 2 bytes per sample
    _logger.info(
        '🔄 Processing ${audio.length} bytes (~${audioDuration.toStringAsFixed(1)}s) of audio...');
    _emit(const VoiceSessionProcessing());

    try {
      if (_processAudioCallback == null) {
        _logger.error(
            '❌ CRITICAL: No processing callback configured! This is a bug - the callback should be set when VoiceSessionHandle is created.');
        _emit(const VoiceSessionError(
            message:
                'No processing callback configured. Voice agent may not be initialized.'));
        return;
      }

      _logger.info('📞 Calling voice agent processAudio...');
      final stopwatch = Stopwatch()..start();
      final result = await _processAudioCallback!.call(audio);
      stopwatch.stop();
      _logger.info(
          '⏱️ Voice agent processing took ${stopwatch.elapsedMilliseconds}ms');

      if (!result.speechDetected) {
        _logger
            .info('🔇 No speech detected in audio (might be silence or noise)');
        // Resume listening
        if (config.continuousMode && _isRunning) {
          _logger.info('👂 Continuous mode: Resuming listening');
          _isProcessing = false;
          await _startListening();
        }
        return;
      }

      _logger.info(
          '✅ Speech detected! Transcription: "${result.transcription ?? "(empty)"}"');

      // Emit intermediate results
      if (result.transcription != null && result.transcription!.isNotEmpty) {
        _emit(VoiceSessionTranscribed(text: result.transcription!));
      } else {
        _logger.warning('⚠️ STT returned empty transcription');
      }

      if (result.response != null && result.response!.isNotEmpty) {
        final previewLen =
            result.response!.length > 100 ? 100 : result.response!.length;
        _logger.info(
            '💬 LLM Response (${result.response!.length} chars): "${result.response!.substring(0, previewLen)}${result.response!.length > 100 ? "..." : ""}"');
        _emit(VoiceSessionResponded(text: result.response!));
      } else {
        _logger.warning('⚠️ LLM returned empty response');
      }

      // Play TTS audio if available and enabled
      if (config.autoPlayTTS &&
          result.synthesizedAudio != null &&
          result.synthesizedAudio!.isNotEmpty) {
        // TTS audio from ONNX Piper is typically 22050Hz mono PCM16
        final ttsDuration = result.synthesizedAudio!.length / (22050 * 2);
        _logger.info(
            '🔊 Playing TTS audio: ${result.synthesizedAudio!.length} bytes (~${ttsDuration.toStringAsFixed(1)}s)');
        _emit(const VoiceSessionSpeaking());

        try {
          // Play audio and wait for completion
          await _audioPlayback.play(
            result.synthesizedAudio!,
            sampleRate: 22050, // ONNX Piper TTS default
            numChannels: 1,
          );
          _logger.info('🔊 TTS playback completed');
        } catch (e) {
          _logger.error('❌ TTS playback failed: $e');
          // Continue even if playback fails
        }
      }

      // Emit complete result
      _emit(VoiceSessionTurnCompleted(
        transcript: result.transcription ?? '',
        response: result.response ?? '',
        audio: result.synthesizedAudio,
      ));
      _logger.info('✅ Voice turn completed successfully');
    } catch (e, stack) {
      _logger.error('❌ Processing failed: $e');
      _logger.error('Stack trace: $stack');
      _emit(VoiceSessionError(message: e.toString()));
    } finally {
      // Resume listening if continuous mode and session still running
      _isProcessing = false;
      if (config.continuousMode && _isRunning) {
        _logger.info('👂 Continuous mode: Resuming listening after turn');
        try {
          await _startListening();
        } catch (e) {
          _logger.error('❌ Failed to resume listening: $e');
        }
      }
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    stop();
    await _audioPlayback.dispose();
    _audioCapture.dispose();
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
