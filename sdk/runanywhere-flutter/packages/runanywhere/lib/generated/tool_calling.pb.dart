//
//  Generated code. Do not modify.
//  source: tool_calling.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
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
    $core.String? jsonSchema,
    ToolValue? defaultValue,
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
    if (jsonSchema != null) {
      $result.jsonSchema = jsonSchema;
    }
    if (defaultValue != null) {
      $result.defaultValue = defaultValue;
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
    ..aOS(6, _omitFieldNames ? '' : 'jsonSchema')
    ..aOM<ToolValue>(7, _omitFieldNames ? '' : 'defaultValue', subBuilder: ToolValue.create)
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

  @$pb.TagNumber(6)
  $core.String get jsonSchema => $_getSZ(5);
  @$pb.TagNumber(6)
  set jsonSchema($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasJsonSchema() => $_has(5);
  @$pb.TagNumber(6)
  void clearJsonSchema() => clearField(6);

  @$pb.TagNumber(7)
  ToolValue get defaultValue => $_getN(6);
  @$pb.TagNumber(7)
  set defaultValue(ToolValue v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasDefaultValue() => $_has(6);
  @$pb.TagNumber(7)
  void clearDefaultValue() => clearField(7);
  @$pb.TagNumber(7)
  ToolValue ensureDefaultValue() => $_ensure(6);
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
    $core.String? jsonSchema,
    $core.Map<$core.String, $core.String>? metadata,
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
    if (jsonSchema != null) {
      $result.jsonSchema = jsonSchema;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
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
    ..aOS(5, _omitFieldNames ? '' : 'jsonSchema')
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'metadata', entryClassName: 'ToolDefinition.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
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

  @$pb.TagNumber(5)
  $core.String get jsonSchema => $_getSZ(4);
  @$pb.TagNumber(5)
  set jsonSchema($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasJsonSchema() => $_has(4);
  @$pb.TagNumber(5)
  void clearJsonSchema() => clearField(5);

  @$pb.TagNumber(6)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(5);
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
    $fixnum.Int64? createdAtMs,
    $core.String? rawText,
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
    if (createdAtMs != null) {
      $result.createdAtMs = createdAtMs;
    }
    if (rawText != null) {
      $result.rawText = rawText;
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
    ..aInt64(7, _omitFieldNames ? '' : 'createdAtMs')
    ..aOS(8, _omitFieldNames ? '' : 'rawText')
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

  @$pb.TagNumber(7)
  $fixnum.Int64 get createdAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set createdAtMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasCreatedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearCreatedAtMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get rawText => $_getSZ(7);
  @$pb.TagNumber(8)
  set rawText($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasRawText() => $_has(7);
  @$pb.TagNumber(8)
  void clearRawText() => clearField(8);
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
    $fixnum.Int64? startedAtMs,
    $fixnum.Int64? completedAtMs,
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
    if (startedAtMs != null) {
      $result.startedAtMs = startedAtMs;
    }
    if (completedAtMs != null) {
      $result.completedAtMs = completedAtMs;
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
    ..aInt64(8, _omitFieldNames ? '' : 'startedAtMs')
    ..aInt64(9, _omitFieldNames ? '' : 'completedAtMs')
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

  @$pb.TagNumber(8)
  $fixnum.Int64 get startedAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set startedAtMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasStartedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearStartedAtMs() => clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get completedAtMs => $_getI64(8);
  @$pb.TagNumber(9)
  set completedAtMs($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasCompletedAtMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearCompletedAtMs() => clearField(9);
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
    ToolChoiceMode? toolChoice,
    $core.String? forcedToolName,
    $core.bool? parallelToolCalls,
    $core.bool? requireJsonArguments,
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
    if (toolChoice != null) {
      $result.toolChoice = toolChoice;
    }
    if (forcedToolName != null) {
      $result.forcedToolName = forcedToolName;
    }
    if (parallelToolCalls != null) {
      $result.parallelToolCalls = parallelToolCalls;
    }
    if (requireJsonArguments != null) {
      $result.requireJsonArguments = requireJsonArguments;
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
    ..e<ToolChoiceMode>(13, _omitFieldNames ? '' : 'toolChoice', $pb.PbFieldType.OE, defaultOrMaker: ToolChoiceMode.TOOL_CHOICE_MODE_UNSPECIFIED, valueOf: ToolChoiceMode.valueOf, enumValues: ToolChoiceMode.values)
    ..aOS(14, _omitFieldNames ? '' : 'forcedToolName')
    ..aOB(15, _omitFieldNames ? '' : 'parallelToolCalls')
    ..aOB(16, _omitFieldNames ? '' : 'requireJsonArguments')
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

  @$pb.TagNumber(13)
  ToolChoiceMode get toolChoice => $_getN(12);
  @$pb.TagNumber(13)
  set toolChoice(ToolChoiceMode v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasToolChoice() => $_has(12);
  @$pb.TagNumber(13)
  void clearToolChoice() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get forcedToolName => $_getSZ(13);
  @$pb.TagNumber(14)
  set forcedToolName($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasForcedToolName() => $_has(13);
  @$pb.TagNumber(14)
  void clearForcedToolName() => clearField(14);

  @$pb.TagNumber(15)
  $core.bool get parallelToolCalls => $_getBF(14);
  @$pb.TagNumber(15)
  set parallelToolCalls($core.bool v) { $_setBool(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasParallelToolCalls() => $_has(14);
  @$pb.TagNumber(15)
  void clearParallelToolCalls() => clearField(15);

  @$pb.TagNumber(16)
  $core.bool get requireJsonArguments => $_getBF(15);
  @$pb.TagNumber(16)
  set requireJsonArguments($core.bool v) { $_setBool(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasRequireJsonArguments() => $_has(15);
  @$pb.TagNumber(16)
  void clearRequireJsonArguments() => clearField(16);
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
    $core.String? errorMessage,
    $core.int? errorCode,
    $core.String? rawText,
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
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    if (rawText != null) {
      $result.rawText = rawText;
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
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(8, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..aOS(9, _omitFieldNames ? '' : 'rawText')
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

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get errorCode => $_getIZ(7);
  @$pb.TagNumber(8)
  set errorCode($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasErrorCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorCode() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get rawText => $_getSZ(8);
  @$pb.TagNumber(9)
  set rawText($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasRawText() => $_has(8);
  @$pb.TagNumber(9)
  void clearRawText() => clearField(9);
}

class ToolParseRequest extends $pb.GeneratedMessage {
  factory ToolParseRequest({
    $core.String? text,
    ToolCallingOptions? options,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (options != null) {
      $result.options = options;
    }
    return $result;
  }
  ToolParseRequest._() : super();
  factory ToolParseRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolParseRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolParseRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOM<ToolCallingOptions>(2, _omitFieldNames ? '' : 'options', subBuilder: ToolCallingOptions.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolParseRequest clone() => ToolParseRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolParseRequest copyWith(void Function(ToolParseRequest) updates) => super.copyWith((message) => updates(message as ToolParseRequest)) as ToolParseRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolParseRequest create() => ToolParseRequest._();
  ToolParseRequest createEmptyInstance() => create();
  static $pb.PbList<ToolParseRequest> createRepeated() => $pb.PbList<ToolParseRequest>();
  @$core.pragma('dart2js:noInline')
  static ToolParseRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolParseRequest>(create);
  static ToolParseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  ToolCallingOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(ToolCallingOptions v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => clearField(2);
  @$pb.TagNumber(2)
  ToolCallingOptions ensureOptions() => $_ensure(1);
}

class ToolParseResult extends $pb.GeneratedMessage {
  factory ToolParseResult({
    $core.bool? hasToolCall,
    $core.Iterable<ToolCall>? toolCalls,
    $core.String? remainingText,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (hasToolCall != null) {
      $result.hasToolCall = hasToolCall;
    }
    if (toolCalls != null) {
      $result.toolCalls.addAll(toolCalls);
    }
    if (remainingText != null) {
      $result.remainingText = remainingText;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  ToolParseResult._() : super();
  factory ToolParseResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolParseResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolParseResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'hasToolCall')
    ..pc<ToolCall>(2, _omitFieldNames ? '' : 'toolCalls', $pb.PbFieldType.PM, subBuilder: ToolCall.create)
    ..aOS(3, _omitFieldNames ? '' : 'remainingText')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolParseResult clone() => ToolParseResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolParseResult copyWith(void Function(ToolParseResult) updates) => super.copyWith((message) => updates(message as ToolParseResult)) as ToolParseResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolParseResult create() => ToolParseResult._();
  ToolParseResult createEmptyInstance() => create();
  static $pb.PbList<ToolParseResult> createRepeated() => $pb.PbList<ToolParseResult>();
  @$core.pragma('dart2js:noInline')
  static ToolParseResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolParseResult>(create);
  static ToolParseResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get hasToolCall => $_getBF(0);
  @$pb.TagNumber(1)
  set hasToolCall($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasHasToolCall() => $_has(0);
  @$pb.TagNumber(1)
  void clearHasToolCall() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ToolCall> get toolCalls => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get remainingText => $_getSZ(2);
  @$pb.TagNumber(3)
  set remainingText($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRemainingText() => $_has(2);
  @$pb.TagNumber(3)
  void clearRemainingText() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => clearField(5);
}

class ToolPromptFormatRequest extends $pb.GeneratedMessage {
  factory ToolPromptFormatRequest({
    $core.String? userPrompt,
    ToolCallingOptions? options,
    $core.Iterable<ToolResult>? toolResults,
    $core.String? assistantText,
  }) {
    final $result = create();
    if (userPrompt != null) {
      $result.userPrompt = userPrompt;
    }
    if (options != null) {
      $result.options = options;
    }
    if (toolResults != null) {
      $result.toolResults.addAll(toolResults);
    }
    if (assistantText != null) {
      $result.assistantText = assistantText;
    }
    return $result;
  }
  ToolPromptFormatRequest._() : super();
  factory ToolPromptFormatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolPromptFormatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolPromptFormatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userPrompt')
    ..aOM<ToolCallingOptions>(2, _omitFieldNames ? '' : 'options', subBuilder: ToolCallingOptions.create)
    ..pc<ToolResult>(3, _omitFieldNames ? '' : 'toolResults', $pb.PbFieldType.PM, subBuilder: ToolResult.create)
    ..aOS(4, _omitFieldNames ? '' : 'assistantText')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolPromptFormatRequest clone() => ToolPromptFormatRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolPromptFormatRequest copyWith(void Function(ToolPromptFormatRequest) updates) => super.copyWith((message) => updates(message as ToolPromptFormatRequest)) as ToolPromptFormatRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatRequest create() => ToolPromptFormatRequest._();
  ToolPromptFormatRequest createEmptyInstance() => create();
  static $pb.PbList<ToolPromptFormatRequest> createRepeated() => $pb.PbList<ToolPromptFormatRequest>();
  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolPromptFormatRequest>(create);
  static ToolPromptFormatRequest? _defaultInstance;

  /// User prompt to merge with tool instructions. Empty means return only
  /// the tool-instruction block for the selected format.
  @$pb.TagNumber(1)
  $core.String get userPrompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set userPrompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserPrompt() => clearField(1);

  /// Carries available tools plus format/choice/iteration constraints.
  @$pb.TagNumber(2)
  ToolCallingOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(ToolCallingOptions v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => clearField(2);
  @$pb.TagNumber(2)
  ToolCallingOptions ensureOptions() => $_ensure(1);

  /// Tool results to include when formatting a follow-up prompt after host
  /// execution. Empty means an initial tool-enabled prompt.
  @$pb.TagNumber(3)
  $core.List<ToolResult> get toolResults => $_getList(2);

  /// Assistant text emitted before tool execution, when available.
  @$pb.TagNumber(4)
  $core.String get assistantText => $_getSZ(3);
  @$pb.TagNumber(4)
  set assistantText($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAssistantText() => $_has(3);
  @$pb.TagNumber(4)
  void clearAssistantText() => clearField(4);
}

class ToolPromptFormatResult extends $pb.GeneratedMessage {
  factory ToolPromptFormatResult({
    $core.String? formattedPrompt,
    ToolCallFormatName? format,
    $core.String? formatHint,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (formattedPrompt != null) {
      $result.formattedPrompt = formattedPrompt;
    }
    if (format != null) {
      $result.format = format;
    }
    if (formatHint != null) {
      $result.formatHint = formatHint;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  ToolPromptFormatResult._() : super();
  factory ToolPromptFormatResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolPromptFormatResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolPromptFormatResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'formattedPrompt')
    ..e<ToolCallFormatName>(2, _omitFieldNames ? '' : 'format', $pb.PbFieldType.OE, defaultOrMaker: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_UNSPECIFIED, valueOf: ToolCallFormatName.valueOf, enumValues: ToolCallFormatName.values)
    ..aOS(3, _omitFieldNames ? '' : 'formatHint')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolPromptFormatResult clone() => ToolPromptFormatResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolPromptFormatResult copyWith(void Function(ToolPromptFormatResult) updates) => super.copyWith((message) => updates(message as ToolPromptFormatResult)) as ToolPromptFormatResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatResult create() => ToolPromptFormatResult._();
  ToolPromptFormatResult createEmptyInstance() => create();
  static $pb.PbList<ToolPromptFormatResult> createRepeated() => $pb.PbList<ToolPromptFormatResult>();
  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolPromptFormatResult>(create);
  static ToolPromptFormatResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get formattedPrompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set formattedPrompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFormattedPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormattedPrompt() => clearField(1);

  @$pb.TagNumber(2)
  ToolCallFormatName get format => $_getN(1);
  @$pb.TagNumber(2)
  set format(ToolCallFormatName v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearFormat() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get formatHint => $_getSZ(2);
  @$pb.TagNumber(3)
  set formatHint($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFormatHint() => $_has(2);
  @$pb.TagNumber(3)
  void clearFormatHint() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => clearField(5);
}

class ToolCallValidationRequest extends $pb.GeneratedMessage {
  factory ToolCallValidationRequest({
    ToolCall? toolCall,
    ToolCallingOptions? options,
  }) {
    final $result = create();
    if (toolCall != null) {
      $result.toolCall = toolCall;
    }
    if (options != null) {
      $result.options = options;
    }
    return $result;
  }
  ToolCallValidationRequest._() : super();
  factory ToolCallValidationRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallValidationRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallValidationRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<ToolCall>(1, _omitFieldNames ? '' : 'toolCall', subBuilder: ToolCall.create)
    ..aOM<ToolCallingOptions>(2, _omitFieldNames ? '' : 'options', subBuilder: ToolCallingOptions.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallValidationRequest clone() => ToolCallValidationRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallValidationRequest copyWith(void Function(ToolCallValidationRequest) updates) => super.copyWith((message) => updates(message as ToolCallValidationRequest)) as ToolCallValidationRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallValidationRequest create() => ToolCallValidationRequest._();
  ToolCallValidationRequest createEmptyInstance() => create();
  static $pb.PbList<ToolCallValidationRequest> createRepeated() => $pb.PbList<ToolCallValidationRequest>();
  @$core.pragma('dart2js:noInline')
  static ToolCallValidationRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallValidationRequest>(create);
  static ToolCallValidationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ToolCall get toolCall => $_getN(0);
  @$pb.TagNumber(1)
  set toolCall(ToolCall v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasToolCall() => $_has(0);
  @$pb.TagNumber(1)
  void clearToolCall() => clearField(1);
  @$pb.TagNumber(1)
  ToolCall ensureToolCall() => $_ensure(0);

  /// Validation uses options.tools as the registry snapshot and honors
  /// portable flags such as require_json_arguments and forced_tool_name.
  @$pb.TagNumber(2)
  ToolCallingOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(ToolCallingOptions v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => clearField(2);
  @$pb.TagNumber(2)
  ToolCallingOptions ensureOptions() => $_ensure(1);
}

class ToolCallValidationResult extends $pb.GeneratedMessage {
  factory ToolCallValidationResult({
    $core.bool? isValid,
    $core.Iterable<$core.String>? validationErrors,
    ToolDefinition? matchedTool,
    $core.String? normalizedArgumentsJson,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (isValid != null) {
      $result.isValid = isValid;
    }
    if (validationErrors != null) {
      $result.validationErrors.addAll(validationErrors);
    }
    if (matchedTool != null) {
      $result.matchedTool = matchedTool;
    }
    if (normalizedArgumentsJson != null) {
      $result.normalizedArgumentsJson = normalizedArgumentsJson;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  ToolCallValidationResult._() : super();
  factory ToolCallValidationResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallValidationResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallValidationResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isValid')
    ..pPS(2, _omitFieldNames ? '' : 'validationErrors')
    ..aOM<ToolDefinition>(3, _omitFieldNames ? '' : 'matchedTool', subBuilder: ToolDefinition.create)
    ..aOS(4, _omitFieldNames ? '' : 'normalizedArgumentsJson')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallValidationResult clone() => ToolCallValidationResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallValidationResult copyWith(void Function(ToolCallValidationResult) updates) => super.copyWith((message) => updates(message as ToolCallValidationResult)) as ToolCallValidationResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallValidationResult create() => ToolCallValidationResult._();
  ToolCallValidationResult createEmptyInstance() => create();
  static $pb.PbList<ToolCallValidationResult> createRepeated() => $pb.PbList<ToolCallValidationResult>();
  @$core.pragma('dart2js:noInline')
  static ToolCallValidationResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallValidationResult>(create);
  static ToolCallValidationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isValid => $_getBF(0);
  @$pb.TagNumber(1)
  set isValid($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsValid() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsValid() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get validationErrors => $_getList(1);

  @$pb.TagNumber(3)
  ToolDefinition get matchedTool => $_getN(2);
  @$pb.TagNumber(3)
  set matchedTool(ToolDefinition v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasMatchedTool() => $_has(2);
  @$pb.TagNumber(3)
  void clearMatchedTool() => clearField(3);
  @$pb.TagNumber(3)
  ToolDefinition ensureMatchedTool() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get normalizedArgumentsJson => $_getSZ(3);
  @$pb.TagNumber(4)
  set normalizedArgumentsJson($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasNormalizedArgumentsJson() => $_has(3);
  @$pb.TagNumber(4)
  void clearNormalizedArgumentsJson() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get errorCode => $_getIZ(5);
  @$pb.TagNumber(6)
  set errorCode($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorCode() => clearField(6);
}

class ToolCallingStreamEvent extends $pb.GeneratedMessage {
  factory ToolCallingStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? conversationId,
    ToolCallingStreamEventKind? kind,
    $core.String? token,
    ToolCall? toolCall,
    ToolResult? toolResult,
    ToolCallingResult? result,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (token != null) {
      $result.token = token;
    }
    if (toolCall != null) {
      $result.toolCall = toolCall;
    }
    if (toolResult != null) {
      $result.toolResult = toolResult;
    }
    if (result != null) {
      $result.result = result;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  ToolCallingStreamEvent._() : super();
  factory ToolCallingStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingStreamEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'conversationId')
    ..e<ToolCallingStreamEventKind>(4, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: ToolCallingStreamEventKind.TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED, valueOf: ToolCallingStreamEventKind.valueOf, enumValues: ToolCallingStreamEventKind.values)
    ..aOS(5, _omitFieldNames ? '' : 'token')
    ..aOM<ToolCall>(6, _omitFieldNames ? '' : 'toolCall', subBuilder: ToolCall.create)
    ..aOM<ToolResult>(7, _omitFieldNames ? '' : 'toolResult', subBuilder: ToolResult.create)
    ..aOM<ToolCallingResult>(8, _omitFieldNames ? '' : 'result', subBuilder: ToolCallingResult.create)
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(10, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingStreamEvent clone() => ToolCallingStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingStreamEvent copyWith(void Function(ToolCallingStreamEvent) updates) => super.copyWith((message) => updates(message as ToolCallingStreamEvent)) as ToolCallingStreamEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingStreamEvent create() => ToolCallingStreamEvent._();
  ToolCallingStreamEvent createEmptyInstance() => create();
  static $pb.PbList<ToolCallingStreamEvent> createRepeated() => $pb.PbList<ToolCallingStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingStreamEvent>(create);
  static ToolCallingStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get conversationId => $_getSZ(2);
  @$pb.TagNumber(3)
  set conversationId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasConversationId() => $_has(2);
  @$pb.TagNumber(3)
  void clearConversationId() => clearField(3);

  @$pb.TagNumber(4)
  ToolCallingStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(ToolCallingStreamEventKind v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get token => $_getSZ(4);
  @$pb.TagNumber(5)
  set token($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasToken() => $_has(4);
  @$pb.TagNumber(5)
  void clearToken() => clearField(5);

  @$pb.TagNumber(6)
  ToolCall get toolCall => $_getN(5);
  @$pb.TagNumber(6)
  set toolCall(ToolCall v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasToolCall() => $_has(5);
  @$pb.TagNumber(6)
  void clearToolCall() => clearField(6);
  @$pb.TagNumber(6)
  ToolCall ensureToolCall() => $_ensure(5);

  @$pb.TagNumber(7)
  ToolResult get toolResult => $_getN(6);
  @$pb.TagNumber(7)
  set toolResult(ToolResult v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasToolResult() => $_has(6);
  @$pb.TagNumber(7)
  void clearToolResult() => clearField(7);
  @$pb.TagNumber(7)
  ToolResult ensureToolResult() => $_ensure(6);

  @$pb.TagNumber(8)
  ToolCallingResult get result => $_getN(7);
  @$pb.TagNumber(8)
  set result(ToolCallingResult v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasResult() => $_has(7);
  @$pb.TagNumber(8)
  void clearResult() => clearField(8);
  @$pb.TagNumber(8)
  ToolCallingResult ensureResult() => $_ensure(7);

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get errorCode => $_getIZ(9);
  @$pb.TagNumber(10)
  set errorCode($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasErrorCode() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorCode() => clearField(10);
}

class ToolRegistrySnapshot extends $pb.GeneratedMessage {
  factory ToolRegistrySnapshot({
    $core.Iterable<ToolDefinition>? tools,
    $fixnum.Int64? updatedAtMs,
  }) {
    final $result = create();
    if (tools != null) {
      $result.tools.addAll(tools);
    }
    if (updatedAtMs != null) {
      $result.updatedAtMs = updatedAtMs;
    }
    return $result;
  }
  ToolRegistrySnapshot._() : super();
  factory ToolRegistrySnapshot.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolRegistrySnapshot.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolRegistrySnapshot', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<ToolDefinition>(1, _omitFieldNames ? '' : 'tools', $pb.PbFieldType.PM, subBuilder: ToolDefinition.create)
    ..aInt64(2, _omitFieldNames ? '' : 'updatedAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolRegistrySnapshot clone() => ToolRegistrySnapshot()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolRegistrySnapshot copyWith(void Function(ToolRegistrySnapshot) updates) => super.copyWith((message) => updates(message as ToolRegistrySnapshot)) as ToolRegistrySnapshot;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolRegistrySnapshot create() => ToolRegistrySnapshot._();
  ToolRegistrySnapshot createEmptyInstance() => create();
  static $pb.PbList<ToolRegistrySnapshot> createRepeated() => $pb.PbList<ToolRegistrySnapshot>();
  @$core.pragma('dart2js:noInline')
  static ToolRegistrySnapshot getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolRegistrySnapshot>(create);
  static ToolRegistrySnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ToolDefinition> get tools => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get updatedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set updatedAtMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUpdatedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearUpdatedAtMs() => clearField(2);
}

class ToolCallingSessionCreateRequest extends $pb.GeneratedMessage {
  factory ToolCallingSessionCreateRequest({
    $core.String? prompt,
    $core.Iterable<ToolDefinition>? tools,
    $core.String? formatHint,
    $core.int? maxIterations,
    $core.bool? keepToolsAvailable,
    $core.bool? validateCalls,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.String? systemPrompt,
  }) {
    final $result = create();
    if (prompt != null) {
      $result.prompt = prompt;
    }
    if (tools != null) {
      $result.tools.addAll(tools);
    }
    if (formatHint != null) {
      $result.formatHint = formatHint;
    }
    if (maxIterations != null) {
      $result.maxIterations = maxIterations;
    }
    if (keepToolsAvailable != null) {
      $result.keepToolsAvailable = keepToolsAvailable;
    }
    if (validateCalls != null) {
      $result.validateCalls = validateCalls;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (topP != null) {
      $result.topP = topP;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    return $result;
  }
  ToolCallingSessionCreateRequest._() : super();
  factory ToolCallingSessionCreateRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingSessionCreateRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingSessionCreateRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..pc<ToolDefinition>(2, _omitFieldNames ? '' : 'tools', $pb.PbFieldType.PM, subBuilder: ToolDefinition.create)
    ..aOS(3, _omitFieldNames ? '' : 'formatHint')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'maxIterations', $pb.PbFieldType.OU3)
    ..aOB(5, _omitFieldNames ? '' : 'keepToolsAvailable')
    ..aOB(6, _omitFieldNames ? '' : 'validateCalls')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(12, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(13, _omitFieldNames ? '' : 'topP', $pb.PbFieldType.OF)
    ..aOS(14, _omitFieldNames ? '' : 'systemPrompt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingSessionCreateRequest clone() => ToolCallingSessionCreateRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingSessionCreateRequest copyWith(void Function(ToolCallingSessionCreateRequest) updates) => super.copyWith((message) => updates(message as ToolCallingSessionCreateRequest)) as ToolCallingSessionCreateRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateRequest create() => ToolCallingSessionCreateRequest._();
  ToolCallingSessionCreateRequest createEmptyInstance() => create();
  static $pb.PbList<ToolCallingSessionCreateRequest> createRepeated() => $pb.PbList<ToolCallingSessionCreateRequest>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionCreateRequest>(create);
  static ToolCallingSessionCreateRequest? _defaultInstance;

  /// Prompt + LLM generation options inline (avoids cross-proto import cycle).
  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ToolDefinition> get tools => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get formatHint => $_getSZ(2);
  @$pb.TagNumber(3)
  set formatHint($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFormatHint() => $_has(2);
  @$pb.TagNumber(3)
  void clearFormatHint() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxIterations => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxIterations($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMaxIterations() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxIterations() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get keepToolsAvailable => $_getBF(4);
  @$pb.TagNumber(5)
  set keepToolsAvailable($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasKeepToolsAvailable() => $_has(4);
  @$pb.TagNumber(5)
  void clearKeepToolsAvailable() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get validateCalls => $_getBF(5);
  @$pb.TagNumber(6)
  set validateCalls($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasValidateCalls() => $_has(5);
  @$pb.TagNumber(6)
  void clearValidateCalls() => clearField(6);

  @$pb.TagNumber(11)
  $core.int get maxTokens => $_getIZ(6);
  @$pb.TagNumber(11)
  set maxTokens($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(11)
  $core.bool hasMaxTokens() => $_has(6);
  @$pb.TagNumber(11)
  void clearMaxTokens() => clearField(11);

  @$pb.TagNumber(12)
  $core.double get temperature => $_getN(7);
  @$pb.TagNumber(12)
  set temperature($core.double v) { $_setFloat(7, v); }
  @$pb.TagNumber(12)
  $core.bool hasTemperature() => $_has(7);
  @$pb.TagNumber(12)
  void clearTemperature() => clearField(12);

  @$pb.TagNumber(13)
  $core.double get topP => $_getN(8);
  @$pb.TagNumber(13)
  set topP($core.double v) { $_setFloat(8, v); }
  @$pb.TagNumber(13)
  $core.bool hasTopP() => $_has(8);
  @$pb.TagNumber(13)
  void clearTopP() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get systemPrompt => $_getSZ(9);
  @$pb.TagNumber(14)
  set systemPrompt($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(14)
  $core.bool hasSystemPrompt() => $_has(9);
  @$pb.TagNumber(14)
  void clearSystemPrompt() => clearField(14);
}

class ToolCallingSessionCreateResult extends $pb.GeneratedMessage {
  factory ToolCallingSessionCreateResult({
    $fixnum.Int64? sessionHandle,
  }) {
    final $result = create();
    if (sessionHandle != null) {
      $result.sessionHandle = sessionHandle;
    }
    return $result;
  }
  ToolCallingSessionCreateResult._() : super();
  factory ToolCallingSessionCreateResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingSessionCreateResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingSessionCreateResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'sessionHandle', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingSessionCreateResult clone() => ToolCallingSessionCreateResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingSessionCreateResult copyWith(void Function(ToolCallingSessionCreateResult) updates) => super.copyWith((message) => updates(message as ToolCallingSessionCreateResult)) as ToolCallingSessionCreateResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateResult create() => ToolCallingSessionCreateResult._();
  ToolCallingSessionCreateResult createEmptyInstance() => create();
  static $pb.PbList<ToolCallingSessionCreateResult> createRepeated() => $pb.PbList<ToolCallingSessionCreateResult>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionCreateResult>(create);
  static ToolCallingSessionCreateResult? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sessionHandle => $_getI64(0);
  @$pb.TagNumber(1)
  set sessionHandle($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSessionHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionHandle() => clearField(1);
}

enum ToolCallingSessionEvent_Kind {
  llmStreamEventBytes, 
  toolCall, 
  finalResult, 
  errorBytes, 
  notSet
}

class ToolCallingSessionEvent extends $pb.GeneratedMessage {
  factory ToolCallingSessionEvent({
    $core.List<$core.int>? llmStreamEventBytes,
    ToolCall? toolCall,
    ToolCallingResult? finalResult,
    $core.List<$core.int>? errorBytes,
    $fixnum.Int64? seq,
  }) {
    final $result = create();
    if (llmStreamEventBytes != null) {
      $result.llmStreamEventBytes = llmStreamEventBytes;
    }
    if (toolCall != null) {
      $result.toolCall = toolCall;
    }
    if (finalResult != null) {
      $result.finalResult = finalResult;
    }
    if (errorBytes != null) {
      $result.errorBytes = errorBytes;
    }
    if (seq != null) {
      $result.seq = seq;
    }
    return $result;
  }
  ToolCallingSessionEvent._() : super();
  factory ToolCallingSessionEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingSessionEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, ToolCallingSessionEvent_Kind> _ToolCallingSessionEvent_KindByTag = {
    1 : ToolCallingSessionEvent_Kind.llmStreamEventBytes,
    2 : ToolCallingSessionEvent_Kind.toolCall,
    3 : ToolCallingSessionEvent_Kind.finalResult,
    4 : ToolCallingSessionEvent_Kind.errorBytes,
    0 : ToolCallingSessionEvent_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingSessionEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'llmStreamEventBytes', $pb.PbFieldType.OY)
    ..aOM<ToolCall>(2, _omitFieldNames ? '' : 'toolCall', subBuilder: ToolCall.create)
    ..aOM<ToolCallingResult>(3, _omitFieldNames ? '' : 'finalResult', subBuilder: ToolCallingResult.create)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'errorBytes', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingSessionEvent clone() => ToolCallingSessionEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingSessionEvent copyWith(void Function(ToolCallingSessionEvent) updates) => super.copyWith((message) => updates(message as ToolCallingSessionEvent)) as ToolCallingSessionEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionEvent create() => ToolCallingSessionEvent._();
  ToolCallingSessionEvent createEmptyInstance() => create();
  static $pb.PbList<ToolCallingSessionEvent> createRepeated() => $pb.PbList<ToolCallingSessionEvent>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionEvent>(create);
  static ToolCallingSessionEvent? _defaultInstance;

  ToolCallingSessionEvent_Kind whichKind() => _ToolCallingSessionEvent_KindByTag[$_whichOneof(0)]!;
  void clearKind() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.List<$core.int> get llmStreamEventBytes => $_getN(0);
  @$pb.TagNumber(1)
  set llmStreamEventBytes($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLlmStreamEventBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmStreamEventBytes() => clearField(1);

  @$pb.TagNumber(2)
  ToolCall get toolCall => $_getN(1);
  @$pb.TagNumber(2)
  set toolCall(ToolCall v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasToolCall() => $_has(1);
  @$pb.TagNumber(2)
  void clearToolCall() => clearField(2);
  @$pb.TagNumber(2)
  ToolCall ensureToolCall() => $_ensure(1);

  @$pb.TagNumber(3)
  ToolCallingResult get finalResult => $_getN(2);
  @$pb.TagNumber(3)
  set finalResult(ToolCallingResult v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasFinalResult() => $_has(2);
  @$pb.TagNumber(3)
  void clearFinalResult() => clearField(3);
  @$pb.TagNumber(3)
  ToolCallingResult ensureFinalResult() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get errorBytes => $_getN(3);
  @$pb.TagNumber(4)
  set errorBytes($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasErrorBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorBytes() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get seq => $_getI64(4);
  @$pb.TagNumber(5)
  set seq($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSeq() => $_has(4);
  @$pb.TagNumber(5)
  void clearSeq() => clearField(5);
}

class ToolCallingSessionStepWithResultRequest extends $pb.GeneratedMessage {
  factory ToolCallingSessionStepWithResultRequest({
    $fixnum.Int64? sessionHandle,
    $core.String? toolCallId,
    $core.String? resultJson,
    $core.String? error,
  }) {
    final $result = create();
    if (sessionHandle != null) {
      $result.sessionHandle = sessionHandle;
    }
    if (toolCallId != null) {
      $result.toolCallId = toolCallId;
    }
    if (resultJson != null) {
      $result.resultJson = resultJson;
    }
    if (error != null) {
      $result.error = error;
    }
    return $result;
  }
  ToolCallingSessionStepWithResultRequest._() : super();
  factory ToolCallingSessionStepWithResultRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingSessionStepWithResultRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingSessionStepWithResultRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'sessionHandle', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'toolCallId')
    ..aOS(3, _omitFieldNames ? '' : 'resultJson')
    ..aOS(4, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingSessionStepWithResultRequest clone() => ToolCallingSessionStepWithResultRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingSessionStepWithResultRequest copyWith(void Function(ToolCallingSessionStepWithResultRequest) updates) => super.copyWith((message) => updates(message as ToolCallingSessionStepWithResultRequest)) as ToolCallingSessionStepWithResultRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionStepWithResultRequest create() => ToolCallingSessionStepWithResultRequest._();
  ToolCallingSessionStepWithResultRequest createEmptyInstance() => create();
  static $pb.PbList<ToolCallingSessionStepWithResultRequest> createRepeated() => $pb.PbList<ToolCallingSessionStepWithResultRequest>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionStepWithResultRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionStepWithResultRequest>(create);
  static ToolCallingSessionStepWithResultRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sessionHandle => $_getI64(0);
  @$pb.TagNumber(1)
  set sessionHandle($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSessionHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionHandle() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get toolCallId => $_getSZ(1);
  @$pb.TagNumber(2)
  set toolCallId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasToolCallId() => $_has(1);
  @$pb.TagNumber(2)
  void clearToolCallId() => clearField(2);

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

class ToolCallingSessionDestroyRequest extends $pb.GeneratedMessage {
  factory ToolCallingSessionDestroyRequest({
    $fixnum.Int64? sessionHandle,
  }) {
    final $result = create();
    if (sessionHandle != null) {
      $result.sessionHandle = sessionHandle;
    }
    return $result;
  }
  ToolCallingSessionDestroyRequest._() : super();
  factory ToolCallingSessionDestroyRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolCallingSessionDestroyRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolCallingSessionDestroyRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'sessionHandle', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolCallingSessionDestroyRequest clone() => ToolCallingSessionDestroyRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolCallingSessionDestroyRequest copyWith(void Function(ToolCallingSessionDestroyRequest) updates) => super.copyWith((message) => updates(message as ToolCallingSessionDestroyRequest)) as ToolCallingSessionDestroyRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionDestroyRequest create() => ToolCallingSessionDestroyRequest._();
  ToolCallingSessionDestroyRequest createEmptyInstance() => create();
  static $pb.PbList<ToolCallingSessionDestroyRequest> createRepeated() => $pb.PbList<ToolCallingSessionDestroyRequest>();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionDestroyRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionDestroyRequest>(create);
  static ToolCallingSessionDestroyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sessionHandle => $_getI64(0);
  @$pb.TagNumber(1)
  set sessionHandle($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSessionHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionHandle() => clearField(1);
}

class ToolCallingApi {
  $pb.RpcClient _client;
  ToolCallingApi(this._client);

  $async.Future<ToolParseResult> parse($pb.ClientContext? ctx, ToolParseRequest request) =>
    _client.invoke<ToolParseResult>(ctx, 'ToolCalling', 'Parse', request, ToolParseResult())
  ;
  $async.Future<ToolPromptFormatResult> formatPrompt($pb.ClientContext? ctx, ToolPromptFormatRequest request) =>
    _client.invoke<ToolPromptFormatResult>(ctx, 'ToolCalling', 'FormatPrompt', request, ToolPromptFormatResult())
  ;
  $async.Future<ToolCallValidationResult> validateCall($pb.ClientContext? ctx, ToolCallValidationRequest request) =>
    _client.invoke<ToolCallValidationResult>(ctx, 'ToolCalling', 'ValidateCall', request, ToolCallValidationResult())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
