/// OpenAI Compatible Provider
///
/// Built-in cloud provider for OpenAI-compatible APIs.
/// Works with OpenAI, Groq, Together, Ollama, vLLM, etc.
///
/// Mirrors Swift OpenAICompatibleProvider from Features/Cloud/OpenAICompatibleProvider.swift
library openai_compatible_provider;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:runanywhere/features/cloud/cloud_provider.dart';
import 'package:runanywhere/features/cloud/cloud_types.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

// MARK: - OpenAI Compatible Provider

/// Cloud provider for any OpenAI-compatible chat completions API.
///
/// Supports both streaming (SSE) and non-streaming responses.
///
/// ```dart
/// // OpenAI
/// final openai = OpenAICompatibleProvider(apiKey: 'sk-...', model: 'gpt-4o-mini');
///
/// // Groq
/// final groq = OpenAICompatibleProvider(
///   apiKey: 'gsk_...',
///   model: 'llama-3.1-8b-instant',
///   baseURL: Uri.parse('https://api.groq.com/openai/v1'),
/// );
///
/// // Local Ollama
/// final ollama = OpenAICompatibleProvider(
///   model: 'llama3.2',
///   baseURL: Uri.parse('http://localhost:11434/v1'),
/// );
/// ```
class OpenAICompatibleProvider implements CloudProvider {
  // MARK: - CloudProvider

  @override
  final String providerId;

  @override
  final String displayName;

  // MARK: - Configuration

  final String? _apiKey;
  final String _model;
  final Uri _baseURL;
  final Map<String, String> _additionalHeaders;
  final HttpClient _httpClient;
  final SDKLogger _logger;

  // MARK: - Init

  /// Create an OpenAI-compatible provider.
  ///
  /// - [providerId] Unique ID (default: auto-generated from base URL)
  /// - [displayName] Human-readable name
  /// - [apiKey] API key (null for local providers like Ollama)
  /// - [model] Default model to use
  /// - [baseURL] API base URL (default: OpenAI)
  /// - [additionalHeaders] Extra headers to send with every request
  OpenAICompatibleProvider({
    String? providerId,
    String? displayName,
    String? apiKey,
    required String model,
    Uri? baseURL,
    Map<String, String> additionalHeaders = const {},
  })  : _apiKey = apiKey,
        _model = model,
        _baseURL = baseURL ?? Uri.parse('https://api.openai.com/v1'),
        _additionalHeaders = additionalHeaders,
        _httpClient = HttpClient(),
        _logger = SDKLogger('OpenAICompatibleProvider'),
        providerId = providerId ??
            'openai-compat-${(baseURL ?? Uri.parse("https://api.openai.com/v1")).host}',
        displayName = displayName ??
            'OpenAI Compatible (${(baseURL ?? Uri.parse("https://api.openai.com/v1")).host})';

  // MARK: - CloudProvider Implementation

  @override
  Future<CloudGenerationResult> generate(
    String prompt,
    CloudGenerationOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();

    final messages = _buildMessages(prompt, options);
    final requestBody = _buildRequestBody(messages, options, stream: false);

    final data = await _performRequest(requestBody);
    stopwatch.stop();

    final response = jsonDecode(data) as Map<String, dynamic>;
    final choices = response['choices'] as List<dynamic>? ?? [];
    final text = choices.isNotEmpty
        ? ((choices[0] as Map<String, dynamic>)['message']
                as Map<String, dynamic>)['content'] as String? ??
            ''
        : '';

    final usage = response['usage'] as Map<String, dynamic>?;
    final promptTokens = usage?['prompt_tokens'] as int? ?? 0;
    final completionTokens = usage?['completion_tokens'] as int? ?? 0;

    return CloudGenerationResult(
      text: text,
      inputTokens: promptTokens,
      outputTokens: completionTokens,
      latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
      providerId: providerId,
      model: options.model,
    );
  }

  @override
  Stream<String> generateStream(
    String prompt,
    CloudGenerationOptions options,
  ) {
    final controller = StreamController<String>();

    _streamGeneration(prompt, options, controller);

    return controller.stream;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final url = _baseURL.resolve('models');
      final request = await _httpClient.getUrl(url);
      request.headers.set('Content-Type', 'application/json');
      if (_apiKey != null) {
        request.headers.set('Authorization', 'Bearer $_apiKey');
      }

      final response =
          await request.close().timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      _logger.debug('Provider availability check failed: $e');
      return false;
    }
  }

  // MARK: - Internal Helpers

  Future<void> _streamGeneration(
    String prompt,
    CloudGenerationOptions options,
    StreamController<String> controller,
  ) async {
    try {
      final messages = _buildMessages(prompt, options);
      final requestBody = _buildRequestBody(messages, options, stream: true);
      final request = await _buildHttpRequest(requestBody);

      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        controller.addError(
          CloudProviderException.httpError(response.statusCode),
        );
        await controller.close();
        return;
      }

      // Parse SSE stream
      await response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') return;

          try {
            final chunk = jsonDecode(data) as Map<String, dynamic>;
            final choices = chunk['choices'] as List<dynamic>? ?? [];
            if (choices.isNotEmpty) {
              final delta = (choices[0] as Map<String, dynamic>)['delta']
                  as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null) {
                controller.add(content);
              }
            }
          } catch (e) {
            // Skip malformed chunks
            _logger.debug('Skipping malformed SSE chunk: $e');
          }
        }
      });

      await controller.close();
    } catch (e) {
      controller.addError(e);
      await controller.close();
    }
  }

  List<Map<String, String>> _buildMessages(
    String prompt,
    CloudGenerationOptions options,
  ) {
    if (options.messages != null && options.messages!.isNotEmpty) {
      return options.messages!.map((m) => m.toJson()).toList();
    }

    final msgs = <Map<String, String>>[];
    if (options.systemPrompt != null) {
      msgs.add({'role': 'system', 'content': options.systemPrompt!});
    }
    msgs.add({'role': 'user', 'content': prompt});
    return msgs;
  }

  Map<String, dynamic> _buildRequestBody(
    List<Map<String, String>> messages,
    CloudGenerationOptions options, {
    required bool stream,
  }) {
    return {
      'model': options.model,
      'messages': messages,
      'max_tokens': options.maxTokens,
      'temperature': options.temperature,
      'stream': stream,
    };
  }

  Future<HttpClientRequest> _buildHttpRequest(
    Map<String, dynamic> body,
  ) async {
    final url = _baseURL.resolve('chat/completions');
    final request = await _httpClient.postUrl(url);

    request.headers.set('Content-Type', 'application/json');

    if (_apiKey != null) {
      request.headers.set('Authorization', 'Bearer $_apiKey');
    }

    for (final entry in _additionalHeaders.entries) {
      request.headers.set(entry.key, entry.value);
    }

    request.write(jsonEncode(body));
    return request;
  }

  Future<String> _performRequest(Map<String, dynamic> body) async {
    final request = await _buildHttpRequest(body);
    final response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudProviderException.httpError(response.statusCode);
    }

    return await response.transform(utf8.decoder).join();
  }
}
