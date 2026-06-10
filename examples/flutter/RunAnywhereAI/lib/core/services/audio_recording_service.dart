import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Audio Recording Service
///
/// Handles audio recording for Speech-to-Text functionality.
/// Uses the `record` package for cross-platform audio capture.
class AudioRecordingService {
  static final AudioRecordingService instance =
      AudioRecordingService._internal();

  AudioRecordingService._internal();

  final AudioRecorder _recorder = AudioRecorder();

  StreamController<double>? _audioLevelController;
  Timer? _audioLevelTimer;

  bool _isRecording = false;
  String? _currentRecordingPath;

  /// Whether the service is currently recording
  bool get isRecording => _isRecording;

  /// Stream of audio levels (0.0 to 1.0) during recording
  Stream<double>? get audioLevelStream => _audioLevelController?.stream;

  /// Check if microphone permission is granted
  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  /// Start recording audio
  ///
  /// Returns the path to the temporary recording file
  Future<String?> startRecording({
    int sampleRate = 16000,
    int numChannels = 1,
    bool enableAudioLevels = true,
  }) async {
    if (_isRecording) {
      debugPrint('⚠️ Already recording, stopping previous recording first');
      await stopRecording();
    }

    // Check permissions
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('❌ Microphone permission not granted');
      return null;
    }

    try {
      // Create temp directory for recording
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/recording_$timestamp.wav';

      // Configure recording
      final config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: numChannels,
        bitRate: 128000,
      );

      // Start recording
      await _recorder.start(
        config,
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      debugPrint('🎙️ Recording started: $_currentRecordingPath');

      // Start audio level monitoring if enabled
      if (enableAudioLevels) {
        _startAudioLevelMonitoring();
      }

      return _currentRecordingPath;
    } catch (e) {
      debugPrint('❌ Failed to start recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      return null;
    }
  }

  /// Stop recording and return the audio data
  ///
  /// Returns a tuple of (audioData, filePath) or (null, null) if failed
  Future<(Uint8List?, String?)> stopRecording() async {
    if (!_isRecording) {
      debugPrint('⚠️ No active recording to stop');
      return (null, null);
    }

    try {
      // Stop audio level monitoring
      _stopAudioLevelMonitoring();

      // Stop recording
      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null) {
        debugPrint('❌ Recording path is null');
        _currentRecordingPath = null;
        return (null, null);
      }

      debugPrint('✅ Recording stopped: $path');

      // Read the recorded audio file
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('❌ Recording file does not exist: $path');
        _currentRecordingPath = null;
        return (null, null);
      }

      final audioData = await file.readAsBytes();
      debugPrint('📊 Audio data size: ${audioData.length} bytes');

      final recordingPath = _currentRecordingPath;
      _currentRecordingPath = null;

      // Clean up the temp file after reading
      try {
        await file.delete();
        debugPrint('🗑️ Cleaned up temp recording file');
      } catch (e) {
        debugPrint('⚠️ Failed to cleanup temp recording file: $e');
      }

      return (audioData, recordingPath);
    } catch (e) {
      debugPrint('❌ Failed to stop recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      return (null, null);
    }
  }

  /// Start a raw PCM16 chunk stream (no file). Used by live streaming STT —
  /// chunks are fed straight into the SDK's streaming transcription session.
  Future<Stream<Uint8List>?> startStreaming({
    int sampleRate = 16000,
    int numChannels = 1,
  }) async {
    if (_isRecording) {
      await stopRecording();
    }
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('❌ Microphone permission not granted');
      return null;
    }
    try {
      final stream = await _recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
      ));
      _isRecording = true;
      _currentRecordingPath = null;
      _startAudioLevelMonitoring();
      debugPrint('🎙️ PCM chunk streaming started');
      return stream;
    } catch (e) {
      debugPrint('❌ Failed to start chunk streaming: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Stop a chunk stream started with [startStreaming]. Closing the recorder
  /// ends the chunk stream, which lets the SDK session flush its final result.
  Future<void> stopStreaming() async {
    if (!_isRecording) {
      return;
    }
    _stopAudioLevelMonitoring();
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('❌ Failed to stop chunk streaming: $e');
    }
    _isRecording = false;
  }

  /// Cancel current recording without returning data
  Future<void> cancelRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      _stopAudioLevelMonitoring();
      await _recorder.stop();

      // Delete the temp file if it exists
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _isRecording = false;
      _currentRecordingPath = null;
      debugPrint('🗑️ Recording cancelled');
    } catch (e) {
      debugPrint('❌ Failed to cancel recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
    }
  }

  /// Start monitoring audio levels during recording
  void _startAudioLevelMonitoring() {
    _audioLevelController = StreamController<double>.broadcast();

    // Poll for audio amplitude
    _audioLevelTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      try {
        final amplitude = await _recorder.getAmplitude();
        if (amplitude.current != double.negativeInfinity) {
          // Convert dB to normalized level (0.0 to 1.0)
          // Typical range is -60 dB (quiet) to 0 dB (loud)
          final normalizedLevel =
              ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
          _audioLevelController?.add(normalizedLevel);
        }
      } catch (e) {
        // Ignore errors in amplitude reading
      }
    });
  }

  /// Stop monitoring audio levels
  void _stopAudioLevelMonitoring() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
    final controller = _audioLevelController;
    if (controller != null) {
      unawaited(controller.close());
    }
    _audioLevelController = null;
  }

  /// Dispose of resources
  Future<void> dispose() async {
    _stopAudioLevelMonitoring();
    if (_isRecording) {
      await cancelRecording();
    }
    await _recorder.dispose();
  }
}
