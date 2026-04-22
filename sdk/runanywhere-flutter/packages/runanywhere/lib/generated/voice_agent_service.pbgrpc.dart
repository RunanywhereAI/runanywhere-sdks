//
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'voice_agent_service.pb.dart' as $0;
import 'voice_events.pb.dart' as $1;

export 'voice_agent_service.pb.dart';

@$pb.GrpcServiceName('runanywhere.v1.VoiceAgent')
class VoiceAgentClient extends $grpc.Client {
  static final _$stream = $grpc.ClientMethod<$0.VoiceAgentRequest, $1.VoiceEvent>(
      '/runanywhere.v1.VoiceAgent/Stream',
      ($0.VoiceAgentRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $1.VoiceEvent.fromBuffer(value));

  VoiceAgentClient($grpc.ClientChannel channel,
      {$grpc.CallOptions? options,
      $core.Iterable<$grpc.ClientInterceptor>? interceptors})
      : super(channel, options: options,
        interceptors: interceptors);

  $grpc.ResponseStream<$1.VoiceEvent> stream($0.VoiceAgentRequest request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$stream, $async.Stream.fromIterable([request]), options: options);
  }
}

@$pb.GrpcServiceName('runanywhere.v1.VoiceAgent')
abstract class VoiceAgentServiceBase extends $grpc.Service {
  $core.String get $name => 'runanywhere.v1.VoiceAgent';

  VoiceAgentServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.VoiceAgentRequest, $1.VoiceEvent>(
        'Stream',
        stream_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.VoiceAgentRequest.fromBuffer(value),
        ($1.VoiceEvent value) => value.writeToBuffer()));
  }

  $async.Stream<$1.VoiceEvent> stream_Pre($grpc.ServiceCall call, $async.Future<$0.VoiceAgentRequest> request) async* {
    yield* stream(call, await request);
  }

  $async.Stream<$1.VoiceEvent> stream($grpc.ServiceCall call, $0.VoiceAgentRequest request);
}
