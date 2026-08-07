// This is a generated file - do not edit.
//
// Generated from structured_output.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

enum StructuredOutputOptions_Constraint { schema, grammar, regex, notSet }

class StructuredOutputOptions extends $pb.GeneratedMessage {
  factory StructuredOutputOptions({
    $core.bool? includeSchemaInPrompt,
    $core.String? schema,
    $core.String? grammar,
    $core.String? regex,
  }) {
    final result = create();
    if (includeSchemaInPrompt != null)
      result.includeSchemaInPrompt = includeSchemaInPrompt;
    if (schema != null) result.schema = schema;
    if (grammar != null) result.grammar = grammar;
    if (regex != null) result.regex = regex;
    return result;
  }

  StructuredOutputOptions._();

  factory StructuredOutputOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StructuredOutputOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, StructuredOutputOptions_Constraint>
      _StructuredOutputOptions_ConstraintByTag = {
    2: StructuredOutputOptions_Constraint.schema,
    3: StructuredOutputOptions_Constraint.grammar,
    4: StructuredOutputOptions_Constraint.regex,
    0: StructuredOutputOptions_Constraint.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StructuredOutputOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [2, 3, 4])
    ..aOB(1, _omitFieldNames ? '' : 'includeSchemaInPrompt')
    ..aOS(2, _omitFieldNames ? '' : 'schema')
    ..aOS(3, _omitFieldNames ? '' : 'grammar')
    ..aOS(4, _omitFieldNames ? '' : 'regex')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputOptions copyWith(
          void Function(StructuredOutputOptions) updates) =>
      super.copyWith((message) => updates(message as StructuredOutputOptions))
          as StructuredOutputOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputOptions create() => StructuredOutputOptions._();
  @$core.override
  StructuredOutputOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StructuredOutputOptions>(create);
  static StructuredOutputOptions? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  StructuredOutputOptions_Constraint whichConstraint() =>
      _StructuredOutputOptions_ConstraintByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearConstraint() => $_clearField($_whichOneof(0));

