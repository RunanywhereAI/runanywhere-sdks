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
// CORE - Types, Error, Platform
// =============================================================================

#include "rac_types.h"
#include "rac_error.h"
#include "rac_core.h"
#include "rac_platform_adapter.h"
#include "rac_component_types.h"

// Lifecycle management
#include "rac_lifecycle.h"

// =============================================================================
// FEATURES - LLM, STT, TTS, VAD, Voice Agent
// =============================================================================

// LLM (Large Language Model)
#include "rac_llm.h"
#include "rac_llm_types.h"
#include "rac_llm_service.h"
#include "rac_llm_component.h"
#include "rac_llm_metrics.h"

// STT (Speech-to-Text)
#include "rac_stt.h"
#include "rac_stt_types.h"
#include "rac_stt_service.h"
#include "rac_stt_component.h"

// TTS (Text-to-Speech)
#include "rac_tts.h"
#include "rac_tts_types.h"
#include "rac_tts_service.h"
#include "rac_tts_component.h"

// VAD (Voice Activity Detection)
#include "rac_vad.h"
#include "rac_vad_types.h"
#include "rac_vad_service.h"
#include "rac_vad_component.h"
#include "rac_vad_energy.h"

// Voice Agent
#include "rac_voice_agent.h"

// =============================================================================
// INFRASTRUCTURE - Events, Download, Model Management
// =============================================================================

// Event system
#include "rac_events.h"

// Download management
#include "rac_download.h"

// Model management
#include "rac_model_types.h"
#include "rac_model_paths.h"
#include "rac_model_registry.h"

#endif /* CRACOMMONS_H */
