//
//  Generated code. Do not modify.
//  source: solutions.proto
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

import 'solutions.pb.dart' as $6;
import 'solutions.pbjson.dart';

export 'solutions.pb.dart';

abstract class SolutionsServiceBase extends $pb.GeneratedService {
  $async.Future<$6.SolutionHandle> create($pb.ServerContext ctx, $6.SolutionConfig request);
  $async.Future<$6.SolutionHandle> start($pb.ServerContext ctx, $6.SolutionHandle request);
  $async.Future<$6.SolutionHandle> stop($pb.ServerContext ctx, $6.SolutionHandle request);
  $async.Future<$6.SolutionHandle> destroy($pb.ServerContext ctx, $6.SolutionHandle request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Create': return $6.SolutionConfig();
      case 'Start': return $6.SolutionHandle();
      case 'Stop': return $6.SolutionHandle();
      case 'Destroy': return $6.SolutionHandle();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Create': return this.create(ctx, request as $6.SolutionConfig);
      case 'Start': return this.start(ctx, request as $6.SolutionHandle);
      case 'Stop': return this.stop(ctx, request as $6.SolutionHandle);
      case 'Destroy': return this.destroy(ctx, request as $6.SolutionHandle);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => SolutionsServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => SolutionsServiceBase$messageJson;
}

