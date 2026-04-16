import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/public/runanywhere_tool_calling.dart';
import 'package:runanywhere/public/types/tool_calling_types.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/core/types/model_selection_context.dart';
import 'package:runanywhere_ai/core/widgets/model_selection_sheet.dart';
import 'package:runanywhere_ai/features/chat/widgets/model_status_banner.dart';

class _ToolsState {
  const _ToolsState({
    this.isGenerating = false,
    this.toolLog = '',
    this.response = '',
    this.modelName,
    this.errorMessage,
    this.tools = const [],
  });

  final bool isGenerating;
  final String toolLog;
  final String response;
  final String? modelName;
  final String? errorMessage;
  final List<ToolDefinition> tools;
}

final _toolsProvider =
    NotifierProvider<_ToolsController, _ToolsState>(_ToolsController.new);

class _ToolsController extends Notifier<_ToolsState> {
  @override
  _ToolsState build() {
    Future.microtask(() {
      _registerDemoTools();
      _syncModel();
    });
    return const _ToolsState();
  }

  Future<void> _syncModel() async {
    final model = await sdk.RunAnywhere.currentLLMModel();
    state = _ToolsState(
      modelName: model?.name,
      tools: state.tools,
    );
  }

  void refreshModel() => _syncModel();

  void _registerDemoTools() {
    RunAnywhereTools.clearTools();

    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'get_weather',
        description: 'Get current weather for a location',
        parameters: [
          ToolParameter(
            name: 'location',
            type: ToolParameterType.string,
            description: 'City name (e.g., "San Francisco")',
          ),
        ],
      ),
      _fetchWeather,
    );

    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'calculate',
        description: 'Perform arithmetic calculations',
        parameters: [
          ToolParameter(
            name: 'expression',
            type: ToolParameterType.string,
            description: 'Math expression (e.g., "2 + 2")',
          ),
        ],
      ),
      _calculate,
    );

    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'get_current_time',
        description: 'Get the current date and time',
        parameters: [],
      ),
      _getCurrentTime,
    );

    state = _ToolsState(
      modelName: state.modelName,
      tools: RunAnywhereTools.getRegisteredTools(),
    );
  }

  Future<void> runWithTools(String prompt) async {
    if (prompt.trim().isEmpty || state.isGenerating) return;
    if (!sdk.RunAnywhere.isModelLoaded) {
      state = _ToolsState(
        modelName: state.modelName,
        tools: state.tools,
        errorMessage: 'Load an LLM model first',
      );
      return;
    }

    state = _ToolsState(
      isGenerating: true,
      modelName: state.modelName,
      tools: state.tools,
      toolLog: '[Starting generation with tools...]\n',
    );

    try {
      final result = await RunAnywhereTools.generateWithTools(
        prompt,
        options: const ToolCallingOptions(
          maxToolCalls: 3,
          autoExecute: true,
        ),
      );

      final log = StringBuffer(state.toolLog);
      for (final tc in result.toolCalls) {
        log.writeln('Tool: ${tc.toolName}');
        log.writeln('Args: ${tc.arguments}');
      }
      for (final tr in result.toolResults) {
        log.writeln(
            '${tr.toolName} ${tr.success ? "OK" : "FAIL"}: ${tr.result ?? tr.error}');
      }

      state = _ToolsState(
        modelName: state.modelName,
        tools: state.tools,
        toolLog: log.toString(),
        response: result.text,
      );
    } on Exception catch (e) {
      state = _ToolsState(
        modelName: state.modelName,
        tools: state.tools,
        errorMessage: e.toString(),
      );
    }
  }

  // Tool executors

  Future<Map<String, ToolValue>> _fetchWeather(
      Map<String, ToolValue> args) async {
    final location = args['location']?.stringValue;
    if (location == null || location.isEmpty) {
      return {'error': const StringToolValue('Missing location')};
    }

    try {
      final geoUrl = Uri.parse(
          'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(location)}&count=1&language=en&format=json');
      final geoRes = await http.get(geoUrl);
      final geoData = jsonDecode(geoRes.body) as Map<String, dynamic>;
      final results = geoData['results'] as List?;
      if (results == null || results.isEmpty) {
        return {'error': StringToolValue('Location not found: $location')};
      }

      final first = results[0] as Map<String, dynamic>;
      final lat = first['latitude'] as num;
      final lon = first['longitude'] as num;

      final wxUrl = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph');
      final wxRes = await http.get(wxUrl);
      final wxData = jsonDecode(wxRes.body) as Map<String, dynamic>;
      final current = wxData['current'] as Map<String, dynamic>;

      return {
        'location': StringToolValue(first['name'] as String? ?? location),
        'temperature': NumberToolValue((current['temperature_2m'] as num).toDouble()),
        'humidity': NumberToolValue((current['relative_humidity_2m'] as num).toDouble()),
        'wind_mph': NumberToolValue((current['wind_speed_10m'] as num).toDouble()),
      };
    } catch (e) {
      return {'error': StringToolValue('Weather fetch failed: $e')};
    }
  }

  Future<Map<String, ToolValue>> _calculate(
      Map<String, ToolValue> args) async {
    final expr = args['expression']?.stringValue;
    if (expr == null || expr.isEmpty) {
      return {'error': const StringToolValue('Missing expression')};
    }
    try {
      final result = _eval(expr);
      return {
        'expression': StringToolValue(expr),
        'result': NumberToolValue(result),
      };
    } catch (e) {
      return {'error': StringToolValue('Calc failed: $e')};
    }
  }

  double _eval(String expr) {
    final e = expr.replaceAll(' ', '');
    if (e.contains('+')) {
      return e.split('+').map(double.parse).reduce((a, b) => a + b);
    } else if (e.contains('-')) {
      final parts = e.split('-');
      var r = double.parse(parts[0]);
      for (var i = 1; i < parts.length; i++) {
        r -= double.parse(parts[i]);
      }
      return r;
    } else if (e.contains('*')) {
      return e.split('*').map(double.parse).reduce((a, b) => a * b);
    } else if (e.contains('/')) {
      final parts = e.split('/');
      var r = double.parse(parts[0]);
      for (var i = 1; i < parts.length; i++) {
        r /= double.parse(parts[i]);
      }
      return r;
    } else if (e.contains('^')) {
      final parts = e.split('^');
      return math.pow(double.parse(parts[0]), double.parse(parts[1])).toDouble();
    }
    return double.parse(e);
  }

  Future<Map<String, ToolValue>> _getCurrentTime(
      Map<String, ToolValue> args) async {
    final now = DateTime.now();
    return {
      'date': StringToolValue(
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'),
      'time': StringToolValue(
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'),
      'timezone': StringToolValue(now.timeZoneName),
    };
  }
}

class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _promptController.text = "What's the weather in San Francisco?";
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toolsState = ref.watch(_toolsProvider);
    final controller = ref.read(_toolsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tool Calling')),
      body: Column(
        children: [
          ModelStatusBanner(
            modelName: toolsState.modelName,
            framework: toolsState.modelName != null ? 'LLM' : null,
            onSelectModel: () async {
              final model = await showModelSelectionSheet(
                context,
                ref,
                selectionContext: ModelSelectionContext.llm,
              );
              if (model != null) controller.refreshModel();
            },
          ),
          Expanded(
            child: ListView(
              padding: AppSpacing.pagePadding,
              children: [
                // Registered tools
                Text('Registered Tools (${toolsState.tools.length})',
                    style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                ...toolsState.tools.map((tool) => Card(
                      margin:
                          const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: Icon(Icons.build_outlined,
                            size: 20, color: theme.colorScheme.primary),
                        title: Text(tool.name,
                            style: AppTypography.titleMedium),
                        subtitle: Text(tool.description,
                            style: AppTypography.bodySmall),
                        dense: true,
                      ),
                    )),

                const SizedBox(height: AppSpacing.lg),

                // Prompt
                TextField(
                  controller: _promptController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Prompt',
                    hintText:
                        'Try: "What\'s the weather in San Francisco?"',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Run button
                FilledButton.icon(
                  onPressed: toolsState.isGenerating
                      ? null
                      : () =>
                          controller.runWithTools(_promptController.text),
                  icon: toolsState.isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(toolsState.isGenerating
                      ? 'Running...'
                      : 'Run with Tools'),
                ),

                if (toolsState.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    toolsState.errorMessage!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],

                if (toolsState.toolLog.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Text('Execution Log', style: AppTypography.labelLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: SelectableText(
                        toolsState.toolLog,
                        style: AppTypography.mono.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],

                if (toolsState.response.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Text('Response', style: AppTypography.labelLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: SelectableText(
                        toolsState.response,
                        style: AppTypography.bodyMedium.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
