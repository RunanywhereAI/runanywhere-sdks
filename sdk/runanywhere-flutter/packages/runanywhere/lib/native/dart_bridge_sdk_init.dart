// SPDX-License-Identifier: Apache-2.0
//
// DartBridge+SdkInit
//
// Two-phase SDK init bridge. Mirrors Swift's CppBridge+SdkInit.swift
// (sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/
// CppBridge+SdkInit.swift). Calls rac_sdk_init_phase1_proto,
// rac_sdk_init_phase2_proto, rac_sdk_retry_http_proto. All business logic is
// in C++ — Dart only packs the request proto, drives the C ABI through
// DartBridgeProtoUtils, and unpacks the SdkInitResult envelope.
//
// This is the canonical SDK init path: DartBridge.initialize() invokes
// [phase1] during Phase 1 and DartBridge.initializeServices() invokes
// [phase2] during Phase 2. The legacy rac_sdk_init + RacSdkConfigStruct
// path has been removed.
library;

import 'dart:ffi' as ffi;

import 'package:runanywhere/core/native/rac_native.dart' show RacProtoBuffer;
import 'package:runanywhere/generated/sdk_init.pb.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Two-phase SDK init bridge.
///
/// The static methods below are 1:1 mirrors of the symbols declared in
/// `sdk/runanywhere-commons/include/rac/lifecycle/rac_sdk_init.h`:
///
///   * [phase1] → `rac_sdk_init_phase1_proto`
///   * [phase2] → `rac_sdk_init_phase2_proto`
///   * [retryHTTP] → `rac_sdk_retry_http_proto`
///
/// Each method throws a [StateError] when the C ABI signals a hard failure
/// (validation / parse / state init). Soft failures (offline mode, missing
/// auth config) come back with `success=true` plus warning + flag fields;
/// callers inspect the returned [SdkInitResult] to decide which UI
/// affordances to enable.
class DartBridgeSdkInit {
  DartBridgeSdkInit._();

  // ---------------------------------------------------------------------------
  // Phase 1 (synchronous core init)
  // ---------------------------------------------------------------------------

  /// Drive Phase 1 (synchronous core init) through the canonical C ABI.
  ///
  /// Validates the request envelope and runs `rac_state_initialize` inside
  /// commons. The platform adapter (file I/O, secure storage, HTTP transport,
  /// log, memory callbacks) must already be registered.
  static SdkInitResult phase1(SdkInitPhase1Request request) {
    final fn = _lookupRequest('rac_sdk_init_phase1_proto');
    final result = DartBridgeProtoUtils.callRequest<SdkInitResult>(
      request: request,
      invoke: fn,
      decode: SdkInitResult.fromBuffer,
      symbol: 'rac_sdk_init_phase1_proto',
    );
    _assertSuccess(result, 'rac_sdk_init_phase1_proto');
    return result;
  }

  // ---------------------------------------------------------------------------
  // Phase 2 (async services init step list owned by C++)
  // ---------------------------------------------------------------------------

  /// Drive Phase 2 (services init step list) through the canonical C ABI.
  ///
  /// The returned [SdkInitResult] carries `httpConfigured`,
  /// `deviceRegistered`, `linkedModelsCount`, `discoveredOrphans`, and an
  /// optional `warning` so the caller can react to soft-failure outcomes.
  /// Failures in individual sub-steps are non-fatal — the C ABI reports
  /// `success=true` with flags off.
  static SdkInitResult phase2(SdkInitPhase2Request request) {
    final fn = _lookupRequest('rac_sdk_init_phase2_proto');
    final result = DartBridgeProtoUtils.callRequest<SdkInitResult>(
      request: request,
      invoke: fn,
      decode: SdkInitResult.fromBuffer,
      symbol: 'rac_sdk_init_phase2_proto',
    );
    _assertSuccess(result, 'rac_sdk_init_phase2_proto');
    return result;
  }

  // ---------------------------------------------------------------------------
  // HTTP retry
  // ---------------------------------------------------------------------------

  /// Re-attempt HTTP/auth setup after an offline initialization. Mirrors
  /// `rac_sdk_retry_http_proto` semantics: idempotent fast path when already
  /// authenticated, surfaces a `warning` when no usable external config is
  /// available.
  static SdkInitResult retryHTTP() {
    final fn = _lookupOut('rac_sdk_retry_http_proto');
    final result = DartBridgeProtoUtils.callOut<SdkInitResult>(
      invoke: fn,
      decode: SdkInitResult.fromBuffer,
      symbol: 'rac_sdk_retry_http_proto',
    );
    _assertSuccess(result, 'rac_sdk_retry_http_proto');
    return result;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Look up a `rac_sdk_init_phase{1,2}_proto`-style symbol — borrowed input
  /// bytes + owned output buffer.
  static int Function(
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<RacProtoBuffer>,
  ) _lookupRequest(String symbol) {
    final lib = PlatformLoader.loadCommons();
    return lib.lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Uint8>,
          ffi.Size,
          ffi.Pointer<RacProtoBuffer>,
        ),
        int Function(
          ffi.Pointer<ffi.Uint8>,
          int,
          ffi.Pointer<RacProtoBuffer>,
        )>(symbol);
  }

  /// Look up `rac_sdk_retry_http_proto` — owned output buffer only.
  static int Function(ffi.Pointer<RacProtoBuffer>) _lookupOut(String symbol) {
    final lib = PlatformLoader.loadCommons();
    return lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<RacProtoBuffer>),
        int Function(ffi.Pointer<RacProtoBuffer>)>(symbol);
  }

  /// Throw a [StateError] when the C ABI signals a hard failure. Soft
  /// failures (offline mode, missing auth config) come back with
  /// `success=true` plus warnings — leave those to the caller.
  static void _assertSuccess(SdkInitResult result, String symbol) {
    if (result.success) return;
    if (result.hasError()) {
      throw StateError(
        '$symbol failed: ${result.error.message} '
        '(code=${result.error.code})',
      );
    }
    throw StateError(
      '$symbol failed without error detail (phase=${result.phase.name})',
    );
  }
}
