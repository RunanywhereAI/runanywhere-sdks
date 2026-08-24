/**
 * @file rac_web_research.h
 * @brief Multi-step web research, registered as a commons tool provider.
 *
 * Where `search_web` was one query and one payload, this plans its own
 * sub-questions, searches each, reads what came back, and composes an answer
 * from it, reporting each stage through `rac_tool_context_t` as it goes.
 *
 * Registration is explicit rather than automatic at init, matching
 * `rac_backend_*_register()`. A tool that reaches the network should be
 * something an app turns on, not something it inherits.
 */
#ifndef RAC_PLUGIN_WEB_RESEARCH_H
#define RAC_PLUGIN_WEB_RESEARCH_H

#include "rac/core/rac_error.h"

// NOLINTBEGIN(modernize-redundant-void-arg)
#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register the `web_research` tool.
 *
 * Needs a platform HTTP transport (`rac_http_transport_register`) and a
 * loaded LLM by the time the tool is called, not at registration.
 */
RAC_API rac_result_t rac_tool_web_research_register(void);

/** @brief Remove it again. */
RAC_API rac_result_t rac_tool_web_research_unregister(void);

#ifdef __cplusplus
}  // extern "C"
#endif
// NOLINTEND(modernize-redundant-void-arg)

#endif  // RAC_PLUGIN_WEB_RESEARCH_H
