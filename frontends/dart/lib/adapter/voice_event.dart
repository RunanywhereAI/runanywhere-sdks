// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:typed_data';

sealed class VoiceEvent {
  const VoiceEvent();
}

class UserSaid extends VoiceEvent {
  final String text;
  final bool   isFinal;
  const UserSaid(this.text, {required this.isFinal});
}

class AssistantToken extends VoiceEvent {
  final String    text;
  final TokenKind kind;
  final bool      isFinal;
  const AssistantToken(
    this.text, {
    this.kind = TokenKind.answer,
    required this.isFinal,
  });
}

class AudioFrame extends VoiceEvent {
  final Uint8List pcm;
  final int       sampleRateHz;
  const AudioFrame(this.pcm, this.sampleRateHz);
}

class Interrupted extends VoiceEvent {
  final String reason;
  const Interrupted(this.reason);
}

class VoiceError extends VoiceEvent {
  final int    code;
  final String message;
  const VoiceError(this.code, this.message);
}

enum TokenKind { answer, thought, toolCall }
