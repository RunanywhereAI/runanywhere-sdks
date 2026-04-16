import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/public/types/download_types.dart';

class ModelDownloadInfo {
  const ModelDownloadInfo({
    required this.modelId,
    this.progress = 0.0,
    this.stage = DownloadProgressStage.queued,
    this.state = DownloadProgressState.downloading,
  });

  final String modelId;
  final double progress;
  final DownloadProgressStage stage;
  final DownloadProgressState state;

  String get stageLabel => switch (stage) {
        DownloadProgressStage.queued => 'Queued',
        DownloadProgressStage.downloading => 'Downloading',
        DownloadProgressStage.extracting => 'Extracting',
        DownloadProgressStage.verifying => 'Verifying',
        DownloadProgressStage.completed => 'Complete',
        DownloadProgressStage.failed => 'Failed',
        DownloadProgressStage.cancelled => 'Cancelled',
      };
}

class ModelsState {
  const ModelsState({
    this.models = const [],
    this.isLoading = false,
    this.loadingModelId,
    this.downloads = const {},
    this.errorMessage,
  });

  final List<ModelInfo> models;
  final bool isLoading;
  final String? loadingModelId;
  final Map<String, ModelDownloadInfo> downloads;
  final String? errorMessage;

  ModelsState copyWith({
    List<ModelInfo>? models,
    bool? isLoading,
    String? loadingModelId,
    Map<String, ModelDownloadInfo>? downloads,
    String? errorMessage,
    bool clearLoading = false,
    bool clearError = false,
  }) {
    return ModelsState(
      models: models ?? this.models,
      isLoading: isLoading ?? this.isLoading,
      loadingModelId:
          clearLoading ? null : (loadingModelId ?? this.loadingModelId),
      downloads: downloads ?? this.downloads,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final modelsControllerProvider =
    NotifierProvider<ModelsController, ModelsState>(ModelsController.new);

class ModelsController extends Notifier<ModelsState> {
  @override
  ModelsState build() {
    _loadModels();
    return const ModelsState(isLoading: true);
  }

  Future<void> _loadModels() async {
    try {
      final models = await sdk.RunAnywhere.availableModels();
      state = state.copyWith(models: models, isLoading: false);
    } on Exception catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadModels();
  }

  Future<void> downloadModel(ModelInfo model) async {
    state = state.copyWith(
      downloads: {
        ...state.downloads,
        model.id: ModelDownloadInfo(modelId: model.id),
      },
      clearError: true,
    );

    try {
      await for (final progress in sdk.RunAnywhere.downloadModel(model.id)) {
        state = state.copyWith(
          downloads: {
            ...state.downloads,
            model.id: ModelDownloadInfo(
              modelId: model.id,
              progress: progress.overallProgress,
              stage: progress.stage,
              state: progress.state,
            ),
          },
        );

        if (progress.state.isCompleted || progress.state.isFailed) {
          break;
        }
      }

      // Remove from active downloads and refresh models list
      final updatedDownloads = Map<String, ModelDownloadInfo>.from(
        state.downloads,
      )..remove(model.id);
      state = state.copyWith(downloads: updatedDownloads);
      await _loadModels();
    } on Exception catch (e) {
      final updatedDownloads = Map<String, ModelDownloadInfo>.from(
        state.downloads,
      )..remove(model.id);
      state = state.copyWith(
        downloads: updatedDownloads,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> deleteModel(ModelInfo model) async {
    try {
      await sdk.RunAnywhere.deleteStoredModel(model.id);
      await _loadModels();
    } on Exception catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> loadModel(ModelInfo model) async {
    if (!model.isDownloaded) {
      await downloadModel(model);
      // Re-fetch model to check if it's now downloaded
      final models = await sdk.RunAnywhere.availableModels();
      final updated = models.where((m) => m.id == model.id).firstOrNull;
      if (updated == null || !updated.isDownloaded) return;
      model = updated;
    }

    state = state.copyWith(loadingModelId: model.id, clearError: true);

    try {
      switch (model.category) {
        case ModelCategory.language:
          await sdk.RunAnywhere.loadModel(model.id);
        case ModelCategory.speechRecognition:
          await sdk.RunAnywhere.loadSTTModel(model.id);
        case ModelCategory.speechSynthesis:
          await sdk.RunAnywhere.loadTTSVoice(model.id);
        case ModelCategory.multimodal || ModelCategory.vision:
          await sdk.RunAnywhere.loadVLMModel(model.id);
        default:
          await sdk.RunAnywhere.loadModel(model.id);
      }
      state = state.copyWith(clearLoading: true);
      await _loadModels();
    } on Exception catch (e) {
      state = state.copyWith(clearLoading: true, errorMessage: e.toString());
    }
  }
}
