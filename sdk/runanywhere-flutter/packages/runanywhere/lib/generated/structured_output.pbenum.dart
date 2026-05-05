//
//  Generated code. Do not modify.
//  source: structured_output.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// JSON Schema primitive type — union across SDKs.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:12     ('string'|'number'|'integer'|
///                                        'boolean'|'object'|'array'|'null')
///   Web (delegates to llamacpp pkg; no own enum)
///   Swift / Kotlin / Dart represent schema as a serialized JSON string today,
///     so this enum canonicalizes the RN-defined union.
/// ---------------------------------------------------------------------------
class JSONSchemaType extends $pb.ProtobufEnum {
  static const JSONSchemaType JSON_SCHEMA_TYPE_UNSPECIFIED = JSONSchemaType._(0, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_UNSPECIFIED');
  static const JSONSchemaType JSON_SCHEMA_TYPE_OBJECT = JSONSchemaType._(1, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_OBJECT');
  static const JSONSchemaType JSON_SCHEMA_TYPE_ARRAY = JSONSchemaType._(2, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_ARRAY');
  static const JSONSchemaType JSON_SCHEMA_TYPE_STRING = JSONSchemaType._(3, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_STRING');
  static const JSONSchemaType JSON_SCHEMA_TYPE_NUMBER = JSONSchemaType._(4, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_NUMBER');
  static const JSONSchemaType JSON_SCHEMA_TYPE_INTEGER = JSONSchemaType._(5, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_INTEGER');
  static const JSONSchemaType JSON_SCHEMA_TYPE_BOOLEAN = JSONSchemaType._(6, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_BOOLEAN');
  static const JSONSchemaType JSON_SCHEMA_TYPE_NULL = JSONSchemaType._(7, _omitEnumNames ? '' : 'JSON_SCHEMA_TYPE_NULL');

  static const $core.List<JSONSchemaType> values = <JSONSchemaType> [
    JSON_SCHEMA_TYPE_UNSPECIFIED,
    JSON_SCHEMA_TYPE_OBJECT,
    JSON_SCHEMA_TYPE_ARRAY,
    JSON_SCHEMA_TYPE_STRING,
    JSON_SCHEMA_TYPE_NUMBER,
    JSON_SCHEMA_TYPE_INTEGER,
    JSON_SCHEMA_TYPE_BOOLEAN,
    JSON_SCHEMA_TYPE_NULL,
  ];

  static final $core.Map<$core.int, JSONSchemaType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static JSONSchemaType? valueOf($core.int value) => _byValue[value];

  const JSONSchemaType._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Sentiment label — union across SDKs.
/// Sources pre-IDL:
///   RN  StructuredOutputTypes.ts:131    ('positive'|'negative'|'neutral')
///   (Other SDKs do not yet define a Sentiment type; MIXED is added for
///    completeness — common in industry sentiment APIs.)
/// ---------------------------------------------------------------------------
class Sentiment extends $pb.ProtobufEnum {
  static const Sentiment SENTIMENT_UNSPECIFIED = Sentiment._(0, _omitEnumNames ? '' : 'SENTIMENT_UNSPECIFIED');
  static const Sentiment SENTIMENT_POSITIVE = Sentiment._(1, _omitEnumNames ? '' : 'SENTIMENT_POSITIVE');
  static const Sentiment SENTIMENT_NEGATIVE = Sentiment._(2, _omitEnumNames ? '' : 'SENTIMENT_NEGATIVE');
  static const Sentiment SENTIMENT_NEUTRAL = Sentiment._(3, _omitEnumNames ? '' : 'SENTIMENT_NEUTRAL');
  static const Sentiment SENTIMENT_MIXED = Sentiment._(4, _omitEnumNames ? '' : 'SENTIMENT_MIXED');

  static const $core.List<Sentiment> values = <Sentiment> [
    SENTIMENT_UNSPECIFIED,
    SENTIMENT_POSITIVE,
    SENTIMENT_NEGATIVE,
    SENTIMENT_NEUTRAL,
    SENTIMENT_MIXED,
  ];

  static final $core.Map<$core.int, Sentiment> _byValue = $pb.ProtobufEnum.initByValue(values);
  static Sentiment? valueOf($core.int value) => _byValue[value];

  const Sentiment._($core.int v, $core.String n) : super(v, n);
}

class StructuredOutputMode extends $pb.ProtobufEnum {
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_UNSPECIFIED = StructuredOutputMode._(0, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_UNSPECIFIED');
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_JSON_SCHEMA = StructuredOutputMode._(1, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_JSON_SCHEMA');
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_JSON_OBJECT = StructuredOutputMode._(2, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_JSON_OBJECT');
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_REGEX = StructuredOutputMode._(3, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_REGEX');
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_GRAMMAR = StructuredOutputMode._(4, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_GRAMMAR');

  static const $core.List<StructuredOutputMode> values = <StructuredOutputMode> [
    STRUCTURED_OUTPUT_MODE_UNSPECIFIED,
    STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
    STRUCTURED_OUTPUT_MODE_JSON_OBJECT,
    STRUCTURED_OUTPUT_MODE_REGEX,
    STRUCTURED_OUTPUT_MODE_GRAMMAR,
  ];

  static final $core.Map<$core.int, StructuredOutputMode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static StructuredOutputMode? valueOf($core.int value) => _byValue[value];

  const StructuredOutputMode._($core.int v, $core.String n) : super(v, n);
}

class StructuredOutputStreamEventKind extends $pb.ProtobufEnum {
  static const StructuredOutputStreamEventKind STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED = StructuredOutputStreamEventKind._(0, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED');
  static const StructuredOutputStreamEventKind STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN = StructuredOutputStreamEventKind._(1, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN');
  static const StructuredOutputStreamEventKind STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON = StructuredOutputStreamEventKind._(2, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON');
  static const StructuredOutputStreamEventKind STRUCTURED_OUTPUT_STREAM_EVENT_KIND_VALIDATION = StructuredOutputStreamEventKind._(3, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_VALIDATION');
  static const StructuredOutputStreamEventKind STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED = StructuredOutputStreamEventKind._(4, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED');
  static const StructuredOutputStreamEventKind STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR = StructuredOutputStreamEventKind._(5, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR');

  static const $core.List<StructuredOutputStreamEventKind> values = <StructuredOutputStreamEventKind> [
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_VALIDATION,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED,
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.Map<$core.int, StructuredOutputStreamEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static StructuredOutputStreamEventKind? valueOf($core.int value) => _byValue[value];

  const StructuredOutputStreamEventKind._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
