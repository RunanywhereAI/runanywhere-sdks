// SPDX-License-Identifier: Apache-2.0
//
// rac_native.dart — Dart FFI bindings for commons C ABI surfaces not
// covered by `lib/native/native_functions.dart` (the legacy binding
// registry).
//
// v3-readiness Phase A2 closes the audit-flagged gap:
// `voice_agent_stream_adapter.dart` imported `../core/native/rac_native.dart`
// but the file didn't exist. This file provides a typed `RacNative`
// facade with an instance-method-style `bindings.rac_voice_agent_*`
// API so the streaming adapter's call-site compiles + runs against
// the canonical `rac_voice_agent_set_proto_callback` C ABI.
//
// Structure: a private `_RacBindings` class holds the FFI lookups as
// final fields (initialized in the constructor from the
// `DynamicLibrary`); `RacNative.bindings` is the shared singleton
// wrapping `PlatformLoader.loadCommons()`.
//
// This file is intentionally thin — only symbols that need the
// instance-method-style facade live here. Everyday
// `NativeFunctions.xxx()` lookups stay in `native_functions.dart`.

library rac_native;

import 'dart:ffi' as ffi;

import 'package:runanywhere/native/platform_loader.dart';

/// Matches `rac_voice_agent_proto_event_callback_fn` in
/// `rac/features/voice_agent/rac_voice_event_abi.h`.
///
///   `void (*)(uint8_t* bytes, size_t size, void* user_data)`
typedef RacVoiceAgentProtoEventCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

/// Native type for `rac_voice_agent_set_proto_callback`.
typedef RacVoiceAgentSetProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>, // rac_voice_agent_handle_t
  ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
  ffi.Pointer<ffi.Void>, // user_data
);

/// Dart type for `rac_voice_agent_set_proto_callback`.
typedef RacVoiceAgentSetProtoCallbackDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

/// Typed bindings for the commons C ABI surfaces this file owns.
///
/// Uses `rac_*`-style snake_case method names (matching the C symbols)
/// so call sites read identically to the C header. Public so the
/// `RacNative.bindings` static-final field can expose it without
/// tripping the `library_private_types_in_public_api` lint.
class RacBindings {
  RacBindings(ffi.DynamicLibrary lib)
      : rac_voice_agent_set_proto_callback = lib.lookupFunction<
            RacVoiceAgentSetProtoCallbackNative,
            RacVoiceAgentSetProtoCallbackDart>(
            'rac_voice_agent_set_proto_callback');

  /// Bind a proto-byte callback to a voice agent handle.
  ///
  /// Matches the C ABI at
  /// `rac/features/voice_agent/rac_voice_event_abi.h`:
  ///
  ///   rac_result_t rac_voice_agent_set_proto_callback(
  ///       rac_voice_agent_handle_t handle,
  ///       rac_voice_agent_proto_event_callback_fn callback,
  ///       void* user_data);
  ///
  /// Pass `ffi.nullptr` for [callback] to clear the registration.
  ///
  /// Returns 0 (RAC_SUCCESS) on success; non-zero otherwise.
  /// Common errors: RAC_ERROR_INVALID_HANDLE,
  /// RAC_ERROR_FEATURE_NOT_AVAILABLE (Protobuf not linked).
  // ignore: non_constant_identifier_names
  final RacVoiceAgentSetProtoCallbackDart rac_voice_agent_set_proto_callback;
}

/// Entry point for the typed commons FFI bindings.
///
/// The first call to [bindings] triggers `PlatformLoader.loadCommons()`.
/// All subsequent calls return the same cached binding singleton.
///
/// Usage (from
/// `sdk/runanywhere-flutter/packages/runanywhere/lib/adapters/
/// voice_agent_stream_adapter.dart`):
///
///     final rc = RacNative.bindings.rac_voice_agent_set_proto_callback(
///       handle,
///       nativeCb.nativeFunction,
///       ffi.nullptr,
///     );
class RacNative {
  RacNative._();

  /// Cached typed bindings. Lazily initialized on first access.
  static final RacBindings bindings =
      RacBindings(PlatformLoader.loadCommons());
}
