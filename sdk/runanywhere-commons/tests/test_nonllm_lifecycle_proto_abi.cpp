/**
 * @file test_nonllm_lifecycle_proto_abi.cpp
 * @brief Lifecycle-owned generated-proto ABI coverage for non-LLM one-shots.
 */

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#include "embeddings_options.pb.h"
#include "model_types.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vad_options.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        const bool check_result = static_cast<bool>(cond);                                       \
        if (check_result) {                                                                      \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                 \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

struct MockState {
    std::string model_path;
    float vad_threshold{0.015f};
};

char* dup_cstr(const char* text) {
    if (!text)
        return nullptr;
    const size_t len = std::strlen(text);
    auto* out = static_cast<char*>(std::malloc(len + 1));
    if (!out)
        return nullptr;
    std::memcpy(out, text, len + 1);
    return out;
}

template <typename T>
bool serialize(const T& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() || message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

rac_result_t mock_create(const char* model_id, const char*, void** out_impl) {
    if (!out_impl)
        return RAC_ERROR_NULL_POINTER;
    auto* state = new MockState();
    state->model_path = model_id ? model_id : "";
    *out_impl = state;
    return RAC_SUCCESS;
}

rac_result_t mock_initialize_with_path(void* impl, const char* model_path) {
    if (!impl || !model_path)
        return RAC_ERROR_NULL_POINTER;
    static_cast<MockState*>(impl)->model_path = model_path;
    return RAC_SUCCESS;
}

rac_result_t mock_tts_initialize(void* impl) {
    return impl ? RAC_SUCCESS : RAC_ERROR_NULL_POINTER;
}

rac_result_t mock_diffusion_initialize(void* impl, const char* model_path,
                                       const rac_diffusion_config_t*) {
    return mock_initialize_with_path(impl, model_path);
}

rac_result_t mock_cleanup(void*) {
    return RAC_SUCCESS;
}

void mock_destroy(void* impl) {
    delete static_cast<MockState*>(impl);
}

rac_result_t mock_stt_transcribe(void*, const void* audio_data, size_t audio_size,
                                 const rac_stt_options_t*, rac_stt_result_t* out_result) {
    if (!audio_data || audio_size == 0 || !out_result)
        return RAC_ERROR_NULL_POINTER;
    *out_result = {};
    out_result->text = dup_cstr("hello lifecycle");
    out_result->detected_language = dup_cstr("en");
    out_result->confidence = 0.93f;
    out_result->processing_time_ms = 12;
    return (out_result->text && out_result->detected_language) ? RAC_SUCCESS
                                                               : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t mock_stt_transcribe_stream(void*, const void* audio_data, size_t audio_size,
                                        const rac_stt_options_t*,
                                        rac_stt_stream_callback_t callback, void* user_data) {
    if (!audio_data || audio_size == 0 || !callback)
        return RAC_ERROR_INVALID_ARGUMENT;
    callback("stream-draft", RAC_FALSE, user_data);
    callback("stream-final", RAC_TRUE, user_data);
    return RAC_SUCCESS;
}

rac_result_t mock_tts_synthesize(void*, const char* text, const rac_tts_options_t* options,
                                 rac_tts_result_t* out_result) {
    if (!text || !out_result)
        return RAC_ERROR_NULL_POINTER;
    *out_result = {};
    constexpr size_t kAudioSize = 8;
    auto* audio = static_cast<unsigned char*>(std::malloc(kAudioSize));
    if (!audio)
        return RAC_ERROR_OUT_OF_MEMORY;
    for (size_t i = 0; i < kAudioSize; ++i) {
        audio[i] = static_cast<unsigned char>(text[0] + static_cast<char>(i));
    }
    out_result->audio_data = audio;
    out_result->audio_size = kAudioSize;
    out_result->audio_format = options ? options->audio_format : RAC_AUDIO_FORMAT_PCM;
    out_result->sample_rate =
        options && options->sample_rate > 0 ? options->sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE;
    out_result->duration_ms = 250;
    out_result->processing_time_ms = 7;
    return RAC_SUCCESS;
}

rac_result_t mock_vad_process(void* impl, const float* samples, size_t num_samples,
                              rac_bool_t* out_is_speech) {
    if (!impl || !samples || !out_is_speech)
        return RAC_ERROR_NULL_POINTER;
    const auto* state = static_cast<const MockState*>(impl);
    double sum = 0.0;
    for (size_t i = 0; i < num_samples; ++i) {
        sum += std::fabs(samples[i]);
    }
    const double average = num_samples > 0 ? sum / static_cast<double>(num_samples) : 0.0;
    *out_is_speech = average > state->vad_threshold ? RAC_TRUE : RAC_FALSE;
    return RAC_SUCCESS;
}

rac_result_t mock_vad_set_threshold(void* impl, float threshold) {
    if (!impl)
        return RAC_ERROR_NULL_POINTER;
    static_cast<MockState*>(impl)->vad_threshold = threshold;
    return RAC_SUCCESS;
}

rac_bool_t mock_vad_is_speech_active(void*) {
    return RAC_FALSE;
}

rac_result_t mock_embeddings_batch(void*, const char* const* texts, size_t num_texts,
                                   const rac_embeddings_options_t*,
                                   rac_embeddings_result_t* out_result) {
    if (!texts || !out_result)
        return RAC_ERROR_NULL_POINTER;
    *out_result = {};
    out_result->num_embeddings = num_texts;
    out_result->dimension = 3;
    out_result->processing_time_ms = 5;
    out_result->total_tokens = static_cast<int32_t>(num_texts * 2);
    out_result->embeddings = static_cast<rac_embedding_vector_t*>(
        std::calloc(num_texts, sizeof(rac_embedding_vector_t)));
    if (!out_result->embeddings)
        return RAC_ERROR_OUT_OF_MEMORY;
    for (size_t i = 0; i < num_texts; ++i) {
        auto& vector = out_result->embeddings[i];
        vector.dimension = out_result->dimension;
        vector.data = static_cast<float*>(std::malloc(sizeof(float) * vector.dimension));
        if (!vector.data)
            return RAC_ERROR_OUT_OF_MEMORY;
        vector.data[0] = static_cast<float>(i);
        vector.data[1] = static_cast<float>(std::strlen(texts[i]));
        vector.data[2] = 1.0f;
    }
    return RAC_SUCCESS;
}

rac_result_t mock_diffusion_generate(void*, const rac_diffusion_options_t* options,
                                     rac_diffusion_result_t* out_result) {
    if (!options || !out_result)
        return RAC_ERROR_NULL_POINTER;
    *out_result = {};
    out_result->width = options->width;
    out_result->height = options->height;
    out_result->seed_used = options->seed >= 0 ? options->seed : 42;
    out_result->generation_time_ms = 33;
    out_result->error_code = RAC_SUCCESS;
    out_result->image_size =
        static_cast<size_t>(out_result->width) * static_cast<size_t>(out_result->height) * 4U;
    out_result->image_data = static_cast<uint8_t*>(std::malloc(out_result->image_size));
    if (!out_result->image_data)
        return RAC_ERROR_OUT_OF_MEMORY;
    std::memset(out_result->image_data, 0x7f, out_result->image_size);
    return RAC_SUCCESS;
}

runanywhere::v1::ModelInfo build_model(const char* id, runanywhere::v1::ModelCategory category) {
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(id);
    model.set_category(category);
    model.set_format(runanywhere::v1::MODEL_FORMAT_ONNX);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_ONNX);
    model.set_local_path(std::string("/tmp/") + id + ".onnx");
    model.set_is_downloaded(true);
    model.set_is_available(true);
    return model;
}

bool register_model(rac_model_registry_handle_t registry, const runanywhere::v1::ModelInfo& model) {
    std::vector<uint8_t> bytes;
    return serialize(model, &bytes) &&
           rac_model_registry_register_proto(registry, bytes.empty() ? nullptr : bytes.data(),
                                             bytes.size()) == RAC_SUCCESS;
}

bool load_model(rac_model_registry_handle_t registry, const char* model_id) {
    runanywhere::v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    std::vector<uint8_t> bytes;
    if (!serialize(request, &bytes))
        return false;

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, bytes.data(), bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    const bool ok = rc == RAC_SUCCESS && parse_buffer(out, &result) && result.success();
    rac_proto_buffer_free(&out);
    return ok;
}

rac_engine_vtable_t make_mock_vtable(rac_stt_service_ops_t* stt_ops, rac_tts_service_ops_t* tts_ops,
                                     rac_vad_service_ops_t* vad_ops,
                                     rac_embeddings_service_ops_t* embeddings_ops,
                                     rac_diffusion_service_ops_t* diffusion_ops) {
    static const uint32_t kOnnxFormats[] = {
        static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_ONNX)};
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = "onnx";
    v.metadata.display_name = "mock ONNX lifecycle ops";
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = 10000;
    v.metadata.formats = kOnnxFormats;
    v.metadata.formats_count = 1;
    v.stt_ops = stt_ops;
    v.tts_ops = tts_ops;
    v.vad_ops = vad_ops;
    v.embedding_ops = embeddings_ops;
    v.diffusion_ops = diffusion_ops;
    return v;
}

bool install_mock_plugin() {
    rac_stt_service_ops_t stt_ops{};
    stt_ops.initialize = mock_initialize_with_path;
    stt_ops.transcribe = mock_stt_transcribe;
    stt_ops.transcribe_stream = mock_stt_transcribe_stream;
    stt_ops.cleanup = mock_cleanup;
    stt_ops.destroy = mock_destroy;
    stt_ops.create = mock_create;

    rac_tts_service_ops_t tts_ops{};
    tts_ops.initialize = mock_tts_initialize;
    tts_ops.synthesize = mock_tts_synthesize;
    tts_ops.cleanup = mock_cleanup;
    tts_ops.destroy = mock_destroy;
    tts_ops.create = mock_create;

    rac_vad_service_ops_t vad_ops{};
    vad_ops.process = mock_vad_process;
    vad_ops.set_threshold = mock_vad_set_threshold;
    vad_ops.is_speech_active = mock_vad_is_speech_active;
    vad_ops.destroy = mock_destroy;
    vad_ops.initialize = mock_initialize_with_path;
    vad_ops.create = mock_create;

    rac_embeddings_service_ops_t embeddings_ops{};
    embeddings_ops.initialize = mock_initialize_with_path;
    embeddings_ops.embed_batch = mock_embeddings_batch;
    embeddings_ops.cleanup = mock_cleanup;
    embeddings_ops.destroy = mock_destroy;
    embeddings_ops.create = mock_create;

    rac_diffusion_service_ops_t diffusion_ops{};
    diffusion_ops.initialize = mock_diffusion_initialize;
    diffusion_ops.generate = mock_diffusion_generate;
    diffusion_ops.cleanup = mock_cleanup;
    diffusion_ops.destroy = mock_destroy;
    diffusion_ops.create = mock_create;

    static rac_stt_service_ops_t static_stt_ops;
    static rac_tts_service_ops_t static_tts_ops;
    static rac_vad_service_ops_t static_vad_ops;
    static rac_embeddings_service_ops_t static_embeddings_ops;
    static rac_diffusion_service_ops_t static_diffusion_ops;
    static rac_engine_vtable_t static_vtable;

    static_stt_ops = stt_ops;
    static_tts_ops = tts_ops;
    static_vad_ops = vad_ops;
    static_embeddings_ops = embeddings_ops;
    static_diffusion_ops = diffusion_ops;
    static_vtable = make_mock_vtable(&static_stt_ops, &static_tts_ops, &static_vad_ops,
                                     &static_embeddings_ops, &static_diffusion_ops);

    (void)rac_plugin_unregister("onnx");
    return rac_plugin_register(&static_vtable) == RAC_SUCCESS;
}

int test_lifecycle_proto_operations(rac_model_registry_handle_t registry) {
    rac_model_lifecycle_reset();
    CHECK(install_mock_plugin(), "mock non-LLM lifecycle plugin registers");

    CHECK(register_model(registry, build_model("lifecycle.stt",
                                               runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION)),
          "STT lifecycle model registers");
    CHECK(register_model(registry, build_model("lifecycle.tts",
                                               runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS)),
          "TTS lifecycle model registers");
    CHECK(register_model(registry,
                         build_model("lifecycle.vad",
                                     runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION)),
          "VAD lifecycle model registers");
    CHECK(register_model(registry, build_model("lifecycle.embeddings",
                                               runanywhere::v1::MODEL_CATEGORY_EMBEDDING)),
          "embeddings lifecycle model registers");
    CHECK(register_model(registry, build_model("lifecycle.diffusion",
                                               runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION)),
          "diffusion lifecycle model registers");

    CHECK(load_model(registry, "lifecycle.stt"), "STT lifecycle model loads");
    CHECK(load_model(registry, "lifecycle.tts"), "TTS lifecycle model loads");
    CHECK(load_model(registry, "lifecycle.vad"), "VAD lifecycle model loads");
    CHECK(load_model(registry, "lifecycle.embeddings"), "embeddings lifecycle model loads");
    CHECK(load_model(registry, "lifecycle.diffusion"), "diffusion lifecycle model loads");

    int16_t stt_samples[] = {0, 1200, -1200, 0};
    runanywhere::v1::STTTranscriptionRequest stt_request;
    stt_request.set_request_id("stt-1");
    auto* stt_audio = stt_request.mutable_audio();
    stt_audio->set_audio_data(reinterpret_cast<const char*>(stt_samples), sizeof(stt_samples));
    stt_audio->set_encoding(runanywhere::v1::STT_AUDIO_ENCODING_PCM_S16_LE);
    stt_audio->set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM);
    stt_audio->set_sample_rate(16000);
    stt_request.mutable_options()->set_language_code("en-US");
    std::vector<uint8_t> bytes;
    CHECK(serialize(stt_request, &bytes), "STT lifecycle request serializes");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_stt_transcribe_lifecycle_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::STTOutput stt_output;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &stt_output),
          "STT lifecycle ABI returns STTOutput");
    CHECK(stt_output.text() == "hello lifecycle", "STT lifecycle ABI uses loaded STT ops");
    CHECK(stt_output.metadata().model_id() == "lifecycle.stt",
          "STT lifecycle output carries loaded model id");
    rac_proto_buffer_free(&out);

    // Lifecycle-owned STT streaming should emit the canonical STTStreamEvent
    // envelope (STARTED → PARTIAL → FINAL) off the mock backend's
    // transcribe_stream callbacks.
    {
        std::vector<runanywhere::v1::STTStreamEvent> stream_events;
        auto stream_cb = [](const uint8_t* data, size_t size, void* user_data) {
            auto* out = static_cast<std::vector<runanywhere::v1::STTStreamEvent>*>(user_data);
            runanywhere::v1::STTStreamEvent event;
            if (event.ParseFromArray(data, static_cast<int>(size))) {
                out->push_back(event);
            }
        };
        std::vector<uint8_t> stream_bytes;
        CHECK(serialize(stt_request, &stream_bytes), "STT lifecycle stream request serializes");
        rc = rac_stt_transcribe_stream_lifecycle_proto(stream_bytes.data(), stream_bytes.size(),
                                                       stream_cb, &stream_events);
        CHECK(rc == RAC_SUCCESS, "STT lifecycle stream ABI returns success");
        CHECK(stream_events.size() == 3,
              "STT lifecycle stream ABI emits started, partial and final events");
        if (stream_events.size() == 3) {
            CHECK(stream_events[0].kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_STARTED &&
                      stream_events[0].seq() == 1,
                  "STT lifecycle stream first event is STARTED with seq=1");
            CHECK(stream_events[1].kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL &&
                      stream_events[1].has_partial() &&
                      stream_events[1].partial().text() == "stream-draft" &&
                      !stream_events[1].partial().is_final(),
                  "STT lifecycle stream second event is PARTIAL with draft text");
            CHECK(stream_events[2].kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL &&
                      stream_events[2].has_partial() && stream_events[2].partial().is_final() &&
                      stream_events[2].has_final_output() &&
                      stream_events[2].final_output().text() == "stream-final",
                  "STT lifecycle stream third event is FINAL with final text");
            CHECK(stream_events[0].seq() == 1 && stream_events[1].seq() == 2 &&
                      stream_events[2].seq() == 3,
                  "STT lifecycle stream sequence is monotonic");
            const std::string request_id = stream_events[0].request_id();
            CHECK(!request_id.empty() && stream_events[1].request_id() == request_id &&
                      stream_events[2].request_id() == request_id,
                  "STT lifecycle stream request_id is stable across events");
        }
    }

    runanywhere::v1::TTSSynthesisRequest tts_request;
    tts_request.set_request_id("tts-1");
    tts_request.set_text("hello");
    tts_request.mutable_options()->set_voice("voice-a");
    tts_request.mutable_options()->set_language_code("en-US");
    tts_request.mutable_options()->set_sample_rate(24000);
    CHECK(serialize(tts_request, &bytes), "TTS lifecycle request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_tts_synthesize_lifecycle_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::TTSOutput tts_output;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &tts_output),
          "TTS lifecycle ABI returns TTSOutput");
    CHECK(tts_output.audio_data().size() == 8, "TTS lifecycle ABI uses loaded TTS ops");
    CHECK(tts_output.sample_rate() == 24000, "TTS lifecycle ABI preserves TTS sample rate");
    CHECK(tts_output.metadata().voice_id() == "voice-a",
          "TTS lifecycle output carries requested voice id");
    CHECK(tts_output.is_final(), "TTS lifecycle output marks one-shot result final");
    rac_proto_buffer_free(&out);

    float vad_samples[] = {0.0f, 0.4f, -0.4f, 0.0f};
    runanywhere::v1::VADProcessRequest vad_request;
    vad_request.set_request_id("vad-1");
    auto* vad_audio = vad_request.mutable_audio();
    vad_audio->set_audio_data(reinterpret_cast<const char*>(vad_samples), sizeof(vad_samples));
    vad_audio->set_encoding(runanywhere::v1::VAD_AUDIO_ENCODING_PCM_F32_LE);
    vad_audio->set_sample_rate(16000);
    vad_audio->set_channels(1);
    vad_request.mutable_options()->set_threshold(0.1f);
    CHECK(serialize(vad_request, &bytes), "VAD lifecycle request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_vad_process_lifecycle_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::VADResult vad_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &vad_result),
          "VAD lifecycle ABI returns VADResult");
    CHECK(vad_result.is_speech(), "VAD lifecycle ABI uses loaded VAD ops");
    CHECK(vad_result.duration_ms() > 0, "VAD lifecycle result carries duration");
    rac_proto_buffer_free(&out);

    runanywhere::v1::EmbeddingsRequest embeddings_request;
    embeddings_request.set_request_id("emb-1");
    embeddings_request.set_model_id("lifecycle.embeddings");
    embeddings_request.add_texts("alpha");
    embeddings_request.add_texts("beta");
    embeddings_request.mutable_options()->set_normalize(true);
    CHECK(serialize(embeddings_request, &bytes), "embeddings lifecycle request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_embeddings_embed_batch_lifecycle_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::EmbeddingsResult embeddings_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &embeddings_result),
          "embeddings lifecycle ABI returns EmbeddingsResult");
    CHECK(embeddings_result.vectors_size() == 2,
          "embeddings lifecycle ABI uses loaded embeddings ops");
    CHECK(embeddings_result.model_id() == "lifecycle.embeddings",
          "embeddings lifecycle result carries loaded model id");
    CHECK(embeddings_result.vectors(0).text() == "alpha",
          "embeddings lifecycle result preserves input text");
    rac_proto_buffer_free(&out);

    runanywhere::v1::DiffusionGenerationRequest diffusion_request;
    diffusion_request.set_request_id("diff-1");
    diffusion_request.set_model_id("lifecycle.diffusion");
    auto* diffusion_options = diffusion_request.mutable_options();
    diffusion_options->set_prompt("a lifecycle image");
    diffusion_options->set_width(4);
    diffusion_options->set_height(2);
    diffusion_options->set_num_inference_steps(1);
    diffusion_options->set_seed(123);
    CHECK(serialize(diffusion_request, &bytes), "diffusion lifecycle request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_diffusion_generate_lifecycle_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::DiffusionResult diffusion_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &diffusion_result),
          "diffusion lifecycle ABI returns DiffusionResult");
    CHECK(diffusion_result.width() == 4 && diffusion_result.height() == 2,
          "diffusion lifecycle ABI uses loaded diffusion ops");
    CHECK(diffusion_result.image_data().size() == 32,
          "diffusion lifecycle result carries generated bytes");
    rac_proto_buffer_free(&out);

    embeddings_request.set_model_id("other.embeddings");
    CHECK(serialize(embeddings_request, &bytes), "embeddings mismatched model request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_embeddings_embed_batch_lifecycle_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_ERROR_INVALID_ARGUMENT && out.status == RAC_ERROR_INVALID_ARGUMENT,
          "embeddings lifecycle ABI rejects mismatched model id");
    rac_proto_buffer_free(&out);

    rac_model_lifecycle_reset();
    rac_plugin_unregister("onnx");
    return 0;
}

