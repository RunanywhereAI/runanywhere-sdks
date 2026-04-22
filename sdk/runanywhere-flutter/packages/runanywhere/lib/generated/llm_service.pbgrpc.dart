//
//  Generated code. Do not modify.
//  source: llm_service.proto
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

import 'llm_service.pb.dart' as $2;

export 'llm_service.pb.dart';

@$pb.GrpcServiceName('runanywhere.v1.LLM')
class LLMClient extends $grpc.Client {
  static final _$generate = $grpc.ClientMethod<$2.LLMGenerateRequest, $2.LLMToken>(
      '/runanywhere.v1.LLM/Generate',
      ($2.LLMGenerateRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $2.LLMToken.fromBuffer(value));

  LLMClient($grpc.ClientChannel channel,
      {$grpc.CallOptions? options,
      $core.Iterable<$grpc.ClientInterceptor>? interceptors})
      : super(channel, options: options,
        interceptors: interceptors);

  $grpc.ResponseStream<$2.LLMToken> generate($2.LLMGenerateRequest request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$generate, $async.Stream.fromIterable([request]), options: options);
  }
}

@$pb.GrpcServiceName('runanywhere.v1.LLM')
abstract class LLMServiceBase extends $grpc.Service {
  $core.String get $name => 'runanywhere.v1.LLM';

  LLMServiceBase() {
    $addMethod($grpc.ServiceMethod<$2.LLMGenerateRequest, $2.LLMToken>(
        'Generate',
        generate_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $2.LLMGenerateRequest.fromBuffer(value),
        ($2.LLMToken value) => value.writeToBuffer()));
  }

  $async.Stream<$2.LLMToken> generate_Pre($grpc.ServiceCall call, $async.Future<$2.LLMGenerateRequest> request) async* {
    yield* generate(call, await request);
  }

  $async.Stream<$2.LLMToken> generate($grpc.ServiceCall call, $2.LLMGenerateRequest request);
}
