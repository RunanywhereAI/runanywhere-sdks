// This is a generated file - do not edit.
//
// Generated from lifecycle_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pb.dart' as $0;
import 'sdk_events.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Logical model-lifecycle service contract. Mirrors the C ABI entry points
/// rac_model_lifecycle_load_proto, rac_model_lifecycle_unload_proto,
/// rac_model_lifecycle_current_model_proto, and
/// rac_component_lifecycle_snapshot_proto. Platform adapters remain
/// responsible for native filesystem permissions, sandbox/bookmark/SAF
/// handles, and OS-level process lifecycle; this service carries only the
/// portable load/unload/current/snapshot contracts owned by C++.
class LifecycleApi {
  final $pb.RpcClient _client;

  LifecycleApi(this._client);

  /// Load a registered model. Mirrors rac_model_lifecycle_load_proto.
  $async.Future<$0.ModelLoadResult> load(
          $pb.ClientContext? ctx, $0.ModelLoadRequest request) =>
      _client.invoke<$0.ModelLoadResult>(
          ctx, 'Lifecycle', 'Load', request, $0.ModelLoadResult());

  /// Unload one or all models. Mirrors rac_model_lifecycle_unload_proto.
  $async.Future<$0.ModelUnloadResult> unload(
          $pb.ClientContext? ctx, $0.ModelUnloadRequest request) =>
      _client.invoke<$0.ModelUnloadResult>(
          ctx, 'Lifecycle', 'Unload', request, $0.ModelUnloadResult());

  /// Query the currently loaded model for a component/framework. Mirrors
  /// rac_model_lifecycle_current_model_proto.
  $async.Future<$0.CurrentModelResult> current(
          $pb.ClientContext? ctx, $0.CurrentModelRequest request) =>
      _client.invoke<$0.CurrentModelResult>(
          ctx, 'Lifecycle', 'Current', request, $0.CurrentModelResult());

  /// Snapshot the lifecycle state of one or more SDKComponent values.
  /// Mirrors rac_component_lifecycle_snapshot_proto.
  $async.Future<$1.ComponentLifecycleSnapshotResult> snapshot(
          $pb.ClientContext? ctx,
          $1.ComponentLifecycleSnapshotRequest request) =>
      _client.invoke<$1.ComponentLifecycleSnapshotResult>(ctx, 'Lifecycle',
          'Snapshot', request, $1.ComponentLifecycleSnapshotResult());
}
