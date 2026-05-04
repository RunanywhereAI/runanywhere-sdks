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
using RegistryRemoveProtoFn = rac_result_t (*)(
    rac_model_registry_handle_t,
    const char*);
using RegistryProtoFreeFn = void (*)(uint8_t*);

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

using STTTranscribeProtoFn = rac_result_t (*)(
    rac_handle_t,
    const void*,
    size_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using STTPartialProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using STTTranscribeStreamProtoFn = rac_result_t (*)(
    rac_handle_t,
    const void*,
    size_t,
    const uint8_t*,
    size_t,
    STTPartialProtoCallbackFn,
    void*);

using TTSVoiceProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using TTSChunkProtoCallbackFn = void (*)(
    const uint8_t*,
    size_t,
    void*);
using TTSListVoicesProtoFn = rac_result_t (*)(
    rac_handle_t,
    TTSVoiceProtoCallbackFn,
    void*);
using TTSSynthesizeProtoFn = rac_result_t (*)(
    rac_handle_t,
    const char*,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using TTSSynthesizeStreamProtoFn = rac_result_t (*)(
    rac_handle_t,
    const char*,
    const uint8_t*,
    size_t,
    TTSChunkProtoCallbackFn,
    void*);

using VADConfigureProtoFn = rac_result_t (*)(
    rac_handle_t,
    const uint8_t*,
    size_t);
using VADProcessProtoFn = rac_result_t (*)(
    rac_handle_t,
    const float*,
    size_t,
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

using EmbeddingsCreateFn = rac_result_t (*)(
    const char*,
    rac_handle_t*);
using EmbeddingsCreateWithConfigFn = rac_result_t (*)(
    const char*,
    const char*,
    rac_handle_t*);
using EmbeddingsInitializeFn = rac_result_t (*)(
    rac_handle_t,
    const char*);
using EmbeddingsEmbedBatchProtoFn = rac_result_t (*)(
    rac_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using EmbeddingsDestroyFn = void (*)(
    rac_handle_t);

using LoRAConfigProtoFn = rac_result_t (*)(
    rac_handle_t,
    const uint8_t*,
    size_t,
    rac_proto_buffer_t*);
using LoRAClearProtoFn = rac_result_t (*)(
    rac_handle_t,
    rac_proto_buffer_t*);

} // namespace margelo::nitro::runanywhere::proto_compat
