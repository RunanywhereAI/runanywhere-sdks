/**
 * @file web_research_internal.h
 * @brief Query-planning helpers shared with the web_research tests.
 *
 * Internal to the provider. Declared here rather than left in an anonymous
 * namespace so the filtering rules can be tested against the exact lines real
 * models have produced, which is the only way they stay correct.
 */
#ifndef RAC_PLUGIN_WEB_RESEARCH_INTERNAL_H
#define RAC_PLUGIN_WEB_RESEARCH_INTERNAL_H

#include <string>

namespace rac::tools::web {

/**
 * @brief Whether a line the model produced is actually a search query.
 *
 * Asking for "one query per line and nothing else" does not stop a reasoning
 * model prefacing the list with commentary, and every such line was being
 * searched verbatim — real runs searched "Thinking Process:" and
 * "**Analyze the Request:**", which is where the junk results came from.
 */
bool query_is_usable(const std::string& line);

/** @brief Strip list markers, quotes and bold markup from one listed line. */
std::string normalize_query_line(const std::string& line);

/**
 * @brief Drop a reasoning block the model emitted despite thinking being off.
 *
 * An unterminated block means the whole reply is reasoning, so nothing is
 * taken from it rather than the narration becoming search queries.
 */
std::string strip_reasoning_block(const std::string& text);

}  // namespace rac::tools::web

#endif  // RAC_PLUGIN_WEB_RESEARCH_INTERNAL_H
