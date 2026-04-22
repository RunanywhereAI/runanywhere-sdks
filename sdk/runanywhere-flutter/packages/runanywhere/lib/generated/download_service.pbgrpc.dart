//
//  Generated code. Do not modify.
//  source: download_service.proto
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

import 'download_service.pb.dart' as $3;

export 'download_service.pb.dart';

@$pb.GrpcServiceName('runanywhere.v1.Download')
class DownloadClient extends $grpc.Client {
  static final _$subscribe = $grpc.ClientMethod<$3.DownloadSubscribeRequest, $3.DownloadProgress>(
      '/runanywhere.v1.Download/Subscribe',
      ($3.DownloadSubscribeRequest value) => value.writeToBuffer(),
      ($core.List<$core.int> value) => $3.DownloadProgress.fromBuffer(value));

  DownloadClient($grpc.ClientChannel channel,
      {$grpc.CallOptions? options,
      $core.Iterable<$grpc.ClientInterceptor>? interceptors})
      : super(channel, options: options,
        interceptors: interceptors);

  $grpc.ResponseStream<$3.DownloadProgress> subscribe($3.DownloadSubscribeRequest request, {$grpc.CallOptions? options}) {
    return $createStreamingCall(_$subscribe, $async.Stream.fromIterable([request]), options: options);
  }
}

@$pb.GrpcServiceName('runanywhere.v1.Download')
abstract class DownloadServiceBase extends $grpc.Service {
  $core.String get $name => 'runanywhere.v1.Download';

  DownloadServiceBase() {
    $addMethod($grpc.ServiceMethod<$3.DownloadSubscribeRequest, $3.DownloadProgress>(
        'Subscribe',
        subscribe_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $3.DownloadSubscribeRequest.fromBuffer(value),
        ($3.DownloadProgress value) => value.writeToBuffer()));
  }

  $async.Stream<$3.DownloadProgress> subscribe_Pre($grpc.ServiceCall call, $async.Future<$3.DownloadSubscribeRequest> request) async* {
    yield* subscribe(call, await request);
  }

  $async.Stream<$3.DownloadProgress> subscribe($grpc.ServiceCall call, $3.DownloadSubscribeRequest request);
}
