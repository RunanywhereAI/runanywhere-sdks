import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/features/models/model_list_view_model.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// Shared lifecycle base for the single-component Voice ViewModels
/// (STT / TTS / VAD). Mirrors iOS `VoiceComponentViewModelBase.swift`:
/// it owns the idempotent initialize/subscribe/cleanup plumbing every
/// voice-component screen needs so each concrete ViewModel only declares
/// its component identity and how it maps an SDK event onto its state.
///
/// `VoiceAgentViewModel` is intentionally NOT built on this base: it
/// orchestrates the full STT -> LLM -> TTS pipeline and consumes
/// per-component event streams plus lifecycle snapshots, a richer pattern
/// than the single-component load/unload tracking captured here.
abstract class VoiceComponentViewModelBase extends ChangeNotifier {
  VoiceComponentViewModelBase();

  // --- Published model state -----------------------------------------------

  /// Framework of the currently loaded model (for the status banner).
  LLMFramework? selectedFramework;

  /// Display name of the currently loaded model.
  String? selectedModelName;

  /// Registry id of the currently loaded model.
  String? selectedModelId;

  /// Last error to surface in the UI, or null.
  String? errorMessage;

  // --- Subscription / idempotency state -------------------------------------

  StreamSubscription<sdk.ModelLifecycleChange>? _lifecycleSubscription;
  bool _isInitialized = false;
  bool _hasSubscribedToSDKEvents = false;
  bool _disposed = false;

  // --- Component identity (override in subclasses) --------------------------

  /// SDK component this ViewModel tracks (e.g. `SDK_COMPONENT_STT`).
  sdk.SDKComponent get component;

  /// Event category that carries this component's lifecycle events.
  sdk.EventCategory get eventCategory;

  /// Model category used to query the initial loaded model.
  ModelCategory get modelCategory;

  /// Whether a model is currently selected/loaded for this component.
  bool get hasModelSelected => selectedModelId != null;

  /// Surface an error produced outside the ViewModel (e.g. a denied
  /// permission request, which the view owns because it needs BuildContext).
  void reportError(String message) {
    errorMessage = message;
    notify();
  }

  // --- Initialization --------------------------------------------------------

  /// Claim the one-time initialization guard. Subclasses call this at the
  /// top of their `initialize()`; when it returns `true` they own the
  /// remaining setup (subscriptions, initial-state query).
  @protected
  bool beginInitialization() {
    if (_isInitialized) {
      debugPrint('Voice component view model already initialized, skipping');
      return false;
    }
    _isInitialized = true;
    return true;
  }

  // --- Model loading ---------------------------------------------------------

  /// Modality-specific canonical SDK load call
  /// (`stt.load` / `tts.loadVoice` / `vad.loadModel`).
  @protected
  Future<void> performLoad(ModelInfo model);

  /// Load a model for this component via the canonical SDK entry point.
  /// Shared by every voice-component screen; subclasses wrap it only to
  /// toggle their busy flag.
  Future<bool> loadModel(ModelInfo model) async {
    debugPrint('Loading $component model: ${model.name}');
    errorMessage = null;
    notify();

    try {
      await performLoad(model);
    } catch (e) {
      debugPrint('Model load failed: $e');
      errorMessage = 'Failed to load model: $e';
      notify();
      return false;
    }
    applyLoadedModel(model);
    debugPrint('Model loaded: ${model.id}');
    return true;
  }

  // --- SDK event subscription ------------------------------------------------

  /// Subscribe to the SDK's unified model-lifecycle stream, filtered to this
  /// component. Idempotent. Mirrors iOS `subscribeToSDKEvents()`.
  @protected
  void subscribeToSDKEvents() {
    if (_hasSubscribedToSDKEvents) {
      debugPrint('Already subscribed to SDK events, skipping');
      return;
    }
    _hasSubscribedToSDKEvents = true;

    _lifecycleSubscription = sdk.RunAnywhere.events.modelLifecycle.listen(
      (change) {
        if (change.component != component &&
            change.event.category != eventCategory) {
          return;
        }
        switch (change.kind) {
          case sdk.ModelLifecycleChangeKind.loaded:
            // Resolve from the event payload, never re-query the SDK here:
            // `modelLifecycle.current()` itself publishes a loaded lifecycle
            // event, so calling it from inside this handler feeds back into an
            // infinite loaded -> current() -> loaded loop that ANRs the app.
            // The change carries the model id; resolve the rest from the
            // catalog and apply through `applyLoadedModel` so the subclass
            // overrides (STT live-mode, TTS system-voice) still run.
            applyLoadedModel(resolveLoadedModel(change.modelId));
            debugPrint('Voice component model loaded: ${change.modelId}');
          case sdk.ModelLifecycleChangeKind.unloaded:
            clearLoadedModel();
            debugPrint('Voice component model unloaded');
        }
      },
    );
  }

