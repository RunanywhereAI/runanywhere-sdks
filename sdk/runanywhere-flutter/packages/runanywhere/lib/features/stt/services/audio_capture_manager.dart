import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Manages audio capture from microphone for STT services.
///
/// This is a shared utility that works with any STT backend (ONNX, WhisperKit, etc.).
/// It captures audio at 16kHz mono Int16 format, which is the standard input format
/// for speech recognition models like Whisper.
///
/// Matches iOS AudioCaptureManager from Features/STT/Services/AudioCaptureManager.swift
///
/// ## Usage
/// ```dart
/// final capture = AudioCaptureManager();
/// final granted = await capture.requestPermission();
/// if (granted) {
///   await capture.startRecording((audioData) {
///     // Feed audioData to your STT service
///   });
/// }
/// ```
class AudioCaptureManager {
  final SDKLogger _logger = SDKLogger('AudioCapture');

  /// Audio recorder instance
  final AudioRecorder _recorder = AudioRecorder();

  /// Whether audio is currently being recorded
  bool _isRecording = false;

  /// Current audio level (0.0 to 1.0)
  double _audioLevel = 0.0;

  /// Target sample rate for Whisper models
  static const int targetSampleRate = 16000;

  /// Audio data callback
  void Function(Uint8List audioData)? _onAudioData;

  /// Audio stream subscription
  StreamSubscription<Uint8List>? _audioStreamSubscription;

  /// Stream controller for recording state changes
  final _recordingStateController = StreamController<bool>.broadcast();

  /// Stream controller for audio level updates
  final _audioLevelController = StreamController<double>.broadcast();

  /// Stream of recording state changes
  Stream<bool> get recordingStateStream => _recordingStateController.stream;

  /// Stream of audio level updates (0.0 to 1.0)
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  /// Whether audio is currently being recorded
  bool get isRecording => _isRecording;

  /// Current audio level (0.0 to 1.0)
  double get audioLevel => _audioLevel;

  AudioCaptureManager() {
    _logger.info('AudioCaptureManager initialized');
  }

