// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// FFI bindings for the ra_llm_* / ra_stt_* / ra_tts_* / ra_vad_* /
// ra_embed_* / ra_state_* primitive C ABI. Complements bindings.dart
// (ra_pipeline_*).

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' show Utf8;

// ---------------------------------------------------------------------------
// Shared structs
// ---------------------------------------------------------------------------

final class RaModelSpec extends Struct {
  external Pointer<Utf8> modelId;
  external Pointer<Utf8> modelPath;
  @Int32()
  external int format;
  @Int32()
  external int preferredRuntime;
}

final class RaSessionConfig extends Struct {
  @Int32()
  external int nGpuLayers;
  @Int32()
  external int nThreads;
  @Int32()
  external int contextSize;
  @Uint8()
  external int useMmap;
  @Uint8()
  external int useMlock;
  @Uint8()
  // ignore: unused_field
  external int reserved0;
  @Uint8()
  // ignore: unused_field
  external int reserved1;
}

final class RaTokenOutput extends Struct {
  external Pointer<Utf8> text;
  @Uint8()
  external int isFinal;
  @Uint8()
  // ignore: unused_field
  external int r0;
  @Uint8()
  // ignore: unused_field
  external int r1;
  @Uint8()
  // ignore: unused_field
  external int r2;
  @Int32()
  external int tokenKind;
}

final class RaTranscriptChunk extends Struct {
  external Pointer<Utf8> text;
  @Uint8()
  external int isPartial;
  @Uint8()
  // ignore: unused_field
  external int r0;
  @Uint8()
  // ignore: unused_field
  external int r1;
  @Uint8()
  // ignore: unused_field
  external int r2;
  @Float()
  external double confidence;
  @Int64()
  external int audioStartUs;
  @Int64()
  external int audioEndUs;
}

final class RaVadEvent extends Struct {
  @Int32()
  external int type;
  @Int64()
  external int frameOffsetUs;
  @Float()
  external double energy;
}

final class RaPrompt extends Struct {
  external Pointer<Utf8> text;
  @Int32()
  external int conversationId;
}

final class RaAuthData extends Struct {
  external Pointer<Utf8> accessToken;
  external Pointer<Utf8> refreshToken;
  @Int64()
  external int expiresAtUnix;
  external Pointer<Utf8> userId;
  external Pointer<Utf8> organizationId;
  external Pointer<Utf8> deviceId;
}

// ---------------------------------------------------------------------------
// Function typedefs (native + dart)
// ---------------------------------------------------------------------------

// LLM
typedef _LlmCreateNative = Int32 Function(Pointer<RaModelSpec>, Pointer<RaSessionConfig>, Pointer<Pointer<Void>>);
typedef LlmCreate        = int Function(Pointer<RaModelSpec>, Pointer<RaSessionConfig>, Pointer<Pointer<Void>>);
typedef _LlmDestroyNative = Void Function(Pointer<Void>);
typedef LlmDestroy        = void Function(Pointer<Void>);
typedef NativeTokenCb    = Void Function(Pointer<RaTokenOutput>, Pointer<Void>);
typedef NativeErrorCb    = Void Function(Int32, Pointer<Utf8>, Pointer<Void>);
typedef _LlmGenerateNative = Int32 Function(
    Pointer<Void>, Pointer<RaPrompt>,
    Pointer<NativeFunction<NativeTokenCb>>,
    Pointer<NativeFunction<NativeErrorCb>>, Pointer<Void>);
typedef LlmGenerate        = int Function(
    Pointer<Void>, Pointer<RaPrompt>,
    Pointer<NativeFunction<NativeTokenCb>>,
    Pointer<NativeFunction<NativeErrorCb>>, Pointer<Void>);
typedef _LlmCancelNative  = Int32 Function(Pointer<Void>);
typedef LlmCancel         = int Function(Pointer<Void>);
typedef _LlmStrNative     = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef LlmStr            = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _LlmGenCtxNative  = Int32 Function(
    Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<NativeTokenCb>>,
    Pointer<NativeFunction<NativeErrorCb>>, Pointer<Void>);
