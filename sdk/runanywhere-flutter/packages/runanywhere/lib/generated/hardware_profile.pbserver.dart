//
//  Generated code. Do not modify.
//  source: hardware_profile.proto
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

import 'hardware_profile.pb.dart' as $0;
import 'hardware_profile.pbjson.dart';

export 'hardware_profile.pb.dart';

abstract class HardwareServiceBase extends $pb.GeneratedService {
  $async.Future<$0.HardwareProfileResult> getProfile($pb.ServerContext ctx, $0.HardwareProfileRequest request);
  $async.Future<$0.HardwareProfileResult> getAccelerators($pb.ServerContext ctx, $0.HardwareAcceleratorsRequest request);
  $async.Future<$0.HardwareAcceleratorPreferenceResult> setAcceleratorPreference($pb.ServerContext ctx, $0.HardwareAcceleratorPreferenceRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'GetProfile': return $0.HardwareProfileRequest();
      case 'GetAccelerators': return $0.HardwareAcceleratorsRequest();
      case 'SetAcceleratorPreference': return $0.HardwareAcceleratorPreferenceRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'GetProfile': return this.getProfile(ctx, request as $0.HardwareProfileRequest);
      case 'GetAccelerators': return this.getAccelerators(ctx, request as $0.HardwareAcceleratorsRequest);
      case 'SetAcceleratorPreference': return this.setAcceleratorPreference(ctx, request as $0.HardwareAcceleratorPreferenceRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => HardwareServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => HardwareServiceBase$messageJson;
}

