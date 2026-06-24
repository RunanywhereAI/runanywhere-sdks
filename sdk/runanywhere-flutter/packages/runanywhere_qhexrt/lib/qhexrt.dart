/// Private Qualcomm Hexagon NPU (QHexRT) backend for the RunAnywhere Flutter SDK.
library;

import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere_qhexrt/native/qhexrt_bindings.dart';

/// Detected Hexagon NPU capability (pre-flight; no QNN load required).
class NpuInfo {
  const NpuInfo({
    required this.socModel,
    required this.socId,
    required this.arch,
    required this.supported,
  });

  /// Vendor SoC model (e.g. "SM8750"); empty when unknown.
  final String socModel;

  /// /sys/devices/soc0/soc_id, or -1 when unavailable.
  final int socId;

  /// Hexagon arch name ("v73", "v79", "v81", "unknown").
  final String arch;

  /// True when [arch] is one QHexRT runs on (v79/v81).
  final bool supported;

  static const unknown = NpuInfo(socModel: '', socId: -1, arch: 'unknown', supported: false);
}

/// QHexRT NPU module — runs prebuilt QNN context binaries on Snapdragon v79/v81
/// NPUs. Android/Snapdragon only; on unsupported parts it stays unavailable.
class QHexRT {
  QHexRT._();

  static const String version = '0.1.5';

  static bool _isRegistered = false;
  static QhexrtBindings? _bindings;
  static final _logger = SDKLogger('QHexRT');

  /// Whether the native backend library can be loaded on this device.
  static bool get isAvailable => QhexrtBindings.checkAvailability();

  /// Probe the Hexagon NPU without loading QNN. Safe on any device.
  static NpuInfo probeNpu() {
    if (!isAvailable) return NpuInfo.unknown;
    try {
      final r = (_bindings ??= QhexrtBindings()).probe();
      return NpuInfo(
        socModel: r.socModel,
        socId: r.socId,
        arch: r.arch == 0 ? 'unknown' : 'v${r.arch}',
        supported: r.supported,
      );
    } catch (e) {
      _logger.error('NPU probe failed: $e');
      return NpuInfo.unknown;
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
        _logger.error('QHexRT unavailable; a Hexagon v79/v81 NPU is required.');
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

  /// Unregister the QHexRT backend.
  static void unregister() {
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
