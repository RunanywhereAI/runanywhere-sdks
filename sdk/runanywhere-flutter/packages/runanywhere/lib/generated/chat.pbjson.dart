//
//  Generated code. Do not modify.
//  source: chat.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

import 'llm_options.pbjson.dart' as $5;
import 'structured_output.pbjson.dart' as $4;
import 'thinking_tag_pattern.pbjson.dart' as $2;
import 'tool_calling.pbjson.dart' as $0;

@$core.Deprecated('Use messageRoleDescriptor instead')
const MessageRole$json = {
  '1': 'MessageRole',
  '2': [
    {'1': 'MESSAGE_ROLE_UNSPECIFIED', '2': 0},
    {'1': 'MESSAGE_ROLE_USER', '2': 1},
    {'1': 'MESSAGE_ROLE_ASSISTANT', '2': 2},
    {'1': 'MESSAGE_ROLE_SYSTEM', '2': 3},
    {'1': 'MESSAGE_ROLE_TOOL', '2': 4},
    {'1': 'MESSAGE_ROLE_DEVELOPER', '2': 5},
  ],
};

/// Descriptor for `MessageRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageRoleDescriptor = $convert.base64Decode(
    'CgtNZXNzYWdlUm9sZRIcChhNRVNTQUdFX1JPTEVfVU5TUEVDSUZJRUQQABIVChFNRVNTQUdFX1'
    'JPTEVfVVNFUhABEhoKFk1FU1NBR0VfUk9MRV9BU1NJU1RBTlQQAhIXChNNRVNTQUdFX1JPTEVf'
    'U1lTVEVNEAMSFQoRTUVTU0FHRV9ST0xFX1RPT0wQBBIaChZNRVNTQUdFX1JPTEVfREVWRUxPUE'
    'VSEAU=');

@$core.Deprecated('Use chatMessageStatusDescriptor instead')
const ChatMessageStatus$json = {
  '1': 'ChatMessageStatus',
  '2': [
    {'1': 'CHAT_MESSAGE_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'CHAT_MESSAGE_STATUS_PENDING', '2': 1},
    {'1': 'CHAT_MESSAGE_STATUS_STREAMING', '2': 2},
    {'1': 'CHAT_MESSAGE_STATUS_COMPLETE', '2': 3},
    {'1': 'CHAT_MESSAGE_STATUS_FAILED', '2': 4},
    {'1': 'CHAT_MESSAGE_STATUS_CANCELLED', '2': 5},
  ],
};

/// Descriptor for `ChatMessageStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chatMessageStatusDescriptor = $convert.base64Decode(
    'ChFDaGF0TWVzc2FnZVN0YXR1cxIjCh9DSEFUX01FU1NBR0VfU1RBVFVTX1VOU1BFQ0lGSUVEEA'
    'ASHwobQ0hBVF9NRVNTQUdFX1NUQVRVU19QRU5ESU5HEAESIQodQ0hBVF9NRVNTQUdFX1NUQVRV'
    'U19TVFJFQU1JTkcQAhIgChxDSEFUX01FU1NBR0VfU1RBVFVTX0NPTVBMRVRFEAMSHgoaQ0hBVF'
    '9NRVNTQUdFX1NUQVRVU19GQUlMRUQQBBIhCh1DSEFUX01FU1NBR0VfU1RBVFVTX0NBTkNFTExF'
    'RBAF');

@$core.Deprecated('Use chatStreamEventKindDescriptor instead')
const ChatStreamEventKind$json = {
  '1': 'ChatStreamEventKind',
  '2': [
    {'1': 'CHAT_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED', '2': 1},
    {'1': 'CHAT_STREAM_EVENT_KIND_TOKEN', '2': 2},
    {'1': 'CHAT_STREAM_EVENT_KIND_TOOL_CALL', '2': 3},
    {'1': 'CHAT_STREAM_EVENT_KIND_TOOL_RESULT', '2': 4},
    {'1': 'CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED', '2': 5},
    {'1': 'CHAT_STREAM_EVENT_KIND_ERROR', '2': 6},
  ],
};

