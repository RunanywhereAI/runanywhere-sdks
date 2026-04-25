// SPDX-License-Identifier: Apache-2.0
//
// solution_converter.cpp — T4.7 SolutionConfig → PipelineSpec expansion.

#include "rac/solutions/solution_converter.hpp"

#include <string>

#include "pipeline.pb.h"
#include "rac/core/rac_error.h"
#include "solutions.pb.h"

namespace rac::solutions {

namespace {

using runanywhere::v1::EdgeSpec;
using runanywhere::v1::OperatorSpec;
using runanywhere::v1::PipelineSpec;
using runanywhere::v1::SolutionConfig;

OperatorSpec* add_op(PipelineSpec* spec,
                     const std::string& name,
                     const std::string& type,
                     const std::string& model_id = {}) {
    auto* op = spec->add_operators();
    op->set_name(name);
    op->set_type(type);
    if (!model_id.empty()) op->set_model_id(model_id);
    return op;
}

void add_edge(PipelineSpec* spec,
              const std::string& from,
              const std::string& to) {
    auto* e = spec->add_edges();
    e->set_from(from);
    e->set_to(to);
}

// ---------------------------------------------------------------------------
// VoiceAgent — VAD → STT → LLM → TTS (mirrors voice_agent_pipeline.cpp).
// ---------------------------------------------------------------------------
void expand_voice_agent(const runanywhere::v1::VoiceAgentConfig& cfg,
                        PipelineSpec* out) {
    out->set_name("voice_agent");

    auto* vad = add_op(out, "vad", "detect_voice", cfg.vad_model_id());
    add_op(out, "stt", "transcribe", cfg.stt_model_id());
    auto* llm = add_op(out, "llm", "generate_text", cfg.llm_model_id());
    auto* tts = add_op(out, "tts", "synthesize",    cfg.tts_model_id());

    if (cfg.sample_rate_hz() > 0) {
        (*vad->mutable_params())["sample_rate_hz"] =
            std::to_string(cfg.sample_rate_hz());
    }
    if (cfg.chunk_ms() > 0) {
        (*vad->mutable_params())["chunk_ms"] = std::to_string(cfg.chunk_ms());
    }
    if (!cfg.system_prompt().empty()) {
        (*llm->mutable_params())["system_prompt"] = cfg.system_prompt();
    }
    if (cfg.max_context_tokens() > 0) {
        (*llm->mutable_params())["max_context_tokens"] =
            std::to_string(cfg.max_context_tokens());
    }
    if (cfg.temperature() != 0.0f) {
        (*llm->mutable_params())["temperature"] =
            std::to_string(cfg.temperature());
    }
    (*tts->mutable_params())["emit_partials"] =
        cfg.emit_partials() ? "true" : "false";

    add_edge(out, "vad.out", "stt.in");
    add_edge(out, "stt.final", "llm.in");
    add_edge(out, "llm.token", "tts.in");
}

// ---------------------------------------------------------------------------
// RAG — Query → Embed → Retrieve → LLM (mirrors rac_rag_pipeline.cpp).
// ---------------------------------------------------------------------------
void expand_rag(const runanywhere::v1::RAGConfig& cfg, PipelineSpec* out) {
    out->set_name("rag");

    add_op(out, "query", "source");
    auto* embed    = add_op(out, "embed", "embed", cfg.embed_model_id());
    auto* retrieve = add_op(out, "retrieve", "retrieve");
    auto* ctx      = add_op(out, "context", "context_build");
    auto* llm      = add_op(out, "llm", "generate_text", cfg.llm_model_id());

    if (cfg.retrieve_k() > 0) {
        (*retrieve->mutable_params())["k"] = std::to_string(cfg.retrieve_k());
    }
    if (cfg.rerank_top() > 0) {
        (*retrieve->mutable_params())["rerank_top"] =
            std::to_string(cfg.rerank_top());
    }
    if (!cfg.vector_store_path().empty()) {
        (*retrieve->mutable_params())["vector_store_path"] =
            cfg.vector_store_path();
    }
    if (!cfg.prompt_template().empty()) {
        (*ctx->mutable_params())["prompt_template"] = cfg.prompt_template();
    }
    if (!cfg.rerank_model_id().empty()) {
        (*retrieve->mutable_params())["rerank_model_id"] =
            cfg.rerank_model_id();
    }
    (void)embed;  // embed params come from model_id only today
    (void)llm;

    add_edge(out, "query.out",    "embed.in");
    add_edge(out, "embed.vec",    "retrieve.in");
    add_edge(out, "retrieve.out", "context.in");
    add_edge(out, "context.out",  "llm.in");
}

// ---------------------------------------------------------------------------
// WakeWord — always-on listener → trigger.
// ---------------------------------------------------------------------------
void expand_wake_word(const runanywhere::v1::WakeWordConfig& cfg,
                      PipelineSpec* out) {
    out->set_name("wake_word");

    add_op(out, "audio", "source");
    auto* detect = add_op(out, "detect", "detect_voice", cfg.model_id());
    add_op(out, "trigger", "sink");

    if (!cfg.keyword().empty()) {
        (*detect->mutable_params())["keyword"] = cfg.keyword();
    }
    if (cfg.threshold() > 0.0f) {
        (*detect->mutable_params())["threshold"] =
            std::to_string(cfg.threshold());
    }

    add_edge(out, "audio.out",   "detect.in");
    add_edge(out, "detect.out",  "trigger.in");
}

// ---------------------------------------------------------------------------
// AgentLoop — multi-turn tool-calling LLM loop. Modelled as a single
// generate_text operator with auxiliary tokenise/context build. The
// iterative loop runs inside the LLM operator's engine; the DAG just
// frames the I/O.
// ---------------------------------------------------------------------------
void expand_agent_loop(const runanywhere::v1::AgentLoopConfig& cfg,
                       PipelineSpec* out) {
    out->set_name("agent_loop");

    add_op(out, "input", "source");
    auto* llm = add_op(out, "llm", "generate_text", cfg.llm_model_id());
    add_op(out, "output", "sink");

    if (!cfg.system_prompt().empty()) {
        (*llm->mutable_params())["system_prompt"] = cfg.system_prompt();
    }
    if (cfg.max_iterations() > 0) {
        (*llm->mutable_params())["max_iterations"] =
            std::to_string(cfg.max_iterations());
    }

    add_edge(out, "input.out", "llm.in");
    add_edge(out, "llm.token", "output.in");
}

// ---------------------------------------------------------------------------
// TimeSeries — window + anomaly_detect + generate_text.
// ---------------------------------------------------------------------------
void expand_time_series(const runanywhere::v1::TimeSeriesConfig& cfg,
                        PipelineSpec* out) {
    out->set_name("time_series");

    add_op(out, "samples", "source");
    auto* win = add_op(out, "window", "window");
    auto* ad  = add_op(out, "anomaly", "anomaly_detect", cfg.anomaly_model_id());
    auto* llm = add_op(out, "llm", "generate_text",      cfg.llm_model_id());
    add_op(out, "report", "sink");

    if (cfg.window_size() > 0) {
        (*win->mutable_params())["size"] = std::to_string(cfg.window_size());
    }
    if (cfg.stride() > 0) {
        (*win->mutable_params())["stride"] = std::to_string(cfg.stride());
    }
    if (cfg.anomaly_threshold() > 0.0f) {
        (*ad->mutable_params())["threshold"] =
            std::to_string(cfg.anomaly_threshold());
    }
    (void)llm;

    add_edge(out, "samples.out", "window.in");
    add_edge(out, "window.out",  "anomaly.in");
    add_edge(out, "anomaly.out", "llm.in");
    add_edge(out, "llm.token",   "report.in");
}

}  // namespace

rac_result_t convert_solution_to_pipeline(const SolutionConfig& config,
                                          PipelineSpec*         out_spec) {
    if (out_spec == nullptr) return RAC_ERROR_INVALID_ARGUMENT;
    out_spec->Clear();

    switch (config.config_case()) {
    case SolutionConfig::kVoiceAgent:
        expand_voice_agent(config.voice_agent(), out_spec);
        return RAC_SUCCESS;
    case SolutionConfig::kRag:
        expand_rag(config.rag(), out_spec);
        return RAC_SUCCESS;
    case SolutionConfig::kWakeWord:
        expand_wake_word(config.wake_word(), out_spec);
        return RAC_SUCCESS;
    case SolutionConfig::kAgentLoop:
        expand_agent_loop(config.agent_loop(), out_spec);
        return RAC_SUCCESS;
    case SolutionConfig::kTimeSeries:
        expand_time_series(config.time_series(), out_spec);
        return RAC_SUCCESS;
    case SolutionConfig::CONFIG_NOT_SET:
        rac_error_set_details("SolutionConfig oneof is unset");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    rac_error_set_details("SolutionConfig oneof case unrecognised");
    return RAC_ERROR_INVALID_CONFIGURATION;
}

}  // namespace rac::solutions
