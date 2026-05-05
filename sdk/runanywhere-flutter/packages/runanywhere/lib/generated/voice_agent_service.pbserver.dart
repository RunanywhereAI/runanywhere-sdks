//
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'stt_options.pb.dart' as $2;
import 'tts_options.pb.dart' as $1;
import 'voice_agent_service.pb.dart' as $5;
import 'voice_agent_service.pbjson.dart';
import 'voice_events.pb.dart' as $0;

export 'voice_agent_service.pb.dart';

abstract class VoiceAgentServiceBase extends $pb.GeneratedService {
  $async.Future<$0.VoiceEvent> stream($pb.ServerContext ctx, $5.VoiceAgentRequest request);
  $async.Future<$5.VoiceAgentResult> processTurn($pb.ServerContext ctx, $5.VoiceAgentTurnRequest request);
  $async.Future<$2.STTOutput> transcribe($pb.ServerContext ctx, $5.VoiceAgentTranscribeProtoRequest request);
  $async.Future<$1.TTSOutput> synthesizeSpeech($pb.ServerContext ctx, $5.VoiceAgentSynthesizeSpeechProtoRequest request);
  $async.Future<$5.VoiceAgentResult> configure($pb.ServerContext ctx, $5.VoiceAgentComposeConfig request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Stream': return $5.VoiceAgentRequest();
      case 'ProcessTurn': return $5.VoiceAgentTurnRequest();
      case 'Transcribe': return $5.VoiceAgentTranscribeProtoRequest();
      case 'SynthesizeSpeech': return $5.VoiceAgentSynthesizeSpeechProtoRequest();
      case 'Configure': return $5.VoiceAgentComposeConfig();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Stream': return this.stream(ctx, request as $5.VoiceAgentRequest);
      case 'ProcessTurn': return this.processTurn(ctx, request as $5.VoiceAgentTurnRequest);
      case 'Transcribe': return this.transcribe(ctx, request as $5.VoiceAgentTranscribeProtoRequest);
      case 'SynthesizeSpeech': return this.synthesizeSpeech(ctx, request as $5.VoiceAgentSynthesizeSpeechProtoRequest);
      case 'Configure': return this.configure(ctx, request as $5.VoiceAgentComposeConfig);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => VoiceAgentServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => VoiceAgentServiceBase$messageJson;
}

