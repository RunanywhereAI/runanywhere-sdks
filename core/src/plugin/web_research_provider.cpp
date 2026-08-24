/**
 * @file web_research_provider.cpp
 * @brief The `web_research` tool: plan questions, search them, compose an answer.
 *
 * Runs its own small loop over the LLM commons already owns. That is safe
 * because the tool-calling run loop releases its lifecycle ref before
 * executing a tool, so a generation started here is sequential rather than
 * nested. It is NOT interruptible by the loop's cancel, though: while a tool
 * runs, the loop has no active generation to cancel. Hence the small
 * per-stage token budgets and the cancel poll between every stage.
 */
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "features/llm/llm_thinking_directive_internal.h"
#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "plugin/web_research_internal.h"
#include "plugin/web_search_client.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/plugin/rac_tool_provider.h"
#include "rac/plugin/rac_web_research.h"

namespace {

using nlohmann::json;
using rac::tools::web::SearchResult;

constexpr const char* kTag = "WebResearch";
constexpr const char* kToolName = "web_research";

constexpr size_t kResultsPerSearch = 6;
constexpr size_t kSnippetBudget = 400;
// How many of the ranked results get read in full. Each is an HTTP round trip
// and this runs on phones, so the cap is deliberately small: the top few carry
// most of the answer, and a cancel is only noticed between stages.
constexpr size_t kPagesToRead = 4;
constexpr size_t kPageFetchBytes = 400 * 1024;
constexpr size_t kPageTextBudget = 2000;
// Floor for "this page yielded content". A consent wall or a JS shell strips
// to a few dozen characters; a short wire item is a few hundred and is worth
// reading. This was 200, which silently discarded real articles — a dropped
// source is invisible in the answer and reads as the model inventing.
constexpr size_t kMinReadableChars = 120;
constexpr int32_t kPageTimeoutMs = 10000;
constexpr int32_t kSearchTimeoutMs = 15000;

// Deliberately small. A cancel arriving mid-tool is only observed at the next
// stage boundary, so per-stage token budgets are also the worst case for how
// long a cancel waits.
constexpr int32_t kQueryTokens = 64;
constexpr int32_t kComposeTokens = 640;

// Directive rather than descriptive: under AUTO tool choice this text is the
// only thing deciding whether the model calls the tool at all.
constexpr const char* kDescription =
    "Searches the live web and answers from what it finds, with sources. Use it for anything "
    "current or time-sensitive: news, today's events, prices, scores, schedules, releases, or "
    "any question about what is happening now or recently. It is the only way to reach "
    "information newer than your training data, so reach for it rather than saying you cannot "
    "know.";

// One property, and a required one. Three advertised parameters made a small
// model emit malformed JSON often enough to lose the call outright
// (`{"clarification": "",question":...,max_questions:6}`), and MLX has no
// grammar constraint to catch it, so bad JSON is simply a dropped tool call.
// Anything else a model passes is ignored rather than rejected.
constexpr const char* kParameters = R"({
  "type": "object",
  "properties": {
    "question": {
      "type": "string",
      "description": "The question to research, in full. Not keywords."
    }
  },
  "required": ["question"]
})";
const char* const kPublishedKeys[] = {"summary", "source_url", nullptr};

// --- small helpers ---------------------------------------------------------

std::string trim(const std::string& in) {
    const auto begin = in.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) {
        return {};
    }
    const auto end = in.find_last_not_of(" \t\r\n");
    return in.substr(begin, end - begin + 1);
}

std::string truncate(const std::string& in, size_t limit) {
    if (in.size() <= limit) {
        return in;
    }
    // Cut on a space so the model is not handed a severed word.
    size_t cut = in.rfind(' ', limit);
    if (cut == std::string::npos || cut + 40 < limit) {
        cut = limit;
    }
    return in.substr(0, cut) + "...";
}

/**
 * Read a string field without trusting its type.
 *
 * These arguments are written by a model, so a number or an object where a
 * string belongs is ordinary rather than exceptional, and nlohmann's value()
 * throws on a type mismatch.
 */
std::string string_field(const json& args, const char* key) {
    const auto it = args.find(key);
    if (it == args.end() || !it->is_string()) {
        return {};
    }
    return it->get<std::string>();
}

char* dup_c(const std::string& text) {
    auto* out = static_cast<char*>(std::malloc(text.size() + 1));
    if (out != nullptr) {
        std::memcpy(out, text.c_str(), text.size() + 1);
    }
    return out;
}

// --- one generation --------------------------------------------------------

/**
 * Run a single completion on the currently-loaded LLM.
 *
 * Mirrors run_generate_once without the tool-loop plumbing: acquire, generate,
 * release. Thinking is suppressed and temperature pinned low because every
 * call here wants a short, literal answer rather than prose.
 */
