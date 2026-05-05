//
//  Generated code. Do not modify.
//  source: structured_output.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use jSONSchemaTypeDescriptor instead')
const JSONSchemaType$json = {
  '1': 'JSONSchemaType',
  '2': [
    {'1': 'JSON_SCHEMA_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'JSON_SCHEMA_TYPE_OBJECT', '2': 1},
    {'1': 'JSON_SCHEMA_TYPE_ARRAY', '2': 2},
    {'1': 'JSON_SCHEMA_TYPE_STRING', '2': 3},
    {'1': 'JSON_SCHEMA_TYPE_NUMBER', '2': 4},
    {'1': 'JSON_SCHEMA_TYPE_INTEGER', '2': 5},
    {'1': 'JSON_SCHEMA_TYPE_BOOLEAN', '2': 6},
    {'1': 'JSON_SCHEMA_TYPE_NULL', '2': 7},
  ],
};

/// Descriptor for `JSONSchemaType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List jSONSchemaTypeDescriptor = $convert.base64Decode(
    'Cg5KU09OU2NoZW1hVHlwZRIgChxKU09OX1NDSEVNQV9UWVBFX1VOU1BFQ0lGSUVEEAASGwoXSl'
    'NPTl9TQ0hFTUFfVFlQRV9PQkpFQ1QQARIaChZKU09OX1NDSEVNQV9UWVBFX0FSUkFZEAISGwoX'
    'SlNPTl9TQ0hFTUFfVFlQRV9TVFJJTkcQAxIbChdKU09OX1NDSEVNQV9UWVBFX05VTUJFUhAEEh'
    'wKGEpTT05fU0NIRU1BX1RZUEVfSU5URUdFUhAFEhwKGEpTT05fU0NIRU1BX1RZUEVfQk9PTEVB'
    'ThAGEhkKFUpTT05fU0NIRU1BX1RZUEVfTlVMTBAH');

@$core.Deprecated('Use sentimentDescriptor instead')
const Sentiment$json = {
  '1': 'Sentiment',
  '2': [
    {'1': 'SENTIMENT_UNSPECIFIED', '2': 0},
    {'1': 'SENTIMENT_POSITIVE', '2': 1},
    {'1': 'SENTIMENT_NEGATIVE', '2': 2},
    {'1': 'SENTIMENT_NEUTRAL', '2': 3},
    {'1': 'SENTIMENT_MIXED', '2': 4},
  ],
};

/// Descriptor for `Sentiment`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sentimentDescriptor = $convert.base64Decode(
    'CglTZW50aW1lbnQSGQoVU0VOVElNRU5UX1VOU1BFQ0lGSUVEEAASFgoSU0VOVElNRU5UX1BPU0'
    'lUSVZFEAESFgoSU0VOVElNRU5UX05FR0FUSVZFEAISFQoRU0VOVElNRU5UX05FVVRSQUwQAxIT'
    'Cg9TRU5USU1FTlRfTUlYRUQQBA==');

@$core.Deprecated('Use structuredOutputModeDescriptor instead')
const StructuredOutputMode$json = {
  '1': 'StructuredOutputMode',
  '2': [
    {'1': 'STRUCTURED_OUTPUT_MODE_UNSPECIFIED', '2': 0},
    {'1': 'STRUCTURED_OUTPUT_MODE_JSON_SCHEMA', '2': 1},
    {'1': 'STRUCTURED_OUTPUT_MODE_JSON_OBJECT', '2': 2},
    {'1': 'STRUCTURED_OUTPUT_MODE_REGEX', '2': 3},
    {'1': 'STRUCTURED_OUTPUT_MODE_GRAMMAR', '2': 4},
  ],
};

/// Descriptor for `StructuredOutputMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List structuredOutputModeDescriptor = $convert.base64Decode(
    'ChRTdHJ1Y3R1cmVkT3V0cHV0TW9kZRImCiJTVFJVQ1RVUkVEX09VVFBVVF9NT0RFX1VOU1BFQ0'
    'lGSUVEEAASJgoiU1RSVUNUVVJFRF9PVVRQVVRfTU9ERV9KU09OX1NDSEVNQRABEiYKIlNUUlVD'
    'VFVSRURfT1VUUFVUX01PREVfSlNPTl9PQkpFQ1QQAhIgChxTVFJVQ1RVUkVEX09VVFBVVF9NT0'
    'RFX1JFR0VYEAMSIgoeU1RSVUNUVVJFRF9PVVRQVVRfTU9ERV9HUkFNTUFSEAQ=');

