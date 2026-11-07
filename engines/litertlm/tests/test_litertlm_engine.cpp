/**
 * LiteRT-LM ops against the real library.
 *
 * Broken-file cases always run. The rest need a small chat model:
 *   RAC_LITERTLM_TEST_MODEL=/path/to/model.litertlm test_litertlm_engine
 * Without it the test exits 77, which CMake registers as a skip.
 */

#include "rac_litertlm.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

extern "C" const rac_llm_service_ops_t g_litertlm_llm_ops;

namespace {

const rac_llm_service_ops_t& ops = g_litertlm_llm_ops;
int g_failures = 0;

#define EXPECT(condition)                                                            \
    do {                                                                             \
        if (!(condition)) {                                                          \
            std::fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            ++g_failures;                                                            \
        }                                                                            \
    } while (0)

struct StreamRecord {
    std::string text;
    int tokens = 0;
    int finals = 0;
    std::string finish_reason;
    std::thread::id thread;
    bool other_thread = false;
    int refuse_after = -1;
    std::atomic<int> seen{0};
};

rac_bool_t on_stream(const char* token, rac_bool_t is_final, const char* finish_reason, int32_t,
                     void* user_data) {
    auto* record = static_cast<StreamRecord*>(user_data);
    if (std::this_thread::get_id() != record->thread) {
        record->other_thread = true;
    }
    if (is_final != RAC_FALSE) {
        ++record->finals;
        record->finish_reason = finish_reason != nullptr ? finish_reason : "";
        return RAC_TRUE;
    }
    record->text += token;
    ++record->tokens;
    ++record->seen;
    return (record->refuse_after >= 0 && record->tokens >= record->refuse_after) ? RAC_FALSE
                                                                                 : RAC_TRUE;
}

rac_llm_options_t greedy_options(int32_t max_tokens) {
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    options.temperature = 0.0f;
    options.repetition_penalty = 1.0f;
    options.max_tokens = max_tokens;
    // The cases below read the answer; a thinking model would spend the budget reasoning.
    options.disable_thinking = RAC_TRUE;
    return options;
}

rac_result_t stream(void* impl, const char* prompt, const rac_llm_options_t& options,
                    StreamRecord* record) {
    record->thread = std::this_thread::get_id();
    return ops.generate_stream(impl, prompt, &options, on_stream, record);
}

// What the last stream put into the context. These cases read this rather than the reply to
// tell what reached the model: a small model can answer a question it was given wrongly.
int32_t last_prompt_tokens(void* impl) {
    rac_llm_token_counts_t counts{};
    EXPECT(ops.get_stream_token_counts(impl, &counts) == RAC_SUCCESS);
    return counts.prompt_tokens;
}

bool is_valid_utf8(const std::string& text) {
    for (std::size_t i = 0; i < text.size();) {
        const auto lead = static_cast<unsigned char>(text[i]);
        const std::size_t length = lead < 0x80           ? 1
                                   : (lead >> 5) == 0x6  ? 2
                                   : (lead >> 4) == 0xE  ? 3
                                   : (lead >> 3) == 0x1E ? 4
                                                         : 0;
        if (length == 0 || i + length > text.size()) {
            return false;
        }
        for (std::size_t j = 1; j < length; ++j) {
            if ((static_cast<unsigned char>(text[i + j]) >> 6) != 0x2) {
                return false;
            }
        }
        i += length;
    }
    return true;
}

rac_result_t load_status(const std::string& path) {
    void* impl = nullptr;
    EXPECT(ops.create(path.c_str(), R"({"accelerator_policy":2})", &impl) == RAC_SUCCESS);
    const rac_result_t rc = ops.initialize(impl, path.c_str());
    ops.destroy(impl);
    return rc;
}

void test_registration() {
    EXPECT(rac_backend_litertlm_register() == RAC_SUCCESS);
    EXPECT(rac_backend_litertlm_register() == RAC_SUCCESS);
    EXPECT(rac_backend_litertlm_is_registered() == RAC_TRUE);
    const rac_engine_vtable_t* found =
        rac_plugin_find_for_engine(RAC_PRIMITIVE_GENERATE_TEXT, "litertlm");
    EXPECT(found != nullptr && found->llm_ops == &g_litertlm_llm_ops);
    EXPECT(rac_backend_litertlm_unregister() == RAC_SUCCESS);
    EXPECT(rac_backend_litertlm_is_registered() == RAC_FALSE);
}

void test_broken_files() {
    namespace fs = std::filesystem;
    const fs::path dir = fs::temp_directory_path() / "litertlm_engine_test";
    fs::create_directories(dir);
    EXPECT(load_status((dir / "missing.litertlm").string()) == RAC_ERROR_MODEL_NOT_FOUND);
    EXPECT(load_status(dir.string()) == RAC_ERROR_MODEL_NOT_FOUND);  // a directory with no bundle
    { std::ofstream empty(dir / "empty.litertlm"); }
    EXPECT(load_status((dir / "empty.litertlm").string()) == RAC_ERROR_INVALID_MODEL_FORMAT);
    {
        std::ofstream garbage(dir / "garbage.litertlm", std::ios::binary);
        for (int i = 0; i < 4096; ++i) {
            garbage.put(static_cast<char>(i * 31));
        }
    }
    EXPECT(load_status((dir / "garbage.litertlm").string()) == RAC_ERROR_INVALID_MODEL_FORMAT);
    const char* details = rac_error_get_details();
    EXPECT(details != nullptr && is_valid_utf8(details));
    fs::remove_all(dir);

    // A generation without a load fails cleanly.
    void* impl = nullptr;
    EXPECT(ops.create("unused", nullptr, &impl) == RAC_SUCCESS);
    StreamRecord record;
    EXPECT(stream(impl, "hi", greedy_options(4), &record) == RAC_ERROR_NOT_INITIALIZED);
    ops.destroy(impl);
}

// A bundle whose chat template takes content only as a string (for example
// qwen3_0_6b_mixed_int4.litertlm) still hears the user, the system prompt and the history.
void test_string_only_template(const char* model) {
    void* impl = nullptr;
    EXPECT(ops.create(model, R"({"accelerator_policy":2})", &impl) == RAC_SUCCESS);
    EXPECT(ops.initialize(impl, model) == RAC_SUCCESS);

    StreamRecord plain;
    EXPECT(stream(impl, "What is the capital of France?", greedy_options(48), &plain) ==
           RAC_SUCCESS);
    std::printf("string-only template reply: %s\n", plain.text.c_str());
    EXPECT(plain.text.find("Paris") != std::string::npos);
    const int32_t plain_tokens = last_prompt_tokens(impl);

    const char* history[] = {"My name is Ann.", "Hello Ann."};
    rac_llm_options_t options = greedy_options(32);
    options.system_prompt = "You are a helpful assistant.";
    options.history = history;
    options.n_history = 2;
    StreamRecord recall;
    EXPECT(stream(impl, "What is my name?", options, &recall) == RAC_SUCCESS);
    std::printf("string-only template history reply: %s\n", recall.text.c_str());
    const int32_t recall_tokens = last_prompt_tokens(impl);
    EXPECT(recall_tokens > plain_tokens);

    const std::string kept_answer = recall.text;
    const char* kept_history[] = {"My name is Ann.", "Hello Ann.", "What is my name?",
                                  kept_answer.c_str()};
    options.history = kept_history;
    options.n_history = 4;
    StreamRecord kept;
    EXPECT(stream(impl, "Say it again.", options, &kept) == RAC_SUCCESS);
    std::printf("string-only template kept reply: %s\n", kept.text.c_str());
    const int32_t kept_tokens = last_prompt_tokens(impl);
    EXPECT(kept_tokens > recall_tokens);

    // Such a template can refuse every kept turn, so the next one goes on without trying.
    const std::string later_answer = kept.text;
    const char* later_history[] = {"My name is Ann.",   "Hello Ann.",    "What is my name?",
                                   kept_answer.c_str(), "Say it again.", later_answer.c_str()};
    options.history = later_history;
    options.n_history = 6;
    StreamRecord later;
    EXPECT(stream(impl, "Once more.", options, &later) == RAC_SUCCESS);
    EXPECT(last_prompt_tokens(impl) > kept_tokens);

    ops.cleanup(impl);
    ops.destroy(impl);
}

void test_with_model(const char* model) {
    void* impl = nullptr;
    EXPECT(ops.create(model, R"({"accelerator_policy":2})", &impl) == RAC_SUCCESS);
    EXPECT(ops.initialize(impl, model) == RAC_SUCCESS);
    rac_llm_info_t info{};
    EXPECT(ops.get_info(impl, &info) == RAC_SUCCESS);
    EXPECT(info.is_ready == RAC_TRUE && info.supports_streaming == RAC_TRUE);

    // One turn: text on the calling thread, one terminal, exact counts.
    std::string first_reply;
    {
        StreamRecord record;
        EXPECT(stream(impl, "Name three colours.", greedy_options(40), &record) == RAC_SUCCESS);
        EXPECT(!record.text.empty());
        EXPECT(record.finals == 1);
        EXPECT(!record.other_thread);
        EXPECT(record.finish_reason == "stop" || record.finish_reason == "length");
        rac_llm_token_counts_t counts{};
        EXPECT(ops.get_stream_token_counts(impl, &counts) == RAC_SUCCESS);
        EXPECT(counts.prompt_tokens > 0 && counts.completion_tokens > 0);
        first_reply = record.text;
        std::printf("reply: %s\n", record.text.c_str());
    }

    // max_tokens ends with "length".
    {
        StreamRecord record;
        EXPECT(stream(impl, "Write a long story about the sea.", greedy_options(5), &record) ==
               RAC_SUCCESS);
        EXPECT(record.finish_reason == "length");
        rac_llm_token_counts_t counts{};
        EXPECT(ops.get_stream_token_counts(impl, &counts) == RAC_SUCCESS);
        EXPECT(counts.completion_tokens == 5);
    }

    // A stop sequence cuts the reply where it first appears. Early in the reply: greedy
    // text is not always stable to the end, since dynamically quantized models can flip
    // near-ties between runs (Qwen3-0.6B does on CPU, through the C API alone).
    if (first_reply.size() > 8) {
        const std::string stop = first_reply.substr(4, 3);
        const char* stops[] = {stop.c_str()};
        rac_llm_options_t options = greedy_options(40);
        options.stop_sequences = stops;
        options.num_stop_sequences = 1;
        StreamRecord record;
        EXPECT(stream(impl, "Name three colours.", options, &record) == RAC_SUCCESS);
        // The reply can differ from the first: a greedy run is not repeatable on every model.
        EXPECT(record.finish_reason == "stop" || record.finish_reason == "length");
        EXPECT(record.text.find(stop) == std::string::npos);
    }

    // The callback refusing a token ends the request, and the engine stays usable.
    {
        StreamRecord record;
        record.refuse_after = 2;
        EXPECT(stream(impl, "Write a long story about the sea.", greedy_options(200), &record) ==
               RAC_ERROR_CANCELLED);
        EXPECT(record.tokens == 2);
        EXPECT(record.finals == 0);
        rac_llm_token_counts_t counts{};
        EXPECT(ops.get_stream_token_counts(impl, &counts) == RAC_ERROR_NOT_SUPPORTED);
    }

    // cancel() from another thread stops a running stream.
    {
        StreamRecord record;
        std::thread canceller([&] {
            while (record.seen.load() < 2) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
            EXPECT(ops.cancel(impl) == RAC_SUCCESS);
        });
        EXPECT(stream(impl, "Write a long story about the sea.", greedy_options(400), &record) ==
               RAC_ERROR_CANCELLED);
        canceller.join();
        EXPECT(record.finals == 0);
    }

    // A cancel with nothing running does not reach the next request.
    EXPECT(ops.cancel(impl) == RAC_SUCCESS);

    // History and system prompt reach the model's template.
    {
        StreamRecord alone;
        EXPECT(stream(impl, "What is my name?", greedy_options(4), &alone) == RAC_SUCCESS);
        const int32_t alone_tokens = last_prompt_tokens(impl);
        const char* history[] = {"My name is Ann.", "Hello Ann."};
        rac_llm_options_t options = greedy_options(20);
        options.system_prompt = "You are a helpful assistant.";
        options.history = history;
        options.n_history = 2;
        StreamRecord record;
        EXPECT(stream(impl, "What is my name?", options, &record) == RAC_SUCCESS);
        std::printf("history reply: %s\n", record.text.c_str());
        EXPECT(last_prompt_tokens(impl) > alone_tokens + 8);
    }

    // A chat sends its whole history every turn, and the conversation carries over when
    // the history is what the last request left. Whatever else comes in starts a new one.
    {
        std::vector<std::string> turns;
        const auto ask = [&](const char* question, const rac_llm_options_t& base,
                             StreamRecord* record) {
            std::vector<const char*> history;
            for (const std::string& turn : turns) {
                history.push_back(turn.c_str());
            }
            rac_llm_options_t options = base;
            options.history = history.data();
            options.n_history = static_cast<int32_t>(history.size());
            const rac_result_t rc = stream(impl, question, options, record);
            if (rc == RAC_SUCCESS) {
                turns.emplace_back(question);
                turns.push_back(record->text);
            }
            return rc;
        };
        const rac_llm_options_t options = greedy_options(20);

        StreamRecord first;
        EXPECT(ask("My name is Ann.", options, &first) == RAC_SUCCESS);
        rac_llm_token_counts_t first_counts{};
        EXPECT(ops.get_stream_token_counts(impl, &first_counts) == RAC_SUCCESS);
        EXPECT(first_counts.prompt_tokens > 0 && first_counts.prompt_tokens < 64);

        StreamRecord second;
        EXPECT(ask("What is my name?", options, &second) == RAC_SUCCESS);
        std::printf("kept chat reply: %s\n", second.text.c_str());
        rac_llm_token_counts_t second_counts{};
        EXPECT(ops.get_stream_token_counts(impl, &second_counts) == RAC_SUCCESS);
        EXPECT(second_counts.prompt_tokens >
               first_counts.prompt_tokens + first_counts.completion_tokens);
        EXPECT(second_counts.completion_tokens <= 20);

        // Another system prompt cannot go on in the same conversation.
        rac_llm_options_t with_system = options;
        with_system.system_prompt = "You are a helpful assistant.";
        StreamRecord third;
        EXPECT(ask("Say my name again.", with_system, &third) == RAC_SUCCESS);
        std::printf("new system prompt reply: %s\n", third.text.c_str());

        // A cancelled turn leaves a conversation that can only be deleted.
        StreamRecord cancelled;
        cancelled.refuse_after = 1;
        EXPECT(ask("Write a long story about the sea.", with_system, &cancelled) ==
               RAC_ERROR_CANCELLED);
        StreamRecord after_cancel;
        EXPECT(ask("Say my name once more.", with_system, &after_cancel) == RAC_SUCCESS);
        std::printf("after cancel reply: %s\n", after_cancel.text.c_str());
        EXPECT(!after_cancel.text.empty());

        // A history that differs from what the conversation holds is rendered again.
        const int32_t before_edit = last_prompt_tokens(impl);
        turns[1] = "Hello Bob.";
        turns[0] = "My name is Bob.";
        turns.resize(2);
        StreamRecord edited;
        EXPECT(ask("What is my name?", options, &edited) == RAC_SUCCESS);
        std::printf("edited history reply: %s\n", edited.text.c_str());
        EXPECT(last_prompt_tokens(impl) < before_edit);

        // Thinking turned on goes through a new conversation and on over several turns,
        // whatever the template does with the reasoning of earlier turns.
        rac_llm_options_t thinking = options;
        thinking.disable_thinking = RAC_FALSE;
        thinking.max_tokens = 64;
        for (const char* question : {"Name a colour.", "Name another.", "And one more."}) {
            StreamRecord record;
            EXPECT(ask(question, thinking, &record) == RAC_SUCCESS);
            std::printf("thinking turn: %s\n", record.text.c_str());
            EXPECT(record.finals == 1);
            // Commons takes the tags out of what it sends back, and so does the app.
            const std::size_t closed = record.text.rfind("</think>");
            if (closed != std::string::npos) {
                turns.back() = record.text.substr(closed + 8);
            }
        }

        // A request with no history is independent of the chat before it.
        StreamRecord independent;
        EXPECT(stream(impl, "Name three colours.", options, &independent) == RAC_SUCCESS);
        EXPECT(!independent.text.empty());
    }

    // A chat that outgrows a short context fails with the context error, and then recovers.
    {
        void* short_impl = nullptr;
        EXPECT(ops.create(model, R"({"accelerator_policy":2,"context_length":256})", &short_impl) ==
               RAC_SUCCESS);
        // A model can need more than this for its tensors (Gemma 4 E2B does).
        if (ops.initialize(short_impl, model) == RAC_SUCCESS) {
            std::vector<std::string> turns;
            rac_result_t rc = RAC_SUCCESS;
            int completed = 0;
            for (; completed < 40 && rc == RAC_SUCCESS; ++completed) {
                std::vector<const char*> history;
                for (const std::string& turn : turns) {
                    history.push_back(turn.c_str());
                }
                rac_llm_options_t options = greedy_options(32);
                options.history = history.data();
                options.n_history = static_cast<int32_t>(history.size());
                StreamRecord record;
                rc = stream(short_impl, "Tell me one more fact about the sea.", options, &record);
                if (rc == RAC_SUCCESS) {
                    turns.emplace_back("Tell me one more fact about the sea.");
                    turns.push_back(record.text);
                }
            }
            std::printf("short context ended after %d turns: %d\n", completed, rc);
            EXPECT(rc == RAC_ERROR_CONTEXT_TOO_LONG);
            StreamRecord fresh;
            EXPECT(stream(short_impl, "Name three colours.", greedy_options(8), &fresh) ==
                   RAC_SUCCESS);
            EXPECT(!fresh.text.empty());

            // The context filling up while decoding ends the reply, keeping what came out.
            StreamRecord long_reply;
            const rac_result_t long_rc = stream(short_impl, "Write a long story about the sea.",
                                                greedy_options(1000), &long_reply);
            std::printf("reply up to the context: rc=%d finish=%s pieces=%d\n", long_rc,
                        long_reply.finish_reason.c_str(), long_reply.tokens);
            EXPECT(long_rc == RAC_SUCCESS);
            EXPECT(long_reply.finish_reason == "length");
            EXPECT(long_reply.tokens > 0);
        } else {
            std::printf("this model does not load with a context of 256\n");
        }
        ops.destroy(short_impl);
    }

    // A trailing user turn joins the prompt instead of breaking role alternation.
    {
        StreamRecord alone;
        EXPECT(stream(impl, "What is my name?", greedy_options(4), &alone) == RAC_SUCCESS);
        const int32_t alone_tokens = last_prompt_tokens(impl);
        const char* history[] = {"My name is Ann."};
        rac_llm_options_t options = greedy_options(20);
        options.history = history;
        options.n_history = 1;
        StreamRecord record;
        EXPECT(stream(impl, "What is my name?", options, &record) == RAC_SUCCESS);
        std::printf("odd history reply: %s\n", record.text.c_str());
        EXPECT(last_prompt_tokens(impl) > alone_tokens);
    }

    // Reasoning reaches the SDK inside balanced tags, whether or not the model thinks.
    {
        rac_llm_options_t options = greedy_options(60);
        options.disable_thinking = RAC_FALSE;
        StreamRecord record;
        EXPECT(stream(impl, "Name three colours.", options, &record) == RAC_SUCCESS);
        const bool opened = record.text.find("<think>") != std::string::npos;
        const bool closed = record.text.find("</think>") != std::string::npos;
        std::printf("thinking on: opened=%d closed=%d\n", opened, closed);
        EXPECT(opened == closed);
    }

    // Multi-byte output: chunks are tokens only for ASCII, so counts must not be chunks.
    {
        StreamRecord record;
        rac_llm_options_t options = greedy_options(40);
        EXPECT(stream(impl,
                      "\xE6\x97\xA5\xE6\x9C\xAC\xE3\x81\xAE\xE9\xA6\x96\xE9\x83\xBD\xE3\x81\xAF"
                      "\xEF\xBC\x9F",
                      options, &record) == RAC_SUCCESS);
        EXPECT(is_valid_utf8(record.text));
        rac_llm_token_counts_t counts{};
        EXPECT(ops.get_stream_token_counts(impl, &counts) == RAC_SUCCESS);
        std::printf("multi-byte reply: %s (%d callbacks, %d tokens)\n", record.text.c_str(),
                    record.tokens, counts.completion_tokens);
    }

    // Blocking generate shares the stream path.
    {
        rac_llm_options_t options = greedy_options(40);
        rac_llm_result_t result{};
        EXPECT(ops.generate(impl, "Name three colours.", &options, &result) == RAC_SUCCESS);
        EXPECT(result.text != nullptr && first_reply.compare(0, 4, result.text, 4) == 0);
        EXPECT(result.prompt_tokens > 0 && result.completion_tokens > 0);
        EXPECT(result.total_tokens == result.prompt_tokens + result.completion_tokens);
        std::free(result.text);
    }

    // A grammar is refused, never ignored.
    {
        rac_llm_options_t options = greedy_options(4);
        options.grammar = "root ::= \"x\"";
        StreamRecord record;
        EXPECT(stream(impl, "hi", options, &record) == RAC_ERROR_NOT_SUPPORTED);
    }

    // A prompt beyond the context fails with a typed error and leaves the engine usable.
    {
        std::string prompt;
        for (int i = 0; i < 40000; ++i) {
            prompt += "word ";
        }
        StreamRecord record;
        const rac_result_t rc = stream(impl, prompt.c_str(), greedy_options(4), &record);
        std::printf("oversized prompt: %d\n", rc);
        EXPECT(rc == RAC_ERROR_CONTEXT_TOO_LONG);
        StreamRecord after;
        EXPECT(stream(impl, "Name three colours.", greedy_options(4), &after) == RAC_SUCCESS);
    }

    // The registry can hand over the model's directory instead of the file.
    {
        namespace fs = std::filesystem;
        const fs::path dir = fs::temp_directory_path() / "litertlm_engine_dir_test";
        fs::remove_all(dir);
        fs::create_directories(dir);
        fs::create_symlink(fs::absolute(model), dir / "model.litertlm");
        EXPECT(load_status(dir.string()) == RAC_SUCCESS);
        fs::remove_all(dir);
        fs::create_directories(dir);

        // A bundle cut short is refused. The library alone ends the process with SIGBUS here.
        const auto full = fs::file_size(model);
        std::vector<char> bytes(static_cast<std::size_t>(full));
        std::ifstream(model, std::ios::binary).read(bytes.data(), bytes.size());
        for (const auto percent : {1, 25, 50, 75, 99}) {
            const fs::path truncated = dir / "truncated.litertlm";
            std::ofstream(truncated, std::ios::binary | std::ios::trunc)
                .write(bytes.data(), static_cast<std::streamsize>(full / 100 * percent));
            EXPECT(load_status(truncated.string()) == RAC_ERROR_INVALID_MODEL_FORMAT);
        }
        fs::remove_all(dir);
    }

    // cleanup unloads and keeps the shell; initialize loads again.
    EXPECT(ops.cleanup(impl) == RAC_SUCCESS);
    {
        StreamRecord record;
        EXPECT(stream(impl, "hi", greedy_options(4), &record) == RAC_ERROR_NOT_INITIALIZED);
    }
    EXPECT(ops.initialize(impl, model) == RAC_SUCCESS);
    {
        StreamRecord record;
        EXPECT(stream(impl, "hi", greedy_options(4), &record) == RAC_SUCCESS);
    }
    ops.destroy(impl);
}

}  // namespace

int main() {
    test_registration();
    test_broken_files();
    if (const char* model = std::getenv("RAC_LITERTLM_TEST_STRING_TEMPLATE_MODEL")) {
        test_string_only_template(model);
    }
    const char* model = std::getenv("RAC_LITERTLM_TEST_MODEL");
    if (model == nullptr || model[0] == '\0') {
        if (g_failures == 0) {
            std::printf("SKIP model cases: RAC_LITERTLM_TEST_MODEL is not set\n");
            return 77;
        }
    } else {
        test_with_model(model);
    }
    if (g_failures != 0) {
        std::fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    return 0;
}
