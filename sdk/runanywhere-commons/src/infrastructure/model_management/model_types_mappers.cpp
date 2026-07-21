/**
 * @file model_types_mappers.cpp
 * @brief Proto enum ↔ C enum mapper implementations (T15a / SWIFT-DUP-MODELTYPES-COMPUTED).
 *
 * Pure switch-table translations between the proto-wire int32 enum values
 * declared in idl/model_types.proto and the corresponding rac_*_t C enum
 * values. No global state; each mapper is a thin, side-effect-free function.
 *
 * Proto numeric values are hard-coded here as compile-time constants — these
 * match runanywhere.v1.* in idl/model_types.proto and are also mirrored by
 * the generated *.pb.h headers. Keeping them as literals avoids pulling the
 * (heavyweight) generated protobuf header into a tiny mapper unit.
 */

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

// ---------------------------------------------------------------------------
// Proto enum integer values (mirrors runanywhere.v1 in idl/model_types.proto).
// ---------------------------------------------------------------------------

namespace {

// InferenceFramework
constexpr int32_t kProtoIfwUnspecified = 0;
constexpr int32_t kProtoIfwOnnx = 1;
constexpr int32_t kProtoIfwLlamaCpp = 2;
constexpr int32_t kProtoIfwFoundationModels = 3;
constexpr int32_t kProtoIfwSystemTts = 4;
constexpr int32_t kProtoIfwFluidAudio = 5;
constexpr int32_t kProtoIfwCoreml = 6;
constexpr int32_t kProtoIfwMlx = 7;
// Proto value 8 and values 9-10 retired — gaps preserved.
constexpr int32_t kProtoIfwTflite = 11;
constexpr int32_t kProtoIfwExecutorch = 12;
constexpr int32_t kProtoIfwMediapipe = 13;
constexpr int32_t kProtoIfwMlc = 14;
constexpr int32_t kProtoIfwPicoLlm = 15;
constexpr int32_t kProtoIfwPiperTts = 16;
// Proto values 17 (WHISPERKIT) and 18 (OPENAI_WHISPER) retired — gaps preserved.
constexpr int32_t kProtoIfwSwiftTransformers = 19;
constexpr int32_t kProtoIfwBuiltIn = 20;
constexpr int32_t kProtoIfwNone = 21;
constexpr int32_t kProtoIfwUnknown = 22;
constexpr int32_t kProtoIfwSherpa = 23;
constexpr int32_t kProtoIfwQhexrt = 24;

// ModelCategory
constexpr int32_t kProtoMcUnspecified = 0;
constexpr int32_t kProtoMcLanguage = 1;
constexpr int32_t kProtoMcSpeechRecognition = 2;
constexpr int32_t kProtoMcSpeechSynthesis = 3;
constexpr int32_t kProtoMcVision = 4;
constexpr int32_t kProtoMcImageGeneration = 5;
constexpr int32_t kProtoMcMultimodal = 6;
constexpr int32_t kProtoMcAudio = 7;
constexpr int32_t kProtoMcEmbedding = 8;
constexpr int32_t kProtoMcVoiceActivityDetection = 9;
constexpr int32_t kProtoMcSpeakerDiarization = 10;
constexpr int32_t kProtoMcSemanticSegmentation = 11;
constexpr int32_t kProtoMcVocoder = 12;

// ModelSource
constexpr int32_t kProtoMsUnspecified = 0;
constexpr int32_t kProtoMsRemote = 1;
constexpr int32_t kProtoMsLocal = 2;
constexpr int32_t kProtoMsBuiltIn = 3;

// ArchiveType
constexpr int32_t kProtoAtUnspecified = 0;
constexpr int32_t kProtoAtZip = 1;
constexpr int32_t kProtoAtTarBz2 = 2;
constexpr int32_t kProtoAtTarGz = 3;
constexpr int32_t kProtoAtTarXz = 4;

// ArchiveStructure
constexpr int32_t kProtoAsUnspecified = 0;
constexpr int32_t kProtoAsSingleFileNested = 1;
constexpr int32_t kProtoAsDirectoryBased = 2;
constexpr int32_t kProtoAsNestedDirectory = 3;
constexpr int32_t kProtoAsUnknown = 4;

// ModelFormat — these already match rac_model_format_t value-for-value via
// RAC_MODEL_FORMAT_ID_*, so listing them here is for documentation.
constexpr int32_t kProtoMfUnspecified = 0;
constexpr int32_t kProtoMfUnknown = 15;

}  // namespace

