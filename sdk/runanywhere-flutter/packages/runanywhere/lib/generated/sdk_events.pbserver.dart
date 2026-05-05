//
//  Generated code. Do not modify.
//  source: sdk_events.proto
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

import 'sdk_events.pb.dart' as $13;
import 'sdk_events.pbjson.dart';

export 'sdk_events.pb.dart';

abstract class SDKEventsServiceBase extends $pb.GeneratedService {
  $async.Future<$13.SDKEventPublishResult> publish($pb.ServerContext ctx, $13.SDKEventPublishRequest request);
  $async.Future<$13.SDKEvent> subscribe($pb.ServerContext ctx, $13.SDKEventSubscribeRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Publish': return $13.SDKEventPublishRequest();
      case 'Subscribe': return $13.SDKEventSubscribeRequest();
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx, $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Publish': return this.publish(ctx, request as $13.SDKEventPublishRequest);
      case 'Subscribe': return this.subscribe(ctx, request as $13.SDKEventSubscribeRequest);
      default: throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => SDKEventsServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> get $messageJson => SDKEventsServiceBase$messageJson;
}

