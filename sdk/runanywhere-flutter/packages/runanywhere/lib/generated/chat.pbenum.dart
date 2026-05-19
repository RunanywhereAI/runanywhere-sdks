// This is a generated file - do not edit.
//
// Generated from chat.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Conversational role of a ChatMessage.
/// ---------------------------------------------------------------------------
class MessageRole extends $pb.ProtobufEnum {
  static const MessageRole MESSAGE_ROLE_UNSPECIFIED =
      MessageRole._(0, _omitEnumNames ? '' : 'MESSAGE_ROLE_UNSPECIFIED');
  static const MessageRole MESSAGE_ROLE_USER =
      MessageRole._(1, _omitEnumNames ? '' : 'MESSAGE_ROLE_USER');
  static const MessageRole MESSAGE_ROLE_ASSISTANT =
      MessageRole._(2, _omitEnumNames ? '' : 'MESSAGE_ROLE_ASSISTANT');
  static const MessageRole MESSAGE_ROLE_SYSTEM =
      MessageRole._(3, _omitEnumNames ? '' : 'MESSAGE_ROLE_SYSTEM');

  /// Tool-result messages injected back into the conversation after a
  /// tool call has been executed. Required for OpenAI-style tool flows.
  static const MessageRole MESSAGE_ROLE_TOOL =
      MessageRole._(4, _omitEnumNames ? '' : 'MESSAGE_ROLE_TOOL');
  static const MessageRole MESSAGE_ROLE_DEVELOPER =
      MessageRole._(5, _omitEnumNames ? '' : 'MESSAGE_ROLE_DEVELOPER');

  static const $core.List<MessageRole> values = <MessageRole>[
    MESSAGE_ROLE_UNSPECIFIED,
    MESSAGE_ROLE_USER,
    MESSAGE_ROLE_ASSISTANT,
    MESSAGE_ROLE_SYSTEM,
    MESSAGE_ROLE_TOOL,
    MESSAGE_ROLE_DEVELOPER,
  ];

  static final $core.List<MessageRole?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static MessageRole? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MessageRole._(super.value, super.name);
}

class ChatMessageStatus extends $pb.ProtobufEnum {
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_UNSPECIFIED =
      ChatMessageStatus._(
          0, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_UNSPECIFIED');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_PENDING =
      ChatMessageStatus._(
          1, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_PENDING');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_STREAMING =
      ChatMessageStatus._(
          2, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_STREAMING');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_COMPLETE =
      ChatMessageStatus._(
          3, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_COMPLETE');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_FAILED =
      ChatMessageStatus._(
          4, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_FAILED');
  static const ChatMessageStatus CHAT_MESSAGE_STATUS_CANCELLED =
      ChatMessageStatus._(
          5, _omitEnumNames ? '' : 'CHAT_MESSAGE_STATUS_CANCELLED');

  static const $core.List<ChatMessageStatus> values = <ChatMessageStatus>[
    CHAT_MESSAGE_STATUS_UNSPECIFIED,
    CHAT_MESSAGE_STATUS_PENDING,
    CHAT_MESSAGE_STATUS_STREAMING,
    CHAT_MESSAGE_STATUS_COMPLETE,
    CHAT_MESSAGE_STATUS_FAILED,
    CHAT_MESSAGE_STATUS_CANCELLED,
  ];

  static final $core.List<ChatMessageStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static ChatMessageStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ChatMessageStatus._(super.value, super.name);
}

class ChatStreamEventKind extends $pb.ProtobufEnum {
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_UNSPECIFIED =
      ChatStreamEventKind._(
          0, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_UNSPECIFIED');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED =
      ChatStreamEventKind._(
          1, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_TOKEN =
      ChatStreamEventKind._(
          2, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_TOKEN');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_TOOL_CALL =
      ChatStreamEventKind._(
          3, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_TOOL_CALL');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_TOOL_RESULT =
      ChatStreamEventKind._(
          4, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_TOOL_RESULT');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED =
      ChatStreamEventKind._(
          5, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED');
  static const ChatStreamEventKind CHAT_STREAM_EVENT_KIND_ERROR =
      ChatStreamEventKind._(
          6, _omitEnumNames ? '' : 'CHAT_STREAM_EVENT_KIND_ERROR');

  static const $core.List<ChatStreamEventKind> values = <ChatStreamEventKind>[
    CHAT_STREAM_EVENT_KIND_UNSPECIFIED,
    CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED,
    CHAT_STREAM_EVENT_KIND_TOKEN,
    CHAT_STREAM_EVENT_KIND_TOOL_CALL,
    CHAT_STREAM_EVENT_KIND_TOOL_RESULT,
    CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED,
    CHAT_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<ChatStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static ChatStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ChatStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
