/// Context Manager for conversation context
/// Similar to Swift SDK's ContextManager
class ContextManager {
  final List<String> _messages = [];
  final int _maxContextLength;

  ContextManager({int maxContextLength = 2048}) : _maxContextLength = maxContextLength;

  /// Add a message to context
  void addMessage(String role, String content) {
    _messages.add('$role: $content');
  }

  /// Get formatted context
  String getContext() {
    return _messages.join('\n');
  }

  /// Clear context
  void clearContext() {
    _messages.clear();
  }

  /// Trim context if too long
  void trimContext() {
    final context = getContext();
    if (context.length > _maxContextLength) {
      // Remove oldest messages
      while (getContext().length > _maxContextLength && _messages.isNotEmpty) {
        _messages.removeAt(0);
      }
    }
  }

  /// Get context length
  int getContextLength() {
    return getContext().length;
  }
}

