// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:async';

import 'llm_session.dart';
import 'types.dart';

enum ChatRole { system, user, assistant, tool }

class ChatMessage {
  final ChatRole role;
  final String content;
  const ChatMessage(this.role, this.content);

  factory ChatMessage.system(String c)    => ChatMessage(ChatRole.system, c);
  factory ChatMessage.user(String c)      => ChatMessage(ChatRole.user, c);
  factory ChatMessage.assistant(String c) => ChatMessage(ChatRole.assistant, c);
  factory ChatMessage.tool(String c)      => ChatMessage(ChatRole.tool, c);
}

/// Chat wrapper over LLMSession. Message history + token stream.
class ChatSession {
  final LLMSession llm;
  bool _systemInjected = false;

  ChatSession(String modelId, String modelPath,
              {String systemPrompt = '',
               ModelFormat format = ModelFormat.gguf})
      : llm = LLMSession(modelId, modelPath, format: format) {
    if (systemPrompt.isNotEmpty) {
      final rc = llm.injectSystemPrompt(systemPrompt);
      _systemInjected = rc == 0;
    }
  }

  Stream<String> generate(List<ChatMessage> messages) async* {
    final rendered = renderMessages(messages, skipSystem: _systemInjected);
    final tokens = _systemInjected
        ? llm.generateFromContext(rendered)
        : llm.generate(rendered);
    await for (final t in tokens) {
      if (t.kind == LLMTokenKind.answer) yield t.text;
    }
  }

  Future<String> generateText(List<ChatMessage> messages) async {
    final buf = StringBuffer();
    await for (final chunk in generate(messages)) { buf.write(chunk); }
    return buf.toString();
  }

  int cancel() => llm.cancel();
  int resetHistory() {
    _systemInjected = false;
    return llm.clearContext();
  }
  void close() => llm.close();

  static String renderMessages(List<ChatMessage> messages,
                                 {bool skipSystem = false}) {
    final sb = StringBuffer();
    for (final m in messages) {
      if (skipSystem && m.role == ChatRole.system) continue;
      sb.write('<|im_start|>${m.role.name}\n${m.content}<|im_end|>\n');
    }
    sb.write('<|im_start|>assistant\n');
    return sb.toString();
  }
}
