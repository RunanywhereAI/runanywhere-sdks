// ignore_for_file: non_constant_identifier_names

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
// Shared proto buffer ownership (rac_proto_buffer.h)
// ============================================================================

/// Matches `rac_proto_buffer_t`.
base class RacProtoBuffer extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> data;

  @ffi.Size()
  external int size;

  @ffi.Int32()
  external int status;

  external ffi.Pointer<Utf8> errorMessage;
}

typedef RacProtoBufferInitNative = ffi.Void Function(
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacProtoBufferInitDart = void Function(
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacProtoBufferFreeNative = ffi.Void Function(
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacProtoBufferFreeDart = void Function(
  ffi.Pointer<RacProtoBuffer>,
);

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
// Generated-proto modality APIs
// ============================================================================

typedef RacLlmGenerateProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacLlmGenerateProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacLlmGenerateStreamProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.NativeFunction<RacLlmStreamProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef RacLlmGenerateStreamProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.NativeFunction<RacLlmStreamProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacLlmCancelProtoNative = ffi.Int32 Function(
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacLlmCancelProtoDart = int Function(ffi.Pointer<RacProtoBuffer>);

typedef RacSttProtoPartialCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacSttTranscribeProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacSttTranscribeProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacSttTranscribeStreamProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.NativeFunction<RacSttProtoPartialCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef RacSttTranscribeStreamProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.NativeFunction<RacSttProtoPartialCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacTtsProtoVoiceCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacTtsProtoChunkCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacTtsListVoicesProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacTtsProtoVoiceCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef RacTtsListVoicesProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacTtsProtoVoiceCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacTtsSynthesizeProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacTtsSynthesizeProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacTtsSynthesizeStreamProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.NativeFunction<RacTtsProtoChunkCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef RacTtsSynthesizeStreamProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.NativeFunction<RacTtsProtoChunkCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacVadProtoActivityCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacVadConfigureProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef RacVadConfigureProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef RacVadProcessProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Float>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacVadProcessProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Float>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacHandleOutProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacHandleOutProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacVadSetActivityProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacVadProtoActivityCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef RacVadSetActivityProtoCallbackDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.NativeFunction<RacVadProtoActivityCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacVoiceAgentInitializeProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacVoiceAgentInitializeProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacVoiceAgentProcessTurnProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacVoiceAgentProcessTurnProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacCreateWithModelNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);
typedef RacCreateWithModelDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);

typedef RacCreateWithModelConfigNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);
typedef RacCreateWithModelConfigDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);

typedef RacCreateWithModelStructConfigNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);
typedef RacCreateWithModelStructConfigDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);

typedef RacDestroyHandleNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef RacDestroyHandleDart = void Function(ffi.Pointer<ffi.Void>);

typedef RacHandleStatusNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef RacHandleStatusDart = int Function(ffi.Pointer<ffi.Void>);

typedef RacHandleCapabilitiesNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void>,
);
typedef RacHandleCapabilitiesDart = int Function(ffi.Pointer<ffi.Void>);

typedef RacVlmInitializeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef RacVlmInitializeDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);

typedef RacVlmProcessProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacVlmProcessProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacVlmStreamProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacVlmProcessStreamProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.NativeFunction<RacVlmStreamProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacVlmProcessStreamProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.NativeFunction<RacVlmStreamProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacDiffusionInitializeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Void>,
);
typedef RacDiffusionInitializeDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Void>,
);

typedef RacHandleBytesToProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacHandleBytesToProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacDiffusionProgressProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacDiffusionGenerateWithProgressProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.NativeFunction<RacDiffusionProgressProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacDiffusionGenerateWithProgressProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.NativeFunction<RacDiffusionProgressProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacRagSessionCreateProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);
typedef RacRagSessionCreateProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);

typedef RacLoraRegistryGetNative = ffi.Pointer<ffi.Void> Function();
typedef RacLoraRegistryGetDart = ffi.Pointer<ffi.Void> Function();

typedef RacEmbeddingsInitializeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef RacEmbeddingsInitializeDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);

// ============================================================================
// Phase H HTTP client (rac_http_client.h)
// ============================================================================

/// Matches `rac_http_header_kv_t`.
base class RacHttpHeaderKv extends ffi.Struct {
  external ffi.Pointer<Utf8> name;
  external ffi.Pointer<Utf8> value;
}

/// Matches `rac_http_request_t`.
base class RacHttpRequest extends ffi.Struct {
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
base class RacHttpResponse extends ffi.Struct {
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
base class RacHttpDownloadRequest extends ffi.Struct {
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
base class RacModelRegistryRefreshOpts extends ffi.Struct {
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
// Model registry proto-byte API (rac_model_registry.h)
// ============================================================================

typedef RacModelRegistryRegisterProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef RacModelRegistryRegisterProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef RacModelRegistryUpdateProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef RacModelRegistryUpdateProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef RacModelRegistryGetProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);
typedef RacModelRegistryGetProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);

typedef RacModelRegistryListProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);
typedef RacModelRegistryListProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);

