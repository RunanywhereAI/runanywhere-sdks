/// DartBridge+TTS
///
/// TTS component bridge - manages C++ TTS component lifecycle.
/// Mirrors Swift's CppBridge+TTS.swift pattern.
library dart_bridge_tts;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/tts_options.pb.dart'
    show
        TTSOptions,
        TTSOutput,
        TTSServiceState,
        TTSStreamEvent,
        TTSSynthesisRequest,
        TTSVoiceInfo;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/native_functions.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// TTS component bridge for C++ interop.
///
/// Provides thread-safe access to the C++ TTS component.
/// Handles voice loading, synthesis, and streaming.
class DartBridgeTTS {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeTTS shared = DartBridgeTTS._();

  DartBridgeTTS._();

  // MARK: - State

  RacHandle? _handle;
  String? _loadedVoiceId;
  final _logger = SDKLogger('DartBridge.TTS');
  static TTSOutput Function(TTSSynthesisRequest)?
      _synthesizeLifecycleProtoForTesting;

  static void setSynthesizeLifecycleProtoForTesting(
    TTSOutput Function(TTSSynthesisRequest)? override,
  ) {
    _synthesizeLifecycleProtoForTesting = override;
  }

  // MARK: - Handle Management

  /// Get or create the TTS component handle.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final handlePtr = calloc<RacHandle>();
      try {
        final result = NativeFunctions.ttsCreate(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create TTS component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('TTS component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create TTS handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a voice is loaded.
  bool get isLoaded {
    if (_handle == null) return false;

    try {
      return NativeFunctions.ttsIsLoaded(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded voice ID.
  String? get currentVoiceId => _loadedVoiceId;

  /// Stop ongoing synthesis.
  void stop() {
    if (_handle == null) return;

    try {
      NativeFunctions.ttsStop(_handle!);
      _logger.debug('TTS synthesis stopped');
    } catch (e) {
      _logger.error('Failed to stop TTS: $e');
    }
  }

  // MARK: - Synthesis

  /// Synthesize speech through the lifecycle-owned generated-proto TTS ABI.
  TTSOutput synthesizeLifecycleProto(TTSSynthesisRequest request) {
    _validateLifecycleRequest(request);

    final override = _synthesizeLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_tts_synthesize_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_tts_synthesize_lifecycle_proto is unavailable',
      );
    }

    return DartBridgeProtoUtils.callRequest<TTSOutput>(
      request: request,
      invoke: fn,
      decode: TTSOutput.fromBuffer,
      symbol: 'rac_tts_synthesize_lifecycle_proto',
    );
  }

  /// Stream TTSStreamEvent chunks via the lifecycle-owned generated-proto ABI.
  ///
  /// Mirrors STT's `transcribeStreamLifecycleProto`. Requires commons to have
  /// the TTS model loaded through model lifecycle.
  Stream<TTSStreamEvent> synthesizeStreamLifecycleProto(
    TTSSynthesisRequest request,
  ) {
    _validateLifecycleRequest(request);

    final fn = RacNative.bindings.rac_tts_synthesize_stream_lifecycle_proto;
    if (fn == null) {
      return Stream<TTSStreamEvent>.error(
        UnsupportedError(
          'rac_tts_synthesize_stream_lifecycle_proto is unavailable',
        ),
      );
    }

    final controller = StreamController<TTSStreamEvent>(sync: false);
    NativeCallable<RacTtsStreamEventCallbackNative>? callback;

    Future<void> run() async {
      final bytes = request.writeToBuffer();
      final requestPtr = DartBridgeProtoUtils.copyBytes(bytes);

      try {
        callback = NativeCallable<RacTtsStreamEventCallbackNative>.listener((
          Pointer<Uint8> bytesPtr,
          int bytesLen,
          Pointer<Void> _,
        ) {
          if (controller.isClosed || bytesPtr == nullptr || bytesLen <= 0) {
            return;
          }
          try {
            final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
            controller.add(TTSStreamEvent.fromBuffer(copy));
          } catch (e, st) {
            controller.addError(e, st);
            unawaited(controller.close());
          }
        });
        final rc = fn(
          requestPtr,
          bytes.length,
          callback!.nativeFunction,
          nullptr,
        );
        if (rc != RAC_SUCCESS && !controller.isClosed) {
          controller.addError(StateError(
            'rac_tts_synthesize_stream_lifecycle_proto failed: '
            '${RacResultCode.getMessage(rc)}',
          ));
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      } finally {
        calloc.free(requestPtr);
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      callback?.close();
      callback = null;
    };

    unawaited(run());
    return controller.stream;
  }

  /// Stop the lifecycle-loaded TTS synthesis. Returns post-stop service state.
  TTSServiceState stopLifecycleProto() {
    final fn = RacNative.bindings.rac_tts_stop_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError('rac_tts_stop_lifecycle_proto is unavailable');
    }
    return DartBridgeProtoUtils.callOut<TTSServiceState>(
      invoke: fn,
      decode: TTSServiceState.fromBuffer,
      symbol: 'rac_tts_stop_lifecycle_proto',
    );
  }

  /// Enumerate voices via the generated-proto ABI.
  Future<List<TTSVoiceInfo>> listVoicesProto() async {
    final handle = getHandle();
    final fn = RacNative.bindings.rac_tts_component_list_voices_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_tts_component_list_voices_proto is unavailable');
    }

    final voices = <TTSVoiceInfo>[];
    NativeCallable<RacTtsProtoVoiceCallbackNative>? callback;

    try {
      callback = NativeCallable<RacTtsProtoVoiceCallbackNative>.listener((
        Pointer<Uint8> bytesPtr,
        int bytesLen,
        Pointer<Void> _,
      ) {
        if (bytesPtr == nullptr || bytesLen <= 0) return;
        final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
        voices.add(TTSVoiceInfo.fromBuffer(copy));
      });
      final rc = fn(handle, callback.nativeFunction, nullptr);
      if (rc != RAC_SUCCESS) {
        throw StateError(
          'rac_tts_component_list_voices_proto failed: '
          '${RacResultCode.getMessage(rc)}',
        );
      }
      return voices;
    } finally {
      callback?.close();
    }
  }

  /// Synthesize speech with serialized runanywhere.v1.TTSOptions.
  Future<TTSOutput> synthesizeProto(String text, TTSOptions options) async {
    final handle = getHandle();
    if (!isLoaded) {
      throw UnsupportedError(
        'No TTS component handle is loaded. Public TTS uses '
        'synthesizeLifecycleProto instead of Dart-held component handles.',
      );
    }

    final fn = RacNative.bindings.rac_tts_component_synthesize_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_tts_component_synthesize_proto is unavailable');
    }

    final textPtr = text.toNativeUtf8();
    final optionBytes = options.writeToBuffer();
    final optionPtr = DartBridgeProtoUtils.copyBytes(optionBytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = fn(handle, textPtr, optionPtr, optionBytes.length, out);
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_tts_component_synthesize_proto',
      );
      return DartBridgeProtoUtils.decodeBuffer(out, TTSOutput.fromBuffer);
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(textPtr);
      calloc.free(optionPtr);
      calloc.free(out);
    }
  }

  /// Stream synthesized speech chunks through serialized TTSOutput messages.
  Stream<TTSOutput> synthesizeStreamProto(String text, TTSOptions options) {
    if (!isLoaded) {
      return Stream<TTSOutput>.error(
        UnsupportedError(
          'No TTS component handle is loaded. Public TTS streaming remains '
          'unavailable until a lifecycle-owned stream ABI exists.',
        ),
      );
    }
    final fn = RacNative.bindings.rac_tts_component_synthesize_stream_proto;
    if (fn == null) {
      return Stream<TTSOutput>.error(
        UnsupportedError(
            'rac_tts_component_synthesize_stream_proto is unavailable'),
      );
    }

    final controller = StreamController<TTSOutput>(sync: false);
    NativeCallable<RacTtsProtoChunkCallbackNative>? callback;

    Future<void> run() async {
      final textPtr = text.toNativeUtf8();
      final optionBytes = options.writeToBuffer();
      final optionPtr = DartBridgeProtoUtils.copyBytes(optionBytes);

      try {
        callback = NativeCallable<RacTtsProtoChunkCallbackNative>.listener((
          Pointer<Uint8> bytesPtr,
          int bytesLen,
          Pointer<Void> _,
        ) {
          if (controller.isClosed || bytesPtr == nullptr || bytesLen <= 0) {
            return;
          }
          try {
            final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
            controller.add(TTSOutput.fromBuffer(copy));
          } catch (e, st) {
            controller.addError(e, st);
            unawaited(controller.close());
          }
        });
        final rc = fn(
          getHandle(),
          textPtr,
          optionPtr,
          optionBytes.length,
          callback!.nativeFunction,
          nullptr,
        );
        if (rc != RAC_SUCCESS && !controller.isClosed) {
          controller.addError(StateError(
            'rac_tts_component_synthesize_stream_proto failed: '
            '${RacResultCode.getMessage(rc)}',
          ));
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      } finally {
        calloc.free(textPtr);
        calloc.free(optionPtr);
        callback?.close();
        callback = null;
      }
    }

    controller.onCancel = () {
      callback?.close();
      callback = null;
    };

    unawaited(run());
    return controller.stream;
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        NativeFunctions.ttsDestroy(_handle!);
        _handle = null;
        _loadedVoiceId = null;
        _logger.debug('TTS component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy TTS component: $e');
      }
    }
  }

  void _validateLifecycleRequest(TTSSynthesisRequest request) {
    if (request.text.isEmpty && (!request.hasSsml() || request.ssml.isEmpty)) {
      throw ArgumentError(
        'TTSSynthesisRequest.text or ssml is required for lifecycle TTS',
      );
    }
  }
}
