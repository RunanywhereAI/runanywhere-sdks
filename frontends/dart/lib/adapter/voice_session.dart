// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../src/ffi/bindings.dart';
import 'runanywhere.dart';
import 'voice_event.dart';

/// Bridges into the C++ core via `libracommons_core` (shared lib produced by
/// `cmake --build <dir> --target racommons_core`). The binding is created
/// lazily the first time a VoiceSession actually runs, so Dart callers can
/// import this library and construct configs even in environments where the
/// native lib is absent (tests, docs).
class VoiceSession {
  final SolutionConfig _config;

  // Populated lazily inside `run()`.
  Pointer<Void>?   _handle;
  Completer<void>? _finished;
  StreamController<VoiceEvent>? _events;

  VoiceSession._(this._config);

  factory VoiceSession.create(SolutionConfig config) =>
      VoiceSession._(config);

  /// Emits events until the pipeline ends, cancels, or errors.
  Stream<VoiceEvent> run() {
    _events = StreamController<VoiceEvent>(
      onCancel: stop,
    );
    _finished = Completer<void>();

    RaCoreBindings bindings;
    try {
      bindings = RaCoreBindings.open();
    } catch (e) {
      _events!.add(VoiceError(-6, 'libracommons_core not loadable: $e'));
      _events!.close();
      return _events!.stream;
    }

    try {
      _startVoiceAgent(bindings);
    } catch (e) {
      _events!.add(VoiceError(-99, 'pipeline start failed: $e'));
      _events!.close();
    }
    return _events!.stream;
  }

  void _startVoiceAgent(RaCoreBindings b) {
    if (_config is! VoiceAgentSolution) {
      throw StateError('only VoiceAgent solutions wired through ra_pipeline yet');
    }
    final va = (_config as VoiceAgentSolution).config;

    final cfgPtr = calloc<RaVoiceAgentConfig>();
    final llm  = va.llm.toNativeUtf8();
    final stt  = va.stt.toNativeUtf8();
    final tts  = va.tts.toNativeUtf8();
    final vad  = va.vad.toNativeUtf8();
    final sp   = va.systemPrompt.toNativeUtf8();
    cfgPtr.ref
      ..llmModelId        = llm
      ..sttModelId        = stt
      ..ttsModelId        = tts
      ..vadModelId        = vad
      ..sampleRateHz      = va.sampleRateHz
      ..chunkMs           = va.chunkMs
      ..audioSource       = raAudioSourceMicrophone
      ..enableBargeIn     = va.enableBargeIn ? 1 : 0
      ..bargeInThresholdMs = 200
      ..systemPrompt      = sp
      ..maxContextTokens  = va.maxContextTokens
      ..temperature       = va.temperature
      ..emitPartials      = va.emitPartials ? 1 : 0
      ..emitThoughts      = va.emitThoughts ? 1 : 0;

    final outPtr = calloc<Pointer<Void>>();
    final rc = b.createVoiceAgent(cfgPtr, outPtr);

    // Free transient strings + config struct right after the call —
    // ra_pipeline_create_voice_agent copies everything it needs.
    calloc.free(llm);
    calloc.free(stt);
    calloc.free(tts);
    calloc.free(vad);
    calloc.free(sp);
    calloc.free(cfgPtr);

    if (rc != raOk) {
      calloc.free(outPtr);
      _events!.add(VoiceError(rc, 'ra_pipeline_create_voice_agent failed'));
      _events!.close();
      return;
    }

    _handle = outPtr.value;
    calloc.free(outPtr);

    // Skipping event callback wiring for now: the Pointer<NativeFunction>
    // registration path requires a static top-level function, and the Dart
    // isolate must receive events via SendPort or similar. Leaving the
    // callback unregistered surfaces the pipeline's completion/error via
    // the completion callback, which is what downstream tests exercise.
    _events!.add(VoiceError(raErrBackendUnavailable,
        'event streaming from native pipeline is not wired in this build; '
        'see frontends/dart/CONTRIBUTING.md'));

    final runRc = b.run(_handle!);
    if (runRc != raOk) {
      _events!.add(VoiceError(runRc, 'ra_pipeline_run failed'));
    }
    _events!.close();
  }

  void stop() {
    if (_handle != null) {
      try {
        final b = RaCoreBindings.open();
        b.cancel(_handle!);
        b.destroy(_handle!);
      } catch (_) {}
      _handle = null;
    }
  }

  /// Feeds externally captured PCM audio to the pipeline.
  void feedAudio(Float32List samples, int sampleRateHz) {
    if (_handle == null) return;
    final b = RaCoreBindings.open();
    final buf = calloc<Float>(samples.length);
    for (var i = 0; i < samples.length; i++) {
      buf[i] = samples[i];
    }
    b.feedAudio(_handle!, buf, samples.length, sampleRateHz);
    calloc.free(buf);
  }

  SolutionConfig get config => _config;
}
