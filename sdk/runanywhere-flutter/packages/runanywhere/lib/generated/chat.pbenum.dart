//
//  Generated code. Do not modify.
//  source: chat.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Conversational role of a ChatMessage.
/// ---------------------------------------------------------------------------
class MessageRole extends $pb.ProtobufEnum {
  static const MessageRole MESSAGE_ROLE_UNSPECIFIED = MessageRole._(0, _omitEnumNames ? '' : 'MESSAGE_ROLE_UNSPECIFIED');
  static const MessageRole MESSAGE_ROLE_USER = MessageRole._(1, _omitEnumNames ? '' : 'MESSAGE_ROLE_USER');
  static const MessageRole MESSAGE_ROLE_ASSISTANT = MessageRole._(2, _omitEnumNames ? '' : 'MESSAGE_ROLE_ASSISTANT');
  static const MessageRole MESSAGE_ROLE_SYSTEM = MessageRole._(3, _omitEnumNames ? '' : 'MESSAGE_ROLE_SYSTEM');
  static const MessageRole MESSAGE_ROLE_TOOL = MessageRole._(4, _omitEnumNames ? '' : 'MESSAGE_ROLE_TOOL');
  static const MessageRole MESSAGE_ROLE_DEVELOPER = MessageRole._(5, _omitEnumNames ? '' : 'MESSAGE_ROLE_DEVELOPER');

  static const $core.List<MessageRole> values = <MessageRole> [
    MESSAGE_ROLE_UNSPECIFIED,
    MESSAGE_ROLE_USER,
    MESSAGE_ROLE_ASSISTANT,
    MESSAGE_ROLE_SYSTEM,
    MESSAGE_ROLE_TOOL,
    MESSAGE_ROLE_DEVELOPER,
  ];

  static final $core.Map<$core.int, MessageRole> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MessageRole? valueOf($core.int value) => _byValue[value];

  const MessageRole._($core.int v, $core.String n) : super(v, n);
}

class ChatMessageStatus extends $pb.ProtobufEnum {
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_UNSPECIFIED = ChatMessageStatus._(0, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_UNSPECIFIED');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_PENDING = ChatMessageStatus._(1, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_PENDING');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_STREAMING = ChatMessageStatus._(2, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_STREAMING');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_COMPLETE = ChatMessageStatus._(3, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_COMPLETE');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_FAILED = ChatMessageStatus._(4, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_FAILED');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_CANCELLED = ChatMessageStatus._(5, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_CANCELLED');

  static const $core.List<ChatMessageStatus> values = <ChatMessageStatus> [
    CHAT_MESSAGE_STATUS_UNSPECIFIED,
    CHAT_MESSAGE_STATUS_PENDING,
    CHAT_MESSAGE_STATUS_STREAMING,
    CHAT_MESSAGE_STATUS_COMPLETE,
    CHAT_MESSAGE_STATUS_FAILED,
    CHAT_MESSAGE_STATUS_CANCELLED,
  ];

  static final $core.Map<$core.int, ChatMessageStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ChatMessageStatus? valueOf($core.int value) => _byValue[value];

  const ChatMessageStatus._($core.int v, $core.String n) : super(v, n);
}

class ChatStreamEventKind extends $pb.ProtobufEnum {
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_UNSPECIFIED = ChatStreamEventKind._(0, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_UNSPECIFIED');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED = ChatStreamEventKind._(1, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_TOKEN = ChatStreamEventKind._(2, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_TOKEN');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_TOOL_CALL = ChatStreamEventKind._(3, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_TOOL_CALL');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_TOOL_RESULT = ChatStreamEventKind._(4, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_TOOL_RESULT');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED = ChatStreamEventKind._(5, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_ERROR = ChatStreamEventKind._(6, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_ERROR');

  static const $core.List<ChatStreamEventKind> values = <ChatStreamEventKind> [
    CHAT_STREAM_EVENT_KIND_UNSPECIFIED,
    CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED,
    CHAT_STREAM_EVENT_KIND_TOKEN,
    CHAT_STREAM_EVENT_KIND_TOOL_CALL,
    CHAT_STREAM_EVENT_KIND_TOOL_RESULT,
    CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED,
    CHAT_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.Map<$core.int, ChatStreamEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ChatStreamEventKind? valueOf($core.int value) => _byValue[value];

  const ChatStreamEventKind._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
