/// Message Types
///
/// Types for conversation messages.
/// Mirrors Swift MessageRole from the RunAnywhere SDK.
library message_types;

/// Role of a message in a conversation
enum MessageRole {
  system,
  user,
  assistant;

  String get rawValue => name;
}
