/**
 * @file model_info_make_proto.cpp
 * @brief Canonical RAModelInfo factory.
 *
 * Commons-owned implementation of Swift's RAModelInfo.make(...) which lives
 * in sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/
 * ModelTypes+Artifacts.swift. Every field-set in this file mirrors the
 * Swift implementation 1:1 so the Swift extension can be deleted.
 *
 * Field semantics summary:
 *   id, name             — derived from URL via rac_model_generate_id /
 *                          rac_model_generate_name when not supplied.
 *   category, format,
 *   framework            — defaulted from URL extension and framework→category
 *                          mapping (rac_model_detect_*).
 *   download_url         — request.url verbatim.
 *   download_size_bytes  — 0 (RAModelInfo.make does not accept it as an input;
 *                          callers fill via the registry update path).
 *   context_length       — 2048 when category requires it, else 0.
 *   supports_thinking    — false (gated on category — make() takes
 *                          supportsThinking as input but only retains it when
 *                          the category supports thinking; the make-request
 *                          omits the per-call boolean and defaults to false).
 *   thinking_pattern     — <think>/</think> only when supports_thinking is
 *                          true (which never fires here without a per-call
 *                          flag, but the implementation still gates the
 *                          field for parity).
 *   artifact             — archive when ArchiveType.from(url) yields a known
 *                          archive type; else single_file.
 *   artifact_type        — derived from artifact branch.
 *   expected_files       — left empty (default artifacts have empty manifest;
 *                          Swift only sets it when the manifest is non-empty).
 *   description          — left empty (request omits description).
 *   source               — request.source when non-UNSPECIFIED, else REMOTE.
 *   created_at_unix_ms,
 *   updated_at_unix_ms   — current Unix-epoch milliseconds.
 *   is_downloaded        — false (no local_path is supplied via this factory).
 *   is_available         — false (mirror Swift behaviour: isAvailableForUse
 *                          returns isBuiltIn || isDownloadedOnDisk || isAvailable;
 *                          all three are false on a fresh make() call).
 *
 * The platform-adapter is_non_empty_directory probe is not exercised by the
 * default make() flow because local_path is empty; it is wired through
 * rac_path_is_non_empty_directory() so SDKs and tests can share the probe
 * semantics, and the disk-state computation below honours it in case future
 * variants of make() ever set local_path.
 */

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

#define LOG_CAT "ModelInfoMakeProto"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize ModelInfo result");
}

// ---------------------------------------------------------------------------
// Enum converters (mirrors model_registry.cpp static helpers — duplicated
// here to keep this TU self-contained and avoid touching model_registry.cpp
// while another agent is working on it).
// ---------------------------------------------------------------------------

runanywhere::v1::ModelCategory model_category_to_proto(rac_model_category_t c) {
    switch (c) {
        case RAC_MODEL_CATEGORY_LANGUAGE:
            return runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
        case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION;
        case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS;
        case RAC_MODEL_CATEGORY_VISION:
            return runanywhere::v1::MODEL_CATEGORY_VISION;
        case RAC_MODEL_CATEGORY_IMAGE_GENERATION:
            return runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION;
        case RAC_MODEL_CATEGORY_MULTIMODAL:
            return runanywhere::v1::MODEL_CATEGORY_MULTIMODAL;
        case RAC_MODEL_CATEGORY_AUDIO:
            return runanywhere::v1::MODEL_CATEGORY_AUDIO;
        case RAC_MODEL_CATEGORY_EMBEDDING:
            return runanywhere::v1::MODEL_CATEGORY_EMBEDDING;
        case RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            return runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
        default:
            return runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
    }
}

rac_model_category_t model_category_from_proto(runanywhere::v1::ModelCategory c) {
    switch (c) {
        case runanywhere::v1::MODEL_CATEGORY_LANGUAGE:
            return RAC_MODEL_CATEGORY_LANGUAGE;
        case runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION:
            return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
        case runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS:
            return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
        case runanywhere::v1::MODEL_CATEGORY_VISION:
            return RAC_MODEL_CATEGORY_VISION;
        case runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION:
            return RAC_MODEL_CATEGORY_IMAGE_GENERATION;
        case runanywhere::v1::MODEL_CATEGORY_MULTIMODAL:
            return RAC_MODEL_CATEGORY_MULTIMODAL;
        case runanywhere::v1::MODEL_CATEGORY_AUDIO:
            return RAC_MODEL_CATEGORY_AUDIO;
        case runanywhere::v1::MODEL_CATEGORY_EMBEDDING:
            return RAC_MODEL_CATEGORY_EMBEDDING;
        case runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            return RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
        default:
            return RAC_MODEL_CATEGORY_UNKNOWN;
    }
}