bool generate(const std::string& system_prompt, const std::string& prompt, int32_t max_tokens,
              std::string* out_text) {
    rac::llm::LifecycleLlmRef ref;
    if (rac::llm::acquire_lifecycle_llm(&ref) != RAC_SUCCESS) {
        return false;
    }
    if (ref.ops == nullptr || ref.ops->generate == nullptr) {
        rac::llm::release_lifecycle_llm(&ref);
        return false;
    }

    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    options.max_tokens = max_tokens;
    options.temperature = 0.0F;
    options.top_p = 1.0F;
    options.streaming_enabled = RAC_FALSE;
    options.disable_thinking = RAC_TRUE;
    options.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    rac::llm::clear_lifecycle_llm_cancel(&ref);

    // Setting options.disable_thinking is not enough on its own: commons
    // suppresses reasoning at the *prompt* level, and without the directive a
    // thinking model spends the entire token budget inside an unterminated
    // <think> block and returns nothing usable. run_generate_once does exactly
    // this before calling generate; so must anything else that drives the LLM.
    const std::string effective_prompt = rac::llm::apply_no_think_directive(
        prompt, options.disable_thinking, ref.framework, ref.supports_thinking);

    rac_llm_result_t raw{};
    const rac_result_t rc = ref.ops->generate(ref.impl, effective_prompt.c_str(), &options, &raw);
    const bool ok = rc == RAC_SUCCESS && raw.text != nullptr;
    if (ok) {
        *out_text = trim(raw.text);
    }
    rac_llm_result_free(&raw);
    rac::llm::release_lifecycle_llm(&ref);
    return ok;
}

// --- stages ----------------------------------------------------------------

/**
 * Turn the request into one search query.
 *
 * This used to plan several sub-questions and search each. It never worked:
 * the model spent its whole budget reasoning and returned nothing, so every
 * run fell back to a single search anyway — while paying for the extra
 * generation and giving the model another chance to invent something. One
 * query, and the user's own words when the model gives nothing usable.
 */
std::string plan_query(const std::string& question) {
    std::string reply;
    const bool ok = generate(
        "You turn a request into one web search query. Reply with the query and nothing "
        "else: no commentary, no quotes, no explanation, one line.",
        "Request: " + question + "\n\nSearch query:", kQueryTokens, &reply);
    if (!ok) {
        return question;
    }

    reply = rac::tools::web::strip_reasoning_block(reply);
    size_t start = 0;
    while (start <= reply.size()) {
        const size_t nl = reply.find('\n', start);
        const std::string line = rac::tools::web::normalize_query_line(
            reply.substr(start, nl == std::string::npos ? std::string::npos : nl - start));
        if (rac::tools::web::query_is_usable(line)) {
            return line;
        }
        if (nl == std::string::npos) {
            break;
        }
        start = nl + 1;
    }
    // The question as asked is a perfectly good query, and a far better one
    // than anything salvaged out of a reply that failed every check.
    return question;
}

std::string compose(const std::string& question, const std::vector<SearchResult>& sources) {
    const std::string evidence = rac::tools::web::build_evidence(sources);
    std::string answer;
    const bool ok = generate(
        "You answer only from the sources below. Every fact in your answer must appear in "
        "them, and you cite the source you took it from as [1], [2] and so on. You do not add "
        "anything you know from elsewhere, you do not guess, and you do not fill a gap with "
        "something plausible. If the sources do not answer the question, say exactly what "
        "they do and do not cover.",
        "Question: " + question + "\n\nSources:\n" + evidence + "\nAnswer, citing sources:",
        kComposeTokens, &answer);
    return ok ? answer : std::string();
}

// --- the provider ----------------------------------------------------------

json error_payload(const std::string& message) {
    json payload;
    payload["error"] = message;
    return payload;
}

