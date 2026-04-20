// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

class ParseFailedException implements Exception {
  final String message;
  ParseFailedException(this.message);
  @override
  String toString() => 'ParseFailedException: $message';
}

class StructuredOutput {
  /// Extract the first top-level JSON object from arbitrary text.
  static String extractJSON(String text) {
    // Try fenced ```json … ``` first
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) {
      final stripped = (fence.group(1) ?? '').trim();
      if (stripped.startsWith('{') || stripped.startsWith('[')) return stripped;
    }
    final start = text.indexOf('{');
    if (start < 0) throw ParseFailedException("no '{' in: $text");
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (escaped) { escaped = false; continue; }
      if (c == r'\') { escaped = true; continue; }
      if (c == '"') { inString = !inString; continue; }
      if (inString) continue;
      if (c == '{') depth++;
      else if (c == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    throw ParseFailedException('unbalanced braces in: $text');
  }
}
