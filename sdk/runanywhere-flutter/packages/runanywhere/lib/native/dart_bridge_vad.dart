/// DartBridge+VAD
///
/// VAD component bridge - manages C++ VAD component lifecycle.
/// Mirrors Swift's CppBridge+VAD.swift pattern.
library dart_bridge_vad;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
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

  /// Stream of speech activity events
  Stream<VADActivityEvent> get activityStream => _activityController.stream;

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
        resultPtr.cast<Void>(),
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

/// FFI struct for VAD result (matches rac_vad_result_t)
final class RacVadResultStruct extends Struct {
  @Int32()
  external int isSpeech;

  @Float()
  external double energy;

  @Float()
  external double speechProbability;
}
