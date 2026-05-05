//
//  Generated code. Do not modify.
//  source: vlm_options.proto
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

import 'vlm_options.pb.dart' as $16;
import 'vlm_options.pbjson.dart';

export 'vlm_options.pb.dart';

abstract class VLMServiceBase extends $pb.GeneratedService {
  $async.Future<$16.VLMResult> generate($pb.ServerContext ctx, $16.VLMGenerationRequest request);
  $async.Future<$16.VLMStreamEvent> stream($pb.ServerContext ctx, $16.VLMGenerationRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Generate': return $16.VLMGenerationRequest();
      case 'Stream': return $16.VLMGenerationRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Generate': return this.generate(ctx, request as $16.VLMGenerationRequest);
      case 'Stream': return this.stream(ctx, request as $16.VLMGenerationRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => VLMServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => VLMServiceBase$messageJson;
}

