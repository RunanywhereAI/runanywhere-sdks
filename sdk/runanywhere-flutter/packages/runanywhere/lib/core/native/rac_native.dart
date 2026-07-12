// ignore_for_file: non_constant_identifier_names

// SPDX-License-Identifier: Apache-2.0
//
// rac_native.dart — typed Dart FFI bindings for commons C ABI surfaces.
//
// Scope today:
//   * Streaming proto callbacks (voice agent, LLM).
//   * HTTP client (`rac_http_client_*`, `rac_http_request_send`,
//     `rac_http_response_free`, `rac_http_request_stream`) and the
//     blocking file download (`rac_http_download_execute`). These
//     replace the per-SDK hand-rolled HTTP transports.
//
// Structure: the public `RacBindings` class holds FFI lookups as final
// fields; `RacNative.bindings` is the shared singleton wrapping
// `PlatformLoader.loadCommons()`.

library;

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

typedef RacProtoBufferInitNative =
    ffi.Void Function(ffi.Pointer<RacProtoBuffer>);
typedef RacProtoBufferInitDart = void Function(ffi.Pointer<RacProtoBuffer>);

typedef RacProtoBufferFreeNative =
    ffi.Void Function(ffi.Pointer<RacProtoBuffer>);
typedef RacProtoBufferFreeDart = void Function(ffi.Pointer<RacProtoBuffer>);

// ============================================================================
// Voice agent + LLM proto streaming
// ============================================================================

/// Matches `rac_voice_agent_proto_event_callback_fn` in
/// `rac/features/voice_agent/rac_voice_event_abi.h`.
typedef RacVoiceAgentProtoEventCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacVoiceAgentSetProtoCallbackNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacVoiceAgentSetProtoCallbackDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

/// Matches `rac_llm_stream_proto_callback_fn` in
/// `rac/features/llm/rac_llm_stream.h`.
typedef RacLlmStreamProtoCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

// ============================================================================
// Generated-proto modality APIs
// ============================================================================

typedef RacLlmGenerateProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacLlmGenerateProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

typedef RacLlmGenerateStreamProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.NativeFunction<RacLlmStreamProtoCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacLlmGenerateStreamProtoDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacLlmStreamProtoCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

/// Matches `bool Dart_PostCObject(Dart_Port, Dart_CObject*)`.
typedef RacDartPostCObjectNative =
    ffi.Int8 Function(ffi.Int64, ffi.Pointer<ffi.Dart_CObject>);

/// Flutter platform helper that copies LLM stream events natively and posts
/// them to a Dart ReceivePort. Exported by the Flutter pod/helper library,
/// not by RACommons.
typedef RaFlutterLlmGenerateStreamNativePortNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Int64,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );
typedef RaFlutterLlmGenerateStreamNativePortDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );

/// Flutter platform helper that copies VLM stream events natively and posts
/// them to a Dart ReceivePort. Exported by the Flutter pod/helper library,
/// not by RACommons.
typedef RaFlutterVlmStreamNativePortNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Int64,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );
typedef RaFlutterVlmStreamNativePortDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );

/// Flutter platform helper that copies TTS stream events natively and posts
/// them to a Dart ReceivePort. Exported by the Flutter pod/helper library,
/// not by RACommons.
typedef RaFlutterTtsSynthesizeStreamNativePortNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Int64,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );
typedef RaFlutterTtsSynthesizeStreamNativePortDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );

/// Flutter platform helper that copies voice-agent turn events natively and
/// posts them to a Dart ReceivePort. Exported by the Flutter pod/helper
/// library, not by RACommons.
typedef RaFlutterVoiceAgentProcessTurnNativePortNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Int64,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );
typedef RaFlutterVoiceAgentProcessTurnNativePortDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );

/// Flutter platform helper that registers the raw voice-agent handle callback
/// through a Dart native port. Exported by the Flutter pod/helper library,
/// not by RACommons.
typedef RaFlutterVoiceAgentSetProtoCallbackNativePortNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int64,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );
typedef RaFlutterVoiceAgentSetProtoCallbackNativePortDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );

typedef RaFlutterVoiceAgentUnsetProtoCallbackNativePortNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef RaFlutterVoiceAgentUnsetProtoCallbackNativePortDart =
    int Function(ffi.Pointer<ffi.Void>);

typedef RacLlmCancelProtoNative =
    ffi.Int32 Function(ffi.Pointer<RacProtoBuffer>);
typedef RacLlmCancelProtoDart = int Function(ffi.Pointer<RacProtoBuffer>);

typedef RacLifecycleRequestProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacLifecycleRequestProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

typedef RacSttProtoPartialCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacSttTranscribeProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacSttTranscribeProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacSttTranscribeStreamProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.NativeFunction<RacSttProtoPartialCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacSttTranscribeStreamProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacSttProtoPartialCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacTtsProtoVoiceCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacTtsProtoChunkCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacTtsListVoicesProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<RacTtsProtoVoiceCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacTtsListVoicesProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<RacTtsProtoVoiceCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacTtsSynthesizeProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacTtsSynthesizeProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacTtsSynthesizeStreamProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.NativeFunction<RacTtsProtoChunkCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacTtsSynthesizeStreamProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacTtsProtoChunkCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

/// Native callback signature for `rac_tts_lifecycle_stream_event_callback_fn`.
typedef RacTtsStreamEventCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacTtsSynthesizeStreamLifecycleProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.NativeFunction<RacTtsStreamEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacTtsSynthesizeStreamLifecycleProtoDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacTtsStreamEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

/// Single-arg out-only proto-buffer ABI (used by tts_stop_lifecycle /
/// vad_start_lifecycle / vad_stop_lifecycle / vad_reset_lifecycle).
typedef RacOutOnlyProtoNative = ffi.Int32 Function(ffi.Pointer<RacProtoBuffer>);
typedef RacOutOnlyProtoDart = int Function(ffi.Pointer<RacProtoBuffer>);

/// `rac_result_to_proto_error(rac_result_t code, rac_proto_buffer_t* out)` —
/// canonical mapping from a signed C ABI error code to a serialized
/// `runanywhere.v1.SDKError` proto buffer.
typedef RacResultToProtoErrorNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<RacProtoBuffer>);
typedef RacResultToProtoErrorDart =
    int Function(int, ffi.Pointer<RacProtoBuffer>);

/// `void (*)(void)` quiesce ABI exposed by every modality stream header
/// (rac_llm_stream.h, rac_stt_stream.h, rac_tts_stream.h, rac_vad_stream.h,
/// rac_diffusion_stream.h, rac_vlm_service.h, voice_agent). Callers spin-wait
/// until all in-flight proto-byte stream dispatches have returned before
/// freeing user_data passed to the matching set_*_callback ABI.
typedef RacProtoQuiesceNative = ffi.Void Function();
typedef RacProtoQuiesceDart = void Function();

typedef RacVadProtoActivityCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacVadConfigureProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef RacVadConfigureProtoDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int);

typedef RacVadProcessProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Float>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacVadProcessProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Float>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacHandleOutProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<RacProtoBuffer>);
typedef RacHandleOutProtoDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<RacProtoBuffer>);

typedef RacVadSetActivityProtoCallbackNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<RacVadProtoActivityCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacVadSetActivityProtoCallbackDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.NativeFunction<RacVadProtoActivityCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacVoiceAgentInitializeProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacVoiceAgentInitializeProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacVoiceAgentProcessTurnProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacVoiceAgentProcessTurnProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacDestroyHandleNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef RacDestroyHandleDart = void Function(ffi.Pointer<ffi.Void>);

typedef RacHandleBytesToProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacHandleBytesToProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacRagSessionCreateProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
    );
typedef RacRagSessionCreateProtoDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
    );

typedef RacLoraRegistryGetNative = ffi.Pointer<ffi.Void> Function();
typedef RacLoraRegistryGetDart = ffi.Pointer<ffi.Void> Function();

// ============================================================================
// Tool-calling proto APIs
// ============================================================================

typedef RacToolCallProtoRequestNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacToolCallProtoRequestDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

/// `void (*)(const uint8_t*, size_t, void*)` matching
/// `rac_tool_calling_session_event_callback_fn`.
typedef RacToolCallingSessionEventCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

/// `void (*)(uint64_t, void*)` matching
/// `rac_tool_calling_handle_published_callback_fn`.
typedef RacToolCallingHandlePublishedCallbackNative =
    ffi.Void Function(ffi.Uint64, ffi.Pointer<ffi.Void>);

typedef RacToolCallingSessionCreateProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.NativeFunction<RacToolCallingSessionEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<
        ffi.NativeFunction<RacToolCallingHandlePublishedCallbackNative>
      >,
      ffi.Pointer<ffi.Void>,
    );
typedef RacToolCallingSessionCreateProtoDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacToolCallingSessionEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<
        ffi.NativeFunction<RacToolCallingHandlePublishedCallbackNative>
      >,
      ffi.Pointer<ffi.Void>,
    );

typedef RacToolCallingSessionStepWithResultProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef RacToolCallingSessionStepWithResultProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int);