int test_portable_source_blockers() {
    runanywhere::v1::STTTranscriptionRequest stt_request;
    stt_request.mutable_audio()->set_file_uri("file:///tmp/audio.wav");
    std::vector<uint8_t> bytes;
    CHECK(serialize(stt_request, &bytes), "STT file-uri request serializes");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_stt_transcribe_lifecycle_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_ERROR_NOT_SUPPORTED && out.status == RAC_ERROR_NOT_SUPPORTED,
          "STT lifecycle ABI rejects native file URI source");
    rac_proto_buffer_free(&out);

    runanywhere::v1::VADProcessRequest vad_request;
    vad_request.mutable_audio()->set_adapter_handle("native-vad-stream");
    CHECK(serialize(vad_request, &bytes), "VAD adapter-handle request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_vad_process_lifecycle_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_ERROR_NOT_SUPPORTED && out.status == RAC_ERROR_NOT_SUPPORTED,
          "VAD lifecycle ABI rejects native adapter handle source");
    rac_proto_buffer_free(&out);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    try {
        std::fprintf(stdout, "test_nonllm_lifecycle_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
        std::fprintf(stdout, "  skip: non-LLM lifecycle proto ABI tests (no protobuf)\n");
        return 0;
#else
        rac_model_registry_handle_t registry = nullptr;
        CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
              "model registry creates");

        test_lifecycle_proto_operations(registry);
        test_portable_source_blockers();

        rac_model_lifecycle_reset();
        rac_plugin_unregister("onnx");
        rac_model_registry_destroy(registry);
        std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
        return fail_count == 0 ? 0 : 1;
#endif
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: uncaught exception: %s\n", e.what());
        return 1;
    } catch (...) {
        std::fprintf(stderr, "FATAL: uncaught unknown exception\n");
        return 1;
    }
}
