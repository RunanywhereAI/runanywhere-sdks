//
//  Generated code. Do not modify.
//  source: download_service.proto
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

import 'download_service.pb.dart' as $7;
import 'download_service.pbjson.dart';

export 'download_service.pb.dart';

abstract class DownloadServiceBase extends $pb.GeneratedService {
  $async.Future<$7.DownloadPlanResult> plan($pb.ServerContext ctx, $7.DownloadPlanRequest request);
  $async.Future<$7.DownloadStartResult> start($pb.ServerContext ctx, $7.DownloadStartRequest request);
  $async.Future<$7.DownloadProgress> subscribe($pb.ServerContext ctx, $7.DownloadSubscribeRequest request);
  $async.Future<$7.DownloadCancelResult> cancel($pb.ServerContext ctx, $7.DownloadCancelRequest request);
  $async.Future<$7.DownloadResumeResult> resume($pb.ServerContext ctx, $7.DownloadResumeRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Plan': return $7.DownloadPlanRequest();
      case 'Start': return $7.DownloadStartRequest();
      case 'Subscribe': return $7.DownloadSubscribeRequest();
      case 'Cancel': return $7.DownloadCancelRequest();
      case 'Resume': return $7.DownloadResumeRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Plan': return this.plan(ctx, request as $7.DownloadPlanRequest);
      case 'Start': return this.start(ctx, request as $7.DownloadStartRequest);
      case 'Subscribe': return this.subscribe(ctx, request as $7.DownloadSubscribeRequest);
      case 'Cancel': return this.cancel(ctx, request as $7.DownloadCancelRequest);
      case 'Resume': return this.resume(ctx, request as $7.DownloadResumeRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => DownloadServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => DownloadServiceBase$messageJson;
}

