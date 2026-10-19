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
#include <vector>

#include "plugin/web_search_client.h"

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
 * @brief Build the evidence block the compose stage answers from.
 *
 * Exposed because this is the one place where "did the scrape actually reach
 * the model" is answerable: it uses each source's page text when the page was
 * read and falls back to the search snippet when it was not.
 */
std::string build_evidence(const std::vector<SearchResult>& sources);

/**
 * @brief Whether a model's reply is a search query rather than an answer.
 *
 * The failure that made this necessary: asked to write a query, a small model
 * answers the question instead, and the answer becomes the search string. A
 * real run searched for "Apple today's latest news is about the new iPhone 15
 * Pro Max with 4K Ultra HD display and 200W charging". Queries are short and
 * are not sentences; answers are long and are.
 */
bool looks_like_query_not_answer(const std::string& line);

/**
 * @brief The specific, checkable parts of a claim.
 *
 * Quoted phrases, numbers and mid-sentence proper nouns: the things a model
 * invents when it embellishes, and the things that must appear in a source if
 * the claim really came from one. Ordinary prose is not extracted, because
 * paraphrase is legitimate and unverifiable.
 */
std::vector<std::string> distinctive_terms(const std::string& sentence);

/** @brief Quoted phrases in a sentence, straight or single quoted. */
std::vector<std::string> quoted_spans(const std::string& sentence);

/**
 * @brief Whether a sentence's distinctive terms appear in the text it cites.
 *
 * True when the sentence makes no specific claim (nothing to verify) or when
 * at least one distinctive term is found. False only for a sentence that is
 * specific AND shares none of its specifics with its source — which is what a
 * fabricated detail looks like. A real run produced a HomePod "Ghost Touch"
 * interface cited to a page that never mentions it.
 */
bool claim_supported(const std::string& sentence, const std::string& source_text);

/**
 * @brief Drop sentences whose specifics are absent from the source they cite.
 *
 * Deterministic, and preferred over asking a model to check itself: the whole
 * problem is that the model is the thing that is wrong.
 */
std::string drop_unsupported_claims(const std::string& answer,
                                    const std::vector<SearchResult>& sources, size_t* out_dropped);

/**
 * @brief Whether an answer's [n] citations all resolve to a real source.
 *
 * The compose step is the last place a model can invent, and unlike the query
 * step its output IS checkable: an answer built from the sources cites them,
 * and an answer citing [5] when four were supplied was not built from them.
 * Cheap, deterministic, and no second model call — which is the whole point.
 *
 * @param source_count how many sources were supplied
 * @param out_cited    set to how many distinct valid citations were found
 */
bool citations_resolve(const std::string& answer, size_t source_count, size_t* out_cited);

/**
 * @brief Drop a reasoning block the model emitted despite thinking being off.
 *
 * An unterminated block means the whole reply is reasoning, so nothing is
 * taken from it rather than the narration becoming search queries.
 */
std::string strip_reasoning_block(const std::string& text);

}  // namespace rac::tools::web

#endif  // RAC_PLUGIN_WEB_RESEARCH_INTERNAL_H
