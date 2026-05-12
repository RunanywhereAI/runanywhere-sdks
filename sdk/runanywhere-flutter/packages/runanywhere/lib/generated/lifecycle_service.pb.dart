//
//  Generated code. Do not modify.
//  source: lifecycle_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pb.dart' as $3;
import 'sdk_events.pb.dart' as $15;

class LifecycleApi {
  $pb.RpcClient _client;
  LifecycleApi(this._client);

  $async.Future<$3.ModelLoadResult> load($pb.ClientContext? ctx, $3.ModelLoadRequest request) =>
    _client.invoke<$3.ModelLoadResult>(ctx, 'Lifecycle', 'Load', request, $3.ModelLoadResult())
  ;
  $async.Future<$3.ModelUnloadResult> unload($pb.ClientContext? ctx, $3.ModelUnloadRequest request) =>
    _client.invoke<$3.ModelUnloadResult>(ctx, 'Lifecycle', 'Unload', request, $3.ModelUnloadResult())
  ;
  $async.Future<$3.CurrentModelResult> current($pb.ClientContext? ctx, $3.CurrentModelRequest request) =>
    _client.invoke<$3.CurrentModelResult>(ctx, 'Lifecycle', 'Current', request, $3.CurrentModelResult())
  ;
  $async.Future<$15.ComponentLifecycleSnapshotResult> snapshot($pb.ClientContext? ctx, $15.ComponentLifecycleSnapshotRequest request) =>
    _client.invoke<$15.ComponentLifecycleSnapshotResult>(ctx, 'Lifecycle', 'Snapshot', request, $15.ComponentLifecycleSnapshotResult())
  ;
}