typedef RacModelRegistryQueryProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);
typedef RacModelRegistryQueryProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);

typedef RacModelRegistryListDownloadedProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);
typedef RacModelRegistryListDownloadedProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.Size>,
);

typedef RacModelRegistryRemoveProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef RacModelRegistryRemoveProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);

typedef RacModelRegistryProtoFreeNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
);
typedef RacModelRegistryProtoFreeDart = void Function(
  ffi.Pointer<ffi.Uint8>,
);

// ============================================================================
// Model lifecycle proto-byte API (rac_model_lifecycle.h)
// ============================================================================

typedef RacModelLifecycleLoadProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacModelLifecycleLoadProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacModelLifecycleRequestProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacModelLifecycleRequestProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacComponentLifecycleSnapshotProtoNative = ffi.Int32 Function(
  ffi.Uint32,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacComponentLifecycleSnapshotProtoDart = int Function(
  int,
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacModelLifecycleResetNative = ffi.Void Function();
typedef RacModelLifecycleResetDart = void Function();

// ============================================================================
// Storage analyzer proto-byte API (rac_storage_analyzer.h)
// ============================================================================

typedef RacStorageCalculateDirSizeNative = ffi.Int64 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Void>,
);

typedef RacStorageGetFileSizeNative = ffi.Int64 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Void>,
);

typedef RacStoragePathExistsNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Void>,
);

typedef RacStorageGetSpaceNative = ffi.Int64 Function(
  ffi.Pointer<ffi.Void>,
);

typedef RacStorageDeletePathNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Int32,
  ffi.Pointer<ffi.Void>,
);

typedef RacStorageIsModelLoadedNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Void>,
);

typedef RacStorageUnloadModelNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Void>,
);

/// Matches `rac_storage_callbacks_t`.
base class RacStorageCallbacks extends ffi.Struct {
  external ffi.Pointer<ffi.NativeFunction<RacStorageCalculateDirSizeNative>>
      calculateDirSize;
  external ffi.Pointer<ffi.NativeFunction<RacStorageGetFileSizeNative>>
      getFileSize;
  external ffi.Pointer<ffi.NativeFunction<RacStoragePathExistsNative>>
      pathExists;
  external ffi.Pointer<ffi.NativeFunction<RacStorageGetSpaceNative>>
      getAvailableSpace;
  external ffi.Pointer<ffi.NativeFunction<RacStorageGetSpaceNative>>
      getTotalSpace;
  external ffi.Pointer<ffi.NativeFunction<RacStorageDeletePathNative>>
      deletePath;
  external ffi.Pointer<ffi.NativeFunction<RacStorageIsModelLoadedNative>>
      isModelLoaded;
  external ffi.Pointer<ffi.NativeFunction<RacStorageUnloadModelNative>>
      unloadModel;
  external ffi.Pointer<ffi.Void> userData;
}

typedef RacStorageAnalyzerCreateNative = ffi.Int32 Function(
  ffi.Pointer<RacStorageCallbacks>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);
typedef RacStorageAnalyzerCreateDart = int Function(
  ffi.Pointer<RacStorageCallbacks>,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
);

typedef RacStorageAnalyzerDestroyNative = ffi.Void Function(
  ffi.Pointer<ffi.Void>,
);
typedef RacStorageAnalyzerDestroyDart = void Function(
  ffi.Pointer<ffi.Void>,
);

typedef RacStorageProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacStorageProtoDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

// ============================================================================
// Download proto-byte API (rac_download_orchestrator.h)
// ============================================================================

typedef RacDownloadProtoProgressCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacDownloadSetProgressProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.NativeFunction<RacDownloadProtoProgressCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef RacDownloadSetProgressProtoCallbackDart = int Function(
  ffi.Pointer<ffi.NativeFunction<RacDownloadProtoProgressCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacDownloadProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacDownloadProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

// ============================================================================
// SDK event stream proto-byte API (rac_sdk_event_stream.h)
// ============================================================================

typedef RacSdkEventCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef RacSdkEventSubscribeNative = ffi.Uint64 Function(
  ffi.Pointer<ffi.NativeFunction<RacSdkEventCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef RacSdkEventSubscribeDart = int Function(
  ffi.Pointer<ffi.NativeFunction<RacSdkEventCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef RacSdkEventUnsubscribeNative = ffi.Void Function(ffi.Uint64);
typedef RacSdkEventUnsubscribeDart = void Function(int);

typedef RacSdkEventPublishProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef RacSdkEventPublishProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef RacSdkEventPollNative = ffi.Int32 Function(
  ffi.Pointer<RacProtoBuffer>,
);
typedef RacSdkEventPollDart = int Function(
  ffi.Pointer<RacProtoBuffer>,
);

typedef RacSdkEventPublishFailureNative = ffi.Int32 Function(
  ffi.Int32,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Int32,
);
typedef RacSdkEventPublishFailureDart = int Function(
  int,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  int,
);

// ============================================================================
// Bindings facade
// ============================================================================

T? _lookupOptional<T extends Function>(T Function() lookup) {
  try {
    return lookup();
  } catch (_) {
    return null;
  }
}

/// Typed bindings for the commons C ABI surfaces this file owns.
class RacBindings {
  RacBindings(ffi.DynamicLibrary lib)
      : rac_proto_buffer_init = lib.lookupFunction<RacProtoBufferInitNative,
            RacProtoBufferInitDart>('rac_proto_buffer_init'),
        rac_proto_buffer_free = lib.lookupFunction<RacProtoBufferFreeNative,
            RacProtoBufferFreeDart>('rac_proto_buffer_free'),
        rac_voice_agent_set_proto_callback = lib.lookupFunction<
                RacVoiceAgentSetProtoCallbackNative,
                RacVoiceAgentSetProtoCallbackDart>(
            'rac_voice_agent_set_proto_callback'),
        rac_llm_set_stream_proto_callback = lib.lookupFunction<
                RacLlmSetStreamProtoCallbackNative,
                RacLlmSetStreamProtoCallbackDart>(
            'rac_llm_set_stream_proto_callback'),
        rac_llm_unset_stream_proto_callback = lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(
                ffi.Pointer<ffi.Void>)>('rac_llm_unset_stream_proto_callback'),
        rac_llm_generate_proto = _lookupOptional<RacLlmGenerateProtoDart>(
          () => lib.lookupFunction<RacLlmGenerateProtoNative,
              RacLlmGenerateProtoDart>('rac_llm_generate_proto'),
        ),
        rac_llm_generate_stream_proto =
            _lookupOptional<RacLlmGenerateStreamProtoDart>(
          () => lib.lookupFunction<RacLlmGenerateStreamProtoNative,
              RacLlmGenerateStreamProtoDart>('rac_llm_generate_stream_proto'),
        ),
        rac_llm_cancel_proto = _lookupOptional<RacLlmCancelProtoDart>(
          () => lib.lookupFunction<RacLlmCancelProtoNative,
              RacLlmCancelProtoDart>('rac_llm_cancel_proto'),
        ),
        rac_stt_component_transcribe_proto =
            _lookupOptional<RacSttTranscribeProtoDart>(
          () => lib.lookupFunction<RacSttTranscribeProtoNative,
              RacSttTranscribeProtoDart>(
            'rac_stt_component_transcribe_proto',
          ),
        ),
        rac_stt_component_transcribe_stream_proto =
            _lookupOptional<RacSttTranscribeStreamProtoDart>(
          () => lib.lookupFunction<RacSttTranscribeStreamProtoNative,
              RacSttTranscribeStreamProtoDart>(
            'rac_stt_component_transcribe_stream_proto',
          ),
        ),
        rac_tts_component_list_voices_proto =
            _lookupOptional<RacTtsListVoicesProtoDart>(
          () => lib.lookupFunction<RacTtsListVoicesProtoNative,
              RacTtsListVoicesProtoDart>(
            'rac_tts_component_list_voices_proto',
          ),
        ),
        rac_tts_component_synthesize_proto =
            _lookupOptional<RacTtsSynthesizeProtoDart>(
          () => lib.lookupFunction<RacTtsSynthesizeProtoNative,
              RacTtsSynthesizeProtoDart>(
            'rac_tts_component_synthesize_proto',
          ),
        ),
        rac_tts_component_synthesize_stream_proto =
            _lookupOptional<RacTtsSynthesizeStreamProtoDart>(
          () => lib.lookupFunction<RacTtsSynthesizeStreamProtoNative,
              RacTtsSynthesizeStreamProtoDart>(
            'rac_tts_component_synthesize_stream_proto',
          ),
        ),
        rac_vad_component_configure_proto =
            _lookupOptional<RacVadConfigureProtoDart>(
          () => lib.lookupFunction<RacVadConfigureProtoNative,
              RacVadConfigureProtoDart>(
            'rac_vad_component_configure_proto',
          ),
        ),
        rac_vad_component_process_proto =
            _lookupOptional<RacVadProcessProtoDart>(
          () => lib
              .lookupFunction<RacVadProcessProtoNative, RacVadProcessProtoDart>(
            'rac_vad_component_process_proto',
          ),
        ),
        rac_vad_component_get_statistics_proto =
            _lookupOptional<RacHandleOutProtoDart>(
          () => lib
              .lookupFunction<RacHandleOutProtoNative, RacHandleOutProtoDart>(
            'rac_vad_component_get_statistics_proto',
          ),
        ),
        rac_vad_component_set_activity_proto_callback =
            _lookupOptional<RacVadSetActivityProtoCallbackDart>(
          () => lib.lookupFunction<RacVadSetActivityProtoCallbackNative,
              RacVadSetActivityProtoCallbackDart>(
            'rac_vad_component_set_activity_proto_callback',
          ),
        ),
        rac_voice_agent_initialize_proto =
            _lookupOptional<RacVoiceAgentInitializeProtoDart>(
          () => lib.lookupFunction<RacVoiceAgentInitializeProtoNative,
              RacVoiceAgentInitializeProtoDart>(
            'rac_voice_agent_initialize_proto',
          ),
        ),
        rac_voice_agent_component_states_proto =
            _lookupOptional<RacHandleOutProtoDart>(
          () => lib
              .lookupFunction<RacHandleOutProtoNative, RacHandleOutProtoDart>(
            'rac_voice_agent_component_states_proto',
          ),
        ),
        rac_voice_agent_process_voice_turn_proto =
            _lookupOptional<RacVoiceAgentProcessTurnProtoDart>(
          () => lib.lookupFunction<RacVoiceAgentProcessTurnProtoNative,
              RacVoiceAgentProcessTurnProtoDart>(
            'rac_voice_agent_process_voice_turn_proto',
          ),
        ),
        rac_vlm_create = _lookupOptional<RacCreateWithModelDart>(
          () => lib.lookupFunction<RacCreateWithModelNative,
              RacCreateWithModelDart>('rac_vlm_create'),
        ),
        rac_vlm_initialize = _lookupOptional<RacVlmInitializeDart>(
          () =>
              lib.lookupFunction<RacVlmInitializeNative, RacVlmInitializeDart>(
                  'rac_vlm_initialize'),
        ),
        rac_vlm_destroy = _lookupOptional<RacDestroyHandleDart>(
          () =>
              lib.lookupFunction<RacDestroyHandleNative, RacDestroyHandleDart>(
                  'rac_vlm_destroy'),
        ),
        rac_vlm_process_proto = _lookupOptional<RacVlmProcessProtoDart>(
          () => lib.lookupFunction<RacVlmProcessProtoNative,
              RacVlmProcessProtoDart>('rac_vlm_process_proto'),
        ),
        rac_vlm_process_stream_proto =
            _lookupOptional<RacVlmProcessStreamProtoDart>(
          () => lib.lookupFunction<RacVlmProcessStreamProtoNative,
              RacVlmProcessStreamProtoDart>('rac_vlm_process_stream_proto'),
        ),
        rac_vlm_cancel_proto = _lookupOptional<RacHandleStatusDart>(
          () => lib.lookupFunction<RacHandleStatusNative, RacHandleStatusDart>(
            'rac_vlm_cancel_proto',
          ),
        ),
        rac_embeddings_create = _lookupOptional<RacCreateWithModelDart>(
          () => lib.lookupFunction<RacCreateWithModelNative,
              RacCreateWithModelDart>('rac_embeddings_create'),
        ),
        rac_embeddings_create_with_config =
            _lookupOptional<RacCreateWithModelConfigDart>(
          () => lib.lookupFunction<RacCreateWithModelConfigNative,
              RacCreateWithModelConfigDart>(
            'rac_embeddings_create_with_config',
          ),
        ),
        rac_embeddings_initialize =
            _lookupOptional<RacEmbeddingsInitializeDart>(
          () => lib.lookupFunction<RacEmbeddingsInitializeNative,
              RacEmbeddingsInitializeDart>('rac_embeddings_initialize'),
        ),
        rac_embeddings_embed_batch_proto =
            _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>(
            'rac_embeddings_embed_batch_proto',
          ),
        ),
        rac_embeddings_destroy = _lookupOptional<RacDestroyHandleDart>(
          () =>
              lib.lookupFunction<RacDestroyHandleNative, RacDestroyHandleDart>(
                  'rac_embeddings_destroy'),
        ),
        rac_diffusion_create = _lookupOptional<RacCreateWithModelDart>(
          () => lib.lookupFunction<RacCreateWithModelNative,
              RacCreateWithModelDart>('rac_diffusion_create'),
        ),
        rac_diffusion_create_with_config =
            _lookupOptional<RacCreateWithModelStructConfigDart>(
          () => lib.lookupFunction<RacCreateWithModelStructConfigNative,
              RacCreateWithModelStructConfigDart>(
            'rac_diffusion_create_with_config',
          ),
        ),
        rac_diffusion_initialize = _lookupOptional<RacDiffusionInitializeDart>(
          () => lib.lookupFunction<RacDiffusionInitializeNative,
              RacDiffusionInitializeDart>('rac_diffusion_initialize'),
        ),
        rac_diffusion_generate_proto =
            _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>('rac_diffusion_generate_proto'),
        ),
        rac_diffusion_generate_with_progress_proto =
            _lookupOptional<RacDiffusionGenerateWithProgressProtoDart>(
          () => lib.lookupFunction<RacDiffusionGenerateWithProgressProtoNative,
              RacDiffusionGenerateWithProgressProtoDart>(
            'rac_diffusion_generate_with_progress_proto',
          ),
        ),
        rac_diffusion_cancel_proto = _lookupOptional<RacHandleStatusDart>(
          () => lib.lookupFunction<RacHandleStatusNative, RacHandleStatusDart>(
            'rac_diffusion_cancel_proto',
          ),
        ),
        rac_diffusion_get_capabilities =
            _lookupOptional<RacHandleCapabilitiesDart>(
          () => lib.lookupFunction<RacHandleCapabilitiesNative,
              RacHandleCapabilitiesDart>('rac_diffusion_get_capabilities'),
        ),
        rac_diffusion_destroy = _lookupOptional<RacDestroyHandleDart>(
          () =>
              lib.lookupFunction<RacDestroyHandleNative, RacDestroyHandleDart>(
                  'rac_diffusion_destroy'),
        ),
        rac_rag_session_create_proto =
            _lookupOptional<RacRagSessionCreateProtoDart>(
          () => lib.lookupFunction<RacRagSessionCreateProtoNative,
              RacRagSessionCreateProtoDart>(
            'rac_rag_session_create_proto',
          ),
        ),
        rac_rag_session_destroy_proto = _lookupOptional<RacDestroyHandleDart>(
          () =>
              lib.lookupFunction<RacDestroyHandleNative, RacDestroyHandleDart>(
                  'rac_rag_session_destroy_proto'),
        ),
        rac_rag_ingest_proto = _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>('rac_rag_ingest_proto'),
        ),
        rac_rag_query_proto = _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>('rac_rag_query_proto'),
        ),
        rac_rag_clear_proto = _lookupOptional<RacHandleOutProtoDart>(
          () => lib.lookupFunction<RacHandleOutProtoNative,
              RacHandleOutProtoDart>('rac_rag_clear_proto'),
        ),
        rac_rag_stats_proto = _lookupOptional<RacHandleOutProtoDart>(
          () => lib.lookupFunction<RacHandleOutProtoNative,
              RacHandleOutProtoDart>('rac_rag_stats_proto'),
        ),
        rac_get_lora_registry = _lookupOptional<RacLoraRegistryGetDart>(
          () => lib.lookupFunction<RacLoraRegistryGetNative,
              RacLoraRegistryGetDart>('rac_get_lora_registry'),
        ),
        rac_lora_register_proto = _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>('rac_lora_register_proto'),
        ),
        rac_lora_compatibility_proto =
            _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>('rac_lora_compatibility_proto'),
        ),
        rac_lora_load_proto = _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>('rac_lora_load_proto'),
        ),
        rac_lora_remove_proto = _lookupOptional<RacHandleBytesToProtoDart>(
          () => lib.lookupFunction<RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart>('rac_lora_remove_proto'),
        ),
        rac_lora_clear_proto = _lookupOptional<RacHandleOutProtoDart>(
          () => lib.lookupFunction<RacHandleOutProtoNative,
              RacHandleOutProtoDart>('rac_lora_clear_proto'),
        ),
        rac_http_client_create = lib.lookupFunction<RacHttpClientCreateNative,
            RacHttpClientCreateDart>('rac_http_client_create'),
        rac_http_client_destroy = lib.lookupFunction<RacHttpClientDestroyNative,
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
            RacModelRegistryRefreshDart>('rac_model_registry_refresh'),
        rac_model_registry_register_proto =
            _lookupOptional<RacModelRegistryRegisterProtoDart>(
          () => lib.lookupFunction<RacModelRegistryRegisterProtoNative,
              RacModelRegistryRegisterProtoDart>(
            'rac_model_registry_register_proto',
          ),
        ),
        rac_model_registry_update_proto =
            _lookupOptional<RacModelRegistryUpdateProtoDart>(
          () => lib.lookupFunction<RacModelRegistryUpdateProtoNative,
              RacModelRegistryUpdateProtoDart>(
            'rac_model_registry_update_proto',
          ),
        ),
        rac_model_registry_get_proto =
            _lookupOptional<RacModelRegistryGetProtoDart>(
          () => lib.lookupFunction<RacModelRegistryGetProtoNative,
              RacModelRegistryGetProtoDart>(
            'rac_model_registry_get_proto',
          ),
        ),
        rac_model_registry_list_proto =
            _lookupOptional<RacModelRegistryListProtoDart>(
          () => lib.lookupFunction<RacModelRegistryListProtoNative,
              RacModelRegistryListProtoDart>(
            'rac_model_registry_list_proto',
          ),
        ),
        rac_model_registry_query_proto =
            _lookupOptional<RacModelRegistryQueryProtoDart>(
          () => lib.lookupFunction<RacModelRegistryQueryProtoNative,
              RacModelRegistryQueryProtoDart>(
            'rac_model_registry_query_proto',
          ),
        ),
        rac_model_registry_list_downloaded_proto =
            _lookupOptional<RacModelRegistryListDownloadedProtoDart>(
          () => lib.lookupFunction<RacModelRegistryListDownloadedProtoNative,
              RacModelRegistryListDownloadedProtoDart>(
            'rac_model_registry_list_downloaded_proto',
          ),
        ),
        rac_model_registry_remove_proto =
            _lookupOptional<RacModelRegistryRemoveProtoDart>(
          () => lib.lookupFunction<RacModelRegistryRemoveProtoNative,
              RacModelRegistryRemoveProtoDart>(
            'rac_model_registry_remove_proto',
          ),
        ),
        rac_model_registry_proto_free =
            _lookupOptional<RacModelRegistryProtoFreeDart>(
          () => lib.lookupFunction<RacModelRegistryProtoFreeNative,
              RacModelRegistryProtoFreeDart>(
            'rac_model_registry_proto_free',
          ),
        ),
        rac_model_lifecycle_load_proto =
            _lookupOptional<RacModelLifecycleLoadProtoDart>(
          () => lib.lookupFunction<RacModelLifecycleLoadProtoNative,
              RacModelLifecycleLoadProtoDart>(
            'rac_model_lifecycle_load_proto',
          ),
        ),
        rac_model_lifecycle_unload_proto =
            _lookupOptional<RacModelLifecycleRequestProtoDart>(
          () => lib.lookupFunction<RacModelLifecycleRequestProtoNative,
              RacModelLifecycleRequestProtoDart>(
            'rac_model_lifecycle_unload_proto',
          ),
        ),
        rac_model_lifecycle_current_model_proto =
            _lookupOptional<RacModelLifecycleRequestProtoDart>(
          () => lib.lookupFunction<RacModelLifecycleRequestProtoNative,
              RacModelLifecycleRequestProtoDart>(
            'rac_model_lifecycle_current_model_proto',
          ),
        ),
        rac_component_lifecycle_snapshot_proto =
            _lookupOptional<RacComponentLifecycleSnapshotProtoDart>(
          () => lib.lookupFunction<RacComponentLifecycleSnapshotProtoNative,
              RacComponentLifecycleSnapshotProtoDart>(
            'rac_component_lifecycle_snapshot_proto',
          ),
        ),
        rac_model_lifecycle_reset = _lookupOptional<RacModelLifecycleResetDart>(
          () => lib.lookupFunction<RacModelLifecycleResetNative,
              RacModelLifecycleResetDart>(
            'rac_model_lifecycle_reset',
          ),
        ),
        rac_storage_analyzer_create =
            _lookupOptional<RacStorageAnalyzerCreateDart>(
          () => lib.lookupFunction<RacStorageAnalyzerCreateNative,
              RacStorageAnalyzerCreateDart>('rac_storage_analyzer_create'),
        ),
        rac_storage_analyzer_destroy =
            _lookupOptional<RacStorageAnalyzerDestroyDart>(
          () => lib.lookupFunction<RacStorageAnalyzerDestroyNative,
              RacStorageAnalyzerDestroyDart>('rac_storage_analyzer_destroy'),
        ),
        rac_storage_analyzer_info_proto = _lookupOptional<RacStorageProtoDart>(
          () => lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
            'rac_storage_analyzer_info_proto',
          ),
        ),
        rac_storage_analyzer_availability_proto =
            _lookupOptional<RacStorageProtoDart>(
          () => lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
            'rac_storage_analyzer_availability_proto',
          ),
        ),
        rac_storage_analyzer_delete_plan_proto =
            _lookupOptional<RacStorageProtoDart>(
          () => lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
            'rac_storage_analyzer_delete_plan_proto',
          ),
        ),
        rac_storage_analyzer_delete_proto =
            _lookupOptional<RacStorageProtoDart>(
          () => lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
            'rac_storage_analyzer_delete_proto',
          ),
        ),
        rac_download_set_progress_proto_callback =
            _lookupOptional<RacDownloadSetProgressProtoCallbackDart>(
          () => lib.lookupFunction<RacDownloadSetProgressProtoCallbackNative,
              RacDownloadSetProgressProtoCallbackDart>(
            'rac_download_set_progress_proto_callback',
          ),
        ),
        rac_download_plan_proto = _lookupOptional<RacDownloadProtoDart>(
          () =>
              lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
            'rac_download_plan_proto',
          ),
        ),
        rac_download_start_proto = _lookupOptional<RacDownloadProtoDart>(
          () =>
              lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
            'rac_download_start_proto',
          ),
        ),
        rac_download_cancel_proto = _lookupOptional<RacDownloadProtoDart>(
          () =>
              lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
            'rac_download_cancel_proto',
          ),
        ),
        rac_download_resume_proto = _lookupOptional<RacDownloadProtoDart>(
          () =>
              lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
            'rac_download_resume_proto',
          ),
        ),
        rac_download_progress_poll_proto =
            _lookupOptional<RacDownloadProtoDart>(
          () =>
              lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
            'rac_download_progress_poll_proto',
          ),
        ),
        rac_sdk_event_subscribe = _lookupOptional<RacSdkEventSubscribeDart>(
          () => lib.lookupFunction<RacSdkEventSubscribeNative,
              RacSdkEventSubscribeDart>('rac_sdk_event_subscribe'),
        ),
        rac_sdk_event_unsubscribe = _lookupOptional<RacSdkEventUnsubscribeDart>(
          () => lib.lookupFunction<RacSdkEventUnsubscribeNative,
              RacSdkEventUnsubscribeDart>('rac_sdk_event_unsubscribe'),
        ),
        rac_sdk_event_publish_proto =
            _lookupOptional<RacSdkEventPublishProtoDart>(
          () => lib.lookupFunction<RacSdkEventPublishProtoNative,
              RacSdkEventPublishProtoDart>('rac_sdk_event_publish_proto'),
        ),
        rac_sdk_event_poll = _lookupOptional<RacSdkEventPollDart>(
          () => lib.lookupFunction<RacSdkEventPollNative, RacSdkEventPollDart>(
              'rac_sdk_event_poll'),
        ),
        rac_sdk_event_publish_failure =
            _lookupOptional<RacSdkEventPublishFailureDart>(
          () => lib.lookupFunction<RacSdkEventPublishFailureNative,
              RacSdkEventPublishFailureDart>(
            'rac_sdk_event_publish_failure',
          ),
        );

  // Shared proto buffers -----------------------------------------------------

  final RacProtoBufferInitDart rac_proto_buffer_init;

  final RacProtoBufferFreeDart rac_proto_buffer_free;

  // Streaming callbacks ------------------------------------------------------

  final RacVoiceAgentSetProtoCallbackDart rac_voice_agent_set_proto_callback;

  final RacLlmSetStreamProtoCallbackDart rac_llm_set_stream_proto_callback;

  final int Function(ffi.Pointer<ffi.Void>) rac_llm_unset_stream_proto_callback;

  // Generated-proto modality APIs -------------------------------------------

  final RacLlmGenerateProtoDart? rac_llm_generate_proto;

  final RacLlmGenerateStreamProtoDart? rac_llm_generate_stream_proto;

  final RacLlmCancelProtoDart? rac_llm_cancel_proto;

  final RacSttTranscribeProtoDart? rac_stt_component_transcribe_proto;

  final RacSttTranscribeStreamProtoDart?
      rac_stt_component_transcribe_stream_proto;

  final RacTtsListVoicesProtoDart? rac_tts_component_list_voices_proto;

  final RacTtsSynthesizeProtoDart? rac_tts_component_synthesize_proto;

  final RacTtsSynthesizeStreamProtoDart?
      rac_tts_component_synthesize_stream_proto;

  final RacVadConfigureProtoDart? rac_vad_component_configure_proto;

  final RacVadProcessProtoDart? rac_vad_component_process_proto;

  final RacHandleOutProtoDart? rac_vad_component_get_statistics_proto;

  final RacVadSetActivityProtoCallbackDart?
      rac_vad_component_set_activity_proto_callback;

  final RacVoiceAgentInitializeProtoDart? rac_voice_agent_initialize_proto;

  final RacHandleOutProtoDart? rac_voice_agent_component_states_proto;

  final RacVoiceAgentProcessTurnProtoDart?
      rac_voice_agent_process_voice_turn_proto;

  final RacCreateWithModelDart? rac_vlm_create;

  final RacVlmInitializeDart? rac_vlm_initialize;

  final RacDestroyHandleDart? rac_vlm_destroy;

  final RacVlmProcessProtoDart? rac_vlm_process_proto;

  final RacVlmProcessStreamProtoDart? rac_vlm_process_stream_proto;

  final RacHandleStatusDart? rac_vlm_cancel_proto;

  final RacCreateWithModelDart? rac_embeddings_create;

  final RacCreateWithModelConfigDart? rac_embeddings_create_with_config;

  final RacEmbeddingsInitializeDart? rac_embeddings_initialize;

  final RacHandleBytesToProtoDart? rac_embeddings_embed_batch_proto;

  final RacDestroyHandleDart? rac_embeddings_destroy;

  final RacCreateWithModelDart? rac_diffusion_create;

  final RacCreateWithModelStructConfigDart? rac_diffusion_create_with_config;

  final RacDiffusionInitializeDart? rac_diffusion_initialize;

  final RacHandleBytesToProtoDart? rac_diffusion_generate_proto;

  final RacDiffusionGenerateWithProgressProtoDart?
      rac_diffusion_generate_with_progress_proto;

  final RacHandleStatusDart? rac_diffusion_cancel_proto;

  final RacHandleCapabilitiesDart? rac_diffusion_get_capabilities;

  final RacDestroyHandleDart? rac_diffusion_destroy;

  final RacRagSessionCreateProtoDart? rac_rag_session_create_proto;

  final RacDestroyHandleDart? rac_rag_session_destroy_proto;

  final RacHandleBytesToProtoDart? rac_rag_ingest_proto;

  final RacHandleBytesToProtoDart? rac_rag_query_proto;

  final RacHandleOutProtoDart? rac_rag_clear_proto;

  final RacHandleOutProtoDart? rac_rag_stats_proto;

  final RacLoraRegistryGetDart? rac_get_lora_registry;

  final RacHandleBytesToProtoDart? rac_lora_register_proto;

  final RacHandleBytesToProtoDart? rac_lora_compatibility_proto;

  final RacHandleBytesToProtoDart? rac_lora_load_proto;

  final RacHandleBytesToProtoDart? rac_lora_remove_proto;

  final RacHandleOutProtoDart? rac_lora_clear_proto;

  // HTTP client --------------------------------------------------------------

  final RacHttpClientCreateDart rac_http_client_create;

  final RacHttpClientDestroyDart rac_http_client_destroy;

  final RacHttpRequestSendDart rac_http_request_send;

  final RacHttpResponseFreeDart rac_http_response_free;

  // HTTP download ------------------------------------------------------------

  final RacHttpDownloadExecuteDart rac_http_download_execute;

  // Model registry refresh (T4.9) --------------------------------------------

  final RacModelRegistryRefreshDart rac_model_registry_refresh;

  // Model registry proto-byte API --------------------------------------------

  final RacModelRegistryRegisterProtoDart? rac_model_registry_register_proto;

  final RacModelRegistryUpdateProtoDart? rac_model_registry_update_proto;

  final RacModelRegistryGetProtoDart? rac_model_registry_get_proto;

  final RacModelRegistryListProtoDart? rac_model_registry_list_proto;

  final RacModelRegistryQueryProtoDart? rac_model_registry_query_proto;

  final RacModelRegistryListDownloadedProtoDart?
      rac_model_registry_list_downloaded_proto;

  final RacModelRegistryRemoveProtoDart? rac_model_registry_remove_proto;

  final RacModelRegistryProtoFreeDart? rac_model_registry_proto_free;

  // Model lifecycle proto-byte API ------------------------------------------

  final RacModelLifecycleLoadProtoDart? rac_model_lifecycle_load_proto;

  final RacModelLifecycleRequestProtoDart? rac_model_lifecycle_unload_proto;

  final RacModelLifecycleRequestProtoDart?
      rac_model_lifecycle_current_model_proto;

  final RacComponentLifecycleSnapshotProtoDart?
      rac_component_lifecycle_snapshot_proto;

  final RacModelLifecycleResetDart? rac_model_lifecycle_reset;

  // Storage analyzer proto-byte API -----------------------------------------

  final RacStorageAnalyzerCreateDart? rac_storage_analyzer_create;

  final RacStorageAnalyzerDestroyDart? rac_storage_analyzer_destroy;

  final RacStorageProtoDart? rac_storage_analyzer_info_proto;

  final RacStorageProtoDart? rac_storage_analyzer_availability_proto;

  final RacStorageProtoDart? rac_storage_analyzer_delete_plan_proto;

  final RacStorageProtoDart? rac_storage_analyzer_delete_proto;

  // Download proto-byte API --------------------------------------------------

  final RacDownloadSetProgressProtoCallbackDart?
      rac_download_set_progress_proto_callback;

  final RacDownloadProtoDart? rac_download_plan_proto;

  final RacDownloadProtoDart? rac_download_start_proto;

  final RacDownloadProtoDart? rac_download_cancel_proto;

  final RacDownloadProtoDart? rac_download_resume_proto;

  final RacDownloadProtoDart? rac_download_progress_poll_proto;

  // SDK event stream proto-byte API -----------------------------------------

  final RacSdkEventSubscribeDart? rac_sdk_event_subscribe;

  final RacSdkEventUnsubscribeDart? rac_sdk_event_unsubscribe;

  final RacSdkEventPublishProtoDart? rac_sdk_event_publish_proto;

  final RacSdkEventPollDart? rac_sdk_event_poll;

  final RacSdkEventPublishFailureDart? rac_sdk_event_publish_failure;
}

/// Entry point for the typed commons FFI bindings.
class RacNative {
  RacNative._();

  static final RacBindings bindings = RacBindings(PlatformLoader.loadCommons());
}
