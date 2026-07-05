/// Private Qualcomm Hexagon NPU (QHexRT) backend for the RunAnywhere Flutter SDK.
library;

import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere_qhexrt/native/qhexrt_bindings.dart';

// Re-export the generated wire types so consumers never hand-mirror them.
export 'package:runanywhere/generated/hardware_profile.pb.dart'
    show NpuCapability;
export 'package:runanywhere/generated/hardware_profile.pbenum.dart'
    show HexagonArch;

/// QHexRT NPU module — runs prebuilt QNN context binaries on Snapdragon
/// v75+ NPUs. Android/Snapdragon only; on unsupported parts it stays
/// unavailable.
class QHexRT {
  QHexRT._();

  static const String version = '0.19.13';

  static bool _isRegistered = false;
  static QhexrtBindings? _bindings;
  static final _logger = SDKLogger('QHexRT');

  /// The unknown/unsupported fallback returned when the probe is unavailable.
  static NpuCapability _unknownCapability() =>
      NpuCapability(socId: -1, archName: 'unknown');

  /// Whether the native backend library can be loaded on this device.
  static bool get isAvailable => QhexrtBindings.checkAvailability();

  /// Probe the Hexagon NPU without loading QNN. Safe on any device.
  ///
  /// Returns the generated `runanywhere.v1.NpuCapability` proto message
  /// (socModel, socId, hexagonArch, qhexrtSupported, archName) decoded from
  /// commons' `rac_npu_probe_proto()`. On unsupported devices or probe
  /// failure it returns the unknown fallback (socId -1, archName "unknown").
  static NpuCapability probeNpu() {
    if (!isAvailable) return _unknownCapability();
    try {
      return (_bindings ??= QhexrtBindings()).probeProto();
    } catch (e) {
      _logger.error('NPU probe failed: $e');
      return _unknownCapability();
    }
  }

  /// Register the QHexRT backend with the C++ plugin registry. Safe to call
  /// multiple times; on unsupported devices registration is rejected.
  static Future<void> register() async {
    if (_isRegistered) {
      _logger.debug('QHexRT already registered');
      return;
    }
    if (!isAvailable) {
      _logger.error('QHexRT native library not available');
      return;
    }
    try {
      _bindings ??= QhexrtBindings();
      final result = _bindings!.register();
      _logger.info('rac_backend_qhexrt_register() returned: $result');
      if (result == RacResultCode.errorBackendUnavailable ||
          result == RacResultCode.errorCapabilityUnsupported) {
        _logger.error(
            'QHexRT unavailable; a Hexagon v75+ NPU is required.');
        return;
      }
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.error('QHexRT registration failed with code: $result');
        return;
      }
      _isRegistered = true;
      _logger.info('QHexRT backend registered (LLM/VLM/STT/TTS)');
    } catch (e) {
      _logger.error('QHexRT registration error: $e');
    }
  }

  /// Unregister the QHexRT backend. Async for symmetry with [register].
  static Future<void> unregister() async {
    if (_isRegistered) {
      _bindings?.unregister();
      _isRegistered = false;
      _logger.info('QHexRT backend unregistered');
    }
  }

  static void dispose() {
    _bindings = null;
    _isRegistered = false;
  }

  static void autoRegister() => unawaited(register());
}
