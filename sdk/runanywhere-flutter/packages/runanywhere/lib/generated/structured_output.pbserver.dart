//
//  Generated code. Do not modify.
//  source: structured_output.proto
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

import 'structured_output.pb.dart' as $11;
import 'structured_output.pbjson.dart';

export 'structured_output.pb.dart';

abstract class StructuredOutputServiceBase extends $pb.GeneratedService {
  $async.Future<$11.StructuredOutputPromptResult> preparePrompt($pb.ServerContext ctx, $11.StructuredOutputRequest request);
  $async.Future<$11.StructuredOutputValidation> validate($pb.ServerContext ctx, $11.StructuredOutputValidationRequest request);
  $async.Future<$11.StructuredOutputResult> parse($pb.ServerContext ctx, $11.StructuredOutputParseRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'PreparePrompt': return $11.StructuredOutputRequest();
      case 'Validate': return $11.StructuredOutputValidationRequest();
      case 'Parse': return $11.StructuredOutputParseRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'PreparePrompt': return this.preparePrompt(ctx, request as $11.StructuredOutputRequest);
      case 'Validate': return this.validate(ctx, request as $11.StructuredOutputValidationRequest);
      case 'Parse': return this.parse(ctx, request as $11.StructuredOutputParseRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => StructuredOutputServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => StructuredOutputServiceBase$messageJson;
}

