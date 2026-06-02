/**
 * @file platform_llm_callbacks_internal.h
 * @brief Internal helper around the Swift platform-LLM callback table.
 *
 * Provides a value-snapshot of the registered callbacks taken under the
 * registration lock so consumers do not dereference the global struct
 * after another thread may have written it (commons-032 — torn-read
 * TOCTOU between rac_platform_llm_set_callbacks and the public pointer
 * returned by rac_platform_llm_get_callbacks).
 *
 * Private to sdk/runanywhere-commons/src/features/platform/; intentionally
 * not exported on the commons ABI surface.
 */

#ifndef RAC_COMMONS_PLATFORM_LLM_CALLBACKS_INTERNAL_H
#define RAC_COMMONS_PLATFORM_LLM_CALLBACKS_INTERNAL_H

#include "rac/features/platform/rac_llm_platform.h"

namespace runanywhere::commons::platform_llm {

bool snapshot_callbacks(rac_platform_llm_callbacks_t* out);

}  // namespace runanywhere::commons::platform_llm

#endif  // RAC_COMMONS_PLATFORM_LLM_CALLBACKS_INTERNAL_H
