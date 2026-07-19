/**
 * @file cmd_bench.cpp
 * @brief `rcli bench [model]` — auto-benchmark installed models, like the
 *        Android app's benchmark screen.
 *
 * With no model argument it enumerates every downloaded, non-built-in model
 * from the registry and benchmarks each in its category (LLM / STT / TTS /
 * VLM). Faithful port of the Android BenchmarkRunner / BenchmarkMetricPolicy
 * flow: per (model, scenario), repeat `trials` times {
 *     unload → sample avail RAM → load (timed) → 1 warmup (discarded)
 *     → 1 measured pass → sample avail RAM → per-trial metrics }
 *   → aggregate trials by MEDIAN, report [min,max] where useful.
 *
 * Metrics come from the SDK result protos (LLMGenerationResult / STTOutput /
 * TTSOutput / VLMResult) with wall-clock fallbacks, matching the Android
 * BenchmarkMetricPolicy. No telemetry is emitted (matches Android — the
 * benchmark is a pure measurement).
 */

#include "commands/commands.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "llm_options.pb.h"
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vlm_options.pb.h"
#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "io/output.h"
#include "io/proto.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

// Prompts / text mirror the Android BenchmarkRunner constants so numbers are
// comparable across the CLI and the app.
constexpr const char* kLlmSystemPrompt =
    "You are a helpful assistant. Always give extremely detailed, thorough responses. Never stop "
    "early. Use the full response length available to you. Elaborate on every point with examples "
    "and explanations.";
constexpr const char* kLlmPrompt =
    "Write a very long and detailed explanation of how neural networks work, covering perceptrons, "
    "activation functions, backpropagation, gradient descent, loss functions, convolutional "
    "layers, recurrent layers, transformers, attention mechanisms, and training procedures. Be as "
    "thorough as possible.";
constexpr const char* kVlmPrompt = "Describe this image in detail.";
constexpr const char* kTtsShort = "Hello, this is a test.";
constexpr const char* kTtsMedium =
    "The quick brown fox jumps over the lazy dog. Machine learning models can generate speech from "
    "text with remarkable quality and natural intonation.";
constexpr double kPi = 3.14159265358979323846;

enum class Modality { kLlm, kStt, kTts, kVlm };

const char* modality_label(Modality m) {
    switch (m) {
        case Modality::kLlm:
            return "llm";
        case Modality::kStt:
            return "stt";
        case Modality::kTts:
            return "tts";
        case Modality::kVlm:
            return "vlm";
    }
    return "?";
}

bool modality_of(v1::ModelCategory category, Modality* out) {
    switch (category) {
        case v1::MODEL_CATEGORY_LANGUAGE:
            *out = Modality::kLlm;
            return true;
        case v1::MODEL_CATEGORY_SPEECH_RECOGNITION:
            *out = Modality::kStt;
            return true;
        case v1::MODEL_CATEGORY_SPEECH_SYNTHESIS:
            *out = Modality::kTts;
            return true;
        case v1::MODEL_CATEGORY_MULTIMODAL:
        case v1::MODEL_CATEGORY_VISION:
            *out = Modality::kVlm;
            return true;
        default:
            return false;  // vad, embedding, image-generation are not benchmarked
    }
}

struct Scenario {
    const char* label;
    int32_t max_tokens;  // LLM/VLM
    double seconds;      // STT audio length
    bool sine;           // STT: 440 Hz tone vs silence
    const char* text;    // TTS input
};

const std::vector<Scenario>& scenarios_for(Modality m) {
    static const std::vector<Scenario> llm = {{"Short (50)", 50, 0, false, nullptr},
                                              {"Medium (256)", 256, 0, false, nullptr},
                                              {"Long (512)", 512, 0, false, nullptr}};
    static const std::vector<Scenario> stt = {{"Silent 2s", 0, 2.0, false, nullptr},
                                              {"Sine Tone 3s", 0, 3.0, true, nullptr}};
    static const std::vector<Scenario> tts = {{"Short Text", 0, 0, false, kTtsShort},
                                              {"Medium Text", 0, 0, false, kTtsMedium}};
    static const std::vector<Scenario> vlm = {{"Image Description", 128, 0, false, nullptr}};
    switch (m) {
        case Modality::kLlm:
            return llm;
        case Modality::kStt:
            return stt;
        case Modality::kTts:
            return tts;
        case Modality::kVlm:
            return vlm;
    }
    return llm;
}