@$core.Deprecated('Use structuredOutputStreamEventKindDescriptor instead')
const StructuredOutputStreamEventKind$json = {
  '1': 'StructuredOutputStreamEventKind',
  '2': [
    {'1': 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN', '2': 1},
    {'1': 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON', '2': 2},
    {'1': 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_VALIDATION', '2': 3},
    {'1': 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED', '2': 4},
    {'1': 'STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR', '2': 5},
  ],
};

/// Descriptor for `StructuredOutputStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List structuredOutputStreamEventKindDescriptor = $convert.base64Decode(
    'Ch9TdHJ1Y3R1cmVkT3V0cHV0U3RyZWFtRXZlbnRLaW5kEjMKL1NUUlVDVFVSRURfT1VUUFVUX1'
    'NUUkVBTV9FVkVOVF9LSU5EX1VOU1BFQ0lGSUVEEAASLQopU1RSVUNUVVJFRF9PVVRQVVRfU1RS'
    'RUFNX0VWRU5UX0tJTkRfVE9LRU4QARI0CjBTVFJVQ1RVUkVEX09VVFBVVF9TVFJFQU1fRVZFTl'
    'RfS0lORF9QQVJUSUFMX0pTT04QAhIyCi5TVFJVQ1RVUkVEX09VVFBVVF9TVFJFQU1fRVZFTlRf'
    'S0lORF9WQUxJREFUSU9OEAMSMQotU1RSVUNUVVJFRF9PVVRQVVRfU1RSRUFNX0VWRU5UX0tJTk'
    'RfQ09NUExFVEVEEAQSLQopU1RSVUNUVVJFRF9PVVRQVVRfU1RSRUFNX0VWRU5UX0tJTkRfRVJS'
    'T1IQBQ==');

@$core.Deprecated('Use jSONSchemaPropertyDescriptor instead')
const JSONSchemaProperty$json = {
  '1': 'JSONSchemaProperty',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.JSONSchemaType', '10': 'type'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'description', '17': true},
    {'1': 'enum_values', '3': 3, '4': 3, '5': 9, '10': 'enumValues'},
    {'1': 'format', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'format', '17': true},
    {'1': 'items_schema', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '9': 2, '10': 'itemsSchema', '17': true},
    {'1': 'object_schema', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '9': 3, '10': 'objectSchema', '17': true},
    {'1': 'minimum', '3': 7, '4': 1, '5': 1, '9': 4, '10': 'minimum', '17': true},
    {'1': 'maximum', '3': 8, '4': 1, '5': 1, '9': 5, '10': 'maximum', '17': true},
    {'1': 'min_length', '3': 9, '4': 1, '5': 5, '9': 6, '10': 'minLength', '17': true},
    {'1': 'max_length', '3': 10, '4': 1, '5': 5, '9': 7, '10': 'maxLength', '17': true},
    {'1': 'pattern', '3': 11, '4': 1, '5': 9, '9': 8, '10': 'pattern', '17': true},
    {'1': 'min_items', '3': 12, '4': 1, '5': 5, '9': 9, '10': 'minItems', '17': true},
    {'1': 'max_items', '3': 13, '4': 1, '5': 5, '9': 10, '10': 'maxItems', '17': true},
    {'1': 'default_json', '3': 14, '4': 1, '5': 9, '9': 11, '10': 'defaultJson', '17': true},
  ],
  '8': [
    {'1': '_description'},
    {'1': '_format'},
    {'1': '_items_schema'},
    {'1': '_object_schema'},
    {'1': '_minimum'},
    {'1': '_maximum'},
    {'1': '_min_length'},
    {'1': '_max_length'},
    {'1': '_pattern'},
    {'1': '_min_items'},
    {'1': '_max_items'},
    {'1': '_default_json'},
  ],
};

/// Descriptor for `JSONSchemaProperty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jSONSchemaPropertyDescriptor = $convert.base64Decode(
    'ChJKU09OU2NoZW1hUHJvcGVydHkSMgoEdHlwZRgBIAEoDjIeLnJ1bmFueXdoZXJlLnYxLkpTT0'
    '5TY2hlbWFUeXBlUgR0eXBlEiUKC2Rlc2NyaXB0aW9uGAIgASgJSABSC2Rlc2NyaXB0aW9uiAEB'
    'Eh8KC2VudW1fdmFsdWVzGAMgAygJUgplbnVtVmFsdWVzEhsKBmZvcm1hdBgEIAEoCUgBUgZmb3'
    'JtYXSIAQESQgoMaXRlbXNfc2NoZW1hGAUgASgLMhoucnVuYW55d2hlcmUudjEuSlNPTlNjaGVt'
    'YUgCUgtpdGVtc1NjaGVtYYgBARJECg1vYmplY3Rfc2NoZW1hGAYgASgLMhoucnVuYW55d2hlcm'
    'UudjEuSlNPTlNjaGVtYUgDUgxvYmplY3RTY2hlbWGIAQESHQoHbWluaW11bRgHIAEoAUgEUgdt'
    'aW5pbXVtiAEBEh0KB21heGltdW0YCCABKAFIBVIHbWF4aW11bYgBARIiCgptaW5fbGVuZ3RoGA'
    'kgASgFSAZSCW1pbkxlbmd0aIgBARIiCgptYXhfbGVuZ3RoGAogASgFSAdSCW1heExlbmd0aIgB'
    'ARIdCgdwYXR0ZXJuGAsgASgJSAhSB3BhdHRlcm6IAQESIAoJbWluX2l0ZW1zGAwgASgFSAlSCG'
    '1pbkl0ZW1ziAEBEiAKCW1heF9pdGVtcxgNIAEoBUgKUghtYXhJdGVtc4gBARImCgxkZWZhdWx0'
    'X2pzb24YDiABKAlIC1ILZGVmYXVsdEpzb26IAQFCDgoMX2Rlc2NyaXB0aW9uQgkKB19mb3JtYX'
    'RCDwoNX2l0ZW1zX3NjaGVtYUIQCg5fb2JqZWN0X3NjaGVtYUIKCghfbWluaW11bUIKCghfbWF4'
    'aW11bUINCgtfbWluX2xlbmd0aEINCgtfbWF4X2xlbmd0aEIKCghfcGF0dGVybkIMCgpfbWluX2'
    'l0ZW1zQgwKCl9tYXhfaXRlbXNCDwoNX2RlZmF1bHRfanNvbg==');

@$core.Deprecated('Use jSONSchemaDescriptor instead')
const JSONSchema$json = {
  '1': 'JSONSchema',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.JSONSchemaType', '10': 'type'},
    {'1': 'properties', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.JSONSchema.PropertiesEntry', '10': 'properties'},
    {'1': 'required', '3': 3, '4': 3, '5': 9, '10': 'required'},
    {'1': 'items', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchemaProperty', '9': 0, '10': 'items', '17': true},
    {'1': 'additional_properties', '3': 5, '4': 1, '5': 8, '9': 1, '10': 'additionalProperties', '17': true},
    {'1': 'schema_uri', '3': 6, '4': 1, '5': 9, '9': 2, '10': '\$schema', '17': true},
    {'1': 'id_uri', '3': 7, '4': 1, '5': 9, '9': 3, '10': '\$id', '17': true},
    {'1': 'title', '3': 8, '4': 1, '5': 9, '9': 4, '10': 'title', '17': true},
    {'1': 'description', '3': 9, '4': 1, '5': 9, '9': 5, '10': 'description', '17': true},
    {'1': 'definitions', '3': 10, '4': 3, '5': 11, '6': '.runanywhere.v1.JSONSchema.DefinitionsEntry', '10': 'definitions'},
    {'1': 'ref', '3': 11, '4': 1, '5': 9, '9': 6, '10': '\$ref', '17': true},
    {'1': 'all_of', '3': 12, '4': 3, '5': 11, '6': '.runanywhere.v1.JSONSchema', '10': 'allOf'},
    {'1': 'any_of', '3': 13, '4': 3, '5': 11, '6': '.runanywhere.v1.JSONSchema', '10': 'anyOf'},
    {'1': 'one_of', '3': 14, '4': 3, '5': 11, '6': '.runanywhere.v1.JSONSchema', '10': 'oneOf'},
    {'1': 'not_schema', '3': 15, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '9': 7, '10': 'notSchema', '17': true},
    {'1': 'raw_json', '3': 16, '4': 1, '5': 9, '9': 8, '10': 'rawJson', '17': true},
  ],
  '3': [JSONSchema_PropertiesEntry$json, JSONSchema_DefinitionsEntry$json],
  '8': [
    {'1': '_items'},
    {'1': '_additional_properties'},
    {'1': '_schema_uri'},
    {'1': '_id_uri'},
    {'1': '_title'},
    {'1': '_description'},
    {'1': '_ref'},
    {'1': '_not_schema'},
    {'1': '_raw_json'},
  ],
};

@$core.Deprecated('Use jSONSchemaDescriptor instead')
const JSONSchema_PropertiesEntry$json = {
  '1': 'PropertiesEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchemaProperty', '10': 'value'},
  ],
  '7': {'7': true},
};

