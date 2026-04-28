///
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:async' as $async;

import 'package:protobuf/protobuf.dart' as $pb;

import 'dart:core' as $core;
import 'llm_service.pb.dart' as $2;
import 'llm_service.pbjson.dart';

export 'llm_service.pb.dart';

abstract class LLMServiceBase extends $pb.GeneratedService {
  $async.Future<$2.LLMStreamEvent> generate($pb.ServerContext ctx, $2.LLMGenerateRequest request);

  $pb.GeneratedMessage createRequest($core.String method) {
    switch (method) {
      case 'Generate': return $2.LLMGenerateRequest();
      default: throw $core.ArgumentError('Unknown method: $method');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String method, $pb.GeneratedMessage request) {
    switch (method) {
      case 'Generate': return this.generate(ctx, request as $2.LLMGenerateRequest);
      default: throw $core.ArgumentError('Unknown method: $method');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => LLMServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => LLMServiceBase$messageJson;
}

