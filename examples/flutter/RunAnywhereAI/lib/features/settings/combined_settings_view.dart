import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CombinedSettingsView (mirroring iOS CombinedSettingsView.swift)
///
/// Comprehensive settings interface with SDK configuration, storage management,
/// and API settings.
class CombinedSettingsView extends StatefulWidget {
  const CombinedSettingsView({super.key});

  @override
  State<CombinedSettingsView> createState() => _CombinedSettingsViewState();
}

class _CombinedSettingsViewState extends State<CombinedSettingsView> {
  // Settings state
  RoutingPolicy _routingPolicy = RoutingPolicy.automatic;
  double _defaultTemperature = 0.7;
  int _defaultMaxTokens = 10000;
  bool _analyticsLogToLocal = false;
  bool _showApiKeyEntry = false;
  String _apiKey = '';

  // Storage info
  int _totalStorageSize = 0;
  int _availableSpace = 0;
  int _modelStorageSize = 0;
  List<dynamic> _storedModels = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_loadStorageInfo());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _routingPolicy = RoutingPolicy.values[
          prefs.getInt(PreferenceKeys.routingPolicy) ?? 0];
      _defaultTemperature =
          prefs.getDouble(PreferenceKeys.defaultTemperature) ?? 0.7;
      _defaultMaxTokens =
          prefs.getInt(PreferenceKeys.defaultMaxTokens) ?? 10000;
    });

    // Load from keychain
    _analyticsLogToLocal =
        await KeychainHelper.loadBool(KeychainKeys.analyticsLogToLocal);
    final savedApiKey = await KeychainHelper.loadString(KeychainKeys.apiKey);
    if (savedApiKey != null) {
      setState(() {
        _apiKey = savedApiKey;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PreferenceKeys.routingPolicy, _routingPolicy.index);
    await prefs.setDouble(
        PreferenceKeys.defaultTemperature, _defaultTemperature);
    await prefs.setInt(PreferenceKeys.defaultMaxTokens, _defaultMaxTokens);
  }

  Future<void> _loadStorageInfo() async {
    // TODO: Implement via RunAnywhere SDK
    // final storageInfo = await RunAnywhere.getStorageInfo();
    setState(() {
      _totalStorageSize = 1024 * 1024 * 1024; // Placeholder: 1GB
      _availableSpace = 512 * 1024 * 1024; // Placeholder: 512MB
      _modelStorageSize = 256 * 1024 * 1024; // Placeholder: 256MB
      _storedModels = [];
    });
  }

  Future<void> _saveApiKey() async {
    if (_apiKey.isNotEmpty) {
      await KeychainHelper.saveString(key: KeychainKeys.apiKey, data: _apiKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API Key saved')),
        );
      }
    }
    setState(() {
      _showApiKeyEntry = false;
    });
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

  Future<void> _clearCache() async {
    // TODO: Implement via RunAnywhere SDK
    // await RunAnywhere.clearCache();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
    await _loadStorageInfo();
  }

  Future<void> _cleanTempFiles() async {
    // TODO: Implement via RunAnywhere SDK
    // await RunAnywhere.cleanTempFiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Temporary files cleaned')),
      );
    }
    await _loadStorageInfo();
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
          // SDK Configuration Section
          _buildSectionHeader('SDK Configuration'),
          _buildRoutingPolicyCard(),
          const SizedBox(height: AppSpacing.large),

          // Generation Settings Section
          _buildSectionHeader('Generation Settings'),
          _buildGenerationSettingsCard(),
          const SizedBox(height: AppSpacing.large),

          // API Configuration Section
          _buildSectionHeader('API Configuration'),
          _buildApiConfigCard(),
          const SizedBox(height: AppSpacing.large),

          // Storage Overview Section
          _buildSectionHeader('Storage Overview'),
          _buildStorageOverviewCard(),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smallMedium),
      child: Text(
        title,
        style: AppTypography.headlineSemibold(context),
      ),
    );
  }

  Widget _buildRoutingPolicyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Routing Policy',
              style: AppTypography.subheadlineSemibold(context),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),
            SegmentedButton<RoutingPolicy>(
              segments: const [
                ButtonSegment(
                  value: RoutingPolicy.automatic,
                  label: Text('Auto'),
                ),
                ButtonSegment(
                  value: RoutingPolicy.deviceOnly,
                  label: Text('Device'),
                ),
                ButtonSegment(
                  value: RoutingPolicy.preferDevice,
                  label: Text('Prefer Device'),
                ),
                ButtonSegment(
                  value: RoutingPolicy.preferCloud,
                  label: Text('Prefer Cloud'),
                ),
              ],
              selected: {_routingPolicy},
              onSelectionChanged: (Set<RoutingPolicy> selection) {
                setState(() {
                  _routingPolicy = selection.first;
                });
                unawaited(_saveSettings());
              },
            ),
          ],
        ),
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
            // Temperature
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Temperature',
                  style: AppTypography.subheadline(context),
                ),
                Text(
                  _defaultTemperature.toStringAsFixed(1),
                  style: AppTypography.monospaced.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              value: _defaultTemperature,
              min: 0,
              max: 2,
              divisions: 20,
              onChanged: (value) {
                setState(() {
                  _defaultTemperature = value;
                });
              },
              onChangeEnd: (_) => _saveSettings(),
            ),
            const SizedBox(height: AppSpacing.large),

            // Max Tokens
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Max Tokens',
                  style: AppTypography.subheadline(context),
                ),
                Text(
                  _defaultMaxTokens.toString(),
                  style: AppTypography.monospaced.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              value: _defaultMaxTokens.toDouble(),
              min: 500,
              max: 20000,
              divisions: 39,
              onChanged: (value) {
                setState(() {
                  _defaultMaxTokens = value.toInt();
                });
              },
              onChangeEnd: (_) => _saveSettings(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiConfigCard() {
    final hasApiKey = _apiKey.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showApiKeyEntry) ...[
              TextField(
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'Enter your API key',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _apiKey = value;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.mediumLarge),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showApiKeyEntry = false;
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.smallMedium),
                  FilledButton(
                    onPressed: _saveApiKey,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  hasApiKey ? Icons.check_circle : Icons.warning,
                  color: hasApiKey
                      ? AppColors.statusGreen
                      : AppColors.statusOrange,
                ),
                title: const Text('API Key'),
                subtitle: Text(hasApiKey ? 'Configured' : 'Not Set'),
                trailing: TextButton(
                  onPressed: () {
                    setState(() {
                      _showApiKeyEntry = true;
                    });
                  },
                  child: Text(hasApiKey ? 'Change' : 'Set'),
                ),
              ),
            ],
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
            ),
            const Divider(),
            _buildStorageRow(
              icon: Icons.memory,
              label: 'Models Storage',
              value: _modelStorageSize.formattedFileSize,
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.smallMedium),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconRegular),
          const SizedBox(width: AppSpacing.mediumLarge),
          Expanded(
            child: Text(
              label,
              style: AppTypography.subheadline(context),
            ),
          ),
          Text(
            value,
            style: AppTypography.subheadlineSemibold(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageManagementCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Clear Cache'),
              subtitle: const Text('Remove cached data'),
              trailing: TextButton(
                onPressed: _clearCache,
                child: const Text('Clear'),
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cleaning_services, color: Colors.orange),
              title: const Text('Clean Temporary Files'),
              subtitle: const Text('Remove temporary files'),
              trailing: TextButton(
                onPressed: _cleanTempFiles,
                child: const Text('Clean'),
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
                'Store analytics data on device for debugging',
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
        child: Column(
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.extension),
              title: Text('RunAnywhere SDK'),
              subtitle: Text('Version 0.1'),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.book),
              title: const Text('Documentation'),
              subtitle: const Text('https://docs.runanywhere.ai'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () {
                // TODO: Open documentation URL
              },
            ),
          ],
        ),
      ),
    );
  }
}
