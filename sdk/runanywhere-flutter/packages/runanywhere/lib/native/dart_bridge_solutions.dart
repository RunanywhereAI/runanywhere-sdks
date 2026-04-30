// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_solutions.dart — FFI helpers for the `rac_solution_*`
// C ABI. Public capability code calls into this bridge so
// `lib/public/capabilities/runanywhere_solutions.dart` stays free of
// `dart:ffi` imports (canonical §15 type-discipline).

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/native_functions.dart';

/// Opaque handle wrapper — capability code never sees the underlying
/// `Pointer`. The bridge dereferences this back into a native
/// `RacHandle` for every C call.
class SolutionNativeHandle {
  SolutionNativeHandle._(this._handle);
  RacHandle? _handle;
  bool get isAlive => _handle != null;
}

class SolutionFfiResult {
  SolutionFfiResult({required this.resultCode, this.handle});
  final int resultCode;
  final SolutionNativeHandle? handle;
  bool get success => resultCode == RAC_SUCCESS;
}

/// FFI bridge to the `rac_solution_*` C ABI.
class DartBridgeSolutions {
  DartBridgeSolutions._();

  static final _logger = SDKLogger('DartBridge.Solutions');

  /// Create a solution handle from proto-encoded config bytes.
  static SolutionFfiResult createFromProto(Uint8List bytes) {
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
        return SolutionFfiResult(resultCode: rc);
      }
      return SolutionFfiResult(
        resultCode: rc,
        handle: SolutionNativeHandle._(handlePtr.value),
      );
    } finally {
      calloc.free(bufferPtr);
      calloc.free(handlePtr);
    }
  }

  /// Create a solution handle from a YAML config string.
  static SolutionFfiResult createFromYaml(String yaml) {
    final yamlPtr = yaml.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();
    try {
      final rc = NativeFunctions.solutionCreateFromYaml(yamlPtr, handlePtr);
      if (rc != RAC_SUCCESS) {
        return SolutionFfiResult(resultCode: rc);
      }
      return SolutionFfiResult(
        resultCode: rc,
        handle: SolutionNativeHandle._(handlePtr.value),
      );
    } finally {
      calloc.free(yamlPtr);
      calloc.free(handlePtr);
    }
  }

  /// Start the underlying scheduler. Non-blocking.
  static int start(SolutionNativeHandle handle) =>
      _invoke(handle, NativeFunctions.solutionStart);

  /// Request a graceful shutdown. Non-blocking.
  static int stop(SolutionNativeHandle handle) =>
      _invoke(handle, NativeFunctions.solutionStop);

  /// Force-cancel the graph.
  static int cancel(SolutionNativeHandle handle) =>
      _invoke(handle, NativeFunctions.solutionCancel);

  /// Signal end-of-stream on the root input edge.
  static int closeInput(SolutionNativeHandle handle) =>
      _invoke(handle, NativeFunctions.solutionCloseInput);

  /// Feed one UTF-8 item into the root input edge.
  static int feed(SolutionNativeHandle handle, String item) {
    final h = handle._handle;
    if (h == null) return -1;
    final itemPtr = item.toNativeUtf8();
    try {
      return NativeFunctions.solutionFeed(h, itemPtr);
    } finally {
      calloc.free(itemPtr);
    }
  }

  /// Cancel, join, and release native resources. Idempotent.
  static void destroy(SolutionNativeHandle handle) {
    final h = handle._handle;
    if (h == null) return;
    handle._handle = null;
    try {
      NativeFunctions.solutionDestroy(h);
    } catch (e) {
      _logger.error('rac_solution_destroy threw: $e');
    }
  }

  static int _invoke(SolutionNativeHandle handle, int Function(RacHandle) fn) {
    final h = handle._handle;
    if (h == null) return -1;
    return fn(h);
  }
}

