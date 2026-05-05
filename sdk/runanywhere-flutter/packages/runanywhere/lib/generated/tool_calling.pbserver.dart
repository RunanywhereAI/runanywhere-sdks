//
//  Generated code. Do not modify.
//  source: tool_calling.proto
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

import 'tool_calling.pb.dart' as $0;
import 'tool_calling.pbjson.dart';

export 'tool_calling.pb.dart';

abstract class ToolCallingServiceBase extends $pb.GeneratedService {
  $async.Future<$0.ToolParseResult> parse($pb.ServerContext ctx, $0.ToolParseRequest request);
  $async.Future<$0.ToolPromptFormatResult> formatPrompt($pb.ServerContext ctx, $0.ToolPromptFormatRequest request);
  $async.Future<$0.ToolCallValidationResult> validateCall($pb.ServerContext ctx, $0.ToolCallValidationRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Parse': return $0.ToolParseRequest();
      case 'FormatPrompt': return $0.ToolPromptFormatRequest();
      case 'ValidateCall': return $0.ToolCallValidationRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Parse': return this.parse(ctx, request as $0.ToolParseRequest);
      case 'FormatPrompt': return this.formatPrompt(ctx, request as $0.ToolPromptFormatRequest);
      case 'ValidateCall': return this.validateCall(ctx, request as $0.ToolCallValidationRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => ToolCallingServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => ToolCallingServiceBase$messageJson;
}

