//
//  Generated code. Do not modify.
//  source: storage_types.proto
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

import 'storage_types.pb.dart' as $10;
import 'storage_types.pbjson.dart';

export 'storage_types.pb.dart';

abstract class StorageServiceBase extends $pb.GeneratedService {
  $async.Future<$10.StorageInfoResult> info($pb.ServerContext ctx, $10.StorageInfoRequest request);
  $async.Future<$10.StorageAvailabilityResult> availability($pb.ServerContext ctx, $10.StorageAvailabilityRequest request);
  $async.Future<$10.StorageDeletePlan> deletePlan($pb.ServerContext ctx, $10.StorageDeletePlanRequest request);
  $async.Future<$10.StorageDeleteResult> delete($pb.ServerContext ctx, $10.StorageDeleteRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Info': return $10.StorageInfoRequest();
      case 'Availability': return $10.StorageAvailabilityRequest();
      case 'DeletePlan': return $10.StorageDeletePlanRequest();
      case 'Delete': return $10.StorageDeleteRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Info': return this.info(ctx, request as $10.StorageInfoRequest);
      case 'Availability': return this.availability(ctx, request as $10.StorageAvailabilityRequest);
      case 'DeletePlan': return this.deletePlan(ctx, request as $10.StorageDeletePlanRequest);
      case 'Delete': return this.delete(ctx, request as $10.StorageDeleteRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => StorageServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => StorageServiceBase$messageJson;
}

