import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/generated/vad_options.pb.dart' as vad_pb;
import 'package:runanywhere/generated/voice_events.pb.dart' as pb;

const int perfBenchMagic = 0x42504152; // 'RAPB'
const int cancelParityMagic = 0x43504152; // 'CPAR'

class PerfBenchFixtureResult {
  PerfBenchFixtureResult({
    required this.count,
    required this.nonEmpty,
    required this.deltas,
  });

  final int count;
  final int nonEmpty;
  final List<int> deltas;
}

class CancelParityFixtureResult {
  CancelParityFixtureResult({
    required this.total,
    required this.interruptOrdinal,
    required this.postCancelCount,
  });

  final int total;
  final int? interruptOrdinal;
  final int postCancelCount;
}

List<pb.VoiceEvent> voiceParityEvents() => <pb.VoiceEvent>[
      pb.VoiceEvent(
        vad: pb.VADEvent(
          type: vad_pb.VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
          isSpeech: true,
        ),
      ),
      pb.VoiceEvent(
        vad: pb.VADEvent(
          type: vad_pb.VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
          isSpeech: false,
        ),
      ),
      pb.VoiceEvent(
        userSaid: pb.UserSaidEvent(
          text: 'what is the weather today',
          isFinal: true,
        ),
      ),
      pb.VoiceEvent(
        assistantToken: pb.AssistantTokenEvent(
          text: 'the weather is sunny and 72 degrees',
          isFinal: true,
          kind: pb.TokenKind.TOKEN_KIND_ANSWER,
        ),
      ),
      pb.VoiceEvent(
        audio: pb.AudioFrameEvent(
          pcm: Uint8List(16),
          sampleRateHz: 24000,
          channels: 1,
          encoding: pb.AudioEncoding.AUDIO_ENCODING_PCM_F32_LE,
        ),
      ),
      pb.VoiceEvent(
        metrics: pb.MetricsEvent(
          tokensGenerated: Int64.ZERO,
          isOverBudget: false,
        ),
      ),
      pb.VoiceEvent(
        error: pb.ErrorEvent(
          code: -259,
          component: 'pipeline',
        ),
      ),
      pb.VoiceEvent(
        state: pb.StateChangeEvent(
          previous: pb.PipelineState.PIPELINE_STATE_IDLE,
          current: pb.PipelineState.PIPELINE_STATE_LISTENING,
        ),
      ),
    ];

List<String> expectedVoiceParityLines() => <String>[
      'vad:type=3,is_speech=true',
      'vad:type=3,is_speech=false',
      'user_said:text=what is the weather today,is_final=true',
      'assistant_token:text=the weather is sunny and 72 degrees,is_final=true,kind=1',
      'audio:bytes=16,sample_rate=24000,channels=1,encoding=1',
      'metrics:tokens_generated=0,is_over_budget=false',
      'error:code=-259,component=pipeline',
      'state:previous=1,current=2',
    ];

String formatVoiceEvent(pb.VoiceEvent event) {
  if (event.hasUserSaid()) {
    final userSaid = event.userSaid;
    return 'user_said:text=${userSaid.text},is_final=${userSaid.isFinal}';
  }
  if (event.hasAssistantToken()) {
    final token = event.assistantToken;
    return 'assistant_token:text=${token.text},is_final=${token.isFinal},'
        'kind=${token.kind.value}';
  }
  if (event.hasAudio()) {
    final audio = event.audio;
    return 'audio:bytes=${audio.pcm.length},'
        'sample_rate=${audio.sampleRateHz},channels=${audio.channels},'
        'encoding=${audio.encoding.value}';
  }
  if (event.hasVad()) {
    return 'vad:type=${event.vad.type.value},is_speech=${event.vad.isSpeech}';
  }
  if (event.hasState()) {
    return 'state:previous=${event.state.previous.value},'
        'current=${event.state.current.value}';
  }
  if (event.hasError()) {
    return 'error:code=${event.error.code},component=${event.error.component}';
  }
  if (event.hasMetrics()) {
    final metrics = event.metrics;
    return 'metrics:tokens_generated=${metrics.tokensGenerated.toInt()},'
        'is_over_budget=${metrics.isOverBudget}';
  }
  if (event.hasInterrupted()) {
    return 'interrupted:reason=${event.interrupted.reason.value}';
  }
  return 'unknown_arm';
}

Uint8List encodeVoiceEventFrames(
  List<pb.VoiceEvent> events, {
  required int magic,
}) {
  final frames = events.map((event) => event.writeToBuffer()).toList();
  final byteCount =
      frames.fold<int>(8, (total, frame) => total + 4 + frame.length);
  final bytes = Uint8List(byteCount);
  final view = ByteData.sublistView(bytes);

  view.setUint32(0, magic, Endian.little);
  view.setUint32(4, frames.length, Endian.little);

  var cursor = 8;
  for (final frame in frames) {
    view.setUint32(cursor, frame.length, Endian.little);
    cursor += 4;
    bytes.setRange(cursor, cursor + frame.length, frame);
    cursor += frame.length;
  }

  return bytes;
}

