// dart_bridge_hf_auth.dart — Hugging Face token passthrough.
//
// Thin FFI shim over commons' `rac_http_hf_token_set`. Auth itself lives in
// the C++ layer (attached only to https huggingface.co/hf.co requests, never
// overriding a caller Authorization header), so every download / HEAD /
// resume / HF repo-registration path authenticates uniformly on all
// platforms. Kotlin parity: RunAnywhereBridge.racHttpHfTokenSet.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/native/platform_loader.dart';

abstract final class DartBridgeHfAuth {
  /// Set (or clear) the process-wide Hugging Face token.
  ///
  /// Empty string clears the token and disables the `HF_TOKEN` env fallback;
  /// null resets to the default env-fallback state.
  static void setHfToken(String? token) {
    final lib = PlatformLoader.loadCommons();
    final setToken = lib.lookupFunction<Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)>('rac_http_hf_token_set');
    if (token == null) {
      setToken(nullptr);
      return;
    }
    final tokenPtr = token.toNativeUtf8();
    try {
      setToken(tokenPtr);
    } finally {
      calloc.free(tokenPtr);
    }
  }
}
