//
//  Generated code. Do not modify.
//  source: stt_options.proto
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

import 'stt_options.pb.dart' as $14;
import 'stt_options.pbjson.dart';

export 'stt_options.pb.dart';

abstract class STTServiceBase extends $pb.GeneratedService {
  $async.Future<$14.STTOutput> transcribe($pb.ServerContext ctx, $14.STTTranscriptionRequest request);
  $async.Future<$14.STTStreamEvent> stream($pb.ServerContext ctx, $14.STTTranscriptionRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Transcribe': return $14.STTTranscriptionRequest();
      case 'Stream': return $14.STTTranscriptionRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Transcribe': return this.transcribe(ctx, request as $14.STTTranscriptionRequest);
      case 'Stream': return this.stream(ctx, request as $14.STTTranscriptionRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => STTServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => STTServiceBase$messageJson;
}

