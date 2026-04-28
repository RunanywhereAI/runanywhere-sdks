///
//  Generated code. Do not modify.
//  source: structured_output.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use jSONSchemaTypeDescriptor instead')
const JSONSchemaType$json = const {
  '1': 'JSONSchemaType',
  '2': const [
    const {'1': 'JSON_SCHEMA_TYPE_UNSPECIFIED', '2': 0},
    const {'1': 'JSON_SCHEMA_TYPE_OBJECT', '2': 1},
    const {'1': 'JSON_SCHEMA_TYPE_ARRAY', '2': 2},
    const {'1': 'JSON_SCHEMA_TYPE_STRING', '2': 3},
    const {'1': 'JSON_SCHEMA_TYPE_NUMBER', '2': 4},
    const {'1': 'JSON_SCHEMA_TYPE_INTEGER', '2': 5},
    const {'1': 'JSON_SCHEMA_TYPE_BOOLEAN', '2': 6},
    const {'1': 'JSON_SCHEMA_TYPE_NULL', '2': 7},
  ],
};

/// Descriptor for `JSONSchemaType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List jSONSchemaTypeDescriptor = $convert.base64Decode('Cg5KU09OU2NoZW1hVHlwZRIgChxKU09OX1NDSEVNQV9UWVBFX1VOU1BFQ0lGSUVEEAASGwoXSlNPTl9TQ0hFTUFfVFlQRV9PQkpFQ1QQARIaChZKU09OX1NDSEVNQV9UWVBFX0FSUkFZEAISGwoXSlNPTl9TQ0hFTUFfVFlQRV9TVFJJTkcQAxIbChdKU09OX1NDSEVNQV9UWVBFX05VTUJFUhAEEhwKGEpTT05fU0NIRU1BX1RZUEVfSU5URUdFUhAFEhwKGEpTT05fU0NIRU1BX1RZUEVfQk9PTEVBThAGEhkKFUpTT05fU0NIRU1BX1RZUEVfTlVMTBAH');
@$core.Deprecated('Use sentimentDescriptor instead')
const Sentiment$json = const {
  '1': 'Sentiment',
  '2': const [
    const {'1': 'SENTIMENT_UNSPECIFIED', '2': 0},
    const {'1': 'SENTIMENT_POSITIVE', '2': 1},
    const {'1': 'SENTIMENT_NEGATIVE', '2': 2},
    const {'1': 'SENTIMENT_NEUTRAL', '2': 3},
    const {'1': 'SENTIMENT_MIXED', '2': 4},
  ],
};

