import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
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
  /// [audioData] - The audio data as bytes (WAV, MP3, etc.)
  /// [volume] - Volume level (0.0 to 1.0)
  /// [rate] - Playback rate (0.5 to 2.0)
  Future<void> playFromBytes(
    Uint8List audioData, {
    double volume = 1.0,
    double rate = 1.0,
  }) async {
    try {
      // Stop any current playback
      await stop();

      // Create a temporary file for the audio data
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/tts_audio_$timestamp.wav');

      // Write audio data to temp file
      await tempFile.writeAsBytes(audioData);
      debugPrint('🎵 Wrote ${audioData.length} bytes to: ${tempFile.path}');

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

  /// Dispose of resources
  Future<void> dispose() async {
    await _playerStateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _playingController.close();
    await _progressController.close();
    await _player.dispose();
    debugPrint('🎵 Audio player disposed');
  }
}
