/**
 * @file test_web_research.cpp
 * @brief The web_research provider: scraping, encoding, and graceful failure.
 *
 * The scrape is the part worth pinning down, because it is the part that
 * breaks silently when DuckDuckGo changes its markup. Everything here runs
 * without a network or a registered HTTP transport.
 *
 * Scenarios:
 *   1. Percent encode / decode round-trip, including the reserved characters.
 *   2. HTML entity decoding and tag stripping.
 *   3. Redirect hrefs resolve to the page they wrap.
 *   4. A realistic Lite results page parses to title / url / snippet.
 *   5. A result whose snippet cell is missing does not borrow the next one's.
 *   6. Markup with no results parses to an empty list rather than junk.
 *   7. Registration puts the tool in the registry with the right flags.
 *   8. With no HTTP transport the tool reports that, rather than hanging.
 *   9. A call with no question is rejected before any work.
 */

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <nlohmann/json.hpp>
#include <string>

#include "plugin/web_research_internal.h"
#include "plugin/web_search_client.h"
#include "rac/plugin/rac_tool_provider.h"
#include "rac/plugin/rac_web_research.h"

namespace {

using nlohmann::json;
namespace web = rac::tools::web;

int g_test_count = 0;
int g_fail_count = 0;

#define CHECK(cond, label)                        \
    do {                                          \
        ++g_test_count;                           \
        if (!(cond)) {                            \
            ++g_fail_count;                       \
            std::printf("  FAIL: %s\n", (label)); \
        } else {                                  \
            std::printf("  ok:   %s\n", (label)); \
        }                                         \
    } while (0)

// Shaped after a real lite.duckduckgo.com response: the link and its snippet
// live in separate table rows, which is why the parser has to scan forward.
const char* kLitePage = R"HTML(
<html><body><table>
<tr>
  <td valign="top">1.&nbsp;</td>
  <td>
    <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fswift&amp;rut=9f" class="result-link">Swift 6.2 &amp; concurrency</a>
  </td>
</tr>
<tr>
  <td>&nbsp;</td>
  <td class="result-snippet">Swift 6.2 tightens <b>strict concurrency</b> checking.</td>
</tr>
<tr>
  <td valign="top">2.&nbsp;</td>
  <td>
    <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdocs.example.org%2Fguide&amp;rut=2a" class="result-link">The migration guide</a>
  </td>
</tr>
<tr>
  <td>&nbsp;</td>
  <td class="result-snippet">How to move an existing package over.</td>
</tr>
</table></body></html>
)HTML";

// First result has no snippet cell at all; the second one does.
const char* kMissingSnippetPage = R"HTML(
<table>
<tr><td><a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fa.example" class="result-link">First</a></td></tr>
<tr><td><a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fb.example" class="result-link">Second</a></td></tr>
<tr><td class="result-snippet">Belongs to the second one.</td></tr>
</table>
)HTML";

void test_percent_coding() {
    std::printf("[1] percent encoding\n");
    CHECK(web::percent_encode("hello world") == "hello%20world", "space encoded");
    CHECK(web::percent_encode("a&b=c") == "a%26b%3Dc", "reserved characters encoded");
    CHECK(web::percent_encode("plain-Text_1.0~") == "plain-Text_1.0~", "unreserved untouched");
    CHECK(web::percent_decode("https%3A%2F%2Fx.com") == "https://x.com", "decode round-trip");
    CHECK(web::percent_decode("a+b") == "a b", "plus decodes to space");
    CHECK(web::percent_decode("100%") == "100%", "a trailing percent is left alone");
    CHECK(web::percent_decode("%zz") == "%zz", "invalid escape is left alone");
}

void test_html_cleaning() {
    std::printf("[2] entity decoding and tag stripping\n");
    CHECK(web::decode_html_entities("a &amp; b") == "a & b", "ampersand");
    CHECK(web::decode_html_entities("&lt;tag&gt;") == "<tag>", "angle brackets");
    CHECK(web::decode_html_entities("it&#39;s") == "it's", "numeric apostrophe");
    CHECK(web::strip_tags("<b>bold</b> text") == "bold text", "tags removed");
    CHECK(web::strip_tags("  spaced   out  ") == "spaced out", "whitespace collapsed");
    CHECK(web::strip_tags("<a href='x'>link</a> &amp; more") == "link & more",
          "tags and entities together");
}

void test_redirect_resolution() {
    std::printf("[3] redirect hrefs\n");
    CHECK(web::resolve_redirect("//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa&rut=x") ==
              "https://example.com/a",
          "uddg target extracted and decoded");
    CHECK(web::resolve_redirect("//example.com/plain") == "https://example.com/plain",
          "protocol-relative href gets a scheme");
    CHECK(web::resolve_redirect("https://example.com/direct") == "https://example.com/direct",
          "an absolute href is passed through");
}

