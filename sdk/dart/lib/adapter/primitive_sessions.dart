// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../src/ffi/primitive_bindings.dart';
import 'types.dart';

class STTSession {
  final String modelId;
  final String modelPath;
  final ModelFormat format;

  Pointer<Void> _handle = nullptr;
  final RaPrimitiveBindings _b = RaPrimitiveBindings.instance();
  StreamController<TranscriptChunk>? _controller;
  NativeCallable<NativeChunkCb>? _cb;

  STTSession(this.modelId, this.modelPath,
             {this.format = ModelFormat.whisperKit}) {
    final spec = calloc<RaModelSpec>();
    final cfg = calloc<RaSessionConfig>();
    final idPtr = modelId.toNativeUtf8();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      spec.ref..modelId = idPtr..modelPath = pathPtr
        ..format = format.raw..preferredRuntime = 0;
      cfg.ref..nGpuLayers = -1..useMmap = 1;
      final out = calloc<Pointer<Void>>();
      final rc = _b.sttCreate(spec, cfg, out);
      if (rc != 0 || out.value == nullptr) {
        throw RunAnywhereException(RunAnywhereException.backendUnavailable,
                                    'ra_stt_create rc=$rc');
      }
      _handle = out.value;
      calloc.free(out);
    } finally {
      calloc.free(spec); calloc.free(cfg);
      calloc.free(idPtr); calloc.free(pathPtr);
    }
    _controller = StreamController<TranscriptChunk>.broadcast();
    _cb = NativeCallable<NativeChunkCb>.listener(
      (Pointer<RaTranscriptChunk> c, Pointer<Void> _) {
        if (c == nullptr) return;
        _controller!.add(TranscriptChunk(
          c.ref.text == nullptr ? '' : c.ref.text.toDartString(),
          c.ref.isPartial != 0,
          c.ref.confidence,
          c.ref.audioStartUs,
          c.ref.audioEndUs));
      });
    _b.sttSetCallback(_handle, _cb!.nativeFunction, nullptr);
  }

  Stream<TranscriptChunk> get transcripts => _controller!.stream;

  int feedAudio(Float32List samples, int sampleRateHz) {
    final buf = calloc<Float>(samples.length);
    for (var i = 0; i < samples.length; i++) { buf[i] = samples[i]; }
    try {
      return _b.sttFeedAudio(_handle, buf, samples.length, sampleRateHz);
    } finally { calloc.free(buf); }
  }

  int flush() => _b.sttFlush(_handle);

  void close() {
    if (_handle != nullptr) { _b.sttDestroy(_handle); _handle = nullptr; }
    _cb?.close(); _cb = null;
    _controller?.close();
  }
}

class TTSSession {
  final String modelId;
  final String modelPath;
  final ModelFormat format;
  Pointer<Void> _handle = nullptr;
  final RaPrimitiveBindings _b = RaPrimitiveBindings.instance();

  TTSSession(this.modelId, this.modelPath,
             {this.format = ModelFormat.onnx}) {
    final spec = calloc<RaModelSpec>();
    final cfg = calloc<RaSessionConfig>();
    final idPtr = modelId.toNativeUtf8();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      spec.ref..modelId = idPtr..modelPath = pathPtr
        ..format = format.raw..preferredRuntime = 0;
      cfg.ref..nGpuLayers = -1..useMmap = 1;
      final out = calloc<Pointer<Void>>();
      final rc = _b.ttsCreate(spec, cfg, out);
      if (rc != 0 || out.value == nullptr) {
        throw RunAnywhereException(RunAnywhereException.backendUnavailable,
                                    'ra_tts_create rc=$rc');
      }
      _handle = out.value;
      calloc.free(out);
    } finally {
      calloc.free(spec); calloc.free(cfg);
      calloc.free(idPtr); calloc.free(pathPtr);
    }
  }

  ({Float32List pcm, int sampleRateHz}) synthesize(String text) {
    var capacity = 240000;
    while (capacity <= 4000000) {
      final buf = calloc<Float>(capacity);
      final written = calloc<Int32>();
      final sr = calloc<Int32>();
      final textPtr = text.toNativeUtf8();
      try {
        final rc = _b.ttsSynthesize(_handle, textPtr, buf, capacity, written, sr);
        if (rc == 0) {
          final n = written.value;
          final out = Float32List(n);
          for (var i = 0; i < n; i++) out[i] = buf[i];
          return (pcm: out, sampleRateHz: sr.value);
        }
        if (rc != -8 /* OUT_OF_MEMORY */) {
          throw RunAnywhereException(rc, 'ra_tts_synthesize');
        }
      } finally {
        calloc.free(buf); calloc.free(written); calloc.free(sr);
        calloc.free(textPtr);
      }
      capacity *= 2;
    }
    throw RunAnywhereException(-1, 'TTS output >4M samples');
  }

  int cancel() => _b.ttsCancel(_handle);
  void close() {
    if (_handle != nullptr) { _b.ttsDestroy(_handle); _handle = nullptr; }
  }
}

