//
//  Generated code. Do not modify.
//  source: structured_output.proto
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

import 'structured_output.pbenum.dart';

export 'structured_output.pbenum.dart';

///  ---------------------------------------------------------------------------
///  JSON Schema property — describes a single property within a schema.
///  Sources pre-IDL:
///    RN  StructuredOutputTypes.ts:24     JSONSchemaProperty (type, description,
///                                        enum, format, items, properties, …)
///
///  proto3 does not allow direct self-referential message fields without
///  `optional` / explicit handle. Recursion is expressed via:
///    - `items_schema`     — for array element types       (handle to JSONSchema)
///    - `object_schema`    — for nested object types       (handle to JSONSchema)
///  Deeper recursion (a property whose items are themselves objects with
///  further nested properties) is represented by repeating the same indirection
///  inside the referenced JSONSchema. Very deep schemas are uncommon and
///  supported by chaining these handles.
///  ---------------------------------------------------------------------------
class JSONSchemaProperty extends $pb.GeneratedMessage {
  factory JSONSchemaProperty({
    JSONSchemaType? type,
    $core.String? description,
    $core.Iterable<$core.String>? enumValues,
    $core.String? format,
    JSONSchema? itemsSchema,
    JSONSchema? objectSchema,
    $core.double? minimum,
    $core.double? maximum,
    $core.int? minLength,
    $core.int? maxLength,
    $core.String? pattern,
    $core.int? minItems,
    $core.int? maxItems,
    $core.String? defaultJson,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (description != null) {
      $result.description = description;
    }
    if (enumValues != null) {
      $result.enumValues.addAll(enumValues);
    }
    if (format != null) {
      $result.format = format;
    }
    if (itemsSchema != null) {
      $result.itemsSchema = itemsSchema;
    }
    if (objectSchema != null) {
      $result.objectSchema = objectSchema;
    }
    if (minimum != null) {
      $result.minimum = minimum;
    }
    if (maximum != null) {
      $result.maximum = maximum;
    }
    if (minLength != null) {
      $result.minLength = minLength;
    }
    if (maxLength != null) {
      $result.maxLength = maxLength;
    }
    if (pattern != null) {
      $result.pattern = pattern;
    }
    if (minItems != null) {
      $result.minItems = minItems;
    }
    if (maxItems != null) {
      $result.maxItems = maxItems;
    }
    if (defaultJson != null) {
      $result.defaultJson = defaultJson;
    }
    return $result;
  }
  JSONSchemaProperty._() : super();
  factory JSONSchemaProperty.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JSONSchemaProperty.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'JSONSchemaProperty', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<JSONSchemaType>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: JSONSchemaType.JSON_SCHEMA_TYPE_UNSPECIFIED, valueOf: JSONSchemaType.valueOf, enumValues: JSONSchemaType.values)
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..pPS(3, _omitFieldNames ? '' : 'enumValues')
    ..aOS(4, _omitFieldNames ? '' : 'format')
    ..aOM<JSONSchema>(5, _omitFieldNames ? '' : 'itemsSchema', subBuilder: JSONSchema.create)
    ..aOM<JSONSchema>(6, _omitFieldNames ? '' : 'objectSchema', subBuilder: JSONSchema.create)
    ..a<$core.double>(7, _omitFieldNames ? '' : 'minimum', $pb.PbFieldType.OD)
    ..a<$core.double>(8, _omitFieldNames ? '' : 'maximum', $pb.PbFieldType.OD)
    ..a<$core.int>(9, _omitFieldNames ? '' : 'minLength', $pb.PbFieldType.O3)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'maxLength', $pb.PbFieldType.O3)
    ..aOS(11, _omitFieldNames ? '' : 'pattern')
    ..a<$core.int>(12, _omitFieldNames ? '' : 'minItems', $pb.PbFieldType.O3)
    ..a<$core.int>(13, _omitFieldNames ? '' : 'maxItems', $pb.PbFieldType.O3)
    ..aOS(14, _omitFieldNames ? '' : 'defaultJson')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JSONSchemaProperty clone() => JSONSchemaProperty()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JSONSchemaProperty copyWith(void Function(JSONSchemaProperty) updates) => super.copyWith((message) => updates(message as JSONSchemaProperty)) as JSONSchemaProperty;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JSONSchemaProperty create() => JSONSchemaProperty._();
  JSONSchemaProperty createEmptyInstance() => create();
  static $pb.PbList<JSONSchemaProperty> createRepeated() => $pb.PbList<JSONSchemaProperty>();
  @$core.pragma('dart2js:noInline')
  static JSONSchemaProperty getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JSONSchemaProperty>(create);
  static JSONSchemaProperty? _defaultInstance;

  /// Primitive / composite type for this property.
  @$pb.TagNumber(1)
  JSONSchemaType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(JSONSchemaType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  /// Human-readable description (`description` in JSON Schema).
  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => clearField(2);

  /// Allowed enum values (`enum` in JSON Schema). Strings only; numeric and
  /// boolean enums are rare and serialized as strings here.
  @$pb.TagNumber(3)
  $core.List<$core.String> get enumValues => $_getList(2);

  /// String format hint (`format` in JSON Schema): "email", "uri",
  /// "date-time", etc.
  @$pb.TagNumber(4)
  $core.String get format => $_getSZ(3);
  @$pb.TagNumber(4)
  set format($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearFormat() => clearField(4);

  /// Element schema when `type == JSON_SCHEMA_TYPE_ARRAY`.
  @$pb.TagNumber(5)
  JSONSchema get itemsSchema => $_getN(4);
  @$pb.TagNumber(5)
  set itemsSchema(JSONSchema v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasItemsSchema() => $_has(4);
  @$pb.TagNumber(5)
  void clearItemsSchema() => clearField(5);
  @$pb.TagNumber(5)
  JSONSchema ensureItemsSchema() => $_ensure(4);

  /// Nested object schema when `type == JSON_SCHEMA_TYPE_OBJECT`.
  @$pb.TagNumber(6)
  JSONSchema get objectSchema => $_getN(5);
  @$pb.TagNumber(6)
  set objectSchema(JSONSchema v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasObjectSchema() => $_has(5);
  @$pb.TagNumber(6)
  void clearObjectSchema() => clearField(6);
  @$pb.TagNumber(6)
  JSONSchema ensureObjectSchema() => $_ensure(5);

  /// Common validation constraints carried by RN/Web schema builders.
  @$pb.TagNumber(7)
  $core.double get minimum => $_getN(6);
  @$pb.TagNumber(7)
  set minimum($core.double v) { $_setDouble(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasMinimum() => $_has(6);
  @$pb.TagNumber(7)
  void clearMinimum() => clearField(7);

  @$pb.TagNumber(8)
  $core.double get maximum => $_getN(7);
  @$pb.TagNumber(8)
  set maximum($core.double v) { $_setDouble(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasMaximum() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaximum() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get minLength => $_getIZ(8);
  @$pb.TagNumber(9)
  set minLength($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasMinLength() => $_has(8);
  @$pb.TagNumber(9)
  void clearMinLength() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get maxLength => $_getIZ(9);
  @$pb.TagNumber(10)
  set maxLength($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasMaxLength() => $_has(9);
  @$pb.TagNumber(10)
  void clearMaxLength() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get pattern => $_getSZ(10);
  @$pb.TagNumber(11)
  set pattern($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasPattern() => $_has(10);
  @$pb.TagNumber(11)
  void clearPattern() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get minItems => $_getIZ(11);
  @$pb.TagNumber(12)
  set minItems($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasMinItems() => $_has(11);
  @$pb.TagNumber(12)
  void clearMinItems() => clearField(12);

  @$pb.TagNumber(13)
  $core.int get maxItems => $_getIZ(12);
  @$pb.TagNumber(13)
  set maxItems($core.int v) { $_setSignedInt32(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasMaxItems() => $_has(12);
  @$pb.TagNumber(13)
  void clearMaxItems() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get defaultJson => $_getSZ(13);
  @$pb.TagNumber(14)
  set defaultJson($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasDefaultJson() => $_has(13);
  @$pb.TagNumber(14)
  void clearDefaultJson() => clearField(14);
}

/// ---------------------------------------------------------------------------
/// JSON Schema definition — top-level schema for structured output.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:59     JSONSchema (extends JSONSchemaProperty
///                                       with $schema, $id, title, definitions,
///                                       $ref, allOf/anyOf/oneOf/not)
/// ---------------------------------------------------------------------------
class JSONSchema extends $pb.GeneratedMessage {
  factory JSONSchema({
    JSONSchemaType? type,
    $core.Map<$core.String, JSONSchemaProperty>? properties,
    $core.Iterable<$core.String>? required,
    JSONSchemaProperty? items,
    $core.bool? additionalProperties,
    $core.String? schemaUri,
    $core.String? idUri,
    $core.String? title,
    $core.String? description,
    $core.Map<$core.String, JSONSchema>? definitions,
    $core.String? ref,
    $core.Iterable<JSONSchema>? allOf,
    $core.Iterable<JSONSchema>? anyOf,
    $core.Iterable<JSONSchema>? oneOf,
    JSONSchema? notSchema,
    $core.String? rawJson,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (properties != null) {
      $result.properties.addAll(properties);
    }
    if (required != null) {
      $result.required.addAll(required);
    }
    if (items != null) {
      $result.items = items;
    }
    if (additionalProperties != null) {
      $result.additionalProperties = additionalProperties;
    }
    if (schemaUri != null) {
      $result.schemaUri = schemaUri;
    }
    if (idUri != null) {
      $result.idUri = idUri;
    }
    if (title != null) {
      $result.title = title;
    }
    if (description != null) {
      $result.description = description;
    }
    if (definitions != null) {
      $result.definitions.addAll(definitions);
    }
    if (ref != null) {
      $result.ref = ref;
    }
    if (allOf != null) {
      $result.allOf.addAll(allOf);
    }
    if (anyOf != null) {
      $result.anyOf.addAll(anyOf);
    }
    if (oneOf != null) {
      $result.oneOf.addAll(oneOf);
    }
    if (notSchema != null) {
      $result.notSchema = notSchema;
    }
    if (rawJson != null) {
      $result.rawJson = rawJson;
    }
    return $result;
  }
  JSONSchema._() : super();
  factory JSONSchema.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JSONSchema.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'JSONSchema', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<JSONSchemaType>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: JSONSchemaType.JSON_SCHEMA_TYPE_UNSPECIFIED, valueOf: JSONSchemaType.valueOf, enumValues: JSONSchemaType.values)
    ..m<$core.String, JSONSchemaProperty>(2, _omitFieldNames ? '' : 'properties', entryClassName: 'JSONSchema.PropertiesEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: JSONSchemaProperty.create, valueDefaultOrMaker: JSONSchemaProperty.getDefault, packageName: const $pb.PackageName('runanywhere.v1'))
    ..pPS(3, _omitFieldNames ? '' : 'required')
    ..aOM<JSONSchemaProperty>(4, _omitFieldNames ? '' : 'items', subBuilder: JSONSchemaProperty.create)
    ..aOB(5, _omitFieldNames ? '' : 'additionalProperties')
    ..aOS(6, _omitFieldNames ? '' : '\$schema', protoName: 'schema_uri')
    ..aOS(7, _omitFieldNames ? '' : '\$id', protoName: 'id_uri')
    ..aOS(8, _omitFieldNames ? '' : 'title')
    ..aOS(9, _omitFieldNames ? '' : 'description')
    ..m<$core.String, JSONSchema>(10, _omitFieldNames ? '' : 'definitions', entryClassName: 'JSONSchema.DefinitionsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: JSONSchema.create, valueDefaultOrMaker: JSONSchema.getDefault, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(11, _omitFieldNames ? '' : '\$ref', protoName: 'ref')
    ..pc<JSONSchema>(12, _omitFieldNames ? '' : 'allOf', $pb.PbFieldType.PM, subBuilder: JSONSchema.create)
    ..pc<JSONSchema>(13, _omitFieldNames ? '' : 'anyOf', $pb.PbFieldType.PM, subBuilder: JSONSchema.create)
    ..pc<JSONSchema>(14, _omitFieldNames ? '' : 'oneOf', $pb.PbFieldType.PM, subBuilder: JSONSchema.create)
    ..aOM<JSONSchema>(15, _omitFieldNames ? '' : 'notSchema', subBuilder: JSONSchema.create)
    ..aOS(16, _omitFieldNames ? '' : 'rawJson')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JSONSchema clone() => JSONSchema()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JSONSchema copyWith(void Function(JSONSchema) updates) => super.copyWith((message) => updates(message as JSONSchema)) as JSONSchema;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JSONSchema create() => JSONSchema._();
  JSONSchema createEmptyInstance() => create();
  static $pb.PbList<JSONSchema> createRepeated() => $pb.PbList<JSONSchema>();
  @$core.pragma('dart2js:noInline')
  static JSONSchema getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JSONSchema>(create);
  static JSONSchema? _defaultInstance;

  /// Root type for this schema (commonly OBJECT or ARRAY).
  @$pb.TagNumber(1)
  JSONSchemaType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(JSONSchemaType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  /// Map of property name -> property definition.
  @$pb.TagNumber(2)
  $core.Map<$core.String, JSONSchemaProperty> get properties => $_getMap(1);

  /// Names of required properties (`required` in JSON Schema).
  @$pb.TagNumber(3)
  $core.List<$core.String> get required => $_getList(2);

  /// Element schema when the root `type == JSON_SCHEMA_TYPE_ARRAY`.
  @$pb.TagNumber(4)
  JSONSchemaProperty get items => $_getN(3);
  @$pb.TagNumber(4)
  set items(JSONSchemaProperty v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasItems() => $_has(3);
  @$pb.TagNumber(4)
  void clearItems() => clearField(4);
  @$pb.TagNumber(4)
  JSONSchemaProperty ensureItems() => $_ensure(3);

  /// Whether properties not declared in `properties` are allowed.
  @$pb.TagNumber(5)
  $core.bool get additionalProperties => $_getBF(4);
  @$pb.TagNumber(5)
  set additionalProperties($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAdditionalProperties() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdditionalProperties() => clearField(5);

  /// JSON Schema document metadata / composition fields. Field names avoid
  /// `$` in generated APIs while preserving JSON names for serializers.
  @$pb.TagNumber(6)
  $core.String get schemaUri => $_getSZ(5);
  @$pb.TagNumber(6)
  set schemaUri($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSchemaUri() => $_has(5);
  @$pb.TagNumber(6)
  void clearSchemaUri() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get idUri => $_getSZ(6);
  @$pb.TagNumber(7)
  set idUri($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIdUri() => $_has(6);
  @$pb.TagNumber(7)
  void clearIdUri() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get title => $_getSZ(7);
  @$pb.TagNumber(8)
  set title($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTitle() => $_has(7);
  @$pb.TagNumber(8)
  void clearTitle() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get description => $_getSZ(8);
  @$pb.TagNumber(9)
  set description($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDescription() => $_has(8);
  @$pb.TagNumber(9)
  void clearDescription() => clearField(9);

  @$pb.TagNumber(10)
  $core.Map<$core.String, JSONSchema> get definitions => $_getMap(9);

  @$pb.TagNumber(11)
  $core.String get ref => $_getSZ(10);
  @$pb.TagNumber(11)
  set ref($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasRef() => $_has(10);
  @$pb.TagNumber(11)
  void clearRef() => clearField(11);

  @$pb.TagNumber(12)
  $core.List<JSONSchema> get allOf => $_getList(11);

  @$pb.TagNumber(13)
  $core.List<JSONSchema> get anyOf => $_getList(12);

  @$pb.TagNumber(14)
  $core.List<JSONSchema> get oneOf => $_getList(13);

  @$pb.TagNumber(15)
  JSONSchema get notSchema => $_getN(14);
  @$pb.TagNumber(15)
  set notSchema(JSONSchema v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasNotSchema() => $_has(14);
  @$pb.TagNumber(15)
  void clearNotSchema() => clearField(15);
  @$pb.TagNumber(15)
  JSONSchema ensureNotSchema() => $_ensure(14);

  @$pb.TagNumber(16)
  $core.String get rawJson => $_getSZ(15);
  @$pb.TagNumber(16)
  set rawJson($core.String v) { $_setString(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasRawJson() => $_has(15);
  @$pb.TagNumber(16)
  void clearRawJson() => clearField(16);
}

/// ---------------------------------------------------------------------------
/// Structured output options — request-side configuration for a structured
/// generation call. Wraps a JSONSchema plus generation flags.
/// Sources pre-IDL:
///   Swift  LLMTypes.swift:533           StructuredOutputConfig
///   Kotlin LLMTypes.kt:242              StructuredOutputConfig
///   Dart   structured_output_types.dart StructuredOutputConfig (incl. strict)
///   RN     StructuredOutputTypes.ts:76  StructuredOutputOptions
/// ---------------------------------------------------------------------------
class StructuredOutputOptions extends $pb.GeneratedMessage {
  factory StructuredOutputOptions({
    JSONSchema? schema,
    $core.bool? includeSchemaInPrompt,
    $core.bool? strictMode,
    $core.String? jsonSchema,
    $core.String? typeName,
    $core.String? name,
    StructuredOutputMode? mode,
    $core.String? regexPattern,
    $core.String? grammar,
    $core.bool? repairJson,
    $core.int? maxRetries,
  }) {
    final $result = create();
    if (schema != null) {
      $result.schema = schema;
    }
    if (includeSchemaInPrompt != null) {
      $result.includeSchemaInPrompt = includeSchemaInPrompt;
    }
    if (strictMode != null) {
      $result.strictMode = strictMode;
    }
    if (jsonSchema != null) {
      $result.jsonSchema = jsonSchema;
    }
    if (typeName != null) {
      $result.typeName = typeName;
    }
    if (name != null) {
      $result.name = name;
    }
    if (mode != null) {
      $result.mode = mode;
    }
    if (regexPattern != null) {
      $result.regexPattern = regexPattern;
    }
    if (grammar != null) {
      $result.grammar = grammar;
    }
    if (repairJson != null) {
      $result.repairJson = repairJson;
    }
    if (maxRetries != null) {
      $result.maxRetries = maxRetries;
    }
    return $result;
  }
  StructuredOutputOptions._() : super();
  factory StructuredOutputOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<JSONSchema>(1, _omitFieldNames ? '' : 'schema', subBuilder: JSONSchema.create)
    ..aOB(2, _omitFieldNames ? '' : 'includeSchemaInPrompt')
    ..aOB(3, _omitFieldNames ? '' : 'strictMode')
    ..aOS(4, _omitFieldNames ? '' : 'jsonSchema')
    ..aOS(5, _omitFieldNames ? '' : 'typeName')
    ..aOS(6, _omitFieldNames ? '' : 'name')
    ..e<StructuredOutputMode>(7, _omitFieldNames ? '' : 'mode', $pb.PbFieldType.OE, defaultOrMaker: StructuredOutputMode.STRUCTURED_OUTPUT_MODE_UNSPECIFIED, valueOf: StructuredOutputMode.valueOf, enumValues: StructuredOutputMode.values)
    ..aOS(8, _omitFieldNames ? '' : 'regexPattern')
    ..aOS(9, _omitFieldNames ? '' : 'grammar')
    ..aOB(10, _omitFieldNames ? '' : 'repairJson')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'maxRetries', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputOptions clone() => StructuredOutputOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputOptions copyWith(void Function(StructuredOutputOptions) updates) => super.copyWith((message) => updates(message as StructuredOutputOptions)) as StructuredOutputOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputOptions create() => StructuredOutputOptions._();
  StructuredOutputOptions createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputOptions> createRepeated() => $pb.PbList<StructuredOutputOptions>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputOptions>(create);
  static StructuredOutputOptions? _defaultInstance;

  /// Schema describing the desired output shape.
  @$pb.TagNumber(1)
  JSONSchema get schema => $_getN(0);
  @$pb.TagNumber(1)
  set schema(JSONSchema v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSchema() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchema() => clearField(1);
  @$pb.TagNumber(1)
  JSONSchema ensureSchema() => $_ensure(0);

  /// Whether to embed the schema text in the LLM prompt.
  @$pb.TagNumber(2)
  $core.bool get includeSchemaInPrompt => $_getBF(1);
  @$pb.TagNumber(2)
  set includeSchemaInPrompt($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIncludeSchemaInPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeSchemaInPrompt() => clearField(2);

  /// Strict schema adherence — rejects outputs that don't fully validate.
  @$pb.TagNumber(3)
  $core.bool get strictMode => $_getBF(2);
  @$pb.TagNumber(3)
  set strictMode($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStrictMode() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrictMode() => clearField(3);

  /// Raw JSON Schema string for C ABI and SDKs that already carry schema as
  /// serialized JSON instead of the typed JSONSchema tree.
  @$pb.TagNumber(4)
  $core.String get jsonSchema => $_getSZ(3);
  @$pb.TagNumber(4)
  set jsonSchema($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasJsonSchema() => $_has(3);
  @$pb.TagNumber(4)
  void clearJsonSchema() => clearField(4);

  /// Optional generated type/name hints used by Swift/Kotlin/Dart wrappers.
  @$pb.TagNumber(5)
  $core.String get typeName => $_getSZ(4);
  @$pb.TagNumber(5)
  set typeName($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTypeName() => $_has(4);
  @$pb.TagNumber(5)
  void clearTypeName() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get name => $_getSZ(5);
  @$pb.TagNumber(6)
  set name($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasName() => $_has(5);
  @$pb.TagNumber(6)
  void clearName() => clearField(6);

  @$pb.TagNumber(7)
  StructuredOutputMode get mode => $_getN(6);
  @$pb.TagNumber(7)
  set mode(StructuredOutputMode v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasMode() => $_has(6);
  @$pb.TagNumber(7)
  void clearMode() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get regexPattern => $_getSZ(7);
  @$pb.TagNumber(8)
  set regexPattern($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasRegexPattern() => $_has(7);
  @$pb.TagNumber(8)
  void clearRegexPattern() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get grammar => $_getSZ(8);
  @$pb.TagNumber(9)
  set grammar($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasGrammar() => $_has(8);
  @$pb.TagNumber(9)
  void clearGrammar() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get repairJson => $_getBF(9);
  @$pb.TagNumber(10)
  set repairJson($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasRepairJson() => $_has(9);
  @$pb.TagNumber(10)
  void clearRepairJson() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get maxRetries => $_getIZ(10);
  @$pb.TagNumber(11)
  set maxRetries($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasMaxRetries() => $_has(10);
  @$pb.TagNumber(11)
  void clearMaxRetries() => clearField(11);
}

/// ---------------------------------------------------------------------------
/// Structured output validation result — populated after the model returns.
/// Sources pre-IDL:
///   Swift  LLMTypes.swift:585           StructuredOutputValidation
///   Kotlin LLMTypes.kt:278              StructuredOutputValidation
///   Dart   structured_output_types.dart StructuredOutputValidation
/// ---------------------------------------------------------------------------
class StructuredOutputValidation extends $pb.GeneratedMessage {
  factory StructuredOutputValidation({
    $core.bool? isValid,
    $core.bool? containsJson,
    $core.String? errorMessage,
    $core.String? rawOutput,
    $core.String? extractedJson,
    $core.Iterable<$core.String>? validationErrors,
    $fixnum.Int64? validationTimeMs,
  }) {
    final $result = create();
    if (isValid != null) {
      $result.isValid = isValid;
    }
    if (containsJson != null) {
      $result.containsJson = containsJson;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (rawOutput != null) {
      $result.rawOutput = rawOutput;
    }
    if (extractedJson != null) {
      $result.extractedJson = extractedJson;
    }
    if (validationErrors != null) {
      $result.validationErrors.addAll(validationErrors);
    }
    if (validationTimeMs != null) {
      $result.validationTimeMs = validationTimeMs;
    }
    return $result;
  }
  StructuredOutputValidation._() : super();
  factory StructuredOutputValidation.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputValidation.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputValidation', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isValid')
    ..aOB(2, _omitFieldNames ? '' : 'containsJson')
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(4, _omitFieldNames ? '' : 'rawOutput')
    ..aOS(5, _omitFieldNames ? '' : 'extractedJson')
    ..pPS(6, _omitFieldNames ? '' : 'validationErrors')
    ..aInt64(7, _omitFieldNames ? '' : 'validationTimeMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputValidation clone() => StructuredOutputValidation()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputValidation copyWith(void Function(StructuredOutputValidation) updates) => super.copyWith((message) => updates(message as StructuredOutputValidation)) as StructuredOutputValidation;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidation create() => StructuredOutputValidation._();
  StructuredOutputValidation createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputValidation> createRepeated() => $pb.PbList<StructuredOutputValidation>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidation getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputValidation>(create);
  static StructuredOutputValidation? _defaultInstance;

  /// Whether the parsed output validates against the requested schema.
  @$pb.TagNumber(1)
  $core.bool get isValid => $_getBF(0);
  @$pb.TagNumber(1)
  set isValid($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsValid() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsValid() => clearField(1);

  /// Whether the raw text contained any parseable JSON object.
  @$pb.TagNumber(2)
  $core.bool get containsJson => $_getBF(1);
  @$pb.TagNumber(2)
  set containsJson($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasContainsJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearContainsJson() => clearField(2);

  /// Validation / parse error message when `is_valid == false`.
  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);

  /// Original raw model output (for debugging / fallback parsing).
  @$pb.TagNumber(4)
  $core.String get rawOutput => $_getSZ(3);
  @$pb.TagNumber(4)
  set rawOutput($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRawOutput() => $_has(3);
  @$pb.TagNumber(4)
  void clearRawOutput() => clearField(4);

  /// JSON substring extracted from raw_output before validation, when the
  /// extractor found one.
  @$pb.TagNumber(5)
  $core.String get extractedJson => $_getSZ(4);
  @$pb.TagNumber(5)
  set extractedJson($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasExtractedJson() => $_has(4);
  @$pb.TagNumber(5)
  void clearExtractedJson() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.String> get validationErrors => $_getList(5);

  @$pb.TagNumber(7)
  $fixnum.Int64 get validationTimeMs => $_getI64(6);
  @$pb.TagNumber(7)
  set validationTimeMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasValidationTimeMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearValidationTimeMs() => clearField(7);
}

/// ---------------------------------------------------------------------------
/// Structured output result — generic envelope returned by structured calls.
/// `parsed_json` is a UTF-8 JSON-encoded byte payload to keep the result
/// language-agnostic; SDKs deserialize into their concrete typed value.
/// Sources pre-IDL:
///   RN     StructuredOutputTypes.ts:93  StructuredOutputResult<T> (data, raw,
///                                       success, error)
///   Dart   structured_output_types.dart StructuredOutputResult<T> (result,
///                                       rawText, metrics)
/// ---------------------------------------------------------------------------
class StructuredOutputResult extends $pb.GeneratedMessage {
  factory StructuredOutputResult({
    $core.List<$core.int>? parsedJson,
    StructuredOutputValidation? validation,
    $core.String? rawText,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (parsedJson != null) {
      $result.parsedJson = parsedJson;
    }
    if (validation != null) {
      $result.validation = validation;
    }
    if (rawText != null) {
      $result.rawText = rawText;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  StructuredOutputResult._() : super();
  factory StructuredOutputResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'parsedJson', $pb.PbFieldType.OY)
    ..aOM<StructuredOutputValidation>(2, _omitFieldNames ? '' : 'validation', subBuilder: StructuredOutputValidation.create)
    ..aOS(3, _omitFieldNames ? '' : 'rawText')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputResult clone() => StructuredOutputResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputResult copyWith(void Function(StructuredOutputResult) updates) => super.copyWith((message) => updates(message as StructuredOutputResult)) as StructuredOutputResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputResult create() => StructuredOutputResult._();
  StructuredOutputResult createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputResult> createRepeated() => $pb.PbList<StructuredOutputResult>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputResult>(create);
  static StructuredOutputResult? _defaultInstance;

  /// JSON-encoded parsed value (UTF-8 bytes).
  @$pb.TagNumber(1)
  $core.List<$core.int> get parsedJson => $_getN(0);
  @$pb.TagNumber(1)
  set parsedJson($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasParsedJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearParsedJson() => clearField(1);

  /// Validation / parse outcome.
  @$pb.TagNumber(2)
  StructuredOutputValidation get validation => $_getN(1);
  @$pb.TagNumber(2)
  set validation(StructuredOutputValidation v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasValidation() => $_has(1);
  @$pb.TagNumber(2)
  void clearValidation() => clearField(2);
  @$pb.TagNumber(2)
  StructuredOutputValidation ensureValidation() => $_ensure(1);

  /// Raw model text prior to parsing (optional, useful for retries).
  @$pb.TagNumber(3)
  $core.String get rawText => $_getSZ(2);
  @$pb.TagNumber(3)
  set rawText($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRawText() => $_has(2);
  @$pb.TagNumber(3)
  void clearRawText() => clearField(3);

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

class StructuredOutputParseRequest extends $pb.GeneratedMessage {
  factory StructuredOutputParseRequest({
    $core.String? requestId,
    $core.String? text,
    StructuredOutputOptions? options,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (text != null) {
      $result.text = text;
    }
    if (options != null) {
      $result.options = options;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  StructuredOutputParseRequest._() : super();
  factory StructuredOutputParseRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputParseRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputParseRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOM<StructuredOutputOptions>(3, _omitFieldNames ? '' : 'options', subBuilder: StructuredOutputOptions.create)
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata', entryClassName: 'StructuredOutputParseRequest.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputParseRequest clone() => StructuredOutputParseRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputParseRequest copyWith(void Function(StructuredOutputParseRequest) updates) => super.copyWith((message) => updates(message as StructuredOutputParseRequest)) as StructuredOutputParseRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputParseRequest create() => StructuredOutputParseRequest._();
  StructuredOutputParseRequest createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputParseRequest> createRepeated() => $pb.PbList<StructuredOutputParseRequest>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputParseRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputParseRequest>(create);
  static StructuredOutputParseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => clearField(2);

  @$pb.TagNumber(3)
  StructuredOutputOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(StructuredOutputOptions v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => clearField(3);
  @$pb.TagNumber(3)
  StructuredOutputOptions ensureOptions() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(3);
}

class StructuredOutputValidationRequest extends $pb.GeneratedMessage {
  factory StructuredOutputValidationRequest({
    $core.String? text,
    StructuredOutputOptions? options,
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
  StructuredOutputValidationRequest._() : super();
  factory StructuredOutputValidationRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputValidationRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputValidationRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOM<StructuredOutputOptions>(2, _omitFieldNames ? '' : 'options', subBuilder: StructuredOutputOptions.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputValidationRequest clone() => StructuredOutputValidationRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputValidationRequest copyWith(void Function(StructuredOutputValidationRequest) updates) => super.copyWith((message) => updates(message as StructuredOutputValidationRequest)) as StructuredOutputValidationRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidationRequest create() => StructuredOutputValidationRequest._();
  StructuredOutputValidationRequest createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputValidationRequest> createRepeated() => $pb.PbList<StructuredOutputValidationRequest>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidationRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputValidationRequest>(create);
  static StructuredOutputValidationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  StructuredOutputOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(StructuredOutputOptions v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => clearField(2);
  @$pb.TagNumber(2)
  StructuredOutputOptions ensureOptions() => $_ensure(1);
}

class StructuredOutputPromptResult extends $pb.GeneratedMessage {
  factory StructuredOutputPromptResult({
    $core.String? preparedPrompt,
    $core.String? systemPrompt,
    $core.String? jsonSchema,
    $core.String? regexPattern,
    $core.String? grammar,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (preparedPrompt != null) {
      $result.preparedPrompt = preparedPrompt;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (jsonSchema != null) {
      $result.jsonSchema = jsonSchema;
    }
    if (regexPattern != null) {
      $result.regexPattern = regexPattern;
    }
    if (grammar != null) {
      $result.grammar = grammar;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  StructuredOutputPromptResult._() : super();
  factory StructuredOutputPromptResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputPromptResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputPromptResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'preparedPrompt')
    ..aOS(2, _omitFieldNames ? '' : 'systemPrompt')
    ..aOS(3, _omitFieldNames ? '' : 'jsonSchema')
    ..aOS(4, _omitFieldNames ? '' : 'regexPattern')
    ..aOS(5, _omitFieldNames ? '' : 'grammar')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(7, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputPromptResult clone() => StructuredOutputPromptResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputPromptResult copyWith(void Function(StructuredOutputPromptResult) updates) => super.copyWith((message) => updates(message as StructuredOutputPromptResult)) as StructuredOutputPromptResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputPromptResult create() => StructuredOutputPromptResult._();
  StructuredOutputPromptResult createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputPromptResult> createRepeated() => $pb.PbList<StructuredOutputPromptResult>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputPromptResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputPromptResult>(create);
  static StructuredOutputPromptResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get preparedPrompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set preparedPrompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPreparedPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPreparedPrompt() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get systemPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemPrompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSystemPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemPrompt() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get jsonSchema => $_getSZ(2);
  @$pb.TagNumber(3)
  set jsonSchema($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasJsonSchema() => $_has(2);
  @$pb.TagNumber(3)
  void clearJsonSchema() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get regexPattern => $_getSZ(3);
  @$pb.TagNumber(4)
  set regexPattern($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRegexPattern() => $_has(3);
  @$pb.TagNumber(4)
  void clearRegexPattern() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get grammar => $_getSZ(4);
  @$pb.TagNumber(5)
  set grammar($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasGrammar() => $_has(4);
  @$pb.TagNumber(5)
  void clearGrammar() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get errorCode => $_getIZ(6);
  @$pb.TagNumber(7)
  set errorCode($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasErrorCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorCode() => clearField(7);
}

class StructuredOutputRequest extends $pb.GeneratedMessage {
  factory StructuredOutputRequest({
    $core.String? requestId,
    $core.String? prompt,
    StructuredOutputOptions? options,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (prompt != null) {
      $result.prompt = prompt;
    }
    if (options != null) {
      $result.options = options;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  StructuredOutputRequest._() : super();
  factory StructuredOutputRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'prompt')
    ..aOM<StructuredOutputOptions>(3, _omitFieldNames ? '' : 'options', subBuilder: StructuredOutputOptions.create)
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata', entryClassName: 'StructuredOutputRequest.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputRequest clone() => StructuredOutputRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputRequest copyWith(void Function(StructuredOutputRequest) updates) => super.copyWith((message) => updates(message as StructuredOutputRequest)) as StructuredOutputRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputRequest create() => StructuredOutputRequest._();
  StructuredOutputRequest createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputRequest> createRepeated() => $pb.PbList<StructuredOutputRequest>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputRequest>(create);
  static StructuredOutputRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get prompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set prompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrompt() => clearField(2);

  @$pb.TagNumber(3)
  StructuredOutputOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(StructuredOutputOptions v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => clearField(3);
  @$pb.TagNumber(3)
  StructuredOutputOptions ensureOptions() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(3);
}

class StructuredOutputStreamEvent extends $pb.GeneratedMessage {
  factory StructuredOutputStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    StructuredOutputStreamEventKind? kind,
    $core.String? token,
    $core.String? partialJson,
    StructuredOutputValidation? validation,
    StructuredOutputResult? result,
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
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (token != null) {
      $result.token = token;
    }
    if (partialJson != null) {
      $result.partialJson = partialJson;
    }
    if (validation != null) {
      $result.validation = validation;
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
  StructuredOutputStreamEvent._() : super();
  factory StructuredOutputStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StructuredOutputStreamEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..e<StructuredOutputStreamEventKind>(4, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED, valueOf: StructuredOutputStreamEventKind.valueOf, enumValues: StructuredOutputStreamEventKind.values)
    ..aOS(5, _omitFieldNames ? '' : 'token')
    ..aOS(6, _omitFieldNames ? '' : 'partialJson')
    ..aOM<StructuredOutputValidation>(7, _omitFieldNames ? '' : 'validation', subBuilder: StructuredOutputValidation.create)
    ..aOM<StructuredOutputResult>(8, _omitFieldNames ? '' : 'result', subBuilder: StructuredOutputResult.create)
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(10, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputStreamEvent clone() => StructuredOutputStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputStreamEvent copyWith(void Function(StructuredOutputStreamEvent) updates) => super.copyWith((message) => updates(message as StructuredOutputStreamEvent)) as StructuredOutputStreamEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputStreamEvent create() => StructuredOutputStreamEvent._();
  StructuredOutputStreamEvent createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputStreamEvent> createRepeated() => $pb.PbList<StructuredOutputStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputStreamEvent>(create);
  static StructuredOutputStreamEvent? _defaultInstance;

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
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => clearField(3);

  @$pb.TagNumber(4)
  StructuredOutputStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(StructuredOutputStreamEventKind v) { setField(4, v); }
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
  $core.String get partialJson => $_getSZ(5);
  @$pb.TagNumber(6)
  set partialJson($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPartialJson() => $_has(5);
  @$pb.TagNumber(6)
  void clearPartialJson() => clearField(6);

  @$pb.TagNumber(7)
  StructuredOutputValidation get validation => $_getN(6);
  @$pb.TagNumber(7)
  set validation(StructuredOutputValidation v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasValidation() => $_has(6);
  @$pb.TagNumber(7)
  void clearValidation() => clearField(7);
  @$pb.TagNumber(7)
  StructuredOutputValidation ensureValidation() => $_ensure(6);

  @$pb.TagNumber(8)
  StructuredOutputResult get result => $_getN(7);
  @$pb.TagNumber(8)
  set result(StructuredOutputResult v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasResult() => $_has(7);
  @$pb.TagNumber(8)
  void clearResult() => clearField(8);
  @$pb.TagNumber(8)
  StructuredOutputResult ensureResult() => $_ensure(7);

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

/// ---------------------------------------------------------------------------
/// Named entity — single span identified within input text.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:143    NamedEntity (text, type, startOffset,
///                                       endOffset, confidence)
/// ---------------------------------------------------------------------------
class NamedEntity extends $pb.GeneratedMessage {
  factory NamedEntity({
    $core.String? text,
    $core.String? entityType,
    $core.int? startOffset,
    $core.int? endOffset,
    $core.double? confidence,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (entityType != null) {
      $result.entityType = entityType;
    }
    if (startOffset != null) {
      $result.startOffset = startOffset;
    }
    if (endOffset != null) {
      $result.endOffset = endOffset;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    return $result;
  }
  NamedEntity._() : super();
  factory NamedEntity.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NamedEntity.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'NamedEntity', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'entityType')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'startOffset', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'endOffset', $pb.PbFieldType.O3)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NamedEntity clone() => NamedEntity()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NamedEntity copyWith(void Function(NamedEntity) updates) => super.copyWith((message) => updates(message as NamedEntity)) as NamedEntity;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NamedEntity create() => NamedEntity._();
  NamedEntity createEmptyInstance() => create();
  static $pb.PbList<NamedEntity> createRepeated() => $pb.PbList<NamedEntity>();
  @$core.pragma('dart2js:noInline')
  static NamedEntity getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NamedEntity>(create);
  static NamedEntity? _defaultInstance;

  /// Surface form of the entity exactly as it appeared in input.
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  /// Entity class label, e.g. "PERSON", "ORG", "LOCATION".
  @$pb.TagNumber(2)
  $core.String get entityType => $_getSZ(1);
  @$pb.TagNumber(2)
  set entityType($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEntityType() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntityType() => clearField(2);

  /// UTF-16 / character start offset (inclusive) within input text.
  @$pb.TagNumber(3)
  $core.int get startOffset => $_getIZ(2);
  @$pb.TagNumber(3)
  set startOffset($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStartOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartOffset() => clearField(3);

  /// UTF-16 / character end offset (exclusive) within input text.
  @$pb.TagNumber(4)
  $core.int get endOffset => $_getIZ(3);
  @$pb.TagNumber(4)
  set endOffset($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEndOffset() => $_has(3);
  @$pb.TagNumber(4)
  void clearEndOffset() => clearField(4);

  /// Model confidence in [0.0, 1.0].
  @$pb.TagNumber(5)
  $core.double get confidence => $_getN(4);
  @$pb.TagNumber(5)
  set confidence($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasConfidence() => $_has(4);
  @$pb.TagNumber(5)
  void clearConfidence() => clearField(5);
}

/// ---------------------------------------------------------------------------
/// Entity extraction result — list of entities pulled from a document.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:110    EntityExtractionResult<T>
///                                       (entities, confidence)
/// Note: RN's per-result `confidence` is dropped in favor of per-entity
/// confidence on `NamedEntity`, which is the more granular and useful form.
/// ---------------------------------------------------------------------------
class EntityExtractionResult extends $pb.GeneratedMessage {
  factory EntityExtractionResult({
    $core.Iterable<NamedEntity>? entities,
  }) {
    final $result = create();
    if (entities != null) {
      $result.entities.addAll(entities);
    }
    return $result;
  }
  EntityExtractionResult._() : super();
  factory EntityExtractionResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EntityExtractionResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EntityExtractionResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<NamedEntity>(1, _omitFieldNames ? '' : 'entities', $pb.PbFieldType.PM, subBuilder: NamedEntity.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EntityExtractionResult clone() => EntityExtractionResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EntityExtractionResult copyWith(void Function(EntityExtractionResult) updates) => super.copyWith((message) => updates(message as EntityExtractionResult)) as EntityExtractionResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EntityExtractionResult create() => EntityExtractionResult._();
  EntityExtractionResult createEmptyInstance() => create();
  static $pb.PbList<EntityExtractionResult> createRepeated() => $pb.PbList<EntityExtractionResult>();
  @$core.pragma('dart2js:noInline')
  static EntityExtractionResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EntityExtractionResult>(create);
  static EntityExtractionResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<NamedEntity> get entities => $_getList(0);
}

/// ---------------------------------------------------------------------------
/// Classification candidate — alternative label considered.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:118    ClassificationResult.alternatives item
/// ---------------------------------------------------------------------------
class ClassificationCandidate extends $pb.GeneratedMessage {
  factory ClassificationCandidate({
    $core.String? label,
    $core.double? confidence,
  }) {
    final $result = create();
    if (label != null) {
      $result.label = label;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    return $result;
  }
  ClassificationCandidate._() : super();
  factory ClassificationCandidate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClassificationCandidate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClassificationCandidate', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'label')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClassificationCandidate clone() => ClassificationCandidate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClassificationCandidate copyWith(void Function(ClassificationCandidate) updates) => super.copyWith((message) => updates(message as ClassificationCandidate)) as ClassificationCandidate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClassificationCandidate create() => ClassificationCandidate._();
  ClassificationCandidate createEmptyInstance() => create();
  static $pb.PbList<ClassificationCandidate> createRepeated() => $pb.PbList<ClassificationCandidate>();
  @$core.pragma('dart2js:noInline')
  static ClassificationCandidate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClassificationCandidate>(create);
  static ClassificationCandidate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get label => $_getSZ(0);
  @$pb.TagNumber(1)
  set label($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLabel() => $_has(0);
  @$pb.TagNumber(1)
  void clearLabel() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);
}

/// ---------------------------------------------------------------------------
/// Classification result — top label plus optional alternatives.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:118    ClassificationResult (category,
///                                       confidence, alternatives)
/// Note: RN names the field `category`; canonicalized here to `label`, which
/// matches industry classifier APIs (HuggingFace, OpenAI, etc.).
/// ---------------------------------------------------------------------------
class ClassificationResult extends $pb.GeneratedMessage {
  factory ClassificationResult({
    $core.String? label,
    $core.double? confidence,
    $core.Iterable<ClassificationCandidate>? alternatives,
  }) {
    final $result = create();
    if (label != null) {
      $result.label = label;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (alternatives != null) {
      $result.alternatives.addAll(alternatives);
    }
    return $result;
  }
  ClassificationResult._() : super();
  factory ClassificationResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClassificationResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClassificationResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'label')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..pc<ClassificationCandidate>(3, _omitFieldNames ? '' : 'alternatives', $pb.PbFieldType.PM, subBuilder: ClassificationCandidate.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClassificationResult clone() => ClassificationResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClassificationResult copyWith(void Function(ClassificationResult) updates) => super.copyWith((message) => updates(message as ClassificationResult)) as ClassificationResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClassificationResult create() => ClassificationResult._();
  ClassificationResult createEmptyInstance() => create();
  static $pb.PbList<ClassificationResult> createRepeated() => $pb.PbList<ClassificationResult>();
  @$core.pragma('dart2js:noInline')
  static ClassificationResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClassificationResult>(create);
  static ClassificationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get label => $_getSZ(0);
  @$pb.TagNumber(1)
  set label($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLabel() => $_has(0);
  @$pb.TagNumber(1)
  void clearLabel() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<ClassificationCandidate> get alternatives => $_getList(2);
}

/// ---------------------------------------------------------------------------
/// Sentiment analysis result — overall sentiment plus per-class scores.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:130    SentimentResult (sentiment, score,
///                                       aspects)
/// ---------------------------------------------------------------------------
class SentimentResult extends $pb.GeneratedMessage {
  factory SentimentResult({
    Sentiment? sentiment,
    $core.double? confidence,
    $core.double? positiveScore,
    $core.double? negativeScore,
    $core.double? neutralScore,
  }) {
    final $result = create();
    if (sentiment != null) {
      $result.sentiment = sentiment;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (positiveScore != null) {
      $result.positiveScore = positiveScore;
    }
    if (negativeScore != null) {
      $result.negativeScore = negativeScore;
    }
    if (neutralScore != null) {
      $result.neutralScore = neutralScore;
    }
    return $result;
  }
  SentimentResult._() : super();
  factory SentimentResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SentimentResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SentimentResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<Sentiment>(1, _omitFieldNames ? '' : 'sentiment', $pb.PbFieldType.OE, defaultOrMaker: Sentiment.SENTIMENT_UNSPECIFIED, valueOf: Sentiment.valueOf, enumValues: Sentiment.values)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'positiveScore', $pb.PbFieldType.OF)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'negativeScore', $pb.PbFieldType.OF)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'neutralScore', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SentimentResult clone() => SentimentResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SentimentResult copyWith(void Function(SentimentResult) updates) => super.copyWith((message) => updates(message as SentimentResult)) as SentimentResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SentimentResult create() => SentimentResult._();
  SentimentResult createEmptyInstance() => create();
  static $pb.PbList<SentimentResult> createRepeated() => $pb.PbList<SentimentResult>();
  @$core.pragma('dart2js:noInline')
  static SentimentResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SentimentResult>(create);
  static SentimentResult? _defaultInstance;

  @$pb.TagNumber(1)
  Sentiment get sentiment => $_getN(0);
  @$pb.TagNumber(1)
  set sentiment(Sentiment v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSentiment() => $_has(0);
  @$pb.TagNumber(1)
  void clearSentiment() => clearField(1);

  /// Aggregate confidence in the chosen sentiment label, [0.0, 1.0].
  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);

  /// Per-class soft scores (optional). Absent fields are unscored.
  @$pb.TagNumber(3)
  $core.double get positiveScore => $_getN(2);
  @$pb.TagNumber(3)
  set positiveScore($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPositiveScore() => $_has(2);
  @$pb.TagNumber(3)
  void clearPositiveScore() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get negativeScore => $_getN(3);
  @$pb.TagNumber(4)
  set negativeScore($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasNegativeScore() => $_has(3);
  @$pb.TagNumber(4)
  void clearNegativeScore() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get neutralScore => $_getN(4);
  @$pb.TagNumber(5)
  set neutralScore($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasNeutralScore() => $_has(4);
  @$pb.TagNumber(5)
  void clearNeutralScore() => clearField(5);
}

/// ---------------------------------------------------------------------------
/// Named entity recognition result — alias-style wrapper carrying entities.
/// Equivalent in shape to `EntityExtractionResult`; both are kept so SDKs that
/// distinguish "extraction" (instruction-driven) from "NER" (model-native)
/// can route to the appropriate type without ambiguity.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:154    NERResult (entities)
/// ---------------------------------------------------------------------------
class NERResult extends $pb.GeneratedMessage {
  factory NERResult({
    $core.Iterable<NamedEntity>? entities,
  }) {
    final $result = create();
    if (entities != null) {
      $result.entities.addAll(entities);
    }
    return $result;
  }
  NERResult._() : super();
  factory NERResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NERResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'NERResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<NamedEntity>(1, _omitFieldNames ? '' : 'entities', $pb.PbFieldType.PM, subBuilder: NamedEntity.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NERResult clone() => NERResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NERResult copyWith(void Function(NERResult) updates) => super.copyWith((message) => updates(message as NERResult)) as NERResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NERResult create() => NERResult._();
  NERResult createEmptyInstance() => create();
  static $pb.PbList<NERResult> createRepeated() => $pb.PbList<NERResult>();
  @$core.pragma('dart2js:noInline')
  static NERResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NERResult>(create);
  static NERResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<NamedEntity> get entities => $_getList(0);
}

class StructuredOutputApi {
  $pb.RpcClient _client;
  StructuredOutputApi(this._client);

  $async.Future<StructuredOutputPromptResult> preparePrompt($pb.ClientContext? ctx, StructuredOutputRequest request) =>
    _client.invoke<StructuredOutputPromptResult>(ctx, 'StructuredOutput', 'PreparePrompt', request, StructuredOutputPromptResult())
  ;
  $async.Future<StructuredOutputValidation> validate($pb.ClientContext? ctx, StructuredOutputValidationRequest request) =>
    _client.invoke<StructuredOutputValidation>(ctx, 'StructuredOutput', 'Validate', request, StructuredOutputValidation())
  ;
  $async.Future<StructuredOutputResult> parse($pb.ClientContext? ctx, StructuredOutputParseRequest request) =>
    _client.invoke<StructuredOutputResult>(ctx, 'StructuredOutput', 'Parse', request, StructuredOutputResult())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