void test_parse_results() {
    std::printf("[4] a realistic results page\n");
    const auto results = web::parse_lite_html(kLitePage);
    CHECK(results.size() == 2, "both results found");
    if (results.size() == 2) {
        CHECK(results[0].title == "Swift 6.2 & concurrency", "title decoded");
        CHECK(results[0].url == "https://example.com/swift", "url resolved through the redirect");
        CHECK(results[0].snippet == "Swift 6.2 tightens strict concurrency checking.",
              "snippet stripped of markup");
        CHECK(results[1].title == "The migration guide", "second title");
        CHECK(results[1].url == "https://docs.example.org/guide", "second url");
        CHECK(results[1].snippet == "How to move an existing package over.", "second snippet");
    }
}

void test_missing_snippet_does_not_steal() {
    std::printf("[5] a missing snippet does not borrow the next result's\n");
    const auto results = web::parse_lite_html(kMissingSnippetPage);
    CHECK(results.size() == 2, "both results found");
    if (results.size() == 2) {
        CHECK(results[0].snippet == "First", "falls back to its own title");
        CHECK(results[1].snippet == "Belongs to the second one.", "second keeps its snippet");
    }
}

void test_empty_and_junk() {
    std::printf("[6] pages with nothing to parse\n");
    CHECK(web::parse_lite_html("").empty(), "empty input");
    CHECK(web::parse_lite_html("<html><body>no results</body></html>").empty(), "no links");
    CHECK(web::parse_lite_html("<a class=\"result-link\">no href</a>").empty(),
          "a link with no href is skipped");
    CHECK(!web::results_page_url("a b").empty(), "results page url built");
    CHECK(web::results_page_url("a b").find("a%20b") != std::string::npos,
          "results page url is encoded");
}

void test_page_content_extraction() {
    std::printf("[7] page text extraction\n");
    const std::string page =
        "<html><head><title>T</title>"
        "<style>body{color:red}</style>"
        "<script>var x = 1; if (x < 2) { alert('hi'); }</script>"
        "</head><body>"
        "<!-- a comment -->"
        "<h1>The headline</h1><p>The first paragraph.</p>"
        "<noscript>Enable JavaScript</noscript>"
        "</body></html>";
    const std::string text = web::strip_tags(web::strip_non_content_elements(page));

    CHECK(text.find("The headline") != std::string::npos, "content kept");
    CHECK(text.find("The first paragraph.") != std::string::npos, "paragraph kept");
    // The reason this function exists: strip_tags alone deletes <script> and
    // keeps the JavaScript between it and </script>.
    CHECK(text.find("alert") == std::string::npos, "script body removed");
    CHECK(text.find("var x") == std::string::npos, "script source removed");
    CHECK(text.find("color:red") == std::string::npos, "style body removed");
    CHECK(text.find("a comment") == std::string::npos, "comment removed");
    CHECK(text.find("Enable JavaScript") == std::string::npos, "noscript removed");

    CHECK(web::strip_non_content_elements("<script>unclosed").find("unclosed") == std::string::npos,
          "an unclosed script does not leak");
    CHECK(web::fetch_page_text("", 1024, 100).empty(), "an empty url reads as nothing");
    CHECK(web::fetch_page_text("https://example.com", 1024, 100).empty(),
          "no transport reads as nothing");
}

// The provider's query filter, reached through the same rules it applies.
// These are the exact lines a reasoning model produced in a real run.
void test_query_filtering() {
    std::printf("[8] planned queries reject model commentary\n");
    struct Case {
        const char* line;
        bool expected;
        const char* label;
    };
    const Case cases[] = {
        {"latest Apple news August 2026", true, "a real query is kept"},
        {"Apple product announcements this week", true, "another real query"},
        {"Thinking Process:", false, "a heading is rejected"},
        {"Task: Write 4 different search queries.", false, "a lead-in is rejected"},
        {"**Analyze the Request:**", false, "bold commentary is rejected"},
        {"# Queries", false, "a markdown heading is rejected"},
        {"news", false, "a single word is not a query"},
        {"", false, "an empty line is rejected"},
        {"I will now write four different search queries that together cover what the user "
         "is asking about, considering recency and relevance and several other factors",
         false, "prose is rejected"},
    };
    for (const auto& item : cases) {
        CHECK(web::query_is_usable(item.line) == item.expected, item.label);
    }
}

void test_reasoning_block_stripping() {
    std::printf("[9] reasoning blocks are dropped before queries are read\n");
    CHECK(web::strip_reasoning_block("<think>plan plan</think>real query here") ==
              "real query here",
          "a closed block is removed");
    CHECK(web::strip_reasoning_block("a\n<thinking>x</thinking>\nb").find("x") == std::string::npos,
          "an alternate tag is removed");
    // Unterminated means the budget ran out mid-reasoning: there is no query
    // after it, and keeping the text would search the reasoning.
    CHECK(web::strip_reasoning_block("<think>never closed").empty(),
          "an unterminated block leaves nothing");
    CHECK(web::strip_reasoning_block("plain queries") == "plain queries",
          "text with no block is untouched");
}

