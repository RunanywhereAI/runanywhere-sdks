// SPDX-License-Identifier: Apache-2.0
//
// op_engine_backed.cpp — engine-backed operator factories.
//
// Materializes the six "engine-backed" `OperatorSpec.type` strings reachable
// from `SolutionConfig` (voice_agent / rag / agent_loop /
// time_series). Each factory produces a single-input / single-output
// PipelineNode that:
//
//   1. Receives the next typed `Item` from its input edge.
//   2. Builds the corresponding `runanywhere.v1.<X>Request` proto from the
//      operator's spec params + payload contents.
//   3. Invokes the lifecycle-owned proto C ABI (rac_llm_generate_proto,
//      rac_stt_transcribe_lifecycle_proto, …) which routes through the
//      currently-loaded model + plugin registry.
//   4. Emits one (or more) typed `Item` payloads on its output edge so the
//      downstream operator sees a contract-correct payload type.
//
// SOLID:
//   * Each factory is independent — adding a new primitive does not touch
//     the others.
//   * The factory only depends on the public proto API and the typed
//     OperatorNode/Item contract; the graph runtime stays decoupled from
//     concrete engines (LlamaCPP / ONNX / Sherpa / …).
//
// MVP scope:
//   * generate_text, transcribe, synthesize, embed, detect_voice all
//     dispatch through their respective `*_lifecycle_proto` ABI. They
//     return RAC_ERROR_FEATURE_NOT_AVAILABLE / RAC_ERROR_*_NOT_LOADED at
//     run time when no model has been loaded for that primitive — the
//     SolutionRunner cancels honestly and feed() returns the error.
//   * retrieve dispatches through `rac_rag_query_proto` against a host-
//     supplied RAG session handle resolved from
//     `OperatorSpec.params["session_handle_id"]`. The handle is a pointer-
//     sized integer produced by `rac_rag_session_create_proto` and stamped
//     onto the spec by the host before SolutionRunner::start(). When the
//     param is missing or unparseable the operator fails honestly on the
//     first input and the runner cancels the graph.

#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/graph/pipeline_node.hpp"
#include "rac/solutions/operator_registry.hpp"

#if defined(RAC_HAVE_PROTOBUF)
#include "embeddings_options.pb.h"
#include "llm_options.pb.h"
#include "llm_service.pb.h"
#include "pipeline.pb.h"
#include "rag.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vad_options.pb.h"

#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#if defined(RAC_HAVE_RAG)
#include "rac/features/rag/rac_rag.h"
#endif
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#endif

namespace rac::solutions {

#if defined(RAC_HAVE_PROTOBUF)

namespace {

using rac::graph::OverflowPolicy;
using rac::graph::PipelineNode;

// ---------------------------------------------------------------------------
// Param helpers — pull strongly-typed values out of `OperatorSpec.params`.
// ---------------------------------------------------------------------------

const std::string* find_param(const runanywhere::v1::OperatorSpec& spec, const std::string& key) {
    auto it = spec.params().find(key);
    if (it == spec.params().end())
        return nullptr;
    return &it->second;
}

int param_int_or(const runanywhere::v1::OperatorSpec& spec, const std::string& key, int fallback) {
    const std::string* value = find_param(spec, key);
    if (!value || value->empty())
        return fallback;
    try {
        return std::stoi(*value);
    } catch (...) {
        return fallback;
    }
}

float param_float_or(const runanywhere::v1::OperatorSpec& spec, const std::string& key,
                     float fallback) {
    const std::string* value = find_param(spec, key);
    if (!value || value->empty())
        return fallback;
    try {
        return std::stof(*value);
    } catch (...) {
        return fallback;
    }
}

// Parse an unsigned 64-bit identifier (e.g. a host-provided session handle)
// from `OperatorSpec.params`. Returns true and writes *out on success;
// returns false when the key is missing, empty, or unparseable so the
// caller can fail honestly instead of falling back to a default.
bool param_uint64(const runanywhere::v1::OperatorSpec& spec, const std::string& key,
                  std::uint64_t* out) {
    const std::string* value = find_param(spec, key);
    if (!value || value->empty())
        return false;
    try {
        size_t pos = 0;
        const unsigned long long parsed = std::stoull(*value, &pos, 0);
        if (pos != value->size())
            return false;
        if (out)
            *out = static_cast<std::uint64_t>(parsed);
        return true;
    } catch (...) {
        return false;
    }
}

// ---------------------------------------------------------------------------
// Owned proto buffer wrapper — RAII free() of the rac_proto_buffer_t output.
// ---------------------------------------------------------------------------

class ProtoBufferGuard {
   public:
    ProtoBufferGuard() { rac_proto_buffer_init(&buffer_); }
    ~ProtoBufferGuard() { rac_proto_buffer_free(&buffer_); }