/// Descriptor for `ChatStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chatStreamEventKindDescriptor = $convert.base64Decode(
    'ChNDaGF0U3RyZWFtRXZlbnRLaW5kEiYKIkNIQVRfU1RSRUFNX0VWRU5UX0tJTkRfVU5TUEVDSU'
    'ZJRUQQABIqCiZDSEFUX1NUUkVBTV9FVkVOVF9LSU5EX01FU1NBR0VfU1RBUlRFRBABEiAKHENI'
    'QVRfU1RSRUFNX0VWRU5UX0tJTkRfVE9LRU4QAhIkCiBDSEFUX1NUUkVBTV9FVkVOVF9LSU5EX1'
    'RPT0xfQ0FMTBADEiYKIkNIQVRfU1RSRUFNX0VWRU5UX0tJTkRfVE9PTF9SRVNVTFQQBBIsCihD'
    'SEFUX1NUUkVBTV9FVkVOVF9LSU5EX01FU1NBR0VfQ09NUExFVEVEEAUSIAocQ0hBVF9TVFJFQU'
    '1fRVZFTlRfS0lORF9FUlJPUhAG');

@$core.Deprecated('Use chatAttachmentDescriptor instead')
const ChatAttachment$json = {
  '1': 'ChatAttachment',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'media_type', '3': 2, '4': 1, '5': 9, '10': 'mediaType'},
    {'1': 'data', '3': 3, '4': 1, '5': 12, '9': 0, '10': 'data'},
    {'1': 'uri', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'uri'},
    {'1': 'adapter_handle', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'adapterHandle'},
    {'1': 'name', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'name', '17': true},
    {'1': 'size_bytes', '3': 7, '4': 1, '5': 3, '10': 'sizeBytes'},
    {'1': 'metadata', '3': 8, '4': 3, '5': 11, '6': '.runanywhere.v1.ChatAttachment.MetadataEntry', '10': 'metadata'},
  ],
  '3': [ChatAttachment_MetadataEntry$json],
  '8': [
    {'1': 'source'},
    {'1': '_name'},
  ],
};

@$core.Deprecated('Use chatAttachmentDescriptor instead')
const ChatAttachment_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ChatAttachment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatAttachmentDescriptor = $convert.base64Decode(
    'Cg5DaGF0QXR0YWNobWVudBIOCgJpZBgBIAEoCVICaWQSHQoKbWVkaWFfdHlwZRgCIAEoCVIJbW'
    'VkaWFUeXBlEhQKBGRhdGEYAyABKAxIAFIEZGF0YRISCgN1cmkYBCABKAlIAFIDdXJpEicKDmFk'
    'YXB0ZXJfaGFuZGxlGAUgASgJSABSDWFkYXB0ZXJIYW5kbGUSFwoEbmFtZRgGIAEoCUgBUgRuYW'
    '1liAEBEh0KCnNpemVfYnl0ZXMYByABKANSCXNpemVCeXRlcxJICghtZXRhZGF0YRgIIAMoCzIs'
    'LnJ1bmFueXdoZXJlLnYxLkNoYXRBdHRhY2htZW50Lk1ldGFkYXRhRW50cnlSCG1ldGFkYXRhGj'
    'sKDU1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVl'
    'OgI4AUIICgZzb3VyY2VCBwoFX25hbWU=');

