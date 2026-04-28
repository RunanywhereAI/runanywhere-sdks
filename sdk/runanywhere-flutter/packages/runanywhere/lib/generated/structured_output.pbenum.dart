///
//  Generated code. Do not modify.
//  source: structured_output.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class JSONSchemaType extends $pb.ProtobufEnum {
  static const JSONSchemaType JSON_SCHEMA_TYPE_UNSPECIFIED = JSONSchemaType._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_UNSPECIFIED');
  static const JSONSchemaType JSON_SCHEMA_TYPE_OBJECT = JSONSchemaType._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_OBJECT');
  static const JSONSchemaType JSON_SCHEMA_TYPE_ARRAY = JSONSchemaType._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_ARRAY');
  static const JSONSchemaType JSON_SCHEMA_TYPE_STRING = JSONSchemaType._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_STRING');
  static const JSONSchemaType JSON_SCHEMA_TYPE_NUMBER = JSONSchemaType._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_NUMBER');
  static const JSONSchemaType JSON_SCHEMA_TYPE_INTEGER = JSONSchemaType._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_INTEGER');
  static const JSONSchemaType JSON_SCHEMA_TYPE_BOOLEAN = JSONSchemaType._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_BOOLEAN');
  static const JSONSchemaType JSON_SCHEMA_TYPE_NULL = JSONSchemaType._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JSON_SCHEMA_TYPE_NULL');

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

class Sentiment extends $pb.ProtobufEnum {
  static const Sentiment SENTIMENT_UNSPECIFIED = Sentiment._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SENTIMENT_UNSPECIFIED');
  static const Sentiment SENTIMENT_POSITIVE = Sentiment._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SENTIMENT_POSITIVE');
  static const Sentiment SENTIMENT_NEGATIVE = Sentiment._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SENTIMENT_NEGATIVE');
  static const Sentiment SENTIMENT_NEUTRAL = Sentiment._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SENTIMENT_NEUTRAL');
  static const Sentiment SENTIMENT_MIXED = Sentiment._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SENTIMENT_MIXED');

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