extern "C" {

// =============================================================================
// InferenceFramework
// =============================================================================

rac_result_t rac_inference_framework_from_proto(int32_t proto_value,
                                                rac_inference_framework_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (proto_value) {
        case kProtoIfwUnspecified:
            *out = RAC_FRAMEWORK_UNKNOWN;
            return RAC_SUCCESS;
        case kProtoIfwOnnx:
            *out = RAC_FRAMEWORK_ONNX;
            return RAC_SUCCESS;
        case kProtoIfwLlamaCpp:
            *out = RAC_FRAMEWORK_LLAMACPP;
            return RAC_SUCCESS;
        case kProtoIfwFoundationModels:
            *out = RAC_FRAMEWORK_FOUNDATION_MODELS;
            return RAC_SUCCESS;
        case kProtoIfwSystemTts:
            *out = RAC_FRAMEWORK_SYSTEM_TTS;
            return RAC_SUCCESS;
        case kProtoIfwFluidAudio:
            *out = RAC_FRAMEWORK_FLUID_AUDIO;
            return RAC_SUCCESS;
        case kProtoIfwCoreml:
            *out = RAC_FRAMEWORK_COREML;
            return RAC_SUCCESS;
        case kProtoIfwMlx:
            *out = RAC_FRAMEWORK_MLX;
            return RAC_SUCCESS;
        case kProtoIfwBuiltIn:
            *out = RAC_FRAMEWORK_BUILTIN;
            return RAC_SUCCESS;
        case kProtoIfwNone:
            *out = RAC_FRAMEWORK_NONE;
            return RAC_SUCCESS;
        case kProtoIfwUnknown:
            *out = RAC_FRAMEWORK_UNKNOWN;
            return RAC_SUCCESS;
        case kProtoIfwSherpa:
            *out = RAC_FRAMEWORK_SHERPA;
            return RAC_SUCCESS;
        case kProtoIfwQhexrt:
            *out = RAC_FRAMEWORK_QHEXRT;
            return RAC_SUCCESS;
        // Proto values defined in idl/model_types.proto but without a
        // corresponding rac_inference_framework_t case: TFLITE, EXECUTORCH,
        // MEDIAPIPE, MLC, PICO_LLM, PIPER_TTS, SWIFT_TRANSFORMERS. Fold these
        // into UNKNOWN so commons can still round-trip a generated proto
        // envelope without losing the message.
        case kProtoIfwTflite:
        case kProtoIfwExecutorch:
        case kProtoIfwMediapipe:
        case kProtoIfwMlc:
        case kProtoIfwPicoLlm:
        case kProtoIfwPiperTts:
        case kProtoIfwSwiftTransformers:
            *out = RAC_FRAMEWORK_UNKNOWN;
            return RAC_SUCCESS;
        default:
            *out = RAC_FRAMEWORK_UNKNOWN;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

rac_result_t rac_inference_framework_to_proto(rac_inference_framework_t value, int32_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (value) {
        case RAC_FRAMEWORK_ONNX:
            *out = kProtoIfwOnnx;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_LLAMACPP:
            *out = kProtoIfwLlamaCpp;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            *out = kProtoIfwFoundationModels;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_SYSTEM_TTS:
            *out = kProtoIfwSystemTts;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_FLUID_AUDIO:
            *out = kProtoIfwFluidAudio;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_BUILTIN:
            *out = kProtoIfwBuiltIn;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_NONE:
            *out = kProtoIfwNone;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_MLX:
            *out = kProtoIfwMlx;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_COREML:
            *out = kProtoIfwCoreml;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_SHERPA:
            *out = kProtoIfwSherpa;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_QHEXRT:
            *out = kProtoIfwQhexrt;
            return RAC_SUCCESS;
        case RAC_FRAMEWORK_UNKNOWN:
            *out = kProtoIfwUnknown;
            return RAC_SUCCESS;
        default:
            *out = kProtoIfwUnspecified;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

// =============================================================================
// ModelCategory
// =============================================================================

rac_result_t rac_model_category_from_proto(int32_t proto_value, rac_model_category_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (proto_value) {
        case kProtoMcUnspecified:
            *out = RAC_MODEL_CATEGORY_UNKNOWN;
            return RAC_SUCCESS;
        case kProtoMcLanguage:
            *out = RAC_MODEL_CATEGORY_LANGUAGE;
            return RAC_SUCCESS;
        case kProtoMcSpeechRecognition:
            *out = RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
            return RAC_SUCCESS;
        case kProtoMcSpeechSynthesis:
            *out = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
            return RAC_SUCCESS;
        case kProtoMcVision:
            *out = RAC_MODEL_CATEGORY_VISION;
            return RAC_SUCCESS;
        case kProtoMcImageGeneration:
            *out = RAC_MODEL_CATEGORY_IMAGE_GENERATION;
            return RAC_SUCCESS;
        case kProtoMcMultimodal:
            *out = RAC_MODEL_CATEGORY_MULTIMODAL;
            return RAC_SUCCESS;
        case kProtoMcAudio:
            *out = RAC_MODEL_CATEGORY_AUDIO;
            return RAC_SUCCESS;
        case kProtoMcEmbedding:
            *out = RAC_MODEL_CATEGORY_EMBEDDING;
            return RAC_SUCCESS;
        case kProtoMcVoiceActivityDetection:
            *out = RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
            return RAC_SUCCESS;
        case kProtoMcSpeakerDiarization:
            *out = RAC_MODEL_CATEGORY_SPEAKER_DIARIZATION;
            return RAC_SUCCESS;
        case kProtoMcSemanticSegmentation:
            *out = RAC_MODEL_CATEGORY_SEMANTIC_SEGMENTATION;
            return RAC_SUCCESS;
        case kProtoMcVocoder:
            *out = RAC_MODEL_CATEGORY_VOCODER;
            return RAC_SUCCESS;
        default:
            *out = RAC_MODEL_CATEGORY_UNKNOWN;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

rac_result_t rac_model_category_to_proto(rac_model_category_t value, int32_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (value) {
        case RAC_MODEL_CATEGORY_LANGUAGE:
            *out = kProtoMcLanguage;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION:
            *out = kProtoMcSpeechRecognition;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS:
            *out = kProtoMcSpeechSynthesis;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_VISION:
            *out = kProtoMcVision;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_IMAGE_GENERATION:
            *out = kProtoMcImageGeneration;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_MULTIMODAL:
            *out = kProtoMcMultimodal;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_AUDIO:
            *out = kProtoMcAudio;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_EMBEDDING:
            *out = kProtoMcEmbedding;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            *out = kProtoMcVoiceActivityDetection;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_SPEAKER_DIARIZATION:
            *out = kProtoMcSpeakerDiarization;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_SEMANTIC_SEGMENTATION:
            *out = kProtoMcSemanticSegmentation;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_VOCODER:
            *out = kProtoMcVocoder;
            return RAC_SUCCESS;
        case RAC_MODEL_CATEGORY_UNKNOWN:
            // No proto equivalent — map to UNSPECIFIED (0).
            *out = kProtoMcUnspecified;
            return RAC_SUCCESS;
        default:
            *out = kProtoMcUnspecified;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

// =============================================================================
// ModelFormat
// =============================================================================

rac_result_t rac_model_format_from_proto(int32_t proto_value, rac_model_format_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    // rac_model_format_t values are 1:1 with proto (via RAC_MODEL_FORMAT_ID_*).
    // We still validate the range explicitly so unknown ints fail closed.
    if (proto_value < kProtoMfUnspecified || proto_value > kProtoMfUnknown) {
        *out = RAC_MODEL_FORMAT_UNSPECIFIED;
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out = static_cast<rac_model_format_t>(proto_value);
    return RAC_SUCCESS;
}

rac_result_t rac_model_format_to_proto(rac_model_format_t value, int32_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    const int32_t v = static_cast<int32_t>(value);
    if (v < kProtoMfUnspecified || v > kProtoMfUnknown) {
        *out = kProtoMfUnspecified;
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out = v;
    return RAC_SUCCESS;
}

// =============================================================================
// ModelSource
// =============================================================================

rac_result_t rac_model_source_from_proto(int32_t proto_value, rac_model_source_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (proto_value) {
        case kProtoMsUnspecified:
        case kProtoMsRemote:
            *out = RAC_MODEL_SOURCE_REMOTE;
            return RAC_SUCCESS;
        case kProtoMsLocal:
            *out = RAC_MODEL_SOURCE_LOCAL;
            return RAC_SUCCESS;
        case kProtoMsBuiltIn:
            // No BUILT_IN case in rac_model_source_t today — surface as LOCAL
            // (the platform-adapter convention: built-in models are visible to
            // the registry as locally-resident assets).
            *out = RAC_MODEL_SOURCE_LOCAL;
            return RAC_SUCCESS;
        default:
            *out = RAC_MODEL_SOURCE_REMOTE;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

rac_result_t rac_model_source_to_proto(rac_model_source_t value, int32_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (value) {
        case RAC_MODEL_SOURCE_REMOTE:
            *out = kProtoMsRemote;
            return RAC_SUCCESS;
        case RAC_MODEL_SOURCE_LOCAL:
            *out = kProtoMsLocal;
            return RAC_SUCCESS;
        default:
            *out = kProtoMsUnspecified;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

// =============================================================================
// ArchiveType
// =============================================================================

rac_result_t rac_archive_type_from_proto(int32_t proto_value, rac_archive_type_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (proto_value) {
        case kProtoAtUnspecified:
            *out = RAC_ARCHIVE_TYPE_NONE;
            return RAC_SUCCESS;
        case kProtoAtZip:
            *out = RAC_ARCHIVE_TYPE_ZIP;
            return RAC_SUCCESS;
        case kProtoAtTarBz2:
            *out = RAC_ARCHIVE_TYPE_TAR_BZ2;
            return RAC_SUCCESS;
        case kProtoAtTarGz:
            *out = RAC_ARCHIVE_TYPE_TAR_GZ;
            return RAC_SUCCESS;
        case kProtoAtTarXz:
            *out = RAC_ARCHIVE_TYPE_TAR_XZ;
            return RAC_SUCCESS;
        default:
            *out = RAC_ARCHIVE_TYPE_NONE;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

rac_result_t rac_archive_type_to_proto(rac_archive_type_t value, int32_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (value) {
        case RAC_ARCHIVE_TYPE_NONE:
            *out = kProtoAtUnspecified;
            return RAC_SUCCESS;
        case RAC_ARCHIVE_TYPE_ZIP:
            *out = kProtoAtZip;
            return RAC_SUCCESS;
        case RAC_ARCHIVE_TYPE_TAR_BZ2:
            *out = kProtoAtTarBz2;
            return RAC_SUCCESS;
        case RAC_ARCHIVE_TYPE_TAR_GZ:
            *out = kProtoAtTarGz;
            return RAC_SUCCESS;
        case RAC_ARCHIVE_TYPE_TAR_XZ:
            *out = kProtoAtTarXz;
            return RAC_SUCCESS;
        default:
            *out = kProtoAtUnspecified;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

// =============================================================================
// ArchiveStructure
// =============================================================================

rac_result_t rac_archive_structure_from_proto(int32_t proto_value, rac_archive_structure_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (proto_value) {
        case kProtoAsUnspecified:
            // No "unknown structure" sentinel in proto-space distinct from
            // UNSPECIFIED; both surface as the C UNKNOWN value.
            *out = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
            return RAC_SUCCESS;
        case kProtoAsSingleFileNested:
            *out = RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED;
            return RAC_SUCCESS;
        case kProtoAsDirectoryBased:
            *out = RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED;
            return RAC_SUCCESS;
        case kProtoAsNestedDirectory:
            *out = RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY;
            return RAC_SUCCESS;
        case kProtoAsUnknown:
            *out = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
            return RAC_SUCCESS;
        default:
            *out = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

rac_result_t rac_archive_structure_to_proto(rac_archive_structure_t value, int32_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    switch (value) {
        case RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED:
            *out = kProtoAsSingleFileNested;
            return RAC_SUCCESS;
        case RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED:
            *out = kProtoAsDirectoryBased;
            return RAC_SUCCESS;
        case RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY:
            *out = kProtoAsNestedDirectory;
            return RAC_SUCCESS;
        case RAC_ARCHIVE_STRUCTURE_UNKNOWN:
            *out = kProtoAsUnknown;
            return RAC_SUCCESS;
        default:
            *out = kProtoAsUnspecified;
            return RAC_ERROR_INVALID_ARGUMENT;
    }
}

}  // extern "C"
