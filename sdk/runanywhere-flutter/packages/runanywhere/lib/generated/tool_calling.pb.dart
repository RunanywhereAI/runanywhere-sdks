//
//  Generated code. Do not modify.
//  source: tool_calling.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

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
  nullValue, 
  notSet
}

/// ---------------------------------------------------------------------------
/// JSON-typed scalar / composite carrier for tool arguments and results.
/// Mirrors Swift's ToolValue enum, Kotlin's sealed class, and the
/// TypeScript discriminated union. Used inside ToolParameter.enum_values
/// (string-only) and as the canonical wire shape when consumers want
/// strongly-typed arguments rather than raw JSON.
/// ---------------------------------------------------------------------------
class ToolValue extends $pb.GeneratedMessage {
  factory ToolValue({
    $core.String? stringValue,
    $core.double? numberValue,
    $core.bool? boolValue,
    ToolValueArray? arrayValue,
    ToolValueObject? objectValue,
    $core.bool? nullValue,
  }) {
    final $result = create();
    if (stringValue != null) {
      $result.stringValue = stringValue;
    }
    if (numberValue != null) {
      $result.numberValue = numberValue;
    }
    if (boolValue != null) {
      $result.boolValue = boolValue;
    }
    if (arrayValue != null) {
      $result.arrayValue = arrayValue;
    }
    if (objectValue != null) {
      $result.objectValue = objectValue;
    }
    if (nullValue != null) {
      $result.nullValue = nullValue;
    }
    return $result;
  }
  ToolValue._() : super();
  factory ToolValue.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolValue.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, ToolValue_Kind> _ToolValue_KindByTag = {
    1 : ToolValue_Kind.stringValue,
    2 : ToolValue_Kind.numberValue,
    3 : ToolValue_Kind.boolValue,
    4 : ToolValue_Kind.arrayValue,
    5 : ToolValue_Kind.objectValue,
    6 : ToolValue_Kind.nullValue,
    0 : ToolValue_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolValue', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6])
    ..aOS(1, _omitFieldNames ? '' : 'stringValue')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'numberValue', $pb.PbFieldType.OD)
    ..aOB(3, _omitFieldNames ? '' : 'boolValue')
    ..aOM<ToolValueArray>(4, _omitFieldNames ? '' : 'arrayValue', subBuilder: ToolValueArray.create)
    ..aOM<ToolValueObject>(5, _omitFieldNames ? '' : 'objectValue', subBuilder: ToolValueObject.create)
    ..aOB(6, _omitFieldNames ? '' : 'nullValue')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolValue clone() => ToolValue()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolValue copyWith(void Function(ToolValue) updates) => super.copyWith((message) => updates(message as ToolValue)) as ToolValue;

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

