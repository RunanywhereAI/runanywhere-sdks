/// DartBridge+STT
///
/// STT component bridge - manages C++ STT component lifecycle.
/// Mirrors Swift's CppBridge+STT.swift pattern.
library dart_bridge_stt;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/stt_options.pb.dart'
    show STTAudioSource_Source, STTOptions, STTOutput, STTTranscriptionRequest;
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
