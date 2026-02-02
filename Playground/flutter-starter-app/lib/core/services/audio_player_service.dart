import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Audio Player Service
///
/// Handles audio playback for Text-to-Speech functionality.
/// Uses the `audioplayers` package for cross-platform audio playback.
class AudioPlayerService {
  static final AudioPlayerService instance = AudioPlayerService._internal();

  AudioPlayerService._internal();

  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

  // Track temp files for cleanup
  File? _currentTempFile;

  /// Whether audio is currently playing
  bool get isPlaying => _isPlaying;

  /// Current playback duration
  Duration get duration => _duration;

  /// Current playback position
  Duration get position => _position;

  /// Stream of playing state changes
  Stream<bool> get playingStream => _playingController.stream;

  /// Stream of playback progress (0.0 to 1.0)
  Stream<double> get progressStream => _progressController.stream;

  /// Initialize the audio player and set up listeners
  Future<void> initialize() async {
    // Listen to player state changes
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      final wasPlaying = _isPlaying;
      _isPlaying = state == PlayerState.playing;

      if (wasPlaying != _isPlaying) {
        _playingController.add(_isPlaying);
      }

      // Reset position when playback completes
      if (state == PlayerState.completed) {
        _position = Duration.zero;
        _progressController.add(0.0);
      }
    });

    // Listen to duration changes
    _durationSubscription = _player.onDurationChanged.listen((duration) {
      _duration = duration;
      debugPrint('🎵 Audio duration: ${duration.inSeconds}s');
    });

    // Listen to position changes
    _positionSubscription = _player.onPositionChanged.listen((position) {
      _position = position;

      if (_duration.inMilliseconds > 0) {
        final progress = position.inMilliseconds / _duration.inMilliseconds;
        _progressController.add(progress.clamp(0.0, 1.0));
      }
    });

    debugPrint('🎵 Audio player initialized');
  }

  /// Play audio from bytes
  ///
  /// [audioData] - The audio data as PCM16 bytes
  /// [volume] - Volume level (0.0 to 1.0)
  /// [rate] - Playback rate (0.5 to 2.0)
  /// [sampleRate] - Sample rate of the audio (default: 22050)
  /// [numChannels] - Number of channels (default: 1 for mono)
  Future<void> playFromBytes(
    Uint8List audioData, {
    double volume = 1.0,
    double rate = 1.0,
    int sampleRate = 22050,
    int numChannels = 1,
  }) async {
    try {
      // Stop any current playback
      await stop();

      // Clean up previous temp file if it exists
      await _cleanupTempFile();

      // Create a temporary file for the audio data
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/tts_audio_$timestamp.wav');
      _currentTempFile = tempFile;

      // Convert PCM16 to proper WAV file with headers
      final wavData = _createWavFile(audioData, sampleRate, numChannels);

      // Write WAV data to temp file
      await tempFile.writeAsBytes(wavData);
      debugPrint(
          '🎵 Wrote ${wavData.length} bytes (${audioData.length} PCM + headers) to: ${tempFile.path}');

      // Set volume and rate
      await _player.setVolume(volume.clamp(0.0, 1.0));
      await _player.setPlaybackRate(rate.clamp(0.5, 2.0));

      // Play the audio file
      await _player.play(DeviceFileSource(tempFile.path));

      debugPrint('🎵 Playing audio from file: ${tempFile.path}');
    } catch (e) {
      debugPrint('❌ Failed to play audio: $e');
      rethrow;
    }
  }

  /// Create a proper WAV file from PCM16 data
  /// Returns WAV file bytes with proper headers
  Uint8List _createWavFile(
      Uint8List pcm16Data, int sampleRate, int numChannels) {
    final int byteRate =
        sampleRate * numChannels * 2; // 2 bytes per sample (16-bit)
    final int blockAlign = numChannels * 2;
    final int dataSize = pcm16Data.length;
    final int fileSize = 36 + dataSize; // 44 byte header - 8 + data size

    final ByteData header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, fileSize, Endian.little); // File size - 8

    // WAVE header
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    header.setUint16(22, numChannels, Endian.little); // NumChannels
    header.setUint32(24, sampleRate, Endian.little); // SampleRate
    header.setUint32(28, byteRate, Endian.little); // ByteRate
    header.setUint16(32, blockAlign, Endian.little); // BlockAlign
    header.setUint16(34, 16, Endian.little); // BitsPerSample

    // data subchunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little); // Subchunk2Size

    // Combine header and PCM data
    final wavFile = Uint8List(44 + dataSize);
    wavFile.setAll(0, header.buffer.asUint8List());
    wavFile.setAll(44, pcm16Data);

    return wavFile;
  }

  /// Play audio from file path
  ///
  /// [filePath] - Path to the audio file
  /// [volume] - Volume level (0.0 to 1.0)
  /// [rate] - Playback rate (0.5 to 2.0)
  Future<void> playFromFile(
    String filePath, {
    double volume = 1.0,
    double rate = 1.0,
  }) async {
    try {
      // Stop any current playback
      await stop();

      // Set volume and rate
      await _player.setVolume(volume.clamp(0.0, 1.0));
      await _player.setPlaybackRate(rate.clamp(0.5, 2.0));

      // Play the audio file
      await _player.play(DeviceFileSource(filePath));

      debugPrint('🎵 Playing audio from file: $filePath');
    } catch (e) {
      debugPrint('❌ Failed to play audio: $e');
      rethrow;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (_isPlaying) {
      await _player.pause();
      debugPrint('⏸️ Audio playback paused');
    }
  }

  /// Resume playback
  Future<void> resume() async {
    if (!_isPlaying) {
      await _player.resume();
      debugPrint('▶️ Audio playback resumed');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    if (_isPlaying) {
      await _player.stop();
      _position = Duration.zero;
      _progressController.add(0.0);
      debugPrint('⏹️ Audio playback stopped');
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    debugPrint('⏩ Seeked to: ${position.inSeconds}s');
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Set playback rate (0.5 to 2.0)
  Future<void> setRate(double rate) async {
    await _player.setPlaybackRate(rate.clamp(0.5, 2.0));
  }

  /// Clean up temporary audio file
  Future<void> _cleanupTempFile() async {
    if (_currentTempFile != null) {
      try {
        if (await _currentTempFile!.exists()) {
          await _currentTempFile!.delete();
          debugPrint('🗑️ Cleaned up temp audio file');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to cleanup temp file: $e');
      }
      _currentTempFile = null;
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _playerStateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _playingController.close();
    await _progressController.close();
    await _player.dispose();
    await _cleanupTempFile();
    debugPrint('🎵 Audio player disposed');
  }
}
