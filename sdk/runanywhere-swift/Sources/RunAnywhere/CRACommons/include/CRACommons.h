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

#include "rac_types.h"
#include "rac_error.h"
#include "rac_structured_error.h"
#include "rac_logger.h"
#include "rac_core.h"
#include "rac_platform_adapter.h"
#include "rac_component_types.h"
#include "rac_audio_utils.h"

// Lifecycle management
#include "rac_lifecycle.h"

// SDK State (centralized state management)
#include "rac_sdk_state.h"

// =============================================================================
// FEATURES - LLM, STT, TTS, VAD, VLM, Diffusion, Voice Agent
// =============================================================================

// LLM (Large Language Model)
#include "rac_llm.h"
#include "rac_llm_types.h"
#include "rac_llm_service.h"
#include "rac_llm_component.h"
#include "rac_llm_metrics.h"
#include "rac_llm_analytics.h"
#include "rac_llm_events.h"
#include "rac_llm_structured_output.h"
#include "rac_routing.h"
#include "rac_tool_calling.h"

// STT (Speech-to-Text)
#include "rac_stt.h"
#include "rac_stt_types.h"
#include "rac_stt_service.h"
#include "rac_stt_component.h"
#include "rac_stt_analytics.h"
#include "rac_stt_events.h"

// TTS (Text-to-Speech)
#include "rac_tts.h"
#include "rac_tts_types.h"
#include "rac_tts_service.h"
#include "rac_tts_component.h"
#include "rac_tts_analytics.h"
#include "rac_tts_events.h"

// VAD (Voice Activity Detection)
#include "rac_vad.h"
#include "rac_vad_types.h"
#include "rac_vad_service.h"
#include "rac_vad_component.h"
#include "rac_vad_energy.h"
#include "rac_vad_analytics.h"
#include "rac_vad_events.h"

// VLM (Vision Language Model)
#include "rac_vlm.h"
#include "rac_vlm_types.h"
#include "rac_vlm_service.h"
#include "rac_vlm_component.h"
#include "rac_vlm_llamacpp.h"

// Diffusion (Image Generation)
#include "rac_diffusion.h"
#include "rac_diffusion_types.h"
#include "rac_diffusion_tokenizer.h"
#include "rac_diffusion_service.h"
#include "rac_diffusion_component.h"
#include "rac_diffusion_model_registry.h"

// Voice Agent
#include "rac_voice_agent.h"

// =============================================================================
// INFRASTRUCTURE - Events, Download, Model Management
// =============================================================================

// Event system
#include "rac_events.h"
#include "rac_analytics_events.h"

// Download management
#include "rac_download.h"

// Model management
#include "rac_model_types.h"
#include "rac_model_registry.h"
#include "rac_model_paths.h"
#include "rac_model_strategy.h"
#include "rac_model_assignment.h"

// Storage
#include "rac_storage_analyzer.h"

// Device
#include "rac_device_manager.h"

// =============================================================================
// PLATFORM BACKEND - Apple Foundation Models, System TTS, CoreML Diffusion
// =============================================================================

#include "rac_llm_platform.h"
#include "rac_tts_platform.h"
#include "rac_diffusion_platform.h"

// =============================================================================
// ONNX/WHISPERCPP BACKENDS - STT
// =============================================================================

#include "rac_stt_whispercpp.h"

// =============================================================================
// NETWORK - Environment, Auth, API Types, Dev Config
// =============================================================================

#include "rac_environment.h"
#include "rac_endpoints.h"
#include "rac_api_types.h"
#include "rac_http_client.h"
#include "rac_auth_manager.h"
#include "rac_dev_config.h"

// =============================================================================
// TELEMETRY - Event payloads, batching, manager
// =============================================================================

#include "rac_telemetry_types.h"
#include "rac_telemetry_manager.h"

#endif /* CRACOMMONS_H */