  /// Also render the schema into the system prompt, not just constrain
  /// decoding. Costs input tokens and invalidates the thread's prompt cache.
  /// Default true (matches Apple FoundationModels includeSchemaInPrompt).
  @$pb.TagNumber(1)
  $core.bool get includeSchemaInPrompt => $_getBF(0);
  @$pb.TagNumber(1)
  set includeSchemaInPrompt($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIncludeSchemaInPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearIncludeSchemaInPrompt() => $_clearField(1);

  /// A JSON Schema document, verbatim. Unsupported keywords are rejected.
  @$pb.TagNumber(2)
  $core.String get schema => $_getSZ(1);
  @$pb.TagNumber(2)
  set schema($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSchema() => $_has(1);
  @$pb.TagNumber(2)
  void clearSchema() => $_clearField(2);

  /// GBNF/EBNF grammar text. On-device only.
  @$pb.TagNumber(3)
  $core.String get grammar => $_getSZ(2);
  @$pb.TagNumber(3)
  set grammar($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGrammar() => $_has(2);
  @$pb.TagNumber(3)
  void clearGrammar() => $_clearField(3);

  /// Regular expression the whole output must match. On-device only.
  @$pb.TagNumber(4)
  $core.String get regex => $_getSZ(3);
  @$pb.TagNumber(4)
  set regex($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRegex() => $_has(3);
  @$pb.TagNumber(4)
  void clearRegex() => $_clearField(4);
}

class StructuredOutputValidation extends $pb.GeneratedMessage {
  factory StructuredOutputValidation({
    $core.bool? isValid,
    $core.bool? containsJson,
    $core.String? rawOutput,
    $core.String? extractedJson,
    $core.Iterable<$core.String>? validationErrors,
    $fixnum.Int64? validationTimeMs,
    $0.SDKError? error,
  }) {
    final result = create();
    if (isValid != null) result.isValid = isValid;
    if (containsJson != null) result.containsJson = containsJson;
    if (rawOutput != null) result.rawOutput = rawOutput;
    if (extractedJson != null) result.extractedJson = extractedJson;
    if (validationErrors != null)
      result.validationErrors.addAll(validationErrors);
    if (validationTimeMs != null) result.validationTimeMs = validationTimeMs;
    if (error != null) result.error = error;
    return result;
  }

  StructuredOutputValidation._();

  factory StructuredOutputValidation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StructuredOutputValidation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StructuredOutputValidation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isValid')
    ..aOB(2, _omitFieldNames ? '' : 'containsJson')
    ..aOS(3, _omitFieldNames ? '' : 'rawOutput')
    ..aOS(4, _omitFieldNames ? '' : 'extractedJson')
    ..pPS(5, _omitFieldNames ? '' : 'validationErrors')
    ..aInt64(6, _omitFieldNames ? '' : 'validationTimeMs')
    ..aOM<$0.SDKError>(7, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputValidation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputValidation copyWith(
          void Function(StructuredOutputValidation) updates) =>
      super.copyWith(
              (message) => updates(message as StructuredOutputValidation))
          as StructuredOutputValidation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidation create() => StructuredOutputValidation._();
  @$core.override
  StructuredOutputValidation createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputValidation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StructuredOutputValidation>(create);
  static StructuredOutputValidation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isValid => $_getBF(0);
  @$pb.TagNumber(1)
  set isValid($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsValid() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsValid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get containsJson => $_getBF(1);
  @$pb.TagNumber(2)
  set containsJson($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContainsJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearContainsJson() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get rawOutput => $_getSZ(2);
  @$pb.TagNumber(3)
  set rawOutput($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRawOutput() => $_has(2);
  @$pb.TagNumber(3)
  void clearRawOutput() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get extractedJson => $_getSZ(3);
  @$pb.TagNumber(4)
  set extractedJson($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExtractedJson() => $_has(3);
  @$pb.TagNumber(4)
  void clearExtractedJson() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get validationErrors => $_getList(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get validationTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set validationTimeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasValidationTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearValidationTimeMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $0.SDKError get error => $_getN(6);
  @$pb.TagNumber(7)
  set error($0.SDKError value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.SDKError ensureError() => $_ensure(6);
}

class StructuredOutputResult extends $pb.GeneratedMessage {
  factory StructuredOutputResult({
    $core.String? json,
    StructuredOutputValidation? validation,
    $core.String? rawText,
    $0.SDKError? error,
  }) {
    final result = create();
    if (json != null) result.json = json;
    if (validation != null) result.validation = validation;
    if (rawText != null) result.rawText = rawText;
    if (error != null) result.error = error;
    return result;
  }

  StructuredOutputResult._();

  factory StructuredOutputResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StructuredOutputResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StructuredOutputResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'json')
    ..aOM<StructuredOutputValidation>(2, _omitFieldNames ? '' : 'validation',
        subBuilder: StructuredOutputValidation.create)
    ..aOS(3, _omitFieldNames ? '' : 'rawText')
    ..aOM<$0.SDKError>(4, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputResult copyWith(
          void Function(StructuredOutputResult) updates) =>
      super.copyWith((message) => updates(message as StructuredOutputResult))
          as StructuredOutputResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputResult create() => StructuredOutputResult._();
  @$core.override
  StructuredOutputResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StructuredOutputResult>(create);
  static StructuredOutputResult? _defaultInstance;

  /// The extracted JSON document, as UTF-8 text. Parse it client-side.
  @$pb.TagNumber(1)
  $core.String get json => $_getSZ(0);
  @$pb.TagNumber(1)
  set json($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearJson() => $_clearField(1);

  @$pb.TagNumber(2)
  StructuredOutputValidation get validation => $_getN(1);
  @$pb.TagNumber(2)
  set validation(StructuredOutputValidation value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasValidation() => $_has(1);
  @$pb.TagNumber(2)
  void clearValidation() => $_clearField(2);
  @$pb.TagNumber(2)
  StructuredOutputValidation ensureValidation() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get rawText => $_getSZ(2);
  @$pb.TagNumber(3)
  set rawText($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRawText() => $_has(2);
  @$pb.TagNumber(3)
  void clearRawText() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.SDKError get error => $_getN(3);
  @$pb.TagNumber(4)
  set error($0.SDKError value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.SDKError ensureError() => $_ensure(3);
}

class StructuredOutputParseRequest extends $pb.GeneratedMessage {
  factory StructuredOutputParseRequest({
    $core.String? requestId,
    $core.String? text,
    StructuredOutputOptions? options,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (text != null) result.text = text;
    if (options != null) result.options = options;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  StructuredOutputParseRequest._();

  factory StructuredOutputParseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StructuredOutputParseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StructuredOutputParseRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOM<StructuredOutputOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: StructuredOutputOptions.create)
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'StructuredOutputParseRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputParseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputParseRequest copyWith(
          void Function(StructuredOutputParseRequest) updates) =>
      super.copyWith(
              (message) => updates(message as StructuredOutputParseRequest))
          as StructuredOutputParseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputParseRequest create() =>
      StructuredOutputParseRequest._();
  @$core.override
  StructuredOutputParseRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputParseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StructuredOutputParseRequest>(create);
  static StructuredOutputParseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  StructuredOutputOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(StructuredOutputOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  StructuredOutputOptions ensureOptions() => $_ensure(2);

  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(3);
}

class StructuredOutputPromptResult extends $pb.GeneratedMessage {
  factory StructuredOutputPromptResult({
    $core.String? preparedPrompt,
    $core.String? systemPrompt,
    $core.String? jsonSchema,
    $core.String? regexPattern,
    $core.String? grammar,
    $0.SDKError? error,
  }) {
    final result = create();
    if (preparedPrompt != null) result.preparedPrompt = preparedPrompt;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (jsonSchema != null) result.jsonSchema = jsonSchema;
    if (regexPattern != null) result.regexPattern = regexPattern;
    if (grammar != null) result.grammar = grammar;
    if (error != null) result.error = error;
    return result;
  }

  StructuredOutputPromptResult._();

  factory StructuredOutputPromptResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StructuredOutputPromptResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StructuredOutputPromptResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'preparedPrompt')
    ..aOS(2, _omitFieldNames ? '' : 'systemPrompt')
    ..aOS(3, _omitFieldNames ? '' : 'jsonSchema')
    ..aOS(4, _omitFieldNames ? '' : 'regexPattern')
    ..aOS(5, _omitFieldNames ? '' : 'grammar')
    ..aOM<$0.SDKError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputPromptResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StructuredOutputPromptResult copyWith(
          void Function(StructuredOutputPromptResult) updates) =>
      super.copyWith(
              (message) => updates(message as StructuredOutputPromptResult))
          as StructuredOutputPromptResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StructuredOutputPromptResult create() =>
      StructuredOutputPromptResult._();
  @$core.override
  StructuredOutputPromptResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StructuredOutputPromptResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StructuredOutputPromptResult>(create);
  static StructuredOutputPromptResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get preparedPrompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set preparedPrompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPreparedPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPreparedPrompt() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get systemPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemPrompt($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSystemPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemPrompt() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get jsonSchema => $_getSZ(2);
  @$pb.TagNumber(3)
  set jsonSchema($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasJsonSchema() => $_has(2);
  @$pb.TagNumber(3)
  void clearJsonSchema() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get regexPattern => $_getSZ(3);
  @$pb.TagNumber(4)
  set regexPattern($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRegexPattern() => $_has(3);
  @$pb.TagNumber(4)
  void clearRegexPattern() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get grammar => $_getSZ(4);
  @$pb.TagNumber(5)
  set grammar($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGrammar() => $_has(4);
  @$pb.TagNumber(5)
  void clearGrammar() => $_clearField(5);

  @$pb.TagNumber(6)
  $0.SDKError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error($0.SDKError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.SDKError ensureError() => $_ensure(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