// Per-trial metrics; aggregated to medians across trials.
struct Metrics {
    double load_ms = 0.0;
    double warmup_ms = 0.0;
    double end_to_end_ms = 0.0;
    double tokens_per_second = 0.0;  // LLM/VLM
    double prompt_eval_ms = 0.0;     // LLM/VLM prefill
    double decode_ms = 0.0;          // LLM/VLM
    int32_t output_tokens = 0;       // LLM/VLM
    double real_time_factor = 0.0;   // STT
    double chars_per_second = 0.0;   // TTS
    double audio_duration_ms = 0.0;  // TTS
    int64_t memory_delta_bytes = 0;
};

// --- small utilities -------------------------------------------------------

int64_t available_ram_bytes() {
    std::FILE* f = std::fopen("/proc/meminfo", "r");
    if (!f) {
        return 0;
    }
    char line[256];
    int64_t kb = 0;
    while (std::fgets(line, sizeof(line), f)) {
        if (std::sscanf(line, "MemAvailable: %lld kB", reinterpret_cast<long long*>(&kb)) == 1) {
            break;
        }
    }
    std::fclose(f);
    return kb * 1024;
}

double median(std::vector<double> values) {
    std::vector<double> v;
    for (double x : values) {
        if (std::isfinite(x)) {
            v.push_back(x);
        }
    }
    if (v.empty()) {
        return 0.0;
    }
    std::sort(v.begin(), v.end());
    const size_t mid = v.size() / 2;
    return (v.size() % 2 == 1) ? v[mid] : (v[mid - 1] + v[mid]) / 2.0;
}

std::string human_bytes(int64_t bytes) {
    if (bytes <= 0) {
        return "-";
    }
    const double b = static_cast<double>(bytes);
    char buf[32];
    if (b >= 1e9) {
        std::snprintf(buf, sizeof(buf), "%.2f GB", b / 1e9);
    } else if (b >= 1e6) {
        std::snprintf(buf, sizeof(buf), "%.0f MB", b / 1e6);
    } else {
        std::snprintf(buf, sizeof(buf), "%.0f KB", b / 1e3);
    }
    return buf;
}

// 16 kHz, 16-bit mono PCM: silence or a 440 Hz sine at 60% amplitude (matches
// Android SyntheticInput.silentPcm / sinePcm).
std::string make_pcm16(double seconds, bool sine) {
    constexpr int kSampleRate = 16000;
    const int n = static_cast<int>(kSampleRate * seconds);
    std::string out;
    out.resize(static_cast<size_t>(n) * 2);
    auto* samples = reinterpret_cast<int16_t*>(out.data());
    for (int i = 0; i < n; ++i) {
        double v = sine ? std::sin(2.0 * kPi * 440.0 * i / kSampleRate) * 32767.0 * 0.6 : 0.0;
        samples[i] = static_cast<int16_t>(v);
    }
    return out;
}

// --- lifecycle helpers -----------------------------------------------------

void unload_category(v1::ModelCategory category) {
    v1::ModelUnloadRequest request;
    request.set_category(category);
    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_model_lifecycle_unload_proto(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                     &out);
    rac_proto_buffer_free(&out);
}

double load_model_timed(const std::string& model_id, v1::ModelCategory category,
                        std::string* out_error) {
    v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    request.set_category(category);
    request.set_validate_availability(true);
    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const int64_t t0 = rac_monotonic_now_ms();
    const rac_result_t rc = rac_model_lifecycle_load_proto(
        rac_get_model_registry(), reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
        &out);
    const int64_t t1 = rac_monotonic_now_ms();
    v1::ModelLoadResult result;
    std::string parse_err;
    if (rc != RAC_SUCCESS || !proto::parse_proto_buffer(&out, &result, &parse_err)) {
        *out_error = parse_err.empty() ? "load failed" : parse_err;
        return -1.0;
    }
    if (!result.success()) {
        *out_error = result.error_message().empty() ? "load failed" : result.error_message();
        return -1.0;
    }
    return static_cast<double>(t1 - t0);
}

// --- per-modality inference calls ------------------------------------------

