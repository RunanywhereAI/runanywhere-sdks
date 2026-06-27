// SPDX-License-Identifier: Apache-2.0
//
// voice_agent_mic_driver.dart — audio ingress for the Flutter voice agent.
//
// The C ABI owns NO microphone (rac_voice_agent.h "Audio-Ingress Contract"):
// the platform SDK must capture mic audio and push complete utterances into
// the C core, or the session is dead air. Without this driver the Flutter
// voice agent only subscribed to the output event stream and never fed any
// PCM, so VAD/STT never saw audio → the LLM got no input → no reply.
//
// Mirrors Kotlin `VoiceAgentMicDriver`: capture 16 kHz mono PCM16 via
// [AudioCaptureManager], segment utterances with energy-based endpointing,
// and drive each utterance through `rac_voice_agent_process_turn_proto`
// (DartBridgeVoiceAgent.processTurnStream). The turn's VoiceEvents are
// forwarded to [events] (so the public eventStream observes them) and the
// synthesized TTS reply is played through [AudioPlaybackManager].
//
// The endpointing is intentionally simple — the C++ pipeline re-runs its own
// VAD over each submitted buffer; the only job here is deciding where one
// utterance ends. Mic chunks that arrive while a turn is processing are
// dropped: the pipeline is strictly turn-taking (no barge-in), which also
// avoids transcribing the device's own TTS output.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:runanywhere/features/stt/services/audio_capture_manager.dart';
import 'package:runanywhere/features/tts/services/audio_playback_manager.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/voice_agent_service.pb.dart'
    as voice_agent_pb;
import 'package:runanywhere/generated/voice_events.pb.dart' as voice_events_pb;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_audio.dart';

/// Captures mic audio and drives per-utterance voice-agent turns. [start]
/// begins capture; [events] streams every turn's VoiceEvents; [stop] tears
/// capture + playback down. Mirrors Kotlin `VoiceAgentMicDriver`.
class VoiceAgentMicDriver {
  VoiceAgentMicDriver();

  static final _logger = SDKLogger('VoiceAgentMic');

  static const int _sampleRateHz = 16000;
  static const int _bytesPerSample = 2;

  /// Absolute floor for the adaptive speech threshold (normalized RMS).
  static const double _speechRmsThreshold = 0.015;

  /// Speech must exceed this multiple of the tracked ambient noise floor.
  static const double _speechFloorMultiplier = 2.2;

  /// Per-chunk rate at which the ambient floor creeps up toward louder ambient.
  static const double _noiseFloorRise = 0.05;

  /// Trailing silence that closes an utterance.
  static const int _endOfUtteranceSilenceMs = 800;

  /// Utterances with less accumulated speech than this are noise.
  static const int _minSpeechMs = 300;

  /// Hard cap so a noisy room cannot grow an unbounded buffer.
  static const int _maxUtteranceMs = 15000;

  /// Leading chunks kept so the utterance onset is not clipped.
  static const int _preRollChunks = 3;

  /// Piper's native rate; used when an audio frame omits sample_rate_hz.
  static const int _defaultTtsSampleRateHz = 22050;

  final AudioCaptureManager _capture = AudioCaptureManager();
  final AudioPlaybackManager _playback = AudioPlaybackManager();
  final StreamController<voice_events_pb.VoiceEvent> _out =
      StreamController<voice_events_pb.VoiceEvent>();

  StreamSubscription<Uint8List>? _micSub;
  bool _stopped = false;
  bool _processing = false;

  // Segmentation state.
  final List<Uint8List> _preRoll = <Uint8List>[];
  final BytesBuilder _utterance = BytesBuilder();
  bool _inSpeech = false;
  int _speechMs = 0;
  int _silenceMs = 0;
  double _noiseFloor = _speechRmsThreshold;

  /// VoiceEvents produced by each turn (userSaid, llm tokens, audio, pipeline
  /// state). The public eventStream yields from this.
  Stream<voice_events_pb.VoiceEvent> get events => _out.stream;

  /// Begin mic capture. On permission/capture failure the [events] stream is
  /// closed with an error so the collector can surface it.
  Future<void> start() async {
    // The voice agent runs a single full-duplex (.playAndRecord) session for the
    // whole turn-taking loop — the `record` plugin configures it on
    // startRecording (defaultToSpeaker by default). Playback must NOT switch the
    // session to the output-only `.playback` category, or it trips
    // AVAudioSessionErrorInsufficientPriority ('!pri', OSStatus 561017449) and
    // the reply is dropped. Mirrors the iOS Swift driver
    // (playback.managesAudioSession = false).
    _playback.managesAudioSession = false;
    final stream =
        await _capture.startRecording(sampleRate: _sampleRateHz, numChannels: 1);
    if (stream == null) {
      _out.addError(StateError(
          'Microphone capture unavailable (permission denied or busy)'));
      unawaited(_out.close());
      return;
    }
    _logger.info('Voice-agent mic capture started');
    _micSub = stream.listen(
      _onChunk,
      onError: (Object e, StackTrace st) => _logger.warning('Mic error: $e'),
      cancelOnError: false,
    );
  }

