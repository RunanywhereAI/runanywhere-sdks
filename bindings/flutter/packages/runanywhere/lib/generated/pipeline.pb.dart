// This is a generated file - do not edit.
//
// Generated from pipeline.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'pipeline.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'pipeline.pbenum.dart';

class PipelineSpec extends $pb.GeneratedMessage {
  factory PipelineSpec({
    $core.String? name,
    $core.Iterable<OperatorSpec>? operators,
    $core.Iterable<EdgeSpec>? edges,
    PipelineOptions? options,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (operators != null) result.operators.addAll(operators);
    if (edges != null) result.edges.addAll(edges);
    if (options != null) result.options = options;
    return result;
  }

  PipelineSpec._();

  factory PipelineSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..pPM<OperatorSpec>(2, _omitFieldNames ? '' : 'operators',
        subBuilder: OperatorSpec.create)
    ..pPM<EdgeSpec>(3, _omitFieldNames ? '' : 'edges',
        subBuilder: EdgeSpec.create)
    ..aOM<PipelineOptions>(4, _omitFieldNames ? '' : 'options',
        subBuilder: PipelineOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineSpec copyWith(void Function(PipelineSpec) updates) =>
      super.copyWith((message) => updates(message as PipelineSpec))
          as PipelineSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineSpec create() => PipelineSpec._();
  @$core.override
  PipelineSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineSpec getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineSpec>(create);
  static PipelineSpec? _defaultInstance;

  /// e.g. "voice_agent_basic".
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<OperatorSpec> get operators => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<EdgeSpec> get edges => $_getList(2);

  @$pb.TagNumber(4)
  PipelineOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options(PipelineOptions value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => $_clearField(4);
  @$pb.TagNumber(4)
  PipelineOptions ensureOptions() => $_ensure(3);
}

class OperatorSpec extends $pb.GeneratedMessage {
  factory OperatorSpec({
    $core.String? name,
    $core.String? type,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? params,
    $core.String? pinnedEngine,
    $core.String? modelId,
    DeviceAffinity? device,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (params != null) result.params.addEntries(params);
    if (pinnedEngine != null) result.pinnedEngine = pinnedEngine;
    if (modelId != null) result.modelId = modelId;
    if (device != null) result.device = device;
    return result;
  }

  OperatorSpec._();

  factory OperatorSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OperatorSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OperatorSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'type')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'params',
        entryClassName: 'OperatorSpec.ParamsEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(4, _omitFieldNames ? '' : 'pinnedEngine')
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..aE<DeviceAffinity>(6, _omitFieldNames ? '' : 'device',
        enumValues: DeviceAffinity.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OperatorSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OperatorSpec copyWith(void Function(OperatorSpec) updates) =>
      super.copyWith((message) => updates(message as OperatorSpec))
          as OperatorSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OperatorSpec create() => OperatorSpec._();
  @$core.override
  OperatorSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OperatorSpec getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OperatorSpec>(create);
  static OperatorSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get params => $_getMap(2);

  /// Bypasses priority-based engine selection.
  @$pb.TagNumber(4)
  $core.String get pinnedEngine => $_getSZ(3);
  @$pb.TagNumber(4)
  set pinnedEngine($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPinnedEngine() => $_has(3);
  @$pb.TagNumber(4)
  void clearPinnedEngine() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => $_clearField(5);

  @$pb.TagNumber(6)
  DeviceAffinity get device => $_getN(5);
  @$pb.TagNumber(6)
  set device(DeviceAffinity value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasDevice() => $_has(5);
  @$pb.TagNumber(6)
  void clearDevice() => $_clearField(6);
}

class EdgeSpec extends $pb.GeneratedMessage {
  factory EdgeSpec({
    $core.String? from,
    $core.String? to,
    $core.int? capacity,
    EdgePolicy? policy,
  }) {
    final result = create();
    if (from != null) result.from = from;
    if (to != null) result.to = to;
    if (capacity != null) result.capacity = capacity;
    if (policy != null) result.policy = policy;
    return result;
  }

  EdgeSpec._();

  factory EdgeSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EdgeSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EdgeSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'from')
    ..aOS(2, _omitFieldNames ? '' : 'to')
    ..aI(3, _omitFieldNames ? '' : 'capacity', fieldType: $pb.PbFieldType.OU3)
    ..aE<EdgePolicy>(4, _omitFieldNames ? '' : 'policy',
        enumValues: EdgePolicy.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EdgeSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EdgeSpec copyWith(void Function(EdgeSpec) updates) =>
      super.copyWith((message) => updates(message as EdgeSpec)) as EdgeSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EdgeSpec create() => EdgeSpec._();
  @$core.override
  EdgeSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EdgeSpec getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EdgeSpec>(create);
  static EdgeSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get from => $_getSZ(0);
  @$pb.TagNumber(1)
  set from($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrom() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get to => $_getSZ(1);
  @$pb.TagNumber(2)
  set to($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTo() => $_clearField(2);

  /// Queue depth, and what happens when it fills.
  @$pb.TagNumber(3)
  $core.int get capacity => $_getIZ(2);
  @$pb.TagNumber(3)
  set capacity($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCapacity() => $_has(2);
  @$pb.TagNumber(3)
  void clearCapacity() => $_clearField(3);

  @$pb.TagNumber(4)
  EdgePolicy get policy => $_getN(3);
  @$pb.TagNumber(4)
  set policy(EdgePolicy value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPolicy() => $_has(3);
  @$pb.TagNumber(4)
  void clearPolicy() => $_clearField(4);
}

class PipelineOptions extends $pb.GeneratedMessage {
  factory PipelineOptions({
    $core.int? latencyBudgetMs,
    $core.bool? emitMetrics,
    $core.bool? strictValidation,
  }) {
    final result = create();
    if (latencyBudgetMs != null) result.latencyBudgetMs = latencyBudgetMs;
    if (emitMetrics != null) result.emitMetrics = emitMetrics;
    if (strictValidation != null) result.strictValidation = strictValidation;
    return result;
  }

  PipelineOptions._();

  factory PipelineOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'latencyBudgetMs')
    ..aOB(2, _omitFieldNames ? '' : 'emitMetrics')
    ..aOB(3, _omitFieldNames ? '' : 'strictValidation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineOptions copyWith(void Function(PipelineOptions) updates) =>
      super.copyWith((message) => updates(message as PipelineOptions))
          as PipelineOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineOptions create() => PipelineOptions._();
  @$core.override
  PipelineOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineOptions>(create);
  static PipelineOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get latencyBudgetMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set latencyBudgetMs($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatencyBudgetMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyBudgetMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get emitMetrics => $_getBF(1);
  @$pb.TagNumber(2)
  set emitMetrics($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmitMetrics() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmitMetrics() => $_clearField(2);

  /// Reject a spec with unknown operators instead of skipping them.
  @$pb.TagNumber(3)
  $core.bool get strictValidation => $_getBF(2);
  @$pb.TagNumber(3)
  set strictValidation($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStrictValidation() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrictValidation() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
