//
//  Generated code. Do not modify.
//  source: tts_options.proto
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

import 'tts_options.pb.dart' as $13;
import 'tts_options.pbjson.dart';

export 'tts_options.pb.dart';

abstract class TTSServiceBase extends $pb.GeneratedService {
  $async.Future<$13.TTSOutput> synthesize($pb.ServerContext ctx, $13.TTSSynthesisRequest request);
  $async.Future<$13.TTSStreamEvent> stream($pb.ServerContext ctx, $13.TTSSynthesisRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Synthesize': return $13.TTSSynthesisRequest();
      case 'Stream': return $13.TTSSynthesisRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Synthesize': return this.synthesize(ctx, request as $13.TTSSynthesisRequest);
      case 'Stream': return this.stream(ctx, request as $13.TTSSynthesisRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => TTSServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => TTSServiceBase$messageJson;
}

