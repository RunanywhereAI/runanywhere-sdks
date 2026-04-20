// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

enum ModelFormat {
  unknown(0),
  gguf(1),
  onnx(2),
  coreml(3),
  mlxSafetensors(4),
  executorchPte(5),
  whisperKit(6),
  openvinoIr(7);

  final int raw;
  const ModelFormat(this.raw);
}

enum Environment {
  development(0),
  staging(1),
  production(2);

  final int raw;
  const Environment(this.raw);

  static Environment of(int raw) => Environment.values.firstWhere(
        (e) => e.raw == raw,
        orElse: () => Environment.production,
      );
}

enum LogLevel {
  trace(0), debug(1), info(2), warn(3), error(4), fatal(5);
  final int raw;
  const LogLevel(this.raw);
}

enum LLMTokenKind { answer, thought, toolCall }

class LLMToken {
  final String text;
  final LLMTokenKind kind;
  final bool isFinal;
  const LLMToken(this.text, this.kind, this.isFinal);

  factory LLMToken.fromKindRaw(String text, int raw, bool isFinal) {
    final k = switch (raw) {
      2 => LLMTokenKind.thought,
      3 => LLMTokenKind.toolCall,
      _ => LLMTokenKind.answer,
    };
    return LLMToken(text, k, isFinal);
  }
}

class TranscriptChunk {
  final String text;
  final bool isPartial;
  final double confidence;
  final int audioStartUs;
  final int audioEndUs;
  const TranscriptChunk(this.text, this.isPartial, this.confidence,
                          this.audioStartUs, this.audioEndUs);
}

enum VADKind { unknown, voiceStart, voiceEnd, bargeIn, silence }

class VADEvent {
  final VADKind kind;
  final int frameOffsetUs;
  final double energy;
  const VADEvent(this.kind, this.frameOffsetUs, this.energy);

  factory VADEvent.fromRaw(int raw, int offset, double energy) =>
      VADEvent(switch (raw) {
        1 => VADKind.voiceStart,
        2 => VADKind.voiceEnd,
        3 => VADKind.bargeIn,
        4 => VADKind.silence,
        _ => VADKind.unknown,
      }, offset, energy);
}

class RunAnywhereException implements Exception {
  static const int backendUnavailable = -6;
  static const int cancelled           = -1;

  final int code;
  final String message;
  const RunAnywhereException(this.code, this.message);

  @override
  String toString() => 'RunAnywhereException[$code]: $message';
}