    ProtoBufferGuard(const ProtoBufferGuard&) = delete;
    ProtoBufferGuard& operator=(const ProtoBufferGuard&) = delete;

    rac_proto_buffer_t* raw() noexcept { return &buffer_; }
    const rac_proto_buffer_t* raw() const noexcept { return &buffer_; }

    rac_result_t status() const noexcept { return buffer_.status; }
    const uint8_t* data() const noexcept { return buffer_.data; }
    size_t size() const noexcept { return buffer_.size; }

   private:
    rac_proto_buffer_t buffer_{};
};

// Set the runner's last-error detail with a uniform, operator-prefixed message.
//
// `rac_error_set_details` is thread_local — operators run inside scheduler
// worker threads, so writing only there leaves the host thread blind to the
// failure cause. We additionally stash the detail in a process-wide buffer
// (record_operator_error_detail) that SolutionRunner::wait() drains on the
// caller's thread and re-publishes via `rac_error_set_details`.
void set_error_detail(const std::string& op, const std::string& message) {
    const std::string detail = "operator '" + op + "': " + message;
    rac_error_set_details(detail.c_str());
    record_operator_error_detail(detail);
}

// Emit a terminal control signal so the SolutionRunner sees a clean failure
// instead of silently dropping items. The PayloadTypeGuardNode treats the
// terminal payload as a contract violation against the configured edge type
// and cancels the graph; that is the desired behavior — better than silent
// stub output.
void cancel_graph(rac::graph::CancelToken* token) {
    if (token)
        token->cancel();
}

// ---------------------------------------------------------------------------
// generate_text — text in (text.utf8) → text out (text.utf8) on port "token".
// ---------------------------------------------------------------------------
class GenerateTextNode final : public OperatorNode {
   public:
    GenerateTextNode(std::string name, const runanywhere::v1::OperatorSpec& spec)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          model_id_(spec.model_id()),
          max_tokens_(param_int_or(spec, "max_tokens", 0)),
          temperature_(param_float_or(spec, "temperature", 0.0f)) {
        if (const std::string* p = find_param(spec, "system_prompt"); p) {
            system_prompt_ = *p;
        }
    }

