/**
 * @file CRACommons.h
 * @brief Umbrella header for CRACommons Swift bridge module
 *
 * This header exposes the runanywhere-commons C API to Swift.
 * Import this module in Swift files that need direct C interop.
 *
 * Note: Headers are included using local includes for SPM compatibility.
 */

#ifndef CRACOMMONS_H
#define CRACOMMONS_H

// =============================================================================
// CORE - Types, Error, Logging, Platform, State
// =============================================================================

#include "rac_audio_utils.h"
#include "rac/core/rac_benchmark.h"
#include "rac_component_types.h"
#include "rac_core.h"
#include "rac_error.h"
#include "rac_error_proto.h" // rac_result_to_proto_error
#include "rac_logger.h"
#include "rac_platform_adapter.h"
#include "rac_proto_buffer.h"
#include "rac_structured_error.h"
#include "rac_types.h"

// Lifecycle management
#include "rac_lifecycle.h"
#include "rac_model_lifecycle.h"
#include "rac_sdk_init.h" // rac_sdk_init_phase{1,2}_proto + retry_http_proto

// SDK State (centralized state management)
#include "rac_sdk_state.h"

// =============================================================================
// FEATURES - LLM, STT, TTS, VAD, VLM, Diffusion, Voice Agent
// =============================================================================

// LLM (Large Language Model)
#include "rac_llm.h"
#include "rac_llm_analytics.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac_llm_metrics.h"
#include "rac_llm_schema_to_json.h" // rac_structured_output_schema_to_json_proto
#include "rac/features/llm/rac_llm_service.h"
#include "rac_llm_structured_output.h"
#include "rac/features/llm/rac_llm_types.h"
// proto-byte LLM stream ABI.
#include "rac_llm_stream.h"
#include "rac_tool_calling.h"

// STT (Speech-to-Text)
#include "rac_stt.h"
#include "rac_stt_analytics.h"
#include "rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac_stt_stream.h"
#include "rac_stt_types.h"

// TTS (Text-to-Speech)
#include "rac_tts.h"
#include "rac_tts_analytics.h"
#include "rac_tts_component.h"
#include "rac_tts_service.h"
#include "rac_tts_stream.h"
#include "rac_tts_types.h"

// VAD (Voice Activity Detection)
#include "rac_vad.h"
#include "rac_vad_analytics.h"
#include "rac_vad_component.h"
#include "rac_vad_energy.h"
#include "rac_vad_service.h"
#include "rac_vad_types.h"

// VLM (Vision Language Model)
#include "rac_vlm.h"
#include "rac_vlm_component.h"
#include "rac_vlm_llamacpp.h"
#include "rac_vlm_service.h"
#include "rac_vlm_types.h"

// CUA (Computer-Use-Agent scaffold)
#include "rac_cua.h"

// Diffusion (Image Generation)
#include "rac_diffusion.h"
#include "rac_diffusion_model_registry.h"
#include "rac_diffusion_service.h"
#include "rac_diffusion_tokenizer.h"
#include "rac_diffusion_types.h"

// Voice Agent
#include "rac_modality_proto_abi.h"
#include "rac_voice_agent.h"
#include "rac_voice_event_abi.h"

// Embeddings
#include "rac_embeddings.h"

// RAG (Retrieval-Augmented Generation)
#include "rac_rag.h"

// Solutions — proto/YAML driven L5 solution runtime
#include "rac_solution.h"

// =============================================================================
// INFRASTRUCTURE - Events, Download, Model Management
// =============================================================================

// Event system
#include "rac_sdk_event_stream.h"

// Download management
#include "rac_download_orchestrator.h"

// Model management
#include "rac_lora_registry.h"
#include "rac_model_assignment.h"
#include "rac_model_format_ids.h"
#include "rac_model_paths.h"
#include "rac_model_registry.h"
#include "rac_model_types.h"

// Storage
#include "rac_storage_analyzer.h"

// File Management
#include "rac_file_manager.h"

// Device
#include "rac_device_identity.h" // rac_device_get_or_create_persistent_id
#include "rac_device_manager.h"

// =============================================================================
// PLATFORM BACKEND - Apple Foundation Models, System TTS, CoreML Diffusion
// =============================================================================

#include "rac_diffusion_platform.h"
#include "rac_llm_platform.h"
#include "rac_tts_platform.h"

// =============================================================================
// NETWORK - Environment, Auth, API Types, Dev Config
// =============================================================================

#include "rac_api_types.h"
#include "rac_auth_manager.h"
#include "rac_client_info.h"
#include "rac_dev_config.h"
#include "rac_endpoints.h"
#include "rac_environment.h"
#include "rac_http_client.h"
#include "rac_http_download.h"
#include "rac_http_transport.h"

// =============================================================================
// TELEMETRY - Event payloads, batching, manager
// =============================================================================

#include "rac_telemetry_manager.h"
#include "rac_telemetry_types.h"

// =============================================================================
// PLUGIN REGISTRY + ROUTER (replaces rac_service_* legacy)
// =============================================================================

#include "rac_cpu_runtime_provider.h"
#include "rac_engine_vtable.h"
#include "rac_plugin_entry.h"
#include "rac_plugin_entry_platform.h" // platform plugin (Apple FM / System TTS / CoreML Diffusion)
#include "rac_plugin_loader.h" // runtime dlopen path
#include "rac_primitive.h"
#include "rac_runtime_registry.h" // explicit-module mode requirement
#include "rac_runtime_vtable.h"

// =============================================================================
// HYBRID ROUTER (cross-SDK STT offline ↔ online dispatch)
//
// Capability-agnostic filter/cascade/rank types + the STT hybrid router and
// its proto-byte ABI, plus the host device-state vtable and the named
// custom-filter callback table. All routing/cascade LOGIC lives in commons
// (src/routing/*.cpp, part of rac_commons core → RACommons.xcframework); the
// Swift binding (Sources/RunAnywhere/Hybrid/) only marshals the policy proto,
// installs callbacks, and calls the router.
// =============================================================================

#include "rac_cloud_stt_provider.h"
#include "rac_hybrid_custom_filter.h"
#include "rac_hybrid_device_state.h"
#include "rac_hybrid_types.h"
#include "rac_stt_hybrid_router.h"
#include "rac_stt_hybrid_router_proto.h"

// cloud engine registration (online side of the STT hybrid pair). Declares
// only rac_backend_cloud_register/_unregister so Cloud.register() can
// fold the plugin in, mirroring ONNX.register() for sherpa. The concrete HTTP
// provider (e.g. "sarvam") is chosen via the create config, not a distinct
// plugin.
#include "rac_plugin_entry_cloud.h"

#endif /* CRACOMMONS_H */