List<pb.VoiceEvent> decodeVoiceEventFrames(
  Uint8List bytes, {
  required int magic,
}) {
  if (bytes.length < 8) {
    throw StateError('streaming fixture input too short: ${bytes.length}');
  }

  final header = ByteData.sublistView(bytes, 0, 8);
  final readMagic = header.getUint32(0, Endian.little);
  if (readMagic != magic) {
    throw StateError(
      'bad streaming fixture magic: 0x${readMagic.toRadixString(16)}',
    );
  }

  final count = header.getUint32(4, Endian.little);
  final events = <pb.VoiceEvent>[];
  var cursor = 8;

  for (var index = 0; index < count; index++) {
    if (cursor + 4 > bytes.length) {
      throw StateError('truncated streaming fixture frame length at $index');
    }
    final length = ByteData.sublistView(bytes, cursor, cursor + 4).getUint32(
      0,
      Endian.little,
    );
    cursor += 4;

    if (cursor + length > bytes.length) {
      throw StateError('truncated streaming fixture frame payload at $index');
    }

    final frame = Uint8List.sublistView(bytes, cursor, cursor + length);
    events.add(pb.VoiceEvent.fromBuffer(frame));
    cursor += length;
  }

  return events;
}

Uint8List buildPerfBenchFixture() {
  final events = List<pb.VoiceEvent>.generate(
    5,
    (index) => pb.VoiceEvent(
      metrics: pb.MetricsEvent(
        createdAtNs: Int64((index + 1) * 1000),
        tokensGenerated: Int64(index + 1),
      ),
    ),
  );
  return encodeVoiceEventFrames(events, magic: perfBenchMagic);
}

PerfBenchFixtureResult decodePerfBenchFixture(
  Uint8List bytes, {
  required List<int> receivedAtNs,
}) {
  final events = decodeVoiceEventFrames(bytes, magic: perfBenchMagic);
  if (receivedAtNs.length < events.length) {
    throw ArgumentError.value(
      receivedAtNs.length,
      'receivedAtNs',
      'must have at least one timestamp per frame',
    );
  }

  final deltas = <int>[];
  var nonEmpty = 0;

  for (var index = 0; index < events.length; index++) {
    final event = events[index];
    var delta = 0;
    if (event.hasMetrics()) {
      final producerNs = event.metrics.createdAtNs.toInt();
      if (producerNs > 0) {
        delta = receivedAtNs[index] - producerNs;
        if (delta > 0) {
          nonEmpty++;
        }
      }
    }
    deltas.add(delta);
  }

  return PerfBenchFixtureResult(
    count: events.length,
    nonEmpty: nonEmpty,
    deltas: deltas,
  );
}

int? p50NonZeroDeltas(List<int> deltas) {
  final nonZero = deltas.where((delta) => delta > 0).toList()..sort();
  if (nonZero.isEmpty) {
    return null;
  }
  return nonZero[nonZero.length ~/ 2];
}

Uint8List buildCancelParityFixture() {
  final events = <pb.VoiceEvent>[
    pb.VoiceEvent(
      state: pb.StateChangeEvent(
        previous: pb.PipelineState.PIPELINE_STATE_LISTENING,
        current: pb.PipelineState.PIPELINE_STATE_GENERATING_RESPONSE,
      ),
    ),
    pb.VoiceEvent(
      assistantToken: pb.AssistantTokenEvent(
        text: 'partial',
        kind: pb.TokenKind.TOKEN_KIND_ANSWER,
      ),
    ),
    pb.VoiceEvent(
      interrupted: pb.InterruptedEvent(
        reason: pb.InterruptReason.INTERRUPT_REASON_USER_BARGE_IN,
        detail: 'barge-in',
      ),
    ),
  ];

  return encodeVoiceEventFrames(events, magic: cancelParityMagic);
}

CancelParityFixtureResult decodeCancelParityFixture(Uint8List bytes) {
  final events = decodeVoiceEventFrames(bytes, magic: cancelParityMagic);
  int? interruptOrdinal;
  var postCancelCount = 0;

  for (var index = 0; index < events.length; index++) {
    if (events[index].hasInterrupted() && interruptOrdinal == null) {
      interruptOrdinal = index;
    } else if (interruptOrdinal != null) {
      postCancelCount++;
    }
  }

  return CancelParityFixtureResult(
    total: events.length,
    interruptOrdinal: interruptOrdinal,
    postCancelCount: postCancelCount,
  );
}