bool llm_generate(int32_t max_tokens, bool system_prompt, v1::LLMGenerationResult* out,
                  std::string* err) {
    v1::LLMGenerateRequest request;
    request.set_prompt(kLlmPrompt);
    v1::LLMGenerationOptions* gen = request.mutable_options();
    gen->set_max_tokens(max_tokens);
    gen->set_temperature(0.0f);
    if (system_prompt) {
        gen->set_system_prompt(kLlmSystemPrompt);
    }
    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    const rac_result_t rc =
        rac_llm_generate_proto(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buf);
    if (rc != RAC_SUCCESS || !proto::parse_proto_buffer(&buf, out, err)) {
        if (err->empty()) {
            *err = rac_error_message(rc);
        }
        return false;
    }
    return true;
}

bool stt_transcribe(const std::string& pcm, v1::STTOutput* out, std::string* err) {
    v1::STTTranscriptionRequest request;
    v1::STTAudioSource* audio = request.mutable_audio();
    audio->set_audio_data(pcm);
    audio->set_encoding(v1::STT_AUDIO_ENCODING_PCM_S16_LE);
    audio->set_sample_rate(16000);
    audio->set_channels(1);
    audio->set_bits_per_sample(16);
    v1::STTOptions* opts = request.mutable_options();
    opts->set_language(v1::STT_LANGUAGE_EN);
    opts->set_sample_rate(16000);
    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    const rac_result_t rc = rac_stt_transcribe_lifecycle_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buf);
    if (rc != RAC_SUCCESS || !proto::parse_proto_buffer(&buf, out, err)) {
        if (err->empty()) {
            *err = rac_error_message(rc);
        }
        return false;
    }
    return true;
}

bool tts_synthesize(const std::string& text, v1::TTSOutput* out, std::string* err) {
    v1::TTSSynthesisRequest request;
    request.set_text(text);
    v1::TTSOptions* opts = request.mutable_options();
    opts->set_sample_rate(22050);
    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    const rac_result_t rc = rac_tts_synthesize_lifecycle_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buf);
    if (rc != RAC_SUCCESS || !proto::parse_proto_buffer(&buf, out, err)) {
        if (err->empty()) {
            *err = rac_error_message(rc);
        }
        return false;
    }
    return true;
}

bool vlm_process(const std::string& image_path, int32_t max_tokens, v1::VLMResult* out,
                 std::string* err) {
    v1::VLMGenerationRequest request;
    v1::VLMImage* image = request.add_images();
    image->set_file_path(image_path);
    v1::VLMGenerationOptions* gen = request.mutable_options();
    gen->set_prompt(kVlmPrompt);
    gen->set_max_tokens(max_tokens);
    gen->set_temperature(0.0f);
    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    const rac_result_t rc =
        rac_vlm_generate_proto(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buf);
    if (rc != RAC_SUCCESS || !proto::parse_proto_buffer(&buf, out, err)) {
        if (err->empty()) {
            *err = rac_error_message(rc);
        }
        return false;
    }
    return true;
}

// --- per-trial runners (one load → warmup → measured pass) -----------------

struct TrialCtx {
    std::string model_id;
    v1::ModelCategory category;
    Scenario scenario;
    std::string vlm_image;
};

bool llm_trial(const TrialCtx& c, Metrics* m, std::string* err) {
    unload_category(c.category);
    const int64_t mem_before = available_ram_bytes();
    m->load_ms = load_model_timed(c.model_id, c.category, err);
    if (m->load_ms < 0.0) {
        return false;
    }
    const int64_t w0 = rac_monotonic_now_ms();
    v1::LLMGenerationResult warm;
    if (!llm_generate(5, false, &warm, err)) {
        unload_category(c.category);
        return false;
    }
    m->warmup_ms = static_cast<double>(rac_monotonic_now_ms() - w0);

    const int64_t t0 = rac_monotonic_now_ms();
    v1::LLMGenerationResult r;
    if (!llm_generate(c.scenario.max_tokens, true, &r, err)) {
        unload_category(c.category);
        return false;
    }
    const double measured_e2e = static_cast<double>(rac_monotonic_now_ms() - t0);
    m->memory_delta_bytes = mem_before - available_ram_bytes();
    unload_category(c.category);

    const int32_t out_tokens = r.tokens_generated();
    if (out_tokens <= 0) {
        *err = "no output tokens";
        return false;
    }
    const double e2e = r.generation_time_ms() > 0.0 ? r.generation_time_ms() : measured_e2e;
    const double explicit_decode =
        r.decode_time_ms() > 0 ? static_cast<double>(r.decode_time_ms()) : 0.0;
    double tps = r.tokens_per_second() > 0.0 ? r.tokens_per_second() : 0.0;
    if (tps <= 0.0 && explicit_decode > 0.0) {
        tps = out_tokens * 1000.0 / explicit_decode;
    }
    if (tps <= 0.0 && e2e > 0.0) {
        tps = out_tokens * 1000.0 / e2e;
    }
    m->end_to_end_ms = e2e;
    m->tokens_per_second = tps;
    m->decode_ms = explicit_decode > 0.0 ? explicit_decode : (tps > 0.0 ? out_tokens * 1000.0 / tps
                                                                        : 0.0);
    m->prompt_eval_ms = r.prompt_eval_time_ms() > 0 ? static_cast<double>(r.prompt_eval_time_ms())
                        : (r.has_ttft_ms() ? r.ttft_ms() : 0.0);
    m->output_tokens = out_tokens;
    return true;
}

