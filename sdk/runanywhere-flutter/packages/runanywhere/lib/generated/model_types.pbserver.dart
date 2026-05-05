//
//  Generated code. Do not modify.
//  source: model_types.proto
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

import 'model_types.pb.dart' as $0;
import 'model_types.pbjson.dart';

export 'model_types.pb.dart';

abstract class ModelRegistryServiceBase extends $pb.GeneratedService {
  $async.Future<$0.ModelInfo> register($pb.ServerContext ctx, $0.ModelInfo request);
  $async.Future<$0.ModelInfo> update($pb.ServerContext ctx, $0.ModelInfo request);
  $async.Future<$0.ModelGetResult> get($pb.ServerContext ctx, $0.ModelGetRequest request);
  $async.Future<$0.ModelListResult> list($pb.ServerContext ctx, $0.ModelListRequest request);
  $async.Future<$0.ModelDeleteResult> remove($pb.ServerContext ctx, $0.ModelDeleteRequest request);
  $async.Future<$0.ModelImportResult> import($pb.ServerContext ctx, $0.ModelImportRequest request);
  $async.Future<$0.ModelDiscoveryResult> discover($pb.ServerContext ctx, $0.ModelDiscoveryRequest request);
  $async.Future<$0.ModelRegistryRefreshResult> refresh($pb.ServerContext ctx, $0.ModelRegistryRefreshRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Register': return $0.ModelInfo();
      case 'Update': return $0.ModelInfo();
      case 'Get': return $0.ModelGetRequest();
      case 'List': return $0.ModelListRequest();
      case 'Remove': return $0.ModelDeleteRequest();
      case 'Import': return $0.ModelImportRequest();
      case 'Discover': return $0.ModelDiscoveryRequest();
      case 'Refresh': return $0.ModelRegistryRefreshRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Register': return this.register(ctx, request as $0.ModelInfo);
      case 'Update': return this.update(ctx, request as $0.ModelInfo);
      case 'Get': return this.get(ctx, request as $0.ModelGetRequest);
      case 'List': return this.list(ctx, request as $0.ModelListRequest);
      case 'Remove': return this.remove(ctx, request as $0.ModelDeleteRequest);
      case 'Import': return this.import(ctx, request as $0.ModelImportRequest);
      case 'Discover': return this.discover(ctx, request as $0.ModelDiscoveryRequest);
      case 'Refresh': return this.refresh(ctx, request as $0.ModelRegistryRefreshRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => ModelRegistryServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => ModelRegistryServiceBase$messageJson;
}

