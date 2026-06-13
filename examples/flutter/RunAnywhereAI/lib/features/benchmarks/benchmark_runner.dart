import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';
import 'package:runanywhere_ai/features/benchmarks/llm_benchmark_provider.dart';
import 'package:runanywhere_ai/features/benchmarks/stt_benchmark_provider.dart';
import 'package:runanywhere_ai/features/benchmarks/tts_benchmark_provider.dart';

/// One provider per modality runs deterministic scenarios through the public
/// SDK against a downloaded model (mirrors iOS `BenchmarkScenarioProvider`).
abstract class BenchmarkScenarioProvider {
  BenchmarkCategory get category;
  List<BenchmarkScenario> scenarios();
  Future<BenchmarkMetrics> execute(
    BenchmarkScenario scenario,
    sdk.ModelInfo model,
  );
}

/// Thrown when a run is cancelled by the user (Dart analogue of Swift's
/// `CancellationError`).
class BenchmarkCancelled implements Exception {
  const BenchmarkCancelled();
}

/// Descriptive runner failure (mirrors iOS `BenchmarkRunnerError`).
class BenchmarkRunnerException implements Exception {
  final String message;
  const BenchmarkRunnerException(this.message);

  factory BenchmarkRunnerException.noModelsAvailable(
    List<BenchmarkCategory> skipped,
  ) {
    final names = skipped.map((category) => category.displayName).join(', ');
    return BenchmarkRunnerException(
      'No downloaded models found for: $names. '
      'Download models first from the Models tab.',
    );
  }

  factory BenchmarkRunnerException.noWorkItems(
    List<BenchmarkCategory> skipped,
  ) {
    if (skipped.isEmpty) {
      return const BenchmarkRunnerException(
        'No benchmarks to run. Select at least one downloaded model '
        'and try again.',
      );
    }
    final names = skipped.map((category) => category.displayName).join(', ');
    return BenchmarkRunnerException(
      'No benchmarks to run. Missing on-disk models for: $names. '
      'Download models first from the Models tab.',
    );
  }

  @override
  String toString() => message;
}

/// Pre-flight snapshot of available models per category (mirrors iOS
/// `BenchmarkPreflightResult`).
class BenchmarkPreflightResult {
  final Map<BenchmarkCategory, List<sdk.ModelInfo>> availableCategories;
  final List<BenchmarkCategory> skippedCategories;
  final int totalWorkItems;

  const BenchmarkPreflightResult({
    required this.availableCategories,
    required this.skippedCategories,
    required this.totalWorkItems,
  });
}

/// One scenario/model pair to execute (mirrors iOS `BenchmarkWorkItem`).
class _BenchmarkWorkItem {
  final BenchmarkCategory category;
  final sdk.ModelInfo model;
  final BenchmarkScenario scenario;

  const _BenchmarkWorkItem({
    required this.category,
    required this.model,
    required this.scenario,
  });
}

/// Orchestrates benchmark execution across all providers (mirrors iOS
/// `BenchmarkRunner.swift`).
class BenchmarkRunner {
  final Map<BenchmarkCategory, BenchmarkScenarioProvider> _providers;

  BenchmarkRunner()
      : _providers = {
          for (final provider in <BenchmarkScenarioProvider>[
            LLMBenchmarkProvider(),
            STTBenchmarkProvider(),
            TTSBenchmarkProvider(),
          ])
            provider.category: provider,
        };

  /// Checks which categories have downloaded models before running, so the
  /// UI can inform the user which categories will be skipped.
  Future<BenchmarkPreflightResult> preflight(
    Set<BenchmarkCategory> categories,
  ) async {
    await sdk.RunAnywhere.models.refreshModelRegistry();

    final listResult = await sdk.RunAnywhere.models.list();
    if (!listResult.success) {
      throw const BenchmarkRunnerException(
        'Failed to fetch available models from the registry.',
      );
    }
    final allModels = listResult.models.models;

    final available = <BenchmarkCategory, List<sdk.ModelInfo>>{};
    final skipped = <BenchmarkCategory>[];

    for (final category in BenchmarkCategory.values) {
      if (!categories.contains(category)) continue;
      final provider = _providers[category];
      if (provider == null) {
        skipped.add(category);
        continue;
      }
      final models = downloadedModels(category, allModels);
      if (models.isEmpty) {
        skipped.add(category);
      } else {
        available[category] = models;
      }
    }

    var totalItems = 0;
    available.forEach((category, models) {
      final scenarioCount = _providers[category]?.scenarios().length ?? 0;
      totalItems += models.length * scenarioCount;
    });

    return BenchmarkPreflightResult(
      availableCategories: available,
      skippedCategories: skipped,
      totalWorkItems: totalItems,
    );
  }

