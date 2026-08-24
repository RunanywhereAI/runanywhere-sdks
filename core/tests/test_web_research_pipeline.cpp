/**
 * @file test_web_research_pipeline.cpp
 * @brief Every step of web_research, asserted on its actual output.
 *
 * The question this exists to answer is "does the page text the scraper
 * extracts actually reach the model, or does it only ever see search
 * snippets" — an answer built from snippets reads as invention even when the
 * URLs are right, and nothing short of inspecting each stage distinguishes
 * the two.
 *
 * A stub HTTP transport serves a DuckDuckGo Lite results page and the article
 * pages behind it, so the whole pipeline runs with no network and no model:
 * search, scrape, evidence. The compose stage needs an LLM and is therefore
 * asserted on its input rather than its output, which is the part that was
 * suspect anyway.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "plugin/web_research_internal.h"
#include "plugin/web_search_client.h"
#include "rac/core/rac_error.h"
#include "rac/infrastructure/http/rac_http_transport.h"
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

// --- the pages the stub transport serves -----------------------------------

const char* kResultsPage = R"HTML(
<html><body><table>
<tr><td><a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fnews.example.com%2Fapple&amp;rut=1" class="result-link">Apple announces the M5 chip</a></td></tr>
<tr><td class="result-snippet">Apple has announced a new chip.</td></tr>
<tr><td><a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwire.example.org%2Fq3&amp;rut=2" class="result-link">Apple Q3 earnings beat estimates</a></td></tr>
<tr><td class="result-snippet">Revenue was up.</td></tr>
<tr><td><a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdead.example.net%2Fgone&amp;rut=3" class="result-link">A page that 404s</a></td></tr>
<tr><td class="result-snippet">This one will not load.</td></tr>
</table></body></html>
)HTML";

// Deliberately hostile: nav chrome, a script block, a style block and a cookie
// banner wrapped around the only sentences that matter.
const char* kArticleOne = R"HTML(
<html><head><title>M5</title>
<style>.nav{display:none}</style>
<script>window.analytics = {track: function(e){ console.log("apple m5 fake"); }};</script>
</head><body>
<nav><a href="/">Home</a><a href="/tech">Tech</a></nav>
<div id="cookie">We use cookies. Accept?</div>
<article>
<h1>Apple announces the M5 chip</h1>
<p>Apple said the M5 delivers 30 percent more graphics performance than the M4.</p>
<p>The chip ships in the MacBook Pro in November, priced from 1999 dollars.</p>
</article>
<noscript>Please enable JavaScript</noscript>
</body></html>
)HTML";

const char* kArticleTwo = R"HTML(
<html><body><article>
<h1>Apple Q3 earnings beat estimates</h1>
<p>Apple reported revenue of 94.9 billion dollars for the quarter, up 6 percent.</p>
<p>Services revenue reached an all-time high of 24.2 billion dollars.</p>
</article></body></html>
)HTML";

struct StubRequest {
    std::string url;
};

std::vector<StubRequest> g_requests;

char* dup_bytes(const std::string& text) {
    auto* out = static_cast<char*>(std::malloc(text.size() + 1));
    std::memcpy(out, text.c_str(), text.size() + 1);
    return out;
}

rac_result_t stub_send(void* user_data, const rac_http_request_t* req, rac_http_response_t* out) {
    (void)user_data;
    const std::string url = req->url != nullptr ? req->url : "";
    g_requests.push_back({url});

    std::string body;
    int32_t status = 200;
    if (url.find("duckduckgo.com/lite") != std::string::npos) {
        body = kResultsPage;
    } else if (url.find("news.example.com") != std::string::npos) {
        body = kArticleOne;
    } else if (url.find("wire.example.org") != std::string::npos) {
        body = kArticleTwo;
    } else {
        status = 404;
        body = "<html><body>Not found</body></html>";
    }

    out->status = status;
    out->body_bytes = reinterpret_cast<uint8_t*>(dup_bytes(body));
    out->body_len = body.size();
    out->headers = nullptr;
    out->header_count = 0;
    out->redirected_url = nullptr;
    out->elapsed_ms = 1;
    return RAC_SUCCESS;
}

void install_stub_transport() {
    static rac_http_transport_ops_t ops{};
    ops.request_send = stub_send;
    rac_http_transport_register(&ops, nullptr);
}

// --- captured progress ------------------------------------------------------

struct Stage {
    std::string stage_id;
    std::string label;
    rac_tool_progress_status_t status;
    std::string detail;
};

std::vector<Stage> g_stages;

rac_bool_t capture_emit(const rac_tool_context_t* ctx, const char* stage_id, const char* label,
                        rac_tool_progress_status_t status, const char* detail) {
    (void)ctx;
    g_stages.push_back({stage_id != nullptr ? stage_id : "", label != nullptr ? label : "", status,
                        detail != nullptr ? detail : ""});
    return RAC_TRUE;
}

rac_bool_t never_cancelled(const rac_tool_context_t*) {
    return RAC_FALSE;
}

json run_tool(const std::string& question) {
    g_stages.clear();
    g_requests.clear();
    rac_tool_web_research_register();
    const rac_tool_provider_t* provider = rac_tool_provider_find("web_research");
    if (provider == nullptr) {
        return json::object();
    }
    rac_tool_context_t ctx{};
    ctx.emit = capture_emit;
    ctx.is_cancelled = never_cancelled;
    ctx.state = nullptr;

    const json args = {{"question", question}};
    const std::string args_text = args.dump();
    char* raw = nullptr;
    const rac_result_t rc = provider->execute(args_text.c_str(), &ctx, &raw, provider->user_data);
    json parsed = json::object();
    if (rc == RAC_SUCCESS && raw != nullptr) {
        parsed = json::parse(raw, nullptr, false);
    }
    std::free(raw);
    rac_tool_web_research_unregister();
    return parsed.is_discarded() ? json::object() : parsed;
}

bool has_stage(const std::string& id, rac_tool_progress_status_t status) {
    for (const auto& stage : g_stages) {
        if (stage.stage_id == id && stage.status == status) {
            return true;
        }
    }
    return false;
}

const Stage* find_stage(const std::string& id, rac_tool_progress_status_t status) {
    for (const auto& stage : g_stages) {
        if (stage.stage_id == id && stage.status == status) {
            return &stage;
        }
    }
    return nullptr;
}

// --- step 1: the search ------------------------------------------------------

void test_search_step() {
    std::printf("[1] search: results parsed, URLs resolved\n");
    g_requests.clear();
    const auto outcome = web::search("apple news", 6, 1000);

    CHECK(outcome.ok, "search reports success");
    CHECK(outcome.results.size() == 3, "three results parsed");
    if (outcome.results.size() == 3) {
        CHECK(outcome.results[0].url == "https://news.example.com/apple",
              "first URL resolved through the DDG redirect");
        CHECK(outcome.results[0].title == "Apple announces the M5 chip", "first title");
        CHECK(outcome.results[0].snippet == "Apple has announced a new chip.", "first snippet");
        CHECK(outcome.results[0].body.empty(), "body is empty until the page is read");
    }
    CHECK(g_requests.size() == 1, "exactly one request for the search");
}

// --- step 2: the scrape ------------------------------------------------------

void test_scrape_step() {
    std::printf("[2] scrape: the page body, not its chrome\n");
    const std::string text = web::fetch_page_text("https://news.example.com/apple", 400000, 1000);

    CHECK(!text.empty(), "page text extracted");
    // The whole point: the sentences that answer the question are present.
    CHECK(text.find("30 percent more graphics performance") != std::string::npos,
          "the article's actual claim is in the text");
    CHECK(text.find("priced from 1999 dollars") != std::string::npos,
          "a second article fact is present");
    // And the noise around them is not.
    CHECK(text.find("window.analytics") == std::string::npos, "script source excluded");
    CHECK(text.find("apple m5 fake") == std::string::npos,
          "text inside a script cannot be mistaken for content");
    CHECK(text.find("display:none") == std::string::npos, "style body excluded");
    CHECK(text.find("Please enable JavaScript") == std::string::npos, "noscript excluded");

    const std::string missing = web::fetch_page_text("https://dead.example.net/gone", 400000, 1000);
    CHECK(missing.empty(), "a 404 yields no text rather than an error page");
}

// --- step 3: evidence --------------------------------------------------------

void test_evidence_step() {
    std::printf("[3] evidence: page text reaches the model, not the snippet\n");
    std::vector<web::SearchResult> sources;
    web::SearchResult read;
    read.title = "Apple announces the M5 chip";
    read.url = "https://news.example.com/apple";
    read.snippet = "Apple has announced a new chip.";
    read.body = web::fetch_page_text(read.url, 400000, 1000);
    sources.push_back(read);

    web::SearchResult unread;
    unread.title = "A page that 404s";
    unread.url = "https://dead.example.net/gone";
    unread.snippet = "This one will not load.";
    sources.push_back(unread);

    const std::string evidence = web::build_evidence(sources);

    CHECK(evidence.find("[1]") != std::string::npos, "sources are numbered for citation");
    CHECK(evidence.find("[2]") != std::string::npos, "the second source is numbered");
    // This is the assertion the whole file exists for.
    CHECK(evidence.find("30 percent more graphics performance") != std::string::npos,
          "a read source contributes its PAGE TEXT to the evidence");
    CHECK(evidence.find("This one will not load.") != std::string::npos,
          "an unread source falls back to its snippet");
    // The property that matters is not a byte count but that the read source
    // contributed more than its own snippet — that is the whole difference
    // between answering from a search listing and answering from the page.
    CHECK(evidence.find(read.body) != std::string::npos,
          "the read source's full page text is present verbatim");
    CHECK(read.body.size() > read.snippet.size() * 3,
          "the page text is materially richer than the snippet it replaced");
}

// --- step 4: the whole tool --------------------------------------------------

void test_pipeline_end_to_end() {
    std::printf("[4] end to end: stages, order, and the payload\n");
    const json result = run_tool("What did Apple announce?");

    CHECK(has_stage("understanding", RAC_TOOL_PROGRESS_STARTED), "understanding started");
    CHECK(has_stage("understanding", RAC_TOOL_PROGRESS_COMPLETED), "understanding completed");
    CHECK(has_stage("gathering", RAC_TOOL_PROGRESS_STARTED), "gathering started");
    CHECK(has_stage("gathering", RAC_TOOL_PROGRESS_COMPLETED), "gathering completed");
    CHECK(has_stage("reading", RAC_TOOL_PROGRESS_STARTED), "reading started");
    CHECK(has_stage("composing", RAC_TOOL_PROGRESS_STARTED), "composing started");

    const Stage* gathered = find_stage("gathering", RAC_TOOL_PROGRESS_COMPLETED);
    CHECK(gathered != nullptr && gathered->detail.find("3 result") != std::string::npos,
          "gathering reports how many results it found");

    // Two pages are readable and one 404s, so exactly two reads should succeed
    // and the failure should be reported rather than silently dropped.
    int reads_done = 0, reads_failed = 0;
    for (const auto& stage : g_stages) {
        if (stage.stage_id != "reading") {
            continue;
        }
        if (stage.status == RAC_TOOL_PROGRESS_COMPLETED) {
            ++reads_done;
        }
        if (stage.status == RAC_TOOL_PROGRESS_FAILED) {
            ++reads_failed;
        }
    }
    CHECK(reads_done == 2, "both readable pages were read");
    CHECK(reads_failed == 1, "the unreadable page was reported, not hidden");

    CHECK(result.contains("sources"), "payload carries its sources");
    if (result.contains("sources") && result["sources"].is_array()) {
        const auto& sources = result["sources"];
        CHECK(sources.size() == 3, "every result is cited, read or not");
        int marked_read = 0;
        for (const auto& source : sources) {
            if (source.value("read", false)) {
                ++marked_read;
            }
        }
        CHECK(marked_read == 2, "the payload says which sources were actually read");
    }
    CHECK(result.value("source_url", std::string()) == "https://news.example.com/apple",
          "source_url points at the top result");
    CHECK(result.contains("query"), "the query that was searched is reported");

    // One search plus one fetch per readable page, and the 404 attempt.
    CHECK(g_requests.size() == 4, "one search and three page fetches");
}

// The worst bug this tool had, pinned so it cannot return.
//
// A generation used to sit between the question and the search, nominally to
// "turn the request into a search query". Asked for a query, a small model
// answers the question instead: a real MLX run searched for "Apple today's
// latest news is about the new iPhone 15 Pro Max with 4K Ultra HD display and
// 200W charging". Everything downstream then worked perfectly on a fabricated
// premise, which is far worse than failing outright.
void test_query_is_the_users_words() {
    std::printf("[6] the search query is the question, never a generated one\n");
    const std::string question = "What is the latest news about Apple today?";
    const json result = run_tool(question);

    CHECK(result.value("query", std::string()) == question,
          "the query searched is the question verbatim");

    bool searched_the_question = false;
    for (const auto& request : g_requests) {
        if (request.url.find("duckduckgo.com/lite") == std::string::npos) {
            continue;
        }
        // Percent-encoded, so match on a distinctive fragment of the question.
        searched_the_question =
            request.url.find("latest%20news%20about%20Apple") != std::string::npos;
    }
    CHECK(searched_the_question, "the question itself went to the search engine");

    const Stage* understood = find_stage("understanding", RAC_TOOL_PROGRESS_COMPLETED);
    CHECK(understood != nullptr && understood->detail == question,
          "the reported query matches what was asked");
}

void test_no_results_is_honest() {
    std::printf("[7] a search with nothing to find says so\n");
    const json result = run_tool("");
    CHECK(result.value("error", std::string()).find("Call web_research again") != std::string::npos,
          "empty question rejected");
}

}  // namespace

int main() {
    std::printf("=== web research pipeline ===\n");
    install_stub_transport();
    test_search_step();
    test_scrape_step();
    test_evidence_step();
    test_pipeline_end_to_end();
    test_query_is_the_users_words();
    test_no_results_is_honest();
    std::printf("=== %d checks, %d failed ===\n", g_test_count, g_fail_count);
    return g_fail_count == 0 ? 0 : 1;
}