  /// Request microphone permission
  ///
  /// Returns true if permission was granted, false otherwise.
  Future<bool> requestPermission() async {
    try {
      _logger.info('Requesting microphone permission');

      // Check and request microphone permission
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _logger.info('Microphone permission granted');
        return true;
      } else if (status.isPermanentlyDenied) {
        _logger.warning(
            'Microphone permission permanently denied - user should enable in settings');
        return false;
      } else {
        _logger.warning('Microphone permission denied: $status');
        return false;
      }
    } catch (e) {
      _logger.error('Failed to request microphone permission: $e');
      return false;
    }
  }

  /// Start recording audio from microphone
  ///
  /// [onAudioData] Callback for audio data chunks (16kHz mono Int16 PCM)
  ///
  /// Throws [AudioCaptureError] if recording cannot be started.
  Future<void> startRecording(
      void Function(Uint8List audioData) onAudioData) async {
    if (_isRecording) {
      _logger.warning('Already recording');
      return;
    }

    try {
      _onAudioData = onAudioData;

      // Check if we can record
      _logger.info('Checking microphone permission...');
      if (!await _recorder.hasPermission()) {
        _logger.error('No microphone permission');
        throw AudioCaptureError.permissionDenied();
      }
      _logger.info('✅ Microphone permission granted');

      // Start streaming audio in PCM 16-bit format
      _logger.info(
          'Starting audio stream: ${targetSampleRate}Hz, mono, PCM16bits...');
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: targetSampleRate,
          numChannels: 1, // Mono
          bitRate: 256000,
        ),
      );
      _logger.info('✅ Audio stream created, setting up listener...');

      // Track data delivery
      int chunkCount = 0;

      // Listen to audio stream
      _audioStreamSubscription = stream.listen(
        (data) {
          chunkCount++;
          // Log first few chunks to verify data flow
          if (chunkCount <= 3) {
            _logger.info(
                '🎵 Audio data received: chunk #$chunkCount, ${data.length} bytes');
          }
          if (_isRecording && _onAudioData != null) {
            _onAudioData!(data);
          } else {
            _logger.warning(
                '⚠️ Audio data ignored: isRecording=$_isRecording, hasCallback=${_onAudioData != null}');
          }
        },
        onError: (Object error) {
          _logger.error('❌ Audio stream error: $error');
        },
        onDone: () {
          _logger.info('🛑 Audio stream ended (total chunks: $chunkCount)');
        },
      );

      _isRecording = true;
      _recordingStateController.add(true);

      _logger.info(
          '✅ Recording started successfully (16kHz mono PCM) - waiting for audio data...');
    } catch (e) {
      _logger.error('❌ Failed to start recording: $e');
      _onAudioData = null;
      throw AudioCaptureError.engineStartFailed();
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      // Cancel stream subscription
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // Stop the recorder
      await _recorder.stop();

      _isRecording = false;
      _audioLevel = 0.0;
      _onAudioData = null;

      _recordingStateController.add(false);
      _audioLevelController.add(0.0);

      _logger.info('Recording stopped');
    } catch (e) {
      _logger.error('Error stopping recording: $e');
    }
  }

  /// Update audio level for visualization.
  ///
  /// This would be called from platform-specific audio buffer callbacks.
  /// The RMS→dB DSP is centralised in commons (`rac_audio_compute_level_db`);
  /// this method only normalises the dB reading to 0-1 for UI consumption.
  ///
  /// [buffer] Float audio samples in [-1.0, 1.0].
  void updateAudioLevel(Float32List buffer) {
    if (buffer.isEmpty) return;

    final compute = RacNative.bindings.rac_audio_compute_level_db;
    if (compute == null) {
      throw UnsupportedError('rac_audio_compute_level_db is unavailable');
    }

    final samples = calloc<ffi.Float>(buffer.length);
    final outDb = calloc<ffi.Float>();
    try {
      samples.asTypedList(buffer.length).setAll(0, buffer);
      compute(samples, buffer.length, outDb);
      final dbLevel = outDb.value;

      // Normalize to 0-1 range (-60dB to 0dB).
      final normalizedLevel = (dbLevel + 60) / 60;
      _audioLevel = normalizedLevel.clamp(0.0, 1.0);

      _audioLevelController.add(_audioLevel);
    } finally {
      calloc.free(samples);
      calloc.free(outDb);
    }
  }

  /// Convert audio buffer to PCM data
  ///
  /// This would be called from platform-specific audio buffer callbacks
  /// to convert audio samples to the format expected by STT models.
  ///
  /// [buffer] Int16 audio samples (16-bit PCM)
  /// Returns PCM data as bytes
  Uint8List bufferToData(Int16List buffer) {
    // Convert Int16 samples to bytes (little-endian)
    final bytes = BytesBuilder();
    for (final sample in buffer) {
      bytes.add([
        sample & 0xFF, // Low byte
        (sample >> 8) & 0xFF, // High byte
      ]);
    }
    return bytes.toBytes();
  }

  /// Called when audio data is available from the platform
  ///
  /// This would be called from platform-specific audio buffer callbacks.
  ///
  /// [audioData] Raw PCM audio data (16kHz mono Int16)
  void onAudioDataAvailable(Uint8List audioData) {
    final callback = _onAudioData;
    if (callback != null && _isRecording) {
      callback(audioData);
    }
  }

  /// Dispose resources
  void dispose() {
    unawaited(stopRecording());
    unawaited(_recordingStateController.close());
    unawaited(_audioLevelController.close());
  }
}

// MARK: - Errors

/// Audio capture errors
/// Matches iOS AudioCaptureError from AudioCaptureManager.swift
class AudioCaptureError implements Exception {
  final String message;
  final AudioCaptureErrorType type;

  AudioCaptureError._(this.message, this.type);

  factory AudioCaptureError.permissionDenied() {
    return AudioCaptureError._(
      'Microphone permission denied',
      AudioCaptureErrorType.permissionDenied,
    );
  }

  factory AudioCaptureError.formatConversionFailed() {
    return AudioCaptureError._(
      'Failed to convert audio format',
      AudioCaptureErrorType.formatConversionFailed,
    );
  }

  factory AudioCaptureError.engineStartFailed() {
    return AudioCaptureError._(
      'Failed to start audio engine',
      AudioCaptureErrorType.engineStartFailed,
    );
  }

  @override
  String toString() => 'AudioCaptureError: $message';
}

/// Audio capture error types
enum AudioCaptureErrorType {
  permissionDenied,
  formatConversionFailed,
  engineStartFailed,
}
