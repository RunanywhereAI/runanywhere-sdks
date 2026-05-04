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
  ],
  '8': [
    {'1': '_description'},
    {'1': '_format'},
    {'1': '_items_schema'},
    {'1': '_object_schema'},
  ],
};

/// Descriptor for `JSONSchemaProperty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jSONSchemaPropertyDescriptor = $convert.base64Decode(
    'ChJKU09OU2NoZW1hUHJvcGVydHkSMgoEdHlwZRgBIAEoDjIeLnJ1bmFueXdoZXJlLnYxLkpTT0'
    '5TY2hlbWFUeXBlUgR0eXBlEiUKC2Rlc2NyaXB0aW9uGAIgASgJSABSC2Rlc2NyaXB0aW9uiAEB'
    'Eh8KC2VudW1fdmFsdWVzGAMgAygJUgplbnVtVmFsdWVzEhsKBmZvcm1hdBgEIAEoCUgBUgZmb3'
    'JtYXSIAQESQgoMaXRlbXNfc2NoZW1hGAUgASgLMhoucnVuYW55d2hlcmUudjEuSlNPTlNjaGVt'
    'YUgCUgtpdGVtc1NjaGVtYYgBARJECg1vYmplY3Rfc2NoZW1hGAYgASgLMhoucnVuYW55d2hlcm'
    'UudjEuSlNPTlNjaGVtYUgDUgxvYmplY3RTY2hlbWGIAQFCDgoMX2Rlc2NyaXB0aW9uQgkKB19m'
    'b3JtYXRCDwoNX2l0ZW1zX3NjaGVtYUIQCg5fb2JqZWN0X3NjaGVtYQ==');

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
    'IJbm90U2NoZW1hiAEBGmEKD1Byb3BlcnRpZXNFbnRyeRIQCgNrZXkYASABKAlSA2tleRI4CgV2'
    'YWx1ZRgCIAEoCzIiLnJ1bmFueXdoZXJlLnYxLkpTT05TY2hlbWFQcm9wZXJ0eVIFdmFsdWU6Aj'
    'gBGloKEERlZmluaXRpb25zRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSMAoFdmFsdWUYAiABKAsy'
    'Gi5ydW5hbnl3aGVyZS52MS5KU09OU2NoZW1hUgV2YWx1ZToCOAFCCAoGX2l0ZW1zQhgKFl9hZG'
    'RpdGlvbmFsX3Byb3BlcnRpZXNCDQoLX3NjaGVtYV91cmlCCQoHX2lkX3VyaUIICgZfdGl0bGVC'
    'DgoMX2Rlc2NyaXB0aW9uQgYKBF9yZWZCDQoLX25vdF9zY2hlbWE=');

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
  ],
  '8': [
    {'1': '_strict_mode'},
    {'1': '_json_schema'},
    {'1': '_type_name'},
    {'1': '_name'},
  ],
};

/// Descriptor for `StructuredOutputOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputOptionsDescriptor = $convert.base64Decode(
    'ChdTdHJ1Y3R1cmVkT3V0cHV0T3B0aW9ucxIyCgZzY2hlbWEYASABKAsyGi5ydW5hbnl3aGVyZS'
    '52MS5KU09OU2NoZW1hUgZzY2hlbWESNwoYaW5jbHVkZV9zY2hlbWFfaW5fcHJvbXB0GAIgASgI'
    'UhVpbmNsdWRlU2NoZW1hSW5Qcm9tcHQSJAoLc3RyaWN0X21vZGUYAyABKAhIAFIKc3RyaWN0TW'
    '9kZYgBARIkCgtqc29uX3NjaGVtYRgEIAEoCUgBUgpqc29uU2NoZW1hiAEBEiAKCXR5cGVfbmFt'
    'ZRgFIAEoCUgCUgh0eXBlTmFtZYgBARIXCgRuYW1lGAYgASgJSANSBG5hbWWIAQFCDgoMX3N0cm'
    'ljdF9tb2RlQg4KDF9qc29uX3NjaGVtYUIMCgpfdHlwZV9uYW1lQgcKBV9uYW1l');

@$core.Deprecated('Use structuredOutputValidationDescriptor instead')
const StructuredOutputValidation$json = {
  '1': 'StructuredOutputValidation',
  '2': [
    {'1': 'is_valid', '3': 1, '4': 1, '5': 8, '10': 'isValid'},
    {'1': 'contains_json', '3': 2, '4': 1, '5': 8, '10': 'containsJson'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'raw_output', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'rawOutput', '17': true},
    {'1': 'extracted_json', '3': 5, '4': 1, '5': 9, '9': 2, '10': 'extractedJson', '17': true},
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
    'SIAQESKgoOZXh0cmFjdGVkX2pzb24YBSABKAlIAlINZXh0cmFjdGVkSnNvbogBAUIQCg5fZXJy'
    'b3JfbWVzc2FnZUINCgtfcmF3X291dHB1dEIRCg9fZXh0cmFjdGVkX2pzb24=');

@$core.Deprecated('Use structuredOutputResultDescriptor instead')
const StructuredOutputResult$json = {
  '1': 'StructuredOutputResult',
  '2': [
    {'1': 'parsed_json', '3': 1, '4': 1, '5': 12, '10': 'parsedJson'},
    {'1': 'validation', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputValidation', '10': 'validation'},
    {'1': 'raw_text', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'rawText', '17': true},
  ],
  '8': [
    {'1': '_raw_text'},
  ],
};

/// Descriptor for `StructuredOutputResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List structuredOutputResultDescriptor = $convert.base64Decode(
    'ChZTdHJ1Y3R1cmVkT3V0cHV0UmVzdWx0Eh8KC3BhcnNlZF9qc29uGAEgASgMUgpwYXJzZWRKc2'
    '9uEkoKCnZhbGlkYXRpb24YAiABKAsyKi5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0'
    'VmFsaWRhdGlvblIKdmFsaWRhdGlvbhIeCghyYXdfdGV4dBgDIAEoCUgAUgdyYXdUZXh0iAEBQg'
    'sKCV9yYXdfdGV4dA==');

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

