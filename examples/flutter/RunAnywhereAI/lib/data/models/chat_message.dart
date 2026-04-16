import 'package:uuid/uuid.dart';

enum MessageRole { system, user, assistant }

class MessageAnalytics {
  const MessageAnalytics({
    this.timeToFirstTokenMs,
    this.totalGenerationMs,
    this.outputTokens,
    this.tokensPerSecond,
  });

  final double? timeToFirstTokenMs;
  final double? totalGenerationMs;
  final int? outputTokens;
  final double? tokensPerSecond;
}

class ChatMessage {
  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.thinkingContent,
    this.analytics,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  final String id;
  final MessageRole role;
  final String content;
  final String? thinkingContent;
  final MessageAnalytics? analytics;
  final DateTime timestamp;

  ChatMessage copyWith({
    String? content,
    String? thinkingContent,
    MessageAnalytics? analytics,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      analytics: analytics ?? this.analytics,
      timestamp: timestamp,
    );
  }
}