typedef RacToolCallingSessionDestroyProtoNative =
    ffi.Int32 Function(ffi.Uint64);
typedef RacToolCallingSessionDestroyProtoDart = int Function(int);

// Cancel ABI for the tool-calling session.
typedef RacToolCallingSessionCancelProtoNative = ffi.Int32 Function(ffi.Uint64);
typedef RacToolCallingSessionCancelProtoDart = int Function(int);

// ============================================================================
// Model format + artifact inference proto APIs
// ============================================================================

typedef RacModelFormatFromUrlProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacModelFormatFromUrlProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

typedef RacArtifactInferFromUrlProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacArtifactInferFromUrlProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

// ---------------------------------------------------------------------------
// Chunk-feed streaming STT sessions (rac_stt_stream.h). Mirrors Swift
// STTStreamSessionABI in CppBridge+STT.swift: register a per-handle proto
// callback, start a session (serialized STTOptions in, session id out), feed
// PCM frames, then stop (flush final) or cancel (drop). Teardown follows the
// header contract: unset callback → rac_stt_proto_quiesce() → free user_data.
// ---------------------------------------------------------------------------

typedef RacSttComponentLoadModelNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
    );
typedef RacSttComponentLoadModelDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
    );

/// Flutter platform helper that registers an STT stream callback which posts
/// copied events to a Dart ReceivePort. Exported by the Flutter pod/helper
/// library, not by RACommons.
typedef RaFlutterSttSetStreamNativePortNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int64,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );
typedef RaFlutterSttSetStreamNativePortDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacDartPostCObjectNative>>,
    );

typedef RaFlutterSttUnsetStreamNativePortNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef RaFlutterSttUnsetStreamNativePortDart =
    int Function(ffi.Pointer<ffi.Void>);

typedef RacSttStreamStartProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Uint64>,
    );
typedef RacSttStreamStartProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint64>,
    );

typedef RacSttStreamFeedAudioProtoNative =
    ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef RacSttStreamFeedAudioProtoDart =
    int Function(int, ffi.Pointer<ffi.Uint8>, int);

typedef RacSttStreamFinishProtoNative = ffi.Int32 Function(ffi.Uint64);
typedef RacSttStreamFinishProtoDart = int Function(int);

// ============================================================================
// Voice agent proto APIs (session + helpers + lifecycle-owned handle)
// ============================================================================

typedef RacVoiceAgentProcessTurnProto2Native =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacVoiceAgentProcessTurnProto2Dart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.NativeFunction<RacVoiceAgentProtoEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacVoiceAgentCancelTurnProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef RacVoiceAgentCancelTurnProtoDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int);

typedef RacVoiceAgentHelperProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacVoiceAgentHelperProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacVoiceAgentComponentCreateProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
    );
typedef RacVoiceAgentComponentCreateProtoDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
    );

typedef RacVoiceAgentComponentDestroyProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef RacVoiceAgentComponentDestroyProtoDart =
    int Function(ffi.Pointer<ffi.Void>);

// ============================================================================
// HTTP client (rac_http_client.h)
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

typedef RacHttpClientCreateNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Pointer<ffi.Void>>);
typedef RacHttpClientCreateDart =
    int Function(ffi.Pointer<ffi.Pointer<ffi.Void>>);

typedef RacHttpClientDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef RacHttpClientDestroyDart = void Function(ffi.Pointer<ffi.Void>);

typedef RacHttpRequestSendNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<RacHttpRequest>,
      ffi.Pointer<RacHttpResponse>,
    );
typedef RacHttpRequestSendDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<RacHttpRequest>,
      ffi.Pointer<RacHttpResponse>,
    );

typedef RacHttpResponseFreeNative =
    ffi.Void Function(ffi.Pointer<RacHttpResponse>);
typedef RacHttpResponseFreeDart = void Function(ffi.Pointer<RacHttpResponse>);

/// Matches `rac_result_t rac_http_default_headers(const rac_http_header_kv_t** out_kvs, size_t* out_count)`.
///
/// The returned array is statically allocated inside commons — DO NOT free.
typedef RacHttpDefaultHeadersNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Pointer<RacHttpHeaderKv>>,
      ffi.Pointer<ffi.Size>,
    );
typedef RacHttpDefaultHeadersDart =
    int Function(
      ffi.Pointer<ffi.Pointer<RacHttpHeaderKv>>,
      ffi.Pointer<ffi.Size>,
    );

// ============================================================================
// HTTP download (rac_http_download.h)
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
typedef RacHttpDownloadProgressNative =
    ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Pointer<ffi.Void>);

typedef RacHttpDownloadExecuteNative =
    ffi.Int32 Function(
      ffi.Pointer<RacHttpDownloadRequest>,
      ffi.Pointer<ffi.NativeFunction<RacHttpDownloadProgressNative>>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Int32>,
    );
typedef RacHttpDownloadExecuteDart =
    int Function(
      ffi.Pointer<RacHttpDownloadRequest>,
      ffi.Pointer<ffi.NativeFunction<RacHttpDownloadProgressNative>>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Int32>,
    );

// ============================================================================
// Model registry proto-byte API (rac_model_registry.h)
// ============================================================================
//
// Refresh is part of the proto-byte API: the only entry point is
// `rac_model_registry_refresh_proto` (handle, ModelRegistryRefreshRequest
// bytes, size, out ModelRegistryRefreshResult). It reuses the shared
// `RacHandleBytesToProto` typedef.

typedef RacModelRegistryRegisterProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef RacModelRegistryRegisterProtoDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int);

typedef RacModelRegistryUpdateProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef RacModelRegistryUpdateProtoDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int);

typedef RacModelRegistryGetProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );
typedef RacModelRegistryGetProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );

typedef RacModelRegistryListProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );
typedef RacModelRegistryListProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );

typedef RacModelRegistryQueryProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );
typedef RacModelRegistryQueryProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );

typedef RacModelRegistryListDownloadedProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );
typedef RacModelRegistryListDownloadedProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.Size>,
    );

typedef RacModelRegistryRemoveProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>);
typedef RacModelRegistryRemoveProtoDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>);

typedef RacModelRegistryProtoFreeNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>);
typedef RacModelRegistryProtoFreeDart = void Function(ffi.Pointer<ffi.Uint8>);

/// Matches `rac_register_model_from_url_proto(in_bytes, in_size, out_proto)`.
/// Shape is identical to `RacLifecycleRequestProtoDart` (no handle) — see
/// `runanywhere-commons/src/infrastructure/model_management/register_model_from_url.cpp`.
typedef RacRegisterModelFromUrlProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacRegisterModelFromUrlProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

/// Matches `rac_model_registry_import_proto(handle, in_bytes, in_size,
/// out_proto)`. Same shape as `RacHandleBytesToProtoDart`.
typedef RacModelRegistryImportProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacModelRegistryImportProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

// ============================================================================
// Model lifecycle proto-byte API (rac_model_lifecycle.h)
// ============================================================================

typedef RacModelLifecycleLoadProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacModelLifecycleLoadProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

typedef RacModelLifecycleRequestProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacModelLifecycleRequestProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

typedef RacComponentLifecycleSnapshotProtoNative =
    ffi.Int32 Function(ffi.Uint32, ffi.Pointer<RacProtoBuffer>);
typedef RacComponentLifecycleSnapshotProtoDart =
    int Function(int, ffi.Pointer<RacProtoBuffer>);

typedef RacModelLifecycleResetNative = ffi.Void Function();
typedef RacModelLifecycleResetDart = void Function();

// ============================================================================
// Storage analyzer proto-byte API (rac_storage_analyzer.h)
// ============================================================================

typedef RacStorageCalculateDirSizeNative =
    ffi.Int64 Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>);

typedef RacStorageGetFileSizeNative =
    ffi.Int64 Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>);

typedef RacStoragePathExistsNative =
    ffi.Int32 Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Int32>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacStorageGetSpaceNative = ffi.Int64 Function(ffi.Pointer<ffi.Void>);

typedef RacStorageDeletePathNative =
    ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32, ffi.Pointer<ffi.Void>);

typedef RacStorageIsModelLoadedNative =
    ffi.Int32 Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Int32>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacStorageUnloadModelNative =
    ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Void>);

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

typedef RacStorageAnalyzerCreateNative =
    ffi.Int32 Function(
      ffi.Pointer<RacStorageCallbacks>,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
    );
typedef RacStorageAnalyzerCreateDart =
    int Function(
      ffi.Pointer<RacStorageCallbacks>,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
    );

typedef RacStorageAnalyzerDestroyNative =
    ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef RacStorageAnalyzerDestroyDart = void Function(ffi.Pointer<ffi.Void>);

typedef RacStorageProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacStorageProtoDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    );

// ============================================================================
// Download proto-byte API (rac_download_orchestrator.h)
// ============================================================================

typedef RacDownloadProtoProgressCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacDownloadSetProgressProtoCallbackNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.NativeFunction<RacDownloadProtoProgressCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacDownloadSetProgressProtoCallbackDart =
    int Function(
      ffi.Pointer<ffi.NativeFunction<RacDownloadProtoProgressCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacDownloadProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef RacDownloadProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

// ============================================================================
// SDK event stream proto-byte API (rac_sdk_event_stream.h)
// ============================================================================

typedef RacSdkEventCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);

typedef RacSdkEventSubscribeNative =
    ffi.Uint64 Function(
      ffi.Pointer<ffi.NativeFunction<RacSdkEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );
typedef RacSdkEventSubscribeDart =
    int Function(
      ffi.Pointer<ffi.NativeFunction<RacSdkEventCallbackNative>>,
      ffi.Pointer<ffi.Void>,
    );

typedef RacSdkEventUnsubscribeNative = ffi.Void Function(ffi.Uint64);
typedef RacSdkEventUnsubscribeDart = void Function(int);

typedef RacSdkEventQuiesceNative = ffi.Void Function();
typedef RacSdkEventQuiesceDart = void Function();

typedef RacSdkEventPublishProtoNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef RacSdkEventPublishProtoDart = int Function(ffi.Pointer<ffi.Uint8>, int);

typedef RacSdkEventPollNative = ffi.Int32 Function(ffi.Pointer<RacProtoBuffer>);
typedef RacSdkEventPollDart = int Function(ffi.Pointer<RacProtoBuffer>);

typedef RacSdkEventPublishFailureNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
      ffi.Int32,
    );
typedef RacSdkEventPublishFailureDart =
    int Function(
      int,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<Utf8>,
      int,
    );

// ============================================================================
// SDK metadata + enum convenience helpers (rac_core.h / rac_environment.h /
// rac_model_types.h / rac_tool_calling.h)
// ============================================================================

/// `const char* rac_sdk_get_version(void)` — canonical SDK semver string
/// sourced from `sdk/runanywhere-commons/VERSION`.
typedef RacSdkGetVersionNative = ffi.Pointer<Utf8> Function();
typedef RacSdkGetVersionDart = ffi.Pointer<Utf8> Function();

/// `bool rac_env_*(rac_environment_t env)` predicate family
/// (is_production / is_testing / requires_auth / requires_backend_url /
/// should_send_telemetry / should_sync_with_backend).
typedef RacEnvPredicateNative = ffi.Bool Function(ffi.Int32);
typedef RacEnvPredicateDart = bool Function(int);

/// `rac_result_t rac_inference_framework_analytics_key(
///     rac_inference_framework_t f, const char** out)`.
/// `out` receives a statically-allocated literal — do NOT free.
typedef RacEnumToCStringNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Pointer<Utf8>>);
typedef RacEnumToCStringDart =
    int Function(int, ffi.Pointer<ffi.Pointer<Utf8>>);

/// `rac_inference_framework_t rac_model_category_default_framework(
///     rac_model_category_t)` and
/// `rac_bool_t rac_model_category_requires_context_length(
///     rac_model_category_t)` — int-enum in, int out.
typedef RacEnumToIntNative = ffi.Int32 Function(ffi.Int32);
typedef RacEnumToIntDart = int Function(int);

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

T? _lookupOptionalIn<T extends Function>(
  Iterable<ffi.DynamicLibrary> libraries,
  T Function(ffi.DynamicLibrary) lookup,
) {
  for (final library in libraries) {
    try {
      return lookup(library);
    } catch (_) {
      // Try the next candidate library.
    }
  }
  return null;
}

List<ffi.DynamicLibrary> _helperLookupLibraries(
  ffi.DynamicLibrary commons,
  ffi.DynamicLibrary? helpers,
) => helpers == null
    ? <ffi.DynamicLibrary>[commons]
    : <ffi.DynamicLibrary>[helpers, commons];

