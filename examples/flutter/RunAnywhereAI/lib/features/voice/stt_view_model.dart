import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/voice/voice_component_view_model_base.dart';

/// STTMode enumeration (matching iOS STTMode in STTViewModel.swift).
enum STTMode {
  batch,
  live,
  hybrid;

  String get displayName {
    switch (this) {
      case STTMode.batch:
        return 'Batch';
      case STTMode.live:
        return 'Live';
      case STTMode.hybrid:
        return 'Hybrid';
    }
  }

  String get description {
    switch (this) {
      case STTMode.batch:
        return 'Record first, then transcribe all at once';
      case STTMode.live:
        return 'Stream with live partial results';
      case STTMode.hybrid:
        return 'On-device first with cloud fallback';
    }
  }

  IconData get icon {
    switch (this) {
      case STTMode.batch:
        return Icons.mic;
      case STTMode.live:
        return Icons.stream;
      case STTMode.hybrid:
        return Icons.cloud;
    }
  }
}

/// ViewModel for the Speech-to-Text view (mirrors iOS `STTViewModel.swift`).
///
/// Owns recording, batch/live/hybrid transcription, hybrid cloud routing
/// config + router cache, and model selection state. The view only renders
/// state and forwards user intent.
class STTViewModel extends VoiceComponentViewModelBase {
  STTViewModel();

  // SDK-owned microphone capture (mirrors Swift AudioCaptureManager).
  final sdk.AudioCaptureManager _capture = sdk.AudioCaptureManager();
  StreamSubscription<double>? _audioLevelSubscription;

  // Live mode: mic chunks are fed straight into the SDK's streaming
  // transcription session (RunAnywhere.transcribeStream), which owns
  // endpointing/segmentation natively. No app-side silence detection.
  StreamSubscription<sdk.STTPartialResult>? _liveSubscription;
  String _committedTranscription = '';

  // Hybrid mode: router cached on the config tuple (mirrors iOS
  // `ensureHybridRouter`).
  sdk.HybridSttRouter? _hybridRouter;
  String? _hybridPairKey;

  // --- Component identity -----------------------------------------------------

  @override
  sdk.SDKComponent get component => sdk.SDKComponent.SDK_COMPONENT_STT;

  @override
  sdk.EventCategory get eventCategory => sdk.EventCategory.EVENT_CATEGORY_STT;

  @override
  ModelCategory get modelCategory =>
      ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;

  // --- UI state ----------------------------------------------------------------

  /// Committed transcription text shown in the main text area.
  String transcription = '';

  /// In-progress (non-final) live partial preview.
  String partialText = '';

  bool isRecording = false;
  bool isProcessing = false;
  bool isTranscribing = false;
  double audioLevel = 0.0;

  /// Sherpa-ONNX supports streaming transcription via its zipformer/RNN-T
  /// runtime. Allow Live mode for Sherpa-/ONNX-backed STT models.
  bool supportsLiveMode = true;

  // --- Hybrid cloud configuration (mirrors iOS STTViewModel) -------------------

  String cloudProviderId = 'flutter-demo-cloud-stt';
  String cloudProvider = sdk.CloudBackend.defaultProvider;
  String cloudModel = 'saarika:v2.5';
  String cloudApiKey = '';
  String cloudLanguageCode = 'en-IN';

  bool _hybridPreferOnline = false;
  bool get hybridPreferOnline => _hybridPreferOnline;
  set hybridPreferOnline(bool value) {
    _hybridPreferOnline = value;
    notify();
  }

  bool _hybridRequireNetwork = true;
  bool get hybridRequireNetwork => _hybridRequireNetwork;
  set hybridRequireNetwork(bool value) {
    _hybridRequireNetwork = value;
    notify();
  }

  /// Minimum battery percent for the cloud candidate (hard filter). Not
  /// surfaced in the UI (iOS parity) but always applied to the policy.
  double hybridMinBattery = 20;