class VADSession {
  final String modelId;
  final String modelPath;
  final ModelFormat format;
  Pointer<Void> _handle = nullptr;
  final RaPrimitiveBindings _b = RaPrimitiveBindings.instance();
  StreamController<VADEvent>? _controller;
  NativeCallable<NativeVadCb>? _cb;

  VADSession(this.modelId, this.modelPath,
             {this.format = ModelFormat.onnx}) {
    final spec = calloc<RaModelSpec>();
    final cfg = calloc<RaSessionConfig>();
    final idPtr = modelId.toNativeUtf8();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      spec.ref..modelId = idPtr..modelPath = pathPtr
        ..format = format.raw..preferredRuntime = 0;
      cfg.ref..nGpuLayers = -1..useMmap = 1;
      final out = calloc<Pointer<Void>>();
      final rc = _b.vadCreate(spec, cfg, out);
      if (rc != 0 || out.value == nullptr) {
        throw RunAnywhereException(RunAnywhereException.backendUnavailable,
                                    'ra_vad_create rc=$rc');
      }
      _handle = out.value;
      calloc.free(out);
    } finally {
      calloc.free(spec); calloc.free(cfg);
      calloc.free(idPtr); calloc.free(pathPtr);
    }
    _controller = StreamController<VADEvent>.broadcast();
    _cb = NativeCallable<NativeVadCb>.listener(
      (Pointer<RaVadEvent> e, Pointer<Void> _) {
        if (e == nullptr) return;
        _controller!.add(VADEvent.fromRaw(e.ref.type, e.ref.frameOffsetUs, e.ref.energy));
      });
    _b.vadSetCallback(_handle, _cb!.nativeFunction, nullptr);
  }

  Stream<VADEvent> get events => _controller!.stream;

  int feedAudio(Float32List samples, int sampleRateHz) {
    final buf = calloc<Float>(samples.length);
    for (var i = 0; i < samples.length; i++) { buf[i] = samples[i]; }
    try {
      return _b.vadFeedAudio(_handle, buf, samples.length, sampleRateHz);
    } finally { calloc.free(buf); }
  }

  void close() {
    if (_handle != nullptr) { _b.vadDestroy(_handle); _handle = nullptr; }
    _cb?.close(); _cb = null;
    _controller?.close();
  }
}

class EmbedSession {
  final String modelId;
  final String modelPath;
  final ModelFormat format;
  Pointer<Void> _handle = nullptr;
  final RaPrimitiveBindings _b = RaPrimitiveBindings.instance();
  late final int dims;

  EmbedSession(this.modelId, this.modelPath,
               {this.format = ModelFormat.gguf}) {
    final spec = calloc<RaModelSpec>();
    final cfg = calloc<RaSessionConfig>();
    final idPtr = modelId.toNativeUtf8();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      spec.ref..modelId = idPtr..modelPath = pathPtr
        ..format = format.raw..preferredRuntime = 0;
      cfg.ref..nGpuLayers = -1..useMmap = 1;
      final out = calloc<Pointer<Void>>();
      final rc = _b.embedCreate(spec, cfg, out);
      if (rc != 0 || out.value == nullptr) {
        throw RunAnywhereException(RunAnywhereException.backendUnavailable,
                                    'ra_embed_create rc=$rc');
      }
      _handle = out.value;
      calloc.free(out);
    } finally {
      calloc.free(spec); calloc.free(cfg);
      calloc.free(idPtr); calloc.free(pathPtr);
    }
    dims = _b.embedDims(_handle);
  }

  Float32List embed(String text) {
    final buf = calloc<Float>(dims);
    final textPtr = text.toNativeUtf8();
    try {
      final rc = _b.embedText(_handle, textPtr, buf, dims);
      if (rc != 0) throw RunAnywhereException(rc, 'ra_embed_text');
      final out = Float32List(dims);
      for (var i = 0; i < dims; i++) out[i] = buf[i];
      return out;
    } finally {
      calloc.free(buf); calloc.free(textPtr);
    }
  }

  void close() {
    if (_handle != nullptr) { _b.embedDestroy(_handle); _handle = nullptr; }
  }
}
