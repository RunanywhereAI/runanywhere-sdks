import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' show RunAnywhere, ToolDefinition;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/hf_token_store.dart';
import 'package:runanywhere_ai/core/services/model_catalog_bootstrap.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:runanywhere_ai/core/utilities/url_utils.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_dashboard_view.dart';
import 'package:runanywhere_ai/features/settings/tool_settings_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// CombinedSettingsView (mirroring iOS CombinedSettingsView.swift)
///
/// Settings interface for tool calling, API configuration, generation, and
/// logging. Storage lives in the More tab, matching iOS.
class CombinedSettingsView extends StatefulWidget {
  const CombinedSettingsView({super.key});

  @override
  State<CombinedSettingsView> createState() => _CombinedSettingsViewState();
}

class _CombinedSettingsViewState extends State<CombinedSettingsView> {
  // Logging
  bool _analyticsLogToLocal = false;

  // API Configuration
  String _apiKey = '';
  String _baseURL = '';
  bool _isApiKeyConfigured = false;
  bool _isBaseURLConfigured = false;

  // Generation Settings
  double _temperature = 0.7;
  int _maxTokens = 1000;
  String _systemPrompt = '';
  bool _thinkingModeEnabled = true;
  late final TextEditingController _systemPromptController;

  // Downloads
  late final TextEditingController _hfTokenController;

  @override
  void initState() {
    super.initState();
    _systemPromptController = TextEditingController();
    _hfTokenController = TextEditingController();
    unawaited(_loadSettings());
    unawaited(_loadGenerationSettings());
    unawaited(_loadApiConfiguration());
    unawaited(_loadHfToken());
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    _hfTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Load from keychain
    _analyticsLogToLocal = await KeychainHelper.loadBool(
      KeychainKeys.analyticsLogToLocal,
    );
    if (mounted) {
      setState(() {});
    }
  }