typedef LlmGenCtx         = int Function(
    Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<NativeTokenCb>>,
    Pointer<NativeFunction<NativeErrorCb>>, Pointer<Void>);

// STT
typedef NativeChunkCb       = Void Function(Pointer<RaTranscriptChunk>, Pointer<Void>);
typedef _SttCreateNative    = Int32 Function(Pointer<RaModelSpec>, Pointer<RaSessionConfig>, Pointer<Pointer<Void>>);
typedef SttCreate           = int Function(Pointer<RaModelSpec>, Pointer<RaSessionConfig>, Pointer<Pointer<Void>>);
typedef _SttFeedAudioNative = Int32 Function(Pointer<Void>, Pointer<Float>, Int32, Int32);
typedef SttFeedAudio        = int Function(Pointer<Void>, Pointer<Float>, int, int);
typedef _SttFlushNative     = Int32 Function(Pointer<Void>);
typedef SttFlush            = int Function(Pointer<Void>);
typedef _SttSetCbNative     = Int32 Function(Pointer<Void>, Pointer<NativeFunction<NativeChunkCb>>, Pointer<Void>);
typedef SttSetCb            = int Function(Pointer<Void>, Pointer<NativeFunction<NativeChunkCb>>, Pointer<Void>);

// TTS
typedef _TtsSynthesizeNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Float>, Int32,
    Pointer<Int32>, Pointer<Int32>);
typedef TtsSynthesize        = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Float>, int,
    Pointer<Int32>, Pointer<Int32>);

// VAD
typedef NativeVadCb      = Void Function(Pointer<RaVadEvent>, Pointer<Void>);
typedef _VadSetCbNative  = Int32 Function(Pointer<Void>, Pointer<NativeFunction<NativeVadCb>>, Pointer<Void>);
typedef VadSetCb         = int Function(Pointer<Void>, Pointer<NativeFunction<NativeVadCb>>, Pointer<Void>);

// Embed
typedef _EmbedDimsNative = Int32 Function(Pointer<Void>);
typedef EmbedDims        = int Function(Pointer<Void>);
typedef _EmbedTextNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, Int32);
typedef EmbedText        = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, int);

// SDK state
typedef _StateInitNative = Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef StateInit        = int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _StateSetAuthNative = Int32 Function(Pointer<RaAuthData>);
typedef StateSetAuth        = int Function(Pointer<RaAuthData>);
typedef _ReturnsString = Pointer<Utf8> Function();
typedef _ReturnsInt32  = Int32 Function();
typedef _ReturnsBool   = Uint8 Function();
typedef _TakesInt32 = Int32 Function(Int32);
typedef TakesInt32  = int Function(int);
typedef _TakesUtf8 = Uint8 Function(Pointer<Utf8>);
typedef TakesUtf8  = int Function(Pointer<Utf8>);
typedef _Int64Getter = Int64 Function();
typedef Int64Getter  = int Function();
typedef IntGetter = int Function();
typedef _VoidNoArgNative = Void Function();
typedef VoidNoArg        = void Function();
typedef _VoidBoolNative  = Void Function(Uint8);
typedef VoidBool         = void Function(int);

/// Lazy-loaded bindings for the primitive sessions.
final class RaPrimitiveBindings {
  final LlmCreate       llmCreate;
  final LlmDestroy      llmDestroy;
  final LlmGenerate     llmGenerate;
  final LlmCancel       llmCancel;
  final LlmCancel       llmReset;
  final LlmStr          llmInjectSystemPrompt;
  final LlmStr          llmAppendContext;
  final LlmGenCtx       llmGenerateFromContext;
  final LlmCancel       llmClearContext;

  final SttCreate       sttCreate;
  final LlmDestroy      sttDestroy;
  final SttFeedAudio    sttFeedAudio;
  final SttFlush        sttFlush;
  final SttSetCb        sttSetCallback;

  final SttCreate       ttsCreate;
  final LlmDestroy      ttsDestroy;
  final TtsSynthesize   ttsSynthesize;
  final LlmCancel       ttsCancel;

