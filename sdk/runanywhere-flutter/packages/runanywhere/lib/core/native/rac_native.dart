// SPDX-License-Identifier: Apache-2.0
//
// rac_native.dart — Dart FFI bindings for commons C ABI surfaces not
// covered by `lib/native/native_functions.dart` (the legacy binding
// registry).
//
// Scope today:
//   * Streaming proto callbacks (voice agent, LLM) — Phase A2 audit gap.
//   * Phase H HTTP client (`rac_http_client_*`, `rac_http_request_send`,
//     `rac_http_response_free`, `rac_http_request_stream`) and the
//     blocking file download (`rac_http_download_execute`). These
//     replace the per-SDK hand-rolled HTTP transports.
//
// Structure: a private `_RacBindings` class holds FFI lookups as final
// fields; `RacNative.bindings` is the shared singleton wrapping
// `PlatformLoader.loadCommons()`.

library rac_native;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' show Utf8;
import 'package:runanywhere/native/platform_loader.dart';

// ============================================================================
// Voice agent + LLM proto streaming (Phase A2 / Phase G-2)
// ============================================================================

/// Matches `rac_voice_agent_proto_event_callback_fn` in
/// `rac/features/voice_agent/rac_voice_event_abi.h`.
typedef RacVoiceAgentProtoEventCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacVoiceAgentSetProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacVoiceAgentSetProtoCallbackDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

/// Matches `rac_llm_stream_proto_callback_fn` in
/// `rac/features/llm/rac_llm_stream.h`.
typedef RacLlmStreamProtoCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacLlmSetStreamProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacLlmStreamProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacLlmSetStreamProtoCallbackDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacLlmStreamProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

// ============================================================================
// Phase H HTTP client (rac_http_client.h)
// ============================================================================

/// Matches `rac_http_header_kv_t`.
final class RacHttpHeaderKv extends ffi.Struct {
  external ffi.Pointer<Utf8> name;
  external ffi.Pointer<Utf8> value;
}

/// Matches `rac_http_request_t`.
final class RacHttpRequest extends ffi.Struct {
  external ffi.Pointer<Utf8> method;
  external ffi.Pointer<Utf8> url;

  external ffi.Pointer<RacHttpHeaderKv> headers;
  @ffi.Size()
  external int headerCount;

  external ffi.Pointer<ffi.Uint8> bodyBytes;
  @ffi.Size()
  external int bodyLen;

  @ffi.Int32()
  external int timeoutMs;

  /// `rac_bool_t` — 1 = follow redirects, 0 = don't.
  @ffi.Int32()
  external int followRedirects;

  external ffi.Pointer<Utf8> expectedChecksumHex;
}

/// Matches `rac_http_response_t`.
final class RacHttpResponse extends ffi.Struct {
  @ffi.Int32()
  external int status;

  external ffi.Pointer<RacHttpHeaderKv> headers;
  @ffi.Size()
  external int headerCount;

  external ffi.Pointer<ffi.Uint8> bodyBytes;
  @ffi.Size()
  external int bodyLen;

  external ffi.Pointer<Utf8> redirectedUrl;

  @ffi.Uint64()
  external int elapsedMs;
}

typedef RacHttpClientCreateNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Pointer<ffi.Void>>);
typedef RacHttpClientCreateDart = int Function(
    ffi.Pointer<ffi.Pointer<ffi.Void>>);

typedef RacHttpClientDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef RacHttpClientDestroyDart = void Function(ffi.Pointer<ffi.Void>);

typedef RacHttpRequestSendNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacHttpRequest>,
  ffi.Pointer<RacHttpResponse>,
);
typedef RacHttpRequestSendDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacHttpRequest>,
  ffi.Pointer<RacHttpResponse>,
);

typedef RacHttpResponseFreeNative = ffi.Void Function(
    ffi.Pointer<RacHttpResponse>);
typedef RacHttpResponseFreeDart = void Function(ffi.Pointer<RacHttpResponse>);

// ============================================================================
// Phase H HTTP download (rac_http_download.h)
// ============================================================================

/// Matches `rac_http_download_request_t`.
final class RacHttpDownloadRequest extends ffi.Struct {
  external ffi.Pointer<Utf8> url;
  external ffi.Pointer<Utf8> destinationPath;

  external ffi.Pointer<RacHttpHeaderKv> headers;
  @ffi.Size()
  external int headerCount;

  @ffi.Int32()
  external int timeoutMs;

  @ffi.Int32()
  external int followRedirects;

  @ffi.Uint64()
  external int resumeFromByte;

  external ffi.Pointer<Utf8> expectedSha256Hex;
}

/// Matches `rac_http_download_progress_fn`.
///
///   rac_bool_t (*)(uint64_t bytes_written, uint64_t total_bytes,
///                  void* user_data)
typedef RacHttpDownloadProgressNative = ffi.Int32 Function(
  ffi.Uint64,
  ffi.Uint64,
  ffi.Pointer<ffi.Void>,
);