  @$pb.TagNumber(6)
  $core.bool get nullValue => $_getBF(5);
  @$pb.TagNumber(6)
  set nullValue($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasNullValue() => $_has(5);
  @$pb.TagNumber(6)
  void clearNullValue() => clearField(6);
}

class ToolValueArray extends $pb.GeneratedMessage {
  factory ToolValueArray({
    $core.Iterable<ToolValue>? values,
  }) {
    final $result = create();
    if (values != null) {
      $result.values.addAll(values);
    }
    return $result;
  }
  ToolValueArray._() : super();
  factory ToolValueArray.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolValueArray.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolValueArray', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ToolValue>(1, _omitFieldNames ? '' : 'values', $pb.PbFieldType.PM, subBuilder: ToolValue.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolValueArray clone() => ToolValueArray()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolValueArray copyWith(void Function(ToolValueArray) updates) => super.copyWith((message) => updates(message as ToolValueArray)) as ToolValueArray;

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
  factory ToolValueObject({
    $core.Map<$core.String, ToolValue>? fields,
  }) {
    final $result = create();
    if (fields != null) {
      $result.fields.addAll(fields);
    }
    return $result;
  }
  ToolValueObject._() : super();
  factory ToolValueObject.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolValueObject.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolValueObject', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..m<$core.String, ToolValue>(1, _omitFieldNames ? '' : 'fields', entryClassName: 'ToolValueObject.FieldsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: ToolValue.create, valueDefaultOrMaker: ToolValue.getDefault, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolValueObject clone() => ToolValueObject()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolValueObject copyWith(void Function(ToolValueObject) updates) => super.copyWith((message) => updates(message as ToolValueObject)) as ToolValueObject;

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

/// ---------------------------------------------------------------------------
/// A single parameter definition for a tool.
/// ---------------------------------------------------------------------------
class ToolParameter extends $pb.GeneratedMessage {
  factory ToolParameter({
    $core.String? name,
    ToolParameterType? type,
    $core.String? description,
    $core.bool? required,
    $core.Iterable<$core.String>? enumValues,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (type != null) {
      $result.type = type;
    }
    if (description != null) {
      $result.description = description;
    }
    if (required != null) {
      $result.required = required;
    }
    if (enumValues != null) {
      $result.enumValues.addAll(enumValues);
    }
    return $result;
  }
  ToolParameter._() : super();
  factory ToolParameter.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolParameter.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolParameter', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..e<ToolParameterType>(2, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: ToolParameterType.TOOL_PARAMETER_TYPE_UNSPECIFIED, valueOf: ToolParameterType.valueOf, enumValues: ToolParameterType.values)
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOB(4, _omitFieldNames ? '' : 'required')
    ..pPS(5, _omitFieldNames ? '' : 'enumValues')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolParameter clone() => ToolParameter()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolParameter copyWith(void Function(ToolParameter) updates) => super.copyWith((message) => updates(message as ToolParameter)) as ToolParameter;

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

  /// Allowed values for enum-like parameters. Empty = unconstrained.
  @$pb.TagNumber(5)
  $core.List<$core.String> get enumValues => $_getList(4);
}

/// ---------------------------------------------------------------------------
/// Definition of a tool that the LLM can call.
/// ---------------------------------------------------------------------------
class ToolDefinition extends $pb.GeneratedMessage {
  factory ToolDefinition({
    $core.String? name,
    $core.String? description,
    $core.Iterable<ToolParameter>? parameters,
    $core.String? category,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (parameters != null) {
      $result.parameters.addAll(parameters);
    }
    if (category != null) {
      $result.category = category;
    }
    return $result;
  }
  ToolDefinition._() : super();
  factory ToolDefinition.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolDefinition.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolDefinition', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..pc<ToolParameter>(3, _omitFieldNames ? '' : 'parameters', $pb.PbFieldType.PM, subBuilder: ToolParameter.create)
    ..aOS(4, _omitFieldNames ? '' : 'category')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolDefinition clone() => ToolDefinition()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolDefinition copyWith(void Function(ToolDefinition) updates) => super.copyWith((message) => updates(message as ToolDefinition)) as ToolDefinition;

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

  /// Optional category for grouping tools in catalogs / UIs.
  @$pb.TagNumber(4)
  $core.String get category => $_getSZ(3);
  @$pb.TagNumber(4)
  set category($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCategory() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategory() => clearField(4);
}

/// ---------------------------------------------------------------------------
/// A tool call requested by the LLM. `arguments_json` is a JSON object
/// matching the parameter shape declared in the corresponding ToolDefinition.
/// ---------------------------------------------------------------------------
class ToolCall extends $pb.GeneratedMessage {
  factory ToolCall({
    $core.String? id,
    $core.String? name,
    $core.String? argumentsJson,
    $core.String? type,
    $core.Map<$core.String, ToolValue>? arguments,
    $core.String? callId,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (argumentsJson != null) {
      $result.argumentsJson = argumentsJson;
    }
    if (type != null) {
      $result.type = type;
    }
    if (arguments != null) {
      $result.arguments.addAll(arguments);
    }
    if (callId != null) {
      $result.callId = callId;
    }
    return $result;
  }
  ToolCall._() : super();
  factory ToolCall.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCall.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCall', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'argumentsJson')
    ..aOS(4, _omitFieldNames ? '' : 'type')
    ..m<$core.String, ToolValue>(5, _omitFieldNames ? '' : 'arguments', entryClassName: 'ToolCall.ArgumentsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: ToolValue.create, valueDefaultOrMaker: ToolValue.getDefault, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(6, _omitFieldNames ? '' : 'callId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCall clone() => ToolCall()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCall copyWith(void Function(ToolCall) updates) => super.copyWith((message) => updates(message as ToolCall)) as ToolCall;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCall create() => ToolCall._();
  ToolCall createEmptyInstance() => create();
  static $pb.PbList<ToolCall> createRepeated() => $pb.PbList<ToolCall>();
  @$core.pragma('dart2js:noInline')
  static ToolCall getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCall>(create);
  static ToolCall? _defaultInstance;

  /// Unique ID (caller-supplied or generated). Empty = unset.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Tool name (matches ToolDefinition.name).
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  /// JSON-encoded arguments. Empty object "{}" if no args.
  @$pb.TagNumber(3)
  $core.String get argumentsJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set argumentsJson($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasArgumentsJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearArgumentsJson() => clearField(3);

  /// Discriminator for OpenAI-compatible flows ("function" is the only
  /// value at the moment). Empty = unset.
  @$pb.TagNumber(4)
  $core.String get type => $_getSZ(3);
  @$pb.TagNumber(4)
  set type($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasType() => $_has(3);
  @$pb.TagNumber(4)
  void clearType() => clearField(4);

  /// Strongly-typed arguments map for SDKs that do not want to parse
  /// arguments_json. Producers should keep arguments_json populated for C++
  /// tokenizer compatibility.
  @$pb.TagNumber(5)
  $core.Map<$core.String, ToolValue> get arguments => $_getMap(4);

  /// Alias for id used by pre-proto SDK surfaces.
  @$pb.TagNumber(6)
  $core.String get callId => $_getSZ(5);
  @$pb.TagNumber(6)
  set callId($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCallId() => $_has(5);
  @$pb.TagNumber(6)
  void clearCallId() => clearField(6);
}

/// ---------------------------------------------------------------------------
/// Result of executing a tool. `result_json` is a JSON-encoded payload;
/// `error` is non-empty when the execution failed.
/// ---------------------------------------------------------------------------
class ToolResult extends $pb.GeneratedMessage {
  factory ToolResult({
    $core.String? toolCallId,
    $core.String? name,
    $core.String? resultJson,
    $core.String? error,
    $core.bool? success,
    $core.Map<$core.String, ToolValue>? result,
    $core.String? callId,
  }) {
    final $result = create();
    if (toolCallId != null) {
      $result.toolCallId = toolCallId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (resultJson != null) {
      $result.resultJson = resultJson;
    }
    if (error != null) {
      $result.error = error;
    }
    if (success != null) {
      $result.success = success;
    }
    if (result != null) {
      $result.result.addAll(result);
    }
    if (callId != null) {
      $result.callId = callId;
    }
    return $result;
  }
  ToolResult._() : super();
  factory ToolResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'toolCallId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'resultJson')
    ..aOS(4, _omitFieldNames ? '' : 'error')
    ..aOB(5, _omitFieldNames ? '' : 'success')
    ..m<$core.String, ToolValue>(6, _omitFieldNames ? '' : 'result', entryClassName: 'ToolResult.ResultEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: ToolValue.create, valueDefaultOrMaker: ToolValue.getDefault, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(7, _omitFieldNames ? '' : 'callId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolResult clone() => ToolResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolResult copyWith(void Function(ToolResult) updates) => super.copyWith((message) => updates(message as ToolResult)) as ToolResult;

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

  /// Whether execution succeeded. If unset/false and error is empty,
  /// consumers should fall back to legacy result_json/error semantics.
  @$pb.TagNumber(5)
  $core.bool get success => $_getBF(4);
  @$pb.TagNumber(5)
  set success($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSuccess() => $_has(4);
  @$pb.TagNumber(5)
  void clearSuccess() => clearField(5);

  /// Strongly-typed result map for SDKs that do not want to parse
  /// result_json. Producers should keep result_json populated for C++
  /// tokenizer compatibility.
  @$pb.TagNumber(6)
  $core.Map<$core.String, ToolValue> get result => $_getMap(5);

  /// Alias for tool_call_id used by pre-proto SDK surfaces.
  @$pb.TagNumber(7)
  $core.String get callId => $_getSZ(6);
  @$pb.TagNumber(7)
  set callId($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasCallId() => $_has(6);
  @$pb.TagNumber(7)
  void clearCallId() => clearField(7);
}

/// ---------------------------------------------------------------------------
/// Options for tool-enabled generation.
/// ---------------------------------------------------------------------------
class ToolCallingOptions extends $pb.GeneratedMessage {
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
    $core.int? maxToolCalls,
  }) {
    final $result = create();
    if (tools != null) {
      $result.tools.addAll(tools);
    }
    if (maxIterations != null) {
      $result.maxIterations = maxIterations;
    }
    if (autoExecute != null) {
      $result.autoExecute = autoExecute;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (replaceSystemPrompt != null) {
      $result.replaceSystemPrompt = replaceSystemPrompt;
    }
    if (keepToolsAvailable != null) {
      $result.keepToolsAvailable = keepToolsAvailable;
    }
    if (formatHint != null) {
      $result.formatHint = formatHint;
    }
    if (format != null) {
      $result.format = format;
    }
    if (customSystemPrompt != null) {
      $result.customSystemPrompt = customSystemPrompt;
    }
    if (maxToolCalls != null) {
      $result.maxToolCalls = maxToolCalls;
    }
    return $result;
  }
  ToolCallingOptions._() : super();
  factory ToolCallingOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ToolDefinition>(1, _omitFieldNames ? '' : 'tools', $pb.PbFieldType.PM, subBuilder: ToolDefinition.create)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'maxIterations', $pb.PbFieldType.O3)
    ..aOB(3, _omitFieldNames ? '' : 'autoExecute')
    ..a<$core.double>(4, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..aOS(6, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(7, _omitFieldNames ? '' : 'replaceSystemPrompt')
    ..aOB(8, _omitFieldNames ? '' : 'keepToolsAvailable')
    ..aOS(9, _omitFieldNames ? '' : 'formatHint')
    ..e<ToolCallFormatName>(10, _omitFieldNames ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_UNSPECIFIED, valueOf: ToolCallFormatName.valueOf, enumValues: ToolCallFormatName.values)
    ..aOS(11, _omitFieldNames ? '' : 'customSystemPrompt')
    ..a<$core.int>(12, _omitFieldNames ? '' : 'maxToolCalls', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingOptions clone() => ToolCallingOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingOptions copyWith(void Function(ToolCallingOptions) updates) => super.copyWith((message) => updates(message as ToolCallingOptions)) as ToolCallingOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingOptions create() => ToolCallingOptions._();
  ToolCallingOptions createEmptyInstance() => create();
  static $pb.PbList<ToolCallingOptions> createRepeated() => $pb.PbList<ToolCallingOptions>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingOptions>(create);
  static ToolCallingOptions? _defaultInstance;

  /// Available tools for this generation. If empty, the SDK falls back to
  /// its registered tools (per-SDK convention).
  @$pb.TagNumber(1)
  $core.List<ToolDefinition> get tools => $_getList(0);

  /// Maximum tool-call iterations in one conversation turn. 0 = SDK default
  /// (typically 5).
  @$pb.TagNumber(2)
  $core.int get maxIterations => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxIterations($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxIterations() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxIterations() => clearField(2);

  /// Whether to auto-execute tools or hand them back to the caller.
  @$pb.TagNumber(3)
  $core.bool get autoExecute => $_getBF(2);
  @$pb.TagNumber(3)
  set autoExecute($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAutoExecute() => $_has(2);
  @$pb.TagNumber(3)
  void clearAutoExecute() => clearField(3);

  /// Sampling temperature override (Swift: optional Float).
  @$pb.TagNumber(4)
  $core.double get temperature => $_getN(3);
  @$pb.TagNumber(4)
  set temperature($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTemperature() => $_has(3);
  @$pb.TagNumber(4)
  void clearTemperature() => clearField(4);

  /// Maximum tokens override.
  @$pb.TagNumber(5)
  $core.int get maxTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxTokens($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxTokens() => clearField(5);

  /// System prompt to use during tool-enabled generation.
  @$pb.TagNumber(6)
  $core.String get systemPrompt => $_getSZ(5);
  @$pb.TagNumber(6)
  set systemPrompt($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSystemPrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearSystemPrompt() => clearField(6);

  /// If true, replaces the system prompt entirely (no auto-injected
  /// tool instructions).
  @$pb.TagNumber(7)
  $core.bool get replaceSystemPrompt => $_getBF(6);
  @$pb.TagNumber(7)
  set replaceSystemPrompt($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasReplaceSystemPrompt() => $_has(6);
  @$pb.TagNumber(7)
  void clearReplaceSystemPrompt() => clearField(7);

  /// If true, keeps tool definitions available across multiple sequential
  /// tool calls in one generation.
  @$pb.TagNumber(8)
  $core.bool get keepToolsAvailable => $_getBF(7);
  @$pb.TagNumber(8)
  set keepToolsAvailable($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasKeepToolsAvailable() => $_has(7);
  @$pb.TagNumber(8)
  void clearKeepToolsAvailable() => clearField(8);

  /// Tool-call format hint: "default" (JSON-tagged), "lfm2", "openai", "auto".
  /// Empty = SDK default.
  @$pb.TagNumber(9)
  $core.String get formatHint => $_getSZ(8);
  @$pb.TagNumber(9)
  set formatHint($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasFormatHint() => $_has(8);
  @$pb.TagNumber(9)
  void clearFormatHint() => clearField(9);

  /// Strongly-typed tool-call format. Preferred over `format_hint` when set;
  /// `format_hint` remains for legacy callers and per-SDK custom strings
  /// that don't round-trip through this enum.
  @$pb.TagNumber(10)
  ToolCallFormatName get format => $_getN(9);
  @$pb.TagNumber(10)
  set format(ToolCallFormatName v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasFormat() => $_has(9);
  @$pb.TagNumber(10)
  void clearFormat() => clearField(10);

  /// Caller-supplied system prompt that fully replaces the SDK-injected
  /// tool-calling system prompt (rather than being merged with it).
  /// Distinct from `system_prompt` (field 6), which is merged unless
  /// `replace_system_prompt` is true.
  @$pb.TagNumber(11)
  $core.String get customSystemPrompt => $_getSZ(10);
  @$pb.TagNumber(11)
  set customSystemPrompt($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasCustomSystemPrompt() => $_has(10);
  @$pb.TagNumber(11)
  void clearCustomSystemPrompt() => clearField(11);

  /// C ABI / SDK field name for max_iterations. 0 = use max_iterations or
  /// SDK default.
  @$pb.TagNumber(12)
  $core.int get maxToolCalls => $_getIZ(11);
  @$pb.TagNumber(12)
  set maxToolCalls($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasMaxToolCalls() => $_has(11);
  @$pb.TagNumber(12)
  void clearMaxToolCalls() => clearField(12);
}

/// ---------------------------------------------------------------------------
/// Result of a tool-enabled generation.
/// ---------------------------------------------------------------------------
class ToolCallingResult extends $pb.GeneratedMessage {
  factory ToolCallingResult({
    $core.String? text,
    $core.Iterable<ToolCall>? toolCalls,
    $core.Iterable<ToolResult>? toolResults,
    $core.bool? isComplete,
    $core.String? conversationId,
    $core.int? iterationsUsed,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (toolCalls != null) {
      $result.toolCalls.addAll(toolCalls);
    }
    if (toolResults != null) {
      $result.toolResults.addAll(toolResults);
    }
    if (isComplete != null) {
      $result.isComplete = isComplete;
    }
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (iterationsUsed != null) {
      $result.iterationsUsed = iterationsUsed;
    }
    return $result;
  }
  ToolCallingResult._() : super();
  factory ToolCallingResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..pc<ToolCall>(2, _omitFieldNames ? '' : 'toolCalls', $pb.PbFieldType.PM, subBuilder: ToolCall.create)
    ..pc<ToolResult>(3, _omitFieldNames ? '' : 'toolResults', $pb.PbFieldType.PM, subBuilder: ToolResult.create)
    ..aOB(4, _omitFieldNames ? '' : 'isComplete')
    ..aOS(5, _omitFieldNames ? '' : 'conversationId')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'iterationsUsed', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingResult clone() => ToolCallingResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingResult copyWith(void Function(ToolCallingResult) updates) => super.copyWith((message) => updates(message as ToolCallingResult)) as ToolCallingResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingResult create() => ToolCallingResult._();
  ToolCallingResult createEmptyInstance() => create();
  static $pb.PbList<ToolCallingResult> createRepeated() => $pb.PbList<ToolCallingResult>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingResult>(create);
  static ToolCallingResult? _defaultInstance;

  /// Final text response from the assistant.
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  /// Tool calls the LLM made.
  @$pb.TagNumber(2)
  $core.List<ToolCall> get toolCalls => $_getList(1);

  /// Results of executed tools (only populated when auto_execute was true).
  @$pb.TagNumber(3)
  $core.List<ToolResult> get toolResults => $_getList(2);

  /// Whether the response is complete or waiting for more tool results.
  @$pb.TagNumber(4)
  $core.bool get isComplete => $_getBF(3);
  @$pb.TagNumber(4)
  set isComplete($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsComplete() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsComplete() => clearField(4);

  /// Conversation ID for continuing with tool results.
  @$pb.TagNumber(5)
  $core.String get conversationId => $_getSZ(4);
  @$pb.TagNumber(5)
  set conversationId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasConversationId() => $_has(4);
  @$pb.TagNumber(5)
  void clearConversationId() => clearField(5);

  /// Number of tool-call iterations actually used.
  @$pb.TagNumber(6)
  $core.int get iterationsUsed => $_getIZ(5);
  @$pb.TagNumber(6)
  set iterationsUsed($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIterationsUsed() => $_has(5);
  @$pb.TagNumber(6)
  void clearIterationsUsed() => clearField(6);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