  /// Stop capture + playback and close the event stream.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _micSub?.cancel();
    _micSub = null;
    await _capture.stopRecording();
    await _playback.stop();
    if (!_out.isClosed) {
      await _out.close();
    }
    _logger.info('Voice-agent mic capture stopped');
  }

  void _onChunk(Uint8List chunk) {
    // Drop chunks while a turn is processing (turn-taking, no barge-in).
    if (_stopped || _processing || chunk.isEmpty) return;

    final chunkMs = chunk.length * 1000 ~/ (_sampleRateHz * _bytesPerSample);
    final level = _rms(chunk);
    // Adaptive endpointing: track the ambient floor — drop instantly to any
    // quieter level, creep up only while not in speech — and require a chunk
    // to rise clearly above that floor to count as speech.
    final speechThreshold =
        max(_speechRmsThreshold, _noiseFloor * _speechFloorMultiplier);
    final isSpeech = level >= speechThreshold;
    if (level < _noiseFloor) {
      _noiseFloor = level;
    } else if (!isSpeech) {
      _noiseFloor += (level - _noiseFloor) * _noiseFloorRise;
    }

    if (!_inSpeech) {
      _preRoll.add(chunk);
      while (_preRoll.length > _preRollChunks) {
        _preRoll.removeAt(0);
      }
      if (isSpeech) {
        _inSpeech = true;
        _speechMs = chunkMs;
        _silenceMs = 0;
        _utterance.clear();
        for (final pre in _preRoll) {
          _utterance.add(pre);
        }
        _preRoll.clear();
      }
      return;
    }

    _utterance.add(chunk);
    if (isSpeech) {
      _speechMs += chunkMs;
      _silenceMs = 0;
    } else {
      _silenceMs += chunkMs;
    }

    final utteranceMs =
        _utterance.length * 1000 ~/ (_sampleRateHz * _bytesPerSample);
    if (_silenceMs >= _endOfUtteranceSilenceMs || utteranceMs >= _maxUtteranceMs) {
      final audio = _utterance.toBytes();
      final hadSpeech = _speechMs >= _minSpeechMs;
      _resetSegmentation();
      if (hadSpeech) {
        unawaited(_processTurn(audio));
      } else {
        _logger.debug('Utterance discarded (${_speechMs}ms speech < '
            '${_minSpeechMs}ms)');
      }
    }
  }

  void _resetSegmentation() {
    _inSpeech = false;
    _speechMs = 0;
    _silenceMs = 0;
    _utterance.clear();
    _preRoll.clear();
  }

  Future<void> _processTurn(Uint8List audio) async {
    _processing = true;
    final ttsPcm = BytesBuilder();
    var ttsSampleRate = 0;
    var ttsEncoding = voice_events_pb.AudioEncoding.AUDIO_ENCODING_UNSPECIFIED;
    try {
      final request = voice_agent_pb.VoiceAgentTurnRequest(
        requestId: 'turn-${DateTime.now().microsecondsSinceEpoch}',
        audioData: audio,
        sampleRateHz: _sampleRateHz,
        channels: 1,
        encoding: voice_events_pb.AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
      );
      _logger.info('Submitting voice turn (${audio.length} bytes)');

      await for (final ev in DartBridge.voiceAgent.processTurnStream(request)) {
        if (!_out.isClosed) {
          _out.add(ev);
        }
        if (ev.hasAudio() && ev.audio.pcm.isNotEmpty) {
          ttsPcm.add(ev.audio.pcm is Uint8List
              ? ev.audio.pcm as Uint8List
              : Uint8List.fromList(ev.audio.pcm));
          if (ev.audio.sampleRateHz > 0) {
            ttsSampleRate = ev.audio.sampleRateHz;
          }
          if (ev.audio.encoding !=
              voice_events_pb.AudioEncoding.AUDIO_ENCODING_UNSPECIFIED) {
            ttsEncoding = ev.audio.encoding;
          }
        }
      }
    } catch (e) {
      _logger.warning('Voice turn failed: $e');
      if (!_out.isClosed) {
        _out.addError(e);
      }
    } finally {
      _processing = false;
      _resetSegmentation();
    }

    await _playTts(ttsPcm.toBytes(), ttsSampleRate, ttsEncoding);
  }

  // Play the turn's synthesized reply through the TTS sink. Runs before the
  // next mic chunk is processed (the _processing gate is cleared above but the
  // playback await keeps the turn logically open), so the mic stays gated
  // while the device speaks — no self-transcription.
  Future<void> _playTts(
    Uint8List pcm,
    int sampleRateHz,
    voice_events_pb.AudioEncoding encoding,
  ) async {
    if (pcm.isEmpty || _stopped) return;
    final sampleRate = sampleRateHz > 0 ? sampleRateHz : _defaultTtsSampleRateHz;
    // TTS backends emit f32 LE by default (AudioFrameEvent contract); only
    // convert as PCM16 when the frame explicitly says so.
    final wav =
        encoding == voice_events_pb.AudioEncoding.AUDIO_ENCODING_PCM_S16_LE
            ? DartBridgeAudio.int16ToWav(pcm, sampleRate)
            : DartBridgeAudio.float32ToWav(pcm, sampleRate);
    if (wav == null || wav.isEmpty) {
      _logger.warning('TTS audio conversion failed (${pcm.length} bytes, '
          '${sampleRate}Hz, $encoding)');
      return;
    }
    _processing = true; // keep mic gated while speaking
    try {
      await _playback.play(wav);
    } catch (e) {
      _logger.warning('Agent reply playback failed: $e');
    } finally {
      _processing = false;
      _resetSegmentation();
    }
  }

  double _rms(Uint8List chunk) {
    final samples = chunk.length ~/ _bytesPerSample;
    if (samples == 0) return 0.0;
    final data = ByteData.sublistView(chunk);
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      final sample = data.getInt16(i * _bytesPerSample, Endian.little).toDouble();
      sum += sample * sample;
    }
    return sqrt(sum / samples) / 32767.0;
  }
}