runanywhere::v1::ModelFormat model_format_to_proto(rac_model_format_t f) {
    return static_cast<runanywhere::v1::ModelFormat>(static_cast<int>(f));
}

runanywhere::v1::InferenceFramework inference_framework_to_proto(rac_inference_framework_t f) {
    switch (f) {
        case RAC_FRAMEWORK_ONNX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        case RAC_FRAMEWORK_LLAMACPP:
            return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS;
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO;
        case RAC_FRAMEWORK_BUILTIN:
            return runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN;
        case RAC_FRAMEWORK_NONE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_NONE;
        case RAC_FRAMEWORK_MLX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
        case RAC_FRAMEWORK_COREML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        case RAC_FRAMEWORK_SHERPA:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
        case RAC_FRAMEWORK_QHEXRT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
        default:
            return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
    }
}

rac_inference_framework_t inference_framework_from_proto(runanywhere::v1::InferenceFramework f) {
    switch (f) {
        case runanywhere::v1::INFERENCE_FRAMEWORK_ONNX:
            return RAC_FRAMEWORK_ONNX;
        case runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            return RAC_FRAMEWORK_LLAMACPP;
        case runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
            return RAC_FRAMEWORK_FOUNDATION_MODELS;
        case runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
            return RAC_FRAMEWORK_SYSTEM_TTS;
        case runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO:
            return RAC_FRAMEWORK_FLUID_AUDIO;
        case runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN:
            return RAC_FRAMEWORK_BUILTIN;
        case runanywhere::v1::INFERENCE_FRAMEWORK_NONE:
            return RAC_FRAMEWORK_NONE;
        case runanywhere::v1::INFERENCE_FRAMEWORK_MLX:
            return RAC_FRAMEWORK_MLX;
        case runanywhere::v1::INFERENCE_FRAMEWORK_COREML:
            return RAC_FRAMEWORK_COREML;
        case runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA:
            return RAC_FRAMEWORK_SHERPA;
        case runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT:
            return RAC_FRAMEWORK_QHEXRT;
        default:
            return RAC_FRAMEWORK_UNKNOWN;
    }
}

// ---------------------------------------------------------------------------
// URL → file extension helper. Strips query/fragment, then takes the suffix
// after the LAST '.' in the last path component. Mirrors Swift URL.pathExtension
// for the common case of HTTPS catalog URLs.
// ---------------------------------------------------------------------------
std::string strip_url_noise(const std::string& url) {
    size_t cut = url.find_first_of("?#");
    return cut == std::string::npos ? url : url.substr(0, cut);
}

std::string url_path_extension(const std::string& url) {
    const std::string clean = strip_url_noise(url);
    if (clean.empty()) {
        return "";
    }
    // Last path component.
    size_t slash = clean.find_last_of("/\\");
    const std::string last = (slash == std::string::npos) ? clean : clean.substr(slash + 1);
    size_t dot = last.find_last_of('.');
    if (dot == std::string::npos || dot + 1 >= last.size()) {
        return "";
    }
    std::string ext = last.substr(dot + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return ext;
}

bool ends_with(const std::string& s, const char* suffix) {
    const size_t suffix_len = std::strlen(suffix);
    if (s.size() < suffix_len) {
        return false;
    }
    return s.compare(s.size() - suffix_len, suffix_len, suffix) == 0;
}

// ---------------------------------------------------------------------------
// ArchiveType.from(url:) — Swift parity. NONE → no archive detected.
// ---------------------------------------------------------------------------
rac_archive_type_t archive_type_from_url(const std::string& url) {
    std::string lower = strip_url_noise(url);
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (ends_with(lower, ".tar.bz2") || ends_with(lower, ".tbz2")) {
        return RAC_ARCHIVE_TYPE_TAR_BZ2;
    }
    if (ends_with(lower, ".tar.gz") || ends_with(lower, ".tgz")) {
        return RAC_ARCHIVE_TYPE_TAR_GZ;
    }
    if (ends_with(lower, ".tar.xz") || ends_with(lower, ".txz")) {
        return RAC_ARCHIVE_TYPE_TAR_XZ;
    }
    if (ends_with(lower, ".zip")) {
        return RAC_ARCHIVE_TYPE_ZIP;
    }
    return RAC_ARCHIVE_TYPE_NONE;
}

runanywhere::v1::ArchiveType archive_type_to_proto(rac_archive_type_t t) {
    switch (t) {
        case RAC_ARCHIVE_TYPE_ZIP:
            return runanywhere::v1::ARCHIVE_TYPE_ZIP;
        case RAC_ARCHIVE_TYPE_TAR_BZ2:
            return runanywhere::v1::ARCHIVE_TYPE_TAR_BZ2;
        case RAC_ARCHIVE_TYPE_TAR_GZ:
            return runanywhere::v1::ARCHIVE_TYPE_TAR_GZ;
        case RAC_ARCHIVE_TYPE_TAR_XZ:
            return runanywhere::v1::ARCHIVE_TYPE_TAR_XZ;
        default:
            return runanywhere::v1::ARCHIVE_TYPE_UNSPECIFIED;
    }
}

runanywhere::v1::ModelArtifactType artifact_type_from_archive(rac_archive_type_t t) {
    switch (t) {
        case RAC_ARCHIVE_TYPE_ZIP:
            return runanywhere::v1::MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE;
        case RAC_ARCHIVE_TYPE_TAR_BZ2:
            return runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE;
        case RAC_ARCHIVE_TYPE_TAR_GZ:
            return runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE;
        case RAC_ARCHIVE_TYPE_TAR_XZ:
            return runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE;
        default:
            return runanywhere::v1::MODEL_ARTIFACT_TYPE_ARCHIVE;
    }
}

int64_t now_unix_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" rac_bool_t rac_path_is_non_empty_directory(const char* path) {
    if (!path || !*path) {
        return RAC_FALSE;
    }

    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (!adapter) {
        return RAC_FALSE;
    }

    // Preferred path: dedicated probe callback.
    if (adapter->is_non_empty_directory) {
        return adapter->is_non_empty_directory(path, adapter->user_data);
    }

    // Fallback path: list_directory two-call enumeration. Capacity query
    // alone tells us whether any entries exist; we never need to allocate
    // the full entry array.
    if (adapter->file_list_directory) {
        size_t count = 0;
        rac_result_t rc =
            adapter->file_list_directory(path, /*out_entries=*/nullptr, &count, adapter->user_data);
        if (rc == RAC_SUCCESS && count > 0) {
            return RAC_TRUE;
        }
        return RAC_FALSE;
    }

    return RAC_FALSE;
}

