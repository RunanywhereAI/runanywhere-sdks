//
//  Generated code. Do not modify.
//  source: vad_options.proto
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

import 'vad_options.pb.dart' as $11;
import 'vad_options.pbjson.dart';

export 'vad_options.pb.dart';

abstract class VADServiceBase extends $pb.GeneratedService {
  $async.Future<$11.VADResult> processFrame($pb.ServerContext ctx, $11.VADProcessRequest request);
  $async.Future<$11.VADStreamEvent> stream($pb.ServerContext ctx, $11.VADProcessRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'ProcessFrame': return $11.VADProcessRequest();
      case 'Stream': return $11.VADProcessRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'ProcessFrame': return this.processFrame(ctx, request as $11.VADProcessRequest);
      case 'Stream': return this.stream(ctx, request as $11.VADProcessRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => VADServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => VADServiceBase$messageJson;
}

