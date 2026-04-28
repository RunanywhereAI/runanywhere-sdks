///
//  Generated code. Do not modify.
//  source: chat.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class MessageRole extends $pb.ProtobufEnum {
  static const MessageRole MESSAGE_ROLE_UNSPECIFIED = MessageRole._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MESSAGE_ROLE_UNSPECIFIED');
  static const MessageRole MESSAGE_ROLE_USER = MessageRole._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MESSAGE_ROLE_USER');
  static const MessageRole MESSAGE_ROLE_ASSISTANT = MessageRole._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MESSAGE_ROLE_ASSISTANT');
  static const MessageRole MESSAGE_ROLE_SYSTEM = MessageRole._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MESSAGE_ROLE_SYSTEM');
  static const MessageRole MESSAGE_ROLE_TOOL = MessageRole._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MESSAGE_ROLE_TOOL');

  static const $core.List<MessageRole> values = <MessageRole> [
    MESSAGE_ROLE_UNSPECIFIED,
    MESSAGE_ROLE_USER,
    MESSAGE_ROLE_ASSISTANT,
    MESSAGE_ROLE_SYSTEM,
    MESSAGE_ROLE_TOOL,
  ];

  static final $core.Map<$core.int, MessageRole> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MessageRole? valueOf($core.int value) => _byValue[value];

  const MessageRole._($core.int v, $core.String n) : super(v, n);
}

