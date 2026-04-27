import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/public/types/tool_calling_types.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/models/proxy_settings.dart';
import 'package:runanywhere_ai/core/services/example_http_service.dart';
import 'package:runanywhere_ai/core/services/proxy_settings_service.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:runanywhere_ai/features/settings/tool_settings_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// CombinedSettingsView (mirroring iOS CombinedSettingsView.swift)
///
/// Settings interface with storage management and logging configuration.
/// Uses RunAnywhere SDK for actual storage operations.
class CombinedSettingsView extends StatefulWidget {
  const CombinedSettingsView({super.key});

  @override
  State<CombinedSettingsView> createState() => _CombinedSettingsViewState();
}

class _CombinedSettingsViewState extends State<CombinedSettingsView> {
  // Logging
  bool _analyticsLogToLocal = false;

  // Storage info (from SDK)
  int _totalStorageSize = 0;
  int _availableSpace = 0;
  int _modelStorageSize = 0;
  List<sdk.StoredModel> _storedModels = [];

  // API Configuration
  String _apiKey = '';
  String _baseURL = '';
  bool _isApiKeyConfigured = false;
  bool _isBaseURLConfigured = false;

  // General Proxy Configuration
  String _generalProxyScheme = ProxyScheme.http.wireValue;
  String _generalProxyHost = '';
  int? _generalProxyPort;
  bool _generalProxyBypassLocal = true;
  bool _isGeneralProxyConfigured = false;

  // Download Proxy Configuration
  String _downloadProxyScheme = ProxyScheme.http.wireValue;
  String _downloadProxyHost = '';
  int? _downloadProxyPort;
  bool _downloadProxyBypassLocal = true;
  bool _isDownloadProxyConfigured = false;

  // Generation Settings
  double _temperature = 0.7;
  int _maxTokens = 1000;
  String _systemPrompt = '';
  late final TextEditingController _systemPromptController;

  // Loading state
  bool _isRefreshingStorage = false;