bool stt_trial(const TrialCtx& c, Metrics* m, std::string* err) {
    unload_category(c.category);
    const int64_t mem_before = available_ram_bytes();
    m->load_ms = load_model_timed(c.model_id, c.category, err);
    if (m->load_ms < 0.0) {
        return false;
    }
    v1::STTOutput warm;
    (void)stt_transcribe(make_pcm16(0.5, false), &warm, err);  // warmup, errors ignored

    const int64_t t0 = rac_monotonic_now_ms();
    v1::STTOutput r;
    if (!stt_transcribe(make_pcm16(c.scenario.seconds, c.scenario.sine), &r, err)) {
        unload_category(c.category);
        return false;
    }
    m->end_to_end_ms = static_cast<double>(rac_monotonic_now_ms() - t0);
    m->memory_delta_bytes = mem_before - available_ram_bytes();
    unload_category(c.category);

    m->real_time_factor = r.has_metadata() && r.metadata().real_time_factor() > 0.0
                              ? r.metadata().real_time_factor()
                              : (c.scenario.seconds > 0.0
                                     ? m->end_to_end_ms / (c.scenario.seconds * 1000.0)
                                     : 0.0);
    return true;
}

bool tts_trial(const TrialCtx& c, Metrics* m, std::string* err) {
    unload_category(c.category);
    const int64_t mem_before = available_ram_bytes();
    m->load_ms = load_model_timed(c.model_id, c.category, err);
    if (m->load_ms < 0.0) {
        return false;
    }
    v1::TTSOutput warm;
    (void)tts_synthesize("Hi.", &warm, err);  // warmup, errors ignored

    const std::string text = c.scenario.text ? c.scenario.text : "";
    const int64_t t0 = rac_monotonic_now_ms();
    v1::TTSOutput r;
    if (!tts_synthesize(text, &r, err)) {
        unload_category(c.category);
        return false;
    }
    m->end_to_end_ms = static_cast<double>(rac_monotonic_now_ms() - t0);
    m->memory_delta_bytes = mem_before - available_ram_bytes();
    unload_category(c.category);

    m->audio_duration_ms = static_cast<double>(r.duration_ms());
    const int32_t chars = r.has_metadata() && r.metadata().character_count() > 0
                              ? r.metadata().character_count()
                              : static_cast<int32_t>(text.size());
    m->chars_per_second = m->end_to_end_ms > 0.0 ? chars * 1000.0 / m->end_to_end_ms : 0.0;
    return true;
}

bool vlm_trial(const TrialCtx& c, Metrics* m, std::string* err) {
    unload_category(v1::MODEL_CATEGORY_MULTIMODAL);
    unload_category(v1::MODEL_CATEGORY_LANGUAGE);
    const int64_t mem_before = available_ram_bytes();
    m->load_ms = load_model_timed(c.model_id, c.category, err);
    if (m->load_ms < 0.0) {
        return false;
    }
    v1::VLMResult warm;
    (void)vlm_process(c.vlm_image, 1, &warm, err);  // warmup, errors ignored

    const int64_t t0 = rac_monotonic_now_ms();
    v1::VLMResult r;
    if (!vlm_process(c.vlm_image, c.scenario.max_tokens, &r, err)) {
        unload_category(c.category);
        return false;
    }
    const double measured_e2e = static_cast<double>(rac_monotonic_now_ms() - t0);
    m->memory_delta_bytes = mem_before - available_ram_bytes();
    unload_category(c.category);

    const int32_t out_tokens = r.completion_tokens();
    m->end_to_end_ms = r.processing_time_ms() > 0 ? static_cast<double>(r.processing_time_ms())
                                                  : measured_e2e;
    m->tokens_per_second = r.tokens_per_second();
    m->prompt_eval_ms = static_cast<double>(r.time_to_first_token_ms());
    m->output_tokens = out_tokens;
    if (m->tokens_per_second <= 0.0 && out_tokens > 0 && m->end_to_end_ms > 0.0) {
        m->tokens_per_second = out_tokens * 1000.0 / m->end_to_end_ms;
    }
    m->decode_ms = m->tokens_per_second > 0.0 ? out_tokens * 1000.0 / m->tokens_per_second : 0.0;
    return true;
}