@$core.Deprecated('Use jSONSchemaDescriptor instead')
const JSONSchema_DefinitionsEntry$json = {
  '1': 'DefinitionsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `JSONSchema`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jSONSchemaDescriptor = $convert.base64Decode(
    'CgpKU09OU2NoZW1hEjIKBHR5cGUYASABKA4yHi5ydW5hbnl3aGVyZS52MS5KU09OU2NoZW1hVH'
    'lwZVIEdHlwZRJKCgpwcm9wZXJ0aWVzGAIgAygLMioucnVuYW55d2hlcmUudjEuSlNPTlNjaGVt'
    'YS5Qcm9wZXJ0aWVzRW50cnlSCnByb3BlcnRpZXMSGgoIcmVxdWlyZWQYAyADKAlSCHJlcXVpcm'
    'VkEj0KBWl0ZW1zGAQgASgLMiIucnVuYW55d2hlcmUudjEuSlNPTlNjaGVtYVByb3BlcnR5SABS'
    'BWl0ZW1ziAEBEjgKFWFkZGl0aW9uYWxfcHJvcGVydGllcxgFIAEoCEgBUhRhZGRpdGlvbmFsUH'
    'JvcGVydGllc4gBARIgCgpzY2hlbWFfdXJpGAYgASgJSAJSByRzY2hlbWGIAQESGAoGaWRfdXJp'
    'GAcgASgJSANSAyRpZIgBARIZCgV0aXRsZRgIIAEoCUgEUgV0aXRsZYgBARIlCgtkZXNjcmlwdG'
    'lvbhgJIAEoCUgFUgtkZXNjcmlwdGlvbogBARJNCgtkZWZpbml0aW9ucxgKIAMoCzIrLnJ1bmFu'
    'eXdoZXJlLnYxLkpTT05TY2hlbWEuRGVmaW5pdGlvbnNFbnRyeVILZGVmaW5pdGlvbnMSFgoDcm'
    'VmGAsgASgJSAZSBCRyZWaIAQESMQoGYWxsX29mGAwgAygLMhoucnVuYW55d2hlcmUudjEuSlNP'
    'TlNjaGVtYVIFYWxsT2YSMQoGYW55X29mGA0gAygLMhoucnVuYW55d2hlcmUudjEuSlNPTlNjaG'
    'VtYVIFYW55T2YSMQoGb25lX29mGA4gAygLMhoucnVuYW55d2hlcmUudjEuSlNPTlNjaGVtYVIF'
    'b25lT2YSPgoKbm90X3NjaGVtYRgPIAEoCzIaLnJ1bmFueXdoZXJlLnYxLkpTT05TY2hlbWFIB1'
    'IJbm90U2NoZW1hiAEBEh4KCHJhd19qc29uGBAgASgJSAhSB3Jhd0pzb26IAQEaYQoPUHJvcGVy'
    'dGllc0VudHJ5EhAKA2tleRgBIAEoCVIDa2V5EjgKBXZhbHVlGAIgASgLMiIucnVuYW55d2hlcm'
    'UudjEuSlNPTlNjaGVtYVByb3BlcnR5UgV2YWx1ZToCOAEaWgoQRGVmaW5pdGlvbnNFbnRyeRIQ'
    'CgNrZXkYASABKAlSA2tleRIwCgV2YWx1ZRgCIAEoCzIaLnJ1bmFueXdoZXJlLnYxLkpTT05TY2'
    'hlbWFSBXZhbHVlOgI4AUIICgZfaXRlbXNCGAoWX2FkZGl0aW9uYWxfcHJvcGVydGllc0INCgtf'
    'c2NoZW1hX3VyaUIJCgdfaWRfdXJpQggKBl90aXRsZUIOCgxfZGVzY3JpcHRpb25CBgoEX3JlZk'
    'INCgtfbm90X3NjaGVtYUILCglfcmF3X2pzb24=');