/// Typed bindings for the commons C ABI surfaces this file owns.
class RacBindings {
  RacBindings(ffi.DynamicLibrary lib, [ffi.DynamicLibrary? helperLib])
    : rac_proto_buffer_init = lib
          .lookupFunction<RacProtoBufferInitNative, RacProtoBufferInitDart>(
            'rac_proto_buffer_init',
          ),
      rac_proto_buffer_free = lib
          .lookupFunction<RacProtoBufferFreeNative, RacProtoBufferFreeDart>(
            'rac_proto_buffer_free',
          ),
      rac_result_to_proto_error = lib
          .lookupFunction<
            RacResultToProtoErrorNative,
            RacResultToProtoErrorDart
          >('rac_result_to_proto_error'),
      rac_voice_agent_set_proto_callback = lib
          .lookupFunction<
            RacVoiceAgentSetProtoCallbackNative,
            RacVoiceAgentSetProtoCallbackDart
          >('rac_voice_agent_set_proto_callback'),
      rac_llm_generate_proto = _lookupOptional<RacLlmGenerateProtoDart>(
        () => lib
            .lookupFunction<RacLlmGenerateProtoNative, RacLlmGenerateProtoDart>(
              'rac_llm_generate_proto',
            ),
      ),
      rac_llm_generate_stream_proto =
          _lookupOptional<RacLlmGenerateStreamProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLlmGenerateStreamProtoNative,
                  RacLlmGenerateStreamProtoDart
                >('rac_llm_generate_stream_proto'),
          ),
      ra_flutter_llm_generate_stream_proto_native_port =
          _lookupOptionalIn<RaFlutterLlmGenerateStreamNativePortDart>(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterLlmGenerateStreamNativePortNative,
                  RaFlutterLlmGenerateStreamNativePortDart
                >('ra_flutter_llm_generate_stream_proto_native_port'),
          ),
      ra_flutter_vlm_stream_proto_native_port =
          _lookupOptionalIn<RaFlutterVlmStreamNativePortDart>(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterVlmStreamNativePortNative,
                  RaFlutterVlmStreamNativePortDart
                >('ra_flutter_vlm_stream_proto_native_port'),
          ),
      ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port =
          _lookupOptionalIn<RaFlutterTtsSynthesizeStreamNativePortDart>(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterTtsSynthesizeStreamNativePortNative,
                  RaFlutterTtsSynthesizeStreamNativePortDart
                >(
                  'ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port',
                ),
          ),
      ra_flutter_voice_agent_process_turn_proto_native_port =
          _lookupOptionalIn<RaFlutterVoiceAgentProcessTurnNativePortDart>(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterVoiceAgentProcessTurnNativePortNative,
                  RaFlutterVoiceAgentProcessTurnNativePortDart
                >('ra_flutter_voice_agent_process_turn_proto_native_port'),
          ),
      ra_flutter_voice_agent_set_proto_callback_native_port =
          _lookupOptionalIn<RaFlutterVoiceAgentSetProtoCallbackNativePortDart>(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterVoiceAgentSetProtoCallbackNativePortNative,
                  RaFlutterVoiceAgentSetProtoCallbackNativePortDart
                >('ra_flutter_voice_agent_set_proto_callback_native_port'),
          ),
      ra_flutter_voice_agent_unset_proto_callback_native_port =
          _lookupOptionalIn<
            RaFlutterVoiceAgentUnsetProtoCallbackNativePortDart
          >(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterVoiceAgentUnsetProtoCallbackNativePortNative,
                  RaFlutterVoiceAgentUnsetProtoCallbackNativePortDart
                >('ra_flutter_voice_agent_unset_proto_callback_native_port'),
          ),
      rac_llm_cancel_proto = _lookupOptional<RacLlmCancelProtoDart>(
        () =>
            lib.lookupFunction<RacLlmCancelProtoNative, RacLlmCancelProtoDart>(
              'rac_llm_cancel_proto',
            ),
      ),
      rac_stt_transcribe_lifecycle_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_stt_transcribe_lifecycle_proto'),
          ),
      rac_stt_component_transcribe_proto =
          _lookupOptional<RacSttTranscribeProtoDart>(
            () =>
                lib.lookupFunction<
                  RacSttTranscribeProtoNative,
                  RacSttTranscribeProtoDart
                >('rac_stt_component_transcribe_proto'),
          ),
      rac_stt_component_transcribe_stream_proto =
          _lookupOptional<RacSttTranscribeStreamProtoDart>(
            () =>
                lib.lookupFunction<
                  RacSttTranscribeStreamProtoNative,
                  RacSttTranscribeStreamProtoDart
                >('rac_stt_component_transcribe_stream_proto'),
          ),
      rac_tts_synthesize_lifecycle_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_tts_synthesize_lifecycle_proto'),
          ),
      rac_tts_component_list_voices_proto =
          _lookupOptional<RacTtsListVoicesProtoDart>(
            () =>
                lib.lookupFunction<
                  RacTtsListVoicesProtoNative,
                  RacTtsListVoicesProtoDart
                >('rac_tts_component_list_voices_proto'),
          ),
      rac_tts_component_synthesize_proto =
          _lookupOptional<RacTtsSynthesizeProtoDart>(
            () =>
                lib.lookupFunction<
                  RacTtsSynthesizeProtoNative,
                  RacTtsSynthesizeProtoDart
                >('rac_tts_component_synthesize_proto'),
          ),
      rac_tts_component_synthesize_stream_proto =
          _lookupOptional<RacTtsSynthesizeStreamProtoDart>(
            () =>
                lib.lookupFunction<
                  RacTtsSynthesizeStreamProtoNative,
                  RacTtsSynthesizeStreamProtoDart
                >('rac_tts_component_synthesize_stream_proto'),
          ),
      rac_vad_process_lifecycle_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_vad_process_lifecycle_proto'),
          ),
      rac_tts_synthesize_stream_lifecycle_proto =
          _lookupOptional<RacTtsSynthesizeStreamLifecycleProtoDart>(
            () =>
                lib.lookupFunction<
                  RacTtsSynthesizeStreamLifecycleProtoNative,
                  RacTtsSynthesizeStreamLifecycleProtoDart
                >('rac_tts_synthesize_stream_lifecycle_proto'),
          ),
      rac_tts_stop_lifecycle_proto = _lookupOptional<RacOutOnlyProtoDart>(
        () => lib.lookupFunction<RacOutOnlyProtoNative, RacOutOnlyProtoDart>(
          'rac_tts_stop_lifecycle_proto',
        ),
      ),
      rac_vad_configure_lifecycle_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_vad_configure_lifecycle_proto'),
          ),
      rac_vad_start_lifecycle_proto = _lookupOptional<RacOutOnlyProtoDart>(
        () => lib.lookupFunction<RacOutOnlyProtoNative, RacOutOnlyProtoDart>(
          'rac_vad_start_lifecycle_proto',
        ),
      ),
      rac_vad_stop_lifecycle_proto = _lookupOptional<RacOutOnlyProtoDart>(
        () => lib.lookupFunction<RacOutOnlyProtoNative, RacOutOnlyProtoDart>(
          'rac_vad_stop_lifecycle_proto',
        ),
      ),
      rac_vad_reset_lifecycle_proto = _lookupOptional<RacOutOnlyProtoDart>(
        () => lib.lookupFunction<RacOutOnlyProtoNative, RacOutOnlyProtoDart>(
          'rac_vad_reset_lifecycle_proto',
        ),
      ),
      rac_vad_component_configure_proto =
          _lookupOptional<RacVadConfigureProtoDart>(
            () =>
                lib.lookupFunction<
                  RacVadConfigureProtoNative,
                  RacVadConfigureProtoDart
                >('rac_vad_component_configure_proto'),
          ),
      rac_vad_component_process_proto = _lookupOptional<RacVadProcessProtoDart>(
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
            () =>
                lib.lookupFunction<
                  RacVadSetActivityProtoCallbackNative,
                  RacVadSetActivityProtoCallbackDart
                >('rac_vad_component_set_activity_proto_callback'),
          ),
      rac_voice_agent_initialize_proto =
          _lookupOptional<RacVoiceAgentInitializeProtoDart>(
            () =>
                lib.lookupFunction<
                  RacVoiceAgentInitializeProtoNative,
                  RacVoiceAgentInitializeProtoDart
                >('rac_voice_agent_initialize_proto'),
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
            () =>
                lib.lookupFunction<
                  RacVoiceAgentProcessTurnProtoNative,
                  RacVoiceAgentProcessTurnProtoDart
                >('rac_voice_agent_process_voice_turn_proto'),
          ),
      rac_vlm_cancel_lifecycle_proto = _lookupOptional<RacOutOnlyProtoDart>(
        () => lib.lookupFunction<RacOutOnlyProtoNative, RacOutOnlyProtoDart>(
          'rac_vlm_cancel_lifecycle_proto',
        ),
      ),
      rac_embeddings_create_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_embeddings_create_proto'),
          ),
      rac_embeddings_embed_batch_proto =
          _lookupOptional<RacHandleBytesToProtoDart>(
            () =>
                lib.lookupFunction<
                  RacHandleBytesToProtoNative,
                  RacHandleBytesToProtoDart
                >('rac_embeddings_embed_batch_proto'),
          ),
      rac_embeddings_embed_batch_lifecycle_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_embeddings_embed_batch_lifecycle_proto'),
          ),
      rac_diffusion_generate_lifecycle_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_diffusion_generate_lifecycle_proto'),
          ),
      rac_rag_session_create_proto =
          _lookupOptional<RacRagSessionCreateProtoDart>(
            () =>
                lib.lookupFunction<
                  RacRagSessionCreateProtoNative,
                  RacRagSessionCreateProtoDart
                >('rac_rag_session_create_proto'),
          ),
      rac_rag_session_destroy_proto = _lookupOptional<RacDestroyHandleDart>(
        () => lib.lookupFunction<RacDestroyHandleNative, RacDestroyHandleDart>(
          'rac_rag_session_destroy_proto',
        ),
      ),
      rac_rag_ingest_proto = _lookupOptional<RacHandleBytesToProtoDart>(
        () =>
            lib.lookupFunction<
              RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart
            >('rac_rag_ingest_proto'),
      ),
      rac_rag_query_proto = _lookupOptional<RacHandleBytesToProtoDart>(
        () =>
            lib.lookupFunction<
              RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart
            >('rac_rag_query_proto'),
      ),
      rac_rag_clear_proto = _lookupOptional<RacHandleOutProtoDart>(
        () =>
            lib.lookupFunction<RacHandleOutProtoNative, RacHandleOutProtoDart>(
              'rac_rag_clear_proto',
            ),
      ),
      rac_rag_stats_proto = _lookupOptional<RacHandleOutProtoDart>(
        () =>
            lib.lookupFunction<RacHandleOutProtoNative, RacHandleOutProtoDart>(
              'rac_rag_stats_proto',
            ),
      ),
      rac_get_lora_registry = _lookupOptional<RacLoraRegistryGetDart>(
        () => lib
            .lookupFunction<RacLoraRegistryGetNative, RacLoraRegistryGetDart>(
              'rac_get_lora_registry',
            ),
      ),
      rac_lora_register_proto = _lookupOptional<RacHandleBytesToProtoDart>(
        () =>
            lib.lookupFunction<
              RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart
            >('rac_lora_register_proto'),
      ),
      rac_lora_catalog_list_proto = _lookupOptional<RacHandleBytesToProtoDart>(
        () =>
            lib.lookupFunction<
              RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart
            >('rac_lora_catalog_list_proto'),
      ),
      rac_lora_catalog_query_proto = _lookupOptional<RacHandleBytesToProtoDart>(
        () =>
            lib.lookupFunction<
              RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart
            >('rac_lora_catalog_query_proto'),
      ),
      rac_lora_catalog_get_proto = _lookupOptional<RacHandleBytesToProtoDart>(
        () =>
            lib.lookupFunction<
              RacHandleBytesToProtoNative,
              RacHandleBytesToProtoDart
            >('rac_lora_catalog_get_proto'),
      ),
      rac_lora_catalog_mark_download_completed_proto =
          _lookupOptional<RacHandleBytesToProtoDart>(
            () =>
                lib.lookupFunction<
                  RacHandleBytesToProtoNative,
                  RacHandleBytesToProtoDart
                >('rac_lora_catalog_mark_download_completed_proto'),
          ),
      rac_lora_adapter_import_proto =
          _lookupOptional<RacHandleBytesToProtoDart>(
            () =>
                lib.lookupFunction<
                  RacHandleBytesToProtoNative,
                  RacHandleBytesToProtoDart
                >('rac_lora_adapter_import_proto'),
          ),
      rac_lora_compatibility_proto =
          _lookupOptional<RacLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacLifecycleRequestProtoNative,
                  RacLifecycleRequestProtoDart
                >('rac_lora_compatibility_proto'),
          ),
      rac_lora_apply_proto = _lookupOptional<RacLifecycleRequestProtoDart>(
        () =>
            lib.lookupFunction<
              RacLifecycleRequestProtoNative,
              RacLifecycleRequestProtoDart
            >('rac_lora_apply_proto'),
      ),
      rac_lora_remove_proto = _lookupOptional<RacLifecycleRequestProtoDart>(
        () =>
            lib.lookupFunction<
              RacLifecycleRequestProtoNative,
              RacLifecycleRequestProtoDart
            >('rac_lora_remove_proto'),
      ),
      rac_lora_list_proto = _lookupOptional<RacLifecycleRequestProtoDart>(
        () =>
            lib.lookupFunction<
              RacLifecycleRequestProtoNative,
              RacLifecycleRequestProtoDart
            >('rac_lora_list_proto'),
      ),
      rac_lora_state_proto = _lookupOptional<RacLifecycleRequestProtoDart>(
        () =>
            lib.lookupFunction<
              RacLifecycleRequestProtoNative,
              RacLifecycleRequestProtoDart
            >('rac_lora_state_proto'),
      ),
      rac_http_client_create = lib
          .lookupFunction<RacHttpClientCreateNative, RacHttpClientCreateDart>(
            'rac_http_client_create',
          ),
      rac_http_client_destroy = lib
          .lookupFunction<RacHttpClientDestroyNative, RacHttpClientDestroyDart>(
            'rac_http_client_destroy',
          ),
      rac_http_request_send = lib
          .lookupFunction<RacHttpRequestSendNative, RacHttpRequestSendDart>(
            'rac_http_request_send',
          ),
      rac_http_response_free = lib
          .lookupFunction<RacHttpResponseFreeNative, RacHttpResponseFreeDart>(
            'rac_http_response_free',
          ),
      rac_http_default_headers = lib
          .lookupFunction<
            RacHttpDefaultHeadersNative,
            RacHttpDefaultHeadersDart
          >('rac_http_default_headers'),
      rac_http_download_execute = lib
          .lookupFunction<
            RacHttpDownloadExecuteNative,
            RacHttpDownloadExecuteDart
          >('rac_http_download_execute'),
      rac_model_registry_refresh_proto = lib
          .lookupFunction<
            RacHandleBytesToProtoNative,
            RacHandleBytesToProtoDart
          >('rac_model_registry_refresh_proto'),
      rac_model_registry_register_proto = lib
          .lookupFunction<
            RacModelRegistryRegisterProtoNative,
            RacModelRegistryRegisterProtoDart
          >('rac_model_registry_register_proto'),
      rac_model_registry_update_proto = lib
          .lookupFunction<
            RacModelRegistryUpdateProtoNative,
            RacModelRegistryUpdateProtoDart
          >('rac_model_registry_update_proto'),
      rac_model_registry_get_proto = lib
          .lookupFunction<
            RacModelRegistryGetProtoNative,
            RacModelRegistryGetProtoDart
          >('rac_model_registry_get_proto'),
      rac_model_registry_list_proto = lib
          .lookupFunction<
            RacModelRegistryListProtoNative,
            RacModelRegistryListProtoDart
          >('rac_model_registry_list_proto'),
      rac_model_registry_query_proto = lib
          .lookupFunction<
            RacModelRegistryQueryProtoNative,
            RacModelRegistryQueryProtoDart
          >('rac_model_registry_query_proto'),
      rac_model_registry_list_downloaded_proto = lib
          .lookupFunction<
            RacModelRegistryListDownloadedProtoNative,
            RacModelRegistryListDownloadedProtoDart
          >('rac_model_registry_list_downloaded_proto'),
      rac_model_registry_remove_proto = lib
          .lookupFunction<
            RacModelRegistryRemoveProtoNative,
            RacModelRegistryRemoveProtoDart
          >('rac_model_registry_remove_proto'),
      rac_model_registry_proto_free = lib
          .lookupFunction<
            RacModelRegistryProtoFreeNative,
            RacModelRegistryProtoFreeDart
          >('rac_model_registry_proto_free'),
      rac_register_model_from_url_proto = lib
          .lookupFunction<
            RacRegisterModelFromUrlProtoNative,
            RacRegisterModelFromUrlProtoDart
          >('rac_register_model_from_url_proto'),
      rac_register_multi_file_model_proto = lib
          .lookupFunction<
            RacRegisterModelFromUrlProtoNative,
            RacRegisterModelFromUrlProtoDart
          >('rac_register_multi_file_model_proto'),
      rac_model_registry_import_proto = lib
          .lookupFunction<
            RacModelRegistryImportProtoNative,
            RacModelRegistryImportProtoDart
          >('rac_model_registry_import_proto'),
      rac_model_registry_discover_proto = lib
          .lookupFunction<
            RacHandleBytesToProtoNative,
            RacHandleBytesToProtoDart
          >('rac_model_registry_discover_proto'),
      rac_model_lifecycle_load_proto =
          _lookupOptional<RacModelLifecycleLoadProtoDart>(
            () =>
                lib.lookupFunction<
                  RacModelLifecycleLoadProtoNative,
                  RacModelLifecycleLoadProtoDart
                >('rac_model_lifecycle_load_proto'),
          ),
      rac_model_lifecycle_unload_proto =
          _lookupOptional<RacModelLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacModelLifecycleRequestProtoNative,
                  RacModelLifecycleRequestProtoDart
                >('rac_model_lifecycle_unload_proto'),
          ),
      rac_model_lifecycle_current_model_proto =
          _lookupOptional<RacModelLifecycleRequestProtoDart>(
            () =>
                lib.lookupFunction<
                  RacModelLifecycleRequestProtoNative,
                  RacModelLifecycleRequestProtoDart
                >('rac_model_lifecycle_current_model_proto'),
          ),
      rac_component_lifecycle_snapshot_proto =
          _lookupOptional<RacComponentLifecycleSnapshotProtoDart>(
            () =>
                lib.lookupFunction<
                  RacComponentLifecycleSnapshotProtoNative,
                  RacComponentLifecycleSnapshotProtoDart
                >('rac_component_lifecycle_snapshot_proto'),
          ),
      rac_model_lifecycle_reset = _lookupOptional<RacModelLifecycleResetDart>(
        () =>
            lib.lookupFunction<
              RacModelLifecycleResetNative,
              RacModelLifecycleResetDart
            >('rac_model_lifecycle_reset'),
      ),
      rac_storage_analyzer_create =
          _lookupOptional<RacStorageAnalyzerCreateDart>(
            () =>
                lib.lookupFunction<
                  RacStorageAnalyzerCreateNative,
                  RacStorageAnalyzerCreateDart
                >('rac_storage_analyzer_create'),
          ),
      rac_storage_analyzer_destroy =
          _lookupOptional<RacStorageAnalyzerDestroyDart>(
            () =>
                lib.lookupFunction<
                  RacStorageAnalyzerDestroyNative,
                  RacStorageAnalyzerDestroyDart
                >('rac_storage_analyzer_destroy'),
          ),
      rac_storage_analyzer_info_proto = _lookupOptional<RacStorageProtoDart>(
        () => lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
          'rac_storage_analyzer_info_proto',
        ),
      ),
      rac_storage_analyzer_availability_proto =
          _lookupOptional<RacStorageProtoDart>(
            () =>
                lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
                  'rac_storage_analyzer_availability_proto',
                ),
          ),
      rac_storage_analyzer_delete_plan_proto =
          _lookupOptional<RacStorageProtoDart>(
            () =>
                lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
                  'rac_storage_analyzer_delete_plan_proto',
                ),
          ),
      rac_storage_analyzer_delete_proto = _lookupOptional<RacStorageProtoDart>(
        () => lib.lookupFunction<RacStorageProtoNative, RacStorageProtoDart>(
          'rac_storage_analyzer_delete_proto',
        ),
      ),
      rac_download_set_progress_proto_callback =
          _lookupOptional<RacDownloadSetProgressProtoCallbackDart>(
            () =>
                lib.lookupFunction<
                  RacDownloadSetProgressProtoCallbackNative,
                  RacDownloadSetProgressProtoCallbackDart
                >('rac_download_set_progress_proto_callback'),
          ),
      rac_download_plan_proto = _lookupOptional<RacDownloadProtoDart>(
        () => lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
          'rac_download_plan_proto',
        ),
      ),
      rac_download_start_proto = _lookupOptional<RacDownloadProtoDart>(
        () => lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
          'rac_download_start_proto',
        ),
      ),
      rac_download_cancel_proto = _lookupOptional<RacDownloadProtoDart>(
        () => lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
          'rac_download_cancel_proto',
        ),
      ),
      rac_download_resume_proto = _lookupOptional<RacDownloadProtoDart>(
        () => lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
          'rac_download_resume_proto',
        ),
      ),
      rac_download_progress_poll_proto = _lookupOptional<RacDownloadProtoDart>(
        () => lib.lookupFunction<RacDownloadProtoNative, RacDownloadProtoDart>(
          'rac_download_progress_poll_proto',
        ),
      ),
      rac_sdk_event_subscribe = _lookupOptional<RacSdkEventSubscribeDart>(
        () =>
            lib.lookupFunction<
              RacSdkEventSubscribeNative,
              RacSdkEventSubscribeDart
            >('rac_sdk_event_subscribe'),
      ),
      rac_sdk_event_unsubscribe = _lookupOptional<RacSdkEventUnsubscribeDart>(
        () =>
            lib.lookupFunction<
              RacSdkEventUnsubscribeNative,
              RacSdkEventUnsubscribeDart
            >('rac_sdk_event_unsubscribe'),
      ),
      rac_sdk_event_quiesce = lib
          .lookupFunction<RacSdkEventQuiesceNative, RacSdkEventQuiesceDart>(
            'rac_sdk_event_quiesce',
          ),
      rac_sdk_event_publish_proto =
          _lookupOptional<RacSdkEventPublishProtoDart>(
            () =>
                lib.lookupFunction<
                  RacSdkEventPublishProtoNative,
                  RacSdkEventPublishProtoDart
                >('rac_sdk_event_publish_proto'),
          ),
      rac_sdk_event_poll = _lookupOptional<RacSdkEventPollDart>(
        () => lib.lookupFunction<RacSdkEventPollNative, RacSdkEventPollDart>(
          'rac_sdk_event_poll',
        ),
      ),
      rac_sdk_event_publish_failure =
          _lookupOptional<RacSdkEventPublishFailureDart>(
            () =>
                lib.lookupFunction<
                  RacSdkEventPublishFailureNative,
                  RacSdkEventPublishFailureDart
                >('rac_sdk_event_publish_failure'),
          ),
      rac_tool_call_parse_proto = lib
          .lookupFunction<
            RacToolCallProtoRequestNative,
            RacToolCallProtoRequestDart
          >('rac_tool_call_parse_proto'),
      rac_tool_call_format_prompt_proto = lib
          .lookupFunction<
            RacToolCallProtoRequestNative,
            RacToolCallProtoRequestDart
          >('rac_tool_call_format_prompt_proto'),
      rac_tool_call_validate_proto = lib
          .lookupFunction<
            RacToolCallProtoRequestNative,
            RacToolCallProtoRequestDart
          >('rac_tool_call_validate_proto'),
      rac_tool_calling_session_create_proto = lib
          .lookupFunction<
            RacToolCallingSessionCreateProtoNative,
            RacToolCallingSessionCreateProtoDart
          >('rac_tool_calling_session_create_proto'),
      rac_tool_calling_session_step_with_result_proto = lib
          .lookupFunction<
            RacToolCallingSessionStepWithResultProtoNative,
            RacToolCallingSessionStepWithResultProtoDart
          >('rac_tool_calling_session_step_with_result_proto'),
      rac_tool_calling_session_destroy_proto = lib
          .lookupFunction<
            RacToolCallingSessionDestroyProtoNative,
            RacToolCallingSessionDestroyProtoDart
          >('rac_tool_calling_session_destroy_proto'),
      rac_tool_calling_session_cancel_proto = lib
          .lookupFunction<
            RacToolCallingSessionCancelProtoNative,
            RacToolCallingSessionCancelProtoDart
          >('rac_tool_calling_session_cancel_proto'),
      rac_model_format_from_url_proto = lib
          .lookupFunction<
            RacModelFormatFromUrlProtoNative,
            RacModelFormatFromUrlProtoDart
          >('rac_model_format_from_url_proto'),
      rac_artifact_infer_from_url_proto = lib
          .lookupFunction<
            RacArtifactInferFromUrlProtoNative,
            RacArtifactInferFromUrlProtoDart
          >('rac_artifact_infer_from_url_proto'),
      rac_stt_component_load_model = lib
          .lookupFunction<
            RacSttComponentLoadModelNative,
            RacSttComponentLoadModelDart
          >('rac_stt_component_load_model'),
      ra_flutter_stt_set_stream_proto_native_port =
          _lookupOptionalIn<RaFlutterSttSetStreamNativePortDart>(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterSttSetStreamNativePortNative,
                  RaFlutterSttSetStreamNativePortDart
                >('ra_flutter_stt_set_stream_proto_native_port'),
          ),
      ra_flutter_stt_unset_stream_proto_native_port =
          _lookupOptionalIn<RaFlutterSttUnsetStreamNativePortDart>(
            _helperLookupLibraries(lib, helperLib),
            (library) =>
                library.lookupFunction<
                  RaFlutterSttUnsetStreamNativePortNative,
                  RaFlutterSttUnsetStreamNativePortDart
                >('ra_flutter_stt_unset_stream_proto_native_port'),
          ),
      rac_stt_stream_start_proto = lib
          .lookupFunction<
            RacSttStreamStartProtoNative,
            RacSttStreamStartProtoDart
          >('rac_stt_stream_start_proto'),
      rac_stt_stream_feed_audio_proto = lib
          .lookupFunction<
            RacSttStreamFeedAudioProtoNative,
            RacSttStreamFeedAudioProtoDart
          >('rac_stt_stream_feed_audio_proto'),
      rac_stt_stream_stop_proto = lib
          .lookupFunction<
            RacSttStreamFinishProtoNative,
            RacSttStreamFinishProtoDart
          >('rac_stt_stream_stop_proto'),
      rac_stt_stream_cancel_proto = lib
          .lookupFunction<
            RacSttStreamFinishProtoNative,
            RacSttStreamFinishProtoDart
          >('rac_stt_stream_cancel_proto'),
      rac_voice_agent_process_turn_proto =
          _lookupOptional<RacVoiceAgentProcessTurnProto2Dart>(
            () =>
                lib.lookupFunction<
                  RacVoiceAgentProcessTurnProto2Native,
                  RacVoiceAgentProcessTurnProto2Dart
                >('rac_voice_agent_process_turn_proto'),
          ),
      rac_voice_agent_cancel_turn_proto =
          _lookupOptional<RacVoiceAgentCancelTurnProtoDart>(
            () =>
                lib.lookupFunction<
                  RacVoiceAgentCancelTurnProtoNative,
                  RacVoiceAgentCancelTurnProtoDart
                >('rac_voice_agent_cancel_turn_proto'),
          ),
      rac_voice_agent_transcribe_proto =
          _lookupOptional<RacVoiceAgentHelperProtoDart>(
            () =>
                lib.lookupFunction<
                  RacVoiceAgentHelperProtoNative,
                  RacVoiceAgentHelperProtoDart
                >('rac_voice_agent_transcribe_proto'),
          ),
      rac_voice_agent_synthesize_speech_proto =
          _lookupOptional<RacVoiceAgentHelperProtoDart>(
            () =>
                lib.lookupFunction<
                  RacVoiceAgentHelperProtoNative,
                  RacVoiceAgentHelperProtoDart
                >('rac_voice_agent_synthesize_speech_proto'),
          ),
      rac_voice_agent_component_create_proto = lib
          .lookupFunction<
            RacVoiceAgentComponentCreateProtoNative,
            RacVoiceAgentComponentCreateProtoDart
          >('rac_voice_agent_component_create_proto'),
      rac_voice_agent_component_destroy_proto = lib
          .lookupFunction<
            RacVoiceAgentComponentDestroyProtoNative,
            RacVoiceAgentComponentDestroyProtoDart
          >('rac_voice_agent_component_destroy_proto'),
      rac_structured_output_parse_proto = lib
          .lookupFunction<
            RacLifecycleRequestProtoNative,
            RacLifecycleRequestProtoDart
          >('rac_structured_output_parse_proto'),
      rac_structured_output_generate_proto = lib
          .lookupFunction<
            RacLifecycleRequestProtoNative,
            RacLifecycleRequestProtoDart
          >('rac_structured_output_generate_proto'),
      rac_structured_output_prepare_prompt_proto = lib
          .lookupFunction<
            RacLifecycleRequestProtoNative,
            RacLifecycleRequestProtoDart
          >('rac_structured_output_prepare_prompt_proto'),
      rac_structured_output_schema_to_json_proto = lib
          .lookupFunction<
            RacLifecycleRequestProtoNative,
            RacLifecycleRequestProtoDart
          >('rac_structured_output_schema_to_json_proto'),
      rac_tool_value_to_json_proto = lib
          .lookupFunction<
            RacLifecycleRequestProtoNative,
            RacLifecycleRequestProtoDart
          >('rac_tool_value_to_json_proto'),
      rac_tool_value_from_json_proto = lib
          .lookupFunction<
            RacLifecycleRequestProtoNative,
            RacLifecycleRequestProtoDart
          >('rac_tool_value_from_json_proto'),
      rac_llm_proto_quiesce = lib
          .lookupFunction<RacProtoQuiesceNative, RacProtoQuiesceDart>(
            'rac_llm_proto_quiesce',
          ),
      rac_stt_proto_quiesce = lib
          .lookupFunction<RacProtoQuiesceNative, RacProtoQuiesceDart>(
            'rac_stt_proto_quiesce',
          ),
      rac_tts_proto_quiesce = lib
          .lookupFunction<RacProtoQuiesceNative, RacProtoQuiesceDart>(
            'rac_tts_proto_quiesce',
          ),
      rac_vad_proto_quiesce = lib
          .lookupFunction<RacProtoQuiesceNative, RacProtoQuiesceDart>(
            'rac_vad_proto_quiesce',
          ),
      rac_vlm_proto_quiesce = lib
          .lookupFunction<RacProtoQuiesceNative, RacProtoQuiesceDart>(
            'rac_vlm_proto_quiesce',
          ),
      rac_voice_agent_proto_quiesce = lib
          .lookupFunction<RacProtoQuiesceNative, RacProtoQuiesceDart>(
            'rac_voice_agent_proto_quiesce',
          ),
      rac_sdk_get_version = lib
          .lookupFunction<RacSdkGetVersionNative, RacSdkGetVersionDart>(
            'rac_sdk_get_version',
          ),
      rac_env_is_production = _lookupOptional<RacEnvPredicateDart>(
        () => lib.lookupFunction<RacEnvPredicateNative, RacEnvPredicateDart>(
          'rac_env_is_production',
        ),
      ),
      rac_env_is_testing = _lookupOptional<RacEnvPredicateDart>(
        () => lib.lookupFunction<RacEnvPredicateNative, RacEnvPredicateDart>(
          'rac_env_is_testing',
        ),
      ),
      rac_env_requires_auth = _lookupOptional<RacEnvPredicateDart>(
        () => lib.lookupFunction<RacEnvPredicateNative, RacEnvPredicateDart>(
          'rac_env_requires_auth',
        ),
      ),
      rac_env_requires_backend_url = _lookupOptional<RacEnvPredicateDart>(
        () => lib.lookupFunction<RacEnvPredicateNative, RacEnvPredicateDart>(
          'rac_env_requires_backend_url',
        ),
      ),
      rac_env_should_send_telemetry = _lookupOptional<RacEnvPredicateDart>(
        () => lib.lookupFunction<RacEnvPredicateNative, RacEnvPredicateDart>(
          'rac_env_should_send_telemetry',
        ),
      ),
      rac_env_should_sync_with_backend = _lookupOptional<RacEnvPredicateDart>(
        () => lib.lookupFunction<RacEnvPredicateNative, RacEnvPredicateDart>(
          'rac_env_should_sync_with_backend',
        ),
      ),
      rac_inference_framework_analytics_key = lib
          .lookupFunction<RacEnumToCStringNative, RacEnumToCStringDart>(
            'rac_inference_framework_analytics_key',
          ),
      rac_model_category_default_framework = lib
          .lookupFunction<RacEnumToIntNative, RacEnumToIntDart>(
            'rac_model_category_default_framework',
          ),
      rac_model_category_requires_context_length = lib
          .lookupFunction<RacEnumToIntNative, RacEnumToIntDart>(
            'rac_model_category_requires_context_length',
          );

  // Shared proto buffers -----------------------------------------------------

  final RacProtoBufferInitDart rac_proto_buffer_init;

  final RacProtoBufferFreeDart rac_proto_buffer_free;

  /// `rac_result_to_proto_error` — canonical rac_result_t → serialized
  /// `SDKError` proto mapping. Mirrors Swift's RASDKError+Helpers.swift path so
  /// the translation lives in commons across every SDK.
  final RacResultToProtoErrorDart rac_result_to_proto_error;

  // Streaming callbacks ------------------------------------------------------

  final RacVoiceAgentSetProtoCallbackDart rac_voice_agent_set_proto_callback;

  // Generated-proto modality APIs -------------------------------------------

  final RacLlmGenerateProtoDart? rac_llm_generate_proto;

  final RacLlmGenerateStreamProtoDart? rac_llm_generate_stream_proto;

  final RaFlutterLlmGenerateStreamNativePortDart?
  ra_flutter_llm_generate_stream_proto_native_port;

  final RaFlutterVlmStreamNativePortDart?
  ra_flutter_vlm_stream_proto_native_port;

  final RaFlutterTtsSynthesizeStreamNativePortDart?
  ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port;

  final RaFlutterVoiceAgentProcessTurnNativePortDart?
  ra_flutter_voice_agent_process_turn_proto_native_port;

  final RaFlutterVoiceAgentSetProtoCallbackNativePortDart?
  ra_flutter_voice_agent_set_proto_callback_native_port;

  final RaFlutterVoiceAgentUnsetProtoCallbackNativePortDart?
  ra_flutter_voice_agent_unset_proto_callback_native_port;

  final RacLlmCancelProtoDart? rac_llm_cancel_proto;

  final RacLifecycleRequestProtoDart? rac_stt_transcribe_lifecycle_proto;

  final RacSttTranscribeProtoDart? rac_stt_component_transcribe_proto;

  final RacSttTranscribeStreamProtoDart?
  rac_stt_component_transcribe_stream_proto;

  final RacLifecycleRequestProtoDart? rac_tts_synthesize_lifecycle_proto;

  final RacTtsListVoicesProtoDart? rac_tts_component_list_voices_proto;

  final RacTtsSynthesizeProtoDart? rac_tts_component_synthesize_proto;

  final RacTtsSynthesizeStreamProtoDart?
  rac_tts_component_synthesize_stream_proto;

  final RacLifecycleRequestProtoDart? rac_vad_process_lifecycle_proto;

  final RacTtsSynthesizeStreamLifecycleProtoDart?
  rac_tts_synthesize_stream_lifecycle_proto;

  final RacOutOnlyProtoDart? rac_tts_stop_lifecycle_proto;

  final RacLifecycleRequestProtoDart? rac_vad_configure_lifecycle_proto;

  final RacOutOnlyProtoDart? rac_vad_start_lifecycle_proto;

  final RacOutOnlyProtoDart? rac_vad_stop_lifecycle_proto;

  final RacOutOnlyProtoDart? rac_vad_reset_lifecycle_proto;

  final RacVadConfigureProtoDart? rac_vad_component_configure_proto;

  final RacVadProcessProtoDart? rac_vad_component_process_proto;

  final RacHandleOutProtoDart? rac_vad_component_get_statistics_proto;

  final RacVadSetActivityProtoCallbackDart?
  rac_vad_component_set_activity_proto_callback;

  final RacVoiceAgentInitializeProtoDart? rac_voice_agent_initialize_proto;

  final RacHandleOutProtoDart? rac_voice_agent_component_states_proto;

  final RacVoiceAgentProcessTurnProtoDart?
  rac_voice_agent_process_voice_turn_proto;

  /// `rac_vlm_cancel_lifecycle_proto` — cancel lifecycle-owned VLM
  /// generation and return a serialized SDKEvent describing the
  /// cancellation. Null on older commons binaries.
  final RacOutOnlyProtoDart? rac_vlm_cancel_lifecycle_proto;

  final RacLifecycleRequestProtoDart? rac_embeddings_create_proto;

  final RacHandleBytesToProtoDart? rac_embeddings_embed_batch_proto;

  final RacLifecycleRequestProtoDart?
  rac_embeddings_embed_batch_lifecycle_proto;

  final RacLifecycleRequestProtoDart? rac_diffusion_generate_lifecycle_proto;

  final RacRagSessionCreateProtoDart? rac_rag_session_create_proto;

  final RacDestroyHandleDart? rac_rag_session_destroy_proto;

  final RacHandleBytesToProtoDart? rac_rag_ingest_proto;

  final RacHandleBytesToProtoDart? rac_rag_query_proto;

  final RacHandleOutProtoDart? rac_rag_clear_proto;

  final RacHandleOutProtoDart? rac_rag_stats_proto;

  final RacLoraRegistryGetDart? rac_get_lora_registry;

  final RacHandleBytesToProtoDart? rac_lora_register_proto;

  final RacHandleBytesToProtoDart? rac_lora_catalog_list_proto;

  final RacHandleBytesToProtoDart? rac_lora_catalog_query_proto;

  final RacHandleBytesToProtoDart? rac_lora_catalog_get_proto;

  final RacHandleBytesToProtoDart?
  rac_lora_catalog_mark_download_completed_proto;

  final RacHandleBytesToProtoDart? rac_lora_adapter_import_proto;

  final RacLifecycleRequestProtoDart? rac_lora_compatibility_proto;

  final RacLifecycleRequestProtoDart? rac_lora_apply_proto;

  final RacLifecycleRequestProtoDart? rac_lora_remove_proto;

  final RacLifecycleRequestProtoDart? rac_lora_list_proto;

  final RacLifecycleRequestProtoDart? rac_lora_state_proto;

  // HTTP client --------------------------------------------------------------

  final RacHttpClientCreateDart rac_http_client_create;

  final RacHttpClientDestroyDart rac_http_client_destroy;

  final RacHttpRequestSendDart rac_http_request_send;

  final RacHttpResponseFreeDart rac_http_response_free;

  /// Canonical SDK header list.
  final RacHttpDefaultHeadersDart rac_http_default_headers;

  // HTTP download ------------------------------------------------------------

  final RacHttpDownloadExecuteDart rac_http_download_execute;

  // Model registry proto-byte API --------------------------------------------

  /// `rac_model_registry_refresh_proto` — the single refresh entry point.
  /// Takes a `ModelRegistryRefreshRequest` and returns a
  /// `ModelRegistryRefreshResult`.
  final RacHandleBytesToProtoDart rac_model_registry_refresh_proto;

  final RacModelRegistryRegisterProtoDart rac_model_registry_register_proto;

  final RacModelRegistryUpdateProtoDart rac_model_registry_update_proto;

  final RacModelRegistryGetProtoDart rac_model_registry_get_proto;

  final RacModelRegistryListProtoDart rac_model_registry_list_proto;

  final RacModelRegistryQueryProtoDart rac_model_registry_query_proto;

  final RacModelRegistryListDownloadedProtoDart
  rac_model_registry_list_downloaded_proto;

  final RacModelRegistryRemoveProtoDart rac_model_registry_remove_proto;

  final RacModelRegistryProtoFreeDart rac_model_registry_proto_free;

  /// `rac_register_model_from_url_proto` — Swift-parity URL-form
  /// `registerModel(...)` entry point. Builds and persists a ModelInfo from a
  /// `RegisterModelFromUrlRequest`.
  final RacRegisterModelFromUrlProtoDart rac_register_model_from_url_proto;
  final RacRegisterModelFromUrlProtoDart rac_register_multi_file_model_proto;

  /// `rac_model_registry_import_proto` — local-import entry point used by
  /// file-picker / bookmark flows after the platform has handled sandbox
  /// access.
  final RacModelRegistryImportProtoDart rac_model_registry_import_proto;

  final RacHandleBytesToProtoDart rac_model_registry_discover_proto;

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

  final RacSdkEventQuiesceDart rac_sdk_event_quiesce;

  final RacSdkEventPublishProtoDart? rac_sdk_event_publish_proto;

  final RacSdkEventPollDart? rac_sdk_event_poll;

  final RacSdkEventPublishFailureDart? rac_sdk_event_publish_failure;

  // Tool-calling proto APIs --------------------------

  final RacToolCallProtoRequestDart rac_tool_call_parse_proto;

  final RacToolCallProtoRequestDart rac_tool_call_format_prompt_proto;

  final RacToolCallProtoRequestDart rac_tool_call_validate_proto;

  final RacToolCallingSessionCreateProtoDart
  rac_tool_calling_session_create_proto;

  final RacToolCallingSessionStepWithResultProtoDart
  rac_tool_calling_session_step_with_result_proto;

  final RacToolCallingSessionDestroyProtoDart
  rac_tool_calling_session_destroy_proto;

  // Cancel an in-flight tool-calling session.
  final RacToolCallingSessionCancelProtoDart
  rac_tool_calling_session_cancel_proto;

  // Model format + artifact inference proto APIs -----------------

  final RacModelFormatFromUrlProtoDart rac_model_format_from_url_proto;

  final RacArtifactInferFromUrlProtoDart rac_artifact_infer_from_url_proto;

  // Chunk-feed streaming STT sessions (rac_stt_stream.h) ----------

  /// `rac_stt_component_load_model(handle, path, id, name)`.
  final RacSttComponentLoadModelDart rac_stt_component_load_model;

  /// Flutter platform helper: register stream callback via Dart native port.
  final RaFlutterSttSetStreamNativePortDart?
  ra_flutter_stt_set_stream_proto_native_port;

  /// Flutter platform helper: unset stream callback and free native-port context.
  final RaFlutterSttUnsetStreamNativePortDart?
  ra_flutter_stt_unset_stream_proto_native_port;

  /// `rac_stt_stream_start_proto(handle, options_bytes, size, out_session)`.
  final RacSttStreamStartProtoDart rac_stt_stream_start_proto;

  /// `rac_stt_stream_feed_audio_proto(session, audio_bytes, size)`.
  final RacSttStreamFeedAudioProtoDart rac_stt_stream_feed_audio_proto;

  /// `rac_stt_stream_stop_proto(session)` — flushes the final result.
  final RacSttStreamFinishProtoDart rac_stt_stream_stop_proto;

  /// `rac_stt_stream_cancel_proto(session)` — immediate teardown.
  final RacSttStreamFinishProtoDart rac_stt_stream_cancel_proto;

  // Voice agent proto APIs -----------------------------------------

  final RacVoiceAgentProcessTurnProto2Dart? rac_voice_agent_process_turn_proto;

  /// `rac_voice_agent_cancel_turn_proto(handle, VoiceAgentTurnRequest)` —
  /// request-scoped cooperative cancellation for a blocking voice turn.
  final RacVoiceAgentCancelTurnProtoDart? rac_voice_agent_cancel_turn_proto;

  final RacVoiceAgentHelperProtoDart? rac_voice_agent_transcribe_proto;

  final RacVoiceAgentHelperProtoDart? rac_voice_agent_synthesize_speech_proto;

  final RacVoiceAgentComponentCreateProtoDart
  rac_voice_agent_component_create_proto;

  final RacVoiceAgentComponentDestroyProtoDart
  rac_voice_agent_component_destroy_proto;

  /// `rac_structured_output_parse_proto` — parses structured output JSON from
  /// raw model text. Takes a serialized `StructuredOutputParseRequest` and
  /// returns a `StructuredOutputResult`.
  final RacLifecycleRequestProtoDart rac_structured_output_parse_proto;

  /// `rac_structured_output_generate_proto` — runs full structured-output
  /// generation against the lifecycle-owned LLM. Takes a serialized
  /// `StructuredOutputRequest` and returns a `StructuredOutputResult`.
  final RacLifecycleRequestProtoDart rac_structured_output_generate_proto;

  /// `rac_structured_output_prepare_prompt_proto` — builds the
  /// schema-instrumented prompt for structured output. Takes a serialized
  /// `StructuredOutputRequest` and returns a `StructuredOutputPromptResult`.
  final RacLifecycleRequestProtoDart rac_structured_output_prepare_prompt_proto;

  /// `rac_structured_output_schema_to_json_proto` — serializes a
  /// `JSONSchema` proto to canonical compact, key-sorted JSON Schema text.
  /// Mirrors Swift `RAJSONSchema.jsonSchemaString`. Output bytes
  /// are raw UTF-8 text, NOT a proto message; callers extract the string
  /// directly from the `rac_proto_buffer_t` data field.
  final RacLifecycleRequestProtoDart rac_structured_output_schema_to_json_proto;

  // Tool value ↔ JSON proto APIs (rac_tool_calling.h) -------------

  /// `rac_tool_value_to_json_proto` — serializes a `ToolValue` proto into a
  /// `ToolValueJSON` wrapper carrying the canonical JSON text.
  final RacLifecycleRequestProtoDart rac_tool_value_to_json_proto;

  /// `rac_tool_value_from_json_proto` — parses a `ToolValueJSON` wrapper back
  /// into a `ToolValue` proto.
  final RacLifecycleRequestProtoDart rac_tool_value_from_json_proto;

  // Per-modality proto-byte stream quiesce ABI ------------------------------
  //
  // Each `rac_<modality>_proto_quiesce()` spin-waits until every in-flight
  // proto-byte stream dispatch on that modality has returned. Stream wrappers
  // MUST call this before closing the `NativeCallable` whose `user_data`
  // backed the C dispatcher; otherwise the dispatcher (which copies the
  // callback slot under its internal mutex and releases it BEFORE invoking
  // the user callback — see commons `*_stream.cpp` lock-release-before-callback
  // comment) can fire on a freed `user_data`. Mirrors Swift's
  // `HandleStreamAdapter` lock-release-then-unregister pattern in
  // `sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/HandleStreamAdapter.swift`.

  /// `rac_llm_proto_quiesce` — spin-wait LLM stream dispatches to drain.
  final RacProtoQuiesceDart rac_llm_proto_quiesce;

  /// `rac_stt_proto_quiesce` — spin-wait STT stream dispatches to drain.
  final RacProtoQuiesceDart rac_stt_proto_quiesce;

  /// `rac_tts_proto_quiesce` — spin-wait TTS stream dispatches to drain.
  final RacProtoQuiesceDart rac_tts_proto_quiesce;

  /// `rac_vad_proto_quiesce` — spin-wait VAD activity dispatches to drain.
  final RacProtoQuiesceDart rac_vad_proto_quiesce;

  /// `rac_vlm_proto_quiesce` — spin-wait VLM stream dispatches to drain.
  final RacProtoQuiesceDart rac_vlm_proto_quiesce;

  /// `rac_voice_agent_proto_quiesce` — spin-wait voice-agent dispatches.
  final RacProtoQuiesceDart rac_voice_agent_proto_quiesce;

  // SDK metadata + enum convenience helpers ----------------------------------

  /// `rac_sdk_get_version` — canonical SDK semver string from commons
  /// (mirrors Swift `SDKConstants.version`).
  final RacSdkGetVersionDart rac_sdk_get_version;

  /// `rac_env_is_production(rac_environment_t)` — true only for production.
  final RacEnvPredicateDart? rac_env_is_production;

  /// `rac_env_is_testing(rac_environment_t)` — true for development/staging.
  final RacEnvPredicateDart? rac_env_is_testing;

  /// `rac_env_requires_auth(rac_environment_t)` — true for non-development.
  final RacEnvPredicateDart? rac_env_requires_auth;

  /// `rac_env_requires_backend_url(rac_environment_t)` — true for
  /// staging/production.
  final RacEnvPredicateDart? rac_env_requires_backend_url;

  /// `rac_env_should_send_telemetry(rac_environment_t)` — true only for
  /// production.
  final RacEnvPredicateDart? rac_env_should_send_telemetry;

  /// `rac_env_should_sync_with_backend(rac_environment_t)` — true for
  /// staging/production.
  final RacEnvPredicateDart? rac_env_should_sync_with_backend;

  /// `rac_inference_framework_analytics_key` — snake_case analytics key for
  /// a C `rac_inference_framework_t` value (mirrors Swift
  /// `RAInferenceFramework.analyticsKey`). Out pointer is static — never free.
  final RacEnumToCStringDart rac_inference_framework_analytics_key;

  /// `rac_model_category_default_framework` — fallback
  /// `rac_inference_framework_t` for a C `rac_model_category_t` value.
  final RacEnumToIntDart rac_model_category_default_framework;

  /// `rac_model_category_requires_context_length` — `rac_bool_t` for a C
  /// `rac_model_category_t` value.
  final RacEnumToIntDart rac_model_category_requires_context_length;
}

/// Entry point for the typed commons FFI bindings.
class RacNative {
  RacNative._();

  static final RacBindings bindings = RacBindings(
    PlatformLoader.loadCommons(),
    PlatformLoader.tryLoadFlutterNativePortHelpers(),
  );
}
