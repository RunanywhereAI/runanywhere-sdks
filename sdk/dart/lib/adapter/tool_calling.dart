// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'dart:convert';

import 'chat_session.dart';

class ToolParameter {
  final String name;
  final String type;
  final String description;
  final bool required;
  const ToolParameter({required this.name, required this.type,
                       required this.description, this.required = true});
}

class ToolDefinition {
  final String name;
  final String description;
  final List<ToolParameter> parameters;
  const ToolDefinition({required this.name, required this.description,
                         required this.parameters});
}

class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;
  const ToolCall(this.name, this.arguments);
}

typedef ToolExecutor = Future<String> Function(Map<String, dynamic> args);

class ToolFormatter {
  static String systemPrompt(List<ToolDefinition> tools) {
    if (tools.isEmpty) return '';
    final sb = StringBuffer('You have access to the following tools:\n\n');
    for (final t in tools) {
      sb.write('${t.name}: ${t.description}\nArguments:\n{\n');
      for (final p in t.parameters) {
        final req = p.required ? '' : ' (optional)';
        sb.write('    "${p.name}": <${p.type}>  // ${p.description}$req\n');
      }
      sb.write('}\n\n');
    }
    sb.write('''

To invoke a tool, reply with EXACTLY:
<tool_call>{"name":"<tool_name>","arguments":{<args_json>}}</tool_call>

Only output the tool call and nothing else when you use a tool.
'''.trim());
    return sb.toString();
  }

  static List<ToolCall> parseToolCalls(String text) {
    final calls = <ToolCall>[];
    final re = RegExp(r'<tool_call>([\s\S]*?)</tool_call>');
    for (final m in re.allMatches(text)) {
      final raw = m.group(1)?.trim();
      if (raw == null) continue;
      try {
        final obj = jsonDecode(raw) as Map<String, dynamic>;
        final name = obj['name'];
        final args = obj['arguments'];
        if (name is String && args is Map) {
          calls.add(ToolCall(name, args.cast<String, dynamic>()));
        }
      } catch (_) { /* skip malformed */ }
    }
    return calls;
  }
}

sealed class ToolCallingReply {
  const ToolCallingReply();
}
class AssistantReply extends ToolCallingReply {
  final String text;
  const AssistantReply(this.text);
}
class ToolCallsReply extends ToolCallingReply {
  final List<ToolCall> calls;
  const ToolCallsReply(this.calls);
}

class ToolCallingAgent {
  final ChatSession _chat;
  final List<ChatMessage> _history = [];

  ToolCallingAgent({
    required String modelId,
    required String modelPath,
    required List<ToolDefinition> tools,
    String systemPrompt = '',
  }) : _chat = ChatSession(
          modelId, modelPath,
          systemPrompt: [systemPrompt, ToolFormatter.systemPrompt(tools)]
              .where((s) => s.isNotEmpty).join('\n\n'),
        );

  Future<ToolCallingReply> send(String userMessage) async {
    _history.add(ChatMessage.user(userMessage));
    final response = await _chat.generateText(_history);
    _history.add(ChatMessage.assistant(response));
    final calls = ToolFormatter.parseToolCalls(response);
    return calls.isNotEmpty ? ToolCallsReply(calls) : AssistantReply(response);
  }

  Future<ToolCallingReply> continueAfter(List<(String, String)> results) async {
    final blob = results.map((r) => 'Tool `${r.$1}` returned:\n${r.$2}').join('\n\n');
    _history.add(ChatMessage.tool(blob));
    final response = await _chat.generateText(_history);
    _history.add(ChatMessage.assistant(response));
    final calls = ToolFormatter.parseToolCalls(response);
    return calls.isNotEmpty ? ToolCallsReply(calls) : AssistantReply(response);
  }

  void resetHistory() {
    _history.clear();
    _chat.resetHistory();
  }

  void close() => _chat.close();
}