  // --- Initial model state ----------------------------------------------------

  /// Apply the SDK's current-model snapshot at cold start.
  @protected
  Future<void> checkInitialModelState() =>
      applyCurrentModelSnapshot('already loaded');

  /// Resolve the current model for this modality via the SDK snapshot and
  /// apply it to published state. Used ONLY at cold start
  /// ([checkInitialModelState]); a one-shot `current()` outside an event
  /// handler is safe. The lifecycle-loaded listener must NOT call this:
  /// `modelLifecycle.current()` re-publishes a loaded event, which from inside
  /// the handler loops forever — it resolves from the event payload instead.
  @protected
  Future<void> applyCurrentModelSnapshot(String reason) async {
    final result = await sdk.RunAnywhere.modelLifecycle.current(
      sdk.CurrentModelRequest(
        category: modelCategory,
        includeModelMetadata: true,
      ),
    );
    if (_disposed || !result.found) return;

    // When the snapshot omits model metadata, `model.id` is empty; fall back
    // to the top-level `modelId` so the id is always populated.
    final model = result.model.deepCopy();
    if (model.id.isEmpty) {
      model.id = result.modelId;
    }
    applyLoadedModel(model);
    debugPrint('Voice component model $reason: ${model.id}');
  }

  /// Apply a model resolved at startup (or via an event) to published state.
  /// Default uses the model's own name/framework; override when a modality
  /// needs different resolution (e.g. catalog lookup or voice-id display).
  @protected
  void applyLoadedModel(ModelInfo model) {
    selectedModelId = model.id;
    selectedModelName = model.name.isNotEmpty ? model.name : model.id;
    selectedFramework = model.framework;
    notify();
  }

  /// Resolve display name/framework through the shared model catalog when
  /// available (mirrors the iOS STT/VAD `applyLoadedModel` overrides).
  @protected
  void applyLoadedModelFromCatalog(ModelInfo model) {
    selectedModelId = model.id;
    final matches = ModelListViewModel.shared.availableModels
        .where((m) => m.id == model.id);
    if (matches.isNotEmpty) {
      final match = matches.first;
      selectedModelName = match.name;
      selectedFramework = match.framework;
    } else {
      selectedModelName = model.name.isNotEmpty ? model.name : model.id;
      selectedFramework = model.framework;
    }
    notify();
  }

  /// Resolve the full [ModelInfo] for a just-loaded [modelId] from the shared
  /// catalog, falling back to an id-only model when the catalog has no entry.
  /// Used by the lifecycle-loaded listener, which only carries the id — this
  /// avoids re-querying the SDK (which would loop) while still giving the
  /// subclass `applyLoadedModel` overrides a populated name/framework.
  @protected
  ModelInfo resolveLoadedModel(String modelId) {
    final matches = ModelListViewModel.shared.availableModels
        .where((m) => m.id == modelId);
    if (matches.isNotEmpty) return matches.first;
    return ModelInfo()..id = modelId;
  }

  /// Clear published state for an unloaded model.
  @protected
  void clearLoadedModel() {
    selectedModelId = null;
    selectedModelName = null;
    selectedFramework = null;
    notify();
  }

  // --- Cleanup ----------------------------------------------------------------

  /// Notify listeners unless the ViewModel was already disposed (async SDK
  /// callbacks can land after the screen is gone).
  @protected
  void notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Tear down subscriptions and reset the idempotency guards so the
  /// ViewModel can be re-initialized.
  @protected
  void cleanupBase() {
    unawaited(_lifecycleSubscription?.cancel());
    _lifecycleSubscription = null;
    _isInitialized = false;
    _hasSubscribedToSDKEvents = false;
  }

  @override
  void dispose() {
    _disposed = true;
    cleanupBase();
    super.dispose();
  }
}