void test_registration() {
    std::printf("[10] registration\n");
    CHECK(rac_tool_web_research_register() == RAC_SUCCESS, "registered");
    const rac_tool_provider_t* provider = rac_tool_provider_find("web_research");
    CHECK(provider != nullptr, "found in the registry");
    if (provider != nullptr) {
        CHECK(provider->grounds_answer != 0, "declares that it grounds the answer");
        CHECK(provider->single_use != 0, "declares single use");
        CHECK(provider->published_keys != nullptr, "publishes keys");
        if (provider->published_keys != nullptr) {
            CHECK(std::strcmp(provider->published_keys[0], "summary") == 0, "publishes summary");
            CHECK(std::strcmp(provider->published_keys[1], "source_url") == 0,
                  "publishes source_url");
            CHECK(provider->published_keys[2] == nullptr, "published keys are terminated");
        }
        CHECK(std::string(provider->parameters_json).find("\"question\"") != std::string::npos,
              "question is a declared parameter");
        // Not required at the schema level on purpose: commons validates before
        // the tool runs, and a rejected call throws away the whole turn rather
        // than letting the model correct itself.
        CHECK(std::string(provider->parameters_json).find("required") == std::string::npos,
              "no argument is marked required");
    }
    CHECK(rac_tool_web_research_unregister() == RAC_SUCCESS, "unregistered");
    CHECK(rac_tool_provider_find("web_research") == nullptr, "gone from the registry");
}

// Runs the tool directly. No LLM is loaded and no HTTP transport is
// registered, which is exactly the degraded case worth pinning: it must
// report why rather than hang or crash.
json run_tool(const char* args) {
    rac_tool_web_research_register();
    const rac_tool_provider_t* provider = rac_tool_provider_find("web_research");
    if (provider == nullptr) {
        return json::object();
    }
    // A context whose emitter accepts everything and never reports a cancel.
    rac_tool_context_t ctx{};
    ctx.emit = [](const rac_tool_context_t*, const char*, const char*, rac_tool_progress_status_t,
                  const char*) { return RAC_TRUE; };
    ctx.is_cancelled = [](const rac_tool_context_t*) { return RAC_FALSE; };
    ctx.state = nullptr;

    char* raw = nullptr;
    const rac_result_t rc = provider->execute(args, &ctx, &raw, provider->user_data);
    json parsed = json::object();
    if (rc == RAC_SUCCESS && raw != nullptr) {
        parsed = json::parse(raw, nullptr, false);
    }
    std::free(raw);
    rac_tool_web_research_unregister();
    return parsed.is_discarded() ? json::object() : parsed;
}

void test_no_transport_is_reported() {
    std::printf("[11] no HTTP transport: reported, not hung\n");
    const json result = run_tool(R"({"question":"what shipped in Swift 6.2"})");
    CHECK(result.contains("error"), "an error is reported");
    if (result.contains("error")) {
        CHECK(result["error"].get<std::string>().find("transport") != std::string::npos,
              "the error names the missing transport");
    }
    CHECK(result.contains("summary"), "a summary is still present for the model to read");
    CHECK(result.value("question", std::string()) == "what shipped in Swift 6.2",
          "the question is echoed back");
}

void test_missing_question_rejected() {
    std::printf("[12] a call with no question\n");
    const json result = run_tool(R"({})");
    CHECK(result.value("error", std::string()).find("Call web_research again") != std::string::npos,
          "rejected up front");

    const json blank = run_tool(R"({"question":"   "})");
    CHECK(blank.value("error", std::string()).find("Call web_research again") != std::string::npos,
          "whitespace is not a question");

    const json broken = run_tool("not json at all");
    CHECK(broken.contains("error"), "unparseable arguments are reported");

    const json wrong_shape = run_tool("[1,2,3]");
    CHECK(wrong_shape.contains("error"), "a non-object argument is reported");

    // A model writing {"question": 42} must degrade, not throw.
    const json wrong_type = run_tool(R"({"question":42})");
    CHECK(wrong_type.value("error", std::string()).find("Call web_research again") !=
              std::string::npos,
          "a non-string question is treated as absent");

    // Models pass arguments the schema never advertised. Ignoring them beats
    // throwing, which would lose an otherwise valid call.
    const json extra = run_tool(R"({"question":"anything","max_questions":"2"})");
    CHECK(extra.value("question", std::string()) == "anything",
          "an unadvertised argument is ignored, not fatal");

    const json odd = run_tool(R"({"question":"anything","depth":{"a":1}})");
    CHECK(odd.value("question", std::string()) == "anything",
          "an unadvertised object argument is ignored");
}

}  // namespace

int main() {
    std::printf("=== web research ===\n");
    test_percent_coding();
    test_html_cleaning();
    test_redirect_resolution();
    test_parse_results();
    test_missing_snippet_does_not_steal();
    test_empty_and_junk();
    test_page_content_extraction();
    test_query_filtering();
    test_reasoning_block_stripping();
    test_registration();
    test_no_transport_is_reported();
    test_missing_question_rejected();
    std::printf("=== %d checks, %d failed ===\n", g_test_count, g_fail_count);
    return g_fail_count == 0 ? 0 : 1;
}