  double _hybridConfidenceThreshold = sdk.kHybridSttConfidenceThreshold;
  double get hybridConfidenceThreshold => _hybridConfidenceThreshold;
  set hybridConfidenceThreshold(double value) {
    _hybridConfidenceThreshold = value;
    notify();
  }

  /// Routing decision of the last hybrid transcription, for display.
  sdk.HybridRoutedMetadata? hybridRouting;

  // --- Mode selection -----------------------------------------------------------

  STTMode _selectedMode = STTMode.batch;
  STTMode get selectedMode => _selectedMode;
  set selectedMode(STTMode mode) {
    if (_selectedMode == mode) return;
    final oldMode = _selectedMode;
    _selectedMode = mode;
    // Stop any active recording/transcription when mode changes (iOS parity).
    if (isRecording) {
      debugPrint('Mode changed from ${oldMode.name} to ${mode.name} - '
          'stopping active recording');
      unawaited(stopRecording());
    }
    if (oldMode == STTMode.live) {
      _stopLiveTranscription();
    }
    notify();
  }

  // --- Initialization -------------------------------------------------------------

  /// Initialize the ViewModel — idempotent. Microphone permission is requested
  /// by the view (the app's PermissionService needs a BuildContext).
  Future<void> initialize() async {
    if (!beginInitialization()) return;

    debugPrint('Initializing STT view model');
    subscribeToSDKEvents();
    await checkInitialModelState();
  }

  /// Load model from the model selection sheet.
  Future<void> loadModelFromSelection(ModelInfo model) async {
    isProcessing = true;
    notify();
    await loadModel(model);
    isProcessing = false;
    notify();
  }

  @override
  Future<void> performLoad(ModelInfo model) =>
      sdk.RunAnywhere.stt.load(model.id);

  /// STT resolves the display name from the model catalog when available,
  /// falling back to the model's own metadata (mirrors iOS).
  @override
  void applyLoadedModel(ModelInfo model) {
    applyLoadedModelFromCatalog(model);
    supportsLiveMode = selectedFramework ==
            LLMFramework.INFERENCE_FRAMEWORK_UNKNOWN ||
        selectedFramework == LLMFramework.INFERENCE_FRAMEWORK_ONNX;
    notify();
  }

  // --- Recording -------------------------------------------------------------------