@$core.Deprecated('Use chatMessageDescriptor instead')
const ChatMessage$json = {
  '1': 'ChatMessage',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'role', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.MessageRole', '10': 'role'},
    {'1': 'content', '3': 3, '4': 1, '5': 9, '10': 'content'},
    {'1': 'timestamp_us', '3': 4, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'name', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {'1': 'tool_call_id', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'toolCallId', '17': true},
    {'1': 'tool_calls', '3': 8, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolCall', '10': 'toolCalls'},
    {'1': 'tool_result', '3': 9, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolResult', '9': 2, '10': 'toolResult', '17': true},
    {'1': 'parent_id', '3': 10, '4': 1, '5': 9, '9': 3, '10': 'parentId', '17': true},
    {'1': 'status', '3': 11, '4': 1, '5': 14, '6': '.runanywhere.v1.ChatMessageStatus', '10': 'status'},
    {'1': 'error_message', '3': 12, '4': 1, '5': 9, '9': 4, '10': 'errorMessage', '17': true},
    {'1': 'metadata', '3': 13, '4': 3, '5': 11, '6': '.runanywhere.v1.ChatMessage.MetadataEntry', '10': 'metadata'},
    {'1': 'attachments', '3': 14, '4': 3, '5': 11, '6': '.runanywhere.v1.ChatAttachment', '10': 'attachments'},
  ],
  '3': [ChatMessage_MetadataEntry$json],
  '8': [
    {'1': '_name'},
    {'1': '_tool_call_id'},
    {'1': '_tool_result'},
    {'1': '_parent_id'},
    {'1': '_error_message'},
  ],
  '9': [
    {'1': 6, '2': 7},
  ],
  '10': ['tool_calls_json'],
};

@$core.Deprecated('Use chatMessageDescriptor instead')
const ChatMessage_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ChatMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageDescriptor = $convert.base64Decode(
    'CgtDaGF0TWVzc2FnZRIOCgJpZBgBIAEoCVICaWQSLwoEcm9sZRgCIAEoDjIbLnJ1bmFueXdoZX'
    'JlLnYxLk1lc3NhZ2VSb2xlUgRyb2xlEhgKB2NvbnRlbnQYAyABKAlSB2NvbnRlbnQSIQoMdGlt'
    'ZXN0YW1wX3VzGAQgASgDUgt0aW1lc3RhbXBVcxIXCgRuYW1lGAUgASgJSABSBG5hbWWIAQESJQ'
    'oMdG9vbF9jYWxsX2lkGAcgASgJSAFSCnRvb2xDYWxsSWSIAQESNwoKdG9vbF9jYWxscxgIIAMo'
    'CzIYLnJ1bmFueXdoZXJlLnYxLlRvb2xDYWxsUgl0b29sQ2FsbHMSQAoLdG9vbF9yZXN1bHQYCS'
    'ABKAsyGi5ydW5hbnl3aGVyZS52MS5Ub29sUmVzdWx0SAJSCnRvb2xSZXN1bHSIAQESIAoJcGFy'
    'ZW50X2lkGAogASgJSANSCHBhcmVudElkiAEBEjkKBnN0YXR1cxgLIAEoDjIhLnJ1bmFueXdoZX'
    'JlLnYxLkNoYXRNZXNzYWdlU3RhdHVzUgZzdGF0dXMSKAoNZXJyb3JfbWVzc2FnZRgMIAEoCUgE'
    'UgxlcnJvck1lc3NhZ2WIAQESRQoIbWV0YWRhdGEYDSADKAsyKS5ydW5hbnl3aGVyZS52MS5DaG'
    'F0TWVzc2FnZS5NZXRhZGF0YUVudHJ5UghtZXRhZGF0YRJACgthdHRhY2htZW50cxgOIAMoCzIe'
    'LnJ1bmFueXdoZXJlLnYxLkNoYXRBdHRhY2htZW50UgthdHRhY2htZW50cxo7Cg1NZXRhZGF0YU'
    'VudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAFCBwoFX25h'
    'bWVCDwoNX3Rvb2xfY2FsbF9pZEIOCgxfdG9vbF9yZXN1bHRCDAoKX3BhcmVudF9pZEIQCg5fZX'
    'Jyb3JfbWVzc2FnZUoECAYQB1IPdG9vbF9jYWxsc19qc29u');

@$core.Deprecated('Use chatGenerationRequestDescriptor instead')
const ChatGenerationRequest$json = {
  '1': 'ChatGenerationRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'conversation_id', '3': 2, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'messages', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ChatMessage', '10': 'messages'},
    {'1': 'options', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.LLMGenerationOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'tool_calling', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCallingOptions', '9': 1, '10': 'toolCalling', '17': true},
    {'1': 'metadata', '3': 6, '4': 3, '5': 11, '6': '.runanywhere.v1.ChatGenerationRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [ChatGenerationRequest_MetadataEntry$json],
  '8': [
    {'1': '_options'},
    {'1': '_tool_calling'},
  ],
};

@$core.Deprecated('Use chatGenerationRequestDescriptor instead')
const ChatGenerationRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ChatGenerationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatGenerationRequestDescriptor = $convert.base64Decode(
    'ChVDaGF0R2VuZXJhdGlvblJlcXVlc3QSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEi'
    'cKD2NvbnZlcnNhdGlvbl9pZBgCIAEoCVIOY29udmVyc2F0aW9uSWQSNwoIbWVzc2FnZXMYAyAD'
    'KAsyGy5ydW5hbnl3aGVyZS52MS5DaGF0TWVzc2FnZVIIbWVzc2FnZXMSQwoHb3B0aW9ucxgEIA'
    'EoCzIkLnJ1bmFueXdoZXJlLnYxLkxMTUdlbmVyYXRpb25PcHRpb25zSABSB29wdGlvbnOIAQES'
    'SgoMdG9vbF9jYWxsaW5nGAUgASgLMiIucnVuYW55d2hlcmUudjEuVG9vbENhbGxpbmdPcHRpb2'
    '5zSAFSC3Rvb2xDYWxsaW5niAEBEk8KCG1ldGFkYXRhGAYgAygLMjMucnVuYW55d2hlcmUudjEu'
    'Q2hhdEdlbmVyYXRpb25SZXF1ZXN0Lk1ldGFkYXRhRW50cnlSCG1ldGFkYXRhGjsKDU1ldGFkYX'
    'RhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AUIKCghf'
    'b3B0aW9uc0IPCg1fdG9vbF9jYWxsaW5n');

@$core.Deprecated('Use chatGenerationResultDescriptor instead')
const ChatGenerationResult$json = {
  '1': 'ChatGenerationResult',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'message', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ChatMessage', '10': 'message'},
    {'1': 'generation', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.LLMGenerationResult', '9': 0, '10': 'generation', '17': true},
    {'1': 'tool_calls', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolCall', '10': 'toolCalls'},
    {'1': 'tool_results', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolResult', '10': 'toolResults'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 7, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_generation'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `ChatGenerationResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatGenerationResultDescriptor = $convert.base64Decode(
    'ChRDaGF0R2VuZXJhdGlvblJlc3VsdBInCg9jb252ZXJzYXRpb25faWQYASABKAlSDmNvbnZlcn'
    'NhdGlvbklkEjUKB21lc3NhZ2UYAiABKAsyGy5ydW5hbnl3aGVyZS52MS5DaGF0TWVzc2FnZVIH'
    'bWVzc2FnZRJICgpnZW5lcmF0aW9uGAMgASgLMiMucnVuYW55d2hlcmUudjEuTExNR2VuZXJhdG'
    'lvblJlc3VsdEgAUgpnZW5lcmF0aW9uiAEBEjcKCnRvb2xfY2FsbHMYBCADKAsyGC5ydW5hbnl3'
    'aGVyZS52MS5Ub29sQ2FsbFIJdG9vbENhbGxzEj0KDHRvb2xfcmVzdWx0cxgFIAMoCzIaLnJ1bm'
    'FueXdoZXJlLnYxLlRvb2xSZXN1bHRSC3Rvb2xSZXN1bHRzEigKDWVycm9yX21lc3NhZ2UYBiAB'
    'KAlIAVIMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYByABKAVSCWVycm9yQ29kZUINCg'
    'tfZ2VuZXJhdGlvbkIQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use chatStreamEventDescriptor instead')
const ChatStreamEvent$json = {
  '1': 'ChatStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'conversation_id', '3': 4, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'kind', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.ChatStreamEventKind', '10': 'kind'},
    {'1': 'token', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'token', '17': true},
    {'1': 'message', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.ChatMessage', '9': 1, '10': 'message', '17': true},
    {'1': 'tool_call', '3': 8, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCall', '9': 2, '10': 'toolCall', '17': true},
    {'1': 'tool_result', '3': 9, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolResult', '9': 3, '10': 'toolResult', '17': true},
    {'1': 'final_result', '3': 10, '4': 1, '5': 11, '6': '.runanywhere.v1.LLMGenerationResult', '9': 4, '10': 'finalResult', '17': true},
    {'1': 'error_message', '3': 11, '4': 1, '5': 9, '9': 5, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 12, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_token'},
    {'1': '_message'},
    {'1': '_tool_call'},
    {'1': '_tool_result'},
    {'1': '_final_result'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `ChatStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatStreamEventDescriptor = $convert.base64Decode(
    'Cg9DaGF0U3RyZWFtRXZlbnQSEAoDc2VxGAEgASgEUgNzZXESIQoMdGltZXN0YW1wX3VzGAIgAS'
    'gDUgt0aW1lc3RhbXBVcxIdCgpyZXF1ZXN0X2lkGAMgASgJUglyZXF1ZXN0SWQSJwoPY29udmVy'
    'c2F0aW9uX2lkGAQgASgJUg5jb252ZXJzYXRpb25JZBI3CgRraW5kGAUgASgOMiMucnVuYW55d2'
    'hlcmUudjEuQ2hhdFN0cmVhbUV2ZW50S2luZFIEa2luZBIZCgV0b2tlbhgGIAEoCUgAUgV0b2tl'
    'bogBARI6CgdtZXNzYWdlGAcgASgLMhsucnVuYW55d2hlcmUudjEuQ2hhdE1lc3NhZ2VIAVIHbW'
    'Vzc2FnZYgBARI6Cgl0b29sX2NhbGwYCCABKAsyGC5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbEgC'
    'Ugh0b29sQ2FsbIgBARJACgt0b29sX3Jlc3VsdBgJIAEoCzIaLnJ1bmFueXdoZXJlLnYxLlRvb2'
    'xSZXN1bHRIA1IKdG9vbFJlc3VsdIgBARJLCgxmaW5hbF9yZXN1bHQYCiABKAsyIy5ydW5hbnl3'
    'aGVyZS52MS5MTE1HZW5lcmF0aW9uUmVzdWx0SARSC2ZpbmFsUmVzdWx0iAEBEigKDWVycm9yX2'
    '1lc3NhZ2UYCyABKAlIBVIMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYDCABKAVSCWVy'
    'cm9yQ29kZUIICgZfdG9rZW5CCgoIX21lc3NhZ2VCDAoKX3Rvb2xfY2FsbEIOCgxfdG9vbF9yZX'
    'N1bHRCDwoNX2ZpbmFsX3Jlc3VsdEIQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use chatConversationStateDescriptor instead')
const ChatConversationState$json = {
  '1': 'ChatConversationState',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'messages', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.ChatMessage', '10': 'messages'},
    {'1': 'created_at_ms', '3': 3, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'updated_at_ms', '3': 4, '4': 1, '5': 3, '10': 'updatedAtMs'},
    {'1': 'metadata', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.ChatConversationState.MetadataEntry', '10': 'metadata'},
  ],
  '3': [ChatConversationState_MetadataEntry$json],
};

@$core.Deprecated('Use chatConversationStateDescriptor instead')
const ChatConversationState_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ChatConversationState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatConversationStateDescriptor = $convert.base64Decode(
    'ChVDaGF0Q29udmVyc2F0aW9uU3RhdGUSJwoPY29udmVyc2F0aW9uX2lkGAEgASgJUg5jb252ZX'
    'JzYXRpb25JZBI3CghtZXNzYWdlcxgCIAMoCzIbLnJ1bmFueXdoZXJlLnYxLkNoYXRNZXNzYWdl'
    'UghtZXNzYWdlcxIiCg1jcmVhdGVkX2F0X21zGAMgASgDUgtjcmVhdGVkQXRNcxIiCg11cGRhdG'
    'VkX2F0X21zGAQgASgDUgt1cGRhdGVkQXRNcxJPCghtZXRhZGF0YRgFIAMoCzIzLnJ1bmFueXdo'
    'ZXJlLnYxLkNoYXRDb252ZXJzYXRpb25TdGF0ZS5NZXRhZGF0YUVudHJ5UghtZXRhZGF0YRo7Cg'
    '1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToC'
    'OAE=');

const $core.Map<$core.String, $core.dynamic> ChatServiceBase$json = {
  '1': 'Chat',
  '2': [
    {'1': 'Generate', '2': '.runanywhere.v1.ChatGenerationRequest', '3': '.runanywhere.v1.ChatGenerationResult'},
    {'1': 'Stream', '2': '.runanywhere.v1.ChatGenerationRequest', '3': '.runanywhere.v1.ChatStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use chatServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> ChatServiceBase$messageJson = {
  '.runanywhere.v1.ChatGenerationRequest': ChatGenerationRequest$json,
  '.runanywhere.v1.ChatMessage': ChatMessage$json,
  '.runanywhere.v1.ToolCall': $0.ToolCall$json,
  '.runanywhere.v1.ToolResult': $0.ToolResult$json,
  '.runanywhere.v1.ChatMessage.MetadataEntry': ChatMessage_MetadataEntry$json,
  '.runanywhere.v1.ChatAttachment': ChatAttachment$json,
  '.runanywhere.v1.ChatAttachment.MetadataEntry': ChatAttachment_MetadataEntry$json,
  '.runanywhere.v1.LLMGenerationOptions': $5.LLMGenerationOptions$json,
  '.runanywhere.v1.ThinkingTagPattern': $2.ThinkingTagPattern$json,
  '.runanywhere.v1.StructuredOutputOptions': $4.StructuredOutputOptions$json,
  '.runanywhere.v1.JSONSchema': $4.JSONSchema$json,
  '.runanywhere.v1.JSONSchema.PropertiesEntry': $4.JSONSchema_PropertiesEntry$json,
  '.runanywhere.v1.JSONSchemaProperty': $4.JSONSchemaProperty$json,
  '.runanywhere.v1.JSONSchema.DefinitionsEntry': $4.JSONSchema_DefinitionsEntry$json,
  '.runanywhere.v1.ToolCallingOptions': $0.ToolCallingOptions$json,
  '.runanywhere.v1.ToolDefinition': $0.ToolDefinition$json,
  '.runanywhere.v1.ToolParameter': $0.ToolParameter$json,
  '.runanywhere.v1.ToolValue': $0.ToolValue$json,
  '.runanywhere.v1.ToolValueArray': $0.ToolValueArray$json,
  '.runanywhere.v1.ToolValueObject': $0.ToolValueObject$json,
  '.runanywhere.v1.ToolValueObject.FieldsEntry': $0.ToolValueObject_FieldsEntry$json,
  '.runanywhere.v1.ToolDefinition.MetadataEntry': $0.ToolDefinition_MetadataEntry$json,
  '.runanywhere.v1.ChatGenerationRequest.MetadataEntry': ChatGenerationRequest_MetadataEntry$json,
  '.runanywhere.v1.ChatGenerationResult': ChatGenerationResult$json,
  '.runanywhere.v1.LLMGenerationResult': $5.LLMGenerationResult$json,
  '.runanywhere.v1.PerformanceMetrics': $5.PerformanceMetrics$json,
  '.runanywhere.v1.StructuredOutputValidation': $4.StructuredOutputValidation$json,
  '.runanywhere.v1.ChatStreamEvent': ChatStreamEvent$json,
};

/// Descriptor for `Chat`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List chatServiceDescriptor = $convert.base64Decode(
    'CgRDaGF0ElcKCEdlbmVyYXRlEiUucnVuYW55d2hlcmUudjEuQ2hhdEdlbmVyYXRpb25SZXF1ZX'
    'N0GiQucnVuYW55d2hlcmUudjEuQ2hhdEdlbmVyYXRpb25SZXN1bHQSUgoGU3RyZWFtEiUucnVu'
    'YW55d2hlcmUudjEuQ2hhdEdlbmVyYXRpb25SZXF1ZXN0Gh8ucnVuYW55d2hlcmUudjEuQ2hhdF'
    'N0cmVhbUV2ZW50MAE=');

