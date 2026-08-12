// SPDX-License-Identifier: Apache-2.0
//
// voice_agent_mic_driver.dart — audio ingress for the Flutter voice agent.
//
// The C ABI owns NO microphone (rac_voice_agent.h "Audio-Ingress Contract"):
// the platform SDK must capture mic audio and push raw frames into the C core
// via `rac_voice_agent_feed_audio_proto`, or the session is dead air.
//
// Mirrors Kotlin/Swift `VoiceAgentMicDriver`: capture 16 kHz mono PCM16 via
// [AudioCaptureManager], feed every chunk to commons (which owns energy VAD,
// hangover, pre-roll, and the STT → LLM → TTS turn), forward VoiceEvents from
// [VoiceAgentStreamAdapter], and play the synthesized WAV reply returned
// inline. NO SDK-side RMS / segmenter / endpointing.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:runanywhere/adapters/voice_agent_stream_adapter.dart';
import 'package:runanywhere/features/stt/services/audio_capture_manager.dart';
import 'package:runanywhere/features/tts/services/audio_playback_manager.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart' as model_pb;
import 'package:runanywhere/generated/ra_defaults_pool.dart';
import 'package:runanywhere/generated/ra_result_codes.dart';
import 'package:runanywhere/generated/voice_agent_service.pb.dart'
    as voice_agent_pb;
import 'package:runanywhere/generated/voice_events.pb.dart' as voice_events_pb;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// Captures mic audio and feeds raw frames to the in-core voice agent. [start]
/// begins capture; [events] streams every turn's VoiceEvents; [stop] tears
/// capture + playback down. Mirrors Kotlin/Swift `VoiceAgentMicDriver`.
class VoiceAgentMicDriver {
  VoiceAgentMicDriver();

  static final _logger = SDKLogger('VoiceAgentMic');

  static const int _sampleRateHz = RADefaultsAudioCapture.micSampleRateHz;
  static const int _channelCapacity =
      RADefaultsAudioCapture.micChannelCapacity;
  static const Duration _feedIdleSleep = Duration(milliseconds: 20);

  final AudioCaptureManager _capture = AudioCaptureManager();
  final AudioPlaybackManager _playback = AudioPlaybackManager();
  final StreamController<voice_events_pb.VoiceEvent> _out =
      StreamController<voice_events_pb.VoiceEvent>();
  final Queue<Uint8List> _queue = Queue<Uint8List>();

  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<voice_events_pb.VoiceEvent>? _eventSub;
  bool _stopped = false;
  bool _feedRunning = false;

  /// VoiceEvents produced by each turn (userSaid, llm tokens, audio, pipeline
  /// state). The public eventStream yields from this. Sourced from the
  /// commons proto callback via [VoiceAgentStreamAdapter] — not from a local
  /// segmenter driving `process_turn_proto`.
  Stream<voice_events_pb.VoiceEvent> get events => _out.stream;

  /// Begin mic capture + feed loop. On permission/capture failure the [events]
  /// stream is closed with an error so the collector can surface it.
  Future<void> start() async {
    // The voice agent runs a single full-duplex (.playAndRecord) session for the
    // whole turn-taking loop — the `record` plugin configures it on
    // startRecording (defaultToSpeaker by default). Playback must NOT switch the
    // session to the output-only `.playback` category, or it trips
    // AVAudioSessionErrorInsufficientPriority ('!pri', OSStatus 561017449) and
    // the reply is dropped. Mirrors the iOS Swift driver
    // (playback.managesAudioSession = false).
    _playback.managesAudioSession = false;
    _stopped = false;

    // Attach the proto callback BEFORE capture so events from the first turn
    // are not dropped (mirrors Swift VoiceSession.events).
    final handle = await DartBridge.voiceAgent.getHandle();
    _eventSub = VoiceAgentStreamAdapter(handle).stream().listen(
      (event) {
        if (!_out.isClosed) _out.add(event);
      },
      onError: (Object e, StackTrace st) {
        if (!_out.isClosed) _out.addError(e, st);
      },
      cancelOnError: false,
    );

    final stream =
        await _capture.startRecording(sampleRate: _sampleRateHz, numChannels: 1);
    if (stream == null) {
      await _eventSub?.cancel();
      _eventSub = null;
      _out.addError(StateError(
          'Microphone capture unavailable (permission denied or busy)'));
      unawaited(_out.close());
      return;
    }
    _logger.info('Voice-agent mic capture started');
    _micSub = stream.listen(
      _enqueueChunk,
      onError: (Object e, StackTrace st) => _logger.warning('Mic error: $e'),
      cancelOnError: false,
    );
    unawaited(_feedLoop());
  }

