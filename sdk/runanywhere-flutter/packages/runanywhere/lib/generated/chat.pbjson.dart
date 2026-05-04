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

@$core.Deprecated('Use messageRoleDescriptor instead')
const MessageRole$json = {
  '1': 'MessageRole',
  '2': [
    {'1': 'MESSAGE_ROLE_UNSPECIFIED', '2': 0},
    {'1': 'MESSAGE_ROLE_USER', '2': 1},
    {'1': 'MESSAGE_ROLE_ASSISTANT', '2': 2},
    {'1': 'MESSAGE_ROLE_SYSTEM', '2': 3},
    {'1': 'MESSAGE_ROLE_TOOL', '2': 4},
  ],
};

/// Descriptor for `MessageRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageRoleDescriptor = $convert.base64Decode(
    'CgtNZXNzYWdlUm9sZRIcChhNRVNTQUdFX1JPTEVfVU5TUEVDSUZJRUQQABIVChFNRVNTQUdFX1'
    'JPTEVfVVNFUhABEhoKFk1FU1NBR0VfUk9MRV9BU1NJU1RBTlQQAhIXChNNRVNTQUdFX1JPTEVf'
    'U1lTVEVNEAMSFQoRTUVTU0FHRV9ST0xFX1RPT0wQBA==');

@$core.Deprecated('Use chatMessageDescriptor instead')
const ChatMessage$json = {
  '1': 'ChatMessage',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'role', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.MessageRole', '10': 'role'},
    {'1': 'content', '3': 3, '4': 1, '5': 9, '10': 'content'},
    {'1': 'timestamp_us', '3': 4, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'name', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {'1': 'tool_calls_json', '3': 6, '4': 3, '5': 9, '10': 'toolCallsJson'},
    {'1': 'tool_call_id', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'toolCallId', '17': true},
    {'1': 'tool_calls', '3': 8, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolCall', '10': 'toolCalls'},
    {'1': 'tool_result', '3': 9, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolResult', '9': 2, '10': 'toolResult', '17': true},
  ],
  '8': [
    {'1': '_name'},
    {'1': '_tool_call_id'},
    {'1': '_tool_result'},
  ],
};

/// Descriptor for `ChatMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageDescriptor = $convert.base64Decode(
    'CgtDaGF0TWVzc2FnZRIOCgJpZBgBIAEoCVICaWQSLwoEcm9sZRgCIAEoDjIbLnJ1bmFueXdoZX'
    'JlLnYxLk1lc3NhZ2VSb2xlUgRyb2xlEhgKB2NvbnRlbnQYAyABKAlSB2NvbnRlbnQSIQoMdGlt'
    'ZXN0YW1wX3VzGAQgASgDUgt0aW1lc3RhbXBVcxIXCgRuYW1lGAUgASgJSABSBG5hbWWIAQESJg'
    'oPdG9vbF9jYWxsc19qc29uGAYgAygJUg10b29sQ2FsbHNKc29uEiUKDHRvb2xfY2FsbF9pZBgH'
    'IAEoCUgBUgp0b29sQ2FsbElkiAEBEjcKCnRvb2xfY2FsbHMYCCADKAsyGC5ydW5hbnl3aGVyZS'
    '52MS5Ub29sQ2FsbFIJdG9vbENhbGxzEkAKC3Rvb2xfcmVzdWx0GAkgASgLMhoucnVuYW55d2hl'
    'cmUudjEuVG9vbFJlc3VsdEgCUgp0b29sUmVzdWx0iAEBQgcKBV9uYW1lQg8KDV90b29sX2NhbG'
    'xfaWRCDgoMX3Rvb2xfcmVzdWx0');

