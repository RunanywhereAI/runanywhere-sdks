/// RunAnywhere Flutter SDK - Core Package.
///
/// The generated protobuf modules are the canonical data-contract surface.
/// Hand-written exports below are limited to platform glue, capability facades,
/// and Dart helpers that expose real SDK behavior.
library;

export 'adapters/voice_agent_stream_adapter.dart' show VoiceAgentStreamAdapter;
export 'foundation/constants/sdk_constants.dart';
export 'foundation/errors/sdk_exception.dart';
export 'foundation/logging/sdk_logger.dart';
// Diffusion is intentionally NOT exported from the public barrel until the
// cross-SDK v2 contract for image generation lands (proto-backed lifecycle
// stream/cancel/capabilities ABIs across Swift/Kotlin/RN/Web). Removed under
// swift-parity-002-followup-flutter to keep the Swift-as-reference public
// surface coherent. The implementation in
// `public/capabilities/runanywhere_diffusion.dart` is retained for the day
// the contract is settled.
export 'public/capabilities/runanywhere_downloads.dart'
    show RunAnywhereDownloads;
export 'public/capabilities/runanywhere_embeddings.dart'
    show RunAnywhereEmbeddings;
export 'public/capabilities/runanywhere_hybrid.dart' show RunAnywhereHybrid;
export 'public/capabilities/runanywhere_llm.dart' show RunAnywhereLLM;
export 'public/capabilities/runanywhere_lora.dart'
    show RunAnywhereLoRACapability;
export 'public/capabilities/runanywhere_model_lifecycle.dart'
    show RunAnywhereModelLifecycle;
export 'public/capabilities/runanywhere_models.dart' show RunAnywhereModels;
export 'public/capabilities/runanywhere_plugin_loader.dart'
    show PluginInfo, RunAnywherePluginLoaderCapability;
export 'public/capabilities/runanywhere_rag.dart' show RunAnywhereRAG;
export 'public/capabilities/runanywhere_solutions.dart'
    show RunAnywhereSolutions;
export 'public/capabilities/runanywhere_stt.dart' show RunAnywhereSTT;
export 'public/capabilities/runanywhere_tools.dart'
    show RunAnywhereTools, ToolExecutor;
export 'public/capabilities/runanywhere_tts.dart' show RunAnywhereTTS;
export 'public/capabilities/runanywhere_vad.dart' show RunAnywhereVAD;
export 'public/capabilities/runanywhere_vlm.dart' show RunAnywhereVLM;
export 'public/capabilities/runanywhere_voice.dart' show RunAnywhereVoice;
export 'public/configuration/sdk_environment.dart';
export 'public/events/event_bus.dart' show EventBus;
export 'public/extensions/format_framework.dart' show formatFramework;
export 'public/extensions/model_category_extensions.dart'
    show ModelCategoryDefaults;
export 'public/extensions/rag_module.dart';
export 'public/extensions/runanywhere_logging.dart';
export 'public/extensions/runanywhere_storage.dart';
export 'public/extensions/runanywhere_structured_output.dart'
    show RunAnywhereStructuredOutput;
export 'public/extensions/stt/stt_options_helpers.dart';
// Hybrid STT router public types (model/backend identity, routing policy,
// cloud-backend registry, device-state provider, router + result). The
// capability facade is `RunAnywhere.hybrid`. The friendly policy type names
// (HybridFilter/HybridCascade/HybridRoutingPolicy) shadow the same-named raw
// proto messages in the unprefixed barrel — those proto messages stay reachable
// via `import '.../runanywhere_protos.dart' as ra_proto` (see the hide on the
// runanywhere_protos export below).
export 'public/hybrid/hybrid_cloud_backend.dart'
    show CloudBackend, cloudSttConfigJson;
export 'public/hybrid/hybrid_device_state.dart'
    show HybridDeviceState, HybridDeviceStateProvider;
export 'public/hybrid/hybrid_model.dart'
    show
        HybridBackend,
        HybridModel,
        HybridModelKind,
        kHybridDefaultCloudProvider;
export 'public/hybrid/hybrid_routing_policy.dart'
    show
        HybridBatteryFilter,
        HybridCascade,
        HybridConfidenceCascade,
        HybridCustomFilter,
        HybridFilter,
        HybridNetworkFilter,
        HybridQualityFilter,
        HybridRankOrder,
        HybridRoutingPolicy,
        kHybridSttConfidenceThreshold;
export 'public/hybrid/hybrid_stt_router.dart'
    show HybridSttRouter, HybridTranscribeException;
export 'public/runanywhere.dart' show RunAnywhere;
export 'public/system_tts.dart' show SystemTTS;
// Hide the hybrid proto messages whose names the friendly public hybrid policy
// types above re-use (the sealed-class HybridFilter/HybridCascade facades that
// carry host-side closures), so the unprefixed barrel resolves them to the
// public types. The raw messages remain available via the prefixed
// `runanywhere_protos.dart` import. `HybridRoutedMetadata`,
// `HybridSttTranscribeOptions`, and `HybridSttTranscribeResponse` are NOT
// hidden — they are now the canonical generated transcribe types exposed
// directly by [HybridSttRouter.transcribe].
export 'runanywhere_protos.dart'
    hide HybridCascade, HybridFilter, HybridRoutingPolicy;
