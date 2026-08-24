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

constexpr size_t kDefaultQuestions = 4;
constexpr size_t kMaxQuestions = 6;
constexpr size_t kResultsPerQuestion = 4;
constexpr size_t kSnippetBudget = 400;
// How many of the ranked results get read in full. Each is an HTTP round trip
// and this runs on phones, so the cap is deliberately small: the top few carry
// most of the answer, and a cancel is only noticed between stages.
constexpr size_t kPagesToRead = 3;
constexpr size_t kPageFetchBytes = 400 * 1024;
constexpr size_t kPageTextBudget = 2000;
constexpr int32_t kPageTimeoutMs = 10000;
constexpr int32_t kSearchTimeoutMs = 15000;

// Deliberately small. A cancel arriving mid-tool is only observed at the next
// stage boundary, so per-stage token budgets are also the worst case for how
// long a cancel waits.
constexpr int32_t kTriageTokens = 48;
constexpr int32_t kQuestionTokens = 160;
constexpr int32_t kComposeTokens = 640;

// Directive rather than descriptive: under AUTO tool choice this text is the
// only thing deciding whether the model calls the tool at all.
constexpr const char* kDescription =
    "Searches the live web and answers from what it finds, with sources. Use it for anything "
    "current or time-sensitive: news, today's events, prices, scores, schedules, releases, or "
    "any question about what is happening now or recently. It is the only way to reach "
    "information newer than your training data, so reach for it rather than saying you cannot "
    "know.";

// One property, and a required one. An earlier version also advertised
// `max_questions` and `clarification`, and a small model handed three
// parameters emitted malformed JSON often enough to break the call outright
// (`{"clarification": "",question":...,max_questions:6}`) — MLX has no grammar
// constraint to fall back on, so bad JSON is simply a lost tool call. Both are
// still accepted when present; neither needs to be the model's problem, and a
// clarification comes back as part of the next question anyway.
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
 * string belongs is a normal occurrence rather than a bug. nlohmann's value()
 * throws on a type mismatch, which would take the tool down instead of
 * degrading.
 */
std::string string_field(const json& args, const char* key) {
    const auto it = args.find(key);
    if (it == args.end() || !it->is_string()) {
        return {};
    }
    return it->get<std::string>();
}