  /// Run all scenarios for the selected categories/models sequentially.
  ///
  /// [isCancelled] is polled between work items (Dart has no structured task
  /// cancellation); a cancelled run throws [BenchmarkCancelled].
  Future<BenchmarkRunOutput> runBenchmarks({
    required Set<BenchmarkCategory> categories,
    Set<String>? modelIds,
    required void Function(BenchmarkProgressUpdate update) onProgress,
    bool Function()? isCancelled,
  }) async {
    final preflightResult = await preflight(categories);

    if (preflightResult.availableCategories.isEmpty ||
        preflightResult.totalWorkItems == 0) {
      throw BenchmarkRunnerException.noModelsAvailable(
        preflightResult.skippedCategories,
      );
    }

    final workItems = _buildWorkItems(
      categories: categories,
      modelIds: modelIds,
      preflightResult: preflightResult,
    );

    if (workItems.isEmpty) {
      throw BenchmarkRunnerException.noWorkItems(
        preflightResult.skippedCategories,
      );
    }

    final total = workItems.length;
    final results = <BenchmarkResult>[];

    for (var index = 0; index < workItems.length; index++) {
      if (isCancelled?.call() ?? false) {
        throw const BenchmarkCancelled();
      }
      final item = workItems[index];

      onProgress(BenchmarkProgressUpdate(
        completedCount: index,
        totalCount: total,
        currentScenario: item.scenario.name,
        currentModel: item.model.name,
      ));

      final provider = _providers[item.category];
      if (provider == null) continue;

      BenchmarkMetrics metrics;
      try {
        metrics = await provider.execute(item.scenario, item.model);
      } on BenchmarkCancelled {
        rethrow;
      } catch (e) {
        metrics = BenchmarkMetrics()
          ..errorMessage =
              '${item.category.displayName} [${item.model.name}]: $e';
      }

      results.add(BenchmarkResult(
        category: item.category,
        scenario: item.scenario,
        modelInfo: ComponentModelInfo.fromModel(item.model),
        metrics: metrics,
      ));
    }

    onProgress(BenchmarkProgressUpdate(
      completedCount: total,
      totalCount: total,
      currentScenario: 'Done',
      currentModel: '',
    ));

    return BenchmarkRunOutput(
      results: results,
      skippedCategories: preflightResult.skippedCategories,
    );
  }

  /// Expand `(category × model × scenario)` into a flat work-item list.
  List<_BenchmarkWorkItem> _buildWorkItems({
    required Set<BenchmarkCategory> categories,
    required Set<String>? modelIds,
    required BenchmarkPreflightResult preflightResult,
  }) {
    final workItems = <_BenchmarkWorkItem>[];
    for (final category in BenchmarkCategory.values) {
      if (!categories.contains(category)) continue;
      final provider = _providers[category];
      final models = preflightResult.availableCategories[category];
      if (provider == null || models == null) continue;

      final filteredModels = (modelIds == null || modelIds.isEmpty)
          ? models
          : models.where((model) => modelIds.contains(model.id)).toList();

      for (final model in filteredModels) {
        for (final scenario in provider.scenarios()) {
          workItems.add(_BenchmarkWorkItem(
            category: category,
            model: model,
            scenario: scenario,
          ));
        }
      }
    }
    return workItems;
  }

  /// Models whose artifacts exist on disk for [category].
  ///
  /// The proto `isDownloaded` flag is not flipped by the C++ registry on
  /// download (see `model_types.dart` `isReadyOnDevice` note), so a non-empty
  /// `localPath` is the on-disk signal — mirrors iOS
  /// `BenchmarkRunner.downloadedModels`.
  static List<sdk.ModelInfo> downloadedModels(
    BenchmarkCategory category,
    List<sdk.ModelInfo> allModels,
  ) {
    return allModels
        .where((model) =>
            model.category == category.modelCategory &&
            !model.builtIn &&
            model.localPath.trim().isNotEmpty)
        .toList();
  }
}