  /// Stop capture + playback and close the event stream.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _micSub?.cancel();
    _micSub = null;
    await _capture.stopRecording();
    await _playback.stop();
    await _eventSub?.cancel();
    _eventSub = null;
    _queue.clear();
    // Wait for the feed loop to observe _stopped before closing events.
    while (_feedRunning) {
      await Future<void>.delayed(_feedIdleSleep);
    }
    if (!_out.isClosed) {
      await _out.close();
    }
    _logger.info('Voice-agent mic capture stopped');
  }

  void _enqueueChunk(Uint8List chunk) {
    if (_stopped || chunk.isEmpty) return;
    _queue.add(chunk);
    while (_queue.length > _channelCapacity) {
      _queue.removeFirst();
    }
  }

  List<Uint8List> _drainChunks() {
    if (_queue.isEmpty) return const <Uint8List>[];
    final drained = _queue.toList(growable: false);
    _queue.clear();
    return drained;
  }

  /// Drains captured frames and feeds them to commons. The core blocks the
  /// feed call for the duration of a turn when an utterance closes and returns
  /// the synthesized reply inline as WAV. Per-stage VoiceEvents fan out through
  /// the handle callback (forwarded by [_eventSub]).
  Future<void> _feedLoop() async {
    _feedRunning = true;
    try {
      while (!_stopped) {
        final chunks = _drainChunks();
        if (chunks.isEmpty) {
          await Future<void>.delayed(_feedIdleSleep);
          continue;
        }

        for (final chunk in chunks) {
          if (_stopped) return;

          try {
            final frame = voice_agent_pb.VoiceAgentAudioFrame(
              audioData: chunk,
              sampleRateHz: _sampleRateHz,
              channels: 1,
              encoding: model_pb.AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
              isFinal: false,
            );
            final outcome = await DartBridge.voiceAgent.feedAudioProto(frame);
            if (_stopped) return;

            if (outcome.status == RacResultCodes.errorNotInitialized) {
              throw StateError('Voice agent is no longer initialized');
            }
            if (outcome.status != RAC_SUCCESS) {
              _logger.warning('Voice feed failed: rc=${outcome.status}');
              _queue.clear();
              continue;
            }

            final reply = outcome.result?.synthesizedAudio;
            if (reply != null && reply.isNotEmpty) {
              _logger.info('Playing agent reply (${reply.length} WAV bytes)');
              // Frames captured while the turn was computed predate playout —
              // drop them so the reply onset cannot seed the echo estimate
              // (mirrors Swift/Kotlin).
              _queue.clear();
              await _playReply(
                reply is Uint8List ? reply : Uint8List.fromList(reply),
              );
            }
          } catch (e) {
            _logger.warning('Voice feed failed: $e');
            _queue.clear();
            if (!_out.isClosed) {
              _out.addError(e);
            }
          }
        }
      }
    } finally {
      _feedRunning = false;
    }
  }

  Future<void> _playReply(Uint8List wav) async {
    if (wav.isEmpty || _stopped) return;
    try {
      await _playback.play(wav);
    } catch (e) {
      _logger.warning('Agent reply playback failed: $e');
    }
  }
}
