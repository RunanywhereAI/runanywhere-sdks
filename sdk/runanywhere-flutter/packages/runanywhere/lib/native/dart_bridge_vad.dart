/// DartBridge+VAD
///
/// VAD component bridge - manages C++ VAD component lifecycle.
/// Mirrors Swift's CppBridge+VAD.swift pattern.
library dart_bridge_vad;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/vad_options.pb.dart' as vad_pb;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/native_functions.dart';

/// VAD component bridge for C++ interop.
///
/// Provides thread-safe access to the C++ VAD component.
/// Handles voice activity detection with configurable thresholds.
///
/// Usage:
/// ```dart
/// final vad = DartBridgeVAD.shared;
/// vad.initialize();
/// vad.start();
/// final isSpeech = vad.process(audioSamples);
/// ```
class DartBridgeVAD {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeVAD shared = DartBridgeVAD._();

  DartBridgeVAD._();

  // MARK: - State

  RacHandle? _handle;
  final _logger = SDKLogger('DartBridge.VAD');

  /// Stream controller for speech activity events
  final _activityController = StreamController<VADActivityEvent>.broadcast();
  final _activityProtoController =
      StreamController<vad_pb.SpeechActivityEvent>.broadcast();
  NativeCallable<RacVadProtoActivityCallbackNative>? _activityProtoCallback;

  /// Stream of speech activity events
  Stream<VADActivityEvent> get activityStream => _activityController.stream;
  Stream<vad_pb.SpeechActivityEvent> get activityProtoStream =>
      _activityProtoController.stream;

  // MARK: - Handle Management

