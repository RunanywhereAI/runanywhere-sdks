/**
 * @file web_search_client.cpp
 * @brief DuckDuckGo Lite fetch and scrape.
 */
#include "plugin/web_search_client.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

namespace rac::tools::web {

namespace {

constexpr const char* kTag = "WebSearch";
constexpr const char* kLiteUrl = "https://lite.duckduckgo.com/lite/?q=";
constexpr const char* kResultsUrl = "https://duckduckgo.com/?q=";

// DuckDuckGo serves a different, JS-only page to clients it does not
// recognize as a browser, so the scrape depends on this header being present.
constexpr const char* kUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0 Safari/537.36";

bool is_unreserved(unsigned char c) {
    return (std::isalnum(c) != 0) || c == '-' || c == '_' || c == '.' || c == '~';
}

int hex_value(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

std::string collapse_whitespace(const std::string& in) {
    std::string out;
    out.reserve(in.size());
    bool pending_space = false;
    for (const char c : in) {
        if (std::isspace(static_cast<unsigned char>(c)) != 0) {
            pending_space = !out.empty();
            continue;
        }
        if (pending_space) {
            out.push_back(' ');
            pending_space = false;
        }
        out.push_back(c);
    }
    return out;
}

// Case-insensitive find, because attribute and tag casing in scraped HTML is
// not something to rely on.
size_t ifind(const std::string& haystack, const std::string& needle, size_t from) {
    if (needle.empty() || from > haystack.size()) {
        return std::string::npos;
    }
    const auto it = std::search(haystack.begin() + static_cast<std::ptrdiff_t>(from),
                                haystack.end(), needle.begin(), needle.end(), [](char a, char b) {
                                    return std::tolower(static_cast<unsigned char>(a)) ==
                                           std::tolower(static_cast<unsigned char>(b));
                                });
    return it == haystack.end() ? std::string::npos : static_cast<size_t>(it - haystack.begin());
}

// Value of `attr="..."` (or single-quoted) within [from, limit).
std::string attribute_value(const std::string& html, size_t from, size_t limit,
                            const std::string& attr) {
    const size_t at = ifind(html, attr + "=", from);
    if (at == std::string::npos || at >= limit) {
        return {};
    }
    size_t value_start = at + attr.size() + 1;
    if (value_start >= limit) {
        return {};
    }
    const char quote = html[value_start];
    if (quote != '"' && quote != '\'') {
        return {};
    }
    ++value_start;
    const size_t value_end = html.find(quote, value_start);
    if (value_end == std::string::npos || value_end > limit) {
        return {};
    }
    return html.substr(value_start, value_end - value_start);
}

}  // namespace

std::string percent_encode(const std::string& raw) {
    static const char* kHex = "0123456789ABCDEF";
    std::string out;
    out.reserve(raw.size() * 3);
    for (const char c : raw) {
        const auto uc = static_cast<unsigned char>(c);
        if (is_unreserved(uc)) {
            out.push_back(c);
        } else {
            out.push_back('%');
            out.push_back(kHex[uc >> 4]);
            out.push_back(kHex[uc & 0x0F]);
        }
    }
    return out;
}

std::string percent_decode(const std::string& raw) {
    std::string out;
    out.reserve(raw.size());
    for (size_t i = 0; i < raw.size(); ++i) {
        if (raw[i] == '+') {
            out.push_back(' ');
            continue;
        }
        if (raw[i] != '%' || i + 2 >= raw.size()) {
            out.push_back(raw[i]);
            continue;
        }
        const int hi = hex_value(raw[i + 1]);
        const int lo = hex_value(raw[i + 2]);
        if (hi < 0 || lo < 0) {
            out.push_back(raw[i]);
            continue;
        }
        out.push_back(static_cast<char>((hi << 4) | lo));
        i += 2;
    }
    return out;
}

std::string decode_html_entities(const std::string& raw) {
    struct Entity {
        const char* from;
        const char* to;
    };
    static const Entity kEntities[] = {
        {"&amp;", "&"}, {"&quot;", "\""}, {"&#x27;", "'"}, {"&#39;", "'"},  {"&lt;", "<"},
        {"&gt;", ">"},  {"&nbsp;", " "},  {"&#x2F;", "/"}, {"&apos;", "'"},
    };
    std::string out = raw;
    for (const auto& entity : kEntities) {
        const std::string from = entity.from;
        size_t at = 0;
        while ((at = out.find(from, at)) != std::string::npos) {
            out.replace(at, from.size(), entity.to);
            at += std::strlen(entity.to);
        }
    }
    return out;
}

std::string strip_tags(const std::string& html) {
    std::string out;
    out.reserve(html.size());
    bool inside = false;
    for (const char c : html) {
        if (c == '<') {
            inside = true;
            out.push_back(' ');
            continue;
        }
        if (c == '>') {
            inside = false;
            continue;
        }
        if (!inside) {
            out.push_back(c);
        }
    }
    return collapse_whitespace(decode_html_entities(out));
}

std::string resolve_redirect(const std::string& href) {
    const size_t at = href.find("uddg=");
    if (at == std::string::npos) {
        // Protocol-relative hrefs are common in the Lite markup.
        return href.rfind("//", 0) == 0 ? "https:" + href : href;
    }
    const size_t value_start = at + 5;
    const size_t amp = href.find('&', value_start);
    const std::string encoded =
        href.substr(value_start, amp == std::string::npos ? std::string::npos : amp - value_start);
    return percent_decode(encoded);
}

std::vector<SearchResult> parse_lite_html(const std::string& html) {
    std::vector<SearchResult> results;

    // A hand-rolled scan rather than std::regex: the Swift original needs
    // lookahead to pair href with class on the same tag, and std::regex is
    // both slow and stack-hungry on a page-sized input.
    size_t cursor = 0;
    while (true) {
        const size_t marker = ifind(html, "result-link", cursor);
        if (marker == std::string::npos) {
            break;
        }
        const size_t tag_start = html.rfind('<', marker);
        const size_t tag_end = html.find('>', marker);
        if (tag_start == std::string::npos || tag_end == std::string::npos) {
            break;
        }

        const std::string href = attribute_value(html, tag_start, tag_end, "href");
        const size_t close = ifind(html, "</a>", tag_end);
        if (href.empty() || close == std::string::npos) {
            cursor = tag_end + 1;
            continue;
        }

        SearchResult entry;
        entry.url = resolve_redirect(decode_html_entities(href));
        entry.title = strip_tags(html.substr(tag_end + 1, close - tag_end - 1));

        // The snippet cell follows the link in the same row. Bound the search
        // so a missing snippet cannot borrow the next result's text.
        const size_t next_link = ifind(html, "result-link", close);
        const size_t snippet_at = ifind(html, "result-snippet", close);
        if (snippet_at != std::string::npos &&
            (next_link == std::string::npos || snippet_at < next_link)) {
            const size_t body_start = html.find('>', snippet_at);
            const size_t body_end = body_start == std::string::npos
                                        ? std::string::npos
                                        : ifind(html, "</td>", body_start);
            if (body_start != std::string::npos && body_end != std::string::npos) {
                entry.snippet = strip_tags(html.substr(body_start + 1, body_end - body_start - 1));
            }
        }
        if (entry.snippet.empty()) {
            entry.snippet = entry.title;
        }

        if (!entry.title.empty() && !entry.url.empty()) {
            results.push_back(std::move(entry));
        }
        cursor = close + 4;
    }

    return results;
}

std::string results_page_url(const std::string& query) {
    return std::string(kResultsUrl) + percent_encode(query);
}

SearchOutcome search(const std::string& query, size_t max_results, int32_t timeout_ms) {
    SearchOutcome outcome;
    if (query.empty()) {
        outcome.error = "empty query";
        return outcome;
    }
    if (rac_http_transport_is_registered() == RAC_FALSE) {
        // Commons never opens a socket itself; without a platform adapter
        // there is no network at all, and saying so beats a generic failure.
        outcome.error = "no HTTP transport registered";
        return outcome;
    }

    rac_http_client_t* client = nullptr;
    if (rac_http_client_create(&client) != RAC_SUCCESS || client == nullptr) {
        outcome.error = "could not create HTTP client";
        return outcome;
    }

    const std::string url = std::string(kLiteUrl) + percent_encode(query);
    const rac_http_header_kv_t headers[] = {{"User-Agent", kUserAgent}, {"Accept", "text/html"}};

    rac_http_request_t request{};
    request.method = "GET";
    request.url = url.c_str();
    request.headers = headers;
    request.header_count = 2;
    request.timeout_ms = timeout_ms;
    request.follow_redirects = RAC_TRUE;

    rac_http_response_t response{};
    const rac_result_t rc = rac_http_request_send(client, &request, &response);

    if (rc != RAC_SUCCESS) {
        outcome.error = rc == RAC_ERROR_TIMEOUT ? "search timed out" : "search request failed";
        rac_http_response_free(&response);
        rac_http_client_destroy(client);
        return outcome;
    }
    if (response.status < 200 || response.status >= 300) {
        char buffer[64];
        std::snprintf(buffer, sizeof(buffer), "search returned HTTP %d", response.status);
        outcome.error = buffer;
        rac_http_response_free(&response);
        rac_http_client_destroy(client);
        return outcome;
    }

    const std::string body(reinterpret_cast<const char*>(response.body_bytes), response.body_len);
    rac_http_response_free(&response);
    rac_http_client_destroy(client);

    outcome.results = parse_lite_html(body);
    if (outcome.results.size() > max_results) {
        outcome.results.resize(max_results);
    }
    outcome.ok = true;
    RAC_LOG_DEBUG(kTag, "query '%s' -> %zu result(s)", query.c_str(), outcome.results.size());
    return outcome;
}

}  // namespace rac::tools::web
