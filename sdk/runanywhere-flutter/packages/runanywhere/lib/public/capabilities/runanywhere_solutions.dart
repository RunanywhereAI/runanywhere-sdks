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
// Usage:
//
//   final handle = await RunAnywhereSDK.instance.solutions.run(
//     config: SolutionConfig()..voiceAgent = VoiceAgentConfig()...,
//   );
//   handle.start();
//   handle.feed('hello');
//   handle.closeInput();
//   handle.destroy();

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/solutions.pb.dart' as proto;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/native_functions.dart';

/// Lifecycle handle for a started solution.
///
/// Owns the underlying `rac_solution_handle_t` and forwards each verb
/// to the matching C ABI entry point. Call [destroy] (or any of the
/// idempotent helpers) when finished — there is no auto-finalizer in
/// Dart FFI and dropping the reference will leak the C resources.
class SolutionHandle {
  SolutionHandle._(this._handle);

  RacHandle? _handle;
  static final _logger = SDKLogger('Solutions.Handle');

  /// True until [destroy] (or [close]) clears the underlying handle.
  bool get isAlive => _handle != null;

  /// Start the underlying scheduler. Non-blocking.
  void start() => _invoke('start', NativeFunctions.solutionStart);

  /// Request a graceful shutdown. Non-blocking.
  void stop() => _invoke('stop', NativeFunctions.solutionStop);

  /// Force-cancel the graph; returns once worker threads observe cancellation.
  void cancel() => _invoke('cancel', NativeFunctions.solutionCancel);

  /// Signal end-of-stream on the root input edge.
  void closeInput() =>
      _invoke('close_input', NativeFunctions.solutionCloseInput);

  /// Feed one UTF-8 item into the root input edge.
  void feed(String item) {
    final handle = _requireHandle();
    final itemPtr = item.toNativeUtf8();
    try {
      final rc = NativeFunctions.solutionFeed(handle, itemPtr);
      if (rc != RAC_SUCCESS) {
        throw SDKException.invalidState(
          'rac_solution_feed failed: ${RacResultCode.getMessage(rc)}',
        );
      }
    } finally {
      calloc.free(itemPtr);
    }
  }

  /// Cancel, join, and release native resources. Idempotent — safe to
  /// call multiple times or after [close].
  void destroy() {
    final handle = _handle;
    if (handle == null) return;
    _handle = null;
    try {
      NativeFunctions.solutionDestroy(handle);
    } catch (e) {
      _logger.error('rac_solution_destroy threw: $e');
    }
  }

  /// Alias for [destroy] — gives the API a more conventional close-shape.
  void close() => destroy();

  RacHandle _requireHandle() {
    final handle = _handle;
    if (handle == null) {
      throw SDKException.invalidState(
        'SolutionHandle has already been destroyed',
      );
    }
    return handle;
  }

  void _invoke(String op, int Function(RacHandle) fn) {
    final handle = _requireHandle();
    final rc = fn(handle);
    if (rc != RAC_SUCCESS) {
      throw SDKException.invalidState(
        'rac_solution_$op failed: ${RacResultCode.getMessage(rc)}',
      );
    }
  }
}

/// Solutions capability surface — `RunAnywhereSDK.instance.solutions`.
///
/// Stateless. Each `run(...)` call allocates a fresh
/// `rac_solution_handle_t`; callers own the returned [SolutionHandle].
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

    final bufferPtr = calloc<Uint8>(bytes.length);
    final handlePtr = calloc<RacHandle>();
    try {
      bufferPtr.asTypedList(bytes.length).setAll(0, bytes);
      final rc = NativeFunctions.solutionCreateFromProto(
        bufferPtr.cast<Void>(),
        bytes.length,
        handlePtr,
      );
      if (rc != RAC_SUCCESS) {
        throw SDKException.invalidConfiguration(
          'rac_solution_create_from_proto failed: '
          '${RacResultCode.getMessage(rc)}',
        );
      }
      return SolutionHandle._(handlePtr.value);
    } finally {
      calloc.free(bufferPtr);
      calloc.free(handlePtr);
    }
  }

  SolutionHandle _createFromYaml(String yaml) {
    final yamlPtr = yaml.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();
    try {
      final rc =
          NativeFunctions.solutionCreateFromYaml(yamlPtr, handlePtr);
      if (rc != RAC_SUCCESS) {
        throw SDKException.invalidConfiguration(
          'rac_solution_create_from_yaml failed: '
          '${RacResultCode.getMessage(rc)}',
        );
      }
      return SolutionHandle._(handlePtr.value);
    } finally {
      calloc.free(yamlPtr);
      calloc.free(handlePtr);
    }
  }

  void _ensureReady() {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
  }
}