@$core.Deprecated('Use structuredOutputOptionsDescriptor instead')
const StructuredOutputOptions$json = {
  '1': 'StructuredOutputOptions',
  '2': [
    {'1': 'schema', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '10': 'schema'},
    {'1': 'include_schema_in_prompt', '3': 2, '4': 1, '5': 8, '10': 'includeSchemaInPrompt'},
    {'1': 'strict_mode', '3': 3, '4': 1, '5': 8, '9': 0, '10': 'strictMode', '17': true},
    {'1': 'json_schema', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'jsonSchema', '17': true},
    {'1': 'type_name', '3': 5, '4': 1, '5': 9, '9': 2, '10': 'typeName', '17': true},
    {'1': 'name', '3': 6, '4': 1, '5': 9, '9': 3, '10': 'name', '17': true},
    {'1': 'mode', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.StructuredOutputMode', '10': 'mode'},
    {'1': 'regex_pattern', '3': 8, '4': 1, '5': 9, '9': 4, '10': 'regexPattern', '17': true},
    {'1': 'grammar', '3': 9, '4': 1, '5': 9, '9': 5, '10': 'grammar', '17': true},
    {'1': 'repair_json', '3': 10, '4': 1, '5': 8, '10': 'repairJson'},
    {'1': 'max_retries', '3': 11, '4': 1, '5': 5, '10': 'maxRetries'},
  ],
  '8': [
    {'1': '_strict_mode'},
    {'1': '_json_schema'},
    {'1': '_type_name'},
    {'1': '_name'},
    {'1': '_regex_pattern'},
    {'1': '_grammar'},
  ],
};

/// Descriptor for `StructuredOutputOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputOptionsDescriptor = $convert.base64Decode(
    'ChdTdHJ1Y3R1cmVkT3V0cHV0T3B0aW9ucxIyCgZzY2hlbWEYASABKAsyGi5ydW5hbnl3aGVyZS'
    '52MS5KU09OU2NoZW1hUgZzY2hlbWESNwoYaW5jbHVkZV9zY2hlbWFfaW5fcHJvbXB0GAIgASgI'
    'UhVpbmNsdWRlU2NoZW1hSW5Qcm9tcHQSJAoLc3RyaWN0X21vZGUYAyABKAhIAFIKc3RyaWN0TW'
    '9kZYgBARIkCgtqc29uX3NjaGVtYRgEIAEoCUgBUgpqc29uU2NoZW1hiAEBEiAKCXR5cGVfbmFt'
    'ZRgFIAEoCUgCUgh0eXBlTmFtZYgBARIXCgRuYW1lGAYgASgJSANSBG5hbWWIAQESOAoEbW9kZR'
    'gHIAEoDjIkLnJ1bmFueXdoZXJlLnYxLlN0cnVjdHVyZWRPdXRwdXRNb2RlUgRtb2RlEigKDXJl'
    'Z2V4X3BhdHRlcm4YCCABKAlIBFIMcmVnZXhQYXR0ZXJuiAEBEh0KB2dyYW1tYXIYCSABKAlIBV'
    'IHZ3JhbW1hcogBARIfCgtyZXBhaXJfanNvbhgKIAEoCFIKcmVwYWlySnNvbhIfCgttYXhfcmV0'
    'cmllcxgLIAEoBVIKbWF4UmV0cmllc0IOCgxfc3RyaWN0X21vZGVCDgoMX2pzb25fc2NoZW1hQg'
    'wKCl90eXBlX25hbWVCBwoFX25hbWVCEAoOX3JlZ2V4X3BhdHRlcm5CCgoIX2dyYW1tYXI=');

