///
//  Generated code. Do not modify.
//  source: structured_output.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'structured_output.pbenum.dart';

export 'structured_output.pbenum.dart';

class JSONSchemaProperty extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'JSONSchemaProperty', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<JSONSchemaType>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: JSONSchemaType.JSON_SCHEMA_TYPE_UNSPECIFIED, valueOf: JSONSchemaType.valueOf, enumValues: JSONSchemaType.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'description')
    ..pPS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'enumValues')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'format')
    ..aOM<JSONSchema>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'itemsSchema', subBuilder: JSONSchema.create)
    ..aOM<JSONSchema>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'objectSchema', subBuilder: JSONSchema.create)
    ..hasRequiredFields = false
  ;

  JSONSchemaProperty._() : super();
  factory JSONSchemaProperty({
    JSONSchemaType? type,
    $core.String? description,
    $core.Iterable<$core.String>? enumValues,
    $core.String? format,
    JSONSchema? itemsSchema,
    JSONSchema? objectSchema,
  }) {
    final _result = create();
    if (type != null) {
      _result.type = type;
    }
    if (description != null) {
      _result.description = description;
    }
    if (enumValues != null) {
      _result.enumValues.addAll(enumValues);
    }
    if (format != null) {
      _result.format = format;
    }
    if (itemsSchema != null) {
      _result.itemsSchema = itemsSchema;
    }
    if (objectSchema != null) {
      _result.objectSchema = objectSchema;
    }
    return _result;
  }
  factory JSONSchemaProperty.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JSONSchemaProperty.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JSONSchemaProperty clone() => JSONSchemaProperty()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JSONSchemaProperty copyWith(void Function(JSONSchemaProperty) updates) => super.copyWith((message) => updates(message as JSONSchemaProperty)) as JSONSchemaProperty; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static JSONSchemaProperty create() => JSONSchemaProperty._();
  JSONSchemaProperty createEmptyInstance() => create();
  static $pb.PbList<JSONSchemaProperty> createRepeated() => $pb.PbList<JSONSchemaProperty>();
  @$core.pragma('dart2js:noInline')
  static JSONSchemaProperty getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JSONSchemaProperty>(create);
  static JSONSchemaProperty? _defaultInstance;

  @$pb.TagNumber(1)
  JSONSchemaType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(JSONSchemaType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.String> get enumValues => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get format => $_getSZ(3);
  @$pb.TagNumber(4)
  set format($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearFormat() => clearField(4);

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
}

class JSONSchema extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'JSONSchema', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<JSONSchemaType>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: JSONSchemaType.JSON_SCHEMA_TYPE_UNSPECIFIED, valueOf: JSONSchemaType.valueOf, enumValues: JSONSchemaType.values)
    ..m<$core.String, JSONSchemaProperty>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'properties', entryClassName: 'JSONSchema.PropertiesEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OM, valueCreator: JSONSchemaProperty.create, packageName: const $pb.PackageName('runanywhere.v1'))
    ..pPS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'required')
    ..aOM<JSONSchemaProperty>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'items', subBuilder: JSONSchemaProperty.create)
    ..aOB(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'additionalProperties')
    ..hasRequiredFields = false
  ;

  JSONSchema._() : super();
  factory JSONSchema({
    JSONSchemaType? type,
    $core.Map<$core.String, JSONSchemaProperty>? properties,
    $core.Iterable<$core.String>? required,
    JSONSchemaProperty? items,
    $core.bool? additionalProperties,
  }) {
    final _result = create();
    if (type != null) {
      _result.type = type;
    }
    if (properties != null) {
      _result.properties.addAll(properties);
    }
    if (required != null) {
      _result.required.addAll(required);
    }
    if (items != null) {
      _result.items = items;
    }
    if (additionalProperties != null) {
      _result.additionalProperties = additionalProperties;
    }
    return _result;
  }
  factory JSONSchema.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JSONSchema.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JSONSchema clone() => JSONSchema()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JSONSchema copyWith(void Function(JSONSchema) updates) => super.copyWith((message) => updates(message as JSONSchema)) as JSONSchema; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static JSONSchema create() => JSONSchema._();
  JSONSchema createEmptyInstance() => create();
  static $pb.PbList<JSONSchema> createRepeated() => $pb.PbList<JSONSchema>();
  @$core.pragma('dart2js:noInline')
  static JSONSchema getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JSONSchema>(create);
  static JSONSchema? _defaultInstance;

  @$pb.TagNumber(1)
  JSONSchemaType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(JSONSchemaType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  @$pb.TagNumber(2)
  $core.Map<$core.String, JSONSchemaProperty> get properties => $_getMap(1);

  @$pb.TagNumber(3)
  $core.List<$core.String> get required => $_getList(2);

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

  @$pb.TagNumber(5)
  $core.bool get additionalProperties => $_getBF(4);
  @$pb.TagNumber(5)
  set additionalProperties($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAdditionalProperties() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdditionalProperties() => clearField(5);
}

class StructuredOutputOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StructuredOutputOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<JSONSchema>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'schema', subBuilder: JSONSchema.create)
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'includeSchemaInPrompt')
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'strictMode')
    ..hasRequiredFields = false
  ;

  StructuredOutputOptions._() : super();
  factory StructuredOutputOptions({
    JSONSchema? schema,
    $core.bool? includeSchemaInPrompt,
    $core.bool? strictMode,
  }) {
    final _result = create();
    if (schema != null) {
      _result.schema = schema;
    }
    if (includeSchemaInPrompt != null) {
      _result.includeSchemaInPrompt = includeSchemaInPrompt;
    }
    if (strictMode != null) {
      _result.strictMode = strictMode;
    }
    return _result;
  }
  factory StructuredOutputOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputOptions clone() => StructuredOutputOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputOptions copyWith(void Function(StructuredOutputOptions) updates) => super.copyWith((message) => updates(message as StructuredOutputOptions)) as StructuredOutputOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static StructuredOutputOptions create() => StructuredOutputOptions._();
  StructuredOutputOptions createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputOptions> createRepeated() => $pb.PbList<StructuredOutputOptions>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputOptions>(create);
  static StructuredOutputOptions? _defaultInstance;

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

  @$pb.TagNumber(2)
  $core.bool get includeSchemaInPrompt => $_getBF(1);
  @$pb.TagNumber(2)
  set includeSchemaInPrompt($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIncludeSchemaInPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeSchemaInPrompt() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get strictMode => $_getBF(2);
  @$pb.TagNumber(3)
  set strictMode($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStrictMode() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrictMode() => clearField(3);
}

class StructuredOutputValidation extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StructuredOutputValidation', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isValid')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'containsJson')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'errorMessage')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'rawOutput')
    ..hasRequiredFields = false
  ;

  StructuredOutputValidation._() : super();
  factory StructuredOutputValidation({
    $core.bool? isValid,
    $core.bool? containsJson,
    $core.String? errorMessage,
    $core.String? rawOutput,
  }) {
    final _result = create();
    if (isValid != null) {
      _result.isValid = isValid;
    }
    if (containsJson != null) {
      _result.containsJson = containsJson;
    }
    if (errorMessage != null) {
      _result.errorMessage = errorMessage;
    }
    if (rawOutput != null) {
      _result.rawOutput = rawOutput;
    }
    return _result;
  }
  factory StructuredOutputValidation.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputValidation.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputValidation clone() => StructuredOutputValidation()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputValidation copyWith(void Function(StructuredOutputValidation) updates) => super.copyWith((message) => updates(message as StructuredOutputValidation)) as StructuredOutputValidation; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidation create() => StructuredOutputValidation._();
  StructuredOutputValidation createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputValidation> createRepeated() => $pb.PbList<StructuredOutputValidation>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidation getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputValidation>(create);
  static StructuredOutputValidation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isValid => $_getBF(0);
  @$pb.TagNumber(1)
  set isValid($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsValid() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsValid() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get containsJson => $_getBF(1);
  @$pb.TagNumber(2)
  set containsJson($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasContainsJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearContainsJson() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get rawOutput => $_getSZ(3);
  @$pb.TagNumber(4)
  set rawOutput($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRawOutput() => $_has(3);
  @$pb.TagNumber(4)
  void clearRawOutput() => clearField(4);
}

class StructuredOutputResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StructuredOutputResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'parsedJson', $pb.PbFieldType.OY)
    ..aOM<StructuredOutputValidation>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'validation', subBuilder: StructuredOutputValidation.create)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'rawText')
    ..hasRequiredFields = false
  ;

  StructuredOutputResult._() : super();
  factory StructuredOutputResult({
    $core.List<$core.int>? parsedJson,
    StructuredOutputValidation? validation,
    $core.String? rawText,
  }) {
    final _result = create();
    if (parsedJson != null) {
      _result.parsedJson = parsedJson;
    }
    if (validation != null) {
      _result.validation = validation;
    }
    if (rawText != null) {
      _result.rawText = rawText;
    }
    return _result;
  }
  factory StructuredOutputResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StructuredOutputResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StructuredOutputResult clone() => StructuredOutputResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StructuredOutputResult copyWith(void Function(StructuredOutputResult) updates) => super.copyWith((message) => updates(message as StructuredOutputResult)) as StructuredOutputResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static StructuredOutputResult create() => StructuredOutputResult._();
  StructuredOutputResult createEmptyInstance() => create();
  static $pb.PbList<StructuredOutputResult> createRepeated() => $pb.PbList<StructuredOutputResult>();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StructuredOutputResult>(create);
  static StructuredOutputResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get parsedJson => $_getN(0);
  @$pb.TagNumber(1)
  set parsedJson($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasParsedJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearParsedJson() => clearField(1);

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

  @$pb.TagNumber(3)
  $core.String get rawText => $_getSZ(2);
  @$pb.TagNumber(3)
  set rawText($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRawText() => $_has(2);
  @$pb.TagNumber(3)
  void clearRawText() => clearField(3);
}

class NamedEntity extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'NamedEntity', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'entityType')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'startOffset', $pb.PbFieldType.O3)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'endOffset', $pb.PbFieldType.O3)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  NamedEntity._() : super();
  factory NamedEntity({
    $core.String? text,
    $core.String? entityType,
    $core.int? startOffset,
    $core.int? endOffset,
    $core.double? confidence,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (entityType != null) {
      _result.entityType = entityType;
    }
    if (startOffset != null) {
      _result.startOffset = startOffset;
    }
    if (endOffset != null) {
      _result.endOffset = endOffset;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    return _result;
  }
  factory NamedEntity.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NamedEntity.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NamedEntity clone() => NamedEntity()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NamedEntity copyWith(void Function(NamedEntity) updates) => super.copyWith((message) => updates(message as NamedEntity)) as NamedEntity; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static NamedEntity create() => NamedEntity._();
  NamedEntity createEmptyInstance() => create();
  static $pb.PbList<NamedEntity> createRepeated() => $pb.PbList<NamedEntity>();
  @$core.pragma('dart2js:noInline')
  static NamedEntity getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NamedEntity>(create);
  static NamedEntity? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get entityType => $_getSZ(1);
  @$pb.TagNumber(2)
  set entityType($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEntityType() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntityType() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get startOffset => $_getIZ(2);
  @$pb.TagNumber(3)
  set startOffset($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStartOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartOffset() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get endOffset => $_getIZ(3);
  @$pb.TagNumber(4)
  set endOffset($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEndOffset() => $_has(3);
  @$pb.TagNumber(4)
  void clearEndOffset() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get confidence => $_getN(4);
  @$pb.TagNumber(5)
  set confidence($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasConfidence() => $_has(4);
  @$pb.TagNumber(5)
  void clearConfidence() => clearField(5);
}

class EntityExtractionResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'EntityExtractionResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<NamedEntity>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'entities', $pb.PbFieldType.PM, subBuilder: NamedEntity.create)
    ..hasRequiredFields = false
  ;

  EntityExtractionResult._() : super();
  factory EntityExtractionResult({
    $core.Iterable<NamedEntity>? entities,
  }) {
    final _result = create();
    if (entities != null) {
      _result.entities.addAll(entities);
    }
    return _result;
  }
  factory EntityExtractionResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EntityExtractionResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EntityExtractionResult clone() => EntityExtractionResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EntityExtractionResult copyWith(void Function(EntityExtractionResult) updates) => super.copyWith((message) => updates(message as EntityExtractionResult)) as EntityExtractionResult; // ignore: deprecated_member_use
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

class ClassificationCandidate extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ClassificationCandidate', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'label')
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  ClassificationCandidate._() : super();
  factory ClassificationCandidate({
    $core.String? label,
    $core.double? confidence,
  }) {
    final _result = create();
    if (label != null) {
      _result.label = label;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    return _result;
  }
  factory ClassificationCandidate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClassificationCandidate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClassificationCandidate clone() => ClassificationCandidate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClassificationCandidate copyWith(void Function(ClassificationCandidate) updates) => super.copyWith((message) => updates(message as ClassificationCandidate)) as ClassificationCandidate; // ignore: deprecated_member_use
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

class ClassificationResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ClassificationResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'label')
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..pc<ClassificationCandidate>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'alternatives', $pb.PbFieldType.PM, subBuilder: ClassificationCandidate.create)
    ..hasRequiredFields = false
  ;

  ClassificationResult._() : super();
  factory ClassificationResult({
    $core.String? label,
    $core.double? confidence,
    $core.Iterable<ClassificationCandidate>? alternatives,
  }) {
    final _result = create();
    if (label != null) {
      _result.label = label;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    if (alternatives != null) {
      _result.alternatives.addAll(alternatives);
    }
    return _result;
  }
  factory ClassificationResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClassificationResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClassificationResult clone() => ClassificationResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClassificationResult copyWith(void Function(ClassificationResult) updates) => super.copyWith((message) => updates(message as ClassificationResult)) as ClassificationResult; // ignore: deprecated_member_use
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

class SentimentResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SentimentResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<Sentiment>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sentiment', $pb.PbFieldType.OE, defaultOrMaker: Sentiment.SENTIMENT_UNSPECIFIED, valueOf: Sentiment.valueOf, enumValues: Sentiment.values)
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'positiveScore', $pb.PbFieldType.OF)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'negativeScore', $pb.PbFieldType.OF)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'neutralScore', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  SentimentResult._() : super();
  factory SentimentResult({
    Sentiment? sentiment,
    $core.double? confidence,
    $core.double? positiveScore,
    $core.double? negativeScore,
    $core.double? neutralScore,
  }) {
    final _result = create();
    if (sentiment != null) {
      _result.sentiment = sentiment;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    if (positiveScore != null) {
      _result.positiveScore = positiveScore;
    }
    if (negativeScore != null) {
      _result.negativeScore = negativeScore;
    }
    if (neutralScore != null) {
      _result.neutralScore = neutralScore;
    }
    return _result;
  }
  factory SentimentResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SentimentResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SentimentResult clone() => SentimentResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SentimentResult copyWith(void Function(SentimentResult) updates) => super.copyWith((message) => updates(message as SentimentResult)) as SentimentResult; // ignore: deprecated_member_use
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

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);

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

class NERResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'NERResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<NamedEntity>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'entities', $pb.PbFieldType.PM, subBuilder: NamedEntity.create)
    ..hasRequiredFields = false
  ;

  NERResult._() : super();
  factory NERResult({
    $core.Iterable<NamedEntity>? entities,
  }) {
    final _result = create();
    if (entities != null) {
      _result.entities.addAll(entities);
    }
    return _result;
  }
  factory NERResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NERResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NERResult clone() => NERResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NERResult copyWith(void Function(NERResult) updates) => super.copyWith((message) => updates(message as NERResult)) as NERResult; // ignore: deprecated_member_use
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