extern "C" rac_result_t rac_model_info_make_proto(const uint8_t* in_request_bytes,
                                                  size_t in_request_size,
                                                  rac_proto_buffer_t* out_proto) {
    if (!out_proto) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_request_bytes;
    (void)in_request_size;
    return rac_proto_buffer_set_error(out_proto, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(in_request_bytes, in_request_size)) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "ModelInfoMakeRequest bytes are invalid");
    }

    runanywhere::v1::ModelInfoMakeRequest request;
    if (in_request_size > 0 &&
        !request.ParseFromArray(parse_data(in_request_bytes, in_request_size),
                                static_cast<int>(in_request_size))) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ModelInfoMakeRequest");
    }

    const std::string url = request.url();

    // -------------------------------------------------------------------------
    // 1) Resolve format from URL extension.
    // -------------------------------------------------------------------------
    rac_model_format_t format = RAC_MODEL_FORMAT_UNSPECIFIED;
    {
        const std::string ext = url_path_extension(url);
        if (!ext.empty()) {
            (void)rac_model_detect_format_from_extension(ext.c_str(), &format);
        }
    }

    // -------------------------------------------------------------------------
    // 2) Resolve framework — request override → format → UNKNOWN.
    // -------------------------------------------------------------------------
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    if (request.has_framework() &&
        request.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
        framework = inference_framework_from_proto(request.framework());
    } else {
        rac_inference_framework_t detected = RAC_FRAMEWORK_UNKNOWN;
        if (rac_model_detect_framework_from_format(format, &detected) == RAC_TRUE) {
            framework = detected;
        }
    }

    // -------------------------------------------------------------------------
    // 3) Resolve category — request override → framework default.
    // -------------------------------------------------------------------------
    rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
    if (request.has_category() &&
        request.category() != runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED) {
        category = model_category_from_proto(request.category());
    } else {
        category = rac_model_category_from_framework(framework);
    }

    // -------------------------------------------------------------------------
    // 4) Resolve source — request override → REMOTE.
    // -------------------------------------------------------------------------
    runanywhere::v1::ModelSource source = runanywhere::v1::MODEL_SOURCE_REMOTE;
    if (request.has_source() && request.source() != runanywhere::v1::MODEL_SOURCE_UNSPECIFIED) {
        source = request.source();
    }

    // -------------------------------------------------------------------------
    // 5) Resolve id — strip known extensions from URL filename.
    // -------------------------------------------------------------------------
    std::string id;
    {
        char buf[512];
        rac_model_generate_id(url.c_str(), buf, sizeof(buf));
        id = buf;
    }

    // -------------------------------------------------------------------------
    // 6) Resolve name — request.name when non-empty, else generate from URL.
    // -------------------------------------------------------------------------
    std::string name = request.name();
    if (name.empty()) {
        char buf[512];
        rac_model_generate_name(url.c_str(), buf, sizeof(buf));
        name = buf;
    }

    // -------------------------------------------------------------------------
    // 7) Compose the ModelInfo proto.
    // -------------------------------------------------------------------------
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(name);
    model.set_category(model_category_to_proto(category));
    model.set_format(model_format_to_proto(format));
    model.set_framework(inference_framework_to_proto(framework));
    model.set_download_url(url);
    model.set_local_path("");
    model.set_download_size_bytes(0);

    // Context length: 2048 when the category requires it, else 0. Mirrors
    // Swift's `Int32(contextLength ?? (category.requiresContextLength ? 2048 : 0))`.
    const bool requires_ctx = rac_model_category_requires_context_length(category) == RAC_TRUE;
    model.set_context_length(requires_ctx ? 2048 : 0);

    // Thinking gating mirrors Swift: `model.supportsThinking =
    // category.supportsThinking ? supportsThinking : false`. The factory
    // request does not carry a per-call thinking boolean, so the input is
    // always false; the gating call is retained as documentation of the
    // Swift parity rule and is referenced once via void cast so the compiler
    // does not warn it away.
    (void)rac_model_category_supports_thinking(category);
    const bool supports_thinking = false;
    model.set_supports_thinking(supports_thinking);
    if (supports_thinking) {
        // Default <think>/</think> pattern. Mirrors Swift's
        // `RAThinkingTagPattern.defaultPattern`.
        runanywhere::v1::ThinkingTagPattern* pattern = model.mutable_thinking_pattern();
        pattern->set_open_tag("<think>");
        pattern->set_close_tag("</think>");
    }

    model.set_supports_lora(false);
    model.set_description("");
    model.set_source(source);
    const int64_t now_ms = now_unix_ms();
    model.set_created_at_unix_ms(now_ms);
    model.set_updated_at_unix_ms(now_ms);

    // -------------------------------------------------------------------------
    // 8) Artifact inference. Swift: ArchiveType.from(url:) → archive() else
    //    singleFile(). artifact_type tracks the artifact branch for callers
    //    that consume the coarse classification.
    // -------------------------------------------------------------------------
    const rac_archive_type_t archive =
        url.empty() ? RAC_ARCHIVE_TYPE_NONE : archive_type_from_url(url);
    if (archive != RAC_ARCHIVE_TYPE_NONE) {
        runanywhere::v1::ArchiveArtifact* artifact = model.mutable_archive();
        artifact->set_type(archive_type_to_proto(archive));
        artifact->set_structure(runanywhere::v1::ARCHIVE_STRUCTURE_UNKNOWN);
        model.set_artifact_type(artifact_type_from_archive(archive));
    } else {
        model.mutable_single_file();
        model.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    }
    // expected_files left unset: Swift only assigns when the manifest is
    // non-empty (`!expected.isEmptyManifest`). Default artifacts have empty
    // patterns, so isEmptyManifest is true.

    // -------------------------------------------------------------------------
    // 9) Disk-state probe. Swift's RAModelInfo.make() does:
    //      model.isDownloaded = model.isDownloadedOnDisk
    //      model.isAvailable  = model.isAvailableForUse
    //    where isDownloadedOnDisk inspects local_path. Because the factory
    //    doesn't accept a localPath, both fields collapse to false unless the
    //    caller is a built-in model. We still consult the platform adapter via
    //    rac_path_is_non_empty_directory() so the probe is exercised when
    //    callers later assign a non-empty local_path before re-calling the
    //    factory; this keeps the implementation forward-compatible.
    // -------------------------------------------------------------------------
    const std::string& local_path = model.local_path();
    bool is_downloaded = false;
    if (!local_path.empty()) {
        // local_path is set — re-check disk via platform adapter.
        is_downloaded = (rac_path_is_non_empty_directory(local_path.c_str()) == RAC_TRUE);
        if (!is_downloaded) {
            // Single-file artifacts: file_exists is sufficient. The directory
            // probe returns FALSE for files, so consult file_exists as a
            // secondary check.
            const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
            if (adapter && adapter->file_exists &&
                adapter->file_exists(local_path.c_str(), adapter->user_data) == RAC_TRUE) {
                is_downloaded = true;
            }
        }
    }
    model.set_is_downloaded(is_downloaded);
    model.set_is_available(is_downloaded);

    RAC_LOG_DEBUG(LOG_CAT,
                  "make: url=%s id=%s name=%s fw=%d cat=%d fmt=%d "
                  "artifact_type=%d ctx=%d supports_thinking=%d",
                  url.c_str(), id.c_str(), name.c_str(), static_cast<int>(framework),
                  static_cast<int>(category), static_cast<int>(format),
                  static_cast<int>(model.artifact_type()), static_cast<int>(model.context_length()),
                  static_cast<int>(supports_thinking));

    return copy_proto(model, out_proto);
#endif
}