// --- aggregation + report --------------------------------------------------

struct BenchRow {
    std::string model_id;
    Modality modality;
    std::string scenario;
    bool success = false;
    std::string error;
    int trials = 0;
    Metrics med;
};

using TrialFn = std::function<bool(const TrialCtx&, Metrics*, std::string*)>;

BenchRow aggregate(const GlobalOptions& options, const TrialCtx& ctx, Modality modality, int trials,
                   const TrialFn& trial) {
    BenchRow row;
    row.model_id = ctx.model_id;
    row.modality = modality;
    row.scenario = ctx.scenario.label;
    row.trials = trials;

    std::vector<double> load, warmup, e2e, tps, prefill, decode, mem, rtf, cps, adur;
    std::vector<int> out_tok;
    for (int t = 0; t < trials; ++t) {
        Metrics m;
        std::string err;
        if (!trial(ctx, &m, &err)) {
            row.error = err;
            return row;
        }
        load.push_back(m.load_ms);
        warmup.push_back(m.warmup_ms);
        e2e.push_back(m.end_to_end_ms);
        tps.push_back(m.tokens_per_second);
        prefill.push_back(m.prompt_eval_ms);
        decode.push_back(m.decode_ms);
        mem.push_back(static_cast<double>(m.memory_delta_bytes));
        rtf.push_back(m.real_time_factor);
        cps.push_back(m.chars_per_second);
        adur.push_back(m.audio_duration_ms);
        out_tok.push_back(m.output_tokens);
        if (options.verbose) {
            out::status_line("  trial " + std::to_string(t + 1) + "/" + std::to_string(trials) +
                             " ok");
        }
    }
    row.success = true;
    row.med.load_ms = median(load);
    row.med.warmup_ms = median(warmup);
    row.med.end_to_end_ms = median(e2e);
    row.med.tokens_per_second = median(tps);
    row.med.prompt_eval_ms = median(prefill);
    row.med.decode_ms = median(decode);
    row.med.memory_delta_bytes = static_cast<int64_t>(median(mem));
    row.med.real_time_factor = median(rtf);
    row.med.chars_per_second = median(cps);
    row.med.audio_duration_ms = median(adur);
    row.med.output_tokens = out_tok.empty() ? 0 : out_tok[out_tok.size() / 2];
    return row;
}

// Modality-specific "primary" throughput/latency string for the report.
std::string primary_metric(const BenchRow& r) {
    char buf[64];
    switch (r.modality) {
        case Modality::kLlm:
        case Modality::kVlm:
            std::snprintf(buf, sizeof(buf), "%.1f tok/s  %.0fms pf", r.med.tokens_per_second,
                          r.med.prompt_eval_ms);
            break;
        case Modality::kStt:
            std::snprintf(buf, sizeof(buf), "RTF %.3f (%.0fx rt)", r.med.real_time_factor,
                          r.med.real_time_factor > 0.0 ? 1.0 / r.med.real_time_factor : 0.0);
            break;
        case Modality::kTts:
            std::snprintf(buf, sizeof(buf), "%.0f chars/s", r.med.chars_per_second);
            break;
    }
    return buf;
}

// --- enumeration + driver --------------------------------------------------

struct BenchModel {
    std::string id;
    v1::ModelCategory category;
    Modality modality;
};

bool collect_models(const std::string& only_model, std::vector<BenchModel>* out,
                    std::string* out_error) {
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    if (rac_model_registry_list_downloaded_proto_buffer(rac_get_model_registry(), &buf) !=
        RAC_SUCCESS) {
        *out_error = "failed to list downloaded models";
        return false;
    }
    v1::ModelInfoList list;
    if (!proto::parse_proto_buffer(&buf, &list, out_error)) {
        return false;
    }
    for (const v1::ModelInfo& m : list.models()) {
        if (!only_model.empty() && m.id() != only_model) {
            continue;
        }
        const bool builtin = m.framework() == v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
                             m.framework() == v1::INFERENCE_FRAMEWORK_SYSTEM_TTS;
        if (builtin) {
            continue;
        }
        Modality modality;
        if (!modality_of(m.category(), &modality)) {
            continue;
        }
        out->push_back({m.id(), m.category(), modality});
    }
    return true;
}

