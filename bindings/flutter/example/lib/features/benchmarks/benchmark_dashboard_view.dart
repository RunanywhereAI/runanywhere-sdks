import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/core/services/device_info_service.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_view_model.dart';

/// Main benchmarking screen: device info, category filters, model selection,
/// run controls, progress, and history.
///
/// Mirrors iOS `BenchmarkDashboardView.swift` at MVP fidelity.
class BenchmarkDashboardView extends StatefulWidget {
  const BenchmarkDashboardView({super.key});

  @override
  State<BenchmarkDashboardView> createState() => _BenchmarkDashboardViewState();
}

class _BenchmarkDashboardViewState extends State<BenchmarkDashboardView> {
  final BenchmarkViewModel _viewModel = BenchmarkViewModel();

  @override
  void initState() {
    super.initState();
    unawaited(_viewModel.loadPastRuns());
    _viewModel.refreshAvailableModels();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Benchmarks'),
            actions: [
              if (_viewModel.pastRuns.isNotEmpty)
                TextButton(
                  onPressed: _confirmClearAll,
                  child: const Text(
                    'Clear All',
                    style: TextStyle(color: AppColors.primaryRed),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.large),
            children: [
              if (_viewModel.isRunning) ...[
                _buildProgressCard(),
                const SizedBox(height: AppSpacing.large),
              ],
              _buildSectionHeader('Device'),
              _buildDeviceCard(),
              const SizedBox(height: AppSpacing.large),
              _buildSectionHeader('Benchmark Suite'),
              _buildSuiteInfoCard(),
              const SizedBox(height: AppSpacing.large),
              _buildSectionHeader('Categories'),
              _buildCategoriesCard(),
              const SizedBox(height: AppSpacing.large),
              if (_visibleModelCategories.isNotEmpty) ...[
                _buildModelsHeader(),
                _buildModelsCard(),
                const SizedBox(height: AppSpacing.large),
              ],
              _buildRunControls(),
              if (_viewModel.skippedCategoriesMessage != null) ...[
                const SizedBox(height: AppSpacing.large),
                _buildWarningCard(_viewModel.skippedCategoriesMessage!),
              ],
              if (_viewModel.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.large),
                _buildErrorCard(_viewModel.errorMessage!),
              ],
              const SizedBox(height: AppSpacing.large),
              _buildSectionHeader('History'),
              if (_viewModel.pastRuns.isEmpty)
                _buildEmptyHistoryCard()
              else
                ..._viewModel.pastRuns.map(_buildRunRow),
              const SizedBox(height: AppSpacing.xxLarge),
            ],
          ),
        );
      },
    );
  }

  List<BenchmarkCategory> get _visibleModelCategories =>
      BenchmarkCategory.values
          .where((category) =>
              _viewModel.selectedCategories.contains(category) &&
              (_viewModel.availableModels[category]?.isNotEmpty ?? false))
          .toList();

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

  // MARK: - Progress

  Widget _buildProgressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Running Benchmarks',
              style: AppTypography.subheadlineSemibold(context),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            LinearProgressIndicator(value: _viewModel.progress),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              _viewModel.totalCount > 0
                  ? '${_viewModel.completedCount}/${_viewModel.totalCount} — '
                      '${_viewModel.currentScenario}'
                  : _viewModel.currentScenario,
              style: AppTypography.caption(context),
            ),
            if (_viewModel.currentModel.isNotEmpty)
              Text(
                _viewModel.currentModel,
                style: AppTypography.caption2(context)
                    .copyWith(color: AppColors.textSecondary(context)),
              ),
            const SizedBox(height: AppSpacing.smallMedium),
            OutlinedButton(
              onPressed: _viewModel.cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryRed,
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Device

  Widget _buildDeviceCard() {
    return ListenableBuilder(
      listenable: DeviceInfoService.shared,
      builder: (context, _) {
        final info = DeviceInfoService.shared.deviceInfo;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Column(
              children: [
                _labeledRow('Model', info?.modelName ?? 'Unknown'),
                if ((info?.chipName ?? '').isNotEmpty)
                  _labeledRow('Chip', info!.chipName),
                _labeledRow('OS', info?.osVersion ?? 'Unknown'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _labeledRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xSmall),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.subheadline(context)),
          Flexible(
            child: Text(
              value,
              style: AppTypography.subheadline(context)
                  .copyWith(color: AppColors.textSecondary(context)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Suite Info

  Widget _buildSuiteInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Text(
          'Each category runs deterministic scenarios against every '
          'downloaded model of that type. Synthetic inputs (silent audio, '
          'sine waves) ensure reproducible results.',
          style: AppTypography.caption(context)
              .copyWith(color: AppColors.textSecondary(context)),
        ),
      ),
    );
  }

  // MARK: - Categories

  Widget _buildCategoriesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.smallMedium,
              runSpacing: AppSpacing.smallMedium,
              children: BenchmarkCategory.values.map((category) {
                final isSelected =
                    _viewModel.selectedCategories.contains(category);
                return FilterChip(
                  avatar: Icon(
                    _categoryIcon(category),
                    size: 16,
                    color: isSelected
                        ? AppColors.primaryAccent
                        : AppColors.textSecondary(context),
                  ),
                  label: Text(category.displayName),
                  selected: isSelected,
                  onSelected: (_) => _viewModel.toggleCategory(category),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            ...BenchmarkCategory.values
                .where(_viewModel.selectedCategories.contains)
                .map(_buildScenarioDescriptionRow),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioDescriptionRow(BenchmarkCategory category) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.smallMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _categoryIcon(category),
                size: 14,
                color: AppColors.primaryAccent,
              ),
              const SizedBox(width: AppSpacing.small),
              Text(
                category.displayName,
                style: AppTypography.caption2Medium(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxSmall),
          Text(
            _scenarioDescription(category),
            style: AppTypography.caption(context)
                .copyWith(color: AppColors.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  // MARK: - Models

  Widget _buildModelsHeader() {
    final visibleIds = _visibleModelCategories
        .expand(
          (category) => _viewModel.availableModels[category] ?? <sdk.ModelInfo>[],
        )
        .map((model) => model.id)
        .toList();
    return _buildSectionHeader(
      'Models',
      trailing: Row(
        children: [
          TextButton(
            onPressed: () => _viewModel.selectModels(visibleIds),
            child: const Text('All'),
          ),
          TextButton(
            onPressed: () => _viewModel.deselectModels(visibleIds),
            child: const Text('None'),
          ),
        ],
      ),
    );
  }

  Widget _buildModelsCard() {
    return Card(
      child: Column(
        children: _visibleModelCategories.map((category) {
          final models = _viewModel.availableModels[category] ?? [];
          final selectedCount = models
              .where((model) => _viewModel.selectedModelIds.contains(model.id))
              .length;
          return ExpansionTile(
            leading: Icon(_categoryIcon(category)),
            title: Text(
              category.displayName,
              style: AppTypography.subheadlineMedium(context),
            ),
            trailing: Text(
              '$selectedCount/${models.length}',
              style: AppTypography.caption(context)
                  .copyWith(color: AppColors.textSecondary(context)),
            ),
            children: models.map((model) {
              final isSelected =
                  _viewModel.selectedModelIds.contains(model.id);
              return CheckboxListTile(
                value: isSelected,
                onChanged: (_) => _viewModel.toggleModel(model.id),
                title: Text(model.name,
                    style: AppTypography.subheadline(context)),
                subtitle: Text(
                  sdk.formatFramework(model.framework),
                  style: AppTypography.caption(context)
                      .copyWith(color: AppColors.textSecondary(context)),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  // MARK: - Run Controls

  Widget _buildRunControls() {
    final selectedCount = _viewModel.selectedCategories.length;
    final allCount = BenchmarkCategory.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _viewModel.isRunning
              ? null
              : () => _viewModel.runBenchmarks(allCategories: true),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Run All Benchmarks'),
        ),
        if (selectedCount < allCount && selectedCount > 0) ...[
          const SizedBox(height: AppSpacing.smallMedium),
          OutlinedButton.icon(
            onPressed:
                _viewModel.isRunning ? null : _viewModel.runBenchmarks,
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text('Run Selected ($selectedCount)'),
          ),
        ],
        if (selectedCount == 0) ...[
          const SizedBox(height: AppSpacing.smallMedium),
          Text(
            'Select at least one category to run benchmarks.',
            style: AppTypography.caption(context)
                .copyWith(color: AppColors.statusOrange),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // MARK: - Warnings / Errors

  Widget _buildWarningCard(String message) {
    return Card(
      color: AppColors.statusOrange.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppColors.statusOrange),
            const SizedBox(width: AppSpacing.smallMedium),
            Expanded(
              child: Text(
                message,
                style: AppTypography.caption(context)
                    .copyWith(color: AppColors.statusOrange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      color: AppColors.statusRed.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.statusRed),
            const SizedBox(width: AppSpacing.smallMedium),
            Expanded(
              child: Text(
                message,
                style: AppTypography.caption(context)
                    .copyWith(color: AppColors.statusRed),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: _viewModel.dismissError,
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - History

  Widget _buildEmptyHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxLarge,
          horizontal: AppSpacing.large,
        ),
        child: Column(
          children: [
            Icon(
              Icons.speed,
              size: 48,
              color: AppColors.textSecondary(context).withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.mediumLarge),
            Text(
              'No benchmark results yet',
              style: AppTypography.callout(context)
                  .copyWith(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'Download models first, then run benchmarks to measure '
              'on-device AI performance.',
              style: AppTypography.caption(context)
                  .copyWith(color: AppColors.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunRow(BenchmarkRun run) {
    final duration = run.duration;
    final failCount = run.results
        .where((result) => !result.metrics.didSucceed)
        .length;
    return Card(
      child: ListTile(
        title: Text(
          _formatDate(run.startedAt),
          style: AppTypography.subheadlineMedium(context),
        ),
        subtitle: Text(
          [
            if (duration != null)
              '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
            run.results.isEmpty
                ? 'No results'
                : '${run.results.length} results',
            if (failCount > 0) '$failCount failed',
          ].join(' · '),
          style: AppTypography.caption(context)
              .copyWith(color: AppColors.textSecondary(context)),
        ),
        leading: _RunStatusBadge(status: run.status),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => _BenchmarkRunDetailView(run: run),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmClearAll() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Clear All Results?'),
          content:
              const Text('This will permanently delete all benchmark history.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(_viewModel.clearAllResults());
              },
              child: const Text(
                'Clear',
                style: TextStyle(color: AppColors.primaryRed),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _categoryIcon(BenchmarkCategory category) {
    switch (category) {
      case BenchmarkCategory.llm:
        return Icons.chat_bubble_outline;
      case BenchmarkCategory.stt:
        return Icons.graphic_eq;
      case BenchmarkCategory.tts:
        return Icons.volume_up;
    }
  }

  static String _scenarioDescription(BenchmarkCategory category) {
    switch (category) {
      case BenchmarkCategory.llm:
        return 'Short (50 tok), Medium (256 tok), Long (512 tok) — '
            'measures tok/s, TTFT, load time';
      case BenchmarkCategory.stt:
        return 'Silent 2s, Sine Tone 3s — measures RTF, processing time';
      case BenchmarkCategory.tts:
        return 'Short text, Medium text — measures audio duration, '
            'char throughput';
    }
  }
}

String _formatDate(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} '
      '${pad(date.hour)}:${pad(date.minute)}';
}

/// Status badge matching iOS `RunStatusBadge`.
class _RunStatusBadge extends StatelessWidget {
  final BenchmarkRunStatus status;

  const _RunStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BenchmarkRunStatus.completed => AppColors.statusGreen,
      BenchmarkRunStatus.running => AppColors.statusBlue,
      BenchmarkRunStatus.cancelled => AppColors.statusOrange,
      BenchmarkRunStatus.failed => AppColors.statusRed,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smallMedium,
        vertical: AppSpacing.xxSmall,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppSpacing.smallMedium),
      ),
      child: Text(
        status.name[0].toUpperCase() + status.name.substring(1),
        style: AppTypography.caption2Medium(context).copyWith(color: color),
      ),
    );
  }
}

/// Per-run detail: device snapshot plus one card per result with all
/// captured metrics (MVP equivalent of iOS `BenchmarkDetailView`).
class _BenchmarkRunDetailView extends StatelessWidget {
  final BenchmarkRun run;

  const _BenchmarkRunDetailView({required this.run});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Run Details')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.large),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDate(run.startedAt),
                        style: AppTypography.subheadlineSemibold(context),
                      ),
                      _RunStatusBadge(status: run.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.smallMedium),
                  Text(
                    '${run.deviceInfo.modelName} · '
                    '${run.deviceInfo.osVersion}',
                    style: AppTypography.caption(context)
                        .copyWith(color: AppColors.textSecondary(context)),
                  ),
                  if (run.duration != null)
                    Text(
                      'Duration: '
                      '${(run.duration!.inMilliseconds / 1000).toStringAsFixed(1)}s',
                      style: AppTypography.caption(context)
                          .copyWith(color: AppColors.textSecondary(context)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          ...run.results.map((result) => _ResultCard(result: result)),
          const SizedBox(height: AppSpacing.xxLarge),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final BenchmarkResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final metrics = result.metrics;
    final rows = <(String, String)>[
      if (metrics.loadTimeMs > 0)
        ('Load time', '${metrics.loadTimeMs.toStringAsFixed(0)} ms'),
      if (metrics.warmupTimeMs > 0)
        ('Warmup', '${metrics.warmupTimeMs.toStringAsFixed(0)} ms'),
      if (metrics.endToEndLatencyMs > 0)
        ('Latency', '${metrics.endToEndLatencyMs.toStringAsFixed(0)} ms'),
      if (metrics.ttftMs != null)
        ('TTFT', '${metrics.ttftMs!.toStringAsFixed(0)} ms'),
      if (metrics.tokensPerSecond != null)
        ('Tokens/sec', metrics.tokensPerSecond!.toStringAsFixed(1)),
      if (metrics.prefillTokensPerSecond != null)
        ('Prefill tok/s', metrics.prefillTokensPerSecond!.toStringAsFixed(1)),
      if (metrics.decodeTokensPerSecond != null)
        ('Decode tok/s', metrics.decodeTokensPerSecond!.toStringAsFixed(1)),
      if (metrics.inputTokens != null)
        ('Input tokens', '${metrics.inputTokens}'),
      if (metrics.outputTokens != null)
        ('Output tokens', '${metrics.outputTokens}'),
      if (metrics.audioLengthSeconds != null)
        ('Audio length', '${metrics.audioLengthSeconds!.toStringAsFixed(1)}s'),
      if (metrics.realTimeFactor != null)
        ('Real-time factor', metrics.realTimeFactor!.toStringAsFixed(3)),
      if (metrics.audioDurationSeconds != null)
        (
          'Audio duration',
          '${metrics.audioDurationSeconds!.toStringAsFixed(2)}s'
        ),
      if (metrics.charactersProcessed != null)
        ('Characters', '${metrics.charactersProcessed}'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${result.category.displayName} — '
                    '${result.scenario.name}',
                    style: AppTypography.subheadlineSemibold(context),
                  ),
                ),
                Icon(
                  metrics.didSucceed ? Icons.check_circle : Icons.error,
                  size: 18,
                  color: metrics.didSucceed
                      ? AppColors.statusGreen
                      : AppColors.statusRed,
                ),
              ],
            ),
            Text(
              '${result.modelInfo.name} · ${result.modelInfo.framework}',
              style: AppTypography.caption(context)
                  .copyWith(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            if (metrics.errorMessage != null)
              Text(
                metrics.errorMessage!,
                style: AppTypography.caption(context)
                    .copyWith(color: AppColors.statusRed),
              )
            else
              ...rows.map(
                (row) => Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.xxSmall),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(row.$1, style: AppTypography.caption(context)),
                      Text(
                        row.$2,
                        style: AppTypography.captionMedium(context),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
