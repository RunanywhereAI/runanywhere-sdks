// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_solutions.dart — v4 Solutions capability (T4.7 / T4.8).
//
// A "solution" is a prepackaged pipeline config — either a typed
// `SolutionConfig` proto, raw proto bytes, or YAML sugar — that the
// C++ core compiles into a GraphScheduler DAG and runs through the
// `rac_solution_*` C ABI. Mirrors the Swift / Kotlin / RN / Web
// capability shape so callers get the same API everywhere.
//
// §15 type-discipline: all `dart:ffi` work lives in
// `lib/native/dart_bridge_solutions.dart`; this capability holds an
// opaque `SolutionNativeHandle`.
//
// Usage:
//
//   final handle = await RunAnywhereSDK.instance.solutions.run(
//     config: SolutionConfig()..voiceAgent = VoiceAgentConfig()...,
//   );
//   handle.start();
//   handle.feed('hello');
//   handle.closeInput();
//   handle.destroy();

import 'dart:typed_data';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/solutions.pb.dart' as proto;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_solutions.dart';
import 'package:runanywhere/native/types/basic_types.dart' show RacResultCode;

/// Lifecycle handle for a started solution.
///
/// Owns an opaque [SolutionNativeHandle] and forwards each verb to
/// the matching C ABI entry point via [DartBridgeSolutions]. Call
/// [destroy] (or any of the idempotent helpers) when finished —
/// there is no auto-finalizer in Dart FFI and dropping the reference
/// will leak the C resources.
class SolutionHandle {
  SolutionHandle._(this._handle);

  final SolutionNativeHandle _handle;

  /// True until [destroy] (or [close]) clears the underlying handle.
  bool get isAlive => _handle.isAlive;

  /// Start the underlying scheduler. Non-blocking.
  void start() => _checkRc('start', DartBridgeSolutions.start(_handle));

  /// Request a graceful shutdown. Non-blocking.
  void stop() => _checkRc('stop', DartBridgeSolutions.stop(_handle));

  /// Force-cancel the graph; returns once worker threads observe cancellation.
  void cancel() => _checkRc('cancel', DartBridgeSolutions.cancel(_handle));

  /// Signal end-of-stream on the root input edge.
  void closeInput() =>
      _checkRc('close_input', DartBridgeSolutions.closeInput(_handle));

  /// Feed one UTF-8 item into the root input edge.
  void feed(String item) {
    _requireAlive();
    final rc = DartBridgeSolutions.feed(_handle, item);
    if (rc != 0) {
      throw SDKException.invalidState(
        'rac_solution_feed failed: ${RacResultCode.getMessage(rc)}',
      );
    }
  }

  /// Cancel, join, and release native resources. Idempotent — safe to
  /// call multiple times or after [close].
  void destroy() => DartBridgeSolutions.destroy(_handle);

  /// Alias for [destroy] — gives the API a more conventional close-shape.
  void close() => destroy();

  void _requireAlive() {
    if (!_handle.isAlive) {
      throw SDKException.invalidState(
        'SolutionHandle has already been destroyed',
      );
    }
  }

  void _checkRc(String op, int rc) {
    _requireAlive();
    if (rc != 0) {
      throw SDKException.invalidState(
        'rac_solution_$op failed: ${RacResultCode.getMessage(rc)}',
      );
    }
  }
}

/// Solutions capability surface — `RunAnywhereSDK.instance.solutions`.
///
/// Stateless. Each `run(...)` call allocates a fresh native handle;
/// callers own the returned [SolutionHandle].
class RunAnywhereSolutions {
  RunAnywhereSolutions._();
  static final RunAnywhereSolutions _instance = RunAnywhereSolutions._();
  static RunAnywhereSolutions get shared => _instance;

  /// Construct and return a (created, not started) solution from either
  /// a typed [proto.SolutionConfig] proto or a raw [configBytes] buffer.
  /// Exactly one of [config] / [configBytes] / [yaml] must be supplied.
  ///
  /// Call [SolutionHandle.start] on the returned handle to launch worker
  /// threads. The handle owns its native resources — invoke
  /// [SolutionHandle.destroy] (or [SolutionHandle.close]) when finished.
  Future<SolutionHandle> run({
    proto.SolutionConfig? config,
    Uint8List? configBytes,
    String? yaml,
  }) async {
    _ensureReady();

    final supplied = [config, configBytes, yaml].where((v) => v != null).length;
    if (supplied != 1) {
      throw SDKException.validationFailed(
        'RunAnywhereSolutions.run requires exactly one of '
        'config / configBytes / yaml (got $supplied)',
      );
    }

    if (yaml != null) return _createFromYaml(yaml);

    final bytes = configBytes ?? Uint8List.fromList(config!.writeToBuffer());
    return _createFromProto(bytes);
  }

  SolutionHandle _createFromProto(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw SDKException.validationFailed(
        'Solution config bytes are empty — refusing to call '
        'rac_solution_create_from_proto',
      );
    }

    final result = DartBridgeSolutions.createFromProto(bytes);
    if (!result.success || result.handle == null) {
      throw SDKException.invalidConfiguration(
        'rac_solution_create_from_proto failed: '
        '${RacResultCode.getMessage(result.resultCode)}',
      );
    }
    return SolutionHandle._(result.handle!);
  }

  SolutionHandle _createFromYaml(String yaml) {
    final result = DartBridgeSolutions.createFromYaml(yaml);
    if (!result.success || result.handle == null) {
      throw SDKException.invalidConfiguration(
        'rac_solution_create_from_yaml failed: '
        '${RacResultCode.getMessage(result.resultCode)}',
      );
    }
    return SolutionHandle._(result.handle!);
  }

  void _ensureReady() {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
  }
}