  @override
  void initState() {
    super.initState();
    _systemPromptController = TextEditingController();
    unawaited(_loadSettings());
    unawaited(_loadGenerationSettings());
    unawaited(_loadApiConfiguration());
    unawaited(_loadProxyConfiguration(ProxyScope.general));
    unawaited(_loadProxyConfiguration(ProxyScope.download));
    unawaited(_loadStorageData());
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Load from keychain
    _analyticsLogToLocal =
        await KeychainHelper.loadBool(KeychainKeys.analyticsLogToLocal);
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
        _maxTokens = prefs.getInt(PreferenceKeys.defaultMaxTokens) ?? 1000;
        _systemPrompt =
            prefs.getString(PreferenceKeys.defaultSystemPrompt) ?? '';
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generation settings saved')),
      );
    }
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

  Future<void> _loadProxyConfiguration(ProxyScope scope) async {
    final settings = await ProxySettingsService.shared.load(scope);
    final selectedScheme = settings.scheme.isSupportedInExampleApp
        ? settings.scheme
        : ProxyScheme.http;
    final isConfigured = settings.enabled &&
        settings.isComplete &&
        settings.scheme.isSupportedInExampleApp;
    if (mounted) {
      setState(() {
        switch (scope) {
          case ProxyScope.general:
            _generalProxyScheme = selectedScheme.wireValue;
            _generalProxyHost = settings.host;
            _generalProxyPort = settings.port;
            _generalProxyBypassLocal = settings.bypassLocal;
            _isGeneralProxyConfigured = isConfigured;
            break;
          case ProxyScope.download:
            _downloadProxyScheme = selectedScheme.wireValue;
            _downloadProxyHost = settings.host;
            _downloadProxyPort = settings.port;
            _downloadProxyBypassLocal = settings.bypassLocal;
            _isDownloadProxyConfigured = isConfigured;
            break;
        }
      });
    }
  }

  /// Normalize base URL by adding https:// if no scheme is present
  String _normalizeBaseURL(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  /// Save API configuration to keychain
  Future<void> _saveApiConfiguration(String apiKey, String baseURL) async {
    final normalizedURL = _normalizeBaseURL(baseURL);

    await KeychainHelper.saveString(key: KeychainKeys.apiKey, data: apiKey);
    await KeychainHelper.saveString(
        key: KeychainKeys.baseURL, data: normalizedURL);

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
    await KeychainHelper.delete(KeychainKeys.deviceRegistered);

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
    unawaited(showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restart_alt,
            color: AppColors.primaryOrange, size: 32),
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
    ));
  }

  Future<void> _showProxyConfigDialog(ProxyScope scope) async {
    final currentSettings = await ProxySettingsService.shared.load(scope);
    final hostController = TextEditingController(text: currentSettings.host);
    final portController =
        TextEditingController(text: currentSettings.port?.toString() ?? '');
    final usernameController =
        TextEditingController(text: currentSettings.username);
    final passwordController =
        TextEditingController(text: currentSettings.password);
    var proxyEnabled = currentSettings.enabled &&
        currentSettings.scheme.isSupportedInExampleApp;
    var selectedScheme = currentSettings.scheme.isSupportedInExampleApp
        ? currentSettings.scheme
        : ProxyScheme.http;
    var bypassLocal = currentSettings.bypassLocal;
    var showPassword = false;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(scope.displayName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Proxy'),
                  value: proxyEnabled,
                  onChanged: (value) {
                    setDialogState(() {
                      proxyEnabled = value;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.smallMedium),
                DropdownButtonFormField<ProxyScheme>(
                  value: selectedScheme,
                  decoration: const InputDecoration(
                    labelText: 'Protocol',
                    border: OutlineInputBorder(),
                  ),
                  items: ProxyScheme.supportedValues
                      .map(
                        (scheme) => DropdownMenuItem(
                          value: scheme,
                          child: Text(scheme.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedScheme = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.mediumLarge),
                TextField(
                  controller: hostController,
                  decoration: const InputDecoration(
                    labelText: 'Host',
                    hintText: '127.0.0.1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.mediumLarge),
                TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '7890',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.mediumLarge),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.mediumLarge),
                TextField(
                  controller: passwordController,
                  obscureText: !showPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          showPassword = !showPassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.mediumLarge),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bypass localhost'),
                  subtitle: const Text(
                      'Skip proxy for localhost, 127.0.0.1, and ::1'),
                  value: bypassLocal,
                  onChanged: (value) {
                    setDialogState(() {
                      bypassLocal = value;
                    });
                  },
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
              onPressed: () async {
                final settings = ProxySettings(
                  enabled: proxyEnabled,
                  scheme: selectedScheme,
                  host: hostController.text.trim(),
                  port: int.tryParse(portController.text.trim()),
                  username: usernameController.text.trim(),
                  password: passwordController.text,
                  bypassLocal: bypassLocal,
                );

                final result =
                    await ProxySettingsService.shared.save(scope, settings);
                if (!result.isValid) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.message ?? 'Invalid proxy settings',
                        ),
                      ),
                    );
                  }
                  return;
                }

                await _loadProxyConfiguration(scope);

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${scope.displayName} settings saved'),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearProxyConfiguration(ProxyScope scope) async {
    await ProxySettingsService.shared.clear(scope);
    await _loadProxyConfiguration(scope);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${scope.displayName} settings cleared')),
      );
    }
  }

  Future<void> _testProxyConfiguration(ProxyScope scope) async {
    try {
      final ok = await ExampleHttpService.shared.testProxy(
        scope,
        Uri.parse('https://api.ipify.org?format=json'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${scope.displayName} test succeeded'
                : '${scope.displayName} test failed',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proxy test failed: $e')),
      );
    }
  }

  /// Show API configuration dialog
  void _showApiConfigDialog() {
    final apiKeyController = TextEditingController(text: _apiKey);
    final baseURLController = TextEditingController(text: _baseURL);
    bool showPassword = false;

    unawaited(showDialog<void>(
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
                      icon: Icon(showPassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () {
                        setDialogState(() => showPassword = !showPassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xSmall),
                Text(
                  'Your API key for authenticating with the backend',
                  style: AppTypography.caption2(context).copyWith(
                    color: AppColors.textSecondary(context),
                  ),
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
                  style: AppTypography.caption2(context).copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),

                const SizedBox(height: AppSpacing.mediumLarge),

                // Warning Box
                Container(
                  padding: const EdgeInsets.all(AppSpacing.mediumLarge),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.cornerRadiusRegular),
                    border: Border.all(
                        color: AppColors.primaryOrange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber,
                          color: AppColors.primaryOrange, size: 20),
                      const SizedBox(width: AppSpacing.smallMedium),
                      Expanded(
                        child: Text(
                          'After saving, you must restart the app for changes to take effect. The SDK will reinitialize with your custom configuration.',
                          style: AppTypography.caption2(context).copyWith(
                            color: AppColors.textSecondary(context),
                          ),
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
                  unawaited(_saveApiConfiguration(
                      apiKeyController.text, baseURLController.text));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ));
  }

  /// Load storage data using RunAnywhere SDK
  Future<void> _loadStorageData() async {
    if (!mounted) return;
    setState(() {
      _isRefreshingStorage = true;
    });

    try {
      // Get storage info from SDK
      final storageInfo = await sdk.RunAnywhere.getStorageInfo();

      // Get downloaded models with full info (including sizes)
      final storedModels = await sdk.RunAnywhere.getDownloadedModelsWithInfo();

      // Calculate total model storage from actual models
      int totalModelStorage = 0;
      for (final model in storedModels) {
        totalModelStorage += model.size;
      }

      if (mounted) {
        setState(() {
          _totalStorageSize = storageInfo.appStorage.totalSize;
          _availableSpace = storageInfo.deviceStorage.freeSpace;
          _modelStorageSize = totalModelStorage;
          _storedModels = storedModels;
          _isRefreshingStorage = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load storage data: $e');
      if (mounted) {
        setState(() {
          _isRefreshingStorage = false;
        });
      }
    }
  }

  Future<void> _refreshStorageData() async {
    await _loadStorageData();
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

  /// Clear cache using RunAnywhere SDK
  Future<void> _clearCache() async {
    // TODO: Implement clearCache() in SDK
    // Once SDK implements clearCache(), replace this with:
    // try {
    //   await sdk.RunAnywhere.clearCache();
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       const SnackBar(content: Text('Cache cleared')),
    //     );
    //   }
    //   await _loadStorageData();
    // } catch (e) {
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(content: Text('Failed to clear cache: $e')),
    //     );
    //   }
    // }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clear Cache not available yet')),
      );
    }
  }

  /// Delete a stored model using RunAnywhere SDK
  Future<void> _deleteModel(sdk.StoredModel model) async {
    try {
      await sdk.RunAnywhere.deleteStoredModel(model.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.name} deleted')),
        );
      }
      await _loadStorageData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete model: $e')),
        );
      }
    }
  }

  Future<void> _openGitHub() async {
    final uri = Uri.parse('https://github.com/RunanywhereAI/runanywhere-sdks/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open GitHub')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
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

          // Network Proxy Section
          _buildSectionHeader('Network Proxy'),
          _buildProxyConfigurationCard(ProxyScope.general),
          const SizedBox(height: AppSpacing.large),

          // Download Proxy Section
          _buildSectionHeader('Download Proxy'),
          _buildProxyConfigurationCard(ProxyScope.download),
          const SizedBox(height: AppSpacing.large),

          // Generation Settings Section
          _buildSectionHeader('Generation Settings'),
          _buildGenerationSettingsCard(),
          const SizedBox(height: AppSpacing.large),

          // Storage Overview Section
          _buildSectionHeader('Storage Overview',
              trailing: _buildRefreshButton()),
          _buildStorageOverviewCard(),
          const SizedBox(height: AppSpacing.large),

          // Downloaded Models Section
          _buildSectionHeader('Downloaded Models'),
          _buildDownloadedModelsCard(),
          const SizedBox(height: AppSpacing.large),

          // Storage Management Section
          _buildSectionHeader('Storage Management'),
          _buildStorageManagementCard(),
          const SizedBox(height: AppSpacing.large),

          // Logging Configuration Section
          _buildSectionHeader('Logging Configuration'),
          _buildLoggingCard(),
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
          Text(
            title,
            style: AppTypography.headlineSemibold(context),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildRefreshButton() {
    return TextButton.icon(
      onPressed: _isRefreshingStorage ? null : _refreshStorageData,
      icon: _isRefreshingStorage
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 16),
      label: Text(
        'Refresh',
        style: AppTypography.caption(context),
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
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
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
                    min: 50,
                    max: 4096,
                    divisions: ((4096 - 50) / 50).round(),
                    label: _maxTokens.toString(),
                    onChanged: (value) {
                      setState(() {
                        _maxTokens = value.round();
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
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
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
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
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
                  subtitle: const Text(
                    'Allow the LLM to use registered tools',
                  ),
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
                        style:
                            AppTypography.subheadlineSemibold(context).copyWith(
                          color: AppColors.primaryAccent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.mediumLarge),

                  // Add/Clear tools buttons
                  if (viewModel.registeredTools.isEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await viewModel.registerDemoTools();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Demo Tools'),
                    )
                  else ...[
                    // Show registered tools
                    ...viewModel.registeredTools.map(
                      (tool) => _ToolRow(tool: tool),
                    ),
                    const SizedBox(height: AppSpacing.mediumLarge),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await viewModel.clearAllTools();
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear All Tools'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryRed,
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: AppSpacing.mediumLarge),
                Text(
                  'Allow the LLM to use registered tools to perform actions like getting weather, time, or calculations.',
                  style: AppTypography.caption(context).copyWith(
                    color: AppColors.textSecondary(context),
                  ),
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
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyConfigurationCard(ProxyScope scope) {
    final isConfigured = scope == ProxyScope.general
        ? _isGeneralProxyConfigured
        : _isDownloadProxyConfigured;
    final scheme = scope == ProxyScope.general
        ? _generalProxyScheme
        : _downloadProxyScheme;
    final host =
        scope == ProxyScope.general ? _generalProxyHost : _downloadProxyHost;
    final port =
        scope == ProxyScope.general ? _generalProxyPort : _downloadProxyPort;
    final bypassLocal = scope == ProxyScope.general
        ? _generalProxyBypassLocal
        : _downloadProxyBypassLocal;

    final summary = isConfigured
        ? 'Enabled • ${scheme.toUpperCase()} • $host:${port ?? "-"}'
        : 'Disabled';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status', style: AppTypography.subheadline(context)),
                Text(
                  summary,
                  style: AppTypography.caption(context).copyWith(
                    color: isConfigured
                        ? AppColors.statusGreen
                        : AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bypass localhost',
                    style: AppTypography.subheadline(context)),
                Text(
                  bypassLocal ? 'Enabled' : 'Disabled',
                  style: AppTypography.caption(context).copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    unawaited(_showProxyConfigDialog(scope));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryBlue,
                  ),
                  child: const Text('Configure'),
                ),
                const SizedBox(width: AppSpacing.smallMedium),
                OutlinedButton(
                  onPressed: () {
                    unawaited(_testProxyConfiguration(scope));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                  ),
                  child: const Text('Test'),
                ),
                if (isConfigured || host.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.smallMedium),
                  OutlinedButton(
                    onPressed: () {
                      unawaited(_clearProxyConfiguration(scope));
                    },
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
              scope == ProxyScope.general
                  ? 'Applies only to HTTP requests made directly by the Flutter example.'
                  : 'Applies only to model downloads. If disabled, downloads go direct.',
              style: AppTypography.caption2(context).copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageOverviewCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          children: [
            _buildStorageRow(
              icon: Icons.storage,
              label: 'Total Usage',
              value: _totalStorageSize.formattedFileSize,
            ),
            const Divider(),
            _buildStorageRow(
              icon: Icons.add_circle_outline,
              label: 'Available Space',
              value: _availableSpace.formattedFileSize,
              valueColor: AppColors.statusGreen,
            ),
            const Divider(),
            _buildStorageRow(
              icon: Icons.memory,
              label: 'Models Storage',
              value: _modelStorageSize.formattedFileSize,
              valueColor: AppColors.primaryBlue,
            ),
            const Divider(),
            _buildStorageRow(
              icon: Icons.download_done,
              label: 'Downloaded Models',
              value: '${_storedModels.length}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.smallMedium),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconRegular),
          const SizedBox(width: AppSpacing.mediumLarge),
          Expanded(
            child: Text(label, style: AppTypography.subheadline(context)),
          ),
          Text(
            value,
            style: AppTypography.subheadlineSemibold(context).copyWith(
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedModelsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: _storedModels.isEmpty
            ? Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.view_in_ar_outlined,
                      size: 48,
                      color: AppColors.textSecondary(context)
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.mediumLarge),
                    Text(
                      'No models downloaded yet',
                      style: AppTypography.subheadline(context).copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: _storedModels.map((model) {
                  final isLast = model == _storedModels.last;
                  return Column(
                    children: [
                      _StoredModelRow(
                        model: model,
                        onDelete: () async {
                          await _deleteModel(model);
                        },
                      ),
                      if (!isLast) const Divider(),
                    ],
                  );
                }).toList(),
              ),
      ),
    );
  }

  Widget _buildStorageManagementCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: _buildManagementButton(
          icon: Icons.delete_outline,
          title: 'Clear Cache',
          subtitle: 'Free up space by clearing cached data',
          color: AppColors.primaryRed,
          onTap: _clearCache,
        ),
      ),
    );
  }

  Widget _buildManagementButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.mediumLarge),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.mediumLarge),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.subheadline(context)),
                  Text(
                    subtitle,
                    style: AppTypography.caption(context).copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
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

/// Stored model row widget
class _StoredModelRow extends StatefulWidget {
  final sdk.StoredModel model;
  final Future<void> Function() onDelete;

  const _StoredModelRow({
    required this.model,
    required this.onDelete,
  });

  @override
  State<_StoredModelRow> createState() => _StoredModelRowState();
}

class _StoredModelRowState extends State<_StoredModelRow> {
  bool _showDetails = false;
  bool _isDeleting = false;

  Future<void> _performDelete() async {
    setState(() => _isDeleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  void _confirmDelete() {
    unawaited(showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Are you sure you want to delete ${widget.model.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(_performDelete());
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.model.name,
                      style: AppTypography.subheadlineSemibold(context),
                    ),
                    const SizedBox(height: AppSpacing.xSmall),
                    Text(
                      widget.model.size.formattedFileSize,
                      style: AppTypography.caption2(context).copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _showDetails = !_showDetails);
                    },
                    child: Text(_showDetails ? 'Hide' : 'Details'),
                  ),
                  IconButton(
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline,
                            color: AppColors.primaryRed),
                    onPressed: _isDeleting ? null : _confirmDelete,
                  ),
                ],
              ),
            ],
          ),
          if (_showDetails) ...[
            const SizedBox(height: AppSpacing.smallMedium),
            Container(
              padding: const EdgeInsets.all(AppSpacing.mediumLarge),
              decoration: BoxDecoration(
                color: AppColors.backgroundGray6(context),
                borderRadius:
                    BorderRadius.circular(AppSpacing.cornerRadiusRegular),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                      'Downloaded:', _formatDate(widget.model.createdDate)),
                  _buildDetailRow('Size:', widget.model.size.formattedFileSize),
                  _buildDetailRow(
                      'Framework:', widget.model.framework.rawValue),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xSmall),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.caption2(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: AppSpacing.xSmall),
          Text(
            value,
            style: AppTypography.caption2(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
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
            style: AppTypography.caption(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
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
                  style: AppTypography.caption2(context).copyWith(
                    color: AppColors.textSecondary(context),
                  ),
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
