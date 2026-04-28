///
//  Generated code. Do not modify.
//  source: pipeline.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'pipeline.pbenum.dart';

export 'pipeline.pbenum.dart';

class PipelineSpec extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'PipelineSpec', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..pc<OperatorSpec>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'operators', $pb.PbFieldType.PM, subBuilder: OperatorSpec.create)
    ..pc<EdgeSpec>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'edges', $pb.PbFieldType.PM, subBuilder: EdgeSpec.create)
    ..aOM<PipelineOptions>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'options', subBuilder: PipelineOptions.create)
    ..hasRequiredFields = false
  ;

  PipelineSpec._() : super();
  factory PipelineSpec({
    $core.String? name,
    $core.Iterable<OperatorSpec>? operators,
    $core.Iterable<EdgeSpec>? edges,
    PipelineOptions? options,
  }) {
    final _result = create();
    if (name != null) {
      _result.name = name;
    }
    if (operators != null) {
      _result.operators.addAll(operators);
    }
    if (edges != null) {
      _result.edges.addAll(edges);
    }
    if (options != null) {
      _result.options = options;
    }
    return _result;
  }
  factory PipelineSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PipelineSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PipelineSpec clone() => PipelineSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PipelineSpec copyWith(void Function(PipelineSpec) updates) => super.copyWith((message) => updates(message as PipelineSpec)) as PipelineSpec; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static PipelineSpec create() => PipelineSpec._();
  PipelineSpec createEmptyInstance() => create();
  static $pb.PbList<PipelineSpec> createRepeated() => $pb.PbList<PipelineSpec>();
  @$core.pragma('dart2js:noInline')
  static PipelineSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PipelineSpec>(create);
  static PipelineSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<OperatorSpec> get operators => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<EdgeSpec> get edges => $_getList(2);

  @$pb.TagNumber(4)
  PipelineOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options(PipelineOptions v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => clearField(4);
  @$pb.TagNumber(4)
  PipelineOptions ensureOptions() => $_ensure(3);
}

