// SPDX-License-Identifier: Apache-2.0
//
// audio_playback_manager.dart — SDK-owned TTS audio playback.
//
// Mirrors Swift `Features/TTS/Services/AudioPlaybackManager.swift`: the SDK
// owns audio playback (repo layering rule — platform audio capture/playback
// belongs in the platform SDK, not example apps), so `RunAnywhere.speak(...)`
// can synthesize AND play in one call exactly like Swift.
//
// Implementation rides the `audioplayers` plugin via a temp WAV file —
// the Dart analogue of Swift's AVAudioPlayer-over-Data playback.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Thrown when audio playback fails. Mirrors Swift `AudioPlaybackError`.
class AudioPlaybackException implements Exception {
  AudioPlaybackException(this.message);

  final String message;

  @override
  String toString() => 'AudioPlaybackException: $message';
}

/// SDK-owned audio playback for synthesized speech.
///
/// Mirrors Swift `AudioPlaybackManager` (play/pause/resume/stop +
/// isPlaying/currentTime/duration + playing/progress streams).
class AudioPlaybackManager {
  AudioPlaybackManager() {
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      final wasPlaying = _isPlaying;
      _isPlaying = state == PlayerState.playing;
      if (wasPlaying != _isPlaying) {
        _playingController.add(_isPlaying);
      }
      if (state == PlayerState.completed) {
        _position = Duration.zero;
        _progressController.add(0.0);
        _completePlayback();
      }
      if (state == PlayerState.stopped) {
        _completePlayback();
      }
    });
    _durationSubscription = _player.onDurationChanged.listen((duration) {
      _duration = duration;
    });
    _positionSubscription = _player.onPositionChanged.listen((position) {
      _position = position;
      if (_duration.inMilliseconds > 0) {
        final progress = position.inMilliseconds / _duration.inMilliseconds;
        _progressController.add(progress.clamp(0.0, 1.0));
      }
    });
  }

  static final _logger = SDKLogger('AudioPlaybackManager');

  final AudioPlayer _player = AudioPlayer();

  /// When `true` (default) this manager configures playback with the
  /// output-only `.playback` audio session category — correct for standalone
  /// `RunAnywhere.speak(...)`. Set to `false` when the caller owns a live
  /// full-duplex session — e.g. the voice agent keeps a single `.playAndRecord`
  /// session active across capture and playback. Switching to `.playback` while
  /// the mic session is live trips AVAudioSessionErrorInsufficientPriority
  /// ('!pri', OSStatus 561017449) and the reply never plays. Mirrors Swift
  /// `AudioPlaybackManager.managesAudioSession`.
  bool managesAudioSession = true;

  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Completer<void>? _playbackCompleter;
  File? _currentTempFile;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

  /// Whether audio is currently playing. Mirrors Swift `isPlaying`.
  bool get isPlaying => _isPlaying;

  /// Current playback position. Mirrors Swift `currentTime`.
  Duration get currentTime => _position;

  /// Total duration of the loaded audio. Mirrors Swift `duration`.
  Duration get duration => _duration;

  /// Stream of playing-state changes. Mirrors Swift's `@Published isPlaying`.
  Stream<bool> get playingStream => _playingController.stream;

  /// Stream of playback progress (0.0 to 1.0). Mirrors Swift's progress timer.
  Stream<double> get progressStream => _progressController.stream;

  /// Play a complete WAV buffer and complete when playback finishes (or is
  /// stopped). Mirrors Swift `play(_ audioData: Data) async throws`.
  ///
  /// [volume] 0.0–1.0; [rate] 0.5–2.0.
  Future<void> play(
    Uint8List wavData, {
    double volume = 1.0,
    double rate = 1.0,
  }) async {
    if (wavData.isEmpty) {
      throw AudioPlaybackException('No audio data to play');
    }

    await stop();
    await _cleanupTempFile();

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/runanywhere_tts_$timestamp.wav');
    _currentTempFile = tempFile;
    await tempFile.writeAsBytes(wavData);

    // Mix with other audio instead of taking exclusive audio focus. On Android
    // this maps to AndroidAudioFocus.none, so playing a TTS reply does NOT
    // evict the voice-agent mic recorder (which otherwise receives
    // AUDIOFOCUS_LOSS and stops — leaving the pipeline deaf after the first
    // turn). The voice-agent mic driver gates capture during playback, so
    // coexisting record + playback never self-transcribes.
    if (managesAudioSession) {
      await _player.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
    } else {
      // The voice agent owns a live `.playAndRecord` mic session (the `record`
      // plugin's default category). Match that category here instead of the
      // default `.playback`: switching to an output-only category while the mic
      // session is active trips AVAudioSessionErrorInsufficientPriority ('!pri',
      // OSStatus 561017449) and the reply is silently dropped. `defaultToSpeaker`
      // forces the loud speaker route (under `.playAndRecord` the output can
      // otherwise fall back to the quiet receiver). Android keeps focus=none so
      // playback does not evict the recorder. Mirrors the iOS Swift driver's
      // configureVoiceAudioSession() + managesAudioSession=false.
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.allowBluetoothA2DP,
            },
          ),
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
    }

    await _player.setVolume(volume.clamp(0.0, 1.0));
    await _player.setPlaybackRate(rate.clamp(0.5, 2.0));

    final completer = Completer<void>();
    _playbackCompleter = completer;
    try {
      await _player.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      _playbackCompleter = null;
      throw AudioPlaybackException('Failed to start playback: $e');
    }
    return completer.future;
  }

  /// Stop playback. Mirrors Swift `stop()`.
  Future<void> stop() async {
    if (_isPlaying) {
      await _player.stop();
      _position = Duration.zero;
      _progressController.add(0.0);
    }
    _completePlayback();
  }

  /// Pause playback. Mirrors Swift `pause()`.
  Future<void> pause() async {
    if (_isPlaying) {
      await _player.pause();
    }
  }

  /// Resume paused playback. Mirrors Swift `resume()`.
  Future<void> resume() async {
    await _player.resume();
  }

  /// Release the player and streams. The manager is inert afterwards.
  Future<void> dispose() async {
    await _playerStateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _playingController.close();
    await _progressController.close();
    await _player.dispose();
    await _cleanupTempFile();
    _completePlayback();
  }

  void _completePlayback() {
    final completer = _playbackCompleter;
    _playbackCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _cleanupTempFile() async {
    final file = _currentTempFile;
    _currentTempFile = null;
    if (file != null) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        _logger.warning('Failed to cleanup temp audio file: $e');
      }
    }
  }
}