  final SttCreate       vadCreate;
  final LlmDestroy      vadDestroy;
  final SttFeedAudio    vadFeedAudio;
  final VadSetCb        vadSetCallback;

  final SttCreate       embedCreate;
  final LlmDestroy      embedDestroy;
  final EmbedText       embedText;
  final EmbedDims       embedDims;

  final StateInit            stateInitialize;
  final IntGetter            stateIsInitialized;
  final VoidNoArg            stateReset;
  final IntGetter            stateGetEnvironment;
  final Pointer<Utf8> Function() stateGetBaseUrl;
  final Pointer<Utf8> Function() stateGetApiKey;
  final Pointer<Utf8> Function() stateGetDeviceId;
  final StateSetAuth         stateSetAuth;
  final Pointer<Utf8> Function() stateGetAccessToken;
  final Pointer<Utf8> Function() stateGetRefreshToken;
  final Pointer<Utf8> Function() stateGetUserId;
  final Pointer<Utf8> Function() stateGetOrganizationId;
  final IntGetter            stateIsAuthenticated;
  final TakesInt32           stateTokenNeedsRefresh;
  final Int64Getter          stateGetTokenExpiresAt;
  final VoidNoArg            stateClearAuth;
  final IntGetter            stateIsDeviceRegistered;
  final VoidBool             stateSetDeviceRegistered;
  final TakesUtf8            stateValidateApiKey;
  final TakesUtf8            stateValidateBaseUrl;

  RaPrimitiveBindings._(Map<String, Object> fns)
      : llmCreate              = fns['llmCreate']              as LlmCreate,
        llmDestroy             = fns['llmDestroy']             as LlmDestroy,
        llmGenerate            = fns['llmGenerate']            as LlmGenerate,
        llmCancel              = fns['llmCancel']              as LlmCancel,
        llmReset               = fns['llmReset']               as LlmCancel,
        llmInjectSystemPrompt  = fns['llmInjectSystemPrompt']  as LlmStr,
        llmAppendContext       = fns['llmAppendContext']       as LlmStr,
        llmGenerateFromContext = fns['llmGenerateFromContext'] as LlmGenCtx,
        llmClearContext        = fns['llmClearContext']        as LlmCancel,
        sttCreate              = fns['sttCreate']              as SttCreate,
        sttDestroy             = fns['sttDestroy']             as LlmDestroy,
        sttFeedAudio           = fns['sttFeedAudio']           as SttFeedAudio,
        sttFlush               = fns['sttFlush']               as SttFlush,
        sttSetCallback         = fns['sttSetCallback']         as SttSetCb,
        ttsCreate              = fns['ttsCreate']              as SttCreate,
        ttsDestroy             = fns['ttsDestroy']             as LlmDestroy,
        ttsSynthesize          = fns['ttsSynthesize']          as TtsSynthesize,
        ttsCancel              = fns['ttsCancel']              as LlmCancel,
        vadCreate              = fns['vadCreate']              as SttCreate,
        vadDestroy             = fns['vadDestroy']             as LlmDestroy,
        vadFeedAudio           = fns['vadFeedAudio']           as SttFeedAudio,
        vadSetCallback         = fns['vadSetCallback']         as VadSetCb,
        embedCreate            = fns['embedCreate']            as SttCreate,
        embedDestroy           = fns['embedDestroy']           as LlmDestroy,
        embedText              = fns['embedText']              as EmbedText,
        embedDims              = fns['embedDims']              as EmbedDims,
        stateInitialize        = fns['stateInitialize']        as StateInit,
        stateIsInitialized     = fns['stateIsInitialized']     as IntGetter,
        stateReset             = fns['stateReset']             as VoidNoArg,
        stateGetEnvironment    = fns['stateGetEnvironment']    as IntGetter,
        stateGetBaseUrl        = fns['stateGetBaseUrl']        as Pointer<Utf8> Function(),
        stateGetApiKey         = fns['stateGetApiKey']         as Pointer<Utf8> Function(),
        stateGetDeviceId       = fns['stateGetDeviceId']       as Pointer<Utf8> Function(),
        stateSetAuth           = fns['stateSetAuth']           as StateSetAuth,
        stateGetAccessToken    = fns['stateGetAccessToken']    as Pointer<Utf8> Function(),
        stateGetRefreshToken   = fns['stateGetRefreshToken']   as Pointer<Utf8> Function(),
        stateGetUserId         = fns['stateGetUserId']         as Pointer<Utf8> Function(),
        stateGetOrganizationId = fns['stateGetOrganizationId'] as Pointer<Utf8> Function(),
        stateIsAuthenticated   = fns['stateIsAuthenticated']   as IntGetter,
        stateTokenNeedsRefresh = fns['stateTokenNeedsRefresh'] as TakesInt32,
        stateGetTokenExpiresAt = fns['stateGetTokenExpiresAt'] as Int64Getter,
        stateClearAuth         = fns['stateClearAuth']         as VoidNoArg,
        stateIsDeviceRegistered = fns['stateIsDeviceRegistered'] as IntGetter,
        stateSetDeviceRegistered = fns['stateSetDeviceRegistered'] as VoidBool,
        stateValidateApiKey    = fns['stateValidateApiKey']    as TakesUtf8,
        stateValidateBaseUrl   = fns['stateValidateBaseUrl']   as TakesUtf8;

