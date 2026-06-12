// This is a generated file - do not edit.
//
// Generated from router.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'model_types.pbenum.dart' as $1;
import 'sdk_events.pbenum.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// ---------------------------------------------------------------------------
/// Request: ask commons which frameworks can serve a given SDK component.
/// Maps to the engine-router plugin registry (not the model registry); this
/// answers "which engines CAN run this capability on this host" independent
/// of whether any matching model has been registered yet.
/// ---------------------------------------------------------------------------
class FrameworksForCapabilityRequest extends $pb.GeneratedMessage {
  factory FrameworksForCapabilityRequest({
    $0.SDKComponent? component,
  }) {
    final result = create();
    if (component != null) result.component = component;
    return result;
  }

  FrameworksForCapabilityRequest._();

  factory FrameworksForCapabilityRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FrameworksForCapabilityRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FrameworksForCapabilityRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<$0.SDKComponent>(1, _omitFieldNames ? '' : 'component',
        enumValues: $0.SDKComponent.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameworksForCapabilityRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameworksForCapabilityRequest copyWith(
          void Function(FrameworksForCapabilityRequest) updates) =>
      super.copyWith(
              (message) => updates(message as FrameworksForCapabilityRequest))
          as FrameworksForCapabilityRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityRequest create() =>
      FrameworksForCapabilityRequest._();
  @$core.override
  FrameworksForCapabilityRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FrameworksForCapabilityRequest>(create);
  static FrameworksForCapabilityRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.SDKComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component($0.SDKComponent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => $_clearField(1);
}

/// ---------------------------------------------------------------------------
/// Response: ordered list of inference frameworks. Ordering matches the
/// engine-router's priority-descending scan of registered plugins for the
/// primitive(s) mapped from `component`. Duplicates are removed while
/// preserving first-seen order.
/// ---------------------------------------------------------------------------
class FrameworksForCapabilityResponse extends $pb.GeneratedMessage {
  factory FrameworksForCapabilityResponse({
    $core.Iterable<$1.InferenceFramework>? frameworks,
  }) {
    final result = create();
    if (frameworks != null) result.frameworks.addAll(frameworks);
    return result;
  }

  FrameworksForCapabilityResponse._();

  factory FrameworksForCapabilityResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FrameworksForCapabilityResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FrameworksForCapabilityResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pc<$1.InferenceFramework>(
        1, _omitFieldNames ? '' : 'frameworks', $pb.PbFieldType.KE,
        valueOf: $1.InferenceFramework.valueOf,
        enumValues: $1.InferenceFramework.values,
        defaultEnumValue: $1.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameworksForCapabilityResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameworksForCapabilityResponse copyWith(
          void Function(FrameworksForCapabilityResponse) updates) =>
      super.copyWith(
              (message) => updates(message as FrameworksForCapabilityResponse))
          as FrameworksForCapabilityResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityResponse create() =>
      FrameworksForCapabilityResponse._();
  @$core.override
  FrameworksForCapabilityResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FrameworksForCapabilityResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FrameworksForCapabilityResponse>(
          create);
  static FrameworksForCapabilityResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$1.InferenceFramework> get frameworks => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
