import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/public/runanywhere_tool_calling.dart';
import 'package:runanywhere/public/types/tool_calling_types.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_selection_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // State
  bool _toolCallingEnabled = true;
  bool _isGenerating = false;
  String? _errorMessage;
  List<ToolDefinition> _registeredTools = [];

  // Results
  String _toolExecutionLog = '';
  String _finalResponse = '';

  // Model state
  String? _loadedModelName;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_syncModelState());
    _registerDemoTools();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _toolCallingEnabled = prefs.getBool('tool_calling_enabled') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tool_calling_enabled', _toolCallingEnabled);
  }

  Future<void> _syncModelState() async {
    final model = await sdk.RunAnywhere.currentLLMModel();
    if (mounted) {
      setState(() {
        _loadedModelName = model?.name;
      });
    }
  }

  /// Register demo tools matching iOS/Android examples
  void _registerDemoTools() {
    // Clear any existing tools
    RunAnywhereTools.clearTools();

    // 1. Weather tool
    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'get_weather',
        description: 'Get current weather for a location',
        parameters: [
          ToolParameter(
            name: 'location',
            type: ToolParameterType.string,
            description: 'City name or coordinates (e.g., "San Francisco, CA")',
          ),
        ],
      ),
      _fetchWeather,
    );

    // 2. Calculator tool
    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'calculate',
        description: 'Perform basic arithmetic calculations',
        parameters: [
          ToolParameter(
            name: 'expression',
            type: ToolParameterType.string,
            description: 'Math expression (e.g., "2 + 2", "10 * 5")',
          ),
        ],
      ),
      _calculate,
    );

    // 3. Time tool
    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'get_current_time',
        description: 'Get the current date and time',
        parameters: [],
      ),
      _getCurrentTime,
    );

    setState(() {
      _registeredTools = RunAnywhereTools.getRegisteredTools();
    });
  }

  /// Weather tool executor - fetches real weather data
  Future<Map<String, ToolValue>> _fetchWeather(
    Map<String, ToolValue> args,
  ) async {
    final location = args['location']?.stringValue ?? 'Unknown';

    try {
      // Use Open-Meteo API (no key required)
      final geocodeUrl = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(location)}&count=1',
      );

      final geocodeResponse = await http.get(geocodeUrl);
      if (geocodeResponse.statusCode != 200) {
        throw Exception('Geocoding failed');
      }

      final geocodeData = jsonDecode(geocodeResponse.body) as Map<String, dynamic>;
      final results = geocodeData['results'] as List?;
      if (results == null || results.isEmpty) {
        return {
          'error': const StringToolValue('Location not found'),
          'location': StringToolValue(location),
        };
      }

      final firstResult = results[0] as Map<String, dynamic>;
      final lat = firstResult['latitude'] as num;
      final lon = firstResult['longitude'] as num;
      final cityName = firstResult['name'] as String;

      // Fetch weather
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weathercode&temperature_unit=fahrenheit',
      );

      final weatherResponse = await http.get(weatherUrl);
      if (weatherResponse.statusCode != 200) {
        throw Exception('Weather fetch failed');
      }

      final weatherData = jsonDecode(weatherResponse.body) as Map<String, dynamic>;
      final current = weatherData['current'] as Map<String, dynamic>;
      final temp = current['temperature_2m'] as num;
      final code = current['weathercode'] as int;

      final condition = _weatherCodeToCondition(code);

      return {
        'location': StringToolValue(cityName),
        'temperature': NumberToolValue(temp.toDouble()),
        'unit': const StringToolValue('fahrenheit'),
        'condition': StringToolValue(condition),
      };
    } catch (e) {
      return {
        'error': StringToolValue('Weather fetch failed: $e'),
        'location': StringToolValue(location),
      };
    }
  }

  String _weatherCodeToCondition(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 49) return 'Foggy';
    if (code <= 59) return 'Drizzle';
    if (code <= 69) return 'Rain';
    if (code <= 79) return 'Snow';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  /// Calculator tool executor
  Future<Map<String, ToolValue>> _calculate(
    Map<String, ToolValue> args,
  ) async {
    final expression = args['expression']?.stringValue ?? '';

    try {
      // Simple expression parser for basic arithmetic
      final result = _evaluateExpression(expression);
      return {
        'expression': StringToolValue(expression),
        'result': NumberToolValue(result),
      };
    } catch (e) {
      return {
        'error': StringToolValue('Calculation failed: $e'),
        'expression': StringToolValue(expression),
      };
    }
  }

  double _evaluateExpression(String expr) {
    // Remove spaces
    expr = expr.replaceAll(' ', '');

    // Handle simple operations
    if (expr.contains('+')) {
      final parts = expr.split('+');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a + b);
    } else if (expr.contains('-')) {
      final parts = expr.split('-');
      var result = double.parse(parts[0]);
      for (var i = 1; i < parts.length; i++) {
        result -= double.parse(parts[i]);
      }
      return result;
    } else if (expr.contains('*')) {
      final parts = expr.split('*');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a * b);
    } else if (expr.contains('/')) {
      final parts = expr.split('/');
      var result = double.parse(parts[0]);
      for (var i = 1; i < parts.length; i++) {
        result /= double.parse(parts[i]);
      }
      return result;
    }

    return double.parse(expr);
  }

  /// Time tool executor
  Future<Map<String, ToolValue>> _getCurrentTime(
    Map<String, ToolValue> args,
  ) async {
    final now = DateTime.now();
    return {
      'date': StringToolValue(
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      ),
      'time': StringToolValue(
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      ),
      'timezone': StringToolValue(now.timeZoneName),
    };
  }

  Future<void> _runToolCalling() async {
    if (!sdk.RunAnywhere.isModelLoaded) {
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

      final result = await RunAnywhereTools.generateWithTools(
        prompt,
        options: const ToolCallingOptions(
          maxToolCalls: 3,
          autoExecute: true,
        ),
      );

      // Log tool calls
      for (final toolCall in result.toolCalls) {
        _addToLog('Tool called: ${toolCall.toolName}');
        _addToLog('Arguments: ${toolCall.arguments}');
      }

      // Log tool results
      for (final toolResult in result.toolResults) {
        _addToLog('Tool result: ${toolResult.toolName}');
        _addToLog('Success: ${toolResult.success}');
        if (toolResult.result != null) {
          _addToLog('Result: ${toolResult.result}');
        }
        if (toolResult.error != null) {
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
        border: Border(
          bottom: BorderSide(color: AppColors.separator(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tool Calling',
                  style: AppTypography.headline(context),
                ),
                const SizedBox(height: 4),
                if (_loadedModelName != null)
                  Text(
                    'Model: $_loadedModelName',
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  )
                else
                  Text(
                    'No model loaded',
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.primaryOrange,
                    ),
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
          setState(() {
            _toolCallingEnabled = value;
          });
          unawaited(_saveSettings());
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
          style: AppTypography.subheadline(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
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
                Icon(Icons.build_outlined, size: 16, color: AppColors.primaryAccent),
                const SizedBox(width: 8),
                Text(
                  tool.name,
                  style: AppTypography.body(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tool.description,
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            if (tool.parameters.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Parameters: ${tool.parameters.map((p) => p.name).join(", ")}',
                style: AppTypography.caption2(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
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
          style: AppTypography.subheadline(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.small),
        TextField(
          controller: _promptController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Try: "What\'s the weather in San Francisco?"',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
        color: AppColors.primaryRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.primaryRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: AppColors.primaryRed),
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
          style: AppTypography.subheadline(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
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
          style: AppTypography.subheadline(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.small),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.padding16),
          decoration: BoxDecoration(
            color: AppColors.primaryAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryAccent.withOpacity(0.3),
            ),
          ),
          child: Text(
            _finalResponse,
            style: AppTypography.body(context),
          ),
        ),
      ],
    );
  }

  void _showModelSelection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (dragContext, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          child: ModelSelectionSheet(
            onModelSelected: (model) async {
              Navigator.pop(sheetContext);
              unawaited(_syncModelState());
            },
          ),
        ),
      ),
    );
  }
}