  factory RaPrimitiveBindings.open([String? libraryPath]) {
    final lib = DynamicLibrary.open(libraryPath ?? _defaultLibraryPath());
    int Function() wrapBoolToInt(String sym) {
      final fn = lib.lookupFunction<_ReturnsBool, int Function()>(sym);
      return fn;
    }
    return RaPrimitiveBindings._({
      'llmCreate':              lib.lookupFunction<_LlmCreateNative, LlmCreate>('ra_llm_create'),
      'llmDestroy':             lib.lookupFunction<_LlmDestroyNative, LlmDestroy>('ra_llm_destroy'),
      'llmGenerate':            lib.lookupFunction<_LlmGenerateNative, LlmGenerate>('ra_llm_generate'),
      'llmCancel':              lib.lookupFunction<_LlmCancelNative, LlmCancel>('ra_llm_cancel'),
      'llmReset':               lib.lookupFunction<_LlmCancelNative, LlmCancel>('ra_llm_reset'),
      'llmInjectSystemPrompt':  lib.lookupFunction<_LlmStrNative, LlmStr>('ra_llm_inject_system_prompt'),
      'llmAppendContext':       lib.lookupFunction<_LlmStrNative, LlmStr>('ra_llm_append_context'),
      'llmGenerateFromContext': lib.lookupFunction<_LlmGenCtxNative, LlmGenCtx>('ra_llm_generate_from_context'),
      'llmClearContext':        lib.lookupFunction<_LlmCancelNative, LlmCancel>('ra_llm_clear_context'),
      'sttCreate':              lib.lookupFunction<_SttCreateNative, SttCreate>('ra_stt_create'),
      'sttDestroy':             lib.lookupFunction<_LlmDestroyNative, LlmDestroy>('ra_stt_destroy'),
      'sttFeedAudio':           lib.lookupFunction<_SttFeedAudioNative, SttFeedAudio>('ra_stt_feed_audio'),
      'sttFlush':               lib.lookupFunction<_SttFlushNative, SttFlush>('ra_stt_flush'),
      'sttSetCallback':         lib.lookupFunction<_SttSetCbNative, SttSetCb>('ra_stt_set_callback'),
      'ttsCreate':              lib.lookupFunction<_SttCreateNative, SttCreate>('ra_tts_create'),
      'ttsDestroy':             lib.lookupFunction<_LlmDestroyNative, LlmDestroy>('ra_tts_destroy'),
      'ttsSynthesize':          lib.lookupFunction<_TtsSynthesizeNative, TtsSynthesize>('ra_tts_synthesize'),
      'ttsCancel':              lib.lookupFunction<_LlmCancelNative, LlmCancel>('ra_tts_cancel'),
      'vadCreate':              lib.lookupFunction<_SttCreateNative, SttCreate>('ra_vad_create'),
      'vadDestroy':             lib.lookupFunction<_LlmDestroyNative, LlmDestroy>('ra_vad_destroy'),
      'vadFeedAudio':           lib.lookupFunction<_SttFeedAudioNative, SttFeedAudio>('ra_vad_feed_audio'),
      'vadSetCallback':         lib.lookupFunction<_VadSetCbNative, VadSetCb>('ra_vad_set_callback'),
      'embedCreate':            lib.lookupFunction<_SttCreateNative, SttCreate>('ra_embed_create'),
      'embedDestroy':           lib.lookupFunction<_LlmDestroyNative, LlmDestroy>('ra_embed_destroy'),
      'embedText':              lib.lookupFunction<_EmbedTextNative, EmbedText>('ra_embed_text'),
      'embedDims':              lib.lookupFunction<_EmbedDimsNative, EmbedDims>('ra_embed_dims'),
      'stateInitialize':        lib.lookupFunction<_StateInitNative, StateInit>('ra_state_initialize'),
      'stateIsInitialized':     wrapBoolToInt('ra_state_is_initialized'),
      'stateReset':             lib.lookupFunction<_VoidNoArgNative, VoidNoArg>('ra_state_reset'),
      'stateGetEnvironment':    lib.lookupFunction<_ReturnsInt32, IntGetter>('ra_state_get_environment'),
      'stateGetBaseUrl':        lib.lookupFunction<_ReturnsString, Pointer<Utf8> Function()>('ra_state_get_base_url'),
      'stateGetApiKey':         lib.lookupFunction<_ReturnsString, Pointer<Utf8> Function()>('ra_state_get_api_key'),
      'stateGetDeviceId':       lib.lookupFunction<_ReturnsString, Pointer<Utf8> Function()>('ra_state_get_device_id'),
      'stateSetAuth':           lib.lookupFunction<_StateSetAuthNative, StateSetAuth>('ra_state_set_auth'),
      'stateGetAccessToken':    lib.lookupFunction<_ReturnsString, Pointer<Utf8> Function()>('ra_state_get_access_token'),
      'stateGetRefreshToken':   lib.lookupFunction<_ReturnsString, Pointer<Utf8> Function()>('ra_state_get_refresh_token'),
      'stateGetUserId':         lib.lookupFunction<_ReturnsString, Pointer<Utf8> Function()>('ra_state_get_user_id'),
      'stateGetOrganizationId': lib.lookupFunction<_ReturnsString, Pointer<Utf8> Function()>('ra_state_get_organization_id'),
      'stateIsAuthenticated':   wrapBoolToInt('ra_state_is_authenticated'),
      'stateTokenNeedsRefresh': lib.lookupFunction<_TakesInt32, TakesInt32>('ra_state_token_needs_refresh'),
      'stateGetTokenExpiresAt': lib.lookupFunction<_Int64Getter, Int64Getter>('ra_state_get_token_expires_at'),
      'stateClearAuth':         lib.lookupFunction<_VoidNoArgNative, VoidNoArg>('ra_state_clear_auth'),
      'stateIsDeviceRegistered': wrapBoolToInt('ra_state_is_device_registered'),
      'stateSetDeviceRegistered': lib.lookupFunction<_VoidBoolNative, VoidBool>('ra_state_set_device_registered'),
      'stateValidateApiKey':    lib.lookupFunction<_TakesUtf8, TakesUtf8>('ra_validate_api_key'),
      'stateValidateBaseUrl':   lib.lookupFunction<_TakesUtf8, TakesUtf8>('ra_validate_base_url'),
    });
  }

  static RaPrimitiveBindings? _cached;
  static RaPrimitiveBindings instance() {
    _cached ??= RaPrimitiveBindings.open();
    return _cached!;
  }

  static String _defaultLibraryPath() {
    if (Platform.isMacOS)   return 'libracommons_core.dylib';
    if (Platform.isIOS)     return 'RACommonsCore.framework/RACommonsCore';
    if (Platform.isAndroid) return 'libracommons_core.so';
    if (Platform.isLinux)   return 'libracommons_core.so';
    if (Platform.isWindows) return 'racommons_core.dll';
    throw UnsupportedError('Unsupported platform');
  }
}
