//
//  Generated code. Do not modify.
//  source: diffusion_options.proto
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

import 'diffusion_options.pb.dart' as $1;
import 'diffusion_options.pbjson.dart';

export 'diffusion_options.pb.dart';

abstract class DiffusionServiceBase extends $pb.GeneratedService {
  $async.Future<$1.DiffusionResult> generate($pb.ServerContext ctx, $1.DiffusionGenerationRequest request);
  $async.Future<$1.DiffusionStreamEvent> stream($pb.ServerContext ctx, $1.DiffusionGenerationRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Generate': return $1.DiffusionGenerationRequest();
      case 'Stream': return $1.DiffusionGenerationRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Generate': return this.generate(ctx, request as $1.DiffusionGenerationRequest);
      case 'Stream': return this.stream(ctx, request as $1.DiffusionGenerationRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => DiffusionServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => DiffusionServiceBase$messageJson;
}

