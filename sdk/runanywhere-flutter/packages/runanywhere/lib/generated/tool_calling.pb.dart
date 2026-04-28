///
//  Generated code. Do not modify.
//  source: tool_calling.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'tool_calling.pbenum.dart';

export 'tool_calling.pbenum.dart';

enum ToolValue_Kind {
  stringValue, 
  numberValue, 
  boolValue, 
  arrayValue, 
  objectValue, 
  notSet
}

class ToolValue extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, ToolValue_Kind> _ToolValue_KindByTag = {
    1 : ToolValue_Kind.stringValue,
    2 : ToolValue_Kind.numberValue,
    3 : ToolValue_Kind.boolValue,
    4 : ToolValue_Kind.arrayValue,
    5 : ToolValue_Kind.objectValue,
    0 : ToolValue_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolValue', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'stringValue')
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'numberValue', $pb.PbFieldType.OD)
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'boolValue')
    ..aOM<ToolValueArray>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'arrayValue', subBuilder: ToolValueArray.create)
    ..aOM<ToolValueObject>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'objectValue', subBuilder: ToolValueObject.create)
    ..hasRequiredFields = false
  ;

  ToolValue._() : super();
  factory ToolValue({
    $core.String? stringValue,
    $core.double? numberValue,
    $core.bool? boolValue,
    ToolValueArray? arrayValue,
    ToolValueObject? objectValue,
  }) {
    final _result = create();
    if (stringValue != null) {
      _result.stringValue = stringValue;
    }
    if (numberValue != null) {
      _result.numberValue = numberValue;
    }
    if (boolValue != null) {
      _result.boolValue = boolValue;
    }
    if (arrayValue != null) {
      _result.arrayValue = arrayValue;
    }
    if (objectValue != null) {
      _result.objectValue = objectValue;
    }
    return _result;
  }
  factory ToolValue.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolValue.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolValue clone() => ToolValue()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolValue copyWith(void Function(ToolValue) updates) => super.copyWith((message) => updates(message as ToolValue)) as ToolValue; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolValue create() => ToolValue._();
  ToolValue createEmptyInstance() => create();
  static $pb.PbList<ToolValue> createRepeated() => $pb.PbList<ToolValue>();
  @$core.pragma('dart2js:noInline')
  static ToolValue getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolValue>(create);
  static ToolValue? _defaultInstance;

  ToolValue_Kind whichKind() => _ToolValue_KindByTag[$_whichOneof(0)]!;
  void clearKind() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get stringValue => $_getSZ(0);
  @$pb.TagNumber(1)
  set stringValue($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStringValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearStringValue() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get numberValue => $_getN(1);
  @$pb.TagNumber(2)
  set numberValue($core.double v) { $_setDouble(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNumberValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearNumberValue() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get boolValue => $_getBF(2);
  @$pb.TagNumber(3)
  set boolValue($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBoolValue() => $_has(2);
  @$pb.TagNumber(3)
  void clearBoolValue() => clearField(3);

  @$pb.TagNumber(4)
  ToolValueArray get arrayValue => $_getN(3);
  @$pb.TagNumber(4)
  set arrayValue(ToolValueArray v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasArrayValue() => $_has(3);
  @$pb.TagNumber(4)
  void clearArrayValue() => clearField(4);
  @$pb.TagNumber(4)
  ToolValueArray ensureArrayValue() => $_ensure(3);

  @$pb.TagNumber(5)
  ToolValueObject get objectValue => $_getN(4);
  @$pb.TagNumber(5)
  set objectValue(ToolValueObject v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasObjectValue() => $_has(4);
  @$pb.TagNumber(5)
  void clearObjectValue() => clearField(5);
  @$pb.TagNumber(5)
  ToolValueObject ensureObjectValue() => $_ensure(4);
}

class ToolValueArray extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolValueArray', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ToolValue>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'values', $pb.PbFieldType.PM, subBuilder: ToolValue.create)
    ..hasRequiredFields = false
  ;

  ToolValueArray._() : super();
  factory ToolValueArray({
    $core.Iterable<ToolValue>? values,
  }) {
    final _result = create();
    if (values != null) {
      _result.values.addAll(values);
    }
    return _result;
  }
  factory ToolValueArray.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolValueArray.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolValueArray clone() => ToolValueArray()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolValueArray copyWith(void Function(ToolValueArray) updates) => super.copyWith((message) => updates(message as ToolValueArray)) as ToolValueArray; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolValueArray create() => ToolValueArray._();
  ToolValueArray createEmptyInstance() => create();
  static $pb.PbList<ToolValueArray> createRepeated() => $pb.PbList<ToolValueArray>();
  @$core.pragma('dart2js:noInline')
  static ToolValueArray getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolValueArray>(create);
  static ToolValueArray? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ToolValue> get values => $_getList(0);
}

class ToolValueObject extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolValueObject', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..m<$core.String, ToolValue>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'fields', entryClassName: 'ToolValueObject.FieldsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: ToolValue.create, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  ToolValueObject._() : super();
  factory ToolValueObject({
    $core.Map<$core.String, ToolValue>? fields,
  }) {
    final _result = create();
    if (fields != null) {
      _result.fields.addAll(fields);
    }
    return _result;
  }
  factory ToolValueObject.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolValueObject.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolValueObject clone() => ToolValueObject()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolValueObject copyWith(void Function(ToolValueObject) updates) => super.copyWith((message) => updates(message as ToolValueObject)) as ToolValueObject; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolValueObject create() => ToolValueObject._();
  ToolValueObject createEmptyInstance() => create();
  static $pb.PbList<ToolValueObject> createRepeated() => $pb.PbList<ToolValueObject>();
  @$core.pragma('dart2js:noInline')
  static ToolValueObject getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolValueObject>(create);
  static ToolValueObject? _defaultInstance;

  @$pb.TagNumber(1)
  $core.Map<$core.String, ToolValue> get fields => $_getMap(0);
}

class ToolParameter extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolParameter', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..e<ToolParameterType>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: ToolParameterType.TOOL_PARAMETER_TYPE_UNSPECIFIED, valueOf: ToolParameterType.valueOf, enumValues: ToolParameterType.values)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'description')
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'required')
    ..pPS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enumValues')
    ..hasRequiredFields = false
  ;

  ToolParameter._() : super();
  factory ToolParameter({
    $core.String? name,
    ToolParameterType? type,
    $core.String? description,
    $core.bool? required,
    $core.Iterable<$core.String>? enumValues,
  }) {
    final _result = create();
    if (name != null) {
      _result.name = name;
    }
    if (type != null) {
      _result.type = type;
    }
    if (description != null) {
      _result.description = description;
    }
    if (required != null) {
      _result.required = required;
    }
    if (enumValues != null) {
      _result.enumValues.addAll(enumValues);
    }
    return _result;
  }
  factory ToolParameter.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolParameter.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolParameter clone() => ToolParameter()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolParameter copyWith(void Function(ToolParameter) updates) => super.copyWith((message) => updates(message as ToolParameter)) as ToolParameter; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolParameter create() => ToolParameter._();
  ToolParameter createEmptyInstance() => create();
  static $pb.PbList<ToolParameter> createRepeated() => $pb.PbList<ToolParameter>();
  @$core.pragma('dart2js:noInline')
  static ToolParameter getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolParameter>(create);
  static ToolParameter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  ToolParameterType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(ToolParameterType v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get required => $_getBF(3);
  @$pb.TagNumber(4)
  set required($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRequired() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequired() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.String> get enumValues => $_getList(4);
}

class ToolDefinition extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolDefinition', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'description')
    ..pc<ToolParameter>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'parameters', $pb.PbFieldType.PM, subBuilder: ToolParameter.create)
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'category')
    ..hasRequiredFields = false
  ;

  ToolDefinition._() : super();
  factory ToolDefinition({
    $core.String? name,
    $core.String? description,
    $core.Iterable<ToolParameter>? parameters,
    $core.String? category,
  }) {
    final _result = create();
    if (name != null) {
      _result.name = name;
    }
    if (description != null) {
      _result.description = description;
    }
    if (parameters != null) {
      _result.parameters.addAll(parameters);
    }
    if (category != null) {
      _result.category = category;
    }
    return _result;
  }
  factory ToolDefinition.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolDefinition.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolDefinition clone() => ToolDefinition()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolDefinition copyWith(void Function(ToolDefinition) updates) => super.copyWith((message) => updates(message as ToolDefinition)) as ToolDefinition; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolDefinition create() => ToolDefinition._();
  ToolDefinition createEmptyInstance() => create();
  static $pb.PbList<ToolDefinition> createRepeated() => $pb.PbList<ToolDefinition>();
  @$core.pragma('dart2js:noInline')
  static ToolDefinition getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolDefinition>(create);
  static ToolDefinition? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<ToolParameter> get parameters => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get category => $_getSZ(3);
  @$pb.TagNumber(4)
  set category($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCategory() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategory() => clearField(4);
}

class ToolCall extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolCall', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'id')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'argumentsJson')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type')
    ..hasRequiredFields = false
  ;

  ToolCall._() : super();
  factory ToolCall({
    $core.String? id,
    $core.String? name,
    $core.String? argumentsJson,
    $core.String? type,
  }) {
    final _result = create();
    if (id != null) {
      _result.id = id;
    }
    if (name != null) {
      _result.name = name;
    }
    if (argumentsJson != null) {
      _result.argumentsJson = argumentsJson;
    }
    if (type != null) {
      _result.type = type;
    }
    return _result;
  }
  factory ToolCall.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCall.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCall clone() => ToolCall()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCall copyWith(void Function(ToolCall) updates) => super.copyWith((message) => updates(message as ToolCall)) as ToolCall; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolCall create() => ToolCall._();
  ToolCall createEmptyInstance() => create();
  static $pb.PbList<ToolCall> createRepeated() => $pb.PbList<ToolCall>();
  @$core.pragma('dart2js:noInline')
  static ToolCall getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCall>(create);
  static ToolCall? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get argumentsJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set argumentsJson($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasArgumentsJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearArgumentsJson() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get type => $_getSZ(3);
  @$pb.TagNumber(4)
  set type($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasType() => $_has(3);
  @$pb.TagNumber(4)
  void clearType() => clearField(4);
}

class ToolResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'toolCallId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'resultJson')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error')
    ..hasRequiredFields = false
  ;

  ToolResult._() : super();
  factory ToolResult({
    $core.String? toolCallId,
    $core.String? name,
    $core.String? resultJson,
    $core.String? error,
  }) {
    final _result = create();
    if (toolCallId != null) {
      _result.toolCallId = toolCallId;
    }
    if (name != null) {
      _result.name = name;
    }
    if (resultJson != null) {
      _result.resultJson = resultJson;
    }
    if (error != null) {
      _result.error = error;
    }
    return _result;
  }
  factory ToolResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolResult clone() => ToolResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolResult copyWith(void Function(ToolResult) updates) => super.copyWith((message) => updates(message as ToolResult)) as ToolResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolResult create() => ToolResult._();
  ToolResult createEmptyInstance() => create();
  static $pb.PbList<ToolResult> createRepeated() => $pb.PbList<ToolResult>();
  @$core.pragma('dart2js:noInline')
  static ToolResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolResult>(create);
  static ToolResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get toolCallId => $_getSZ(0);
  @$pb.TagNumber(1)
  set toolCallId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasToolCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearToolCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get resultJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set resultJson($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasResultJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearResultJson() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get error => $_getSZ(3);
  @$pb.TagNumber(4)
  set error($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => clearField(4);
}

class ToolCallingOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolCallingOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ToolDefinition>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tools', $pb.PbFieldType.PM, subBuilder: ToolDefinition.create)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxIterations', $pb.PbFieldType.O3)
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'autoExecute')
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'systemPrompt')
    ..aOB(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'replaceSystemPrompt')
    ..aOB(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'keepToolsAvailable')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'formatHint')
    ..e<ToolCallFormatName>(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_UNSPECIFIED, valueOf: ToolCallFormatName.valueOf, enumValues: ToolCallFormatName.values)
    ..aOS(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'customSystemPrompt')
    ..hasRequiredFields = false
  ;

  ToolCallingOptions._() : super();
  factory ToolCallingOptions({
    $core.Iterable<ToolDefinition>? tools,
    $core.int? maxIterations,
    $core.bool? autoExecute,
    $core.double? temperature,
    $core.int? maxTokens,
    $core.String? systemPrompt,
    $core.bool? replaceSystemPrompt,
    $core.bool? keepToolsAvailable,
    $core.String? formatHint,
    ToolCallFormatName? format,
    $core.String? customSystemPrompt,
  }) {
    final _result = create();
    if (tools != null) {
      _result.tools.addAll(tools);
    }
    if (maxIterations != null) {
      _result.maxIterations = maxIterations;
    }
    if (autoExecute != null) {
      _result.autoExecute = autoExecute;
    }
    if (temperature != null) {
      _result.temperature = temperature;
    }
    if (maxTokens != null) {
      _result.maxTokens = maxTokens;
    }
    if (systemPrompt != null) {
      _result.systemPrompt = systemPrompt;
    }
    if (replaceSystemPrompt != null) {
      _result.replaceSystemPrompt = replaceSystemPrompt;
    }
    if (keepToolsAvailable != null) {
      _result.keepToolsAvailable = keepToolsAvailable;
    }
    if (formatHint != null) {
      _result.formatHint = formatHint;
    }
    if (format != null) {
      _result.format = format;
    }
    if (customSystemPrompt != null) {
      _result.customSystemPrompt = customSystemPrompt;
    }
    return _result;
  }
  factory ToolCallingOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingOptions clone() => ToolCallingOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingOptions copyWith(void Function(ToolCallingOptions) updates) => super.copyWith((message) => updates(message as ToolCallingOptions)) as ToolCallingOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolCallingOptions create() => ToolCallingOptions._();
  ToolCallingOptions createEmptyInstance() => create();
  static $pb.PbList<ToolCallingOptions> createRepeated() => $pb.PbList<ToolCallingOptions>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingOptions>(create);
  static ToolCallingOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ToolDefinition> get tools => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get maxIterations => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxIterations($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxIterations() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxIterations() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get autoExecute => $_getBF(2);
  @$pb.TagNumber(3)
  set autoExecute($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAutoExecute() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoExecute() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get temperature => $_getN(3);
  @$pb.TagNumber(4)
  set temperature($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTemperature() => $_has(3);
  @$pb.TagNumber(4)
  void clearTemperature() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxTokens($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxTokens() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get systemPrompt => $_getSZ(5);
  @$pb.TagNumber(6)
  set systemPrompt($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSystemPrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearSystemPrompt() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get replaceSystemPrompt => $_getBF(6);
  @$pb.TagNumber(7)
  set replaceSystemPrompt($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasReplaceSystemPrompt() => $_has(6);
  @$pb.TagNumber(7)
  void clearReplaceSystemPrompt() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get keepToolsAvailable => $_getBF(7);
  @$pb.TagNumber(8)
  set keepToolsAvailable($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasKeepToolsAvailable() => $_has(7);
  @$pb.TagNumber(8)
  void clearKeepToolsAvailable() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get formatHint => $_getSZ(8);
  @$pb.TagNumber(9)
  set formatHint($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasFormatHint() => $_has(8);
  @$pb.TagNumber(9)
  void clearFormatHint() => clearField(9);

  @$pb.TagNumber(10)
  ToolCallFormatName get format => $_getN(9);
  @$pb.TagNumber(10)
  set format(ToolCallFormatName v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasFormat() => $_has(9);
  @$pb.TagNumber(10)
  void clearFormat() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get customSystemPrompt => $_getSZ(10);
  @$pb.TagNumber(11)
  set customSystemPrompt($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasCustomSystemPrompt() => $_has(10);
  @$pb.TagNumber(11)
  void clearCustomSystemPrompt() => clearField(11);
}

class ToolCallingResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ToolCallingResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..pc<ToolCall>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'toolCalls', $pb.PbFieldType.PM, subBuilder: ToolCall.create)
    ..pc<ToolResult>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'toolResults', $pb.PbFieldType.PM, subBuilder: ToolResult.create)
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isComplete')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'conversationId')
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'iterationsUsed', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  ToolCallingResult._() : super();
  factory ToolCallingResult({
    $core.String? text,
    $core.Iterable<ToolCall>? toolCalls,
    $core.Iterable<ToolResult>? toolResults,
    $core.bool? isComplete,
    $core.String? conversationId,
    $core.int? iterationsUsed,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (toolCalls != null) {
      _result.toolCalls.addAll(toolCalls);
    }
    if (toolResults != null) {
      _result.toolResults.addAll(toolResults);
    }
    if (isComplete != null) {
      _result.isComplete = isComplete;
    }
    if (conversationId != null) {
      _result.conversationId = conversationId;
    }
    if (iterationsUsed != null) {
      _result.iterationsUsed = iterationsUsed;
    }
    return _result;
  }
  factory ToolCallingResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingResult clone() => ToolCallingResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingResult copyWith(void Function(ToolCallingResult) updates) => super.copyWith((message) => updates(message as ToolCallingResult)) as ToolCallingResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ToolCallingResult create() => ToolCallingResult._();
  ToolCallingResult createEmptyInstance() => create();
  static $pb.PbList<ToolCallingResult> createRepeated() => $pb.PbList<ToolCallingResult>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingResult>(create);
  static ToolCallingResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ToolCall> get toolCalls => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<ToolResult> get toolResults => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get isComplete => $_getBF(3);
  @$pb.TagNumber(4)
  set isComplete($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsComplete() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsComplete() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get conversationId => $_getSZ(4);
  @$pb.TagNumber(5)
  set conversationId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasConversationId() => $_has(4);
  @$pb.TagNumber(5)
  void clearConversationId() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get iterationsUsed => $_getIZ(5);
  @$pb.TagNumber(6)
  set iterationsUsed($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIterationsUsed() => $_has(5);
  @$pb.TagNumber(6)
  void clearIterationsUsed() => clearField(6);
}

