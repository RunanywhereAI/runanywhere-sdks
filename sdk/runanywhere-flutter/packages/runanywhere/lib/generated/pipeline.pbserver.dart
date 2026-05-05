//
//  Generated code. Do not modify.
//  source: pipeline.proto
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

import 'pipeline.pb.dart' as $5;
import 'pipeline.pbjson.dart';

export 'pipeline.pb.dart';

abstract class PipelineServiceBase extends $pb.GeneratedService {
  $async.Future<$5.PipelineCompileResult> compile($pb.ServerContext ctx, $5.PipelineSpec request);
  $async.Future<$5.PipelineHandle> start($pb.ServerContext ctx, $5.PipelineStartRequest request);
  $async.Future<$5.PipelineStopResult> stop($pb.ServerContext ctx, $5.PipelineHandle request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Compile': return $5.PipelineSpec();
      case 'Start': return $5.PipelineStartRequest();
      case 'Stop': return $5.PipelineHandle();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Compile': return this.compile(ctx, request as $5.PipelineSpec);
      case 'Start': return this.start(ctx, request as $5.PipelineStartRequest);
      case 'Stop': return this.stop(ctx, request as $5.PipelineHandle);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => PipelineServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => PipelineServiceBase$messageJson;
}

