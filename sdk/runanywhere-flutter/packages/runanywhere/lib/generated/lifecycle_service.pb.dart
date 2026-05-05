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

import 'model_types.pb.dart' as $0;
import 'sdk_events.pb.dart' as $1;

class LifecycleApi {
  $pb.RpcClient _client;
  LifecycleApi(this._client);

  $async.Future<$0.ModelLoadResult> load($pb.ClientContext? ctx, $0.ModelLoadRequest request) =>
    _client.invoke<$0.ModelLoadResult>(ctx, 'Lifecycle', 'Load', request, $0.ModelLoadResult())
  ;
  $async.Future<$0.ModelUnloadResult> unload($pb.ClientContext? ctx, $0.ModelUnloadRequest request) =>
    _client.invoke<$0.ModelUnloadResult>(ctx, 'Lifecycle', 'Unload', request, $0.ModelUnloadResult())
  ;
  $async.Future<$0.CurrentModelResult> current($pb.ClientContext? ctx, $0.CurrentModelRequest request) =>
    _client.invoke<$0.CurrentModelResult>(ctx, 'Lifecycle', 'Current', request, $0.CurrentModelResult())
  ;
  $async.Future<$1.ComponentLifecycleSnapshotResult> snapshot($pb.ClientContext? ctx, $1.ComponentLifecycleSnapshotRequest request) =>
    _client.invoke<$1.ComponentLifecycleSnapshotResult>(ctx, 'Lifecycle', 'Snapshot', request, $1.ComponentLifecycleSnapshotResult())
  ;
}