  /// Load generation settings from SharedPreferences
  Future<void> _loadGenerationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _temperature =
            prefs.getDouble(PreferenceKeys.defaultTemperature) ?? 0.7;
        _maxTokens = (prefs.getInt(PreferenceKeys.defaultMaxTokens) ?? 1000)
            .clamp(500, 20000)
            .toInt();
        final storedPrompt = prefs.getString(
          PreferenceKeys.defaultSystemPrompt,
        );
        // Prefill a meaningful default the first time (null) so it's applied and
        // editable everywhere; respect an explicit empty string the user saved.
        _systemPrompt = storedPrompt ?? kDefaultSystemPrompt;
        _thinkingModeEnabled =
            prefs.getBool(PreferenceKeys.thinkingModeEnabled) ?? true;
        _systemPromptController.text = _systemPrompt;
      });
    }
  }

  /// Save generation settings to SharedPreferences
  Future<void> _saveGenerationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PreferenceKeys.defaultTemperature, _temperature);
    await prefs.setInt(PreferenceKeys.defaultMaxTokens, _maxTokens);
    await prefs.setString(PreferenceKeys.defaultSystemPrompt, _systemPrompt);
    await prefs.setBool(
      PreferenceKeys.thinkingModeEnabled,
      _thinkingModeEnabled,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generation settings saved')),
      );
    }
  }

  /// Load the persisted HuggingFace token from secure storage.
  Future<void> _loadHfToken() async {
    final token = await HfTokenStore.load();
    if (mounted) {
      setState(() {
        _hfTokenController.text = token;
      });
    }
  }

  /// Persist the HuggingFace token and apply it to the SDK after editing.
  Future<void> _saveHfToken(String value, {bool showFeedback = false}) async {
    final token = value.trim();
    await HfTokenStore.save(token);
    RunAnywhere.setHfToken(token);
    await ModelCatalogBootstrap.refreshNpuCatalog();
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            token.isEmpty
                ? 'Hugging Face token cleared'
                : 'Hugging Face token saved',
          ),
        ),
      );
    }
  }

  Future<void> _clearHfToken() async {
    _hfTokenController.clear();
    await _saveHfToken('', showFeedback: true);
  }

  /// Load API configuration from keychain
  Future<void> _loadApiConfiguration() async {
    final storedApiKey = await KeychainHelper.loadString(KeychainKeys.apiKey);
    final storedBaseURL = await KeychainHelper.loadString(KeychainKeys.baseURL);

    if (mounted) {
      setState(() {
        _apiKey = storedApiKey ?? '';
        _baseURL = storedBaseURL ?? '';
        _isApiKeyConfigured = storedApiKey != null && storedApiKey.isNotEmpty;
        _isBaseURLConfigured =
            storedBaseURL != null && storedBaseURL.isNotEmpty;
      });
    }
  }

  /// Save API configuration to keychain
  Future<void> _saveApiConfiguration(String apiKey, String baseURL) async {
    final normalizedURL = normalizeBaseURL(baseURL);

    await KeychainHelper.saveString(key: KeychainKeys.apiKey, data: apiKey);
    await KeychainHelper.saveString(
      key: KeychainKeys.baseURL,
      data: normalizedURL,
    );

    if (mounted) {
      setState(() {
        _apiKey = apiKey;
        _baseURL = normalizedURL;
        _isApiKeyConfigured = apiKey.isNotEmpty;
        _isBaseURLConfigured = normalizedURL.isNotEmpty;
      });

      _showRestartDialog();
    }
  }

  /// Clear API configuration from keychain
  Future<void> _clearApiConfiguration() async {
    await KeychainHelper.delete(KeychainKeys.apiKey);
    await KeychainHelper.delete(KeychainKeys.baseURL);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PreferenceKeys.deviceRegistered);

    if (mounted) {
      setState(() {
        _apiKey = '';
        _baseURL = '';
        _isApiKeyConfigured = false;
        _isBaseURLConfigured = false;
      });

      _showRestartDialog();
    }
  }

  /// Show restart required dialog
  void _showRestartDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.restart_alt,
            color: AppColors.primaryOrange,
            size: 32,
          ),
          title: const Text('Restart Required'),
          content: const Text(
            'API configuration has been updated. Please restart the app for changes to take effect.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  /// Show API configuration dialog
  void _showApiConfigDialog() {
    final apiKeyController = TextEditingController(text: _apiKey);
    final baseURLController = TextEditingController(text: _baseURL);
    bool showPassword = false;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('API Configuration'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API Key Input
                  Text('API Key', style: AppTypography.caption(context)),
                  const SizedBox(height: AppSpacing.xSmall),
                  TextField(
                    controller: apiKeyController,
                    obscureText: !showPassword,
                    decoration: InputDecoration(
                      hintText: 'Enter your API key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setDialogState(() => showPassword = !showPassword);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xSmall),
                  Text(
                    'Your API key for authenticating with the backend',
                    style: AppTypography.caption2(
                      context,
                    ).copyWith(color: AppColors.textSecondary(context)),
                  ),

                  const SizedBox(height: AppSpacing.mediumLarge),

                  // Base URL Input
                  Text('Base URL', style: AppTypography.caption(context)),
                  const SizedBox(height: AppSpacing.xSmall),
                  TextField(
                    controller: baseURLController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://api.example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xSmall),
                  Text(
                    'The backend API URL (https:// added automatically if missing)',
                    style: AppTypography.caption2(
                      context,
                    ).copyWith(color: AppColors.textSecondary(context)),
                  ),

                  const SizedBox(height: AppSpacing.mediumLarge),

                  // Warning Box
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.mediumLarge),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.cornerRadiusRegular,
                      ),
                      border: Border.all(
                        color: AppColors.primaryOrange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: AppColors.primaryOrange,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.smallMedium),
                        Expanded(
                          child: Text(
                            'After saving, you must restart the app for changes to take effect. The SDK will reinitialize with your custom configuration.',
                            style: AppTypography.caption2(
                              context,
                            ).copyWith(color: AppColors.textSecondary(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (apiKeyController.text.isNotEmpty &&
                      baseURLController.text.isNotEmpty) {
                    Navigator.pop(dialogContext);
                    unawaited(
                      _saveApiConfiguration(
                        apiKeyController.text,
                        baseURLController.text,
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAnalyticsLogging(bool value) async {
    setState(() {
      _analyticsLogToLocal = value;
    });
    await KeychainHelper.saveBool(
      key: KeychainKeys.analyticsLogToLocal,
      data: value,
    );
  }

  Future<void> _openGitHub() async {
    final uri = Uri.parse('https://github.com/RunanywhereAI/runanywhere-sdks/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open GitHub')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.large),
        children: [
          // Tool Calling Section (matches iOS)
          _buildSectionHeader('Tool Calling'),
          _buildToolCallingCard(),
          const SizedBox(height: AppSpacing.large),

          // API Configuration Section
          _buildSectionHeader('API Configuration (Testing)'),
          _buildApiConfigurationCard(),
          const SizedBox(height: AppSpacing.large),

          // Generation Settings Section
          _buildSectionHeader('Generation Settings'),
          _buildGenerationSettingsCard(),
          const SizedBox(height: AppSpacing.large),

          // Logging Configuration Section
          _buildSectionHeader('Logging Configuration'),
          _buildLoggingCard(),
          const SizedBox(height: AppSpacing.large),

          // Downloads Section (mirrors Android SettingsScreen "Downloads")
          _buildSectionHeader('Downloads'),
          _buildDownloadsCard(),
          const SizedBox(height: AppSpacing.large),

          // Performance Section (mirrors iOS CombinedSettingsView.swift:179-183)
          _buildSectionHeader('Performance'),
          _buildPerformanceCard(),
          const SizedBox(height: AppSpacing.large),

          // About Section
          _buildSectionHeader('About'),
          _buildAboutCard(),
          const SizedBox(height: AppSpacing.xxLarge),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smallMedium),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTypography.headlineSemibold(context)),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildGenerationSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Temperature Slider
            Text('Temperature', style: AppTypography.subheadline(context)),
            const SizedBox(height: AppSpacing.xSmall),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _temperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    label: _temperature.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _temperature = value;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    _temperature.toStringAsFixed(1),
                    style: AppTypography.subheadlineSemibold(context),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            Text(
              'Controls randomness. Lower = more focused, higher = more creative.',
              style: AppTypography.caption2(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),

            // Max Tokens Slider
            Text('Max Tokens', style: AppTypography.subheadline(context)),
            const SizedBox(height: AppSpacing.xSmall),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _maxTokens.toDouble(),
                    min: 500,
                    max: 20000,
                    divisions: ((20000 - 500) / 500).round(),
                    label: _maxTokens.toString(),
                    onChanged: (value) {
                      setState(() {
                        _maxTokens = (value / 500).round() * 500;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    _maxTokens.toString(),
                    style: AppTypography.subheadlineSemibold(context),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            Text(
              'Maximum number of tokens to generate.',
              style: AppTypography.caption2(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Thinking Mode'),
              subtitle: const Text('Show model reasoning when supported'),
              value: _thinkingModeEnabled,
              onChanged: (value) {
                setState(() {
                  _thinkingModeEnabled = value;
                });
              },
            ),
            const SizedBox(height: AppSpacing.mediumLarge),

            // System Prompt Field
            Text('System Prompt', style: AppTypography.subheadline(context)),
            const SizedBox(height: AppSpacing.xSmall),
            TextField(
              controller: _systemPromptController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter a system prompt...',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _systemPrompt = value;
              },
            ),
            const SizedBox(height: AppSpacing.xSmall),
            Text(
              'Instructions for how the model should behave.',
              style: AppTypography.caption2(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),

            // Save Settings Button
            ElevatedButton(
              onPressed: _saveGenerationSettings,
              child: const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCallingCard() {
    return ListenableBuilder(
      listenable: ToolSettingsViewModel.shared,
      builder: (context, _) {
        final viewModel = ToolSettingsViewModel.shared;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Enable toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Tool Calling'),
                  subtitle: const Text('Allow the LLM to use registered tools'),
                  value: viewModel.toolCallingEnabled,
                  onChanged: (value) {
                    viewModel.toolCallingEnabled = value;
                  },
                ),

                if (viewModel.toolCallingEnabled) ...[
                  const Divider(),

                  // Registered tools count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Registered Tools',
                        style: AppTypography.subheadline(context),
                      ),
                      Text(
                        '${viewModel.registeredTools.length}',
                        style: AppTypography.subheadlineSemibold(
                          context,
                        ).copyWith(color: AppColors.primaryAccent),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.mediumLarge),
                  ...viewModel.registeredTools.map(
                    (tool) => _ToolRow(tool: tool),
                  ),
                ],

                const SizedBox(height: AppSpacing.mediumLarge),
                Text(
                  'Allow the LLM to use registered tools to perform actions like getting weather, time, or calculations.',
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildApiConfigurationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Key Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('API Key', style: AppTypography.subheadline(context)),
                Text(
                  _isApiKeyConfigured ? 'Configured' : 'Not Set',
                  style: AppTypography.caption(context).copyWith(
                    color: _isApiKeyConfigured
                        ? AppColors.statusGreen
                        : AppColors.primaryOrange,
                  ),
                ),
              ],
            ),
            const Divider(),
            // Base URL Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Base URL', style: AppTypography.subheadline(context)),
                Text(
                  _isBaseURLConfigured ? 'Configured' : 'Not Set',
                  style: AppTypography.caption(context).copyWith(
                    color: _isBaseURLConfigured
                        ? AppColors.statusGreen
                        : AppColors.primaryOrange,
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: AppSpacing.smallMedium),
            // Buttons
            Row(
              children: [
                OutlinedButton(
                  onPressed: _showApiConfigDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryBlue,
                  ),
                  child: const Text('Configure'),
                ),
                if (_isApiKeyConfigured && _isBaseURLConfigured) ...[
                  const SizedBox(width: AppSpacing.smallMedium),
                  OutlinedButton(
                    onPressed: _clearApiConfiguration,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryRed,
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Configure custom API key and base URL for testing. Requires app restart.',
              style: AppTypography.caption2(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log Analytics Locally'),
              subtitle: const Text(
                'When enabled, analytics events will be saved locally on your device.',
              ),
              value: _analyticsLogToLocal,
              onChanged: _toggleAnalyticsLogging,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HuggingFace token',
              style: AppTypography.subheadline(context),
            ),
            const SizedBox(height: AppSpacing.xSmall),
            TextField(
              controller: _hfTokenController,
              decoration: const InputDecoration(
                hintText: 'hf_…',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => unawaited(_saveHfToken(value)),
            ),
            const SizedBox(height: AppSpacing.xSmall),
            Wrap(
              spacing: AppSpacing.small,
              runSpacing: AppSpacing.xSmall,
              children: [
                FilledButton.icon(
                  onPressed: () => unawaited(
                    _saveHfToken(_hfTokenController.text, showFeedback: true),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save token'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_clearHfToken()),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xSmall),
            Text(
              'Used to download private Hugging Face model repos, including HNPU/QHexRT NPU bundles',
              style: AppTypography.caption2(
                context,
              ).copyWith(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.speed, color: AppColors.primaryBlue),
        title: const Text('Benchmarks'),
        subtitle: const Text('Measure on-device AI performance'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const BenchmarkDashboardView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code, color: AppColors.primaryBlue),
          title: const Text('RunAnywhere SDK'),
          subtitle: const Text('github.com/RunanywhereAI/runanywhere-sdks'),
          trailing: const Icon(Icons.open_in_new),
          onTap: _openGitHub,
        ),
      ),
    );
  }
}

/// Tool row widget (mirroring iOS ToolRow)
class _ToolRow extends StatelessWidget {
  final ToolDefinition tool;

  const _ToolRow({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.build_outlined,
                size: 12,
                color: AppColors.primaryAccent,
              ),
              const SizedBox(width: 8),
              Text(
                tool.name,
                style: AppTypography.subheadlineSemibold(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tool.description,
            style: AppTypography.caption(
              context,
            ).copyWith(color: AppColors.textSecondary(context)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (tool.parameters.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                Text(
                  'Params:',
                  style: AppTypography.caption2(
                    context,
                  ).copyWith(color: AppColors.textSecondary(context)),
                ),
                ...tool.parameters.map(
                  (param) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundTertiary(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      param.name,
                      style: AppTypography.caption2(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
