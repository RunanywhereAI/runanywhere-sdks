import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/runanywhere.dart' show MessageRole;

import 'package:runanywhere_ai/core/models/app_types.dart';

/// ConversationStore (mirroring iOS ConversationStore.swift)
///
/// File-based persistence for conversation history with search and CRUD operations.
class ConversationStore extends ChangeNotifier {
  static final ConversationStore shared = ConversationStore._();

  ConversationStore._() {
    unawaited(_initialize());
  }

  List<Conversation> _conversations = [];
  Conversation? _currentConversation;
  Directory? _conversationsDirectory;

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

  /// Create a new conversation
  Conversation createConversation({String? title}) {
    final conversation = Conversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title ?? 'New Chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [],
    );

    _conversations.insert(0, conversation);
    _currentConversation = conversation;
    unawaited(_saveConversation(conversation));
    notifyListeners();

    return conversation;
  }

  /// Update an existing conversation
  void updateConversation(Conversation conversation) {
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index != -1) {
      final updated = conversation.copyWith(updatedAt: DateTime.now());
      _conversations[index] = updated;

      if (_currentConversation?.id == conversation.id) {
        _currentConversation = updated;
      }

      unawaited(_saveConversation(updated));
      notifyListeners();
    }
  }

  /// Delete a conversation
  void deleteConversation(Conversation conversation) {
    _conversations.removeWhere((c) => c.id == conversation.id);

    if (_currentConversation?.id == conversation.id) {
      _currentConversation =
          _conversations.isNotEmpty ? _conversations.first : null;
    }

    unawaited(_deleteConversationFile(conversation.id));
    notifyListeners();
  }

  /// Add a message to a conversation
  void addMessage(Message message, Conversation conversation) {
    var updated = conversation.copyWith(
      messages: [...conversation.messages, message],
      updatedAt: DateTime.now(),
    );

    // Auto-generate title from first user message
    if (updated.title == 'New Chat' &&
        message.role == MessageRole.user &&
        message.content.isNotEmpty) {
      updated = updated.copyWith(title: _generateTitle(message.content));
    }

    updateConversation(updated);
  }

  /// Load a specific conversation
  Conversation? loadConversation(String id) {
    final existing = _conversations.firstWhere(
      (c) => c.id == id,
      orElse: Conversation.empty,
    );

    if (existing.id.isNotEmpty) {
      _currentConversation = existing;
      notifyListeners();
      return existing;
    }

    return null;
  }

  /// Search conversations by query
  List<Conversation> searchConversations(String query) {
    if (query.isEmpty) return _conversations;

    final lowercasedQuery = query.toLowerCase();

    return _conversations.where((conversation) {
      if (conversation.title.toLowerCase().contains(lowercasedQuery)) {
        return true;
      }

      return conversation.messages.any(
        (message) => message.content.toLowerCase().contains(lowercasedQuery),
      );
    }).toList();
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
    if (_conversationsDirectory == null) return;

    try {
      final file =
          File('${_conversationsDirectory!.path}/${conversation.id}.json');
      final json = jsonEncode(conversation.toJson());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('Error saving conversation: $e');
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

  String _generateTitle(String content) {
    const maxLength = 50;
    final cleaned = content.trim();

    final newlineIndex = cleaned.indexOf('\n');
    if (newlineIndex != -1) {
      final firstLine = cleaned.substring(0, newlineIndex);
      return firstLine.length > maxLength
          ? firstLine.substring(0, maxLength)
          : firstLine;
    }

    return cleaned.length > maxLength
        ? cleaned.substring(0, maxLength)
        : cleaned;
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

  factory Conversation.empty() => Conversation(
        id: '',
        title: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [],
      );

  Conversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Message>? messages,
    String? modelName,
    String? frameworkName,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      modelName: modelName ?? this.modelName,
      frameworkName: frameworkName ?? this.frameworkName,
    );
  }

  String get summary {
    if (messages.isEmpty) return 'No messages';

    final messageCount = messages.length;
    final userMessages =
        messages.where((m) => m.role == MessageRole.user).length;
    final assistantMessages =
        messages.where((m) => m.role == MessageRole.assistant).length;

    return '$messageCount messages • $userMessages from you, $assistantMessages from AI';
  }

  String get lastMessagePreview {
    if (messages.isEmpty) return 'Start a conversation';

    final lastMessage = messages.last;
    final preview = lastMessage.content.trim().replaceAll('\n', ' ');

    return preview.length > 100 ? preview.substring(0, 100) : preview;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'modelName': modelName,
        'frameworkName': frameworkName,
      };

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
  final MessageRole role;
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
    MessageRole? role,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'thinkingContent': thinkingContent,
        'timestamp': timestamp.toIso8601String(),
        'analytics': analytics?.toJson(),
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: MessageRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => MessageRole.user,
        ),
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
  final CompletionStatus completionStatus;

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
    this.completionStatus = CompletionStatus.complete,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'modelName': modelName,
        'framework': framework,
        'timeToFirstToken': timeToFirstToken,
        'totalGenerationTime': totalGenerationTime,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'tokensPerSecond': tokensPerSecond,
        'wasThinkingMode': wasThinkingMode,
        'completionStatus': completionStatus.name,
      };

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
        completionStatus: CompletionStatus.values.firstWhere(
          (s) => s.name == json['completionStatus'],
          orElse: () => CompletionStatus.complete,
        ),
      );
}
