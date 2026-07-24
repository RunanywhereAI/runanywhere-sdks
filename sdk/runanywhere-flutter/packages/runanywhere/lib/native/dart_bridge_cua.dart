// SPDX-License-Identifier: Apache-2.0
//
// DartBridge+CUA
//
// Thin Dart FFI bridge over the stateless, model-agnostic Computer-Use-Agent
// (CUA) scaffold in commons (`rac/features/cua/rac_cua.h`). Mirrors the Swift
// `RunAnywhere.CUA` bridging in RunAnywhere+CUA.swift: renders a profile's
// system prompt and parses a CUA model's raw output into a viewport-scaled
// `CuaAction`, decoded from the canonical `runanywhere.v1.CuaAction` proto that
// commons serializes — the same proto-byte bridging every other modality uses,
// so there is no hand-mirrored C struct to keep in sync. No model handle / no
// inference — pair it with the VLM APIs.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/cua.pb.dart' as pb;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/capabilities/runanywhere_cua.dart';

typedef _CuaSystemPromptNative =
    Int32 Function(Pointer<Utf8>, Uint32, Uint32, Pointer<Utf8>, Size);
typedef _CuaSystemPromptDart =
    int Function(Pointer<Utf8>, int, int, Pointer<Utf8>, int);

typedef _CuaParseActionProtoNative =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Uint32,
      Uint32,
      Pointer<RacProtoBuffer>,
    );
typedef _CuaParseActionProtoDart =
    int Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      int,
      Pointer<RacProtoBuffer>,
    );

/// CUA scaffold bridge for C++ interop. Stateless — every call is a pure
/// function over commons' built-in profile registry.
class DartBridgeCua {
  DartBridgeCua._();

  static final DartBridgeCua shared = DartBridgeCua._();

  final _logger = SDKLogger('DartBridge.CUA');

  /// Render [profileId]'s system prompt at a declared coordinate space.
  /// Returns null for an unknown profile (C returns -1). Mirrors Swift
  /// `CUA.systemPrompt`: a first sizing call (null out-buffer) then a second
  /// call into a right-sized buffer.
  String? systemPrompt(String profileId, int displayW, int displayH) {
    final fn = _lookupSystemPromptOrNull();
    if (fn == null) return null;

    final profilePtr = profileId.toNativeUtf8();
    try {
      final needed = fn(profilePtr, displayW, displayH, nullptr, 0);
      if (needed <= 0) return null;

      final bufferSize = needed + 1;
      final buffer = calloc<Uint8>(bufferSize).cast<Utf8>();
      try {
        fn(profilePtr, displayW, displayH, buffer, bufferSize);
        return buffer.toDartString();
      } finally {
        calloc.free(buffer);
      }
    } catch (e) {
      _logger.debug('rac_cua_system_prompt error: $e');
      return null;
    } finally {
      calloc.free(profilePtr);
    }
  }

  /// Parse [modelOutput] into a [CuaAction], rescaling coordinates from the
  /// profile's model space to [viewportW] x [viewportH]. Decodes the
  /// `runanywhere.v1.CuaAction` proto commons serializes. Returns null for an
  /// unknown profile (or if the native symbol is unavailable); `CuaAction.isValid`
  /// is false when no valid tool call was found. Mirrors Swift `CUA.parseAction`.
  CuaAction? parseAction(
    String profileId,
    String modelOutput,
    int viewportW,
    int viewportH,
  ) {
    final fn = _lookupParseActionOrNull();
    if (fn == null) return null;

    final profilePtr = profileId.toNativeUtf8();
    final outputPtr = modelOutput.toNativeUtf8();
    try {
      final proto = DartBridgeProtoUtils.callOut<pb.CuaAction>(
        invoke: (out) => fn(profilePtr, outputPtr, viewportW, viewportH, out),
        decode: pb.CuaAction.fromBuffer,
        symbol: 'rac_cua_parse_action_proto',
      );
      final coordinate = proto.coordinateValid ? (x: proto.x, y: proto.y) : null;
      return CuaAction(
        kind: CuaActionKind.fromValue(proto.type.value),
        coordinate: coordinate,
        text: proto.text,
        reasoning: proto.reasoning,
        scrollPixels: proto.scrollPixels,
        waitSeconds: proto.waitSeconds,
        isValid: proto.parseOk,
      );
    } on SDKException {
      // Unknown profile — commons returns an error buffer. Match Swift (nil).
      return null;
    } finally {
      calloc.free(outputPtr);
      calloc.free(profilePtr);
    }
  }

  _CuaSystemPromptDart? _lookupSystemPromptOrNull() {
    try {
      return PlatformLoader.loadCommons()
          .lookupFunction<_CuaSystemPromptNative, _CuaSystemPromptDart>(
            'rac_cua_system_prompt',
          );
    } catch (_) {
      _logger.debug('rac_cua_system_prompt is unavailable');
      return null;
    }
  }

  _CuaParseActionProtoDart? _lookupParseActionOrNull() {
    try {
      return PlatformLoader.loadCommons()
          .lookupFunction<_CuaParseActionProtoNative, _CuaParseActionProtoDart>(
            'rac_cua_parse_action_proto',
          );
    } catch (_) {
      _logger.debug('rac_cua_parse_action_proto is unavailable');
      return null;
    }
  }
}