@$core.Deprecated('Use structuredOutputValidationDescriptor instead')
const StructuredOutputValidation$json = {
  '1': 'StructuredOutputValidation',
  '2': [
    {'1': 'is_valid', '3': 1, '4': 1, '5': 8, '10': 'isValid'},
    {'1': 'contains_json', '3': 2, '4': 1, '5': 8, '10': 'containsJson'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'raw_output', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'rawOutput', '17': true},
    {'1': 'extracted_json', '3': 5, '4': 1, '5': 9, '9': 2, '10': 'extractedJson', '17': true},
    {'1': 'validation_errors', '3': 6, '4': 3, '5': 9, '10': 'validationErrors'},
    {'1': 'validation_time_ms', '3': 7, '4': 1, '5': 3, '10': 'validationTimeMs'},
  ],
  '8': [
    {'1': '_error_message'},
    {'1': '_raw_output'},
    {'1': '_extracted_json'},
  ],
};

/// Descriptor for `StructuredOutputValidation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputValidationDescriptor = $convert.base64Decode(
    'ChpTdHJ1Y3R1cmVkT3V0cHV0VmFsaWRhdGlvbhIZCghpc192YWxpZBgBIAEoCFIHaXNWYWxpZB'
    'IjCg1jb250YWluc19qc29uGAIgASgIUgxjb250YWluc0pzb24SKAoNZXJyb3JfbWVzc2FnZRgD'
    'IAEoCUgAUgxlcnJvck1lc3NhZ2WIAQESIgoKcmF3X291dHB1dBgEIAEoCUgBUglyYXdPdXRwdX'
    'SIAQESKgoOZXh0cmFjdGVkX2pzb24YBSABKAlIAlINZXh0cmFjdGVkSnNvbogBARIrChF2YWxp'
    'ZGF0aW9uX2Vycm9ycxgGIAMoCVIQdmFsaWRhdGlvbkVycm9ycxIsChJ2YWxpZGF0aW9uX3RpbW'
    'VfbXMYByABKANSEHZhbGlkYXRpb25UaW1lTXNCEAoOX2Vycm9yX21lc3NhZ2VCDQoLX3Jhd19v'
    'dXRwdXRCEQoPX2V4dHJhY3RlZF9qc29u');

