/// Message role in a conversation
/// Matches iOS MessageRole from Conversation.swift
enum MessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  final String value;
  const MessageRole(this.value);

  static MessageRole fromString(String value) {
    return MessageRole.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MessageRole.user,
    );
  }
}

/// A message in a conversation
/// Matches iOS Message from Conversation.swift
class Message {
  /// The role of the message sender
  final MessageRole role;

  /// The content of the message
  final String content;

  /// Optional metadata
  final Map<String, String>? metadata;

  /// Timestamp when the message was created
  final DateTime timestamp;

  Message({
    required this.role,
    required this.content,
    this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convenience constructor for user message
  factory Message.user(String content) {
    return Message(role: MessageRole.user, content: content);
  }

  /// Convenience constructor for assistant message
  factory Message.assistant(String content) {
    return Message(role: MessageRole.assistant, content: content);
  }

  /// Convenience constructor for system message
  factory Message.system(String content) {
    return Message(role: MessageRole.system, content: content);
  }

  Map<String, dynamic> toJson() => {
        'role': role.value,
        'content': content,
        if (metadata != null) 'metadata': metadata,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        role: MessageRole.fromString(json['role'] as String),
        content: json['content'] as String,
        metadata: json['metadata'] != null
            ? Map<String, String>.from(json['metadata'] as Map)
            : null,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : null,
      );
}

/// Context for a conversation
/// Matches iOS Context from Conversation.swift
class Context {
  /// System prompt for the conversation
  final String? systemPrompt;

  /// Previous messages in the conversation
  final List<Message> messages;

  /// Maximum number of messages to keep in context
  final int maxMessages;

  /// Additional context metadata
  final Map<String, String> metadata;

  Context({
    this.systemPrompt,
    List<Message>? messages,
    this.maxMessages = 100,
    Map<String, String>? metadata,
  })  : messages = messages ?? [],
        metadata = metadata ?? {};

  /// Add a message to the context
  Context adding(Message message) {
    final newMessages = List<Message>.from(messages)..add(message);

    // Trim if exceeds max
    final trimmedMessages = newMessages.length > maxMessages
        ? newMessages.sublist(newMessages.length - maxMessages)
        : newMessages;

    return Context(
      systemPrompt: systemPrompt,
      messages: trimmedMessages,
      maxMessages: maxMessages,
      metadata: metadata,
    );
  }

  /// Clear all messages but keep system prompt
  Context cleared() {
    return Context(
      systemPrompt: systemPrompt,
      messages: [],
      maxMessages: maxMessages,
      metadata: metadata,
    );
  }

  /// Build a prompt string from messages
  String buildPrompt() {
    final buffer = StringBuffer();

    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      buffer.writeln(systemPrompt);
      buffer.writeln();
    }

    for (final message in messages) {
      buffer.writeln(message.content);
    }

    return buffer.toString().trim();
  }
}

/// Token usage statistics
/// Matches iOS TokenUsage from LLMComponent.swift
class TokenUsage {
  final int promptTokens;
  final int completionTokens;

  TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
  });

  int get totalTokens => promptTokens + completionTokens;

  Map<String, dynamic> toJson() => {
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'totalTokens': totalTokens,
      };

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
        promptTokens: json['promptTokens'] as int,
        completionTokens: json['completionTokens'] as int,
      );
}

/// Generation metadata
/// Matches iOS GenerationMetadata from LLMComponent.swift
class GenerationMetadata {
  final String modelId;
  final double temperature;
  final double generationTime;
  final double? tokensPerSecond;

  GenerationMetadata({
    required this.modelId,
    required this.temperature,
    required this.generationTime,
    this.tokensPerSecond,
  });

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'temperature': temperature,
        'generationTime': generationTime,
        if (tokensPerSecond != null) 'tokensPerSecond': tokensPerSecond,
      };

  factory GenerationMetadata.fromJson(Map<String, dynamic> json) =>
      GenerationMetadata(
        modelId: json['modelId'] as String,
        temperature: (json['temperature'] as num).toDouble(),
        generationTime: (json['generationTime'] as num).toDouble(),
        tokensPerSecond: json['tokensPerSecond'] != null
            ? (json['tokensPerSecond'] as num).toDouble()
            : null,
      );
}

/// Reason for generation completion
/// Matches iOS FinishReason from LLMComponent.swift
enum FinishReason {
  completed('completed'),
  maxTokens('max_tokens'),
  stopSequence('stop_sequence'),
  contentFilter('content_filter'),
  error('error');

  final String value;
  const FinishReason(this.value);

  static FinishReason fromString(String value) {
    return FinishReason.values.firstWhere(
      (e) => e.value == value,
      orElse: () => FinishReason.completed,
    );
  }
}
