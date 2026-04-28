// This is a generated file - do not edit.
//
// Generated from voice_agent_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'voice_agent_service.pb.dart' as $1;
import 'voice_agent_service.pbjson.dart';
import 'voice_events.pb.dart' as $0;

export 'voice_agent_service.pb.dart';

abstract class VoiceAgentServiceBase extends $pb.GeneratedService {
  $async.Future<$0.VoiceEvent> stream(
      $pb.ServerContext ctx, $1.VoiceAgentRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Stream':
        return $1.VoiceAgentRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Stream':
        return stream(ctx, request as $1.VoiceAgentRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json =>
      VoiceAgentServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => VoiceAgentServiceBase$messageJson;
}
