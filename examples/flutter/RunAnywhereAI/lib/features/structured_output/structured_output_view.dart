import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';

/// StructuredOutputView - Demonstrates structured output functionality
///
/// Provides examples for both generate() and generateStream() with
/// various JSON schema templates and prompt templates.
class StructuredOutputView extends StatefulWidget {
  const StructuredOutputView({super.key});

  @override
  State<StructuredOutputView> createState() => _StructuredOutputViewState();
}

class _StructuredOutputViewState extends State<StructuredOutputView> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Selected example
  int _selectedExampleIndex = 0;
  bool _useStream = false;

  // State
  bool _isGenerating = false;
  String? _errorMessage;
  String? _rawResponse;
  Map<String, dynamic>? _structuredData;

  // Examples with both schema and prompt templates
  final List<StructuredOutputExample> _examples = [
    StructuredOutputExample(
      name: 'Recipe',
      typeName: 'Recipe',
      schema: '''{
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "ingredients": { "type": "array", "items": { "type": "string" } },
          "steps": { "type": "array", "items": { "type": "string" } },
          "cookingTime": { "type": "integer" }
        },
        "required": ["name", "ingredients", "steps", "cookingTime"]
      }''',
      promptTemplates: [
        'Generate a recipe for homemade pasta',
        'Give me a quick breakfast recipe with eggs',
        'Create a vegan dessert recipe',
      ],
    ),
    StructuredOutputExample(
      name: 'User Profile',
      typeName: 'User',
      schema: '''{
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "age": { "type": "integer" },
          "email": { "type": "string" },
          "location": { "type": "string" }
        },
        "required": ["name", "age"]
      }''',
      promptTemplates: [
        'Create a user profile for John',
        'Generate a fictional user from New York',
        'Make a profile for a software developer',
      ],
    ),
    StructuredOutputExample(
      name: 'Weather',
      typeName: 'WeatherResponse',
      schema: '''{
        "type": "object",
        "properties": {
          "temperature": { "type": "number" },
          "condition": { "type": "string" },
          "humidity": { "type": "integer" },
          "windSpeed": { "type": "number" }
        },
        "required": ["temperature", "condition"]
      }''',
      promptTemplates: [
        'What is the weather in Paris?',
        'Give me weather info for Tokyo',
        'Weather forecast for London today',
      ],
    ),
    StructuredOutputExample(
      name: 'Product List',
      typeName: 'ProductList',
      schema: '''{
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "name": { "type": "string" },
            "price": { "type": "number" },
            "category": { "type": "string" }
          }
        }
      }''',
      promptTemplates: [
        'List 3 electronics products with prices',
        'Generate 5 grocery items',
        'Create a list of 4 books with prices',
      ],
    ),
    StructuredOutputExample(
      name: 'Book Summary',
      typeName: 'BookSummary',
      schema: '''{
        "type": "object",
        "properties": {
          "title": { "type": "string" },
          "author": { "type": "string" },
          "genre": { "type": "string" },
          "year": { "type": "integer" },
          "rating": { "type": "number" }
        },
        "required": ["title", "author"]
      }''',
      promptTemplates: [
        'Summarize the book 1984',
        'Give me info about Harry Potter',
        'Create a summary for The Great Gatsby',
      ],
    ),
    StructuredOutputExample(
      name: 'Task',
      typeName: 'Task',
      schema: '''{
        "type": "object",
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "completed": { "type": "boolean" },
          "priority": { "type": "string", "enum": ["low", "medium", "high"] },
          "dueDate": { "type": "string" }
        },
        "required": ["id", "title", "completed"]
      }''',
      promptTemplates: [
        'Create a task to buy groceries',
        'Generate a high priority task',
        'Make a task for meeting tomorrow',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _promptController.text = _examples[0].promptTemplates[0];
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onExampleChanged(int? index) {
    if (index != null) {
      setState(() {
        _selectedExampleIndex = index;
        _promptController.text = _examples[index].promptTemplates[0];
        _rawResponse = null;
        _structuredData = null;
        _errorMessage = null;
      });
    }
  }

  void _onPromptTemplateSelected(String prompt) {
    setState(() {
      _promptController.text = prompt;
    });
  }

  Future<void> _generate() async {
    if (_promptController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a prompt';
      });
      return;
    }

    if (!sdk.RunAnywhere.isModelLoaded) {
      setState(() {
        _errorMessage = 'LLM model not loaded. Please load a model first.';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _rawResponse = null;
      _structuredData = null;
    });

    try {
      final example = _examples[_selectedExampleIndex];

      if (_useStream) {
        await _generateStream(example);
      } else {
        await _generateNonStream(example);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateNonStream(StructuredOutputExample example) async {
    final result = await sdk.RunAnywhere.generate(
      _promptController.text,
      options: sdk.LLMGenerationOptions(
        maxTokens: 1000,
        temperature: 0.7,
        structuredOutput: sdk.StructuredOutputConfig(
          typeName: example.typeName,
          schema: example.schema,
        ),
      ),
    );

    setState(() {
      _rawResponse = result.text;
      _structuredData = result.structuredData;
    });
  }

  Future<void> _generateStream(StructuredOutputExample example) async {
    final streamResult = await sdk.RunAnywhere.generateStream(
      _promptController.text,
      options: sdk.LLMGenerationOptions(
        maxTokens: 1000,
        temperature: 0.7,
        structuredOutput: sdk.StructuredOutputConfig(
          typeName: example.typeName,
          schema: example.schema,
        ),
      ),
    );

    final buffer = StringBuffer();

    await for (final token in streamResult.stream) {
      buffer.write(token);
      setState(() {
        _rawResponse = buffer.toString();
      });
    }

    final finalResult = await streamResult.result;
    setState(() {
      _structuredData = finalResult.structuredData;
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final example = _examples[_selectedExampleIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Structured Output'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _rawResponse != null
                ? () => _copyToClipboard(_rawResponse!)
                : null,
            tooltip: 'Copy raw response',
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Example selector
            _buildExampleSelector(),

            // Prompt templates
            _buildPromptTemplates(example),

            // Prompt input
            _buildPromptInput(),

            // Schema preview
            _buildSchemaPreview(),

            const SizedBox(height: AppSpacing.large),

            // Stream toggle and generate button
            _buildGenerateControls(),

            const SizedBox(height: AppSpacing.large),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isGenerating ? null : _generate,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(_isGenerating ? 'Generating...' : 'Generate'),
                    ),
                  )
                ],
              ),
            ),

            // Error message
            if (_errorMessage != null) _buildErrorBanner(),

            // Results
            _buildResults()
          ],
        ),
      ),
    );
  }

  Widget _buildExampleSelector() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: DropdownButtonFormField<int>(
        value: _selectedExampleIndex,
        decoration: InputDecoration(
          labelText: 'Example',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.large,
            vertical: AppSpacing.mediumLarge,
          ),
        ),
        items: List.generate(_examples.length, (index) {
          return DropdownMenuItem(
            value: index,
            child: Text(_examples[index].name),
          );
        }),
        onChanged: _onExampleChanged,
      ),
    );
  }

  Widget _buildPromptTemplates(StructuredOutputExample example) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prompt Templates',
            style: AppTypography.subheadline(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          Wrap(
            spacing: AppSpacing.smallMedium,
            runSpacing: AppSpacing.smallMedium,
            children: example.promptTemplates.map((template) {
              return ActionChip(
                label: Text(
                  template,
                  style: AppTypography.caption(context),
                ),
                onPressed: () => _onPromptTemplateSelected(template),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptInput() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: TextField(
        controller: _promptController,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Prompt',
          hintText: 'Enter your prompt...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
          ),
          contentPadding: const EdgeInsets.all(AppSpacing.large),
        ),
      ),
    );
  }

  Widget _buildSchemaPreview() {
    final example = _examples[_selectedExampleIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schema,
                size: AppSpacing.iconRegular,
                color: AppColors.textSecondary(context),
              ),
              const SizedBox(width: AppSpacing.smallMedium),
              Text(
                'JSON Schema (${example.typeName})',
                style: AppTypography.subheadline(context).copyWith(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smallMedium),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.mediumLarge),
            decoration: BoxDecoration(
              color: AppColors.backgroundGray5(context),
              borderRadius:
                  BorderRadius.circular(AppSpacing.cornerRadiusRegular),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
              ),
            ),
            child: SelectableText(
              _formatJson(example.schema),
              style: AppTypography.monospaced.copyWith(
                fontSize: 12,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatJson(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (e) {
      return jsonString;
    }
  }

  Widget _buildGenerateControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Non-Stream'),
                  icon: Icon(Icons.check_circle_outline),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Stream'),
                  icon: Icon(Icons.stream),
                ),
              ],
              selected: {_useStream},
              onSelectionChanged: (selected) {
                setState(() {
                  _useStream = selected.first;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.large),
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTypography.subheadline(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _errorMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_rawResponse == null && !_isGenerating) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.data_object,
              size: AppSpacing.iconXXLarge,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(height: AppSpacing.large),
            Text(
              'Generate a response',
              style: AppTypography.title2(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Select an example and enter a prompt',
              style: AppTypography.subheadline(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.large),
      children: [
        // Raw Response
        if (_rawResponse != null) ...[
          _buildSectionHeader('Raw Response', Icons.text_snippet),
          const SizedBox(height: AppSpacing.smallMedium),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.mediumLarge),
            decoration: BoxDecoration(
              color: AppColors.backgroundGray5(context),
              borderRadius:
                  BorderRadius.circular(AppSpacing.cornerRadiusRegular),
            ),
            child: MarkdownBody(
              data: _rawResponse!,
              styleSheet: MarkdownStyleSheet(
                p: AppTypography.body(context),
                code: AppTypography.monospaced.copyWith(
                  backgroundColor: AppColors.backgroundGray6(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
        ],

        // Structured Data
        if (_structuredData != null) ...[
          _buildSectionHeader('Structured Data ', Icons.data_object),
          const SizedBox(height: AppSpacing.smallMedium),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.mediumLarge),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              borderRadius:
                  BorderRadius.circular(AppSpacing.cornerRadiusRegular),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
              ),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(_structuredData),
              style: AppTypography.monospaced.copyWith(
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
        ],

        // Loading indicator
        if (_isGenerating) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.large),
              child: CircularProgressIndicator(),
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.large),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: AppSpacing.iconRegular,
          color: AppColors.textSecondary(context),
        ),
        const SizedBox(width: AppSpacing.smallMedium),
        Text(
          title,
          style: AppTypography.title3(context),
        ),
      ],
    );
  }
}

/// Data class for structured output example
class StructuredOutputExample {
  final String name;
  final String typeName;
  final String schema;
  final List<String> promptTemplates;

  const StructuredOutputExample({
    required this.name,
    required this.typeName,
    required this.schema,
    required this.promptTemplates,
  });
}
