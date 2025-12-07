/// LLM template types for different model architectures.
///
/// This is the Flutter equivalent of Swift's LLM Template enum.
enum LLMTemplate {
  /// ChatML format (used by Qwen, OpenAI-style models)
  chatML('chatML'),

  /// Alpaca instruction format
  alpaca('alpaca'),

  /// Llama 2 chat format
  llama('llama'),

  /// Mistral instruct format
  mistral('mistral'),

  /// Gemma instruction format
  gemma('gemma'),

  /// Vicuna chat format
  vicuna('vicuna'),

  /// Raw/no template
  none('none');

  final String name;

  const LLMTemplate(this.name);
}

/// Utility for determining the appropriate LLM template based on model characteristics.
///
/// This is the Flutter equivalent of Swift's `LLMSwiftTemplateResolver`.
class LlamaCppTemplateResolver {
  /// Determine the appropriate template for a model.
  ///
  /// [modelPath] - Path to the model file
  /// [systemPrompt] - Optional system prompt (stored for use during generation)
  ///
  /// Returns the appropriate [LLMTemplate] for the model.
  static LLMTemplate determineTemplate(
    String modelPath, {
    String? systemPrompt,
  }) {
    final filename = modelPath.split('/').last.toLowerCase();

    // TinyLlama usually uses ChatML (check before 'llama' since it contains 'llama')
    if (filename.contains('tinyllama')) {
      return LLMTemplate.chatML;
    }

    // Phi models use ChatML
    if (filename.contains('phi')) {
      return LLMTemplate.chatML;
    }

    // Qwen models typically use ChatML format
    if (filename.contains('qwen')) {
      return LLMTemplate.chatML;
    }

    // ChatML / OpenAI style
    if (filename.contains('chatml') || filename.contains('openai')) {
      return LLMTemplate.chatML;
    }

    // Alpaca format
    if (filename.contains('alpaca')) {
      return LLMTemplate.alpaca;
    }

    // Mistral format (check before llama since some mistral models might contain 'llama')
    if (filename.contains('mistral')) {
      return LLMTemplate.mistral;
    }

    // Gemma format
    if (filename.contains('gemma')) {
      return LLMTemplate.gemma;
    }

    // Vicuna format
    if (filename.contains('vicuna')) {
      return LLMTemplate.vicuna;
    }

    // Llama format (generic llama check last after more specific patterns)
    if (filename.contains('llama')) {
      return LLMTemplate.llama;
    }

    // Default to ChatML
    return LLMTemplate.chatML;
  }

  /// Format a prompt using the specified template.
  ///
  /// [template] - The template to use
  /// [prompt] - The user's prompt
  /// [systemPrompt] - Optional system prompt
  ///
  /// Returns the formatted prompt string.
  static String formatPrompt(
    LLMTemplate template,
    String prompt, {
    String? systemPrompt,
  }) {
    switch (template) {
      case LLMTemplate.chatML:
        return _formatChatML(prompt, systemPrompt);
      case LLMTemplate.alpaca:
        return _formatAlpaca(prompt, systemPrompt);
      case LLMTemplate.llama:
        return _formatLlama(prompt, systemPrompt);
      case LLMTemplate.mistral:
        return _formatMistral(prompt);
      case LLMTemplate.gemma:
        return _formatGemma(prompt);
      case LLMTemplate.vicuna:
        return _formatVicuna(prompt, systemPrompt);
      case LLMTemplate.none:
        return prompt;
    }
  }

  static String _formatChatML(String prompt, String? systemPrompt) {
    final buffer = StringBuffer();
    if (systemPrompt != null) {
      buffer.writeln('<|im_start|>system');
      buffer.writeln(systemPrompt);
      buffer.writeln('<|im_end|>');
    }
    buffer.writeln('<|im_start|>user');
    buffer.writeln(prompt);
    buffer.writeln('<|im_end|>');
    buffer.writeln('<|im_start|>assistant');
    return buffer.toString();
  }

  static String _formatAlpaca(String prompt, String? systemPrompt) {
    final buffer = StringBuffer();
    if (systemPrompt != null) {
      buffer.writeln('### System:');
      buffer.writeln(systemPrompt);
      buffer.writeln();
    }
    buffer.writeln('### Instruction:');
    buffer.writeln(prompt);
    buffer.writeln();
    buffer.writeln('### Response:');
    return buffer.toString();
  }

  static String _formatLlama(String prompt, String? systemPrompt) {
    final buffer = StringBuffer();
    buffer.write('[INST] ');
    if (systemPrompt != null) {
      buffer.write('<<SYS>>\n$systemPrompt\n<</SYS>>\n\n');
    }
    buffer.write('$prompt [/INST]');
    return buffer.toString();
  }

  static String _formatMistral(String prompt) {
    return '[INST] $prompt [/INST]';
  }

  static String _formatGemma(String prompt) {
    return '<start_of_turn>user\n$prompt<end_of_turn>\n<start_of_turn>model\n';
  }

  static String _formatVicuna(String prompt, String? systemPrompt) {
    final buffer = StringBuffer();
    if (systemPrompt != null) {
      buffer.writeln(systemPrompt);
      buffer.writeln();
    }
    buffer.writeln('USER: $prompt');
    buffer.write('ASSISTANT: ');
    return buffer.toString();
  }
}
