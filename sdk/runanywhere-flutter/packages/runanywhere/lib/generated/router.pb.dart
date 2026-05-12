//
//  Generated code. Do not modify.
//  source: router.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart' as $3;
import 'sdk_events.pbenum.dart' as $15;

/// ---------------------------------------------------------------------------
/// Request: ask commons which frameworks can serve a given SDK component.
/// Maps to the engine-router plugin registry (not the model registry); this
/// answers "which engines CAN run this capability on this host" independent
/// of whether any matching model has been registered yet.
/// ---------------------------------------------------------------------------
class FrameworksForCapabilityRequest extends $pb.GeneratedMessage {
  factory FrameworksForCapabilityRequest({
    $15.SDKComponent? component,
  }) {
    final $result = create();
    if (component != null) {
      $result.component = component;
    }
    return $result;
  }
  FrameworksForCapabilityRequest._() : super();
  factory FrameworksForCapabilityRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FrameworksForCapabilityRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FrameworksForCapabilityRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<$15.SDKComponent>(1, _omitFieldNames ? '' : 'component', $pb.PbFieldType.OE, defaultOrMaker: $15.SDKComponent.SDK_COMPONENT_UNSPECIFIED, valueOf: $15.SDKComponent.valueOf, enumValues: $15.SDKComponent.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FrameworksForCapabilityRequest clone() => FrameworksForCapabilityRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FrameworksForCapabilityRequest copyWith(void Function(FrameworksForCapabilityRequest) updates) => super.copyWith((message) => updates(message as FrameworksForCapabilityRequest)) as FrameworksForCapabilityRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityRequest create() => FrameworksForCapabilityRequest._();
  FrameworksForCapabilityRequest createEmptyInstance() => create();
  static $pb.PbList<FrameworksForCapabilityRequest> createRepeated() => $pb.PbList<FrameworksForCapabilityRequest>();
  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FrameworksForCapabilityRequest>(create);
  static FrameworksForCapabilityRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $15.SDKComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component($15.SDKComponent v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => clearField(1);
}

/// ---------------------------------------------------------------------------
/// Response: ordered list of inference frameworks. Ordering matches the
/// engine-router's priority-descending scan of registered plugins for the
/// primitive(s) mapped from `component`. Duplicates are removed while
/// preserving first-seen order.
/// ---------------------------------------------------------------------------
class FrameworksForCapabilityResponse extends $pb.GeneratedMessage {
  factory FrameworksForCapabilityResponse({
    $core.Iterable<$3.InferenceFramework>? frameworks,
  }) {
    final $result = create();
    if (frameworks != null) {
      $result.frameworks.addAll(frameworks);
    }
    return $result;
  }
  FrameworksForCapabilityResponse._() : super();
  factory FrameworksForCapabilityResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FrameworksForCapabilityResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FrameworksForCapabilityResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<$3.InferenceFramework>(1, _omitFieldNames ? '' : 'frameworks', $pb.PbFieldType.KE, valueOf: $3.InferenceFramework.valueOf, enumValues: $3.InferenceFramework.values, defaultEnumValue: $3.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FrameworksForCapabilityResponse clone() => FrameworksForCapabilityResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FrameworksForCapabilityResponse copyWith(void Function(FrameworksForCapabilityResponse) updates) => super.copyWith((message) => updates(message as FrameworksForCapabilityResponse)) as FrameworksForCapabilityResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityResponse create() => FrameworksForCapabilityResponse._();
  FrameworksForCapabilityResponse createEmptyInstance() => create();
  static $pb.PbList<FrameworksForCapabilityResponse> createRepeated() => $pb.PbList<FrameworksForCapabilityResponse>();
  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FrameworksForCapabilityResponse>(create);
  static FrameworksForCapabilityResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$3.InferenceFramework> get frameworks => $_getList(0);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
