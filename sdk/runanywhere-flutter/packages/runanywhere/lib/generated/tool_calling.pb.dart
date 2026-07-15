// This is a generated file - do not edit.
//
// Generated from tool_calling.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'tool_calling.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

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
    final result = create();
    if (stringValue != null) result.stringValue = stringValue;
    if (numberValue != null) result.numberValue = numberValue;
    if (boolValue != null) result.boolValue = boolValue;
    if (arrayValue != null) result.arrayValue = arrayValue;
    if (objectValue != null) result.objectValue = objectValue;
    if (nullValue != null) result.nullValue = nullValue;
    return result;
  }

  ToolValue._();

  factory ToolValue.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolValue.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ToolValue_Kind> _ToolValue_KindByTag = {
    1: ToolValue_Kind.stringValue,
    2: ToolValue_Kind.numberValue,
    3: ToolValue_Kind.boolValue,
    4: ToolValue_Kind.arrayValue,
    5: ToolValue_Kind.objectValue,
    6: ToolValue_Kind.nullValue,
    0: ToolValue_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolValue',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6])
    ..aOS(1, _omitFieldNames ? '' : 'stringValue')
    ..aD(2, _omitFieldNames ? '' : 'numberValue')
    ..aOB(3, _omitFieldNames ? '' : 'boolValue')
    ..aOM<ToolValueArray>(4, _omitFieldNames ? '' : 'arrayValue',
        subBuilder: ToolValueArray.create)
    ..aOM<ToolValueObject>(5, _omitFieldNames ? '' : 'objectValue',
        subBuilder: ToolValueObject.create)
    ..aOB(6, _omitFieldNames ? '' : 'nullValue')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValue clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValue copyWith(void Function(ToolValue) updates) =>
      super.copyWith((message) => updates(message as ToolValue)) as ToolValue;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolValue create() => ToolValue._();
  @$core.override
  ToolValue createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolValue getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolValue>(create);
  static ToolValue? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  ToolValue_Kind whichKind() => _ToolValue_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearKind() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get stringValue => $_getSZ(0);
  @$pb.TagNumber(1)
  set stringValue($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStringValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearStringValue() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get numberValue => $_getN(1);
  @$pb.TagNumber(2)
  set numberValue($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNumberValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearNumberValue() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get boolValue => $_getBF(2);
  @$pb.TagNumber(3)
  set boolValue($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBoolValue() => $_has(2);
  @$pb.TagNumber(3)
  void clearBoolValue() => $_clearField(3);

  @$pb.TagNumber(4)
  ToolValueArray get arrayValue => $_getN(3);
  @$pb.TagNumber(4)
  set arrayValue(ToolValueArray value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasArrayValue() => $_has(3);
  @$pb.TagNumber(4)
  void clearArrayValue() => $_clearField(4);
  @$pb.TagNumber(4)
  ToolValueArray ensureArrayValue() => $_ensure(3);

  @$pb.TagNumber(5)
  ToolValueObject get objectValue => $_getN(4);
  @$pb.TagNumber(5)
  set objectValue(ToolValueObject value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasObjectValue() => $_has(4);
  @$pb.TagNumber(5)
  void clearObjectValue() => $_clearField(5);
  @$pb.TagNumber(5)
  ToolValueObject ensureObjectValue() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.bool get nullValue => $_getBF(5);
  @$pb.TagNumber(6)
  set nullValue($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNullValue() => $_has(5);
  @$pb.TagNumber(6)
  void clearNullValue() => $_clearField(6);
}

class ToolValueArray extends $pb.GeneratedMessage {
  factory ToolValueArray({
    $core.Iterable<ToolValue>? values,
  }) {
    final result = create();
    if (values != null) result.values.addAll(values);
    return result;
  }

  ToolValueArray._();

  factory ToolValueArray.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolValueArray.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolValueArray',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<ToolValue>(1, _omitFieldNames ? '' : 'values',
        subBuilder: ToolValue.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValueArray clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValueArray copyWith(void Function(ToolValueArray) updates) =>
      super.copyWith((message) => updates(message as ToolValueArray))
          as ToolValueArray;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolValueArray create() => ToolValueArray._();
  @$core.override
  ToolValueArray createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolValueArray getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolValueArray>(create);
  static ToolValueArray? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ToolValue> get values => $_getList(0);
}

class ToolValueObject extends $pb.GeneratedMessage {
  factory ToolValueObject({
    $core.Iterable<$core.MapEntry<$core.String, ToolValue>>? fields,
  }) {
    final result = create();
    if (fields != null) result.fields.addEntries(fields);
    return result;
  }

  ToolValueObject._();

  factory ToolValueObject.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolValueObject.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolValueObject',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..m<$core.String, ToolValue>(1, _omitFieldNames ? '' : 'fields',
        entryClassName: 'ToolValueObject.FieldsEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OM,
        valueCreator: ToolValue.create,
        valueDefaultOrMaker: ToolValue.getDefault,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValueObject clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValueObject copyWith(void Function(ToolValueObject) updates) =>
      super.copyWith((message) => updates(message as ToolValueObject))
          as ToolValueObject;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolValueObject create() => ToolValueObject._();
  @$core.override
  ToolValueObject createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolValueObject getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolValueObject>(create);
  static ToolValueObject? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbMap<$core.String, ToolValue> get fields => $_getMap(0);
}

/// ---------------------------------------------------------------------------
/// String wrapper used by the rac_tool_value_to_json_proto /
/// rac_tool_value_from_json_proto ABIs. Carries either the JSON text rendered
/// from a ToolValue, or the JSON text that should be parsed back into a
/// ToolValue. Defined here (rather than reusing a stand-alone wrapper) so the
/// tool-calling round-trip stays self-contained in this proto.
/// ---------------------------------------------------------------------------
class ToolValueJSON extends $pb.GeneratedMessage {
  factory ToolValueJSON({
    $core.String? json,
  }) {
    final result = create();
    if (json != null) result.json = json;
    return result;
  }

  ToolValueJSON._();

  factory ToolValueJSON.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolValueJSON.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolValueJSON',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'json')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValueJSON clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolValueJSON copyWith(void Function(ToolValueJSON) updates) =>
      super.copyWith((message) => updates(message as ToolValueJSON))
          as ToolValueJSON;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolValueJSON create() => ToolValueJSON._();
  @$core.override
  ToolValueJSON createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolValueJSON getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolValueJSON>(create);
  static ToolValueJSON? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get json => $_getSZ(0);
  @$pb.TagNumber(1)
  set json($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearJson() => $_clearField(1);
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
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (description != null) result.description = description;
    if (required != null) result.required = required;
    if (enumValues != null) result.enumValues.addAll(enumValues);
    if (jsonSchema != null) result.jsonSchema = jsonSchema;
    if (defaultValue != null) result.defaultValue = defaultValue;
    return result;
  }

  ToolParameter._();

  factory ToolParameter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolParameter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolParameter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aE<ToolParameterType>(2, _omitFieldNames ? '' : 'type',
        enumValues: ToolParameterType.values)
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOB(4, _omitFieldNames ? '' : 'required')
    ..pPS(5, _omitFieldNames ? '' : 'enumValues')
    ..aOS(6, _omitFieldNames ? '' : 'jsonSchema')
    ..aOM<ToolValue>(7, _omitFieldNames ? '' : 'defaultValue',
        subBuilder: ToolValue.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolParameter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolParameter copyWith(void Function(ToolParameter) updates) =>
      super.copyWith((message) => updates(message as ToolParameter))
          as ToolParameter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolParameter create() => ToolParameter._();
  @$core.override
  ToolParameter createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolParameter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolParameter>(create);
  static ToolParameter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  ToolParameterType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(ToolParameterType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get required => $_getBF(3);
  @$pb.TagNumber(4)
  set required($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRequired() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequired() => $_clearField(4);

  /// Allowed values for enum-like parameters. Empty = unconstrained.
  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get enumValues => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get jsonSchema => $_getSZ(5);
  @$pb.TagNumber(6)
  set jsonSchema($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasJsonSchema() => $_has(5);
  @$pb.TagNumber(6)
  void clearJsonSchema() => $_clearField(6);

  @$pb.TagNumber(7)
  ToolValue get defaultValue => $_getN(6);
  @$pb.TagNumber(7)
  set defaultValue(ToolValue value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasDefaultValue() => $_has(6);
  @$pb.TagNumber(7)
  void clearDefaultValue() => $_clearField(7);
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
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (parameters != null) result.parameters.addAll(parameters);
    if (category != null) result.category = category;
    if (jsonSchema != null) result.jsonSchema = jsonSchema;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  ToolDefinition._();

  factory ToolDefinition.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolDefinition.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolDefinition',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..pPM<ToolParameter>(3, _omitFieldNames ? '' : 'parameters',
        subBuilder: ToolParameter.create)
    ..aOS(4, _omitFieldNames ? '' : 'category')
    ..aOS(5, _omitFieldNames ? '' : 'jsonSchema')
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'ToolDefinition.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolDefinition clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolDefinition copyWith(void Function(ToolDefinition) updates) =>
      super.copyWith((message) => updates(message as ToolDefinition))
          as ToolDefinition;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolDefinition create() => ToolDefinition._();
  @$core.override
  ToolDefinition createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolDefinition getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolDefinition>(create);
  static ToolDefinition? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<ToolParameter> get parameters => $_getList(2);

  /// Optional category for grouping tools in catalogs / UIs.
  @$pb.TagNumber(4)
  $core.String get category => $_getSZ(3);
  @$pb.TagNumber(4)
  set category($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCategory() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategory() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get jsonSchema => $_getSZ(4);
  @$pb.TagNumber(5)
  set jsonSchema($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasJsonSchema() => $_has(4);
  @$pb.TagNumber(5)
  void clearJsonSchema() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(5);
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
    $fixnum.Int64? createdAtMs,
    $core.String? rawText,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (argumentsJson != null) result.argumentsJson = argumentsJson;
    if (type != null) result.type = type;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (rawText != null) result.rawText = rawText;
    return result;
  }

  ToolCall._();

  factory ToolCall.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCall.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCall',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'argumentsJson')
    ..aOS(4, _omitFieldNames ? '' : 'type')
    ..aInt64(7, _omitFieldNames ? '' : 'createdAtMs')
    ..aOS(8, _omitFieldNames ? '' : 'rawText')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCall clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCall copyWith(void Function(ToolCall) updates) =>
      super.copyWith((message) => updates(message as ToolCall)) as ToolCall;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCall create() => ToolCall._();
  @$core.override
  ToolCall createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCall getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolCall>(create);
  static ToolCall? _defaultInstance;

  /// Unique ID (caller-supplied or generated). Empty = unset.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Tool name (matches ToolDefinition.name).
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// JSON-encoded arguments. Empty object "{}" if no args.
  ///
  /// The C++ tokenizer / tool-prompt formatter
  /// (sdk/runanywhere-commons/src/features/llm/tool_calling.cpp) reads
  /// `arguments_json` directly when building LLM prompts. It is the
  /// canonical wire shape for the prompt-formatting path.
  @$pb.TagNumber(3)
  $core.String get argumentsJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set argumentsJson($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasArgumentsJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearArgumentsJson() => $_clearField(3);

  /// Discriminator for OpenAI-compatible flows ("function" is the only
  /// value at the moment). Empty = unset.
  @$pb.TagNumber(4)
  $core.String get type => $_getSZ(3);
  @$pb.TagNumber(4)
  set type($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasType() => $_has(3);
  @$pb.TagNumber(4)
  void clearType() => $_clearField(4);

  @$pb.TagNumber(7)
  $fixnum.Int64 get createdAtMs => $_getI64(4);
  @$pb.TagNumber(7)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(7)
  $core.bool hasCreatedAtMs() => $_has(4);
  @$pb.TagNumber(7)
  void clearCreatedAtMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get rawText => $_getSZ(5);
  @$pb.TagNumber(8)
  set rawText($core.String value) => $_setString(5, value);
  @$pb.TagNumber(8)
  $core.bool hasRawText() => $_has(5);
  @$pb.TagNumber(8)
  void clearRawText() => $_clearField(8);
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
    $fixnum.Int64? startedAtMs,
    $fixnum.Int64? completedAtMs,
  }) {
    final result = create();
    if (toolCallId != null) result.toolCallId = toolCallId;
    if (name != null) result.name = name;
    if (resultJson != null) result.resultJson = resultJson;
    if (error != null) result.error = error;
    if (success != null) result.success = success;
    if (startedAtMs != null) result.startedAtMs = startedAtMs;
    if (completedAtMs != null) result.completedAtMs = completedAtMs;
    return result;
  }

  ToolResult._();

  factory ToolResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'toolCallId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'resultJson')
    ..aOS(4, _omitFieldNames ? '' : 'error')
    ..aOB(5, _omitFieldNames ? '' : 'success')
    ..aInt64(8, _omitFieldNames ? '' : 'startedAtMs')
    ..aInt64(9, _omitFieldNames ? '' : 'completedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolResult copyWith(void Function(ToolResult) updates) =>
      super.copyWith((message) => updates(message as ToolResult)) as ToolResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolResult create() => ToolResult._();
  @$core.override
  ToolResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolResult>(create);
  static ToolResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get toolCallId => $_getSZ(0);
  @$pb.TagNumber(1)
  set toolCallId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToolCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearToolCallId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// JSON-encoded tool execution result.
  ///
  /// The C++ tool-prompt formatter
  /// (`sdk/runanywhere-commons/src/features/llm/tool_calling.cpp:1870-1885`)
  /// reads `result_json` directly when building follow-up LLM prompts after
  /// tool execution. It is the canonical wire shape.
  @$pb.TagNumber(3)
  $core.String get resultJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set resultJson($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResultJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearResultJson() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get error => $_getSZ(3);
  @$pb.TagNumber(4)
  set error($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);

  /// Whether execution succeeded. If unset/false and error is empty,
  /// consumers should fall back to result_json/error semantics.
  @$pb.TagNumber(5)
  $core.bool get success => $_getBF(4);
  @$pb.TagNumber(5)
  set success($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSuccess() => $_has(4);
  @$pb.TagNumber(5)
  void clearSuccess() => $_clearField(5);

  @$pb.TagNumber(8)
  $fixnum.Int64 get startedAtMs => $_getI64(5);
  @$pb.TagNumber(8)
  set startedAtMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(8)
  $core.bool hasStartedAtMs() => $_has(5);
  @$pb.TagNumber(8)
  void clearStartedAtMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get completedAtMs => $_getI64(6);
  @$pb.TagNumber(9)
  set completedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(9)
  $core.bool hasCompletedAtMs() => $_has(6);
  @$pb.TagNumber(9)
  void clearCompletedAtMs() => $_clearField(9);
}

/// ---------------------------------------------------------------------------
/// Options for tool-enabled generation.
/// ---------------------------------------------------------------------------
class ToolCallingOptions extends $pb.GeneratedMessage {
  factory ToolCallingOptions({
    $core.Iterable<ToolDefinition>? tools,
    $core.bool? autoExecute,
    $core.double? temperature,
    $core.int? maxTokens,
    $core.String? systemPrompt,
    $core.bool? replaceSystemPrompt,
    $core.bool? keepToolsAvailable,
    ToolCallFormatName? format,
    $core.int? maxToolCalls,
    ToolChoiceMode? toolChoice,
    $core.String? forcedToolName,
    $core.bool? requireJsonArguments,
    $core.bool? disableThinking,
  }) {
    final result = create();
    if (tools != null) result.tools.addAll(tools);
    if (autoExecute != null) result.autoExecute = autoExecute;
    if (temperature != null) result.temperature = temperature;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (replaceSystemPrompt != null)
      result.replaceSystemPrompt = replaceSystemPrompt;
    if (keepToolsAvailable != null)
      result.keepToolsAvailable = keepToolsAvailable;
    if (format != null) result.format = format;
    if (maxToolCalls != null) result.maxToolCalls = maxToolCalls;
    if (toolChoice != null) result.toolChoice = toolChoice;
    if (forcedToolName != null) result.forcedToolName = forcedToolName;
    if (requireJsonArguments != null)
      result.requireJsonArguments = requireJsonArguments;
    if (disableThinking != null) result.disableThinking = disableThinking;
    return result;
  }

  ToolCallingOptions._();

  factory ToolCallingOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<ToolDefinition>(1, _omitFieldNames ? '' : 'tools',
        subBuilder: ToolDefinition.create)
    ..aOB(3, _omitFieldNames ? '' : 'autoExecute')
    ..aD(4, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aI(5, _omitFieldNames ? '' : 'maxTokens')
    ..aOS(6, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(7, _omitFieldNames ? '' : 'replaceSystemPrompt')
    ..aOB(8, _omitFieldNames ? '' : 'keepToolsAvailable')
    ..aE<ToolCallFormatName>(10, _omitFieldNames ? '' : 'format',
        enumValues: ToolCallFormatName.values)
    ..aI(12, _omitFieldNames ? '' : 'maxToolCalls')
    ..aE<ToolChoiceMode>(13, _omitFieldNames ? '' : 'toolChoice',
        enumValues: ToolChoiceMode.values)
    ..aOS(14, _omitFieldNames ? '' : 'forcedToolName')
    ..aOB(16, _omitFieldNames ? '' : 'requireJsonArguments')
    ..aOB(17, _omitFieldNames ? '' : 'disableThinking')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingOptions copyWith(void Function(ToolCallingOptions) updates) =>
      super.copyWith((message) => updates(message as ToolCallingOptions))
          as ToolCallingOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingOptions create() => ToolCallingOptions._();
  @$core.override
  ToolCallingOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallingOptions>(create);
  static ToolCallingOptions? _defaultInstance;

  /// Available tools for this generation. If empty, the SDK falls back to
  /// its registered tools (per-SDK convention).
  @$pb.TagNumber(1)
  $pb.PbList<ToolDefinition> get tools => $_getList(0);

  /// Whether to auto-execute tools or hand them back to the caller.
  @$pb.TagNumber(3)
  $core.bool get autoExecute => $_getBF(1);
  @$pb.TagNumber(3)
  set autoExecute($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(3)
  $core.bool hasAutoExecute() => $_has(1);
  @$pb.TagNumber(3)
  void clearAutoExecute() => $_clearField(3);

  /// Sampling temperature override (Swift: optional Float).
  @$pb.TagNumber(4)
  $core.double get temperature => $_getN(2);
  @$pb.TagNumber(4)
  set temperature($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(4)
  $core.bool hasTemperature() => $_has(2);
  @$pb.TagNumber(4)
  void clearTemperature() => $_clearField(4);

  /// Maximum tokens override.
  @$pb.TagNumber(5)
  $core.int get maxTokens => $_getIZ(3);
  @$pb.TagNumber(5)
  set maxTokens($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxTokens() => $_has(3);
  @$pb.TagNumber(5)
  void clearMaxTokens() => $_clearField(5);

  /// System prompt to use during tool-enabled generation.
  @$pb.TagNumber(6)
  $core.String get systemPrompt => $_getSZ(4);
  @$pb.TagNumber(6)
  set systemPrompt($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasSystemPrompt() => $_has(4);
  @$pb.TagNumber(6)
  void clearSystemPrompt() => $_clearField(6);

  /// If true, replaces the system prompt entirely (no auto-injected
  /// tool instructions).
  @$pb.TagNumber(7)
  $core.bool get replaceSystemPrompt => $_getBF(5);
  @$pb.TagNumber(7)
  set replaceSystemPrompt($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(7)
  $core.bool hasReplaceSystemPrompt() => $_has(5);
  @$pb.TagNumber(7)
  void clearReplaceSystemPrompt() => $_clearField(7);

  /// If true, keeps tool definitions available across multiple sequential
  /// tool calls in one generation.
  @$pb.TagNumber(8)
  $core.bool get keepToolsAvailable => $_getBF(6);
  @$pb.TagNumber(8)
  set keepToolsAvailable($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(8)
  $core.bool hasKeepToolsAvailable() => $_has(6);
  @$pb.TagNumber(8)
  void clearKeepToolsAvailable() => $_clearField(8);

  /// Typed tool-call format. Unset lets commons select the model default.
  @$pb.TagNumber(10)
  ToolCallFormatName get format => $_getN(7);
  @$pb.TagNumber(10)
  set format(ToolCallFormatName value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasFormat() => $_has(7);
  @$pb.TagNumber(10)
  void clearFormat() => $_clearField(10);

  /// Maximum tool calls in one conversation turn. Unset/0 = SDK default
  /// (typically 5).
  @$pb.TagNumber(12)
  $core.int get maxToolCalls => $_getIZ(8);
  @$pb.TagNumber(12)
  set maxToolCalls($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(12)
  $core.bool hasMaxToolCalls() => $_has(8);
  @$pb.TagNumber(12)
  void clearMaxToolCalls() => $_clearField(12);

  @$pb.TagNumber(13)
  ToolChoiceMode get toolChoice => $_getN(9);
  @$pb.TagNumber(13)
  set toolChoice(ToolChoiceMode value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasToolChoice() => $_has(9);
  @$pb.TagNumber(13)
  void clearToolChoice() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get forcedToolName => $_getSZ(10);
  @$pb.TagNumber(14)
  set forcedToolName($core.String value) => $_setString(10, value);
  @$pb.TagNumber(14)
  $core.bool hasForcedToolName() => $_has(10);
  @$pb.TagNumber(14)
  void clearForcedToolName() => $_clearField(14);

  @$pb.TagNumber(16)
  $core.bool get requireJsonArguments => $_getBF(11);
  @$pb.TagNumber(16)
  set requireJsonArguments($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(16)
  $core.bool hasRequireJsonArguments() => $_has(11);
  @$pb.TagNumber(16)
  void clearRequireJsonArguments() => $_clearField(16);

  /// When true, suppress the model's thinking/reasoning phase during
  /// tool-enabled generation (commons prepends the model no-think directive
  /// at the prompt level — same contract as
  /// LLMGenerationOptions.disable_thinking). Default false.
  @$pb.TagNumber(17)
  $core.bool get disableThinking => $_getBF(12);
  @$pb.TagNumber(17)
  set disableThinking($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(17)
  $core.bool hasDisableThinking() => $_has(12);
  @$pb.TagNumber(17)
  void clearDisableThinking() => $_clearField(17);
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
    $core.String? thinkingContent,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (toolResults != null) result.toolResults.addAll(toolResults);
    if (isComplete != null) result.isComplete = isComplete;
    if (conversationId != null) result.conversationId = conversationId;
    if (iterationsUsed != null) result.iterationsUsed = iterationsUsed;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (rawText != null) result.rawText = rawText;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    return result;
  }

  ToolCallingResult._();

  factory ToolCallingResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..pPM<ToolCall>(2, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: ToolCall.create)
    ..pPM<ToolResult>(3, _omitFieldNames ? '' : 'toolResults',
        subBuilder: ToolResult.create)
    ..aOB(4, _omitFieldNames ? '' : 'isComplete')
    ..aOS(5, _omitFieldNames ? '' : 'conversationId')
    ..aI(6, _omitFieldNames ? '' : 'iterationsUsed')
    ..aOS(7, _omitFieldNames ? '' : 'errorMessage')
    ..aI(8, _omitFieldNames ? '' : 'errorCode')
    ..aOS(9, _omitFieldNames ? '' : 'rawText')
    ..aOS(10, _omitFieldNames ? '' : 'thinkingContent')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingResult copyWith(void Function(ToolCallingResult) updates) =>
      super.copyWith((message) => updates(message as ToolCallingResult))
          as ToolCallingResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingResult create() => ToolCallingResult._();
  @$core.override
  ToolCallingResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallingResult>(create);
  static ToolCallingResult? _defaultInstance;

  /// Final text response from the assistant.
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  /// Tool calls the LLM made.
  @$pb.TagNumber(2)
  $pb.PbList<ToolCall> get toolCalls => $_getList(1);

  /// Results of executed tools (only populated when auto_execute was true).
  @$pb.TagNumber(3)
  $pb.PbList<ToolResult> get toolResults => $_getList(2);

  /// Whether the response is complete or waiting for more tool results.
  @$pb.TagNumber(4)
  $core.bool get isComplete => $_getBF(3);
  @$pb.TagNumber(4)
  set isComplete($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsComplete() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsComplete() => $_clearField(4);

  /// Conversation ID for continuing with tool results.
  @$pb.TagNumber(5)
  $core.String get conversationId => $_getSZ(4);
  @$pb.TagNumber(5)
  set conversationId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasConversationId() => $_has(4);
  @$pb.TagNumber(5)
  void clearConversationId() => $_clearField(5);

  /// Number of LLM generation turns used, including the final synthesis turn.
  @$pb.TagNumber(6)
  $core.int get iterationsUsed => $_getIZ(5);
  @$pb.TagNumber(6)
  set iterationsUsed($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIterationsUsed() => $_has(5);
  @$pb.TagNumber(6)
  void clearIterationsUsed() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get errorMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set errorMessage($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorMessage() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get errorCode => $_getIZ(7);
  @$pb.TagNumber(8)
  set errorCode($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasErrorCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorCode() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get rawText => $_getSZ(8);
  @$pb.TagNumber(9)
  set rawText($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRawText() => $_has(8);
  @$pb.TagNumber(9)
  void clearRawText() => $_clearField(9);

  /// Optional thinking/reasoning content extracted from the final response.
  @$pb.TagNumber(10)
  $core.String get thinkingContent => $_getSZ(9);
  @$pb.TagNumber(10)
  set thinkingContent($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasThinkingContent() => $_has(9);
  @$pb.TagNumber(10)
  void clearThinkingContent() => $_clearField(10);
}

class ToolParseRequest extends $pb.GeneratedMessage {
  factory ToolParseRequest({
    $core.String? text,
    ToolCallingOptions? options,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (options != null) result.options = options;
    return result;
  }

  ToolParseRequest._();

  factory ToolParseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolParseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolParseRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOM<ToolCallingOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: ToolCallingOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolParseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolParseRequest copyWith(void Function(ToolParseRequest) updates) =>
      super.copyWith((message) => updates(message as ToolParseRequest))
          as ToolParseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolParseRequest create() => ToolParseRequest._();
  @$core.override
  ToolParseRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolParseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolParseRequest>(create);
  static ToolParseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  ToolCallingOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(ToolCallingOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
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
    final result = create();
    if (hasToolCall != null) result.hasToolCall = hasToolCall;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (remainingText != null) result.remainingText = remainingText;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  ToolParseResult._();

  factory ToolParseResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolParseResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolParseResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'hasToolCall')
    ..pPM<ToolCall>(2, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: ToolCall.create)
    ..aOS(3, _omitFieldNames ? '' : 'remainingText')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..aI(5, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolParseResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolParseResult copyWith(void Function(ToolParseResult) updates) =>
      super.copyWith((message) => updates(message as ToolParseResult))
          as ToolParseResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolParseResult create() => ToolParseResult._();
  @$core.override
  ToolParseResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolParseResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolParseResult>(create);
  static ToolParseResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get hasToolCall => $_getBF(0);
  @$pb.TagNumber(1)
  set hasToolCall($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHasToolCall() => $_has(0);
  @$pb.TagNumber(1)
  void clearHasToolCall() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ToolCall> get toolCalls => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get remainingText => $_getSZ(2);
  @$pb.TagNumber(3)
  set remainingText($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRemainingText() => $_has(2);
  @$pb.TagNumber(3)
  void clearRemainingText() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => $_clearField(5);
}

class ToolPromptFormatRequest extends $pb.GeneratedMessage {
  factory ToolPromptFormatRequest({
    $core.String? userPrompt,
    ToolCallingOptions? options,
    $core.Iterable<ToolResult>? toolResults,
    $core.String? assistantText,
  }) {
    final result = create();
    if (userPrompt != null) result.userPrompt = userPrompt;
    if (options != null) result.options = options;
    if (toolResults != null) result.toolResults.addAll(toolResults);
    if (assistantText != null) result.assistantText = assistantText;
    return result;
  }

  ToolPromptFormatRequest._();

  factory ToolPromptFormatRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolPromptFormatRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolPromptFormatRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userPrompt')
    ..aOM<ToolCallingOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: ToolCallingOptions.create)
    ..pPM<ToolResult>(3, _omitFieldNames ? '' : 'toolResults',
        subBuilder: ToolResult.create)
    ..aOS(4, _omitFieldNames ? '' : 'assistantText')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolPromptFormatRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolPromptFormatRequest copyWith(
          void Function(ToolPromptFormatRequest) updates) =>
      super.copyWith((message) => updates(message as ToolPromptFormatRequest))
          as ToolPromptFormatRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatRequest create() => ToolPromptFormatRequest._();
  @$core.override
  ToolPromptFormatRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolPromptFormatRequest>(create);
  static ToolPromptFormatRequest? _defaultInstance;

  /// User prompt to merge with tool instructions. Empty means return only
  /// the tool-instruction block for the selected format.
  @$pb.TagNumber(1)
  $core.String get userPrompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set userPrompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserPrompt() => $_clearField(1);

  /// Carries available tools plus format/choice/iteration constraints.
  @$pb.TagNumber(2)
  ToolCallingOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(ToolCallingOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
  @$pb.TagNumber(2)
  ToolCallingOptions ensureOptions() => $_ensure(1);

  /// Tool results to include when formatting a follow-up prompt after host
  /// execution. Empty means an initial tool-enabled prompt.
  @$pb.TagNumber(3)
  $pb.PbList<ToolResult> get toolResults => $_getList(2);

  /// Assistant text emitted before tool execution, when available.
  @$pb.TagNumber(4)
  $core.String get assistantText => $_getSZ(3);
  @$pb.TagNumber(4)
  set assistantText($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAssistantText() => $_has(3);
  @$pb.TagNumber(4)
  void clearAssistantText() => $_clearField(4);
}

class ToolPromptFormatResult extends $pb.GeneratedMessage {
  factory ToolPromptFormatResult({
    $core.String? formattedPrompt,
    ToolCallFormatName? format,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (formattedPrompt != null) result.formattedPrompt = formattedPrompt;
    if (format != null) result.format = format;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  ToolPromptFormatResult._();

  factory ToolPromptFormatResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolPromptFormatResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolPromptFormatResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'formattedPrompt')
    ..aE<ToolCallFormatName>(2, _omitFieldNames ? '' : 'format',
        enumValues: ToolCallFormatName.values)
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..aI(5, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolPromptFormatResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolPromptFormatResult copyWith(
          void Function(ToolPromptFormatResult) updates) =>
      super.copyWith((message) => updates(message as ToolPromptFormatResult))
          as ToolPromptFormatResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatResult create() => ToolPromptFormatResult._();
  @$core.override
  ToolPromptFormatResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolPromptFormatResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolPromptFormatResult>(create);
  static ToolPromptFormatResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get formattedPrompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set formattedPrompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFormattedPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormattedPrompt() => $_clearField(1);

  @$pb.TagNumber(2)
  ToolCallFormatName get format => $_getN(1);
  @$pb.TagNumber(2)
  set format(ToolCallFormatName value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasFormat() => $_has(1);
  @$pb.TagNumber(2)
  void clearFormat() => $_clearField(2);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(4)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(4)
  void clearErrorMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(3);
  @$pb.TagNumber(5)
  set errorCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(3);
  @$pb.TagNumber(5)
  void clearErrorCode() => $_clearField(5);
}

class ToolCallValidationRequest extends $pb.GeneratedMessage {
  factory ToolCallValidationRequest({
    ToolCall? toolCall,
    ToolCallingOptions? options,
  }) {
    final result = create();
    if (toolCall != null) result.toolCall = toolCall;
    if (options != null) result.options = options;
    return result;
  }

  ToolCallValidationRequest._();

  factory ToolCallValidationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallValidationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallValidationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<ToolCall>(1, _omitFieldNames ? '' : 'toolCall',
        subBuilder: ToolCall.create)
    ..aOM<ToolCallingOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: ToolCallingOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallValidationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallValidationRequest copyWith(
          void Function(ToolCallValidationRequest) updates) =>
      super.copyWith((message) => updates(message as ToolCallValidationRequest))
          as ToolCallValidationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallValidationRequest create() => ToolCallValidationRequest._();
  @$core.override
  ToolCallValidationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallValidationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallValidationRequest>(create);
  static ToolCallValidationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ToolCall get toolCall => $_getN(0);
  @$pb.TagNumber(1)
  set toolCall(ToolCall value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasToolCall() => $_has(0);
  @$pb.TagNumber(1)
  void clearToolCall() => $_clearField(1);
  @$pb.TagNumber(1)
  ToolCall ensureToolCall() => $_ensure(0);

  /// Validation uses options.tools as the registry snapshot and honors
  /// portable flags such as require_json_arguments and forced_tool_name.
  @$pb.TagNumber(2)
  ToolCallingOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(ToolCallingOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
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
    final result = create();
    if (isValid != null) result.isValid = isValid;
    if (validationErrors != null)
      result.validationErrors.addAll(validationErrors);
    if (matchedTool != null) result.matchedTool = matchedTool;
    if (normalizedArgumentsJson != null)
      result.normalizedArgumentsJson = normalizedArgumentsJson;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  ToolCallValidationResult._();

  factory ToolCallValidationResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallValidationResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallValidationResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isValid')
    ..pPS(2, _omitFieldNames ? '' : 'validationErrors')
    ..aOM<ToolDefinition>(3, _omitFieldNames ? '' : 'matchedTool',
        subBuilder: ToolDefinition.create)
    ..aOS(4, _omitFieldNames ? '' : 'normalizedArgumentsJson')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aI(6, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallValidationResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallValidationResult copyWith(
          void Function(ToolCallValidationResult) updates) =>
      super.copyWith((message) => updates(message as ToolCallValidationResult))
          as ToolCallValidationResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallValidationResult create() => ToolCallValidationResult._();
  @$core.override
  ToolCallValidationResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallValidationResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallValidationResult>(create);
  static ToolCallValidationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isValid => $_getBF(0);
  @$pb.TagNumber(1)
  set isValid($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsValid() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsValid() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get validationErrors => $_getList(1);

  @$pb.TagNumber(3)
  ToolDefinition get matchedTool => $_getN(2);
  @$pb.TagNumber(3)
  set matchedTool(ToolDefinition value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasMatchedTool() => $_has(2);
  @$pb.TagNumber(3)
  void clearMatchedTool() => $_clearField(3);
  @$pb.TagNumber(3)
  ToolDefinition ensureMatchedTool() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get normalizedArgumentsJson => $_getSZ(3);
  @$pb.TagNumber(4)
  set normalizedArgumentsJson($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNormalizedArgumentsJson() => $_has(3);
  @$pb.TagNumber(4)
  void clearNormalizedArgumentsJson() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get errorCode => $_getIZ(5);
  @$pb.TagNumber(6)
  set errorCode($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorCode() => $_clearField(6);
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
    final result$ = create();
    if (seq != null) result$.seq = seq;
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (conversationId != null) result$.conversationId = conversationId;
    if (kind != null) result$.kind = kind;
    if (token != null) result$.token = token;
    if (toolCall != null) result$.toolCall = toolCall;
    if (toolResult != null) result$.toolResult = toolResult;
    if (result != null) result$.result = result;
    if (errorMessage != null) result$.errorMessage = errorMessage;
    if (errorCode != null) result$.errorCode = errorCode;
    return result$;
  }

  ToolCallingStreamEvent._();

  factory ToolCallingStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'conversationId')
    ..aE<ToolCallingStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: ToolCallingStreamEventKind.values)
    ..aOS(5, _omitFieldNames ? '' : 'token')
    ..aOM<ToolCall>(6, _omitFieldNames ? '' : 'toolCall',
        subBuilder: ToolCall.create)
    ..aOM<ToolResult>(7, _omitFieldNames ? '' : 'toolResult',
        subBuilder: ToolResult.create)
    ..aOM<ToolCallingResult>(8, _omitFieldNames ? '' : 'result',
        subBuilder: ToolCallingResult.create)
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..aI(10, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingStreamEvent copyWith(
          void Function(ToolCallingStreamEvent) updates) =>
      super.copyWith((message) => updates(message as ToolCallingStreamEvent))
          as ToolCallingStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingStreamEvent create() => ToolCallingStreamEvent._();
  @$core.override
  ToolCallingStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallingStreamEvent>(create);
  static ToolCallingStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get conversationId => $_getSZ(2);
  @$pb.TagNumber(3)
  set conversationId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConversationId() => $_has(2);
  @$pb.TagNumber(3)
  void clearConversationId() => $_clearField(3);

  @$pb.TagNumber(4)
  ToolCallingStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(ToolCallingStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get token => $_getSZ(4);
  @$pb.TagNumber(5)
  set token($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasToken() => $_has(4);
  @$pb.TagNumber(5)
  void clearToken() => $_clearField(5);

  @$pb.TagNumber(6)
  ToolCall get toolCall => $_getN(5);
  @$pb.TagNumber(6)
  set toolCall(ToolCall value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasToolCall() => $_has(5);
  @$pb.TagNumber(6)
  void clearToolCall() => $_clearField(6);
  @$pb.TagNumber(6)
  ToolCall ensureToolCall() => $_ensure(5);

  @$pb.TagNumber(7)
  ToolResult get toolResult => $_getN(6);
  @$pb.TagNumber(7)
  set toolResult(ToolResult value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasToolResult() => $_has(6);
  @$pb.TagNumber(7)
  void clearToolResult() => $_clearField(7);
  @$pb.TagNumber(7)
  ToolResult ensureToolResult() => $_ensure(6);

  @$pb.TagNumber(8)
  ToolCallingResult get result => $_getN(7);
  @$pb.TagNumber(8)
  set result(ToolCallingResult value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasResult() => $_has(7);
  @$pb.TagNumber(8)
  void clearResult() => $_clearField(8);
  @$pb.TagNumber(8)
  ToolCallingResult ensureResult() => $_ensure(7);

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get errorCode => $_getIZ(9);
  @$pb.TagNumber(10)
  set errorCode($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasErrorCode() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorCode() => $_clearField(10);
}

class ToolRegistrySnapshot extends $pb.GeneratedMessage {
  factory ToolRegistrySnapshot({
    $core.Iterable<ToolDefinition>? tools,
    $fixnum.Int64? updatedAtMs,
  }) {
    final result = create();
    if (tools != null) result.tools.addAll(tools);
    if (updatedAtMs != null) result.updatedAtMs = updatedAtMs;
    return result;
  }

  ToolRegistrySnapshot._();

  factory ToolRegistrySnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolRegistrySnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolRegistrySnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<ToolDefinition>(1, _omitFieldNames ? '' : 'tools',
        subBuilder: ToolDefinition.create)
    ..aInt64(2, _omitFieldNames ? '' : 'updatedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolRegistrySnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolRegistrySnapshot copyWith(void Function(ToolRegistrySnapshot) updates) =>
      super.copyWith((message) => updates(message as ToolRegistrySnapshot))
          as ToolRegistrySnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolRegistrySnapshot create() => ToolRegistrySnapshot._();
  @$core.override
  ToolRegistrySnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolRegistrySnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolRegistrySnapshot>(create);
  static ToolRegistrySnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ToolDefinition> get tools => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get updatedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set updatedAtMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUpdatedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearUpdatedAtMs() => $_clearField(2);
}

class ToolCallingSessionCreateRequest extends $pb.GeneratedMessage {
  factory ToolCallingSessionCreateRequest({
    $core.String? prompt,
    $core.Iterable<ToolDefinition>? tools,
    ToolCallFormatName? format,
    $core.int? maxToolCalls,
    $core.bool? keepToolsAvailable,
    $core.bool? validateCalls,
    ToolChoiceMode? toolChoice,
    $core.String? forcedToolName,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.String? systemPrompt,
    $core.bool? disableThinking,
    $core.bool? autoExecute,
    $core.bool? replaceSystemPrompt,
    $core.bool? requireJsonArguments,
    $core.Iterable<$core.String>? history,
  }) {
    final result = create();
    if (prompt != null) result.prompt = prompt;
    if (tools != null) result.tools.addAll(tools);
    if (format != null) result.format = format;
    if (maxToolCalls != null) result.maxToolCalls = maxToolCalls;
    if (keepToolsAvailable != null)
      result.keepToolsAvailable = keepToolsAvailable;
    if (validateCalls != null) result.validateCalls = validateCalls;
    if (toolChoice != null) result.toolChoice = toolChoice;
    if (forcedToolName != null) result.forcedToolName = forcedToolName;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (temperature != null) result.temperature = temperature;
    if (topP != null) result.topP = topP;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (disableThinking != null) result.disableThinking = disableThinking;
    if (autoExecute != null) result.autoExecute = autoExecute;
    if (replaceSystemPrompt != null)
      result.replaceSystemPrompt = replaceSystemPrompt;
    if (requireJsonArguments != null)
      result.requireJsonArguments = requireJsonArguments;
    if (history != null) result.history.addAll(history);
    return result;
  }

  ToolCallingSessionCreateRequest._();

  factory ToolCallingSessionCreateRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingSessionCreateRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingSessionCreateRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..pPM<ToolDefinition>(2, _omitFieldNames ? '' : 'tools',
        subBuilder: ToolDefinition.create)
    ..aE<ToolCallFormatName>(3, _omitFieldNames ? '' : 'format',
        enumValues: ToolCallFormatName.values)
    ..aI(4, _omitFieldNames ? '' : 'maxToolCalls',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(5, _omitFieldNames ? '' : 'keepToolsAvailable')
    ..aOB(6, _omitFieldNames ? '' : 'validateCalls')
    ..aE<ToolChoiceMode>(7, _omitFieldNames ? '' : 'toolChoice',
        enumValues: ToolChoiceMode.values)
    ..aOS(8, _omitFieldNames ? '' : 'forcedToolName')
    ..aI(11, _omitFieldNames ? '' : 'maxTokens')
    ..aD(12, _omitFieldNames ? '' : 'temperature',
        fieldType: $pb.PbFieldType.OF)
    ..aD(13, _omitFieldNames ? '' : 'topP', fieldType: $pb.PbFieldType.OF)
    ..aOS(14, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(15, _omitFieldNames ? '' : 'disableThinking')
    ..aOB(16, _omitFieldNames ? '' : 'autoExecute')
    ..aOB(17, _omitFieldNames ? '' : 'replaceSystemPrompt')
    ..aOB(18, _omitFieldNames ? '' : 'requireJsonArguments')
    ..pPS(19, _omitFieldNames ? '' : 'history')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionCreateRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionCreateRequest copyWith(
          void Function(ToolCallingSessionCreateRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ToolCallingSessionCreateRequest))
          as ToolCallingSessionCreateRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateRequest create() =>
      ToolCallingSessionCreateRequest._();
  @$core.override
  ToolCallingSessionCreateRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionCreateRequest>(
          create);
  static ToolCallingSessionCreateRequest? _defaultInstance;

  /// Prompt + LLM generation options inline (avoids cross-proto import cycle).
  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ToolDefinition> get tools => $_getList(1);

  @$pb.TagNumber(3)
  ToolCallFormatName get format => $_getN(2);
  @$pb.TagNumber(3)
  set format(ToolCallFormatName value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFormat() => $_has(2);
  @$pb.TagNumber(3)
  void clearFormat() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxToolCalls => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxToolCalls($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxToolCalls() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxToolCalls() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get keepToolsAvailable => $_getBF(4);
  @$pb.TagNumber(5)
  set keepToolsAvailable($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasKeepToolsAvailable() => $_has(4);
  @$pb.TagNumber(5)
  void clearKeepToolsAvailable() => $_clearField(5);

  /// proto3 `optional` enables presence detection (has_validate_calls()).
  /// When unset, commons defaults to validate_calls=true so unknown tool
  /// calls short-circuit before host execution.
  /// Callers that delegate validation/authorization to their executor or
  /// use dynamic tool registries must explicitly set validate_calls=false.
  @$pb.TagNumber(6)
  $core.bool get validateCalls => $_getBF(5);
  @$pb.TagNumber(6)
  set validateCalls($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasValidateCalls() => $_has(5);
  @$pb.TagNumber(6)
  void clearValidateCalls() => $_clearField(6);

  /// OpenAI-style tool_choice override surfaced through the high-level
  /// run-loop / session APIs. The same fields exist on ToolCallingOptions
  /// (fields 13/14); we re-publish them here so the canonical request
  /// envelope can carry the policy without forcing callers to pass an
  /// inline ToolCallingOptions. commons honors these on every
  /// format/validate primitive via build_options_snapshot.
  @$pb.TagNumber(7)
  ToolChoiceMode get toolChoice => $_getN(6);
  @$pb.TagNumber(7)
  set toolChoice(ToolChoiceMode value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasToolChoice() => $_has(6);
  @$pb.TagNumber(7)
  void clearToolChoice() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get forcedToolName => $_getSZ(7);
  @$pb.TagNumber(8)
  set forcedToolName($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasForcedToolName() => $_has(7);
  @$pb.TagNumber(8)
  void clearForcedToolName() => $_clearField(8);

  @$pb.TagNumber(11)
  $core.int get maxTokens => $_getIZ(8);
  @$pb.TagNumber(11)
  set maxTokens($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(11)
  $core.bool hasMaxTokens() => $_has(8);
  @$pb.TagNumber(11)
  void clearMaxTokens() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.double get temperature => $_getN(9);
  @$pb.TagNumber(12)
  set temperature($core.double value) => $_setFloat(9, value);
  @$pb.TagNumber(12)
  $core.bool hasTemperature() => $_has(9);
  @$pb.TagNumber(12)
  void clearTemperature() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.double get topP => $_getN(10);
  @$pb.TagNumber(13)
  set topP($core.double value) => $_setFloat(10, value);
  @$pb.TagNumber(13)
  $core.bool hasTopP() => $_has(10);
  @$pb.TagNumber(13)
  void clearTopP() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get systemPrompt => $_getSZ(11);
  @$pb.TagNumber(14)
  set systemPrompt($core.String value) => $_setString(11, value);
  @$pb.TagNumber(14)
  $core.bool hasSystemPrompt() => $_has(11);
  @$pb.TagNumber(14)
  void clearSystemPrompt() => $_clearField(14);

  /// When true, suppress the model's thinking phase for every generate in
  /// the loop/session (maps from ToolCallingOptions.disable_thinking; same
  /// contract as LLMGenerationOptions.disable_thinking). Default false.
  @$pb.TagNumber(15)
  $core.bool get disableThinking => $_getBF(12);
  @$pb.TagNumber(15)
  set disableThinking($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(15)
  $core.bool hasDisableThinking() => $_has(12);
  @$pb.TagNumber(15)
  void clearDisableThinking() => $_clearField(15);

  /// Default true when absent. False returns the parsed ToolCall without
  /// invoking the host executor.
  @$pb.TagNumber(16)
  $core.bool get autoExecute => $_getBF(13);
  @$pb.TagNumber(16)
  set autoExecute($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(16)
  $core.bool hasAutoExecute() => $_has(13);
  @$pb.TagNumber(16)
  void clearAutoExecute() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.bool get replaceSystemPrompt => $_getBF(14);
  @$pb.TagNumber(17)
  set replaceSystemPrompt($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(17)
  $core.bool hasReplaceSystemPrompt() => $_has(14);
  @$pb.TagNumber(17)
  void clearReplaceSystemPrompt() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.bool get requireJsonArguments => $_getBF(15);
  @$pb.TagNumber(18)
  set requireJsonArguments($core.bool value) => $_setBool(15, value);
  @$pb.TagNumber(18)
  $core.bool hasRequireJsonArguments() => $_has(15);
  @$pb.TagNumber(18)
  void clearRequireJsonArguments() => $_clearField(18);

  /// Prior conversation turns as a flat alternating list [user0, asst0, user1, asst1, ...],
  /// EXCLUDING the current turn (which is `prompt`). commons threads these into every generate
  /// in the loop so multi-turn tool use keeps context. Same contract as the standard path's
  /// ChatMessage history (llm_service.proto history=27), inlined as strings to avoid a
  /// cross-proto import cycle.
  @$pb.TagNumber(19)
  $pb.PbList<$core.String> get history => $_getList(16);
}

class ToolCallingSessionCreateResult extends $pb.GeneratedMessage {
  factory ToolCallingSessionCreateResult({
    $fixnum.Int64? sessionHandle,
  }) {
    final result = create();
    if (sessionHandle != null) result.sessionHandle = sessionHandle;
    return result;
  }

  ToolCallingSessionCreateResult._();

  factory ToolCallingSessionCreateResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingSessionCreateResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingSessionCreateResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sessionHandle', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionCreateResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionCreateResult copyWith(
          void Function(ToolCallingSessionCreateResult) updates) =>
      super.copyWith(
              (message) => updates(message as ToolCallingSessionCreateResult))
          as ToolCallingSessionCreateResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateResult create() =>
      ToolCallingSessionCreateResult._();
  @$core.override
  ToolCallingSessionCreateResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionCreateResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionCreateResult>(create);
  static ToolCallingSessionCreateResult? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sessionHandle => $_getI64(0);
  @$pb.TagNumber(1)
  set sessionHandle($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionHandle() => $_clearField(1);
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
    final result = create();
    if (llmStreamEventBytes != null)
      result.llmStreamEventBytes = llmStreamEventBytes;
    if (toolCall != null) result.toolCall = toolCall;
    if (finalResult != null) result.finalResult = finalResult;
    if (errorBytes != null) result.errorBytes = errorBytes;
    if (seq != null) result.seq = seq;
    return result;
  }

  ToolCallingSessionEvent._();

  factory ToolCallingSessionEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingSessionEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ToolCallingSessionEvent_Kind>
      _ToolCallingSessionEvent_KindByTag = {
    1: ToolCallingSessionEvent_Kind.llmStreamEventBytes,
    2: ToolCallingSessionEvent_Kind.toolCall,
    3: ToolCallingSessionEvent_Kind.finalResult,
    4: ToolCallingSessionEvent_Kind.errorBytes,
    0: ToolCallingSessionEvent_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingSessionEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'llmStreamEventBytes', $pb.PbFieldType.OY)
    ..aOM<ToolCall>(2, _omitFieldNames ? '' : 'toolCall',
        subBuilder: ToolCall.create)
    ..aOM<ToolCallingResult>(3, _omitFieldNames ? '' : 'finalResult',
        subBuilder: ToolCallingResult.create)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'errorBytes', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionEvent copyWith(
          void Function(ToolCallingSessionEvent) updates) =>
      super.copyWith((message) => updates(message as ToolCallingSessionEvent))
          as ToolCallingSessionEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionEvent create() => ToolCallingSessionEvent._();
  @$core.override
  ToolCallingSessionEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionEvent>(create);
  static ToolCallingSessionEvent? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  ToolCallingSessionEvent_Kind whichKind() =>
      _ToolCallingSessionEvent_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearKind() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.List<$core.int> get llmStreamEventBytes => $_getN(0);
  @$pb.TagNumber(1)
  set llmStreamEventBytes($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLlmStreamEventBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmStreamEventBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  ToolCall get toolCall => $_getN(1);
  @$pb.TagNumber(2)
  set toolCall(ToolCall value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasToolCall() => $_has(1);
  @$pb.TagNumber(2)
  void clearToolCall() => $_clearField(2);
  @$pb.TagNumber(2)
  ToolCall ensureToolCall() => $_ensure(1);

  @$pb.TagNumber(3)
  ToolCallingResult get finalResult => $_getN(2);
  @$pb.TagNumber(3)
  set finalResult(ToolCallingResult value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFinalResult() => $_has(2);
  @$pb.TagNumber(3)
  void clearFinalResult() => $_clearField(3);
  @$pb.TagNumber(3)
  ToolCallingResult ensureFinalResult() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get errorBytes => $_getN(3);
  @$pb.TagNumber(4)
  set errorBytes($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get seq => $_getI64(4);
  @$pb.TagNumber(5)
  set seq($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSeq() => $_has(4);
  @$pb.TagNumber(5)
  void clearSeq() => $_clearField(5);
}

class ToolCallingSessionStepWithResultRequest extends $pb.GeneratedMessage {
  factory ToolCallingSessionStepWithResultRequest({
    $fixnum.Int64? sessionHandle,
    $core.String? toolCallId,
    $core.String? resultJson,
    $core.String? error,
  }) {
    final result = create();
    if (sessionHandle != null) result.sessionHandle = sessionHandle;
    if (toolCallId != null) result.toolCallId = toolCallId;
    if (resultJson != null) result.resultJson = resultJson;
    if (error != null) result.error = error;
    return result;
  }

  ToolCallingSessionStepWithResultRequest._();

  factory ToolCallingSessionStepWithResultRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingSessionStepWithResultRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingSessionStepWithResultRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sessionHandle', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'toolCallId')
    ..aOS(3, _omitFieldNames ? '' : 'resultJson')
    ..aOS(4, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionStepWithResultRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionStepWithResultRequest copyWith(
          void Function(ToolCallingSessionStepWithResultRequest) updates) =>
      super.copyWith((message) =>
              updates(message as ToolCallingSessionStepWithResultRequest))
          as ToolCallingSessionStepWithResultRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionStepWithResultRequest create() =>
      ToolCallingSessionStepWithResultRequest._();
  @$core.override
  ToolCallingSessionStepWithResultRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionStepWithResultRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ToolCallingSessionStepWithResultRequest>(create);
  static ToolCallingSessionStepWithResultRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sessionHandle => $_getI64(0);
  @$pb.TagNumber(1)
  set sessionHandle($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionHandle() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get toolCallId => $_getSZ(1);
  @$pb.TagNumber(2)
  set toolCallId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasToolCallId() => $_has(1);
  @$pb.TagNumber(2)
  void clearToolCallId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get resultJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set resultJson($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResultJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearResultJson() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get error => $_getSZ(3);
  @$pb.TagNumber(4)
  set error($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
}

class ToolCallingSessionDestroyRequest extends $pb.GeneratedMessage {
  factory ToolCallingSessionDestroyRequest({
    $fixnum.Int64? sessionHandle,
  }) {
    final result = create();
    if (sessionHandle != null) result.sessionHandle = sessionHandle;
    return result;
  }

  ToolCallingSessionDestroyRequest._();

  factory ToolCallingSessionDestroyRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolCallingSessionDestroyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolCallingSessionDestroyRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sessionHandle', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionDestroyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolCallingSessionDestroyRequest copyWith(
          void Function(ToolCallingSessionDestroyRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ToolCallingSessionDestroyRequest))
          as ToolCallingSessionDestroyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionDestroyRequest create() =>
      ToolCallingSessionDestroyRequest._();
  @$core.override
  ToolCallingSessionDestroyRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolCallingSessionDestroyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolCallingSessionDestroyRequest>(
          create);
  static ToolCallingSessionDestroyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sessionHandle => $_getI64(0);
  @$pb.TagNumber(1)
  set sessionHandle($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionHandle() => $_clearField(1);
}

/// Logical tool-calling service contract. Host tool registration, permission
/// checks, execution, callbacks, browser/native APIs, and side effects remain
/// adapter-owned; this service describes only portable parsing, prompt
/// formatting, and validation semantics over generated messages.
class ToolCallingApi {
  final $pb.RpcClient _client;

  ToolCallingApi(this._client);

  $async.Future<ToolParseResult> parse(
          $pb.ClientContext? ctx, ToolParseRequest request) =>
      _client.invoke<ToolParseResult>(
          ctx, 'ToolCalling', 'Parse', request, ToolParseResult());
  $async.Future<ToolPromptFormatResult> formatPrompt(
          $pb.ClientContext? ctx, ToolPromptFormatRequest request) =>
      _client.invoke<ToolPromptFormatResult>(ctx, 'ToolCalling', 'FormatPrompt',
          request, ToolPromptFormatResult());
  $async.Future<ToolCallValidationResult> validateCall(
          $pb.ClientContext? ctx, ToolCallValidationRequest request) =>
      _client.invoke<ToolCallValidationResult>(ctx, 'ToolCalling',
          'ValidateCall', request, ToolCallValidationResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
