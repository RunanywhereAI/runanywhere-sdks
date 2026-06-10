import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/runanywhere.dart'
    show ToolDefinition, ToolCallingOptions;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/settings/tool_settings_view_model.dart';

/// ToolsView - Demonstrates tool calling functionality
///
/// Matches iOS ToolsScreen and Android ToolSettingsScreen
class ToolsView extends StatefulWidget {
  const ToolsView({super.key});

  @override
  State<ToolsView> createState() => _ToolsViewState();
}

class _ToolsViewState extends State<ToolsView> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Single source of truth for the tool-calling toggle (B-FL-2-001).
  // The Settings tab also reads/writes this same singleton so toggling
  // in one place reflects in the other.
  final ToolSettingsViewModel _toolSettings = ToolSettingsViewModel.shared;

  // State
  bool _isGenerating = false;
  String? _errorMessage;
  List<ToolDefinition> _registeredTools = [];

  // Results
  String _toolExecutionLog = '';
  String _finalResponse = '';

  // Model state
  String? _loadedModelName;

  bool get _toolCallingEnabled => _toolSettings.toolCallingEnabled;

  @override
  void initState() {
    super.initState();
    _toolSettings.addListener(_onToolSettingsChanged);
    unawaited(_syncModelState());
    unawaited(_registerDemoTools());
  }

  @override
  void dispose() {
    _toolSettings.removeListener(_onToolSettingsChanged);
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onToolSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _syncModelState() async {
    final model = await sdk.RunAnywhere.llm.currentModel();
    if (mounted) {
      setState(() {
        _loadedModelName = model?.name;
      });
    }
  }

  /// Register the three demo tools through the shared
  /// `ToolSettingsViewModel.shared.registerDemoTools()` so this view and the
  /// Settings tab use the SAME executors (single source of truth). Also
  /// refresh local UI state from the SDK registry.
  Future<void> _registerDemoTools() async {
    sdk.RunAnywhere.tools.clearTools();
    await _toolSettings.registerDemoTools();
    if (!mounted) return;
    setState(() {
      _registeredTools = sdk.RunAnywhere.tools.getRegisteredTools();
    });
  }

  Future<void> _runToolCalling() async {
    if (!sdk.RunAnywhere.llm.isLoaded) {
      setState(() {
        _errorMessage = 'Please load an LLM model first';
      });
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a prompt';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _toolExecutionLog = '';
      _finalResponse = '';
    });

    try {
      _addToLog('Starting generation with tools...');

      final result = await sdk.RunAnywhere.tools.generateWithTools(
        prompt,
        options: ToolCallingOptions(maxIterations: 3, autoExecute: true),
      );

      // Log tool calls
      for (final toolCall in result.toolCalls) {
        _addToLog('Tool called: ${toolCall.name}');
        _addToLog('Arguments: ${toolCall.argumentsJson}');
      }

      // Log tool results
      for (final toolResult in result.toolResults) {
        _addToLog('Tool result: ${toolResult.name}');
        final hasError = toolResult.error.isNotEmpty;
        _addToLog('Success: ${!hasError}');
        if (toolResult.resultJson.isNotEmpty) {
          _addToLog('Result: ${toolResult.resultJson}');
        }
        if (hasError) {
          _addToLog('Error: ${toolResult.error}');
        }
      }

      setState(() {
        _finalResponse = result.text;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Tool calling failed: $e';
        _isGenerating = false;
      });
    }
  }

  void _addToLog(String message) {
    setState(() {
      final timestamp = DateTime.now().toString().substring(11, 19);
      _toolExecutionLog += '[$timestamp] $message\n';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary(context),
      body: SafeArea(
        child: Column(
          children: [
            // Model status header
            _buildHeader(context),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.padding16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tool calling toggle
                    _buildToolCallingToggle(context),

                    const SizedBox(height: AppSpacing.large),

                    // Registered tools
                    _buildRegisteredToolsSection(context),

                    const SizedBox(height: AppSpacing.large),

                    // Prompt input
                    _buildPromptInput(context),

                    const SizedBox(height: AppSpacing.medium),

                    // Run button
                    _buildRunButton(context),

                    // Error message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.medium),
                      _buildErrorMessage(context),
                    ],

                    // Results
                    if (_toolExecutionLog.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.large),
                      _buildExecutionLog(context),
                    ],

                    if (_finalResponse.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.large),
                      _buildFinalResponse(context),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.padding16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary(context),
        border: Border(bottom: BorderSide(color: AppColors.separator(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tool Calling', style: AppTypography.headline(context)),
                const SizedBox(height: 4),
                if (_loadedModelName != null)
                  Text(
                    'Model: $_loadedModelName',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: AppColors.textSecondary(context)),
                  )
                else
                  Text(
                    'No model loaded',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: AppColors.primaryOrange),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.layers_outlined),
            onPressed: () => _showModelSelection(context),
            color: AppColors.primaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildToolCallingToggle(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: const Text('Enable Tool Calling'),
        subtitle: const Text('Allow LLM to use external tools'),
        value: _toolCallingEnabled,
        onChanged: (value) {
          // Routes through ToolSettingsViewModel.shared so the Settings
          // tab toggle stays in sync (B-FL-2-001).
          _toolSettings.toolCallingEnabled = value;
        },
      ),
    );
  }

  Widget _buildRegisteredToolsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Registered Tools (${_registeredTools.length})',
          style: AppTypography.subheadline(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.small),
        ...(_registeredTools.map((tool) => _buildToolCard(context, tool))),
      ],
    );
  }

  Widget _buildToolCard(BuildContext context, ToolDefinition tool) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.small),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.padding16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.build_outlined,
                  size: 16,
                  color: AppColors.primaryAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  tool.name,
                  style: AppTypography.body(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tool.description,
              style: AppTypography.caption(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
            if (tool.parameters.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Parameters: ${tool.parameters.map((p) => p.name).join(", ")}',
                style: AppTypography.caption2(
                  context,
                ).copyWith(color: AppColors.textSecondary(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPromptInput(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Test Prompt',
          style: AppTypography.subheadline(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.small),
        TextField(
          controller: _promptController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Try: "What\'s the weather in San Francisco?"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: AppColors.backgroundSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildRunButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (_isGenerating || !_toolCallingEnabled)
            ? null
            : _runToolCalling,
        icon: _isGenerating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow),
        label: Text(_isGenerating ? 'Generating...' : 'Run with Tools'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.padding16),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.primaryRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.primaryRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionLog(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Execution Log',
          style: AppTypography.subheadline(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.small),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.padding16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _toolExecutionLog,
            style: AppTypography.caption(context).copyWith(
              fontFamily: 'Menlo',
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinalResponse(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Final Response',
          style: AppTypography.subheadline(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.small),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.padding16),
          decoration: BoxDecoration(
            color: AppColors.primaryAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Text(_finalResponse, style: AppTypography.body(context)),
        ),
      ],
    );
  }

  void _showModelSelection(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => ModelSelectionSheet(
          onModelSelected: (model) async {
            // ModelSelectionSheet handles closing itself, so just sync state
            unawaited(_syncModelState());
          },
        ),
      ),
    );
  }
}
