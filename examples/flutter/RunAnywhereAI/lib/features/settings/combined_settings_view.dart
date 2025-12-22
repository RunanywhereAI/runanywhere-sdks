import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

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
/// and API settings. Uses RunAnywhere SDK for actual storage operations.
class CombinedSettingsView extends StatefulWidget {
  const CombinedSettingsView({super.key});

  @override
  State<CombinedSettingsView> createState() => _CombinedSettingsViewState();
}

class _CombinedSettingsViewState extends State<CombinedSettingsView> {
  // Generation settings
  double _temperature = 0.7;
  int _maxTokens = 1000;

  // API Configuration
  bool _showApiKeyEntry = false;
  String _apiKey = '';
  bool _isApiKeyConfigured = false;

  // Logging
  bool _analyticsLogToLocal = false;

  // Storage info (from SDK)
  int _totalStorageSize = 0;
  int _availableSpace = 0;
  int _modelStorageSize = 0;
  List<StoredModelInfo> _storedModels = [];

  // Loading state
  bool _isRefreshingStorage = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_loadStorageData());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _temperature =
          prefs.getDouble(PreferenceKeys.defaultTemperature) ?? 0.7;
      _maxTokens = prefs.getInt(PreferenceKeys.defaultMaxTokens) ?? 1000;
    });

    // Load from keychain
    _analyticsLogToLocal =
        await KeychainHelper.loadBool(KeychainKeys.analyticsLogToLocal);
    final savedApiKey = await KeychainHelper.loadString(KeychainKeys.apiKey);
    if (savedApiKey != null && savedApiKey.isNotEmpty) {
      setState(() {
        _apiKey = savedApiKey;
        _isApiKeyConfigured = true;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PreferenceKeys.defaultTemperature, _temperature);
    await prefs.setInt(PreferenceKeys.defaultMaxTokens, _maxTokens);
  }

  /// Load storage data using RunAnywhere SDK
  Future<void> _loadStorageData() async {
    setState(() {
      _isRefreshingStorage = true;
    });

    try {
      // Get storage info from SDK
      final storageInfo = await sdk.RunAnywhere.getStorageInfo();

      // Get downloaded models from SDK
      final downloadedModels = await sdk.RunAnywhere.getDownloadedModels();
      final storedModels = <StoredModelInfo>[];

      // Convert to StoredModelInfo list
      downloadedModels.forEach((framework, modelIds) {
        for (final modelId in modelIds) {
          storedModels.add(StoredModelInfo(
            id: modelId,
            name: modelId, // Will be replaced with actual name if available
            framework: framework,
            size: 0, // Size would need to be calculated
            createdDate: DateTime.now(),
          ));
        }
      });

      if (mounted) {
        setState(() {
          _totalStorageSize = storageInfo.appStorage.totalSize;
          _availableSpace = storageInfo.deviceStorage.freeSpace;
          _modelStorageSize = storageInfo.modelStorage.totalSize;
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

  Future<void> _saveApiKey() async {
    if (_apiKey.isNotEmpty) {
      await KeychainHelper.saveString(key: KeychainKeys.apiKey, data: _apiKey);
      if (mounted) {
        setState(() {
          _isApiKeyConfigured = true;
          _showApiKeyEntry = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API Key saved securely')),
        );
      }
    }
  }

  void _cancelApiKeyEntry() {
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

  /// Clear cache using RunAnywhere SDK
  Future<void> _clearCache() async {
    try {
      await sdk.RunAnywhere.clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
      await _loadStorageData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    }
  }

  /// Clean temp files using RunAnywhere SDK
  Future<void> _cleanTempFiles() async {
    try {
      await sdk.RunAnywhere.cleanTempFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temporary files cleaned')),
        );
      }
      await _loadStorageData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clean temp files: $e')),
        );
      }
    }
  }

  /// Delete a stored model using RunAnywhere SDK
  Future<void> _deleteModel(StoredModelInfo model) async {
    try {
      await sdk.RunAnywhere.deleteStoredModel(model.id, model.framework);
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

  Future<void> _openDocumentation() async {
    // Documentation URL - would use url_launcher in production
    debugPrint('Opening documentation: https://docs.runanywhere.ai');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documentation: docs.runanywhere.ai')),
      );
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
          // Generation Settings Section
          _buildSectionHeader('Generation Settings'),
          _buildGenerationSettingsCard(),
          const SizedBox(height: AppSpacing.large),

          // API Configuration Section
          _buildSectionHeader('API Configuration'),
          _buildApiConfigCard(),
          const SizedBox(height: AppSpacing.large),

          // Storage Overview Section
          _buildSectionHeader('Storage Overview', trailing: _buildRefreshButton()),
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
            // Temperature
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Temperature', style: AppTypography.subheadline(context)),
                Text(
                  _temperature.toStringAsFixed(2),
                  style: AppTypography.monospaced.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              value: _temperature,
              min: 0,
              max: 2,
              divisions: 20,
              onChanged: (value) {
                setState(() {
                  _temperature = value;
                });
              },
              onChangeEnd: (_) => _saveSettings(),
            ),
            const SizedBox(height: AppSpacing.large),

            // Max Tokens
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Max Tokens', style: AppTypography.subheadline(context)),
                Text(
                  _maxTokens.toString(),
                  style: AppTypography.monospaced.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              value: _maxTokens.toDouble(),
              min: 500,
              max: 20000,
              divisions: 39,
              onChanged: (value) {
                setState(() {
                  _maxTokens = value.toInt();
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
              const SizedBox(height: AppSpacing.smallMedium),
              Text(
                'Your API key is stored securely in the keychain',
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: AppSpacing.mediumLarge),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _cancelApiKeyEntry,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.smallMedium),
                  FilledButton(
                    onPressed: _apiKey.isEmpty ? null : _saveApiKey,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _isApiKeyConfigured ? Icons.check_circle : Icons.warning,
                  color: _isApiKeyConfigured
                      ? AppColors.statusGreen
                      : AppColors.statusOrange,
                ),
                title: const Text('API Key'),
                subtitle: Text(_isApiKeyConfigured ? 'Configured' : 'Not Set'),
                trailing: TextButton(
                  onPressed: () {
                    setState(() {
                      _showApiKeyEntry = true;
                    });
                  },
                  child: Text(_isApiKeyConfigured ? 'Change' : 'Configure'),
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
                      color: AppColors.textSecondary(context).withValues(alpha: 0.5),
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
                        onDelete: () => _deleteModel(model),
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
        child: Column(
          children: [
            _buildManagementButton(
              icon: Icons.delete_outline,
              title: 'Clear Cache',
              subtitle: 'Free up space by clearing cached data',
              color: AppColors.primaryRed,
              onTap: _clearCache,
            ),
            const SizedBox(height: AppSpacing.large),
            _buildManagementButton(
              icon: Icons.cleaning_services,
              title: 'Clean Temporary Files',
              subtitle: 'Remove temporary files and logs',
              color: AppColors.primaryOrange,
              onTap: _cleanTempFiles,
            ),
          ],
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
        child: Column(
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.extension, color: AppColors.primaryBlue),
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
              onTap: _openDocumentation,
            ),
          ],
        ),
      ),
    );
  }
}

/// Stored model info for display
class StoredModelInfo {
  final String id;
  final String name;
  final sdk.LLMFramework framework;
  final int size;
  final DateTime createdDate;
  final DateTime? lastUsed;

  const StoredModelInfo({
    required this.id,
    required this.name,
    required this.framework,
    required this.size,
    required this.createdDate,
    this.lastUsed,
  });
}

/// Stored model row widget
class _StoredModelRow extends StatefulWidget {
  final StoredModelInfo model;
  final VoidCallback onDelete;

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

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Are you sure you want to delete ${widget.model.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isDeleting = true);
              widget.onDelete();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
                        : const Icon(Icons.delete_outline, color: AppColors.primaryRed),
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
                borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Downloaded:', _formatDate(widget.model.createdDate)),
                  if (widget.model.lastUsed != null)
                    _buildDetailRow('Last used:', _formatRelativeDate(widget.model.lastUsed!)),
                  _buildDetailRow('Size:', widget.model.size.formattedFileSize),
                  _buildDetailRow('Framework:', widget.model.framework.displayName),
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

  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }
}
