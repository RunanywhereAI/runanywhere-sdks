///
//  Generated code. Do not modify.
//  source: chat.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use messageRoleDescriptor instead')
const MessageRole$json = const {
  '1': 'MessageRole',
  '2': const [
    const {'1': 'MESSAGE_ROLE_UNSPECIFIED', '2': 0},
    const {'1': 'MESSAGE_ROLE_USER', '2': 1},
    const {'1': 'MESSAGE_ROLE_ASSISTANT', '2': 2},
    const {'1': 'MESSAGE_ROLE_SYSTEM', '2': 3},
    const {'1': 'MESSAGE_ROLE_TOOL', '2': 4},
  ],
};

/// Descriptor for `MessageRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageRoleDescriptor = $convert.base64Decode('CgtNZXNzYWdlUm9sZRIcChhNRVNTQUdFX1JPTEVfVU5TUEVDSUZJRUQQABIVChFNRVNTQUdFX1JPTEVfVVNFUhABEhoKFk1FU1NBR0VfUk9MRV9BU1NJU1RBTlQQAhIXChNNRVNTQUdFX1JPTEVfU1lTVEVNEAMSFQoRTUVTU0FHRV9ST0xFX1RPT0wQBA==');
@$core.Deprecated('Use chatMessageDescriptor instead')
const ChatMessage$json = const {
  '1': 'ChatMessage',
  '2': const [
    const {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'role', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.MessageRole', '10': 'role'},
    const {'1': 'content', '3': 3, '4': 1, '5': 9, '10': 'content'},
    const {'1': 'timestamp_us', '3': 4, '4': 1, '5': 3, '10': 'timestampUs'},
    const {'1': 'name', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    const {'1': 'tool_calls_json', '3': 6, '4': 3, '5': 9, '10': 'toolCallsJson'},
    const {'1': 'tool_call_id', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'toolCallId', '17': true},
  ],
  '8': const [
    const {'1': '_name'},
    const {'1': '_tool_call_id'},
  ],
};

/// Descriptor for `ChatMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatMessageDescriptor = $convert.base64Decode('CgtDaGF0TWVzc2FnZRIOCgJpZBgBIAEoCVICaWQSLwoEcm9sZRgCIAEoDjIbLnJ1bmFueXdoZXJlLnYxLk1lc3NhZ2VSb2xlUgRyb2xlEhgKB2NvbnRlbnQYAyABKAlSB2NvbnRlbnQSIQoMdGltZXN0YW1wX3VzGAQgASgDUgt0aW1lc3RhbXBVcxIXCgRuYW1lGAUgASgJSABSBG5hbWWIAQESJgoPdG9vbF9jYWxsc19qc29uGAYgAygJUg10b29sQ2FsbHNKc29uEiUKDHRvb2xfY2FsbF9pZBgHIAEoCUgBUgp0b29sQ2FsbElkiAEBQgcKBV9uYW1lQg8KDV90b29sX2NhbGxfaWQ=');