typedef RacHttpDownloadExecuteNative = ffi.Int32 Function(
  ffi.Pointer<RacHttpDownloadRequest>,
  ffi.Pointer<ffi.NativeFunction<RacHttpDownloadProgressNative>>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Int32>,
);
typedef RacHttpDownloadExecuteDart = int Function(
  ffi.Pointer<RacHttpDownloadRequest>,
  ffi.Pointer<ffi.NativeFunction<RacHttpDownloadProgressNative>>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Int32>,
);

// ============================================================================
// Model registry refresh (rac_model_registry.h — T4.9)
// ============================================================================

/// Matches `rac_model_registry_refresh_opts_t`.
///
/// `discoveryCallbacks` is left as `Pointer<ffi.Void>` here because the
/// callbacks struct is defined in `dart_bridge_model_registry.dart` and the
/// Dart-side refresh caller (the Models capability) passes `nullptr`
/// today — platform file-IO discovery runs through
/// `DartBridgeModelRegistry.discoverDownloadedModels()` separately.
final class RacModelRegistryRefreshOpts extends ffi.Struct {
  @ffi.Int32()
  external int includeRemoteCatalog;
  @ffi.Int32()
  external int rescanLocal;
  @ffi.Int32()
  external int pruneOrphans;
  external ffi.Pointer<ffi.Void> discoveryCallbacks;
}

typedef RacModelRegistryRefreshNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, RacModelRegistryRefreshOpts);
typedef RacModelRegistryRefreshDart = int Function(
    ffi.Pointer<ffi.Void>, RacModelRegistryRefreshOpts);

// ============================================================================
// Bindings facade
// ============================================================================

/// Typed bindings for the commons C ABI surfaces this file owns.
class RacBindings {
  RacBindings(ffi.DynamicLibrary lib)
      : rac_voice_agent_set_proto_callback = lib.lookupFunction<
            RacVoiceAgentSetProtoCallbackNative,
            RacVoiceAgentSetProtoCallbackDart>(
            'rac_voice_agent_set_proto_callback'),
        rac_llm_set_stream_proto_callback = lib.lookupFunction<
            RacLlmSetStreamProtoCallbackNative,
            RacLlmSetStreamProtoCallbackDart>(
            'rac_llm_set_stream_proto_callback'),
        rac_llm_unset_stream_proto_callback = lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)>(
            'rac_llm_unset_stream_proto_callback'),
        rac_http_client_create = lib.lookupFunction<RacHttpClientCreateNative,
            RacHttpClientCreateDart>('rac_http_client_create'),
        rac_http_client_destroy = lib.lookupFunction<
            RacHttpClientDestroyNative,
            RacHttpClientDestroyDart>('rac_http_client_destroy'),
        rac_http_request_send = lib.lookupFunction<RacHttpRequestSendNative,
            RacHttpRequestSendDart>('rac_http_request_send'),
        rac_http_response_free = lib.lookupFunction<RacHttpResponseFreeNative,
            RacHttpResponseFreeDart>('rac_http_response_free'),
        rac_http_download_execute = lib.lookupFunction<
            RacHttpDownloadExecuteNative,
            RacHttpDownloadExecuteDart>('rac_http_download_execute'),
        rac_model_registry_refresh = lib.lookupFunction<
            RacModelRegistryRefreshNative,
            RacModelRegistryRefreshDart>('rac_model_registry_refresh');

  // Streaming callbacks ------------------------------------------------------

  // ignore: non_constant_identifier_names
  final RacVoiceAgentSetProtoCallbackDart rac_voice_agent_set_proto_callback;

  // ignore: non_constant_identifier_names
  final RacLlmSetStreamProtoCallbackDart rac_llm_set_stream_proto_callback;

  // ignore: non_constant_identifier_names
  final int Function(ffi.Pointer<ffi.Void>) rac_llm_unset_stream_proto_callback;

  // HTTP client --------------------------------------------------------------

  // ignore: non_constant_identifier_names
  final RacHttpClientCreateDart rac_http_client_create;

  // ignore: non_constant_identifier_names
  final RacHttpClientDestroyDart rac_http_client_destroy;

  // ignore: non_constant_identifier_names
  final RacHttpRequestSendDart rac_http_request_send;

  // ignore: non_constant_identifier_names
  final RacHttpResponseFreeDart rac_http_response_free;

  // HTTP download ------------------------------------------------------------

  // ignore: non_constant_identifier_names
  final RacHttpDownloadExecuteDart rac_http_download_execute;

  // Model registry refresh (T4.9) --------------------------------------------

  // ignore: non_constant_identifier_names
  final RacModelRegistryRefreshDart rac_model_registry_refresh;
}

/// Entry point for the typed commons FFI bindings.
class RacNative {
  RacNative._();

  static final RacBindings bindings =
      RacBindings(PlatformLoader.loadCommons());
}