  /// Get or create the VAD component handle.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final handlePtr = calloc<RacHandle>();
      try {
        final result = NativeFunctions.vadCreate(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create VAD component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('VAD component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create VAD handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if VAD is initialized.
  bool get isInitialized {
    if (_handle == null) return false;

    try {
      return NativeFunctions.vadIsInitialized(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isInitialized check failed: $e');
      return false;
    }
  }

  /// Check if speech is currently detected.
  bool get isSpeechActive {
    if (_handle == null) return false;

    try {
      return NativeFunctions.vadIsSpeechActive(_handle!) == RAC_TRUE;
    } catch (e) {
      return false;
    }
  }

  /// Get current energy threshold.
  double get energyThreshold {
    if (_handle == null) return 0.0;

    try {
      return NativeFunctions.vadGetEnergyThreshold(_handle!);
    } catch (e) {
      return 0.0;
    }
  }

  /// Set energy threshold.
  set energyThreshold(double threshold) {
    if (_handle == null) return;

    try {
      NativeFunctions.vadSetEnergyThreshold(_handle!, threshold);
    } catch (e) {
      _logger.error('Failed to set energy threshold: $e');
    }
  }

  // MARK: - Lifecycle

  /// Configure VAD using the generated VADConfiguration proto.
  Future<void> configureProto(vad_pb.VADConfiguration config) async {
    final handle = getHandle();
    final fn = RacNative.bindings.rac_vad_component_configure_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_vad_component_configure_proto is unavailable');
    }

    final bytes = config.writeToBuffer();
    final ptr = DartBridgeProtoUtils.copyBytes(bytes);
    try {
      final rc = fn(handle, ptr, bytes.length);
      if (rc != RAC_SUCCESS) {
        throw StateError(
          'rac_vad_component_configure_proto failed: '
          '${RacResultCode.getMessage(rc)}',
        );
      }
      _installActivityProtoCallback();
      _logger.info('VAD configured from proto');
    } finally {
      calloc.free(ptr);
    }
  }

  /// Initialize VAD.
  ///
  /// Throws on failure.
  Future<void> initialize() async {
    final handle = getHandle();

    try {
      final result = NativeFunctions.vadInitialize(handle);

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to initialize VAD: ${RacResultCode.getMessage(result)}',
        );
      }

      _logger.info('VAD initialized');
    } catch (e) {
      _logger.error('Failed to initialize VAD: $e');
      rethrow;
    }
  }

  /// Start VAD processing.
  void start() {
    if (_handle == null) return;

    try {
      final result = NativeFunctions.vadStart(_handle!);
      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to start VAD: ${RacResultCode.getMessage(result)}',
        );
      }

      _logger.debug('VAD started');
    } catch (e) {
      _logger.error('Failed to start VAD: $e');
    }
  }

  /// Stop VAD processing.
  void stop() {
    if (_handle == null) return;

    try {
      NativeFunctions.vadStop(_handle!);
      _logger.debug('VAD stopped');
    } catch (e) {
      _logger.error('Failed to stop VAD: $e');
    }
  }

  /// Reset VAD state.
  void reset() {
    if (_handle == null) return;

    try {
      NativeFunctions.vadReset(_handle!);
      _logger.debug('VAD reset');
    } catch (e) {
      _logger.error('Failed to reset VAD: $e');
    }
  }

  /// Cleanup VAD.
  void cleanup() {
    if (_handle == null) return;

    try {
      NativeFunctions.vadCleanup(_handle!);
      _logger.info('VAD cleaned up');
    } catch (e) {
      _logger.error('Failed to cleanup VAD: $e');
    }
  }

  // MARK: - Processing

  vad_pb.VADResult processProto(
    Float32List samples, [
    vad_pb.VADOptions? options,
  ]) {
    final handle = getHandle();
    if (!isInitialized) {
      throw StateError('VAD not initialized. Call initialize() first.');
    }

    final fn = RacNative.bindings.rac_vad_component_process_proto;
    if (fn == null) {
      throw UnsupportedError('rac_vad_component_process_proto is unavailable');
    }

    final opts = options ?? vad_pb.VADOptions();
    final optionBytes = opts.writeToBuffer();
    final samplesPtr = calloc<Float>(samples.isEmpty ? 1 : samples.length);
    final optionsPtr = DartBridgeProtoUtils.copyBytes(optionBytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      for (var i = 0; i < samples.length; i++) {
        samplesPtr[i] = samples[i];
      }
      bindings.rac_proto_buffer_init(out);
      final code = fn(
        handle,
        samplesPtr,
        samples.length,
        optionsPtr,
        optionBytes.length,
        out,
      );
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_vad_component_process_proto',
      );
      return DartBridgeProtoUtils.decodeBuffer(
          out, vad_pb.VADResult.fromBuffer);
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(samplesPtr);
      calloc.free(optionsPtr);
      calloc.free(out);
    }
  }

  vad_pb.VADStatistics statisticsProto() {
    final handle = getHandle();
    final fn = RacNative.bindings.rac_vad_component_get_statistics_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_vad_component_get_statistics_proto is unavailable',
      );
    }
    return DartBridgeProtoUtils.callOut<vad_pb.VADStatistics>(
      invoke: (out) => fn(handle, out),
      decode: vad_pb.VADStatistics.fromBuffer,
      symbol: 'rac_vad_component_get_statistics_proto',
    );
  }

  /// Process audio samples for voice activity.
  ///
  /// [samples] - Float32 audio samples.
  ///
  /// Returns VAD result with speech/non-speech determination.
  VADResult process(Float32List samples) {
    final handle = getHandle();

    if (!isInitialized) {
      throw StateError('VAD not initialized. Call initialize() first.');
    }

    // Allocate native memory for samples
    final samplesPtr = calloc<Float>(samples.length);
    final resultPtr = calloc<RacVadResultStruct>();

    try {
      // Copy samples to native memory
      for (var i = 0; i < samples.length; i++) {
        samplesPtr[i] = samples[i];
      }

      final status = NativeFunctions.vadProcess(
        handle,
        samplesPtr,
        samples.length,
        resultPtr,
      );

      if (status != RAC_SUCCESS) {
        throw StateError(
          'VAD processing failed: ${RacResultCode.getMessage(status)}',
        );
      }

      final result = resultPtr.ref;
      final vadResult = VADResult(
        isSpeech: result.isSpeech == RAC_TRUE,
        energy: result.energy,
        speechProbability: result.speechProbability,
      );

      // Emit activity event
      if (vadResult.isSpeech) {
        _activityController.add(VADActivityEvent.speechStarted(
          energy: vadResult.energy,
          probability: vadResult.speechProbability,
        ));
      } else {
        _activityController.add(VADActivityEvent.speechEnded(
          energy: vadResult.energy,
        ));
      }

      return vadResult;
    } finally {
      calloc.free(samplesPtr);
      calloc.free(resultPtr);
    }
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        NativeFunctions.vadDestroy(_handle!);
        _handle = null;
        _activityProtoCallback?.close();
        _activityProtoCallback = null;
        _logger.debug('VAD component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy VAD component: $e');
      }
    }
  }

  /// Dispose resources.
  void dispose() {
    destroy();
    unawaited(_activityController.close());
    unawaited(_activityProtoController.close());
  }

  void _installActivityProtoCallback() {
    final fn = RacNative.bindings.rac_vad_component_set_activity_proto_callback;
    if (fn == null || _handle == null || _activityProtoCallback != null) {
      return;
    }

    final callback =
        NativeCallable<RacVadProtoActivityCallbackNative>.listener((
      Pointer<Uint8> bytesPtr,
      int bytesLen,
      Pointer<Void> _,
    ) {
      if (_activityProtoController.isClosed ||
          bytesPtr == nullptr ||
          bytesLen <= 0) {
        return;
      }
      try {
        final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
        _activityProtoController
            .add(vad_pb.SpeechActivityEvent.fromBuffer(copy));
      } catch (e, st) {
        _activityProtoController.addError(e, st);
      }
    });

    final rc = fn(_handle!, callback.nativeFunction, nullptr);
    if (rc == RAC_SUCCESS) {
      _activityProtoCallback = callback;
    } else {
      callback.close();
      _logger.debug(
        'rac_vad_component_set_activity_proto_callback failed: '
        '${RacResultCode.getMessage(rc)}',
      );
    }
  }
}

/// Result from VAD processing.
class VADResult {
  final bool isSpeech;
  final double energy;
  final double speechProbability;

  const VADResult({
    required this.isSpeech,
    required this.energy,
    required this.speechProbability,
  });
}

/// VAD activity event.
sealed class VADActivityEvent {
  const VADActivityEvent();

  factory VADActivityEvent.speechStarted({
    required double energy,
    required double probability,
  }) = VADSpeechStartedEvent;

  factory VADActivityEvent.speechEnded({required double energy}) =
      VADSpeechEndedEvent;
}

/// Speech started event.
class VADSpeechStartedEvent extends VADActivityEvent {
  final double energy;
  final double probability;

  const VADSpeechStartedEvent({
    required this.energy,
    required this.probability,
  });
}

/// Speech ended event.
class VADSpeechEndedEvent extends VADActivityEvent {
  final double energy;

  const VADSpeechEndedEvent({required this.energy});
}
