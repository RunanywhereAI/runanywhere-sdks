import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/services/device_info_service.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_runner.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_store.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';

/// Orchestrates benchmark execution, persistence, and history.
///
/// Mirrors iOS `BenchmarkViewModel.swift` as a [ChangeNotifier] (precedent:
/// `model_list_view_model.dart`). Export/clipboard features are an iOS-only
/// extra and are omitted at MVP.
class BenchmarkViewModel extends ChangeNotifier {
  // MARK: - State

  bool isRunning = false;
  double progress = 0;
  String currentScenario = '';
  String currentModel = '';
  int completedCount = 0;
  int totalCount = 0;
  List<BenchmarkRun> pastRuns = [];
  Set<BenchmarkCategory> selectedCategories =
      BenchmarkCategory.values.toSet();
  String? errorMessage;

  /// Categories that had no downloaded models during the last run.
  String? skippedCategoriesMessage;

  /// Available downloaded models grouped by category, for user selection.
  Map<BenchmarkCategory, List<sdk.ModelInfo>> availableModels = {};

  /// Which model IDs the user has selected for benchmarking.
  Set<String> selectedModelIds = {};

  // MARK: - Private

  final BenchmarkRunner _runner = BenchmarkRunner();
  final BenchmarkStore _store = BenchmarkStore();
  bool _cancelRequested = false;

  // MARK: - Lifecycle

  Future<void> loadPastRuns() async {
    pastRuns = (await _store.loadRuns()).reversed.toList();
    notifyListeners();
  }

  void refreshAvailableModels() {
    unawaited(_reloadAvailableModels().then((_) => notifyListeners()));
  }

  /// Resync registry paths from disk, then rebuild the grouped model picker
  /// state (mirrors iOS `reloadAvailableModels`).
  Future<void> _reloadAvailableModels() async {
    try {
      await sdk.RunAnywhere.models.refreshModelRegistry();
      final listResult = await sdk.RunAnywhere.models.list();
      if (!listResult.success) {
        availableModels = {};
        return;
      }
      final allModels = listResult.models.models;
      final grouped = <BenchmarkCategory, List<sdk.ModelInfo>>{};
      for (final category in BenchmarkCategory.values) {
        final models = BenchmarkRunner.downloadedModels(category, allModels);
        if (models.isNotEmpty) {
          grouped[category] = models;
        }
      }
      availableModels = grouped;
    } catch (e) {
      debugPrint('Benchmarks: failed to reload models: $e');
      availableModels = {};
      return;
    }

    final availableIds = availableModels.values
        .expand((models) => models)
        .map((model) => model.id)
        .toSet();
    if (selectedModelIds.isEmpty) {
      selectedModelIds = availableIds;
    } else {
      selectedModelIds = selectedModelIds.intersection(availableIds);
      if (selectedModelIds.isEmpty && availableIds.isNotEmpty) {
        selectedModelIds = availableIds;
      }
    }
  }

  /// Categories that have on-disk models after the latest registry rescan.
  Set<BenchmarkCategory> _categoriesReadyToRun() {
    final withModels = selectedCategories
        .where((category) => availableModels[category]?.isNotEmpty ?? false)
        .toSet();
    return withModels.isEmpty ? selectedCategories : withModels;
  }

  void toggleCategory(BenchmarkCategory category) {
    if (selectedCategories.contains(category)) {
      selectedCategories.remove(category);
    } else {
      selectedCategories.add(category);
    }
    notifyListeners();
  }

  void toggleModel(String modelId) {
    if (selectedModelIds.contains(modelId)) {
      selectedModelIds.remove(modelId);
    } else {
      selectedModelIds.add(modelId);
    }
    notifyListeners();
  }

  void selectModels(Iterable<String> modelIds) {
    selectedModelIds.addAll(modelIds);
    notifyListeners();
  }

  void deselectModels(Iterable<String> modelIds) {
    selectedModelIds.removeAll(modelIds);
    notifyListeners();
  }

  void dismissError() {
    errorMessage = null;
    notifyListeners();
  }

  // MARK: - Run

  void runBenchmarks({bool allCategories = false}) {
    if (isRunning) return;
    if (allCategories) {
      selectedCategories = BenchmarkCategory.values.toSet();
    }
    isRunning = true;
    errorMessage = null;
    skippedCategoriesMessage = null;
    progress = 0;
    completedCount = 0;
    totalCount = 0;
    currentScenario = 'Preparing...';
    currentModel = '';
    _cancelRequested = false;
    notifyListeners();

    unawaited(_executeBenchmarkRun());
  }

  Future<void> _executeBenchmarkRun() async {
    await _reloadAvailableModels();

    final availableIds = availableModels.values
        .expand((models) => models)
        .map((model) => model.id)
        .toSet();
    if (availableIds.isNotEmpty) {
      selectedModelIds = availableIds;
    }
    final categoriesToRun = _categoriesReadyToRun();

    final run = BenchmarkRun(deviceInfo: _makeDeviceInfo());

    try {
      final output = await _runner.runBenchmarks(
        categories: categoriesToRun,
        modelIds: availableIds.isEmpty ? null : availableIds,
        isCancelled: () => _cancelRequested,
        onProgress: (update) {
          progress = update.progress;
          completedCount = update.completedCount;
          totalCount = update.totalCount;
          currentScenario = update.currentScenario;
          currentModel = update.currentModel;
          notifyListeners();
        },
      );

      if (output.skippedCategories.isNotEmpty) {
        final names = output.skippedCategories
            .map((category) => category.displayName)
            .join(', ');
        skippedCategoriesMessage = 'Skipped (no models): $names';
      }

      run.results = output.results;
      run.status = output.results
              .every((result) => result.metrics.didSucceed)
          ? BenchmarkRunStatus.completed
          : BenchmarkRunStatus.failed;
      run.completedAt = DateTime.now();
    } on BenchmarkCancelled {
      run.status = BenchmarkRunStatus.cancelled;
      run.completedAt = DateTime.now();
    } catch (e) {
      run.status = BenchmarkRunStatus.failed;
      run.completedAt = DateTime.now();
      errorMessage = e.toString();
    }

    // Persist completed work only — skip empty failed preflight runs
    // (mirrors iOS persistRunIfNeeded).
    if (run.results.isNotEmpty || run.status == BenchmarkRunStatus.cancelled) {
      await _store.save(run);
    }
    await loadPastRuns();
    isRunning = false;
    notifyListeners();
  }

  void cancel() {
    _cancelRequested = true;
  }

  Future<void> clearAllResults() async {
    await _store.clearAll();
    pastRuns = [];
    notifyListeners();
  }

  // MARK: - Helpers

  BenchmarkDeviceInfo _makeDeviceInfo() {
    final info = DeviceInfoService.shared.deviceInfo;
    return BenchmarkDeviceInfo(
      modelName: info?.modelName ?? 'Unknown',
      chipName: info?.chipName ?? 'Unknown',
      totalMemoryBytes: info?.totalMemory ?? 0,
      availableMemoryBytes: info?.availableMemory ?? 0,
      osVersion: info?.osVersion ?? 'Unknown',
    );
  }
}