  /// Toggle recording state (start/stop).
  Future<void> toggleRecording() async {
    if (isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    debugPrint('Starting recording in ${_selectedMode.name} mode');
    errorMessage = null;
    hybridRouting = null;
    transcription = '';
    partialText = '';
    _committedTranscription = '';

    if (selectedModelId == null) {
      errorMessage = 'No STT model loaded';
      notify();
      return;
    }

    // iOS parity: hybrid mode requires a configured cloud API key.
    if (_selectedMode == STTMode.hybrid && !isHybridCloudConfigValid) {
      errorMessage = 'Enter a cloud STT API key before using Hybrid mode';
      notify();
      return;
    }

    if (_selectedMode == STTMode.live) {
      await _startLiveStreaming();
      return;
    }

    // Batch/hybrid: record to a buffer, transcribe once on stop.
    final recordingPath = await _capture.startRecordingToBuffer(
      sampleRate: 16000,
      numChannels: 1,
    );
    if (recordingPath == null) {
      errorMessage = 'Failed to start recording';
      notify();
      return;
    }

    _subscribeToAudioLevels();
    isRecording = true;
    notify();
    debugPrint('Recording started in ${_selectedMode.name} mode');
  }

  Future<void> stopRecording() async {
    debugPrint('Stopping recording');

    await _audioLevelSubscription?.cancel();
    _audioLevelSubscription = null;
    isRecording = false;
    audioLevel = 0.0;

    if (_selectedMode == STTMode.live) {
      // Closing the recorder ends the chunk stream, which lets the native
      // session flush its final result; the live subscription ends with it.
      isTranscribing = true;
      notify();
      await _capture.stopRecording();
      return;
    }
    notify();

    final audioData = await _capture.stopRecording();
    if (audioData == null || audioData.isEmpty) {
      errorMessage = 'No audio data recorded';
      notify();
      return;
    }

    if (_selectedMode == STTMode.hybrid) {
      await _performHybridTranscription(audioData);
    } else {
      await _performBatchTranscription(audioData);
    }
  }

  // --- Transcription ------------------------------------------------------------------

  /// Perform batch transcription on collected audio.
  Future<void> _performBatchTranscription(Uint8List audioData) async {
    debugPrint('Starting batch transcription of ${audioData.length} bytes');
    isTranscribing = true;
    errorMessage = null;
    notify();

    try {
      if (!sdk.RunAnywhere.stt.isLoaded) {
        throw StateError(
            'STT component not loaded. Please load an STT model first.');
      }
      final result = await sdk.RunAnywhere.stt.transcribe(audioData);
      transcription = result.text;
      debugPrint('Batch transcription complete: ${result.text.length} chars');
    } catch (e) {
      debugPrint('Batch transcription failed: $e');
      errorMessage = 'Transcription failed: $e';
    }

    isTranscribing = false;
    notify();
  }

  /// Perform one request through the SDK hybrid STT router
  /// (mirrors iOS `performHybridTranscription`).
  Future<void> _performHybridTranscription(Uint8List audioBytes) async {
    final offlineModelId = selectedModelId;
    if (offlineModelId == null) {
      errorMessage = 'No STT model loaded';
      notify();
      return;
    }

    debugPrint('Starting hybrid transcription of ${audioBytes.length} bytes');
    isTranscribing = true;
    errorMessage = null;
    hybridRouting = null;
    notify();

    try {
      final onlineModelId = _registerCloudProvider();
      final router = _ensureHybridRouter(
        offlineModelId: offlineModelId,
        onlineModelId: onlineModelId,
      );
      // Buffered recordings are WAV-encoded at 16 kHz (AudioCaptureManager).
      // audio_format wire values match rac_audio_format_enum_t (1 = WAV).
      final response = router.transcribe(
        audioBytes,
        options: sdk.HybridSttTranscribeOptions(
          sampleRate: 16000,
          audioFormat: 1,
        ),
      );
      transcription = response.text;
      hybridRouting = response.routing;
      debugPrint('Hybrid transcription complete: ${response.text}');
    } catch (e) {
      debugPrint('Hybrid transcription failed: $e');
      errorMessage = 'Hybrid transcription failed: $e';
    }

    isTranscribing = false;
    notify();
  }

  /// Whether the cloud config is complete enough to attempt hybrid routing.
  bool get isHybridCloudConfigValid =>
      cloudProviderId.trim().isNotEmpty &&
      cloudProvider.trim().isNotEmpty &&
      cloudModel.trim().isNotEmpty &&
      cloudApiKey.trim().isNotEmpty;

  /// Register the cloud plugin + provider credentials and return the cloud
  /// registry id the router resolves the online side by.
  String _registerCloudProvider() {
    final id = cloudProviderId.trim();
    final provider = cloudProvider.trim();
    final model = cloudModel.trim();
    final apiKey = cloudApiKey.trim();
    final language = cloudLanguageCode.trim();

    if (id.isEmpty || provider.isEmpty || model.isEmpty || apiKey.isEmpty) {
      throw StateError(
          'Cloud provider id, provider, model, and API key are required');
    }

    sdk.RunAnywhere.hybrid.registerCloud();
    sdk.RunAnywhere.hybrid.cloud.register(
      id: id,
      provider: provider,
      model: model,
      apiKey: apiKey,
      languageCode: language.isEmpty ? null : language,
    );
    return id;
  }

  /// Reuse the cached router when the config tuple is unchanged; otherwise
  /// close the old one and build a fresh pairing (mirrors iOS).
  sdk.HybridSttRouter _ensureHybridRouter({
    required String offlineModelId,
    required String onlineModelId,
  }) {
    final key = [
      offlineModelId,
      onlineModelId,
      cloudProvider.trim(),
      '$_hybridPreferOnline',
      '$_hybridRequireNetwork',
      '${hybridMinBattery.round()}',
      '$_hybridConfidenceThreshold',
    ].join('|');

    final cached = _hybridRouter;
    if (cached != null && _hybridPairKey == key) {
      return cached;
    }

    _hybridRouter?.close();
    _hybridRouter = null;
    _hybridPairKey = null;

    final router = sdk.RunAnywhere.hybrid.createSttRouter();
    final filters = <sdk.HybridFilter>[
      if (_hybridRequireNetwork) const sdk.HybridFilter.network(),
      sdk.HybridFilter.battery(minPercent: hybridMinBattery.round()),
    ];
    router.setPair(
      offline: sdk.HybridModel.offlineSherpa(offlineModelId),
      online: sdk.HybridModel.onlineCloud(
        onlineModelId,
        provider: cloudProvider.trim(),
      ),
      policy: sdk.HybridRoutingPolicy(
        hardFilters: filters,
        cascade: sdk.HybridCascade.confidence(_hybridConfidenceThreshold),
        rank: _hybridPreferOnline
            ? sdk.HybridRankOrder.preferOnlineFirst
            : sdk.HybridRankOrder.preferLocalFirst,
      ),
    );
    _hybridRouter = router;
    _hybridPairKey = key;
    return router;
  }

  // --- Live streaming ---------------------------------------------------------------

  /// Live mode: feed mic chunks into the SDK's streaming transcription
  /// session. Non-final partials preview the current utterance; finals
  /// commit it as a line (mirrors iOS `handleLivePartial`).
  Future<void> _startLiveStreaming() async {
    final chunks = await _capture.startRecording(
      sampleRate: 16000,
      numChannels: 1,
    );
    if (chunks == null) {
      errorMessage = 'Failed to start streaming recording';
      notify();
      return;
    }

    _subscribeToAudioLevels();

    _liveSubscription = sdk.RunAnywhere.transcribeStream(chunks).listen(
      (partial) {
        final text = partial.text.trim();
        if (partial.isFinal) {
          // Stream errors surface as a terminal partial carrying the
          // failure text (see RunAnywhere.transcribeStream).
          if (text.startsWith('STT stream failed')) {
            errorMessage = text;
            notify();
            return;
          }
          if (text.isNotEmpty) {
            _committedTranscription = _committedTranscription.isEmpty
                ? text
                : '$_committedTranscription\n$text';
          }
          transcription = _committedTranscription;
          partialText = '';
        } else if (text.isNotEmpty) {
          partialText = text;
        }
        notify();
      },
      onError: (Object e) {
        errorMessage = 'Transcription failed: $e';
        notify();
      },
      onDone: () {
        _liveSubscription = null;
        isTranscribing = false;
        notify();
      },
    );

    isRecording = true;
    notify();
    debugPrint('Live streaming transcription started');
  }

  void _subscribeToAudioLevels() {
    _audioLevelSubscription = _capture.audioLevelStream?.listen((level) {
      audioLevel = level;
      notify();
    });
  }

  /// Stop live transcription resources (called when mode changes).
  void _stopLiveTranscription() {
    unawaited(_liveSubscription?.cancel());
    _liveSubscription = null;
  }

  // --- Transcript actions --------------------------------------------------------------

  void clearTranscription() {
    transcription = '';
    partialText = '';
    hybridRouting = null;
    notify();
  }

  // --- Cleanup ---------------------------------------------------------------------------

  @override
  void dispose() {
    _stopLiveTranscription();
    unawaited(_audioLevelSubscription?.cancel());
    _audioLevelSubscription = null;
    unawaited(_capture.dispose());
    _hybridRouter?.close();
    _hybridRouter = null;
    _hybridPairKey = null;
    super.dispose();
  }
}
