// SPDX-License-Identifier: Apache-2.0
//
// DartBridge+CUA
//
// Thin Dart FFI bridge over the stateless, model-agnostic Computer-Use-Agent
// (CUA) scaffold in commons (`rac/features/cua/rac_cua.h`). Mirrors the Swift
// `RunAnywhere.CUA` bridging in RunAnywhere+CUA.swift: renders a profile's
// system prompt and parses a CUA model's raw output into a viewport-scaled
// `CuaAction`. No model handle / no inference — pair it with the VLM APIs.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/public/capabilities/runanywhere_cua.dart';

/// Mirrors `rac_cua_action_t` (rac_cua.h). Field order/type must match the C
/// struct exactly; Dart FFI applies the C ABI alignment (the `double` lands on
/// its natural 8-byte boundary after the five leading int32s, exactly as the
/// C compiler pads the struct).
base class RacCuaActionStruct extends Struct {
  @Int32()
  external int type;

  @Int32()
  external int hasCoordinate;

  @Int32()
  external int x;

  @Int32()
  external int y;

  @Int32()
  external int scrollPixels;

  @Double()
  external double waitSeconds;

  @Array(2048)
  external Array<Uint8> text;

  @Array(2048)
  external Array<Uint8> reasoning;

  @Int32()
  external int parseOk;

  /// Fixed capacity of the `text` / `reasoning` char arrays in `rac_cua.h`.
  static const int textCapacity = 2048;
}

typedef _CuaSystemPromptNative =
    Int32 Function(Pointer<Utf8>, Uint32, Uint32, Pointer<Utf8>, Size);
typedef _CuaSystemPromptDart =
    int Function(Pointer<Utf8>, int, int, Pointer<Utf8>, int);

typedef _CuaParseActionNative =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Uint32,
      Uint32,
      Pointer<RacCuaActionStruct>,
    );
typedef _CuaParseActionDart =
    int Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      int,
      Pointer<RacCuaActionStruct>,
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
  /// profile's model space to [viewportW] x [viewportH]. Returns null for an
  /// unknown profile (C returns -1); `CuaAction.isValid` is false when no valid
  /// tool call was found. Mirrors Swift `CUA.parseAction`.
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
    final actionPtr = calloc<RacCuaActionStruct>();
    try {
      final rc = fn(profilePtr, outputPtr, viewportW, viewportH, actionPtr);
      if (rc != RacResultCode.success) return null;

      final action = actionPtr.ref;
      final coordinate = action.hasCoordinate != 0
          ? (x: action.x, y: action.y)
          : null;
      return CuaAction(
        kind: CuaActionKind.fromValue(action.type),
        coordinate: coordinate,
        text: _readFixedCString(action.text),
        reasoning: _readFixedCString(action.reasoning),
        scrollPixels: action.scrollPixels,
        waitSeconds: action.waitSeconds,
        isValid: action.parseOk != 0,
      );
    } catch (e) {
      _logger.debug('rac_cua_parse_action error: $e');
      return null;
    } finally {
      calloc.free(actionPtr);
      calloc.free(outputPtr);
      calloc.free(profilePtr);
    }
  }

  /// Read a NUL-terminated UTF-8 C string out of a fixed-size `char` array.
  String _readFixedCString(Array<Uint8> chars) {
    final bytes = <int>[];
    for (var i = 0; i < RacCuaActionStruct.textCapacity; i++) {
      final byte = chars[i];
      if (byte == 0) break;
      bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true);
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

  _CuaParseActionDart? _lookupParseActionOrNull() {
    try {
      return PlatformLoader.loadCommons()
          .lookupFunction<_CuaParseActionNative, _CuaParseActionDart>(
            'rac_cua_parse_action',
          );
    } catch (_) {
      _logger.debug('rac_cua_parse_action is unavailable');
      return null;
    }
  }
}