@$core.Deprecated('Use structuredOutputResultDescriptor instead')
const StructuredOutputResult$json = {
  '1': 'StructuredOutputResult',
  '2': [
    {'1': 'parsed_json', '3': 1, '4': 1, '5': 12, '10': 'parsedJson'},
    {'1': 'validation', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputValidation', '10': 'validation'},
    {'1': 'raw_text', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'rawText', '17': true},
    {'1': 'error_message', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_raw_text'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `StructuredOutputResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputResultDescriptor = $convert.base64Decode(
    'ChZTdHJ1Y3R1cmVkT3V0cHV0UmVzdWx0Eh8KC3BhcnNlZF9qc29uGAEgASgMUgpwYXJzZWRKc2'
    '9uEkoKCnZhbGlkYXRpb24YAiABKAsyKi5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0'
    'VmFsaWRhdGlvblIKdmFsaWRhdGlvbhIeCghyYXdfdGV4dBgDIAEoCUgAUgdyYXdUZXh0iAEBEi'
    'gKDWVycm9yX21lc3NhZ2UYBCABKAlIAVIMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUY'
    'BSABKAVSCWVycm9yQ29kZUILCglfcmF3X3RleHRCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use structuredOutputParseRequestDescriptor instead')
const StructuredOutputParseRequest$json = {
  '1': 'StructuredOutputParseRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'options', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.StructuredOutputParseRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [StructuredOutputParseRequest_MetadataEntry$json],
  '8': [
    {'1': '_options'},
  ],
};

@$core.Deprecated('Use structuredOutputParseRequestDescriptor instead')
const StructuredOutputParseRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `StructuredOutputParseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputParseRequestDescriptor = $convert.base64Decode(
    'ChxTdHJ1Y3R1cmVkT3V0cHV0UGFyc2VSZXF1ZXN0Eh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcX'
    'Vlc3RJZBISCgR0ZXh0GAIgASgJUgR0ZXh0EkYKB29wdGlvbnMYAyABKAsyJy5ydW5hbnl3aGVy'
    'ZS52MS5TdHJ1Y3R1cmVkT3V0cHV0T3B0aW9uc0gAUgdvcHRpb25ziAEBElYKCG1ldGFkYXRhGA'
    'QgAygLMjoucnVuYW55d2hlcmUudjEuU3RydWN0dXJlZE91dHB1dFBhcnNlUmVxdWVzdC5NZXRh'
    'ZGF0YUVudHJ5UghtZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5Eh'
    'QKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAFCCgoIX29wdGlvbnM=');

@$core.Deprecated('Use structuredOutputValidationRequestDescriptor instead')
const StructuredOutputValidationRequest$json = {
  '1': 'StructuredOutputValidationRequest',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputOptions', '9': 0, '10': 'options', '17': true},
  ],
  '8': [
    {'1': '_options'},
  ],
};

/// Descriptor for `StructuredOutputValidationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputValidationRequestDescriptor = $convert.base64Decode(
    'CiFTdHJ1Y3R1cmVkT3V0cHV0VmFsaWRhdGlvblJlcXVlc3QSEgoEdGV4dBgBIAEoCVIEdGV4dB'
    'JGCgdvcHRpb25zGAIgASgLMicucnVuYW55d2hlcmUudjEuU3RydWN0dXJlZE91dHB1dE9wdGlv'
    'bnNIAFIHb3B0aW9uc4gBAUIKCghfb3B0aW9ucw==');

@$core.Deprecated('Use structuredOutputPromptResultDescriptor instead')
const StructuredOutputPromptResult$json = {
  '1': 'StructuredOutputPromptResult',
  '2': [
    {'1': 'prepared_prompt', '3': 1, '4': 1, '5': 9, '10': 'preparedPrompt'},
    {'1': 'system_prompt', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    {'1': 'json_schema', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'jsonSchema', '17': true},
    {'1': 'regex_pattern', '3': 4, '4': 1, '5': 9, '9': 2, '10': 'regexPattern', '17': true},
    {'1': 'grammar', '3': 5, '4': 1, '5': 9, '9': 3, '10': 'grammar', '17': true},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '9': 4, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 7, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_system_prompt'},
    {'1': '_json_schema'},
    {'1': '_regex_pattern'},
    {'1': '_grammar'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `StructuredOutputPromptResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputPromptResultDescriptor = $convert.base64Decode(
    'ChxTdHJ1Y3R1cmVkT3V0cHV0UHJvbXB0UmVzdWx0EicKD3ByZXBhcmVkX3Byb21wdBgBIAEoCV'
    'IOcHJlcGFyZWRQcm9tcHQSKAoNc3lzdGVtX3Byb21wdBgCIAEoCUgAUgxzeXN0ZW1Qcm9tcHSI'
    'AQESJAoLanNvbl9zY2hlbWEYAyABKAlIAVIKanNvblNjaGVtYYgBARIoCg1yZWdleF9wYXR0ZX'
    'JuGAQgASgJSAJSDHJlZ2V4UGF0dGVybogBARIdCgdncmFtbWFyGAUgASgJSANSB2dyYW1tYXKI'
    'AQESKAoNZXJyb3JfbWVzc2FnZRgGIAEoCUgEUgxlcnJvck1lc3NhZ2WIAQESHQoKZXJyb3JfY2'
    '9kZRgHIAEoBVIJZXJyb3JDb2RlQhAKDl9zeXN0ZW1fcHJvbXB0Qg4KDF9qc29uX3NjaGVtYUIQ'
    'Cg5fcmVnZXhfcGF0dGVybkIKCghfZ3JhbW1hckIQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use structuredOutputRequestDescriptor instead')
const StructuredOutputRequest$json = {
  '1': 'StructuredOutputRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'prompt', '3': 2, '4': 1, '5': 9, '10': 'prompt'},
    {'1': 'options', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.StructuredOutputRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [StructuredOutputRequest_MetadataEntry$json],
  '8': [
    {'1': '_options'},
  ],
};

@$core.Deprecated('Use structuredOutputRequestDescriptor instead')
const StructuredOutputRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `StructuredOutputRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputRequestDescriptor = $convert.base64Decode(
    'ChdTdHJ1Y3R1cmVkT3V0cHV0UmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SW'
    'QSFgoGcHJvbXB0GAIgASgJUgZwcm9tcHQSRgoHb3B0aW9ucxgDIAEoCzInLnJ1bmFueXdoZXJl'
    'LnYxLlN0cnVjdHVyZWRPdXRwdXRPcHRpb25zSABSB29wdGlvbnOIAQESUQoIbWV0YWRhdGEYBC'
    'ADKAsyNS5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0UmVxdWVzdC5NZXRhZGF0YUVu'
    'dHJ5UghtZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbH'
    'VlGAIgASgJUgV2YWx1ZToCOAFCCgoIX29wdGlvbnM=');

@$core.Deprecated('Use structuredOutputStreamEventDescriptor instead')
const StructuredOutputStreamEvent$json = {
  '1': 'StructuredOutputStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.StructuredOutputStreamEventKind', '10': 'kind'},
    {'1': 'token', '3': 5, '4': 1, '5': 9, '10': 'token'},
    {'1': 'partial_json', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'partialJson', '17': true},
    {'1': 'validation', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputValidation', '9': 1, '10': 'validation', '17': true},
    {'1': 'result', '3': 8, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputResult', '9': 2, '10': 'result', '17': true},
    {'1': 'error_message', '3': 9, '4': 1, '5': 9, '9': 3, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 10, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_partial_json'},
    {'1': '_validation'},
    {'1': '_result'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `StructuredOutputStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputStreamEventDescriptor = $convert.base64Decode(
    'ChtTdHJ1Y3R1cmVkT3V0cHV0U3RyZWFtRXZlbnQSEAoDc2VxGAEgASgEUgNzZXESIQoMdGltZX'
    'N0YW1wX3VzGAIgASgDUgt0aW1lc3RhbXBVcxIdCgpyZXF1ZXN0X2lkGAMgASgJUglyZXF1ZXN0'
    'SWQSQwoEa2luZBgEIAEoDjIvLnJ1bmFueXdoZXJlLnYxLlN0cnVjdHVyZWRPdXRwdXRTdHJlYW'
    '1FdmVudEtpbmRSBGtpbmQSFAoFdG9rZW4YBSABKAlSBXRva2VuEiYKDHBhcnRpYWxfanNvbhgG'
    'IAEoCUgAUgtwYXJ0aWFsSnNvbogBARJPCgp2YWxpZGF0aW9uGAcgASgLMioucnVuYW55d2hlcm'
    'UudjEuU3RydWN0dXJlZE91dHB1dFZhbGlkYXRpb25IAVIKdmFsaWRhdGlvbogBARJDCgZyZXN1'
    'bHQYCCABKAsyJi5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0UmVzdWx0SAJSBnJlc3'
    'VsdIgBARIoCg1lcnJvcl9tZXNzYWdlGAkgASgJSANSDGVycm9yTWVzc2FnZYgBARIdCgplcnJv'
    'cl9jb2RlGAogASgFUgllcnJvckNvZGVCDwoNX3BhcnRpYWxfanNvbkINCgtfdmFsaWRhdGlvbk'
    'IJCgdfcmVzdWx0QhAKDl9lcnJvcl9tZXNzYWdl');

@$core.Deprecated('Use namedEntityDescriptor instead')
const NamedEntity$json = {
  '1': 'NamedEntity',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'entity_type', '3': 2, '4': 1, '5': 9, '10': 'entityType'},
    {'1': 'start_offset', '3': 3, '4': 1, '5': 5, '10': 'startOffset'},
    {'1': 'end_offset', '3': 4, '4': 1, '5': 5, '10': 'endOffset'},
    {'1': 'confidence', '3': 5, '4': 1, '5': 2, '10': 'confidence'},
  ],
};

/// Descriptor for `NamedEntity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List namedEntityDescriptor = $convert.base64Decode(
    'CgtOYW1lZEVudGl0eRISCgR0ZXh0GAEgASgJUgR0ZXh0Eh8KC2VudGl0eV90eXBlGAIgASgJUg'
    'plbnRpdHlUeXBlEiEKDHN0YXJ0X29mZnNldBgDIAEoBVILc3RhcnRPZmZzZXQSHQoKZW5kX29m'
    'ZnNldBgEIAEoBVIJZW5kT2Zmc2V0Eh4KCmNvbmZpZGVuY2UYBSABKAJSCmNvbmZpZGVuY2U=');

@$core.Deprecated('Use entityExtractionResultDescriptor instead')
const EntityExtractionResult$json = {
  '1': 'EntityExtractionResult',
  '2': [
    {'1': 'entities', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.NamedEntity', '10': 'entities'},
  ],
};

/// Descriptor for `EntityExtractionResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List entityExtractionResultDescriptor = $convert.base64Decode(
    'ChZFbnRpdHlFeHRyYWN0aW9uUmVzdWx0EjcKCGVudGl0aWVzGAEgAygLMhsucnVuYW55d2hlcm'
    'UudjEuTmFtZWRFbnRpdHlSCGVudGl0aWVz');

@$core.Deprecated('Use classificationCandidateDescriptor instead')
const ClassificationCandidate$json = {
  '1': 'ClassificationCandidate',
  '2': [
    {'1': 'label', '3': 1, '4': 1, '5': 9, '10': 'label'},
    {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
  ],
};

/// Descriptor for `ClassificationCandidate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List classificationCandidateDescriptor = $convert.base64Decode(
    'ChdDbGFzc2lmaWNhdGlvbkNhbmRpZGF0ZRIUCgVsYWJlbBgBIAEoCVIFbGFiZWwSHgoKY29uZm'
    'lkZW5jZRgCIAEoAlIKY29uZmlkZW5jZQ==');

@$core.Deprecated('Use classificationResultDescriptor instead')
const ClassificationResult$json = {
  '1': 'ClassificationResult',
  '2': [
    {'1': 'label', '3': 1, '4': 1, '5': 9, '10': 'label'},
    {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'alternatives', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ClassificationCandidate', '10': 'alternatives'},
  ],
};

/// Descriptor for `ClassificationResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List classificationResultDescriptor = $convert.base64Decode(
    'ChRDbGFzc2lmaWNhdGlvblJlc3VsdBIUCgVsYWJlbBgBIAEoCVIFbGFiZWwSHgoKY29uZmlkZW'
    '5jZRgCIAEoAlIKY29uZmlkZW5jZRJLCgxhbHRlcm5hdGl2ZXMYAyADKAsyJy5ydW5hbnl3aGVy'
    'ZS52MS5DbGFzc2lmaWNhdGlvbkNhbmRpZGF0ZVIMYWx0ZXJuYXRpdmVz');

@$core.Deprecated('Use sentimentResultDescriptor instead')
const SentimentResult$json = {
  '1': 'SentimentResult',
  '2': [
    {'1': 'sentiment', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.Sentiment', '10': 'sentiment'},
    {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'positive_score', '3': 3, '4': 1, '5': 2, '9': 0, '10': 'positiveScore', '17': true},
    {'1': 'negative_score', '3': 4, '4': 1, '5': 2, '9': 1, '10': 'negativeScore', '17': true},
    {'1': 'neutral_score', '3': 5, '4': 1, '5': 2, '9': 2, '10': 'neutralScore', '17': true},
  ],
  '8': [
    {'1': '_positive_score'},
    {'1': '_negative_score'},
    {'1': '_neutral_score'},
  ],
};

/// Descriptor for `SentimentResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sentimentResultDescriptor = $convert.base64Decode(
    'Cg9TZW50aW1lbnRSZXN1bHQSNwoJc2VudGltZW50GAEgASgOMhkucnVuYW55d2hlcmUudjEuU2'
    'VudGltZW50UglzZW50aW1lbnQSHgoKY29uZmlkZW5jZRgCIAEoAlIKY29uZmlkZW5jZRIqCg5w'
    'b3NpdGl2ZV9zY29yZRgDIAEoAkgAUg1wb3NpdGl2ZVNjb3JliAEBEioKDm5lZ2F0aXZlX3Njb3'
    'JlGAQgASgCSAFSDW5lZ2F0aXZlU2NvcmWIAQESKAoNbmV1dHJhbF9zY29yZRgFIAEoAkgCUgxu'
    'ZXV0cmFsU2NvcmWIAQFCEQoPX3Bvc2l0aXZlX3Njb3JlQhEKD19uZWdhdGl2ZV9zY29yZUIQCg'
    '5fbmV1dHJhbF9zY29yZQ==');

@$core.Deprecated('Use nERResultDescriptor instead')
const NERResult$json = {
  '1': 'NERResult',
  '2': [
    {'1': 'entities', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.NamedEntity', '10': 'entities'},
  ],
};

/// Descriptor for `NERResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nERResultDescriptor = $convert.base64Decode(
    'CglORVJSZXN1bHQSNwoIZW50aXRpZXMYASADKAsyGy5ydW5hbnl3aGVyZS52MS5OYW1lZEVudG'
    'l0eVIIZW50aXRpZXM=');

const $core.Map<$core.String, $core.dynamic> StructuredOutputServiceBase$json = {
  '1': 'StructuredOutput',
  '2': [
    {'1': 'PreparePrompt', '2': '.runanywhere.v1.StructuredOutputRequest', '3': '.runanywhere.v1.StructuredOutputPromptResult'},
    {'1': 'Validate', '2': '.runanywhere.v1.StructuredOutputValidationRequest', '3': '.runanywhere.v1.StructuredOutputValidation'},
    {'1': 'Parse', '2': '.runanywhere.v1.StructuredOutputParseRequest', '3': '.runanywhere.v1.StructuredOutputResult'},
    {'1': 'Generate', '2': '.runanywhere.v1.StructuredOutputRequest', '3': '.runanywhere.v1.StructuredOutputResult'},
    {'1': 'GenerateStream', '2': '.runanywhere.v1.StructuredOutputRequest', '3': '.runanywhere.v1.StructuredOutputStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use structuredOutputServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> StructuredOutputServiceBase$messageJson = {
  '.runanywhere.v1.StructuredOutputRequest': StructuredOutputRequest$json,
  '.runanywhere.v1.StructuredOutputOptions': StructuredOutputOptions$json,
  '.runanywhere.v1.JSONSchema': JSONSchema$json,
  '.runanywhere.v1.JSONSchema.PropertiesEntry': JSONSchema_PropertiesEntry$json,
  '.runanywhere.v1.JSONSchemaProperty': JSONSchemaProperty$json,
  '.runanywhere.v1.JSONSchema.DefinitionsEntry': JSONSchema_DefinitionsEntry$json,
  '.runanywhere.v1.StructuredOutputRequest.MetadataEntry': StructuredOutputRequest_MetadataEntry$json,
  '.runanywhere.v1.StructuredOutputPromptResult': StructuredOutputPromptResult$json,
  '.runanywhere.v1.StructuredOutputValidationRequest': StructuredOutputValidationRequest$json,
  '.runanywhere.v1.StructuredOutputValidation': StructuredOutputValidation$json,
  '.runanywhere.v1.StructuredOutputParseRequest': StructuredOutputParseRequest$json,
  '.runanywhere.v1.StructuredOutputParseRequest.MetadataEntry': StructuredOutputParseRequest_MetadataEntry$json,
  '.runanywhere.v1.StructuredOutputResult': StructuredOutputResult$json,
  '.runanywhere.v1.StructuredOutputStreamEvent': StructuredOutputStreamEvent$json,
};

/// Descriptor for `StructuredOutput`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List structuredOutputServiceDescriptor = $convert.base64Decode(
    'ChBTdHJ1Y3R1cmVkT3V0cHV0EmYKDVByZXBhcmVQcm9tcHQSJy5ydW5hbnl3aGVyZS52MS5TdH'
    'J1Y3R1cmVkT3V0cHV0UmVxdWVzdBosLnJ1bmFueXdoZXJlLnYxLlN0cnVjdHVyZWRPdXRwdXRQ'
    'cm9tcHRSZXN1bHQSaQoIVmFsaWRhdGUSMS5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cH'
    'V0VmFsaWRhdGlvblJlcXVlc3QaKi5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0VmFs'
    'aWRhdGlvbhJdCgVQYXJzZRIsLnJ1bmFueXdoZXJlLnYxLlN0cnVjdHVyZWRPdXRwdXRQYXJzZV'
    'JlcXVlc3QaJi5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0UmVzdWx0ElsKCEdlbmVy'
    'YXRlEicucnVuYW55d2hlcmUudjEuU3RydWN0dXJlZE91dHB1dFJlcXVlc3QaJi5ydW5hbnl3aG'
    'VyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0UmVzdWx0EmgKDkdlbmVyYXRlU3RyZWFtEicucnVuYW55'
    'd2hlcmUudjEuU3RydWN0dXJlZE91dHB1dFJlcXVlc3QaKy5ydW5hbnl3aGVyZS52MS5TdHJ1Y3'
    'R1cmVkT3V0cHV0U3RyZWFtRXZlbnQwAQ==');