/// Descriptor for `Sentiment`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sentimentDescriptor = $convert.base64Decode('CglTZW50aW1lbnQSGQoVU0VOVElNRU5UX1VOU1BFQ0lGSUVEEAASFgoSU0VOVElNRU5UX1BPU0lUSVZFEAESFgoSU0VOVElNRU5UX05FR0FUSVZFEAISFQoRU0VOVElNRU5UX05FVVRSQUwQAxITCg9TRU5USU1FTlRfTUlYRUQQBA==');
@$core.Deprecated('Use jSONSchemaPropertyDescriptor instead')
const JSONSchemaProperty$json = const {
  '1': 'JSONSchemaProperty',
  '2': const [
    const {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.JSONSchemaType', '10': 'type'},
    const {'1': 'description', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'description', '17': true},
    const {'1': 'enum_values', '3': 3, '4': 3, '5': 9, '10': 'enumValues'},
    const {'1': 'format', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'format', '17': true},
    const {'1': 'items_schema', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '9': 2, '10': 'itemsSchema', '17': true},
    const {'1': 'object_schema', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '9': 3, '10': 'objectSchema', '17': true},
  ],
  '8': const [
    const {'1': '_description'},
    const {'1': '_format'},
    const {'1': '_items_schema'},
    const {'1': '_object_schema'},
  ],
};

/// Descriptor for `JSONSchemaProperty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jSONSchemaPropertyDescriptor = $convert.base64Decode('ChJKU09OU2NoZW1hUHJvcGVydHkSMgoEdHlwZRgBIAEoDjIeLnJ1bmFueXdoZXJlLnYxLkpTT05TY2hlbWFUeXBlUgR0eXBlEiUKC2Rlc2NyaXB0aW9uGAIgASgJSABSC2Rlc2NyaXB0aW9uiAEBEh8KC2VudW1fdmFsdWVzGAMgAygJUgplbnVtVmFsdWVzEhsKBmZvcm1hdBgEIAEoCUgBUgZmb3JtYXSIAQESQgoMaXRlbXNfc2NoZW1hGAUgASgLMhoucnVuYW55d2hlcmUudjEuSlNPTlNjaGVtYUgCUgtpdGVtc1NjaGVtYYgBARJECg1vYmplY3Rfc2NoZW1hGAYgASgLMhoucnVuYW55d2hlcmUudjEuSlNPTlNjaGVtYUgDUgxvYmplY3RTY2hlbWGIAQFCDgoMX2Rlc2NyaXB0aW9uQgkKB19mb3JtYXRCDwoNX2l0ZW1zX3NjaGVtYUIQCg5fb2JqZWN0X3NjaGVtYQ==');
@$core.Deprecated('Use jSONSchemaDescriptor instead')
const JSONSchema$json = const {
  '1': 'JSONSchema',
  '2': const [
    const {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.JSONSchemaType', '10': 'type'},
    const {'1': 'properties', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.JSONSchema.PropertiesEntry', '10': 'properties'},
    const {'1': 'required', '3': 3, '4': 3, '5': 9, '10': 'required'},
    const {'1': 'items', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchemaProperty', '9': 0, '10': 'items', '17': true},
    const {'1': 'additional_properties', '3': 5, '4': 1, '5': 8, '9': 1, '10': 'additionalProperties', '17': true},
  ],
  '3': const [JSONSchema_PropertiesEntry$json],
  '8': const [
    const {'1': '_items'},
    const {'1': '_additional_properties'},
  ],
};

@$core.Deprecated('Use jSONSchemaDescriptor instead')
const JSONSchema_PropertiesEntry$json = const {
  '1': 'PropertiesEntry',
  '2': const [
    const {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    const {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchemaProperty', '10': 'value'},
  ],
  '7': const {'7': true},
};

/// Descriptor for `JSONSchema`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jSONSchemaDescriptor = $convert.base64Decode('CgpKU09OU2NoZW1hEjIKBHR5cGUYASABKA4yHi5ydW5hbnl3aGVyZS52MS5KU09OU2NoZW1hVHlwZVIEdHlwZRJKCgpwcm9wZXJ0aWVzGAIgAygLMioucnVuYW55d2hlcmUudjEuSlNPTlNjaGVtYS5Qcm9wZXJ0aWVzRW50cnlSCnByb3BlcnRpZXMSGgoIcmVxdWlyZWQYAyADKAlSCHJlcXVpcmVkEj0KBWl0ZW1zGAQgASgLMiIucnVuYW55d2hlcmUudjEuSlNPTlNjaGVtYVByb3BlcnR5SABSBWl0ZW1ziAEBEjgKFWFkZGl0aW9uYWxfcHJvcGVydGllcxgFIAEoCEgBUhRhZGRpdGlvbmFsUHJvcGVydGllc4gBARphCg9Qcm9wZXJ0aWVzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSOAoFdmFsdWUYAiABKAsyIi5ydW5hbnl3aGVyZS52MS5KU09OU2NoZW1hUHJvcGVydHlSBXZhbHVlOgI4AUIICgZfaXRlbXNCGAoWX2FkZGl0aW9uYWxfcHJvcGVydGllcw==');
@$core.Deprecated('Use structuredOutputOptionsDescriptor instead')
const StructuredOutputOptions$json = const {
  '1': 'StructuredOutputOptions',
  '2': const [
    const {'1': 'schema', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.JSONSchema', '10': 'schema'},
    const {'1': 'include_schema_in_prompt', '3': 2, '4': 1, '5': 8, '10': 'includeSchemaInPrompt'},
    const {'1': 'strict_mode', '3': 3, '4': 1, '5': 8, '9': 0, '10': 'strictMode', '17': true},
  ],
  '8': const [
    const {'1': '_strict_mode'},
  ],
};

/// Descriptor for `StructuredOutputOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputOptionsDescriptor = $convert.base64Decode('ChdTdHJ1Y3R1cmVkT3V0cHV0T3B0aW9ucxIyCgZzY2hlbWEYASABKAsyGi5ydW5hbnl3aGVyZS52MS5KU09OU2NoZW1hUgZzY2hlbWESNwoYaW5jbHVkZV9zY2hlbWFfaW5fcHJvbXB0GAIgASgIUhVpbmNsdWRlU2NoZW1hSW5Qcm9tcHQSJAoLc3RyaWN0X21vZGUYAyABKAhIAFIKc3RyaWN0TW9kZYgBAUIOCgxfc3RyaWN0X21vZGU=');
@$core.Deprecated('Use structuredOutputValidationDescriptor instead')
const StructuredOutputValidation$json = const {
  '1': 'StructuredOutputValidation',
  '2': const [
    const {'1': 'is_valid', '3': 1, '4': 1, '5': 8, '10': 'isValid'},
    const {'1': 'contains_json', '3': 2, '4': 1, '5': 8, '10': 'containsJson'},
    const {'1': 'error_message', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    const {'1': 'raw_output', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'rawOutput', '17': true},
  ],
  '8': const [
    const {'1': '_error_message'},
    const {'1': '_raw_output'},
  ],
};

/// Descriptor for `StructuredOutputValidation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputValidationDescriptor = $convert.base64Decode('ChpTdHJ1Y3R1cmVkT3V0cHV0VmFsaWRhdGlvbhIZCghpc192YWxpZBgBIAEoCFIHaXNWYWxpZBIjCg1jb250YWluc19qc29uGAIgASgIUgxjb250YWluc0pzb24SKAoNZXJyb3JfbWVzc2FnZRgDIAEoCUgAUgxlcnJvck1lc3NhZ2WIAQESIgoKcmF3X291dHB1dBgEIAEoCUgBUglyYXdPdXRwdXSIAQFCEAoOX2Vycm9yX21lc3NhZ2VCDQoLX3Jhd19vdXRwdXQ=');
@$core.Deprecated('Use structuredOutputResultDescriptor instead')
const StructuredOutputResult$json = const {
  '1': 'StructuredOutputResult',
  '2': const [
    const {'1': 'parsed_json', '3': 1, '4': 1, '5': 12, '10': 'parsedJson'},
    const {'1': 'validation', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputValidation', '10': 'validation'},
    const {'1': 'raw_text', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'rawText', '17': true},
  ],
  '8': const [
    const {'1': '_raw_text'},
  ],
};

/// Descriptor for `StructuredOutputResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputResultDescriptor = $convert.base64Decode('ChZTdHJ1Y3R1cmVkT3V0cHV0UmVzdWx0Eh8KC3BhcnNlZF9qc29uGAEgASgMUgpwYXJzZWRKc29uEkoKCnZhbGlkYXRpb24YAiABKAsyKi5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0VmFsaWRhdGlvblIKdmFsaWRhdGlvbhIeCghyYXdfdGV4dBgDIAEoCUgAUgdyYXdUZXh0iAEBQgsKCV9yYXdfdGV4dA==');
@$core.Deprecated('Use namedEntityDescriptor instead')
const NamedEntity$json = const {
  '1': 'NamedEntity',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'entity_type', '3': 2, '4': 1, '5': 9, '10': 'entityType'},
    const {'1': 'start_offset', '3': 3, '4': 1, '5': 5, '10': 'startOffset'},
    const {'1': 'end_offset', '3': 4, '4': 1, '5': 5, '10': 'endOffset'},
    const {'1': 'confidence', '3': 5, '4': 1, '5': 2, '10': 'confidence'},
  ],
};

/// Descriptor for `NamedEntity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List namedEntityDescriptor = $convert.base64Decode('CgtOYW1lZEVudGl0eRISCgR0ZXh0GAEgASgJUgR0ZXh0Eh8KC2VudGl0eV90eXBlGAIgASgJUgplbnRpdHlUeXBlEiEKDHN0YXJ0X29mZnNldBgDIAEoBVILc3RhcnRPZmZzZXQSHQoKZW5kX29mZnNldBgEIAEoBVIJZW5kT2Zmc2V0Eh4KCmNvbmZpZGVuY2UYBSABKAJSCmNvbmZpZGVuY2U=');
@$core.Deprecated('Use entityExtractionResultDescriptor instead')
const EntityExtractionResult$json = const {
  '1': 'EntityExtractionResult',
  '2': const [
    const {'1': 'entities', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.NamedEntity', '10': 'entities'},
  ],
};

/// Descriptor for `EntityExtractionResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List entityExtractionResultDescriptor = $convert.base64Decode('ChZFbnRpdHlFeHRyYWN0aW9uUmVzdWx0EjcKCGVudGl0aWVzGAEgAygLMhsucnVuYW55d2hlcmUudjEuTmFtZWRFbnRpdHlSCGVudGl0aWVz');
@$core.Deprecated('Use classificationCandidateDescriptor instead')
const ClassificationCandidate$json = const {
  '1': 'ClassificationCandidate',
  '2': const [
    const {'1': 'label', '3': 1, '4': 1, '5': 9, '10': 'label'},
    const {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
  ],
};

/// Descriptor for `ClassificationCandidate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List classificationCandidateDescriptor = $convert.base64Decode('ChdDbGFzc2lmaWNhdGlvbkNhbmRpZGF0ZRIUCgVsYWJlbBgBIAEoCVIFbGFiZWwSHgoKY29uZmlkZW5jZRgCIAEoAlIKY29uZmlkZW5jZQ==');
@$core.Deprecated('Use classificationResultDescriptor instead')
const ClassificationResult$json = const {
  '1': 'ClassificationResult',
  '2': const [
    const {'1': 'label', '3': 1, '4': 1, '5': 9, '10': 'label'},
    const {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    const {'1': 'alternatives', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ClassificationCandidate', '10': 'alternatives'},
  ],
};

/// Descriptor for `ClassificationResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List classificationResultDescriptor = $convert.base64Decode('ChRDbGFzc2lmaWNhdGlvblJlc3VsdBIUCgVsYWJlbBgBIAEoCVIFbGFiZWwSHgoKY29uZmlkZW5jZRgCIAEoAlIKY29uZmlkZW5jZRJLCgxhbHRlcm5hdGl2ZXMYAyADKAsyJy5ydW5hbnl3aGVyZS52MS5DbGFzc2lmaWNhdGlvbkNhbmRpZGF0ZVIMYWx0ZXJuYXRpdmVz');
@$core.Deprecated('Use sentimentResultDescriptor instead')
const SentimentResult$json = const {
  '1': 'SentimentResult',
  '2': const [
    const {'1': 'sentiment', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.Sentiment', '10': 'sentiment'},
    const {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    const {'1': 'positive_score', '3': 3, '4': 1, '5': 2, '9': 0, '10': 'positiveScore', '17': true},
    const {'1': 'negative_score', '3': 4, '4': 1, '5': 2, '9': 1, '10': 'negativeScore', '17': true},
    const {'1': 'neutral_score', '3': 5, '4': 1, '5': 2, '9': 2, '10': 'neutralScore', '17': true},
  ],
  '8': const [
    const {'1': '_positive_score'},
    const {'1': '_negative_score'},
    const {'1': '_neutral_score'},
  ],
};

/// Descriptor for `SentimentResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sentimentResultDescriptor = $convert.base64Decode('Cg9TZW50aW1lbnRSZXN1bHQSNwoJc2VudGltZW50GAEgASgOMhkucnVuYW55d2hlcmUudjEuU2VudGltZW50UglzZW50aW1lbnQSHgoKY29uZmlkZW5jZRgCIAEoAlIKY29uZmlkZW5jZRIqCg5wb3NpdGl2ZV9zY29yZRgDIAEoAkgAUg1wb3NpdGl2ZVNjb3JliAEBEioKDm5lZ2F0aXZlX3Njb3JlGAQgASgCSAFSDW5lZ2F0aXZlU2NvcmWIAQESKAoNbmV1dHJhbF9zY29yZRgFIAEoAkgCUgxuZXV0cmFsU2NvcmWIAQFCEQoPX3Bvc2l0aXZlX3Njb3JlQhEKD19uZWdhdGl2ZV9zY29yZUIQCg5fbmV1dHJhbF9zY29yZQ==');
@$core.Deprecated('Use nERResultDescriptor instead')
const NERResult$json = const {
  '1': 'NERResult',
  '2': const [
    const {'1': 'entities', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.NamedEntity', '10': 'entities'},
  ],
};

/// Descriptor for `NERResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nERResultDescriptor = $convert.base64Decode('CglORVJSZXN1bHQSNwoIZW50aXRpZXMYASADKAsyGy5ydW5hbnl3aGVyZS52MS5OYW1lZEVudGl0eVIIZW50aXRpZXM=');
