// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../src/ffi/primitive_bindings.dart';
import 'types.dart';

/// Direct LLM text-generation session. Wraps ra_llm_* C ABI.
class LLMSession {
  final String modelId;
  final String modelPath;
  final ModelFormat format;

  Pointer<Void> _handle = nullptr;
  final RaPrimitiveBindings _b = RaPrimitiveBindings.instance();
  StreamController<LLMToken>? _controller;
  NativeCallable<NativeTokenCb>? _tokenCb;
  NativeCallable<NativeErrorCb>? _errorCb;

  LLMSession(this.modelId, this.modelPath,
             {this.format = ModelFormat.gguf}) {
    final spec = calloc<RaModelSpec>();
    final cfg = calloc<RaSessionConfig>();
    final idPtr = modelId.toNativeUtf8();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      spec.ref.modelId = idPtr;
      spec.ref.modelPath = pathPtr;
      spec.ref.format = format.raw;
      spec.ref.preferredRuntime = 0;
      cfg.ref.nGpuLayers = -1;
      cfg.ref.nThreads = 0;
      cfg.ref.contextSize = 0;
      cfg.ref.useMmap = 1;
      cfg.ref.useMlock = 0;

      final outPtr = calloc<Pointer<Void>>();
      final rc = _b.llmCreate(spec, cfg, outPtr);
      if (rc != 0 || outPtr.value == nullptr) {
        throw RunAnywhereException(RunAnywhereException.backendUnavailable,
            'ra_llm_create failed rc=$rc');
      }
      _handle = outPtr.value;
      calloc.free(outPtr);
    } finally {
      calloc.free(spec); calloc.free(cfg);
      calloc.free(idPtr); calloc.free(pathPtr);
    }
  }

  Stream<LLMToken> generate(String prompt, {int conversationId = -1}) {
    _controller?.close();
    _controller = StreamController<LLMToken>();
    _setupCallbacks(_controller!);
    final promptPtr = prompt.toNativeUtf8();
    final p = calloc<RaPrompt>();
    try {
      p.ref.text = promptPtr;
      p.ref.conversationId = conversationId;
      final rc = _b.llmGenerate(_handle, p,
          _tokenCb!.nativeFunction, _errorCb!.nativeFunction, nullptr);
      if (rc != 0) {
        _controller!.addError(RunAnywhereException(rc, 'ra_llm_generate'));
        _controller!.close();
      }
    } finally {
      calloc.free(p); calloc.free(promptPtr);
    }
    return _controller!.stream;
  }

  Stream<LLMToken> generateFromContext(String query) {
    _controller?.close();
    _controller = StreamController<LLMToken>();
    _setupCallbacks(_controller!);
    final qPtr = query.toNativeUtf8();
    try {
      final rc = _b.llmGenerateFromContext(_handle, qPtr,
          _tokenCb!.nativeFunction, _errorCb!.nativeFunction, nullptr);
      if (rc != 0) {
        _controller!.addError(RunAnywhereException(rc, 'ra_llm_generate_from_context'));
        _controller!.close();
      }
    } finally {
      calloc.free(qPtr);
    }
    return _controller!.stream;
  }

  void _setupCallbacks(StreamController<LLMToken> c) {
    _tokenCb?.close(); _errorCb?.close();
    _tokenCb = NativeCallable<NativeTokenCb>.listener(
      (Pointer<RaTokenOutput> t, Pointer<Void> _) {
        if (t == nullptr) return;
        final text = t.ref.text == nullptr ? '' : t.ref.text.toDartString();
        final isFinal = t.ref.isFinal != 0;
        c.add(LLMToken.fromKindRaw(text, t.ref.tokenKind, isFinal));
        if (isFinal) c.close();
      },
    );
    _errorCb = NativeCallable<NativeErrorCb>.listener(
      (int code, Pointer<Utf8> msg, Pointer<Void> _) {
        final m = msg == nullptr ? '' : msg.toDartString();
        c.addError(RunAnywhereException(code, m));
        c.close();
      },
    );
  }

  int cancel() => _b.llmCancel(_handle);
  int reset()  => _b.llmReset(_handle);

  int injectSystemPrompt(String prompt) {
    final p = prompt.toNativeUtf8();
    try { return _b.llmInjectSystemPrompt(_handle, p); }
    finally { calloc.free(p); }
  }

  int appendContext(String text) {
    final p = text.toNativeUtf8();
    try { return _b.llmAppendContext(_handle, p); }
    finally { calloc.free(p); }
  }

  int clearContext() => _b.llmClearContext(_handle);

  void close() {
    if (_handle != nullptr) { _b.llmDestroy(_handle); _handle = nullptr; }
    _tokenCb?.close(); _tokenCb = null;
    _errorCb?.close(); _errorCb = null;
    _controller?.close(); _controller = null;
  }
}
