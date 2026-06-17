/// DartBridge+STT
///
/// STT component bridge - manages C++ STT component lifecycle.
/// Mirrors Swift's CppBridge+STT.swift pattern.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/stt_options.pb.dart'
    show
        STTAudioSource_Source,
        STTOptions,
        STTOutput,
        STTPartialResult,
        STTStreamEvent,
        STTStreamEventKind,
        STTTranscriptionRequest;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/native_functions.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// STT component bridge for C++ interop.
///
/// Provides thread-safe access to the C++ STT component.
/// Handles model loading, transcription, and streaming.
class DartBridgeSTT {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeSTT shared = DartBridgeSTT._();

  DartBridgeSTT._();

  // MARK: - State

  RacHandle? _handle;
  String? _loadedModelId;
  final _logger = SDKLogger('DartBridge.STT');
  static STTOutput Function(STTTranscriptionRequest)?
      _transcribeLifecycleProtoForTesting;

  static void setTranscribeLifecycleProtoForTesting(
    STTOutput Function(STTTranscriptionRequest)? override,
  ) {
    _transcribeLifecycleProtoForTesting = override;
  }

  // MARK: - Handle Management

  /// Get or create the STT component handle.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final handlePtr = calloc<RacHandle>();
      try {
        final result = NativeFunctions.sttCreate(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create STT component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('STT component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create STT handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a model is loaded.
  bool get isLoaded {
    if (_handle == null) return false;

    try {
      return NativeFunctions.sttIsLoaded(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded model ID.
  String? get currentModelId => _loadedModelId;

  /// Check if streaming is supported.
  bool get supportsStreaming {
    if (_handle == null) return false;

    try {
      return NativeFunctions.sttSupportsStreaming(_handle!) == RAC_TRUE;
    } catch (e) {
      return false;
    }
  }

  // MARK: - Transcription

  /// Transcribe audio through the lifecycle-owned generated-proto STT ABI.
  ///
  /// Synchronous variant retained for the unit-test harness (which drives it
  /// with [setTranscribeLifecycleProtoForTesting]). Production callers use
  /// [transcribeLifecycleProtoAsync], which runs the blocking native call off
  /// the UI isolate.
  STTOutput transcribeLifecycleProto(STTTranscriptionRequest request) {
    _validateLifecycleRequest(request);

    final override = _transcribeLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_stt_transcribe_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_stt_transcribe_lifecycle_proto is unavailable',
      );
    }

    return DartBridgeProtoUtils.callRequest<STTOutput>(
      request: request,
      invoke: fn,
      decode: STTOutput.fromBuffer,
      symbol: 'rac_stt_transcribe_lifecycle_proto',
    );
  }

  /// Transcribe audio through the lifecycle-owned generated-proto STT ABI,
  /// running the blocking native call in a short-lived worker isolate
  /// (`Isolate.run`) so the calling isolate — usually the Flutter UI isolate —
  /// stays responsive for the whole transcription. Whisper decode of a batch
  /// buffer is a long synchronous block; on the UI isolate it freezes frames.
  /// Mirrors `dart_bridge_llm.dart`'s `generateProto`: this ABI is
  /// lifecycle-owned (no Dart-held handle), so the worker re-resolves the
  /// engine via the commons model lifecycle — nothing isolate-bound crosses.
  Future<STTOutput> transcribeLifecycleProtoAsync(
    STTTranscriptionRequest request,
  ) async {
    _validateLifecycleRequest(request);

    final override = _transcribeLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    if (RacNative.bindings.rac_stt_transcribe_lifecycle_proto == null) {
      throw UnsupportedError(
        'rac_stt_transcribe_lifecycle_proto is unavailable',
      );
    }

    final requestBytes = request.writeToBuffer();
    final resultBytes =
        await Isolate.run(() => _sttTranscribeWorker(requestBytes));
    return STTOutput.fromBuffer(resultBytes);
  }

  /// Transcribe audio with serialized runanywhere.v1.STTOptions.
  Future<STTOutput> transcribeProto(
    Uint8List audioData,
    STTOptions options,
  ) async {
    final handle = getHandle();
    if (!isLoaded) {
      throw UnsupportedError(
        'No STT component handle is loaded. Public STT uses '
        'transcribeLifecycleProto instead of Dart-held component handles.',
      );
    }

    final fn = RacNative.bindings.rac_stt_component_transcribe_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_stt_component_transcribe_proto is unavailable');
    }

    final optionsBytes = options.writeToBuffer();
    final audioPtr = calloc<Uint8>(audioData.isEmpty ? 1 : audioData.length);
    final optionsPtr = DartBridgeProtoUtils.copyBytes(optionsBytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      if (audioData.isNotEmpty) {
        audioPtr.asTypedList(audioData.length).setAll(0, audioData);
      }
      bindings.rac_proto_buffer_init(out);
      final code = fn(
        handle,
        audioPtr.cast<Void>(),
        audioData.length,
        optionsPtr,
        optionsBytes.length,
        out,
      );
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_stt_component_transcribe_proto',
      );
      return DartBridgeProtoUtils.decodeBuffer(out, STTOutput.fromBuffer);
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(audioPtr);
      calloc.free(optionsPtr);
      calloc.free(out);
    }
  }

  // MARK: - Streaming Session (chunk-feed)

  /// Load a model onto this component handle. Streaming sessions are
  /// handle-bound, so the lifecycle-resolved model must be loaded here first
  /// (mirrors Swift `prepareStreamingHandle`). No-op when already loaded.
  void loadModelForStreaming({
    required String path,
    required String id,
    required String name,
  }) {
    if (_loadedModelId == id && isLoaded) {
      return;
    }
    final fn = RacNative.bindings.rac_stt_component_load_model;
    if (fn == null) {
      throw UnsupportedError('rac_stt_component_load_model is unavailable');
    }
    final handle = getHandle();
    final pathPtr = path.toNativeUtf8();
    final idPtr = id.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      final code = fn(handle, pathPtr, idPtr, namePtr);
      if (code != RAC_SUCCESS) {
        throw StateError(
          'rac_stt_component_load_model failed: '
          '${RacResultCode.getMessage(code)}',
        );
      }
      _loadedModelId = id;
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  /// Canonical chunk-feed stream-in / stream-out transcription session.
  ///
  /// Consumes a `Stream<Uint8List>` of PCM audio chunks and yields
  /// `STTPartialResult` events as the native session emits them. Closing the
  /// input stream stops the session, which flushes the final result. Mirrors
  /// Swift `CppBridge.STT.transcribeSessionStream` over the
  /// `rac_stt_stream_*_proto` ABI (rac_stt_stream.h).
  ///
  /// Events fire synchronously during `feed`/`stop` on this isolate
  /// (`NativeCallable.isolateLocal` — same UAF rationale as the one-shot
  /// `transcribeStream`); teardown follows the header contract:
  /// unset callback → `rac_stt_proto_quiesce()` → close the callable.
  Stream<STTPartialResult> transcribeSessionStream(
    Stream<Uint8List> audio,
    STTOptions options,
  ) {
    final controller = StreamController<STTPartialResult>();
    NativeCallable<RacSttStreamEventCallbackNative>? nativeCb;
    var cancelled = false;
    var sessionId = 0;

    void emitFailure(String message) {
      if (controller.isClosed) return;
      controller.add(
        STTPartialResult(text: message, isFinal: true),
      );
    }

    controller
      ..onListen = () async {
        final bindings = RacNative.bindings;
        final setCallback = bindings.rac_stt_set_stream_proto_callback;
        final unsetCallback = bindings.rac_stt_unset_stream_proto_callback;
        final start = bindings.rac_stt_stream_start_proto;
        final feed = bindings.rac_stt_stream_feed_audio_proto;
        final stop = bindings.rac_stt_stream_stop_proto;
        final cancel = bindings.rac_stt_stream_cancel_proto;
        if (setCallback == null ||
            unsetCallback == null ||
            start == null ||
            feed == null ||
            stop == null ||
            cancel == null) {
          controller.addError(UnsupportedError(
            'rac_stt_stream_*_proto session ABI is unavailable in this '
            'commons binary',
          ));
          unawaited(controller.close());
          return;
        }

        RacHandle? handle;
        try {
          handle = getHandle();

          nativeCb = NativeCallable<RacSttStreamEventCallbackNative>.isolateLocal(
            (Pointer<Uint8> bytesPtr, int bytesLen, Pointer<Void> _) {
              if (controller.isClosed ||
                  cancelled ||
                  bytesLen <= 0 ||
                  bytesPtr == nullptr) {
                return;
              }
              final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
              try {
                final event = STTStreamEvent.fromBuffer(copy);
                switch (event.kind) {
                  case STTStreamEventKind.STT_STREAM_EVENT_KIND_PARTIAL:
                  case STTStreamEventKind.STT_STREAM_EVENT_KIND_ENDPOINT:
                    if (event.hasPartial()) {
                      controller.add(event.partial);
                    }
                  case STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL:
                    // `event` is a local decode of copied bytes; mutating its
                    // submessage in place is safe.
                    final partial =
                        event.hasPartial() ? event.partial : STTPartialResult();
                    partial.isFinal = true;
                    if (event.hasFinalOutput()) {
                      partial.finalOutput = event.finalOutput;
                      if (partial.text.isEmpty) {
                        partial.text = event.finalOutput.text;
                      }
                    }
                    controller.add(partial);
                  case STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR:
                    emitFailure(
                      event.hasErrorMessage()
                          ? event.errorMessage
                          : 'STT stream failed',
                    );
                  default:
                    break;
                }
              } catch (e, st) {
                controller.addError(e, st);
              }
            },
          );

          final registerCode =
              setCallback(handle, nativeCb!.nativeFunction, nullptr);
          if (registerCode != RAC_SUCCESS) {
            emitFailure(
              'STT stream callback registration failed: $registerCode',
            );
            return;
          }

          final optionsBytes = options.writeToBuffer();
          final optionsPtr = DartBridgeProtoUtils.copyBytes(optionsBytes);
          final sessionOut = calloc<Uint64>();
          try {
            final startCode = start(
              handle,
              optionsPtr,
              optionsBytes.length,
              sessionOut,
            );
            sessionId = sessionOut.value;
            if (startCode != RAC_SUCCESS || sessionId == 0) {
              emitFailure('STT stream start failed: $startCode');
              return;
            }
          } finally {
            calloc.free(optionsPtr);
            calloc.free(sessionOut);
          }

          await for (final chunk in audio) {
            if (cancelled || controller.isClosed) break;
            if (chunk.isEmpty) continue;
            final chunkPtr = DartBridgeProtoUtils.copyBytes(chunk);
            try {
              final feedCode = feed(sessionId, chunkPtr, chunk.length);
              if (feedCode != RAC_SUCCESS) {
                emitFailure('STT stream feed failed: $feedCode');
                cancelled = true;
                break;
              }
            } finally {
              calloc.free(chunkPtr);
            }
          }

          if (cancelled) {
            cancel(sessionId);
          } else {
            final stopCode = stop(sessionId);
            if (stopCode != RAC_SUCCESS) {
              emitFailure('STT stream stop failed: $stopCode');
            }
          }
          sessionId = 0;
        } catch (e, st) {
          controller.addError(e, st);
        } finally {
          if (handle != null) {
            unsetCallback(handle);
          }
          bindings.rac_stt_proto_quiesce?.call();
          nativeCb?.close();
          nativeCb = null;
          unawaited(controller.close());
        }
      }
      ..onCancel = () {
        cancelled = true;
        if (sessionId != 0) {
          RacNative.bindings.rac_stt_stream_cancel_proto?.call(sessionId);
          sessionId = 0;
        }
      };

    return controller.stream;
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        NativeFunctions.sttDestroy(_handle!);
        _handle = null;
        _loadedModelId = null;
        _logger.debug('STT component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy STT component: $e');
      }
    }
  }

  void _validateLifecycleRequest(STTTranscriptionRequest request) {
    if (!request.hasAudio()) {
      throw ArgumentError(
        'STTTranscriptionRequest.audio is required for lifecycle STT',
      );
    }
    switch (request.audio.whichSource()) {
      case STTAudioSource_Source.audioData:
        if (request.audio.audioData.isEmpty) {
          throw ArgumentError(
            'STTTranscriptionRequest.audio.audio_data is required',
          );
        }
        return;
      case STTAudioSource_Source.fileUri:
      case STTAudioSource_Source.adapterHandle:
        throw UnsupportedError(
          'STT audio file_uri/adapter_handle requires a platform adapter',
        );
      case STTAudioSource_Source.notSet:
        throw ArgumentError(
          'STTTranscriptionRequest.audio.audio_data is required',
        );
    }
  }
}

/// Blocking body of [DartBridgeSTT.transcribeLifecycleProtoAsync]: a plain
/// request→response proto call with no callbacks. Top-level so the
/// `Isolate.run` closure captures only its sendable `Uint8List` argument.
/// `RacNative.bindings` is a per-isolate static — the worker re-resolves the
/// dylib symbols on first access (idempotent `PlatformLoader.loadCommons()`,
/// same convention as the LLM/VLM workers). Returns the serialized STTOutput
/// so the main isolate owns the decode.
Uint8List _sttTranscribeWorker(Uint8List requestBytes) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_stt_transcribe_lifecycle_proto;
  if (fn == null) {
    throw UnsupportedError('rac_stt_transcribe_lifecycle_proto is unavailable');
  }

  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  final out = calloc<RacProtoBuffer>();
  try {
    bindings.rac_proto_buffer_init(out);
    final code = fn(requestPtr, requestBytes.length, out);
    DartBridgeProtoUtils.ensureSuccess(
      out,
      code,
      'rac_stt_transcribe_lifecycle_proto',
    );
    if (out.ref.data == nullptr || out.ref.size == 0) {
      return Uint8List(0);
    }
    return Uint8List.fromList(out.ref.data.asTypedList(out.ref.size));
  } finally {
    bindings.rac_proto_buffer_free(out);
    calloc.free(out);
    calloc.free(requestPtr);
  }
}
