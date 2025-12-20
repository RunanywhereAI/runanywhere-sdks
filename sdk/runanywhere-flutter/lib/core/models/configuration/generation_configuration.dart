import '../framework/llm_framework.dart';

/// Default settings for text generation.
/// Matches iOS DefaultGenerationSettings from Configuration/GenerationConfiguration.swift
class DefaultGenerationSettings {
  /// Default temperature for generation
  final double temperature;

  /// Default maximum tokens for generation
  final int maxTokens;

  /// Default top-p value
  final double topP;

  /// Default top-k value
  final int? topK;

  /// Default repetition penalty
  final double? repetitionPenalty;

  /// Default stop sequences
  final List<String> stopSequences;

  const DefaultGenerationSettings({
    this.temperature = 0.7,
    this.maxTokens = 256,
    this.topP = 0.9,
    this.topK,
    this.repetitionPenalty,
    this.stopSequences = const [],
  });

  /// Create from JSON map
  factory DefaultGenerationSettings.fromJson(Map<String, dynamic> json) {
    return DefaultGenerationSettings(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 256,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      topK: (json['topK'] as num?)?.toInt(),
      repetitionPenalty: (json['repetitionPenalty'] as num?)?.toDouble(),
      stopSequences:
          (json['stopSequences'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'maxTokens': maxTokens,
      'topP': topP,
      if (topK != null) 'topK': topK,
      if (repetitionPenalty != null) 'repetitionPenalty': repetitionPenalty,
      'stopSequences': stopSequences,
    };
  }

  /// Create a copy with updated fields
  DefaultGenerationSettings copyWith({
    double? temperature,
    int? maxTokens,
    double? topP,
    int? topK,
    double? repetitionPenalty,
    List<String>? stopSequences,
  }) {
    return DefaultGenerationSettings(
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      stopSequences: stopSequences ?? this.stopSequences,
    );
  }
}

/// Token budget configuration for managing usage.
/// Matches iOS TokenBudgetConfiguration from Configuration/GenerationConfiguration.swift
class TokenBudgetConfiguration {
  /// Maximum tokens per request
  final int? maxTokensPerRequest;

  /// Maximum tokens per day
  final int? maxTokensPerDay;

  /// Maximum tokens per month
  final int? maxTokensPerMonth;

  /// Whether to enforce token limits strictly
  final bool enforceStrictly;

  const TokenBudgetConfiguration({
    this.maxTokensPerRequest,
    this.maxTokensPerDay,
    this.maxTokensPerMonth,
    this.enforceStrictly = false,
  });

  /// Create from JSON map
  factory TokenBudgetConfiguration.fromJson(Map<String, dynamic> json) {
    return TokenBudgetConfiguration(
      maxTokensPerRequest: (json['maxTokensPerRequest'] as num?)?.toInt(),
      maxTokensPerDay: (json['maxTokensPerDay'] as num?)?.toInt(),
      maxTokensPerMonth: (json['maxTokensPerMonth'] as num?)?.toInt(),
      enforceStrictly: json['enforceStrictly'] as bool? ?? false,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      if (maxTokensPerRequest != null)
        'maxTokensPerRequest': maxTokensPerRequest,
      if (maxTokensPerDay != null) 'maxTokensPerDay': maxTokensPerDay,
      if (maxTokensPerMonth != null) 'maxTokensPerMonth': maxTokensPerMonth,
      'enforceStrictly': enforceStrictly,
    };
  }

  /// Create a copy with updated fields
  TokenBudgetConfiguration copyWith({
    int? maxTokensPerRequest,
    int? maxTokensPerDay,
    int? maxTokensPerMonth,
    bool? enforceStrictly,
  }) {
    return TokenBudgetConfiguration(
      maxTokensPerRequest: maxTokensPerRequest ?? this.maxTokensPerRequest,
      maxTokensPerDay: maxTokensPerDay ?? this.maxTokensPerDay,
      maxTokensPerMonth: maxTokensPerMonth ?? this.maxTokensPerMonth,
      enforceStrictly: enforceStrictly ?? this.enforceStrictly,
    );
  }
}

/// Configuration for text generation behavior.
/// Matches iOS GenerationConfiguration from Configuration/GenerationConfiguration.swift
class GenerationConfiguration {
  /// Default generation settings
  final DefaultGenerationSettings defaults;

  /// Token budget configuration (optional)
  final TokenBudgetConfiguration? tokenBudget;

  /// Preferred frameworks for generation in order of preference
  final List<LLMFramework> frameworkPreferences;

  /// Maximum context length
  final int maxContextLength;

  /// Whether to enable thinking/reasoning extraction
  final bool enableThinkingExtraction;

  /// Pattern for thinking content extraction
  final String? thinkingPattern;

  const GenerationConfiguration({
    this.defaults = const DefaultGenerationSettings(),
    this.tokenBudget,
    this.frameworkPreferences = const [],
    this.maxContextLength = 4096,
    this.enableThinkingExtraction = false,
    this.thinkingPattern,
  });

  /// Create from JSON map
  factory GenerationConfiguration.fromJson(Map<String, dynamic> json) {
    return GenerationConfiguration(
      defaults: json['defaults'] != null
          ? DefaultGenerationSettings.fromJson(
              json['defaults'] as Map<String, dynamic>)
          : const DefaultGenerationSettings(),
      tokenBudget: json['tokenBudget'] != null
          ? TokenBudgetConfiguration.fromJson(
              json['tokenBudget'] as Map<String, dynamic>)
          : null,
      frameworkPreferences: (json['frameworkPreferences'] as List<dynamic>?)
              ?.map((e) => LLMFramework.fromRawValue(e as String))
              .whereType<LLMFramework>()
              .toList() ??
          [],
      maxContextLength: (json['maxContextLength'] as num?)?.toInt() ?? 4096,
      enableThinkingExtraction:
          json['enableThinkingExtraction'] as bool? ?? false,
      thinkingPattern: json['thinkingPattern'] as String?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'defaults': defaults.toJson(),
      if (tokenBudget != null) 'tokenBudget': tokenBudget!.toJson(),
      'frameworkPreferences':
          frameworkPreferences.map((f) => f.rawValue).toList(),
      'maxContextLength': maxContextLength,
      'enableThinkingExtraction': enableThinkingExtraction,
      if (thinkingPattern != null) 'thinkingPattern': thinkingPattern,
    };
  }

  /// Create a copy with updated fields
  GenerationConfiguration copyWith({
    DefaultGenerationSettings? defaults,
    TokenBudgetConfiguration? tokenBudget,
    List<LLMFramework>? frameworkPreferences,
    int? maxContextLength,
    bool? enableThinkingExtraction,
    String? thinkingPattern,
  }) {
    return GenerationConfiguration(
      defaults: defaults ?? this.defaults,
      tokenBudget: tokenBudget ?? this.tokenBudget,
      frameworkPreferences: frameworkPreferences ?? this.frameworkPreferences,
      maxContextLength: maxContextLength ?? this.maxContextLength,
      enableThinkingExtraction:
          enableThinkingExtraction ?? this.enableThinkingExtraction,
      thinkingPattern: thinkingPattern ?? this.thinkingPattern,
    );
  }
}