int run_bench(const GlobalOptions& options, const std::string& only_model, int trials,
              const std::string& vlm_image) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }
    if (trials < 1) {
        trials = 1;
    }

    std::vector<BenchModel> models;
    std::string error;
    if (!collect_models(only_model, &models, &error)) {
        out::error_line(error);
        return 1;
    }
    if (models.empty()) {
        out::error_line(only_model.empty()
                            ? "no downloaded models to benchmark (pull one with `rcli pull`)"
                            : "model '" + only_model + "' is not a downloaded benchmarkable model");
        return 1;
    }

    std::vector<BenchRow> rows;
    for (const BenchModel& model : models) {
        for (const Scenario& scenario : scenarios_for(model.modality)) {
            out::status_line(std::string("benchmarking ") + modality_label(model.modality) + " " +
                             model.id + " — " + scenario.label + " (" + std::to_string(trials) +
                             " trials)");
            TrialCtx ctx{model.id, model.category, scenario, vlm_image};
            TrialFn fn;
            switch (model.modality) {
                case Modality::kLlm:
                    fn = llm_trial;
                    break;
                case Modality::kStt:
                    fn = stt_trial;
                    break;
                case Modality::kTts:
                    fn = tts_trial;
                    break;
                case Modality::kVlm:
                    fn = vlm_trial;
                    break;
            }
            rows.push_back(aggregate(options, ctx, model.modality, trials, fn));
        }
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object().begin_array("results");
        for (const BenchRow& r : rows) {
            json.begin_array_object()
                .field("model", r.model_id)
                .field("modality", modality_label(r.modality))
                .field("scenario", r.scenario)
                .field("success", r.success)
                .field("trials", static_cast<int64_t>(r.trials));
            if (r.success) {
                json.field("tokens_per_second", r.med.tokens_per_second)
                    .field("prompt_eval_ms", r.med.prompt_eval_ms)
                    .field("decode_ms", r.med.decode_ms)
                    .field("end_to_end_ms", r.med.end_to_end_ms)
                    .field("real_time_factor", r.med.real_time_factor)
                    .field("chars_per_second", r.med.chars_per_second)
                    .field("output_tokens", static_cast<int64_t>(r.med.output_tokens))
                    .field("load_ms", r.med.load_ms)
                    .field("memory_delta_bytes", r.med.memory_delta_bytes);
            } else {
                json.field("error", r.error);
            }
            json.end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
        return 0;
    }

    out::result_line("");
    out::result_line(
        "MODEL                          MOD  SCENARIO         PRIMARY                 LOAD     MEMΔ");
    for (const BenchRow& r : rows) {
        char line[256];
        if (r.success) {
            std::snprintf(line, sizeof(line), "%-30.30s %-4.4s %-15.15s %-22.22s %6.0fms  %s",
                          r.model_id.c_str(), modality_label(r.modality), r.scenario.c_str(),
                          primary_metric(r).c_str(), r.med.load_ms,
                          human_bytes(r.med.memory_delta_bytes).c_str());
        } else {
            std::snprintf(line, sizeof(line), "%-30.30s %-4.4s %-15.15s FAILED: %s",
                          r.model_id.c_str(), modality_label(r.modality), r.scenario.c_str(),
                          r.error.c_str());
        }
        out::result_line(line);
    }
    return 0;
}

}  // namespace

void register_bench(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand(
        "bench", "Benchmark installed models (auto-runs all downloaded LLM/STT/TTS/VLM models)");
    auto model = std::make_shared<std::string>();
    auto trials = std::make_shared<int>(3);
    auto vlm_image = std::make_shared<std::string>("docs/gifs/npu-model-tag-screenshot.png");
    cmd->add_option("model", *model, "Model id to benchmark (default: all downloaded models)");
    cmd->add_option("--trials,-n", *trials, "Measured trials per scenario (median reported)")
        ->default_val(3);
    cmd->add_option("--vlm-image", *vlm_image, "Image file for VLM benchmarking");
    cmd->callback([&options, model, trials, vlm_image]() {
        const int exit_code = run_bench(options, *model, *trials, *vlm_image);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