rac_result_t web_research_execute(const char* args_json, const rac_tool_context_t* ctx,
                                  char** out_result_json, void* user_data) {
    (void)user_data;

    json args;
    try {
        args = json::parse(args_json != nullptr ? args_json : "{}");
    } catch (const json::exception&) {
        *out_result_json = dup_c(error_payload("could not parse tool arguments").dump());
        return RAC_SUCCESS;
    }

    if (!args.is_object()) {
        *out_result_json = dup_c(error_payload("tool arguments must be an object").dump());
        return RAC_SUCCESS;
    }

    const std::string question = trim(string_field(args, "question"));
    if (question.empty()) {
        *out_result_json = dup_c(error_payload("missing question").dump());
        return RAC_SUCCESS;
    }

    json payload;
    payload["question"] = question;

    // Stage 1 — turn the request into a search query.
    if (!ctx->emit(ctx, "understanding", "Understanding the question", RAC_TOOL_PROGRESS_STARTED,
                   nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    const std::string query = plan_query(question);
    payload["query"] = query;
    if (!ctx->emit(ctx, "understanding", "Understanding the question", RAC_TOOL_PROGRESS_COMPLETED,
                   query.c_str())) {
        return RAC_ERROR_CANCELLED;
    }

    // Stage 2 — search it.
    const std::string search_label = "Searching: " + query;
    if (!ctx->emit(ctx, "gathering", search_label.c_str(), RAC_TOOL_PROGRESS_STARTED, nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    const auto outcome = rac::tools::web::search(query, kResultsPerSearch, kSearchTimeoutMs);
    if (!outcome.ok || outcome.results.empty()) {
        const std::string message = outcome.ok ? "no search results found" : outcome.error;
        ctx->emit(ctx, "gathering", search_label.c_str(), RAC_TOOL_PROGRESS_FAILED,
                  message.c_str());
        payload["error"] = message;
        payload["summary"] = "The web search returned nothing for this question.";
        payload["source_url"] = rac::tools::web::results_page_url(query);
        *out_result_json = dup_c(payload.dump());
        return RAC_SUCCESS;
    }
    std::vector<SearchResult> sources = outcome.results;
    const std::string found = std::to_string(sources.size()) + " result(s)";
    if (!ctx->emit(ctx, "gathering", search_label.c_str(), RAC_TOOL_PROGRESS_COMPLETED,
                   found.c_str())) {
        return RAC_ERROR_CANCELLED;
    }

    // Stage 3 — read the pages behind the results.
    if (!ctx->emit(ctx, "reading", "Reading the sources", RAC_TOOL_PROGRESS_STARTED, nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    size_t read_count = 0;
    for (size_t i = 0; i < sources.size() && read_count < kPagesToRead; ++i) {
        if (ctx->is_cancelled(ctx) != RAC_FALSE) {
            return RAC_ERROR_CANCELLED;
        }
        const std::string label = "Reading: " + sources[i].title;
        const std::string body =
            rac::tools::web::fetch_page_text(sources[i].url, kPageFetchBytes, kPageTimeoutMs);
        // A page that will not load, or yields almost nothing, is skipped
        // rather than fatal: its snippet still stands and the others carry the
        // answer. A very short body is nearly always a consent wall or a JS
        // shell rather than an article.
        if (body.size() < kMinReadableChars) {
            ctx->emit(ctx, "reading", label.c_str(), RAC_TOOL_PROGRESS_FAILED,
                      "could not read this page");
            continue;
        }
        sources[i].body = body;
        ++read_count;
        const std::string detail = std::to_string(body.size()) + " characters";
        if (!ctx->emit(ctx, "reading", label.c_str(), RAC_TOOL_PROGRESS_COMPLETED,
                       detail.c_str())) {
            return RAC_ERROR_CANCELLED;
        }
    }
    if (read_count == 0) {
        ctx->emit(ctx, "reading", "Reading the sources", RAC_TOOL_PROGRESS_FAILED,
                  "no page could be read; answering from search snippets");
    }

    json source_list = json::array();
    for (const auto& source : sources) {
        source_list.push_back({{"title", source.title},
                               {"url", source.url},
                               {"snippet", truncate(source.snippet, kSnippetBudget)},
                               {"read", !source.body.empty()}});
    }
    payload["sources"] = source_list;
    payload["source_url"] = sources.front().url;

    // Stage 4 — answer from what was read.
    if (!ctx->emit(ctx, "composing", "Composing the answer", RAC_TOOL_PROGRESS_STARTED, nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    const std::string summary = compose(question, sources);
    if (summary.empty()) {
        // Falling back to the strongest snippet keeps the turn useful when the
        // compose pass fails; the model still sees every source below it.
        payload["summary"] = truncate(sources.front().snippet, kSnippetBudget);
        ctx->emit(ctx, "composing", "Composing the answer", RAC_TOOL_PROGRESS_FAILED,
                  "could not summarize; returning sources");
    } else {
        payload["summary"] = summary;
        ctx->emit(ctx, "composing", "Composing the answer", RAC_TOOL_PROGRESS_COMPLETED, nullptr);
    }

    RAC_LOG_INFO(kTag, "researched '%s' as '%s': %zu source(s), %zu read", question.c_str(),
                 query.c_str(), sources.size(), read_count);
    *out_result_json = dup_c(payload.dump());
    return RAC_SUCCESS;
}

const rac_tool_provider_t kProvider = {
    /* name */ kToolName,
    /* description */ kDescription,
    /* category */ "Web",
    /* parameters_json */ kParameters,
    /* execute */ web_research_execute,
    /* published_keys */ kPublishedKeys,
    /* single_use */ 1,
    /* grounds_answer */ 1,
    /* user_data */ nullptr,
    /* reserved */ {0, 0, 0, 0, 0, 0},
};

}  // namespace

namespace rac::tools::web {

std::string build_evidence(const std::vector<SearchResult>& sources) {
    std::string evidence;
    for (size_t i = 0; i < sources.size(); ++i) {
        // The page text when the source was read, the search snippet when it
        // was not. A snippet is a ranking signal; the page is the material.
        const std::string& body = sources[i].body.empty() ? sources[i].snippet : sources[i].body;
        const size_t budget = sources[i].body.empty() ? kSnippetBudget : kPageTextBudget;
        evidence += "[" + std::to_string(i + 1) + "] " + sources[i].title + "\n" +
                    truncate(body, budget) + "\n\n";
    }
    return evidence;
}

/**
 * Drop a reasoning block the model emitted anyway.
 *
 * `disable_thinking` is set on every call here, and models still open a
 * `<think>` block. Parsing the raw reply means every line of reasoning is a
 * candidate query; an unterminated block means the reply is *all* reasoning
 * and there is nothing to take from it.
 */
std::string strip_reasoning_block(const std::string& text) {
    static const char* kOpen[] = {"<think>", "<thinking>", "<reasoning>"};
    static const char* kClose[] = {"</think>", "</thinking>", "</reasoning>"};
    std::string out = text;
    for (size_t tag = 0; tag < 3; ++tag) {
        size_t at = 0;
        while ((at = out.find(kOpen[tag], at)) != std::string::npos) {
            const size_t end = out.find(kClose[tag], at);
            if (end == std::string::npos) {
                out.erase(at);
                break;
            }
            out.erase(at, end + std::strlen(kClose[tag]) - at);
        }
    }
    return trim(out);
}

/** Strip "1.", "-", "*", "Q:" and surrounding quotes from a listed line. */
std::string normalize_query_line(const std::string& line) {
    std::string out = trim(line);
    size_t at = 0;
    while (at < out.size() && (std::isdigit(static_cast<unsigned char>(out[at])) != 0)) {
        ++at;
    }
    if (at > 0 && at < out.size() && (out[at] == '.' || out[at] == ')')) {
        out = trim(out.substr(at + 1));
    } else if (!out.empty() && (out[0] == '-' || out[0] == '*' || out[0] == 0x2022)) {
        out = trim(out.substr(1));
    }
    if (out.size() > 2 && (out.rfind("Q:", 0) == 0 || out.rfind("q:", 0) == 0)) {
        out = trim(out.substr(2));
    }
    if (out.size() > 1 && out.front() == '"' && out.back() == '"') {
        out = out.substr(1, out.size() - 2);
    }
    // Models bold their queries as often as not; the asterisks would otherwise
    // travel into the search string.
    if (out.size() > 4 && out.rfind("**", 0) == 0 && out.compare(out.size() - 2, 2, "**") == 0) {
        out = trim(out.substr(2, out.size() - 4));
    }
    return out;
}

/**
 * Whether a line the model produced is actually a search query.
 *
 * Asking for "one query per line and nothing else" does not stop a reasoning
 * model prefacing the list with its own commentary, and every such line was
 * being searched verbatim — real runs searched "Thinking Process:" and
 * "**Analyze the Request:**", which is where the junk results came from.
 */
bool query_is_usable(const std::string& line) {
    if (line.size() < 8) {
        return false;
    }
    // A heading or a lead-in, not a question. Models write "Thinking Process:",
    // "Task:", "Queries:" before the list they were asked for.
    if (line.back() == ':') {
        return false;
    }
    // Markdown emphasis and headings only ever appear in commentary here.
    if (line.front() == '#' || line.front() == '*' || line.front() == '`') {
        return false;
    }
    // A label on the first word ("Task:", "Note:", "Step 1:") marks a lead-in
    // rather than a query, and unlike a heading it can still end in a full
    // stop: "Task: Write 4 different search queries." reads as a sentence.
    const size_t first_space = line.find(' ');
    if (first_space != std::string::npos && line[first_space - 1] == ':') {
        return false;
    }
    size_t words = 1;
    for (const char c : line) {
        if (c == ' ') {
            ++words;
        }
    }
    // Two words is the floor for something worth a request; past about twenty
    // it is prose the model wrote about the task rather than a query.
    return words >= 2 && words <= 20;
}

}  // namespace rac::tools::web

extern "C" {

rac_result_t rac_tool_web_research_register(void) {
    return rac_tool_provider_register(&kProvider);
}

rac_result_t rac_tool_web_research_unregister(void) {
    return rac_tool_provider_unregister(kToolName);
}

}  // extern "C"