   protected:
    void process(Item item, OutputEdge& out) override {
        if (!item.is_text()) {
            set_error_detail(name(), "generate_text expected text.utf8 input but received '" +
                                         std::string(item.body_type_id()) + "'");
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::LLMGenerateRequest request;
        request.set_prompt(item.text());
        auto* options = request.mutable_options();
        options->set_temperature(temperature_ > 0.0f ? temperature_ : 0.8f);
        options->set_top_p(1.0f);
        options->set_repetition_penalty(1.0f);
        if (!system_prompt_.empty()) {
            options->set_system_prompt(system_prompt_);
        }
        if (max_tokens_ > 0) {
            options->set_max_tokens(max_tokens_);
        }
        if (!model_id_.empty()) {
            request.set_model_id(model_id_);
        }

        std::vector<uint8_t> bytes(request.ByteSizeLong());
        if (!bytes.empty() &&
            !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            set_error_detail(name(), "failed to serialize LLMGenerateRequest");
            cancel_graph(this->cancel_token());
            return;
        }

        ProtoBufferGuard buffer;
        rac_result_t rc = rac_llm_generate_proto(bytes.data(), bytes.size(), buffer.raw());
        if (rc != RAC_SUCCESS) {
            set_error_detail(name(), std::string("rac_llm_generate_proto failed: ") +
                                         rac_error_message(rc));
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::LLMGenerationResult result;
        if (!result.ParseFromArray(buffer.data(), static_cast<int>(buffer.size()))) {
            set_error_detail(name(), "failed to decode LLMGenerationResult");
            cancel_graph(this->cancel_token());
            return;
        }

        if (!result.error_message().empty() || result.error_code() != 0) {
            set_error_detail(name(), "LLM generation failed: " + result.error_message());
            cancel_graph(this->cancel_token());
            return;
        }

        out.push(Item::text(result.text()), this->cancel_token());
    }

   private:
    std::string model_id_;
    int max_tokens_;
    float temperature_;
    std::string system_prompt_;
};

// ---------------------------------------------------------------------------
// transcribe — audio in (audio.pcm_s16le) → text out (text.utf8) on port "final".
// ---------------------------------------------------------------------------
class TranscribeNode final : public OperatorNode {
   public:
    TranscribeNode(std::string name, const runanywhere::v1::OperatorSpec& spec)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          model_id_(spec.model_id()),
          sample_rate_(param_int_or(spec, "sample_rate_hz", 16000)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        if (!item.is_audio_pcm_s16le()) {
            set_error_detail(name(), "transcribe expected audio.pcm_s16le input but received '" +
                                         std::string(item.body_type_id()) + "'");
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::STTTranscriptionRequest request;
        auto* audio = request.mutable_audio();
        audio->set_audio_data(item.bytes);
        audio->set_encoding(runanywhere::v1::STT_AUDIO_ENCODING_PCM_S16_LE);
        audio->set_sample_rate(sample_rate_);
        audio->set_channels(1);
        audio->set_bits_per_sample(16);
        if (!model_id_.empty()) {
            (*request.mutable_metadata())["model_id"] = model_id_;
        }

        std::vector<uint8_t> bytes(request.ByteSizeLong());
        if (!bytes.empty() &&
            !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            set_error_detail(name(), "failed to serialize STTTranscriptionRequest");
            cancel_graph(this->cancel_token());
            return;
        }

        ProtoBufferGuard buffer;
        rac_result_t rc =
            rac_stt_transcribe_lifecycle_proto(bytes.data(), bytes.size(), buffer.raw());
        if (rc != RAC_SUCCESS) {
            set_error_detail(name(), std::string("rac_stt_transcribe_lifecycle_proto failed: ") +
                                         rac_error_message(rc));
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::STTOutput output;
        if (!output.ParseFromArray(buffer.data(), static_cast<int>(buffer.size()))) {
            set_error_detail(name(), "failed to decode STTOutput");
            cancel_graph(this->cancel_token());
            return;
        }

        if (output.error_code() != 0) {
            set_error_detail(name(), "STT transcription failed: " + output.error_message());
            cancel_graph(this->cancel_token());
            return;
        }

        out.push(Item::text(output.text()), this->cancel_token());
    }

   private:
    std::string model_id_;
    int sample_rate_;
};

// ---------------------------------------------------------------------------
// synthesize — text in (text.utf8) → audio out (audio.pcm_s16le) on port "out".
// ---------------------------------------------------------------------------
class SynthesizeNode final : public OperatorNode {
   public:
    SynthesizeNode(std::string name, const runanywhere::v1::OperatorSpec& spec)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          model_id_(spec.model_id()) {
        const std::string* voice = find_param(spec, "voice");
        if (voice)
            voice_ = *voice;
        const std::string* lang = find_param(spec, "language");
        if (lang)
            language_ = *lang;
    }

   protected:
    void process(Item item, OutputEdge& out) override {
        if (!item.is_text()) {
            set_error_detail(name(), "synthesize expected text.utf8 input but received '" +
                                         std::string(item.body_type_id()) + "'");
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::TTSSynthesisRequest request;
        request.set_text(item.text());
        if (!voice_.empty() || !language_.empty()) {
            auto* options = request.mutable_options();
            if (!voice_.empty()) {
                options->set_voice(voice_);
            }
            if (!language_.empty()) {
                options->set_language_code(language_);
            }
        }
        if (!model_id_.empty()) {
            (*request.mutable_metadata())["model_id"] = model_id_;
        }

        std::vector<uint8_t> bytes(request.ByteSizeLong());
        if (!bytes.empty() &&
            !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            set_error_detail(name(), "failed to serialize TTSSynthesisRequest");
            cancel_graph(this->cancel_token());
            return;
        }

        ProtoBufferGuard buffer;
        rac_result_t rc =
            rac_tts_synthesize_lifecycle_proto(bytes.data(), bytes.size(), buffer.raw());
        if (rc != RAC_SUCCESS) {
            set_error_detail(name(), std::string("rac_tts_synthesize_lifecycle_proto failed: ") +
                                         rac_error_message(rc));
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::TTSOutput output;
        if (!output.ParseFromArray(buffer.data(), static_cast<int>(buffer.size()))) {
            set_error_detail(name(), "failed to decode TTSOutput");
            cancel_graph(this->cancel_token());
            return;
        }

        if (output.error_code() != 0) {
            set_error_detail(name(), "TTS synthesis failed: " + output.error_message());
            cancel_graph(this->cancel_token());
            return;
        }

        // PCM S16LE bytes from the TTS engine flow as-is on the audio edge.
        if (output.audio_data().empty()) {
            set_error_detail(name(), "TTS produced empty audio buffer");
            cancel_graph(this->cancel_token());
            return;
        }

        out.push(Item::audio_pcm_s16le(output.audio_data()), this->cancel_token());
    }

   private:
    std::string model_id_;
    std::string voice_;
    std::string language_;
};

// ---------------------------------------------------------------------------
// detect_voice — audio in (audio.pcm_s16le) → audio out (audio.pcm_s16le)
//                on port "out". Frames are forwarded only when speech is
//                detected; non-speech frames are silently dropped.
// ---------------------------------------------------------------------------
class DetectVoiceNode final : public OperatorNode {
   public:
    DetectVoiceNode(std::string name, const runanywhere::v1::OperatorSpec& spec)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          sample_rate_(param_int_or(spec, "sample_rate_hz", 16000)),
          threshold_(param_float_or(spec, "threshold", 0.0f)) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        if (!item.is_audio_pcm_s16le()) {
            set_error_detail(name(), "detect_voice expected audio.pcm_s16le input but received '" +
                                         std::string(item.body_type_id()) + "'");
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::VADProcessRequest request;
        auto* audio = request.mutable_audio();
        audio->set_audio_data(item.bytes);
        audio->set_encoding(runanywhere::v1::VAD_AUDIO_ENCODING_PCM_S16_LE);
        audio->set_sample_rate(sample_rate_);
        audio->set_channels(1);
        if (threshold_ > 0.0f) {
            request.mutable_options()->set_threshold(threshold_);
        }

        std::vector<uint8_t> bytes(request.ByteSizeLong());
        if (!bytes.empty() &&
            !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            set_error_detail(name(), "failed to serialize VADProcessRequest");
            cancel_graph(this->cancel_token());
            return;
        }

        ProtoBufferGuard buffer;
        rac_result_t rc = rac_vad_process_lifecycle_proto(bytes.data(), bytes.size(), buffer.raw());
        if (rc != RAC_SUCCESS) {
            set_error_detail(name(), std::string("rac_vad_process_lifecycle_proto failed: ") +
                                         rac_error_message(rc));
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::VADResult result;
        if (!result.ParseFromArray(buffer.data(), static_cast<int>(buffer.size()))) {
            set_error_detail(name(), "failed to decode VADResult");
            cancel_graph(this->cancel_token());
            return;
        }

        if (result.error_code() != 0) {
            set_error_detail(name(), "VAD detect failed: " + result.error_message());
            cancel_graph(this->cancel_token());
            return;
        }

        // Forward audio frames only when the VAD reports speech. The MVP
        // gate is the simplest semantically-correct behavior: STT / LLM
        // downstream do not see silence.
        if (result.is_speech()) {
            out.push(std::move(item), this->cancel_token());
        }
    }

   private:
    int sample_rate_;
    float threshold_;
};

// ---------------------------------------------------------------------------
// embed — text in (text.utf8) → embedding out (embedding.vector.float32)
//         on port "vec".
// ---------------------------------------------------------------------------
class EmbedNode final : public OperatorNode {
   public:
    EmbedNode(std::string name, const runanywhere::v1::OperatorSpec& spec)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          model_id_(spec.model_id()) {}

   protected:
    void process(Item item, OutputEdge& out) override {
        if (!item.is_text()) {
            set_error_detail(name(), "embed expected text.utf8 input but received '" +
                                         std::string(item.body_type_id()) + "'");
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::EmbeddingsRequest request;
        request.add_texts(item.text());
        if (!model_id_.empty()) {
            request.set_model_id(model_id_);
        }

        std::vector<uint8_t> bytes(request.ByteSizeLong());
        if (!bytes.empty() &&
            !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            set_error_detail(name(), "failed to serialize EmbeddingsRequest");
            cancel_graph(this->cancel_token());
            return;
        }

        ProtoBufferGuard buffer;
        rac_result_t rc =
            rac_embeddings_embed_batch_lifecycle_proto(bytes.data(), bytes.size(), buffer.raw());
        if (rc != RAC_SUCCESS) {
            set_error_detail(name(),
                             std::string("rac_embeddings_embed_batch_lifecycle_proto failed: ") +
                                 rac_error_message(rc));
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::EmbeddingsResult result;
        if (!result.ParseFromArray(buffer.data(), static_cast<int>(buffer.size()))) {
            set_error_detail(name(), "failed to decode EmbeddingsResult");
            cancel_graph(this->cancel_token());
            return;
        }

        if (result.error_code() != 0) {
            set_error_detail(name(), "embeddings call failed: " + result.error_message());
            cancel_graph(this->cancel_token());
            return;
        }

        if (result.vectors_size() == 0) {
            set_error_detail(name(), "embeddings result has no vectors");
            cancel_graph(this->cancel_token());
            return;
        }

        const auto& vec = result.vectors(0);
        std::vector<float> values(vec.values().begin(), vec.values().end());
        if (values.empty()) {
            set_error_detail(name(), "embeddings result vector is empty");
            cancel_graph(this->cancel_token());
            return;
        }
        out.push(Item::embedding_vector(std::move(values)), this->cancel_token());
    }

   private:
    std::string model_id_;
};

// ---------------------------------------------------------------------------
// retrieve — text in (text.utf8) → text out (text.utf8) on port "results".
//
// The retrieve operator queries a host-provided RAG session
// (`rac_rag_session_create_proto`) for chunks relevant to the inbound
// query text. The host stamps the session handle into
// `OperatorSpec.params["session_handle_id"]` (decimal or 0x-prefixed
// hexadecimal of the pointer-sized integer returned by the create call).
// The operator builds a `runanywhere.v1.RAGQueryOptions` proto from the
// remaining `params` and the inbound text, calls `rac_rag_query_proto`,
// decodes the `RAGResult`, joins the retrieved chunks into a single
// context string, and emits it on the output edge.
//
// Errors are surfaced via `set_error_detail` + `cancel_graph` so the
// SolutionRunner sees a clean failure rather than silently dropping
// items. Missing `session_handle_id` fails on the first input — the
// operator never runs in mock mode.
// ---------------------------------------------------------------------------
class RetrieveNode final : public OperatorNode {
   public:
    RetrieveNode(std::string name, const runanywhere::v1::OperatorSpec& spec)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8, OverflowPolicy::BlockProducer),
          model_id_(spec.model_id()),
          retrieval_top_k_(param_int_or(spec, "k", 0)),
          similarity_threshold_(param_float_or(spec, "similarity_threshold", 0.0f)),
          has_session_handle_(param_uint64(spec, "session_handle_id", &session_handle_id_)) {
        if (const std::string* p = find_param(spec, "system_prompt"); p) {
            system_prompt_ = *p;
        }
    }

   protected:
    void process(Item item, OutputEdge& out) override {
        if (!has_session_handle_) {
            set_error_detail(name(),
                             "retrieve requires OperatorSpec.params['session_handle_id'] "
                             "(unsigned 64-bit RAG session handle from "
                             "rac_rag_session_create_proto); none was provided");
            cancel_graph(this->cancel_token());
            return;
        }
        if (!item.is_text()) {
            set_error_detail(name(), "retrieve expected text.utf8 input but received '" +
                                         std::string(item.body_type_id()) + "'");
            cancel_graph(this->cancel_token());
            return;
        }
        if (item.text().empty()) {
            set_error_detail(name(), "retrieve requires a non-empty query text");
            cancel_graph(this->cancel_token());
            return;
        }

        runanywhere::v1::RAGQueryOptions request;
        request.set_question(item.text());
        if (!system_prompt_.empty()) {
            request.set_system_prompt(system_prompt_);
        }
        if (retrieval_top_k_ > 0) {
            request.set_retrieval_top_k(retrieval_top_k_);
        }
        if (similarity_threshold_ > 0.0f) {
            request.set_similarity_threshold(similarity_threshold_);
        }
        // Per the RAG service contract, retrieve does not generate. Setting
        // max_tokens to 0 still produces a RAGResult with retrieved_chunks
        // populated; downstream context_build operators consume those
        // chunks. (The current `rac_rag_query_proto` runs the full query
        // pipeline; the chunks remain authoritative.)

        std::vector<uint8_t> bytes(request.ByteSizeLong());
        if (!bytes.empty() &&
            !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            set_error_detail(name(), "failed to serialize RAGQueryOptions");
            cancel_graph(this->cancel_token());
            return;
        }

        rac_handle_t session =
            reinterpret_cast<rac_handle_t>(static_cast<std::uintptr_t>(session_handle_id_));

        ProtoBufferGuard buffer;
#if defined(RAC_HAVE_RAG)
        rac_result_t rc = rac_rag_query_proto(session, bytes.data(), bytes.size(), buffer.raw());
        if (rc != RAC_SUCCESS) {
            const char* msg = buffer.raw()->error_message;
            set_error_detail(name(), std::string("rac_rag_query_proto failed: ") +
                                         (msg && msg[0] ? msg : rac_error_message(rc)));
            cancel_graph(this->cancel_token());
            return;
        }
#else
        (void)session;
        set_error_detail(
            name(),
            "Solutions RetrieveNode requires RAG backend; rebuild with -DRAC_BACKEND_RAG=ON");
        cancel_graph(this->cancel_token());
        return;
#endif

        runanywhere::v1::RAGResult result;
        if (!result.ParseFromArray(buffer.data(), static_cast<int>(buffer.size()))) {
            set_error_detail(name(), "failed to decode RAGResult");
            cancel_graph(this->cancel_token());
            return;
        }

        if (result.error_code() != 0 || !result.error_message().empty()) {
            set_error_detail(name(), "RAG query failed: " + result.error_message());
            cancel_graph(this->cancel_token());
            return;
        }

        // Prefer the joined context (already prompt-template ready). When
        // empty, fall back to concatenating the chunk texts so downstream
        // context_build / generate_text always see a non-empty payload
        // when the retriever returned chunks.
        std::string out_text = result.context_used();
        if (out_text.empty()) {
            for (int i = 0; i < result.retrieved_chunks_size(); ++i) {
                if (!out_text.empty())
                    out_text.push_back('\n');
                out_text.append(result.retrieved_chunks(i).text());
            }
        }
        if (out_text.empty()) {
            set_error_detail(name(), "RAG query produced no retrieval context");
            cancel_graph(this->cancel_token());
            return;
        }

        out.push(Item::text(std::move(out_text)), this->cancel_token());
        (void)model_id_;  // model_id is host metadata; the active session owns the model.
    }

   private:
    std::string model_id_;
    int retrieval_top_k_;
    float similarity_threshold_;
    std::uint64_t session_handle_id_{0};
    bool has_session_handle_{false};
    std::string system_prompt_;
};

// ---------------------------------------------------------------------------
// Port schema helpers — same shape as test_pipeline_executor's helpers.
// ---------------------------------------------------------------------------

OperatorPortSchema schema(std::vector<std::string> input_ports,
                          std::vector<std::string> output_ports, const char* input_type,
                          const char* output_type) {
    OperatorPortSchema s;
    s.input_ports = std::move(input_ports);
    s.output_ports = std::move(output_ports);
    for (const auto& p : s.input_ports) {
        s.input_port_types.emplace(p, input_type);
    }
    for (const auto& p : s.output_ports) {
        s.output_port_types.emplace(p, output_type);
    }
    return s;
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

std::size_t register_engine_backed_operators(OperatorRegistry& registry) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)registry;
    return 0;
#else
    std::size_t count = 0;

    // generate_text — LLM text generation. text.utf8 in → text.utf8 out
    // on port "token" (matches solution_converter's edge layout).
    registry.register_factory(
        "generate_text",
        [](const runanywhere::v1::OperatorSpec& spec) {
            return std::make_shared<GenerateTextNode>(spec.name(), spec);
        },
        schema({"in"}, {"token"}, kPayloadTextUtf8, kPayloadTextUtf8));
    ++count;

    // transcribe — STT. audio.pcm_s16le in → text.utf8 out on port "final".
    registry.register_factory(
        "transcribe",
        [](const runanywhere::v1::OperatorSpec& spec) {
            return std::make_shared<TranscribeNode>(spec.name(), spec);
        },
        schema({"in"}, {"final"}, kPayloadAudioPcmS16Le, kPayloadTextUtf8));
    ++count;

    // synthesize — TTS. text.utf8 in → audio.pcm_s16le out on port "out".
    registry.register_factory(
        "synthesize",
        [](const runanywhere::v1::OperatorSpec& spec) {
            return std::make_shared<SynthesizeNode>(spec.name(), spec);
        },
        schema({"in"}, {"out"}, kPayloadTextUtf8, kPayloadAudioPcmS16Le));
    ++count;

    // detect_voice — VAD. audio.pcm_s16le in → audio.pcm_s16le out on
    // port "out". Frames are forwarded only when speech is detected.
    registry.register_factory(
        "detect_voice",
        [](const runanywhere::v1::OperatorSpec& spec) {
            return std::make_shared<DetectVoiceNode>(spec.name(), spec);
        },
        schema({"in"}, {"out"}, kPayloadAudioPcmS16Le, kPayloadAudioPcmS16Le));
    ++count;

    // embed — Embeddings. text.utf8 in → embedding.vector.float32 out on
    // port "vec".
    registry.register_factory(
        "embed",
        [](const runanywhere::v1::OperatorSpec& spec) {
            return std::make_shared<EmbedNode>(spec.name(), spec);
        },
        schema({"in"}, {"vec"}, kPayloadTextUtf8, kPayloadEmbeddingVectorFloat32));
    ++count;

    // retrieve — RAG retrieval. text.utf8 in → text.utf8 out on port
    // "results". The host stamps the RAG session handle into
    // OperatorSpec.params["session_handle_id"]; missing/unparseable values
    // fail the operator on the first input so the runner cancels honestly.
    registry.register_factory(
        "retrieve",
        [](const runanywhere::v1::OperatorSpec& spec) {
            return std::make_shared<RetrieveNode>(spec.name(), spec);
        },
        schema({"in"}, {"results"}, kPayloadTextUtf8, kPayloadTextUtf8));
    ++count;

    return count;
#endif
}

}  // namespace rac::solutions
