/**
 * @file web_search_client.h
 * @brief DuckDuckGo search, fetched through the platform HTTP transport.
 *
 * Ported from the Swift, Kotlin and Web copies of `search_web`, which each
 * reimplemented the same fetch, the same HTML shape and the same fallback.
 * Parsing is separated from fetching so the scraper can be tested against
 * fixtures without a network or a registered transport.
 */
#ifndef RAC_PLUGIN_WEB_SEARCH_CLIENT_H
#define RAC_PLUGIN_WEB_SEARCH_CLIENT_H

#include <cstdint>
#include <string>
#include <vector>

namespace rac::tools::web {

struct SearchResult {
    std::string title;
    std::string url;
    std::string snippet;
    /// Readable page text, once the source has been fetched. Empty until then.
    std::string body;
};

struct SearchOutcome {
    bool ok = false;
    std::string error;  // set when ok is false
    std::vector<SearchResult> results;
};

/**
 * @brief Run one query against DuckDuckGo Lite.
 *
 * Returns ok=false with `error` set when no HTTP transport is registered,
 * the request fails, or the response is not 2xx. An empty result list with
 * ok=true means the query genuinely matched nothing.
 */
SearchOutcome search(const std::string& query, size_t max_results, int32_t timeout_ms);

/** @brief The `lite.duckduckgo.com` results page for `query`, for citation. */
std::string results_page_url(const std::string& query);

/**
 * @brief Fetch `url` and return its readable text.
 *
 * A search snippet is one or two sentences, which is enough to rank a result
 * and not enough to answer from. This reads the page behind the link so the
 * model has the actual material.
 *
 * Returns an empty string when the fetch fails, the response is not HTML, or
 * the page yields nothing readable — a source that cannot be read is skipped,
 * never fatal. `max_bytes` caps what is pulled off the wire, since research
 * runs on phones and some pages are enormous.
 */
std::string fetch_page_text(const std::string& url, size_t max_bytes, int32_t timeout_ms);

/**
 * @brief Strip script and style *bodies* before their tags are removed.
 *
 * `strip_tags` alone deletes `<script>` and keeps everything between it and
 * `</script>`, which turns a modern page into a wall of JavaScript. Exposed
 * for tests.
 */
std::string strip_non_content_elements(const std::string& html);

// Exposed for tests.
std::vector<SearchResult> parse_lite_html(const std::string& html);
std::string percent_encode(const std::string& raw);
std::string percent_decode(const std::string& raw);
std::string decode_html_entities(const std::string& raw);
std::string strip_tags(const std::string& html);

/**
 * @brief Resolve a DuckDuckGo redirect href to the destination it wraps.
 *
 * Lite results link through `/l/?uddg=<percent-encoded target>`; the target
 * is what a citation should show.
 */
std::string resolve_redirect(const std::string& href);

}  // namespace rac::tools::web

#endif  // RAC_PLUGIN_WEB_SEARCH_CLIENT_H
