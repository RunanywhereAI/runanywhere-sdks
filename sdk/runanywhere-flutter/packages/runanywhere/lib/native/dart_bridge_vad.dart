// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';

/// VAD bridge for C++ voice activity detection operations.
/// Matches Swift's `CppBridge+VAD.swift`.
class DartBridgeVAD {
  DartBridgeVAD._();

  static final _logger = SDKLogger('DartBridge.VAD');
  static final DartBridgeVAD instance = DartBridgeVAD._();

  NativeBackend? _backend;

  /// Set the native backend for VAD operations
  void setBackend(NativeBackend backend) {
    _backend = backend;
  }

  /// Load a VAD model
  Future<bool> loadModel({
    String? modelPath,
    Map<String, dynamic>? config,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for VAD operations');
      return false;
    }

    try {
      backend.loadVadModel(modelPath, config: config);
      return true;
    } catch (e) {
      _logger
          .error('Failed to load VAD model', metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Check if VAD model is loaded
  bool isModelLoaded() {
    return _backend?.isVadModelLoaded ?? false;
  }

  /// Unload the current VAD model
  Future<bool> unloadModel() async {
    final backend = _backend;
    if (backend == null) return true;

    try {
      backend.unloadVadModel();
      return true;
    } catch (e) {
      _logger.error('Failed to unload VAD model',
          metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Process audio for voice activity detection
  Future<VADResult?> process({
    required Float32List samples,
    int sampleRate = 16000,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for VAD processing');
      return null;
    }

    try {
      final result = backend.processVad(samples, sampleRate: sampleRate);

      return VADResult(
        isSpeech: result['isSpeech'] as bool? ?? false,
        probability: (result['probability'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      _logger.error('VAD processing failed', metadata: {'error': e.toString()});
      return null;
    }
  }

  /// Reset VAD state
  /// Note: VAD reset is not yet implemented in NativeBackend.
  void reset() {
    _logger.debug('VAD reset called (using energy-based detection)');
  }
}

/// Result of VAD processing
class VADResult {
  final bool isSpeech;
  final double probability;

  VADResult({
    required this.isSpeech,
    required this.probability,
  });
}
