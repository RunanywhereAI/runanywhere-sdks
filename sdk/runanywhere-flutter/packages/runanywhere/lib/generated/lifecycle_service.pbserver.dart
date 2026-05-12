//
//  Generated code. Do not modify.
//  source: lifecycle_service.proto
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

import 'lifecycle_service.pbjson.dart';
import 'model_types.pb.dart' as $3;
import 'sdk_events.pb.dart' as $15;

export 'lifecycle_service.pb.dart';

abstract class LifecycleServiceBase extends $pb.GeneratedService {
  $async.Future<$3.ModelLoadResult> load($pb.ServerContext ctx, $3.ModelLoadRequest request);
  $async.Future<$3.ModelUnloadResult> unload($pb.ServerContext ctx, $3.ModelUnloadRequest request);
  $async.Future<$3.CurrentModelResult> current($pb.ServerContext ctx, $3.CurrentModelRequest request);
  $async.Future<$15.ComponentLifecycleSnapshotResult> snapshot($pb.ServerContext ctx, $15.ComponentLifecycleSnapshotRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Load': return $3.ModelLoadRequest();
      case 'Unload': return $3.ModelUnloadRequest();
      case 'Current': return $3.CurrentModelRequest();
      case 'Snapshot': return $15.ComponentLifecycleSnapshotRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Load': return this.load(ctx, request as $3.ModelLoadRequest);
      case 'Unload': return this.unload(ctx, request as $3.ModelUnloadRequest);
      case 'Current': return this.current(ctx, request as $3.CurrentModelRequest);
      case 'Snapshot': return this.snapshot(ctx, request as $15.ComponentLifecycleSnapshotRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => LifecycleServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => LifecycleServiceBase$messageJson;
}

