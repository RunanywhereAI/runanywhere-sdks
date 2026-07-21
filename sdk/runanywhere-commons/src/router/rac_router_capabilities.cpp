/**
 * @file rac_router_capabilities.cpp
 * @brief Proto-byte C ABI for engine-router capability queries.
 *
 * Single commons-owned implementation of the
 * `SDKComponent → [InferenceFramework]` lookup. Enumerates the engine-router
 * plugin registry for the primitives mapped from the requested
 * SDKComponent, maps each plugin's metadata.name to an InferenceFramework
 * enum, and returns the ordered de-duplicated list.
 */

#include "rac/router/rac_router_capabilities.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <ranges>
#include <string>
#include <string_view>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#include "router.pb.h"
#include "sdk_events.pb.h"
#endif

#define LOG_CAT "Router.Capabilities"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

std::string to_lower(std::string_view s) {
    std::string out(s);
    std::ranges::transform(out, out.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
}

/* Local plugin-name → InferenceFramework heuristic for capability reporting. */
runanywhere::v1::InferenceFramework framework_for_plugin(const rac_engine_vtable_t* vt) {
    if (!vt || !vt->metadata.name) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
    }
    const std::string name = to_lower(vt->metadata.name);
    if (name.find("onnx") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
    }
    if (name.find("llama") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
    }
    if (name.find("coreml") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
    }
    if (name.find("mlx") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
    }
    if (name.find("qhexrt") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
    }
    if (name.find("sherpa") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
    }
    if (name.find("piper") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_PIPER_TTS;
    }
    return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
}

/* Component → ordered set of primitives this component can be served by.
 * VOICE_AGENT spans LLM/STT/TTS/VAD because the voice pipeline composes all
 * four; this matches the pre-fix Kotlin mapping in
 * `RunAnywhere+Frameworks.jvmAndroid.kt`. */
std::vector<rac_primitive_t> primitives_for_component(runanywhere::v1::SDKComponent component) {
    switch (component) {
        case runanywhere::v1::SDK_COMPONENT_LLM:
            return {RAC_PRIMITIVE_GENERATE_TEXT};
        case runanywhere::v1::SDK_COMPONENT_VLM:
            return {RAC_PRIMITIVE_VLM};
        case runanywhere::v1::SDK_COMPONENT_STT:
            return {RAC_PRIMITIVE_TRANSCRIBE};
        case runanywhere::v1::SDK_COMPONENT_TTS:
            return {RAC_PRIMITIVE_SYNTHESIZE};
        case runanywhere::v1::SDK_COMPONENT_VAD:
            return {RAC_PRIMITIVE_DETECT_VOICE};
        case runanywhere::v1::SDK_COMPONENT_EMBEDDINGS:
            return {RAC_PRIMITIVE_EMBED};
        case runanywhere::v1::SDK_COMPONENT_DIFFUSION:
            return {RAC_PRIMITIVE_DIFFUSION};
        case runanywhere::v1::SDK_COMPONENT_SPEAKER_DIARIZATION:
            return {RAC_PRIMITIVE_DIARIZE};
        case runanywhere::v1::SDK_COMPONENT_SEMANTIC_SEGMENTATION:
            return {RAC_PRIMITIVE_SEGMENT};
        case runanywhere::v1::SDK_COMPONENT_VOICE_AGENT:
            return {RAC_PRIMITIVE_GENERATE_TEXT, RAC_PRIMITIVE_TRANSCRIBE, RAC_PRIMITIVE_SYNTHESIZE,
                    RAC_PRIMITIVE_DETECT_VOICE};
        case runanywhere::v1::SDK_COMPONENT_RAG:
            /* RAG composes LLM generation + (optional) embeddings. */
            return {RAC_PRIMITIVE_GENERATE_TEXT, RAC_PRIMITIVE_EMBED};
        case runanywhere::v1::SDK_COMPONENT_WAKEWORD:
        case runanywhere::v1::SDK_COMPONENT_UNSPECIFIED:
        default:
            return {};
    }
}

/* Snapshot the registry for one primitive via the public C ABI. The cap is
 * generous — no realistic deployment has more engines per primitive. */
std::vector<const rac_engine_vtable_t*> list_plugins_for_primitive(rac_primitive_t p) {
    constexpr size_t kMax = 64;
    const rac_engine_vtable_t* buf[kMax] = {nullptr};
    size_t n = 0;
    if (rac_plugin_list(p, buf, kMax, &n) != RAC_SUCCESS) {
        return {};
    }
    std::vector<const rac_engine_vtable_t*> out;
    out.reserve(n);
    for (size_t i = 0; i < n; ++i) {
        if (buf[i] != nullptr)
            out.push_back(buf[i]);
    }
    return out;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" rac_result_t rac_router_frameworks_for_capability_proto(const uint8_t* request_bytes,
                                                                   size_t request_size,
                                                                   uint8_t** out_response_bytes,
                                                                   size_t* out_response_size) {
    if (out_response_bytes == nullptr || out_response_size == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_response_bytes = nullptr;
    *out_response_size = 0;

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (request_bytes == nullptr && request_size != 0) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::FrameworksForCapabilityRequest request;
    if (request_size > 0 &&
        !request.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        RAC_LOG_WARNING(LOG_CAT, "failed to parse FrameworksForCapabilityRequest (%zu bytes)",
                        request_size);
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::FrameworksForCapabilityResponse response;
    const auto primitives = primitives_for_component(request.component());
    if (!primitives.empty()) {
        /* Collect frameworks in registry order (priority desc), deduped with
         * first-seen preservation. A small vector linear-scan is cheaper than
         * a set here — the cardinality is tiny (< 10 total frameworks). */
        std::vector<runanywhere::v1::InferenceFramework> ordered;
        for (rac_primitive_t p : primitives) {
            const auto plugins = list_plugins_for_primitive(p);
            for (const auto* vt : plugins) {
                const auto framework = framework_for_plugin(vt);
                if (framework == runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
                    continue;
                }
                if (std::ranges::find(ordered, framework) == ordered.end()) {
                    ordered.push_back(framework);
                }
            }
        }
        for (const auto f : ordered) {
            response.add_frameworks(f);
        }
    }

    const size_t size = response.ByteSizeLong();
    auto* bytes = static_cast<uint8_t*>(std::malloc(size == 0 ? 1 : size));
    if (bytes == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "malloc failed for %zu response bytes", size);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    if (size > 0 && !response.SerializeToArray(bytes, static_cast<int>(size))) {
        std::free(bytes);
        RAC_LOG_ERROR(LOG_CAT, "failed to serialize FrameworksForCapabilityResponse");
        return RAC_ERROR_ENCODING_ERROR;
    }
    *out_response_bytes = bytes;
    *out_response_size = size;
    RAC_LOG_DEBUG(LOG_CAT, "component=%d frameworks_returned=%d bytes=%zu",
                  static_cast<int>(request.component()), response.frameworks_size(), size);
    return RAC_SUCCESS;
#endif
}

extern "C" void rac_router_frameworks_for_capability_proto_free(uint8_t* response_bytes) {
    std::free(response_bytes);
}
