import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/runanywhere_protos.dart' as proto;

/// File-based persistence for conversation history.
///
/// Note: chat sessions are currently in-memory only (`ChatInterfaceView`).
/// This store reads pre-existing conversation files from disk so the
/// History sheet can display them and delete them. Re-wiring the chat
/// to write back through this store is a future feature.
class ConversationStore extends ChangeNotifier {
  static final ConversationStore shared = ConversationStore._();

  ConversationStore._() {
    unawaited(_initialize());
  }

  List<Conversation> _conversations = [];
  Directory? _conversationsDirectory;

  List<Conversation> get conversations => _conversations;

  Future<void> _initialize() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    _conversationsDirectory = Directory('${documentsDir.path}/Conversations');

    if (!await _conversationsDirectory!.exists()) {
      await _conversationsDirectory!.create(recursive: true);
    }

    await loadConversations();
  }

  /// Delete a conversation
  void deleteConversation(Conversation conversation) {
    _conversations.removeWhere((c) => c.id == conversation.id);
    unawaited(_deleteConversationFile(conversation.id));
    notifyListeners();
  }

  /// Load all conversations from disk
  Future<void> loadConversations() async {
    if (_conversationsDirectory == null) return;

    try {
      final files = _conversationsDirectory!.listSync();
      final loadedConversations = <Conversation>[];

      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            loadedConversations.add(Conversation.fromJson(json));
          } catch (e) {
            debugPrint('Error loading conversation: $e');
          }
        }
      }

      _conversations = loadedConversations
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading conversations: $e');
    }
  }

  Future<void> _deleteConversationFile(String id) async {
    if (_conversationsDirectory == null) return;

    try {
      final file = File('${_conversationsDirectory!.path}/$id.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting conversation file: $e');
    }
  }
}

/// Conversation model
class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Message> messages;
  final String? modelName;
  final String? frameworkName;

  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.modelName,
    this.frameworkName,
  });

  String get lastMessagePreview {
    if (messages.isEmpty) return 'Start a conversation';

    final lastMessage = messages.last;
    final preview = lastMessage.content.trim().replaceAll('\n', ' ');

    return preview.length > 100 ? preview.substring(0, 100) : preview;
  }

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        messages: (json['messages'] as List<dynamic>)
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(),
        modelName: json['modelName'] as String?,
        frameworkName: json['frameworkName'] as String?,
      );
}

/// Message model
class Message {
  final String id;
  final proto.MessageRole role;
  final String content;
  final String? thinkingContent;
  final DateTime timestamp;
  final MessageAnalytics? analytics;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    this.thinkingContent,
    required this.timestamp,
    this.analytics,
  });

  Message copyWith({
    String? id,
    proto.MessageRole? role,
    String? content,
    String? thinkingContent,
    DateTime? timestamp,
    MessageAnalytics? analytics,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      timestamp: timestamp ?? this.timestamp,
      analytics: analytics ?? this.analytics,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: _messageRoleFromJson(json['role'] as String?),
        content: json['content'] as String,
        thinkingContent: json['thinkingContent'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        analytics: json['analytics'] != null
            ? MessageAnalytics.fromJson(
                json['analytics'] as Map<String, dynamic>)
            : null,
      );
}

/// Message analytics for tracking generation metrics
class MessageAnalytics {
  final String messageId;
  final String? modelName;
  final String? framework;
  final double? timeToFirstToken;
  final double? totalGenerationTime;
  final int inputTokens;
  final int outputTokens;
  final double? tokensPerSecond;
  final bool wasThinkingMode;
  final proto.ChatMessageStatus completionStatus;

  const MessageAnalytics({
    required this.messageId,
    this.modelName,
    this.framework,
    this.timeToFirstToken,
    this.totalGenerationTime,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.tokensPerSecond,
    this.wasThinkingMode = false,
    this.completionStatus =
        proto.ChatMessageStatus.CHAT_MESSAGE_STATUS_COMPLETE,
  });

  factory MessageAnalytics.fromJson(Map<String, dynamic> json) =>
      MessageAnalytics(
        messageId: json['messageId'] as String,
        modelName: json['modelName'] as String?,
        framework: json['framework'] as String?,
        timeToFirstToken: json['timeToFirstToken'] as double?,
        totalGenerationTime: json['totalGenerationTime'] as double?,
        inputTokens: json['inputTokens'] as int? ?? 0,
        outputTokens: json['outputTokens'] as int? ?? 0,
        tokensPerSecond: json['tokensPerSecond'] as double?,
        wasThinkingMode: json['wasThinkingMode'] as bool? ?? false,
        completionStatus:
            _chatMessageStatusFromJson(json['completionStatus'] as String?),
      );
}

proto.MessageRole _messageRoleFromJson(String? value) {
  switch (value) {
    case 'MESSAGE_ROLE_SYSTEM':
    case 'system':
      return proto.MessageRole.MESSAGE_ROLE_SYSTEM;
    case 'MESSAGE_ROLE_ASSISTANT':
    case 'assistant':
      return proto.MessageRole.MESSAGE_ROLE_ASSISTANT;
    case 'MESSAGE_ROLE_USER':
    case 'user':
      return proto.MessageRole.MESSAGE_ROLE_USER;
    default:
      return proto.MessageRole.MESSAGE_ROLE_USER;
  }
}

proto.ChatMessageStatus _chatMessageStatusFromJson(String? value) {
  switch (value) {
    case 'CHAT_MESSAGE_STATUS_PENDING':
      return proto.ChatMessageStatus.CHAT_MESSAGE_STATUS_PENDING;
    case 'CHAT_MESSAGE_STATUS_STREAMING':
      return proto.ChatMessageStatus.CHAT_MESSAGE_STATUS_STREAMING;
    case 'CHAT_MESSAGE_STATUS_FAILED':
    case 'failed':
    case 'timeout':
      return proto.ChatMessageStatus.CHAT_MESSAGE_STATUS_FAILED;
    case 'CHAT_MESSAGE_STATUS_CANCELLED':
    case 'interrupted':
      return proto.ChatMessageStatus.CHAT_MESSAGE_STATUS_CANCELLED;
    case 'CHAT_MESSAGE_STATUS_COMPLETE':
    case 'complete':
    default:
      return proto.ChatMessageStatus.CHAT_MESSAGE_STATUS_COMPLETE;
  }
}
