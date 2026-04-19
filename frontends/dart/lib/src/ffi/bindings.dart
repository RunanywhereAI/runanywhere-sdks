// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Hand-written FFI bindings for the `ra_pipeline_*` C ABI surface in
// core/abi/ra_pipeline.h. Chose hand-rolled over ffigen because the struct
// has only ~10 fields and the callback signatures are simpler to hand-write
// than to coax out of ffigen.
//
// Loads `libracommons_core.dylib` (macOS) / `libracommons_core.so` (Linux) /
// `racommons_core.dll` (Windows) / `libracommons_core.so` packaged inside
// the platform-specific APK (Android).

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' show Utf8;

const int raOk              =  0;
const int raErrCancelled    = -1;
const int raErrInvalidArg   = -2;
const int raErrBackendUnavailable = -6;
const int raErrInternal     = -99;

const int raAudioSourceMicrophone = 1;
const int raAudioSourceFile       = 2;
const int raAudioSourceCallback   = 3;

const int raVoiceEventUserSaid       = 1;
const int raVoiceEventAssistantToken = 2;
const int raVoiceEventAudio          = 3;
const int raVoiceEventVad            = 4;
const int raVoiceEventInterrupted    = 5;
const int raVoiceEventStateChange    = 6;
const int raVoiceEventError          = 7;
const int raVoiceEventMetrics        = 8;

/// C `ra_voice_agent_config_t`.
final class RaVoiceAgentConfig extends Struct {
  external Pointer<Utf8> llmModelId;
  external Pointer<Utf8> sttModelId;
  external Pointer<Utf8> ttsModelId;
  external Pointer<Utf8> vadModelId;

  @Int32()
  external int sampleRateHz;
  @Int32()
  external int chunkMs;
  @Int32()
  external int audioSource;

  external Pointer<Utf8> audioFilePath;

  @Uint8()
  external int enableBargeIn;
  @Int32()
  external int bargeInThresholdMs;

  external Pointer<Utf8> systemPrompt;
  @Int32()
  external int maxContextTokens;
  @Float()
  external double temperature;

  @Uint8()
  external int emitPartials;
  @Uint8()
  external int emitThoughts;
  @Uint8()
  external int _reserved0;
  @Uint8()
  external int _reserved1;
}

/// C `ra_voice_event_t`.
final class RaVoiceEvent extends Struct {
  @Int32()
  external int kind;
  @Uint64()
  external int seq;

  external Pointer<Utf8> text;
  @Uint8()
  external int isFinal;
  @Uint8()
  external int _r0;
  @Uint8()
  external int _r1;
  @Uint8()
  external int _r2;
  @Int32()
  external int tokenKind;
  @Int32()
  external int vadType;

  external Pointer<Float> pcmF32;
  @Int32()
  external int pcmLen;
  @Int32()
  external int sampleRateHz;

  @Int32()
  external int prevState;
  @Int32()
  external int currState;

  @Double()
  external double sttFinalMs;
  @Double()
  external double llmFirstTokenMs;
  @Double()
  external double ttsFirstAudioMs;
  @Double()
  external double endToEndMs;

  @Int32()
  external int errorCode;
}

// C callback type signatures.
typedef NativeVoiceEventCb  = Void Function(Pointer<RaVoiceEvent>, Pointer<Void>);
typedef NativeCompletionCb  = Void Function(Int32, Pointer<Utf8>, Pointer<Void>);

// C function signatures.
typedef _CreateVoiceAgentNative = Int32 Function(
    Pointer<RaVoiceAgentConfig>, Pointer<Pointer<Void>>);
typedef _DestroyNative          = Void  Function(Pointer<Void>);
typedef _SetEventCbNative       = Int32 Function(
    Pointer<Void>, Pointer<NativeFunction<NativeVoiceEventCb>>, Pointer<Void>);
typedef _SetCompletionCbNative  = Int32 Function(
    Pointer<Void>, Pointer<NativeFunction<NativeCompletionCb>>, Pointer<Void>);
typedef _RunNative              = Int32 Function(Pointer<Void>);
typedef _CancelNative           = Int32 Function(Pointer<Void>);
typedef _FeedAudioNative        = Int32 Function(
    Pointer<Void>, Pointer<Float>, Int32, Int32);
typedef _InjectBargeInNative    = Int32 Function(Pointer<Void>);

// Dart function signatures.
typedef CreateVoiceAgent = int Function(
    Pointer<RaVoiceAgentConfig>, Pointer<Pointer<Void>>);
typedef Destroy          = void Function(Pointer<Void>);
typedef SetEventCb       = int Function(
    Pointer<Void>, Pointer<NativeFunction<NativeVoiceEventCb>>, Pointer<Void>);
typedef SetCompletionCb  = int Function(
    Pointer<Void>, Pointer<NativeFunction<NativeCompletionCb>>, Pointer<Void>);
typedef Run              = int Function(Pointer<Void>);
typedef Cancel           = int Function(Pointer<Void>);
typedef FeedAudio        = int Function(
    Pointer<Void>, Pointer<Float>, int, int);
typedef InjectBargeIn    = int Function(Pointer<Void>);

/// Bound once per process.
final class RaCoreBindings {
  final CreateVoiceAgent  createVoiceAgent;
  final Destroy           destroy;
  final SetEventCb        setEventCallback;
  final SetCompletionCb   setCompletionCallback;
  final Run               run;
  final Cancel            cancel;
  final FeedAudio         feedAudio;
  final InjectBargeIn     injectBargeIn;

  RaCoreBindings._({
    required this.createVoiceAgent,
    required this.destroy,
    required this.setEventCallback,
    required this.setCompletionCallback,
    required this.run,
    required this.cancel,
    required this.feedAudio,
    required this.injectBargeIn,
  });

  factory RaCoreBindings.open([String? libraryPath]) {
    final lib = DynamicLibrary.open(libraryPath ?? _defaultLibraryPath());
    return RaCoreBindings._(
      createVoiceAgent: lib
          .lookupFunction<_CreateVoiceAgentNative, CreateVoiceAgent>(
              'ra_pipeline_create_voice_agent'),
      destroy: lib.lookupFunction<_DestroyNative, Destroy>('ra_pipeline_destroy'),
      setEventCallback: lib.lookupFunction<_SetEventCbNative, SetEventCb>(
          'ra_pipeline_set_event_callback'),
      setCompletionCallback: lib
          .lookupFunction<_SetCompletionCbNative, SetCompletionCb>(
              'ra_pipeline_set_completion_callback'),
      run:    lib.lookupFunction<_RunNative, Run>('ra_pipeline_run'),
      cancel: lib.lookupFunction<_CancelNative, Cancel>('ra_pipeline_cancel'),
      feedAudio: lib.lookupFunction<_FeedAudioNative, FeedAudio>(
          'ra_pipeline_feed_audio'),
      injectBargeIn: lib.lookupFunction<_InjectBargeInNative, InjectBargeIn>(
          'ra_pipeline_inject_barge_in'),
    );
  }

  static String _defaultLibraryPath() {
    if (Platform.isMacOS)   return 'libracommons_core.dylib';
    if (Platform.isIOS)     return 'RACommonsCore.framework/RACommonsCore';
    if (Platform.isAndroid) return 'libracommons_core.so';
    if (Platform.isLinux)   return 'libracommons_core.so';
    if (Platform.isWindows) return 'racommons_core.dll';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
