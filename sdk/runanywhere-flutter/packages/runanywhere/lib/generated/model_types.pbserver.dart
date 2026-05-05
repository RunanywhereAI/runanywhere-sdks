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

import 'model_types.pb.dart' as $2;
import 'model_types.pbjson.dart';

export 'model_types.pb.dart';

abstract class ModelRegistryServiceBase extends $pb.GeneratedService {
  $async.Future<$2.ModelInfo> register($pb.ServerContext ctx, $2.ModelInfo request);
  $async.Future<$2.ModelInfo> update($pb.ServerContext ctx, $2.ModelInfo request);
  $async.Future<$2.ModelGetResult> get($pb.ServerContext ctx, $2.ModelGetRequest request);
  $async.Future<$2.ModelListResult> list($pb.ServerContext ctx, $2.ModelListRequest request);
  $async.Future<$2.ModelDeleteResult> remove($pb.ServerContext ctx, $2.ModelDeleteRequest request);
  $async.Future<$2.ModelImportResult> import($pb.ServerContext ctx, $2.ModelImportRequest request);
  $async.Future<$2.ModelDiscoveryResult> discover($pb.ServerContext ctx, $2.ModelDiscoveryRequest request);
  $async.Future<$2.ModelRegistryRefreshResult> refresh($pb.ServerContext ctx, $2.ModelRegistryRefreshRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Register': return $2.ModelInfo();
      case 'Update': return $2.ModelInfo();
      case 'Get': return $2.ModelGetRequest();
      case 'List': return $2.ModelListRequest();
      case 'Remove': return $2.ModelDeleteRequest();
      case 'Import': return $2.ModelImportRequest();
      case 'Discover': return $2.ModelDiscoveryRequest();
      case 'Refresh': return $2.ModelRegistryRefreshRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Register': return this.register(ctx, request as $2.ModelInfo);
      case 'Update': return this.update(ctx, request as $2.ModelInfo);
      case 'Get': return this.get(ctx, request as $2.ModelGetRequest);
      case 'List': return this.list(ctx, request as $2.ModelListRequest);
      case 'Remove': return this.remove(ctx, request as $2.ModelDeleteRequest);
      case 'Import': return this.import(ctx, request as $2.ModelImportRequest);
      case 'Discover': return this.discover(ctx, request as $2.ModelDiscoveryRequest);
      case 'Refresh': return this.refresh(ctx, request as $2.ModelRegistryRefreshRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => ModelRegistryServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => ModelRegistryServiceBase$messageJson;
}

