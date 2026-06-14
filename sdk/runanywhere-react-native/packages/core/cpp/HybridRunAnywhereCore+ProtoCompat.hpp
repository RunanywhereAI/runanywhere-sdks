/**
 * Compatibility declarations for optional RACommons proto-byte ABI symbols.
 *
 * RN native artifacts can lag the C++ bridge sources during local validation.
 * These helpers keep the bridge compiling/linking against older staged
 * artifacts while using the canonical RACommons symbols when refreshed
 * artifacts provide them.
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <dlfcn.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

#if __has_include("rac/infrastructure/model_management/rac_lora_registry.h")
#include "rac/infrastructure/model_management/rac_lora_registry.h"
#elif __has_include("rac_lora_registry.h")
#include "rac_lora_registry.h"
#else
extern "C" {
typedef struct rac_lora_registry* rac_lora_registry_handle_t;
}
#endif

#if __has_include("rac/foundation/rac_proto_buffer.h")
#include "rac/foundation/rac_proto_buffer.h"
#else
extern "C" {
typedef struct rac_proto_buffer {
    uint8_t* data;
    size_t size;
    rac_result_t status;
    char* error_message;
} rac_proto_buffer_t;
}
#endif

namespace margelo::nitro::runanywhere::proto_compat {

template <typename Fn>
Fn symbol(const char* name) {
    return reinterpret_cast<Fn>(dlsym(RTLD_DEFAULT, name));
}

using ProtoBufferInitFn = void (*)(rac_proto_buffer_t*);
using ProtoBufferFreeFn = void (*)(rac_proto_buffer_t*);

inline void initBuffer(rac_proto_buffer_t* buffer) {
    if (!buffer) {
        return;
    }

    if (auto fn = symbol<ProtoBufferInitFn>("rac_proto_buffer_init")) {
        fn(buffer);
        return;
    }

    buffer->data = nullptr;
    buffer->size = 0;
    buffer->status = RAC_SUCCESS;
    buffer->error_message = nullptr;
}

inline void freeBuffer(rac_proto_buffer_t* buffer) {
    if (!buffer) {
        return;
    }

    if (auto fn = symbol<ProtoBufferFreeFn>("rac_proto_buffer_free")) {
        fn(buffer);
        return;
    }

    std::free(buffer->data);
    std::free(buffer->error_message);
    initBuffer(buffer);
}

using RegistryGetProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    const char*,
    uint8_t**,
    size_t*);
using RegistryListProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    uint8_t**,
    size_t*);
using RegistryWriteProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    const uint8_t*,
    size_t);
using RegistryQueryProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    const uint8_t*,
    size_t,
    uint8_t**,
    size_t*);
using RegistryRequestProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using RegistryRemoveProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    const char*);
using RegistryProtoFreeFn = void (*)(uint8_t*);

// rac_register_model_from_url_proto: handle-less global-registry C ABI that
// translates a RegisterModelFromUrlRequest into the canonical build-and-save
// flow (framework defaulting + artifact inference + id derivation).
using RegisterModelFromUrlProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);

using ProtoBufferCallFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using DownloadProtoProgressCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using DownloadSetProgressProtoCallbackFn = rac_result_t (*)(
    DownloadProtoProgressCallbackFn,
    void*);

using StorageProtoFn = rac_result_t (*)(
    rac_storage_analyzer_handle_t,
    rac_model_registry_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);

using SDKEventCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using SDKEventSubscribeFn = uint64_t (*)(
    SDKEventCallbackFn,
    void*);
using SDKEventUnsubscribeFn = void (*)(uint64_t);
using SDKEventQuiesceFn = void (*)();
using SDKEventPublishProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t);
using SDKEventPollFn = rac_result_t (*)(
    rac_proto_buffer_t*);
using SDKEventPublishFailureFn = rac_result_t (*)(
    rac_result_t,
    const char*,
    const char*,
    const char*,
    rac_bool_t);

using ModelLifecycleLoadProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using ComponentLifecycleSnapshotProtoFn = rac_result_t (*)(
    uint32_t,
    rac_proto_buffer_t*);

using LLMGenerateProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using LLMStreamProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using LLMGenerateStreamProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    LLMStreamProtoCallbackFn,
    void*);
using LLMCancelProtoFn = rac_result_t (*)(
    rac_proto_buffer_t*);

using LoraRegistryGetFn = rac_lora_registry_handle_t (*)();
using LoraRegisterProtoFn = rac_result_t (*)(
    rac_lora_registry_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using LoraCatalogProtoFn = rac_result_t (*)(
    rac_lora_registry_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using STTLifecycleProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using STTPartialProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using STTLifecycleStreamProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    STTPartialProtoCallbackFn,
    void*);
// Session streaming ABI (rac_stt_stream.h) — set/unset callback on the
// component handle, start/feed/stop/cancel a session, quiesce in-flight
// callback dispatches before freeing user_data.
using STTStreamSetProtoCallbackFn = rac_result_t (*)(
    rac_handle_t,
    STTPartialProtoCallbackFn,
    void*);
using STTStreamUnsetProtoCallbackFn = rac_result_t (*)(
    rac_handle_t);
using STTStreamStartProtoFn = rac_result_t (*)(
    rac_handle_t,
    const uint8_t*,
    size_t,
    uint64_t*);
using STTStreamFeedAudioProtoFn = rac_result_t (*)(
    uint64_t,
    const uint8_t*,
    size_t);
using STTStreamFinishProtoFn = rac_result_t (*)(
    uint64_t);

using TTSVoiceProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using TTSChunkProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using TTSBufferProtoFn = rac_result_t (*)(
    rac_proto_buffer_t*);
using TTSLifecycleProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using TTSLifecycleStreamProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    TTSChunkProtoCallbackFn,
    void*);

using VADLifecycleProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using VADStatsProtoFn = rac_result_t (*)(
    rac_handle_t,
    rac_proto_buffer_t*);
using VADActivityProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using VADSetActivityProtoCallbackFn = rac_result_t (*)(
    rac_handle_t,
    VADActivityProtoCallbackFn,
    void*);

using VLMProcessProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using VLMStreamProtoCallbackFn = rac_bool_t (*)(
    const uint8_t*,
    size_t,
    void*);
using VLMProcessStreamProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    VLMStreamProtoCallbackFn,
    void*);
using VLMCancelProtoFn = rac_result_t (*)(
    rac_proto_buffer_t*);

using VoiceAgentInitProtoFn = rac_result_t (*)(
    void*,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using VoiceAgentStatesProtoFn = rac_result_t (*)(
    void*,
    rac_proto_buffer_t*);
using VoiceAgentProcessTurnProtoFn = rac_result_t (*)(
    void*,
    const void*,
    size_t,
    rac_proto_buffer_t*);

// D-7 helper-level proto wrappers for the voice-agent sub-components.
using VoiceAgentTranscribeProtoFn = rac_result_t (*)(
    void*,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using VoiceAgentSynthesizeSpeechProtoFn = rac_result_t (*)(
    void*,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);

using RAGSessionCreateProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_handle_t*);
using RAGSessionDestroyProtoFn = void (*)(
    rac_handle_t);
using RAGBufferProtoFn = rac_result_t (*)(
    rac_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using RAGStatsProtoFn = rac_result_t (*)(
    rac_handle_t,
    rac_proto_buffer_t*);

using StructuredOutputParseProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using ProtoBytesCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using StructuredOutputStreamProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    ProtoBytesCallbackFn,
    void*);

using ToolExecuteCallbackFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*,
    void*);
using ToolRunLoopProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    ToolExecuteCallbackFn,
    void*,
    rac_proto_buffer_t*);
// pass3-syn-028: callback variant — fires `on_handle_published(handle,
// user_data)` SYNCHRONOUSLY before iteration so SDKs can publish the handle
// to a thread-safe sink (JS callback, Completer, Deferred) without racing
// the worker. Preferred over polling the out-pointer from a watcher thread.
using ToolRunLoopOnHandlePublishedCb = void (*)(uint64_t, void*);
using ToolRunLoopWithHandleAndCbProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    ToolExecuteCallbackFn,
    void*,
    ToolRunLoopOnHandlePublishedCb,
    void*,
    uint64_t*,
    rac_proto_buffer_t*);
using ToolRunLoopCancelProtoFn = rac_result_t (*)(uint64_t);

using EmbeddingsEmbedBatchLifecycleProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);

using InferenceFrameworkFromProtoFn = rac_result_t (*)(
    int32_t,
    rac_inference_framework_t*);
using InferenceFrameworkToProtoFn = rac_result_t (*)(
    rac_inference_framework_t,
    int32_t*);
using InferenceFrameworkDisplayNameFn = rac_result_t (*)(
    rac_inference_framework_t,
    const char**);
using ModelCategoryFromProtoFn = rac_result_t (*)(
    int32_t,
    rac_model_category_t*);
using ModelCategoryDefaultFrameworkFn = rac_inference_framework_t (*)(
    rac_model_category_t);
using InferModelFileRoleFn = rac_result_t (*)(
    const char*,
    int32_t,
    int32_t*);

using LoRARequestProtoFn = rac_result_t (*)(
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);

} // namespace margelo::nitro::runanywhere::proto_compat
