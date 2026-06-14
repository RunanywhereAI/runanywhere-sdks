// SPDX-License-Identifier: Apache-2.0
//
// audio_capture_manager.dart — SDK-owned microphone capture for STT.
//
// Mirrors Swift `Features/STT/Services/AudioCaptureManager.swift`: the SDK
// owns audio capture (repo layering rule — platform audio capture/playback
// belongs in the platform SDK, not example apps). Emits PCM16 chunks the
// SDK's streaming transcription session consumes directly, plus a normalized
// audio-level stream for UI meters (Swift's `@Published audioLevel`).
//
// Implementation rides the `record` plugin — the Dart analogue of Swift's
// AVAudioEngine tap.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// SDK-owned microphone capture for speech-to-text.
///
/// Mirrors Swift `AudioCaptureManager`: `startRecording` emits PCM16 chunks
/// (the streaming-STT input), `startRecordingToBuffer`/`stopRecording` is the
/// one-shot WAV convenience, `audioLevelStream` mirrors `@Published audioLevel`.
class AudioCaptureManager {
  AudioCaptureManager();

  static final _logger = SDKLogger('AudioCaptureManager');

  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  String? _currentRecordingPath;
  StreamController<double>? _audioLevelController;
  Timer? _audioLevelTimer;

  /// Whether capture is active. Mirrors Swift `isRecording`.
  bool get isRecording => _isRecording;

  /// Normalized audio levels (0.0 to 1.0) while recording, or null when no
  /// capture is active. Mirrors Swift's `@Published audioLevel`.
  Stream<double>? get audioLevelStream => _audioLevelController?.stream;

  /// Whether microphone permission is granted (requests it when needed).
  /// Mirrors Swift `requestPermission()`.
  Future<bool> requestPermission() {
    return _recorder.hasPermission();
  }

  /// Start a raw PCM16 chunk stream (no file). The canonical streaming-STT
  /// input: chunks feed straight into `RunAnywhere.transcribeStream(...)`.
  /// Mirrors Swift's tap `onAudioData` Int16 PCM callback as a Dart stream.
  ///
  /// Returns null when microphone permission is missing or capture fails.
  Future<Stream<Uint8List>?> startRecording({
    int sampleRate = 16000,
    int numChannels = 1,
  }) async {
    if (_isRecording) {
      await stopRecording();
    }
    if (!await _recorder.hasPermission()) {
      _logger.warning('Microphone permission not granted');
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
      return stream;
    } catch (e) {
      _logger.error('Failed to start PCM capture: $e');
      _isRecording = false;
      return null;
    }
  }

  /// One-shot convenience: record to a temp WAV file until [stopRecording]
  /// is called. Returns the recording path, or null on failure.
  Future<String?> startRecordingToBuffer({
    int sampleRate = 16000,
    int numChannels = 1,
  }) async {
    if (_isRecording) {
      await stopRecording();
    }
    if (!await _recorder.hasPermission()) {
      _logger.warning('Microphone permission not granted');
      return null;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/runanywhere_rec_$timestamp.wav';
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: numChannels,
          bitRate: 128000,
        ),
        path: _currentRecordingPath!,
      );
      _isRecording = true;
      _startAudioLevelMonitoring();
      return _currentRecordingPath;
    } catch (e) {
      _logger.error('Failed to start recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      return null;
    }
  }

  /// Stop capture. For a [startRecordingToBuffer] session, returns the
  /// accumulated WAV bytes (and deletes the temp file); for a chunk-stream
  /// session, closing the recorder ends the stream (which lets the SDK
  /// session flush its final result) and this returns null.
  /// Mirrors Swift `stopRecording()`.
  Future<Uint8List?> stopRecording() async {
    if (!_isRecording) {
      return null;
    }
    _stopAudioLevelMonitoring();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      _logger.error('Failed to stop capture: $e');
    }
    _isRecording = false;

    final recordingPath = _currentRecordingPath;
    _currentRecordingPath = null;
    if (recordingPath == null) {
      // Chunk-stream session: no file involved.
      return null;
    }

    final file = File(path ?? recordingPath);
    if (!await file.exists()) {
      _logger.error('Recording file does not exist: ${file.path}');
      return null;
    }
    final audioData = await file.readAsBytes();
    try {
      await file.delete();
    } catch (e) {
      _logger.warning('Failed to cleanup temp recording file: $e');
    }
    return audioData;
  }

  /// Cancel the current capture without returning data.
  /// Mirrors Swift `cancel()`.
  Future<void> cancel() async {
    if (!_isRecording) {
      return;
    }
    _stopAudioLevelMonitoring();
    try {
      await _recorder.stop();
    } catch (e) {
      _logger.warning('Failed to cancel capture: $e');
    }
    final recordingPath = _currentRecordingPath;
    _currentRecordingPath = null;
    _isRecording = false;
    if (recordingPath != null) {
      final file = File(recordingPath);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort temp cleanup.
      }
    }
  }

  /// Release the recorder. The manager is inert afterwards.
  Future<void> dispose() async {
    _stopAudioLevelMonitoring();
    if (_isRecording) {
      await cancel();
    }
    await _recorder.dispose();
  }

  void _startAudioLevelMonitoring() {
    _audioLevelController = StreamController<double>.broadcast();
    _audioLevelTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      try {
        final amplitude = await _recorder.getAmplitude();
        if (amplitude.current != double.negativeInfinity) {
          // Convert dB to a normalized level: -60 dB (quiet) .. 0 dB (loud).
          final normalizedLevel =
              ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
          _audioLevelController?.add(normalizedLevel);
        }
      } catch (_) {
        // Ignore amplitude read errors.
      }
    });
  }

  void _stopAudioLevelMonitoring() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
    final controller = _audioLevelController;
    if (controller != null) {
      unawaited(controller.close());
    }
    _audioLevelController = null;
  }
}
