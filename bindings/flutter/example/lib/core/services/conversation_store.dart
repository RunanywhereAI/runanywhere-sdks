import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/runanywhere_protos.dart' as proto;

/// File-based persistence for conversation history.
///
/// Mirrors iOS `Core/Services/ConversationStore.swift`: conversations are
/// created in-memory, become persistent on the first message, and every
/// update is written back to a `Conversations/<id>.json` file.
class ConversationStore extends ChangeNotifier {
  static final ConversationStore shared = ConversationStore._();

  ConversationStore._() {
    unawaited(_ready);
  }

  static const _defaultTitle = 'New Chat';
  static const _encoder = JsonEncoder.withIndent('  ');

  List<Conversation> _conversations = [];
  Conversation? _currentConversation;
  Directory? _conversationsDirectory;
  late final Future<void> _ready = _initialize();

  List<Conversation> get conversations => _conversations;
  Conversation? get currentConversation => _currentConversation;

  Future<void> _initialize() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    _conversationsDirectory = Directory('${documentsDir.path}/Conversations');

    if (!await _conversationsDirectory!.exists()) {
      await _conversationsDirectory!.create(recursive: true);
    }

    await loadConversations();
  }

  /// Create a new conversation. Not added to the list or written to disk
  /// until the first message arrives (iOS parity).
  Conversation createConversation({String? title}) {
    final now = DateTime.now();
    final conversation = Conversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: title ?? _defaultTitle,
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    _currentConversation = conversation;
    return conversation;
  }

  /// Insert or update [conversation], persist it to disk, and return the
  /// stored copy (with a refreshed `updatedAt`).
  Conversation updateConversation(Conversation conversation) {
    final updated = conversation.copyWith(updatedAt: DateTime.now());

    final index = _conversations.indexWhere((c) => c.id == updated.id);
    if (index >= 0) {
      _conversations[index] = updated;
    } else {
      // First time this conversation is persisted (first message sent).
      _conversations.insert(0, updated);
    }

    if (_currentConversation?.id == updated.id) {
      _currentConversation = updated;
    }

    unawaited(_saveConversation(updated));
    notifyListeners();
    return updated;
  }

  /// Append [message] to [conversation], derive a title from the first user
  /// message if still untitled, persist, and return the updated conversation.
  ///
  /// iOS additionally generates "smart titles" via Apple FoundationModels —
  /// that path is Apple-platform-gated, so Flutter keeps the deterministic
  /// fallback title only.
  Conversation addMessage(Message message, Conversation conversation) {
    var updated = conversation.copyWith(
      messages: [...conversation.messages, message],
    );

    if (updated.title == _defaultTitle) {
      final firstUserContent = updated.messages
          .firstWhere(
            (m) =>
                m.role == proto.MessageRole.MESSAGE_ROLE_USER &&
                m.content.trim().isNotEmpty,
            orElse: () => message,
          )
          .content;
      if (firstUserContent.trim().isNotEmpty) {
        updated = updated.copyWith(title: _generateTitle(firstUserContent));
      }
    }

    return updateConversation(updated);
  }

  /// Delete a conversation
  void deleteConversation(Conversation conversation) {
    _conversations.removeWhere((c) => c.id == conversation.id);
    if (_currentConversation?.id == conversation.id) {
      _currentConversation = null;
    }
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

  Future<void> _saveConversation(Conversation conversation) async {
    await _ready;
    try {
      final file = File('${_conversationsDirectory!.path}/${conversation.id}.json');
      await file.writeAsString(_encoder.convert(conversation.toJson()));
    } catch (e) {
      debugPrint('Error saving conversation: $e');
    }
  }

  Future<void> _deleteConversationFile(String id) async {
    await _ready;

    try {
      final file = File('${_conversationsDirectory!.path}/$id.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting conversation file: $e');
    }
  }

  /// Deterministic title fallback: first line of the first user message,
  /// capped at 50 characters (mirrors iOS `generateTitle(from:)`).
  String _generateTitle(String content) {
    const maxLength = 50;
    final cleaned = content.trim();
    final firstLine = cleaned.split('\n').first;
    return firstLine.length > maxLength
        ? firstLine.substring(0, maxLength)
        : firstLine;
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

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<Message>? messages,
    String? modelName,
    String? frameworkName,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      modelName: modelName ?? this.modelName,
      frameworkName: frameworkName ?? this.frameworkName,
    );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        if (modelName != null) 'modelName': modelName,
        if (frameworkName != null) 'frameworkName': frameworkName,
      };
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        if (thinkingContent != null) 'thinkingContent': thinkingContent,
        'timestamp': timestamp.toIso8601String(),
        if (analytics != null) 'analytics': analytics!.toJson(),
      };
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

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        if (modelName != null) 'modelName': modelName,
        if (framework != null) 'framework': framework,
        if (timeToFirstToken != null) 'timeToFirstToken': timeToFirstToken,
        if (totalGenerationTime != null)
          'totalGenerationTime': totalGenerationTime,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        if (tokensPerSecond != null) 'tokensPerSecond': tokensPerSecond,
        'wasThinkingMode': wasThinkingMode,
        'completionStatus': completionStatus.name,
      };
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