size_t question_count(const json& args) {
    const auto it = args.find("max_questions");
    if (it == args.end()) {
        return kDefaultQuestions;
    }
    // Accept "4" as readily as 4: models quote numbers often enough that
    // rejecting the string form would just look like the argument was ignored.
    long long requested = 0;
    if (it->is_number_integer()) {
        requested = it->get<long long>();
    } else if (it->is_string()) {
        requested = std::strtoll(it->get<std::string>().c_str(), nullptr, 10);
    } else {
        return kDefaultQuestions;
    }
    if (requested <= 0) {
        return kDefaultQuestions;
    }
    return std::min(static_cast<size_t>(requested), kMaxQuestions);
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

    rac_llm_result_t raw{};
    const rac_result_t rc = ref.ops->generate(ref.impl, prompt.c_str(), &options, &raw);
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
 * Decide whether the question can be researched as written.
 *
 * Returns an empty string to proceed, or the clarification to put to the
 * user. Asking is deliberately not a blocking call into the host: the tool
 * returns `needs_input`, the app asks, and the next turn calls the tool again
 * with `clarification` filled in.
 */
std::string triage(const std::string& question) {
    std::string reply;
    const bool ok = generate(
        "You decide whether a research question can be searched as written. Answer with "
        "exactly OK, or with CLARIFY: followed by one short question, when the request is too "
        "vague or ambiguous to search. Prefer OK. Nothing else.",
        "Request: " + question, kTriageTokens, &reply);
    if (!ok) {
        return {};
    }
    const size_t at = reply.find("CLARIFY:");
    if (at == std::string::npos) {
        return {};
    }
    return trim(reply.substr(at + 8));
}

std::vector<std::string> plan_questions(const std::string& question, size_t wanted) {
    std::string reply;
    const bool ok = generate(
        "You turn a request into search queries. Reply with one query per line and nothing "
        "else: no numbering, no commentary, no blank lines. Each query stands alone and is "
        "specific enough to search on its own.",
        "Write " + std::to_string(wanted) +
            " different search queries that together answer this request. Cover what, why, "
            "how and when where they apply.\n\nRequest: " +
            question,
        kQuestionTokens, &reply);

    std::vector<std::string> questions;
    if (ok) {
        size_t start = 0;
        while (start <= reply.size() && questions.size() < wanted) {
            const size_t nl = reply.find('\n', start);
            const std::string line = rac::tools::web::normalize_query_line(
                reply.substr(start, nl == std::string::npos ? std::string::npos : nl - start));
            if (rac::tools::web::query_is_usable(line)) {
                questions.push_back(line);
            }
            if (nl == std::string::npos) {
                break;
            }
            start = nl + 1;
        }
    }

    // The original question is always worth searching, and it is the whole
    // fallback when the model returns nothing usable.
    if (std::find(questions.begin(), questions.end(), question) == questions.end()) {
        questions.insert(questions.begin(), question);
    }
    if (questions.size() > wanted) {
        questions.resize(wanted);
    }
    return questions;
}

std::string compose(const std::string& question, const std::vector<SearchResult>& sources) {
    std::string evidence;
    for (size_t i = 0; i < sources.size(); ++i) {
        // The page text when the source was read, the search snippet when it
        // was not. A snippet is a ranking signal; the page is the material.
        const std::string& body = sources[i].body.empty() ? sources[i].snippet : sources[i].body;
        const size_t budget = sources[i].body.empty() ? kSnippetBudget : kPageTextBudget;
        evidence += "[" + std::to_string(i + 1) + "] " + sources[i].title + "\n" +
                    truncate(body, budget) + "\n\n";
    }

    std::string answer;
    const bool ok = generate(
        "You answer strictly from the search results given to you. Cite the results you use "
        "as [1], [2] and so on. If the results do not answer the question, say so plainly "
        "rather than filling the gap from memory.",
        "Question: " + question + "\n\nSearch results:\n" + evidence + "\nAnswer:", kComposeTokens,
        &answer);
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

    const size_t wanted = question_count(args);
    const std::string clarification = trim(string_field(args, "clarification"));
    const std::string subject =
        clarification.empty() ? question : question + " (" + clarification + ")";

    json payload;
    payload["question"] = question;

    // Stage 1 — understand what is being asked.
    if (!ctx->emit(ctx, "understanding", "Understanding the question", RAC_TOOL_PROGRESS_STARTED,
                   nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    // A clarification the user already gave is the answer to the only question
    // this stage could ask, so asking again would loop.
    const std::string clarify = clarification.empty() ? triage(subject) : std::string();
    if (!clarify.empty()) {
        ctx->emit(ctx, "understanding", "Needs a clarification", RAC_TOOL_PROGRESS_COMPLETED,
                  clarify.c_str());
        payload["needs_input"] = clarify;
        payload["summary"] = "I need one more detail before I can research this: " + clarify;
        *out_result_json = dup_c(payload.dump());
        return RAC_SUCCESS;
    }
    if (!ctx->emit(ctx, "understanding", "Understanding the question", RAC_TOOL_PROGRESS_COMPLETED,
                   subject.c_str())) {
        return RAC_ERROR_CANCELLED;
    }

    // Stage 2 — plan the sub-questions.
    if (!ctx->emit(ctx, "generating_questions", "Generating questions", RAC_TOOL_PROGRESS_STARTED,
                   nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    const std::vector<std::string> questions = plan_questions(subject, wanted);
    std::string question_list;
    for (const auto& item : questions) {
        question_list += (question_list.empty() ? "" : "\n") + item;
    }
    payload["sub_questions"] = questions;
    if (!ctx->emit(ctx, "generating_questions", "Generating questions", RAC_TOOL_PROGRESS_COMPLETED,
                   question_list.c_str())) {
        return RAC_ERROR_CANCELLED;
    }

    // Stage 3 — search each of them.
    if (!ctx->emit(ctx, "gathering", "Gathering data", RAC_TOOL_PROGRESS_STARTED, nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    std::vector<SearchResult> sources;
    std::vector<std::string> seen_urls;
    std::string last_error;
    for (const auto& item : questions) {
        if (ctx->is_cancelled(ctx) != RAC_FALSE) {
            return RAC_ERROR_CANCELLED;
        }
        const std::string label = "Searching: " + item;
        const auto outcome = rac::tools::web::search(item, kResultsPerQuestion, kSearchTimeoutMs);
        if (!outcome.ok) {
            last_error = outcome.error;
            ctx->emit(ctx, "gathering", label.c_str(), RAC_TOOL_PROGRESS_FAILED,
                      outcome.error.c_str());
            continue;
        }
        for (const auto& result : outcome.results) {
            // The planned questions overlap on purpose, so their results do
            // too; the same page cited twice is noise in the evidence block.
            if (std::find(seen_urls.begin(), seen_urls.end(), result.url) != seen_urls.end()) {
                continue;
            }
            seen_urls.push_back(result.url);
            sources.push_back(result);
        }
        // Per-query label, not a repeated "Gathering data": this stage
        // reports once per search, and a reader wants to see which ones ran.
        const std::string detail = std::to_string(outcome.results.size()) + " result(s)";
        if (!ctx->emit(ctx, "gathering", label.c_str(), RAC_TOOL_PROGRESS_COMPLETED,
                       detail.c_str())) {
            return RAC_ERROR_CANCELLED;
        }
    }

    if (sources.empty()) {
        const std::string message = last_error.empty() ? "no search results found" : last_error;
        ctx->emit(ctx, "gathering", "Gathering data", RAC_TOOL_PROGRESS_FAILED, message.c_str());
        payload["error"] = message;
        payload["summary"] = "The web search returned nothing usable for this question.";
        payload["source_url"] = rac::tools::web::results_page_url(question);
        *out_result_json = dup_c(payload.dump());
        return RAC_SUCCESS;
    }

    // Stage 4 — read the pages behind the top results.
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
        if (body.size() < 200) {
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

    // Stage 5 — answer from what came back.
    if (!ctx->emit(ctx, "composing", "Composing the answer", RAC_TOOL_PROGRESS_STARTED, nullptr)) {
        return RAC_ERROR_CANCELLED;
    }
    const std::string summary = compose(subject, sources);
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

    RAC_LOG_INFO(kTag, "researched '%s' across %zu question(s), %zu source(s)", question.c_str(),
                 questions.size(), sources.size());
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
