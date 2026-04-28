///
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:async' as $async;

import 'package:protobuf/protobuf.dart' as $pb;

import 'dart:core' as $core;
import 'voice_agent_service.pb.dart' as $1;
import 'voice_events.pb.dart' as $0;
import 'voice_agent_service.pbjson.dart';

export 'voice_agent_service.pb.dart';

abstract class VoiceAgentServiceBase extends $pb.GeneratedService {
  $async.Future<$0.VoiceEvent> stream($pb.ServerContext ctx, $1.VoiceAgentRequest request);

  $pb.GeneratedMessage createRequest($core.String method) {
    switch (method) {
      case 'Stream': return $1.VoiceAgentRequest();
      default: throw $core.ArgumentError('Unknown method: $method');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String method, $pb.GeneratedMessage request) {
    switch (method) {
      case 'Stream': return this.stream(ctx, request as $1.VoiceAgentRequest);
      default: throw $core.ArgumentError('Unknown method: $method');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => VoiceAgentServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => VoiceAgentServiceBase$messageJson;
}

