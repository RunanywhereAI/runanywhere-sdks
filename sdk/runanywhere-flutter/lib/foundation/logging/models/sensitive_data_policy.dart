/// Policy for handling sensitive data in logs
///
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Models/SensitiveDataPolicy.swift
enum SensitiveDataPolicy {
  /// Data is not sensitive - can be logged locally and remotely
  none,

  /// Data contains sensitive information - log locally only in debug mode, never remotely
  sensitive,

  /// Data is critical - never log the actual content, only log category/type
  critical,

  /// Completely redact - don't log at all
  redacted,
}

/// Categories of sensitive data for classification
enum SensitiveDataCategory {
  // Authentication & Credentials
  apiKey,
  bearerToken,
  password,
  credential,

  // User Content
  userPrompt,
  generatedResponse,
  conversationHistory,
  systemPrompt,
  userMessage,

  // Personal Information
  userId,
  email,
  phoneNumber,
  deviceIdentifier,

  // Configuration & System
  modelPath,
  fileSystemPath,
  internalURL,
  errorDetails,

  // Business Logic
  costCalculation,
  routingDecision,
  performanceMetric,
}

/// Extension for SensitiveDataCategory
extension SensitiveDataCategoryExtension on SensitiveDataCategory {
  /// Get the default policy for this category
  SensitiveDataPolicy get defaultPolicy {
    switch (this) {
      case SensitiveDataCategory.apiKey:
      case SensitiveDataCategory.bearerToken:
      case SensitiveDataCategory.password:
      case SensitiveDataCategory.credential:
        return SensitiveDataPolicy.redacted;

      case SensitiveDataCategory.userPrompt:
      case SensitiveDataCategory.generatedResponse:
      case SensitiveDataCategory.conversationHistory:
      case SensitiveDataCategory.systemPrompt:
      case SensitiveDataCategory.userMessage:
        return SensitiveDataPolicy.critical;

      case SensitiveDataCategory.userId:
      case SensitiveDataCategory.email:
      case SensitiveDataCategory.phoneNumber:
      case SensitiveDataCategory.deviceIdentifier:
        return SensitiveDataPolicy.critical;

      case SensitiveDataCategory.modelPath:
      case SensitiveDataCategory.fileSystemPath:
      case SensitiveDataCategory.internalURL:
        return SensitiveDataPolicy.sensitive;

      case SensitiveDataCategory.errorDetails:
      case SensitiveDataCategory.costCalculation:
      case SensitiveDataCategory.routingDecision:
      case SensitiveDataCategory.performanceMetric:
        return SensitiveDataPolicy.sensitive;
    }
  }

  /// Get the sanitized placeholder for this category
  String get sanitizedPlaceholder {
    switch (this) {
      case SensitiveDataCategory.apiKey:
        return '[API_KEY]';
      case SensitiveDataCategory.bearerToken:
        return '[TOKEN]';
      case SensitiveDataCategory.password:
        return '[PASSWORD]';
      case SensitiveDataCategory.credential:
        return '[CREDENTIAL]';
      case SensitiveDataCategory.userPrompt:
        return '[USER_PROMPT]';
      case SensitiveDataCategory.generatedResponse:
        return '[GENERATED_RESPONSE]';
      case SensitiveDataCategory.conversationHistory:
        return '[CONVERSATION]';
      case SensitiveDataCategory.systemPrompt:
        return '[SYSTEM_PROMPT]';
      case SensitiveDataCategory.userMessage:
        return '[USER_MESSAGE]';
      case SensitiveDataCategory.userId:
        return '[USER_ID]';
      case SensitiveDataCategory.email:
        return '[EMAIL]';
      case SensitiveDataCategory.phoneNumber:
        return '[PHONE]';
      case SensitiveDataCategory.deviceIdentifier:
        return '[DEVICE_ID]';
      case SensitiveDataCategory.modelPath:
        return '[MODEL_PATH]';
      case SensitiveDataCategory.fileSystemPath:
        return '[FILE_PATH]';
      case SensitiveDataCategory.internalURL:
        return '[URL]';
      case SensitiveDataCategory.errorDetails:
        return '[ERROR_DETAILS]';
      case SensitiveDataCategory.costCalculation:
        return '[COST_DATA]';
      case SensitiveDataCategory.routingDecision:
        return '[ROUTING_DATA]';
      case SensitiveDataCategory.performanceMetric:
        return '[PERFORMANCE_DATA]';
    }
  }
}

/// Metadata keys for marking sensitive data
class LogMetadataKeys {
  LogMetadataKeys._();

  static const String sensitiveDataPolicy = '__sensitive_data_policy';
  static const String sensitiveDataCategory = '__sensitive_data_category';
  static const String isUserContent = '__is_user_content';
  static const String containsPII = '__contains_pii';
  static const String sanitized = '__sanitized';
}
