import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/models/app_types.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
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

  // Loading state
  bool _isRefreshingStorage = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_loadStorageData());
  }

  Future<void> _loadSettings() async {
    // Load from keychain
    _analyticsLogToLocal =
        await KeychainHelper.loadBool(KeychainKeys.analyticsLogToLocal);
    if (mounted) {
      setState(() {});
    }
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

  // ignore: unused_element - kept for future use
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
