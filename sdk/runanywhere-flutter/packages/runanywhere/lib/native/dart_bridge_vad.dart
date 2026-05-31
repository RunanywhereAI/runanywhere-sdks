/// DartBridge+VAD
///
/// VAD component bridge - the public VAD capability routes through
/// commons model lifecycle, so this bridge only exposes the
/// lifecycle-owned generated-proto one-shot processing entry point
/// plus a minimal handle accessor used by state-query getters.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/vad_options.pb.dart' as vad_pb;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/native_functions.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// VAD component bridge for C++ interop.
///
/// The live entry point is [processLifecycleProto]; the remaining
/// getters expose handle state for diagnostics. All other VAD
/// lifecycle (configure / start / stop / reset / statistics) is owned
/// by commons model lifecycle and surfaced through `RunAnywhereVAD`.
class DartBridgeVAD {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeVAD shared = DartBridgeVAD._();

  DartBridgeVAD._();

  // MARK: - State

  RacHandle? _handle;
  final _logger = SDKLogger('DartBridge.VAD');
  static vad_pb.VADResult Function(vad_pb.VADProcessRequest)?
      _processLifecycleProtoForTesting;

  static void setProcessLifecycleProtoForTesting(
    vad_pb.VADResult Function(vad_pb.VADProcessRequest)? override,
  ) {
    _processLifecycleProtoForTesting = override;
  }

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

  // MARK: - Processing

  /// Process one VAD frame through the lifecycle-owned generated-proto ABI.
  vad_pb.VADResult processLifecycleProto(vad_pb.VADProcessRequest request) {
    _validateLifecycleRequest(request);

    final override = _processLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_vad_process_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_vad_process_lifecycle_proto is unavailable',
      );
    }

    return DartBridgeProtoUtils.callRequest<vad_pb.VADResult>(
      request: request,
      invoke: fn,
      decode: vad_pb.VADResult.fromBuffer,
      symbol: 'rac_vad_process_lifecycle_proto',
    );
  }

  /// Configure the lifecycle-loaded VAD with a VADConfiguration proto.
  vad_pb.VADServiceState configureLifecycleProto(
    vad_pb.VADConfiguration config,
  ) {
    final fn = RacNative.bindings.rac_vad_configure_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_vad_configure_lifecycle_proto is unavailable',
      );
    }
    return DartBridgeProtoUtils.callRequest<vad_pb.VADServiceState>(
      request: config,
      invoke: fn,
      decode: vad_pb.VADServiceState.fromBuffer,
      symbol: 'rac_vad_configure_lifecycle_proto',
    );
  }

  /// Start the lifecycle-loaded VAD. Returns post-start service state.
  vad_pb.VADServiceState startLifecycleProto() {
    final fn = RacNative.bindings.rac_vad_start_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError('rac_vad_start_lifecycle_proto is unavailable');
    }
    return DartBridgeProtoUtils.callOut<vad_pb.VADServiceState>(
      invoke: fn,
      decode: vad_pb.VADServiceState.fromBuffer,
      symbol: 'rac_vad_start_lifecycle_proto',
    );
  }

  /// Stop the lifecycle-loaded VAD. Returns post-stop service state.
  vad_pb.VADServiceState stopLifecycleProto() {
    final fn = RacNative.bindings.rac_vad_stop_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError('rac_vad_stop_lifecycle_proto is unavailable');
    }
    return DartBridgeProtoUtils.callOut<vad_pb.VADServiceState>(
      invoke: fn,
      decode: vad_pb.VADServiceState.fromBuffer,
      symbol: 'rac_vad_stop_lifecycle_proto',
    );
  }

  /// Reset internal state on the lifecycle-loaded VAD.
  vad_pb.VADServiceState resetLifecycleProto() {
    final fn = RacNative.bindings.rac_vad_reset_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError('rac_vad_reset_lifecycle_proto is unavailable');
    }
    return DartBridgeProtoUtils.callOut<vad_pb.VADServiceState>(
      invoke: fn,
      decode: vad_pb.VADServiceState.fromBuffer,
      symbol: 'rac_vad_reset_lifecycle_proto',
    );
  }

  void _validateLifecycleRequest(vad_pb.VADProcessRequest request) {
    if (!request.hasAudio()) {
      throw ArgumentError(
        'VADProcessRequest.audio is required for lifecycle VAD',
      );
    }
    switch (request.audio.whichSource()) {
      case vad_pb.VADAudioSource_Source.audioData:
        if (request.audio.audioData.isEmpty) {
          throw ArgumentError('VADProcessRequest.audio.audio_data is required');
        }
        return;
      case vad_pb.VADAudioSource_Source.adapterHandle:
        throw UnsupportedError(
          'VAD audio adapter_handle requires a platform adapter',
        );
      case vad_pb.VADAudioSource_Source.notSet:
        throw ArgumentError('VADProcessRequest.audio.audio_data is required');
    }
  }

  // MARK: - Cleanup

  /// Destroy the VAD component handle and release commons-side resources.
  /// Mirrors Swift `CppBridge+VAD.destroy()` semantics so
  /// `DartBridge.shutdown()` releases the same per-modality C++ state Swift
  /// does (see `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift:184`).
  void destroy() {
    if (_handle == null) return;
    try {
      NativeFunctions.vadDestroy(_handle!);
      _handle = null;
      _logger.debug('VAD component destroyed');
    } catch (e) {
      _logger.error('Failed to destroy VAD component: $e');
    }
  }
}
