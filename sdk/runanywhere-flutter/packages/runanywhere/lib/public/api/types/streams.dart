// SPDX-License-Identifier: Apache-2.0
//
// Live push-stream handles returned by `stt.openStream` and `vad.openStream`.
// Format is established once at open time; every frame pushed afterward
// carries raw PCM in that format. Mirrors Swift's `SttStream`/`VadStream`
// and Web's `SttStream`/`VadStream`.

// prefer_initializing_formals cannot apply: the fields are private and set via
// named parameters, and Dart forbids named initializing formals that start with
// an underscore, so the lint's suggested `this._field` form is illegal here.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';

/// Live transcription stream: push frames, then flush/finish/close.
class SttStream {
  /// Internal — build through `stt.openStream`.
  SttStream({
    required Stream<TranscriptionEvent> events,
    required void Function(AudioFrame frame) pushHandler,
    required void Function() flushHandler,
    required void Function() finishHandler,
    required Future<void> Function() closeHandler,
  }) : _events = events,
       _pushHandler = pushHandler,
       _flushHandler = flushHandler,
       _finishHandler = finishHandler,
       _closeHandler = closeHandler;

  final Stream<TranscriptionEvent> _events;
  final void Function(AudioFrame frame) _pushHandler;
  final void Function() _flushHandler;
  final void Function() _finishHandler;
  final Future<void> Function() _closeHandler;
  bool _closed = false;

  /// Transcription progress. Ends in `TranscriptionFinal`/`completed`,
  /// `TranscriptionFailed`, or `TranscriptionCancelled` — never fabricated.
  Stream<TranscriptionEvent> get events => _events;

  /// Push one PCM frame in the stream's established format.
  void pushFrame(AudioFrame frame) => _pushHandler(frame);

  /// Request the native session flush any buffered partial. A no-op where
  /// the backend has no incremental buffer to flush.
  void flush() => _flushHandler();

  /// Signal end of input; the session settles its final transcript.
  void finish() => _finishHandler();

  /// Release the stream. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeHandler();
  }
}

/// Live VAD stream: push frames, then flush/finish/close.
class VadStream {
  /// Internal — build through `vad.openStream`.
  VadStream({
    required Stream<VadEvent> events,
    required void Function(AudioFrame frame) pushHandler,
    required void Function() flushHandler,
    required void Function() finishHandler,
    required Future<void> Function() closeHandler,
  }) : _events = events,
       _pushHandler = pushHandler,
       _flushHandler = flushHandler,
       _finishHandler = finishHandler,
       _closeHandler = closeHandler;

  final Stream<VadEvent> _events;
  final void Function(AudioFrame frame) _pushHandler;
  final void Function() _flushHandler;
  final void Function() _finishHandler;
  final Future<void> Function() _closeHandler;
  bool _closed = false;

  /// Speech-activity transitions. Ends in `VadCompleted` or `VadFailed`.
  Stream<VadEvent> get events => _events;

  /// Push one PCM frame in the stream's established format.
  void pushFrame(AudioFrame frame) => _pushHandler(frame);

  /// No-op: every pushed frame is processed as it arrives.
  void flush() => _flushHandler();

  /// Signal end of input.
  void finish() => _finishHandler();

  /// Release the stream. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeHandler();
  }
}