class OperatorSpec extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'OperatorSpec', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type')
    ..m<$core.String, $core.String>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'params', entryClassName: 'OperatorSpec.ParamsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'pinnedEngine')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..e<DeviceAffinity>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'device', $pb.PbFieldType.OE, defaultOrMaker: DeviceAffinity.DEVICE_AFFINITY_UNSPECIFIED, valueOf: DeviceAffinity.valueOf, enumValues: DeviceAffinity.values)
    ..hasRequiredFields = false
  ;

  OperatorSpec._() : super();
  factory OperatorSpec({
    $core.String? name,
    $core.String? type,
    $core.Map<$core.String, $core.String>? params,
    $core.String? pinnedEngine,
    $core.String? modelId,
    DeviceAffinity? device,
  }) {
    final _result = create();
    if (name != null) {
      _result.name = name;
    }
    if (type != null) {
      _result.type = type;
    }
    if (params != null) {
      _result.params.addAll(params);
    }
    if (pinnedEngine != null) {
      _result.pinnedEngine = pinnedEngine;
    }
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (device != null) {
      _result.device = device;
    }
    return _result;
  }
  factory OperatorSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OperatorSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OperatorSpec clone() => OperatorSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OperatorSpec copyWith(void Function(OperatorSpec) updates) => super.copyWith((message) => updates(message as OperatorSpec)) as OperatorSpec; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static OperatorSpec create() => OperatorSpec._();
  OperatorSpec createEmptyInstance() => create();
  static $pb.PbList<OperatorSpec> createRepeated() => $pb.PbList<OperatorSpec>();
  @$core.pragma('dart2js:noInline')
  static OperatorSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OperatorSpec>(create);
  static OperatorSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => clearField(2);

  @$pb.TagNumber(3)
  $core.Map<$core.String, $core.String> get params => $_getMap(2);

  @$pb.TagNumber(4)
  $core.String get pinnedEngine => $_getSZ(3);
  @$pb.TagNumber(4)
  set pinnedEngine($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPinnedEngine() => $_has(3);
  @$pb.TagNumber(4)
  void clearPinnedEngine() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => clearField(5);

  @$pb.TagNumber(6)
  DeviceAffinity get device => $_getN(5);
  @$pb.TagNumber(6)
  set device(DeviceAffinity v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasDevice() => $_has(5);
  @$pb.TagNumber(6)
  void clearDevice() => clearField(6);
}

class EdgeSpec extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'EdgeSpec', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'from')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'to')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'capacity', $pb.PbFieldType.OU3)
    ..e<EdgePolicy>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'policy', $pb.PbFieldType.OE, defaultOrMaker: EdgePolicy.EDGE_POLICY_UNSPECIFIED, valueOf: EdgePolicy.valueOf, enumValues: EdgePolicy.values)
    ..hasRequiredFields = false
  ;

  EdgeSpec._() : super();
  factory EdgeSpec({
    $core.String? from,
    $core.String? to,
    $core.int? capacity,
    EdgePolicy? policy,
  }) {
    final _result = create();
    if (from != null) {
      _result.from = from;
    }
    if (to != null) {
      _result.to = to;
    }
    if (capacity != null) {
      _result.capacity = capacity;
    }
    if (policy != null) {
      _result.policy = policy;
    }
    return _result;
  }
  factory EdgeSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EdgeSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EdgeSpec clone() => EdgeSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EdgeSpec copyWith(void Function(EdgeSpec) updates) => super.copyWith((message) => updates(message as EdgeSpec)) as EdgeSpec; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EdgeSpec create() => EdgeSpec._();
  EdgeSpec createEmptyInstance() => create();
  static $pb.PbList<EdgeSpec> createRepeated() => $pb.PbList<EdgeSpec>();
  @$core.pragma('dart2js:noInline')
  static EdgeSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EdgeSpec>(create);
  static EdgeSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get from => $_getSZ(0);
  @$pb.TagNumber(1)
  set from($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrom() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get to => $_getSZ(1);
  @$pb.TagNumber(2)
  set to($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTo() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get capacity => $_getIZ(2);
  @$pb.TagNumber(3)
  set capacity($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCapacity() => $_has(2);
  @$pb.TagNumber(3)
  void clearCapacity() => clearField(3);

  @$pb.TagNumber(4)
  EdgePolicy get policy => $_getN(3);
  @$pb.TagNumber(4)
  set policy(EdgePolicy v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasPolicy() => $_has(3);
  @$pb.TagNumber(4)
  void clearPolicy() => clearField(4);
}

class PipelineOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'PipelineOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'latencyBudgetMs', $pb.PbFieldType.O3)
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'emitMetrics')
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'strictValidation')
    ..hasRequiredFields = false
  ;

  PipelineOptions._() : super();
  factory PipelineOptions({
    $core.int? latencyBudgetMs,
    $core.bool? emitMetrics,
    $core.bool? strictValidation,
  }) {
    final _result = create();
    if (latencyBudgetMs != null) {
      _result.latencyBudgetMs = latencyBudgetMs;
    }
    if (emitMetrics != null) {
      _result.emitMetrics = emitMetrics;
    }
    if (strictValidation != null) {
      _result.strictValidation = strictValidation;
    }
    return _result;
  }
  factory PipelineOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PipelineOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PipelineOptions clone() => PipelineOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PipelineOptions copyWith(void Function(PipelineOptions) updates) => super.copyWith((message) => updates(message as PipelineOptions)) as PipelineOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static PipelineOptions create() => PipelineOptions._();
  PipelineOptions createEmptyInstance() => create();
  static $pb.PbList<PipelineOptions> createRepeated() => $pb.PbList<PipelineOptions>();
  @$core.pragma('dart2js:noInline')
  static PipelineOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PipelineOptions>(create);
  static PipelineOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get latencyBudgetMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set latencyBudgetMs($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLatencyBudgetMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyBudgetMs() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get emitMetrics => $_getBF(1);
  @$pb.TagNumber(2)
  set emitMetrics($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEmitMetrics() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmitMetrics() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get strictValidation => $_getBF(2);
  @$pb.TagNumber(3)
  set strictValidation($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStrictValidation() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrictValidation() => clearField(3);
}

