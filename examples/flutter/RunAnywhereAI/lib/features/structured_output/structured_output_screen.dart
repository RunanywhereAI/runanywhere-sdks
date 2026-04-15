import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/public/types/generation_types.dart';
import 'package:runanywhere/public/types/structured_output_types.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';

enum StructuredExample {
  recipe('Recipe', '{"type":"object","properties":{"name":{"type":"string"},"ingredients":{"type":"array","items":{"type":"string"}},"steps":{"type":"array","items":{"type":"string"}}}}'),
  userProfile('User Profile', '{"type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"},"email":{"type":"string"},"hobbies":{"type":"array","items":{"type":"string"}}}}'),
  weather('Weather', '{"type":"object","properties":{"city":{"type":"string"},"temperature":{"type":"number"},"condition":{"type":"string"},"humidity":{"type":"integer"}}}'),
  bookSummary('Book Summary', '{"type":"object","properties":{"title":{"type":"string"},"author":{"type":"string"},"summary":{"type":"string"},"rating":{"type":"number"}}}');

  const StructuredExample(this.label, this.schema);
  final String label;
  final String schema;
}

class _ScreenState {
  const _ScreenState({
    this.selectedExample = StructuredExample.recipe,
    this.isGenerating = false,
    this.response = '',
    this.useStreaming = false,
    this.errorMessage,
  });

  final StructuredExample selectedExample;
  final bool isGenerating;
  final String response;
  final bool useStreaming;
  final String? errorMessage;
}

final _screenProvider =
    NotifierProvider<_ScreenController, _ScreenState>(_ScreenController.new);

class _ScreenController extends Notifier<_ScreenState> {
  @override
  _ScreenState build() => const _ScreenState();

  void selectExample(StructuredExample ex) =>
      state = _ScreenState(selectedExample: ex, useStreaming: state.useStreaming);

  void toggleStreaming() =>
      state = _ScreenState(
        selectedExample: state.selectedExample,
        useStreaming: !state.useStreaming,
      );

  Future<void> generate(String prompt) async {
    if (prompt.trim().isEmpty || state.isGenerating) return;

    state = _ScreenState(
      selectedExample: state.selectedExample,
      isGenerating: true,
      useStreaming: state.useStreaming,
    );

    try {
      final options = LLMGenerationOptions(
        maxTokens: 512,
        temperature: 0.3,
        structuredOutput: StructuredOutputConfig(
          typeName: state.selectedExample.label,
          schema: state.selectedExample.schema,
        ),
      );

      if (state.useStreaming) {
        final result = await sdk.RunAnywhere.generateStream(
          prompt,
          options: options,
        );
        final buffer = StringBuffer();
        await for (final token in result.stream) {
          buffer.write(token);
          state = _ScreenState(
            selectedExample: state.selectedExample,
            isGenerating: true,
            response: buffer.toString(),
            useStreaming: state.useStreaming,
          );
        }
        state = _ScreenState(
          selectedExample: state.selectedExample,
          response: buffer.toString(),
          useStreaming: state.useStreaming,
        );
      } else {
        final result = await sdk.RunAnywhere.generate(prompt, options: options);
        state = _ScreenState(
          selectedExample: state.selectedExample,
          response: result.text,
          useStreaming: state.useStreaming,
        );
      }
    } on Exception catch (e) {
      state = _ScreenState(
        selectedExample: state.selectedExample,
        errorMessage: e.toString(),
        useStreaming: state.useStreaming,
      );
    }
  }
}

class StructuredOutputScreen extends ConsumerStatefulWidget {
  const StructuredOutputScreen({super.key});

  @override
  ConsumerState<StructuredOutputScreen> createState() =>
      _StructuredOutputScreenState();
}

class _StructuredOutputScreenState
    extends ConsumerState<StructuredOutputScreen> {
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _promptController.text = 'Generate a chocolate cake recipe';
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenState = ref.watch(_screenProvider);
    final controller = ref.read(_screenProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Structured Output')),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          DropdownButtonFormField<StructuredExample>(
            initialValue: screenState.selectedExample,
            decoration: const InputDecoration(labelText: 'Schema Template'),
            items: StructuredExample.values
                .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) controller.selectExample(v);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: SelectableText(
                screenState.selectedExample.schema,
                style: AppTypography.mono.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _promptController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Prompt',
              hintText: 'Enter your prompt...',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FilterChip(
                label: const Text('Stream'),
                selected: screenState.useStreaming,
                onSelected: (_) => controller.toggleStreaming(),
              ),
              const Spacer(),
              FilledButton(
                onPressed: screenState.isGenerating
                    ? null
                    : () => controller.generate(_promptController.text),
                child: screenState.isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Generate'),
              ),
            ],
          ),
          if (screenState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              screenState.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (screenState.response.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            Text('Response', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: SelectableText(
                  screenState.response,
                  style: AppTypography.mono.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
