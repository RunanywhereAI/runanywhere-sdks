/**
 * HybridRunAnywhereCore+Voice.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 *
 * Bridge classification:
 *   - SDK-facing pass-through: every `*Proto` method (LLM gen/cancel,
 *     STT/TTS/VAD/VLM/diffusion/embeddings proto thunks, voice agent
 *     proto thunks, LoRA proto thunks). Each takes/returns ArrayBuffer
 *     bytes and calls the matching `rac_*_proto` C ABI through
 *     proto_compat::symbol or, on Apple, via static linking.
 *   - Bridge-internal helper: `getGlobalLLMHandle()` calls
 *     `rac_llm_component_create()` directly to maintain a single LLM
 *     handle shared across HybridRunAnywhereCore instances. Migration
 *     target: source the live LLM handle from
 *     `rac_model_lifecycle_load_proto` (which returns the handle on
 *     load) so this bridge no longer creates components on its own.
 *   - Other helpers (`callLoraRequestProto`, `callLoraCatalogProto`,
 *     proto callbacks, VAD activity callback) are pure pass-through.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <unordered_map>

#include "rac/features/llm/rac_llm_service.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

std::vector<uint8_t> copyVoiceArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
    std::vector<uint8_t> bytes;
    if (!buffer) {
        return bytes;
    }
    uint8_t* data = buffer->data();
    size_t size = buffer->size();
    if (!data || size == 0) {
        return bytes;
    }
    bytes.assign(data, data + size);
    return bytes;
}

std::shared_ptr<ArrayBuffer> emptyVoiceProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

std::shared_ptr<ArrayBuffer> copyVoiceProtoBuffer(rac_proto_buffer_t& protoBuffer,
                                                  const char* operation) {
    // Mirrors the canonical JNI thunk in commons (runanywhere_commons_jni.cpp
    // `makeProtoCallResult` / `makeProtoBufferByteArray`): when the proto
    // buffer carries a typed error (status != RAC_SUCCESS), surface it to the
    // JS layer as a real exception with the typed `error_message`. Returning
    // an empty ArrayBuffer here swallows the typed error and forces every
    // JS consumer to throw a generic `protoDecodeFailed(operation)` instead
    // of the actual reason (e.g. "VAD lifecycle model is not loaded").
    if (protoBuffer.status != RAC_SUCCESS) {
        const std::string message = protoBuffer.error_message && protoBuffer.error_message[0]
            ? std::string(protoBuffer.error_message)
            : std::string(rac_error_message(protoBuffer.status));
        LOGE("%s proto error: %s", operation, message.c_str());
        proto_compat::freeBuffer(&protoBuffer);
        throw std::runtime_error(std::string(operation) + ": " + message);
    }
    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyVoiceProtoBuffer();
    }
    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

// --- Request-shaped stream callback lifetime --------------------------------
//
// `rac_llm_generate_stream_proto` and its STT/TTS/VLM siblings copy the
// {callback, user_data} slot under an internal mutex and RELEASE that mutex
// BEFORE invoking the callback (see rac_llm_stream.h "@warning user_data
// ownership and lifetime"). A generator thread can therefore dispatch with the
// snapshotted user_data AFTER `fn()` has already returned to this bridge. The
// previous `unique_ptr`-owned wrapper freed its heap as soon as the Promise
// lambda returned, so that late dispatch read freed memory (UAF).
//
// Ownership is held by a process-global `shared_ptr<StreamCallback>` registry
// keyed by the registration's raw address (used solely as a map key — never
// dereferenced through that pointer). The trampoline acquires its OWN strong
// reference under a short mutex before touching the callback, so a dispatch
// that races teardown either wins the lookup (the callback stays alive for the
// dispatch) or loses it (observes null and returns). Teardown after `fn()`
// returns runs the canonical commons recipe — quiesce in-flight dispatches,
// then drop the registry's strong ref. This mirrors HybridLLM.cpp's
// subscribe-then-trigger registry and Swift's ProtoStreamContext ownership.

struct StreamCallback {
    std::function<void(const std::shared_ptr<ArrayBuffer>&)> onBytes;
    std::atomic<bool> active{true};
};

std::mutex& streamRegistryMutex() {
    static std::mutex m;
    return m;
}

std::unordered_map<void*, std::shared_ptr<StreamCallback>>& streamRegistry() {
    static std::unordered_map<void*, std::shared_ptr<StreamCallback>> reg;
    return reg;
}

std::shared_ptr<StreamCallback> acquireStreamCallback(void* userData) {
    std::lock_guard<std::mutex> lock(streamRegistryMutex());
    auto it = streamRegistry().find(userData);
    if (it == streamRegistry().end()) {
        return nullptr;
    }
    return it->second;
}

// Publish a strong reference into the registry BEFORE the C callback is
// installed so a synchronously-fired first event can resolve it.
std::shared_ptr<StreamCallback> registerStreamCallback(
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onBytes) {
    auto reg = std::make_shared<StreamCallback>();
    reg->onBytes = onBytes;
    std::lock_guard<std::mutex> lock(streamRegistryMutex());
    streamRegistry()[reg.get()] = reg;
    return reg;
}

// Teardown after `fn()` returns: stop NEW dispatch, wait out in-flight
// dispatches via the modality's quiesce symbol (LLM/VLM expose one; the
// strong-ref acquire above already makes STT/TTS safe even without it), then
// drop the registry's strong ref. `quiesceSymbol` is resolved defensively so
// the bridge keeps linking against staged artifacts that predate it.
void releaseStreamCallback(const std::shared_ptr<StreamCallback>& reg,
                           const char* quiesceSymbol) {
    if (!reg) {
        return;
    }
    reg->active.store(false, std::memory_order_release);
    if (quiesceSymbol) {
        if (auto quiesce = proto_compat::symbol<void (*)()>(quiesceSymbol)) {
            quiesce();
        }
    }
    std::lock_guard<std::mutex> lock(streamRegistryMutex());
    streamRegistry().erase(reg.get());
}

void protoBytesCallback(const uint8_t* protoBytes, size_t protoSize, void* userData) {
    if (!protoBytes || protoSize == 0 || !userData) {
        return;
    }
    auto reg = acquireStreamCallback(userData);
    if (!reg || !reg->active.load(std::memory_order_acquire) || !reg->onBytes) {
        return;
    }
    try {
        reg->onBytes(ArrayBuffer::copy(protoBytes, protoSize));
    } catch (...) {
        LOGE("proto callback dispatch failed");
    }
}

std::mutex g_vadActivityCallbackMutex;
std::function<void(const std::shared_ptr<ArrayBuffer>&)> g_vadActivityCallback;

void vadActivityProtoCallback(const uint8_t* protoBytes, size_t protoSize, void*) {
    if (!protoBytes || protoSize == 0) {
        return;
    }
    std::function<void(const std::shared_ptr<ArrayBuffer>&)> callback;
    {
        std::lock_guard<std::mutex> lock(g_vadActivityCallbackMutex);
        callback = g_vadActivityCallback;
    }
    if (!callback) {
        return;
    }
    try {
        callback(ArrayBuffer::copy(protoBytes, protoSize));
    } catch (...) {
        LOGE("vad activity callback dispatch failed");
    }
}

} // namespace

// LLM/STT/TTS/VAD/Voice Agent
// ============================================================================
// LLM Capability (Backend-Agnostic)
// Calls rac_llm_component_* APIs - works with any registered backend
// Uses a global LLM component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global LLM component handle - shared across all instances
static rac_handle_t g_llm_component_handle = nullptr;
static std::mutex g_llm_mutex;

static rac_handle_t getGlobalLLMHandle() {
    std::lock_guard<std::mutex> lock(g_llm_mutex);
    if (g_llm_component_handle == nullptr) {
        rac_result_t result = rac_llm_component_create(&g_llm_component_handle);
        if (result != RAC_SUCCESS) {
            g_llm_component_handle = nullptr;
        }
    }
    return g_llm_component_handle;
}

// Commons resolves the lifecycle-owned LLM component internally for every
// `rac_lora_*_proto` entry point, so the RN bridge no longer needs to
// acquire/validate a handle here. We just pass the request bytes straight
// through; commons returns the typed result (including "service not loaded"
// failures) so callers see the same surface across platforms.
static std::shared_ptr<ArrayBuffer> callLoraRequestProto(
    const std::vector<uint8_t>& bytes,
    const char* symbolName,
    const char* operation) {
    auto fn = proto_compat::symbol<proto_compat::LoRARequestProtoFn>(symbolName);
    if (!fn) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return emptyVoiceProtoBuffer();
    }
    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
    rac_result_t rc = fn(data, bytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        proto_compat::freeBuffer(&out);
        return emptyVoiceProtoBuffer();
    }
    return copyVoiceProtoBuffer(out, operation);
}

static std::shared_ptr<ArrayBuffer> callLoraCatalogProto(
    const std::vector<uint8_t>& bytes,
    const char* symbolName,
    const char* operation) {
    auto getRegistry = proto_compat::symbol<proto_compat::LoraRegistryGetFn>(
        "rac_get_lora_registry");
    auto fn = proto_compat::symbol<proto_compat::LoraCatalogProtoFn>(symbolName);
    if (!getRegistry || !fn) {
        throw std::runtime_error(
            std::string(operation) +
            " unavailable: missing rac_get_lora_registry or " + symbolName);
    }

    rac_lora_registry_handle_t registry = getRegistry();
    if (!registry) {
        throw std::runtime_error(
            std::string(operation) +
            " unavailable: rac_get_lora_registry returned null");
    }

    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
    rac_result_t rc = fn(registry, data, bytes.size(), &out);
    if (rc != RAC_SUCCESS || out.status != RAC_SUCCESS) {
        rac_result_t status = out.status != RAC_SUCCESS ? out.status : rc;
        std::string message = out.error_message && out.error_message[0]
            ? std::string(out.error_message)
            : std::string(rac_error_message(status));
        proto_compat::freeBuffer(&out);
        throw std::runtime_error(std::string(operation) + " failed: " + message);
    }

    return copyVoiceProtoBuffer(out, operation);
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::getLLMHandle() {
    return Promise<double>::async([]() -> double {
        rac_handle_t handle = getGlobalLLMHandle();
        return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTextModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_llm_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isTextModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTextModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        rac_llm_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_llm_mutex);
            g_llm_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelGeneration() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        rac_llm_component_cancel(handle);
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::llmGenerateProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        auto fn = &rac_llm_generate_proto;
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("llmGenerateProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "llmGenerateProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::llmGenerateStreamProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<void>::async([bytes = std::move(bytes), onEventBytes]() {
        auto fn = &rac_llm_generate_stream_proto;
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        auto reg = registerStreamCallback(onEventBytes);
        rac_result_t rc = fn(data, bytes.size(), protoBytesCallback, reg.get());
        if (rc != RAC_SUCCESS) {
            LOGE("llmGenerateStreamProto: rc=%d", rc);
        }
        releaseStreamCallback(reg, "rac_llm_proto_quiesce");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::llmCancelProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        auto fn = &rac_llm_cancel_proto;
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(&out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("llmCancelProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "llmCancelProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraApplyProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_apply_proto",
            "loraApplyProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraRemoveProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_remove_proto",
            "loraRemoveProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraListProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_list_proto",
            "loraListProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraStateProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_state_proto",
            "loraStateProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCompatibilityProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_compatibility_proto",
            "loraCompatibilityProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraRegisterCatalogEntryProto(
    const std::shared_ptr<ArrayBuffer>& entryBytes) {
    auto bytes = copyVoiceArrayBufferBytes(entryBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_register_proto",
            "loraRegisterCatalogEntryProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogListProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_list_proto",
            "loraCatalogListProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogQueryProto(
    const std::shared_ptr<ArrayBuffer>& queryBytes) {
    auto bytes = copyVoiceArrayBufferBytes(queryBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_query_proto",
            "loraCatalogQueryProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogGetProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_get_proto",
            "loraCatalogGetProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogMarkDownloadCompletedProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_mark_download_completed_proto",
            "loraCatalogMarkDownloadCompletedProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraAdapterImportProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_adapter_import_proto",
            "loraAdapterImportProto");
    });
}

// ============================================================================
// STT Capability (Backend-Agnostic)
// Calls rac_stt_component_* APIs - works with any registered backend
// Uses a global STT component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global STT component handle - shared across all instances
// This ensures model loading state persists even when HybridRunAnywhereCore instances are recreated
static rac_handle_t g_stt_component_handle = nullptr;
static std::mutex g_stt_mutex;

static rac_handle_t getGlobalSTTHandle() {
    std::lock_guard<std::mutex> lock(g_stt_mutex);
    if (g_stt_component_handle == nullptr) {
        rac_result_t result = rac_stt_component_create(&g_stt_component_handle);
        if (result != RAC_SUCCESS) {
            g_stt_component_handle = nullptr;
        }
    }
    return g_stt_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isSTTModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_stt_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isSTTModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadSTTModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            return false;
        }
        rac_stt_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_stt_mutex);
            g_stt_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::sttTranscribeProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto request = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [request = std::move(request)]() {
        auto fn = proto_compat::symbol<proto_compat::STTLifecycleProtoFn>(
            "rac_stt_transcribe_lifecycle_proto");
        if (!fn) {
            LOGE("sttTranscribeProto: lifecycle proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* requestData = request.empty() ? nullptr : request.data();
        rac_result_t rc = fn(requestData, request.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("sttTranscribeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "sttTranscribeProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::sttTranscribeStreamProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto request = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<void>::async(
        [request = std::move(request), onEventBytes]() {
        auto fn = proto_compat::symbol<proto_compat::STTLifecycleStreamProtoFn>(
            "rac_stt_transcribe_stream_lifecycle_proto");
        if (!fn) {
            LOGE("sttTranscribeStreamProto: lifecycle stream ABI unavailable");
            return;
        }
        auto reg = registerStreamCallback(onEventBytes);
        const uint8_t* requestData = request.empty() ? nullptr : request.data();
        rac_result_t rc = fn(requestData, request.size(), protoBytesCallback, reg.get());
        if (rc != RAC_SUCCESS) {
            LOGE("sttTranscribeStreamProto: rc=%d", rc);
        }
        releaseStreamCallback(reg, "rac_stt_proto_quiesce");
    });
}

// ============================================================================
// STT Streaming Session (rac_stt_stream.h)
// Mirrors Swift CppBridge+STT.swift `transcribeSessionStream`: callback is
// registered BEFORE start, stop drains final events THROUGH the
// still-registered callback, and teardown follows the canonical recipe —
// stop/cancel first, then unset callback -> rac_stt_proto_quiesce -> free
// user_data (rac_stt_stream.h:79-84).
//
// The C ABI exposes ONE callback slot per handle, so the bridge tracks a
// single live session guarded by a mutex and rejects a second concurrent
// start.
// ============================================================================

namespace {

struct STTStreamSession {
    uint64_t sessionId = 0;
    rac_handle_t handle = nullptr;
    std::shared_ptr<StreamCallback> callback;
};

std::mutex g_stt_stream_mutex;
STTStreamSession g_stt_stream_session;
// Same-model fast path mirror of Swift CppBridge.STT `loadedModelId`.
std::string g_stt_stream_loaded_model_id;

// Pop the live session if it matches `sessionId` (0 matches any live
// session — used by global teardown). Returns an empty session when there
// is no match.
STTStreamSession takeSTTStreamSession(uint64_t sessionId) {
    std::lock_guard<std::mutex> lock(g_stt_stream_mutex);
    if (g_stt_stream_session.sessionId == 0 ||
        (sessionId != 0 && g_stt_stream_session.sessionId != sessionId)) {
        return {};
    }
    STTStreamSession session = std::move(g_stt_stream_session);
    g_stt_stream_session = {};
    return session;
}

// Canonical teardown tail (after stop/cancel already ran): unset the
// callback slot, quiesce in-flight dispatches, drop the registry ref.
void teardownSTTStreamSession(STTStreamSession& session) {
    if (session.handle) {
        if (auto unset = proto_compat::symbol<proto_compat::STTStreamUnsetProtoCallbackFn>(
                "rac_stt_unset_stream_proto_callback")) {
            unset(session.handle);
        }
    }
    releaseStreamCallback(session.callback, "rac_stt_proto_quiesce");
    session = {};
}

// Cancel-and-teardown for global component reset / cancel paths.
void cancelSTTStreamSession(STTStreamSession& session) {
    if (session.sessionId == 0) {
        return;
    }
    if (auto cancel = proto_compat::symbol<proto_compat::STTStreamFinishProtoFn>(
            "rac_stt_stream_cancel_proto")) {
        cancel(session.sessionId);
    }
    teardownSTTStreamSession(session);
}

} // namespace

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::sttStreamLoadModel(
    const std::string& modelPath,
    const std::string& modelId,
    const std::string& modelName) {
    return Promise<bool>::async([modelPath, modelId, modelName]() -> bool {
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            throw std::runtime_error("sttStreamLoadModel: STT component unavailable");
        }
        {
            // Same-model fast path — skips redundant backend load work.
            // Gated on the component still reporting loaded so an
            // unloadSTTModel() in between cannot stale-skip the reload.
            std::lock_guard<std::mutex> lock(g_stt_stream_mutex);
            if (!modelId.empty() && g_stt_stream_loaded_model_id == modelId &&
                rac_stt_component_is_loaded(handle) == RAC_TRUE) {
                return true;
            }
        }
        rac_result_t rc = rac_stt_component_load_model(
            handle, modelPath.c_str(), modelId.c_str(), modelName.c_str());
        if (rc != RAC_SUCCESS) {
            throw std::runtime_error("sttStreamLoadModel failed: rc=" + std::to_string(rc));
        }
        {
            std::lock_guard<std::mutex> lock(g_stt_stream_mutex);
            g_stt_stream_loaded_model_id = modelId;
        }
        return true;
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::sttStreamStart(
    const std::shared_ptr<ArrayBuffer>& optionsBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<double>::async([options = std::move(options), onEventBytes]() -> double {
        auto setCallback = proto_compat::symbol<proto_compat::STTStreamSetProtoCallbackFn>(
            "rac_stt_set_stream_proto_callback");
        auto unsetCallback = proto_compat::symbol<proto_compat::STTStreamUnsetProtoCallbackFn>(
            "rac_stt_unset_stream_proto_callback");
        auto start = proto_compat::symbol<proto_compat::STTStreamStartProtoFn>(
            "rac_stt_stream_start_proto");
        if (!setCallback || !unsetCallback || !start) {
            throw std::runtime_error(
                "sttStreamStart: rac_stt_stream session ABI unavailable");
        }
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            throw std::runtime_error("sttStreamStart: STT component unavailable");
        }

        std::lock_guard<std::mutex> lock(g_stt_stream_mutex);
        if (g_stt_stream_session.sessionId != 0) {
            throw std::runtime_error(
                "sttStreamStart: an STT stream session is already active "
                "(one callback slot per handle)");
        }

        // Publish-before-install: registry holds the strong ref before the C
        // callback can fire (see registerStreamCallback comment above).
        auto reg = registerStreamCallback(onEventBytes);
        rac_result_t rc = setCallback(handle, protoBytesCallback, reg.get());
        if (rc != RAC_SUCCESS) {
            releaseStreamCallback(reg, "rac_stt_proto_quiesce");
            throw std::runtime_error(
                "sttStreamStart: callback registration failed: rc=" + std::to_string(rc));
        }

        uint64_t sessionId = 0;
        const uint8_t* data = options.empty() ? nullptr : options.data();
        rc = start(handle, data, options.size(), &sessionId);
        if (rc != RAC_SUCCESS || sessionId == 0) {
            unsetCallback(handle);
            releaseStreamCallback(reg, "rac_stt_proto_quiesce");
            throw std::runtime_error(
                "sttStreamStart failed: rc=" + std::to_string(rc));
        }

        g_stt_stream_session.sessionId = sessionId;
        g_stt_stream_session.handle = handle;
        g_stt_stream_session.callback = reg;
        return static_cast<double>(sessionId);
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::sttStreamFeed(
    double sessionId,
    const std::shared_ptr<ArrayBuffer>& audioBytes) {
    auto audio = copyVoiceArrayBufferBytes(audioBytes);
    return Promise<void>::async([sessionId, audio = std::move(audio)]() {
        if (audio.empty()) {
            return; // Skip empty chunks (Swift parity).
        }
        auto feed = proto_compat::symbol<proto_compat::STTStreamFeedAudioProtoFn>(
            "rac_stt_stream_feed_audio_proto");
        if (!feed) {
            throw std::runtime_error(
                "sttStreamFeed: rac_stt_stream_feed_audio_proto unavailable");
        }
        rac_result_t rc = feed(static_cast<uint64_t>(sessionId), audio.data(), audio.size());
        if (rc != RAC_SUCCESS) {
            throw std::runtime_error("sttStreamFeed failed: rc=" + std::to_string(rc));
        }
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::sttStreamStop(double sessionId) {
    return Promise<void>::async([sessionId]() {
        auto session = takeSTTStreamSession(static_cast<uint64_t>(sessionId));
        if (session.sessionId == 0) {
            return; // Unknown / already torn down — idempotent.
        }
        // Stop FIRST so final events drain through the still-registered
        // callback, then run the canonical teardown tail.
        rac_result_t rc = RAC_ERROR_NOT_SUPPORTED;
        if (auto stop = proto_compat::symbol<proto_compat::STTStreamFinishProtoFn>(
                "rac_stt_stream_stop_proto")) {
            rc = stop(session.sessionId);
        }
        teardownSTTStreamSession(session);
        if (rc != RAC_SUCCESS) {
            throw std::runtime_error("sttStreamStop failed: rc=" + std::to_string(rc));
        }
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::sttStreamCancel(double sessionId) {
    return Promise<void>::async([sessionId]() {
        auto session = takeSTTStreamSession(static_cast<uint64_t>(sessionId));
        // Idempotent on unknown session ids — no throw.
        cancelSTTStreamSession(session);
    });
}

// ============================================================================
// TTS Capability (Backend-Agnostic)
// Calls rac_tts_component_* APIs - works with any registered backend
// Uses a global TTS component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global TTS component handle - shared across all instances
static rac_handle_t g_tts_component_handle = nullptr;
static std::mutex g_tts_mutex;

static rac_handle_t getGlobalTTSHandle() {
    std::lock_guard<std::mutex> lock(g_tts_mutex);
    if (g_tts_component_handle == nullptr) {
        rac_result_t result = rac_tts_component_create(&g_tts_component_handle);
        if (result != RAC_SUCCESS) {
            g_tts_component_handle = nullptr;
        }
    }
    return g_tts_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTTSModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_tts_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isTTSModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTTSModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            return false;
        }
        rac_tts_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_tts_mutex);
            g_tts_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ttsListVoicesProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        auto fn = proto_compat::symbol<proto_compat::TTSBufferProtoFn>(
            "rac_tts_list_voices_lifecycle_proto");
        if (!fn) {
            LOGE("ttsListVoicesProto: lifecycle list voices ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(&out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("ttsListVoicesProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "ttsListVoicesProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ttsSynthesizeProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto request = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [request = std::move(request)]() {
        auto fn = proto_compat::symbol<proto_compat::TTSLifecycleProtoFn>(
            "rac_tts_synthesize_lifecycle_proto");
        if (!fn) {
            LOGE("ttsSynthesizeProto: lifecycle synthesize ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* requestData = request.empty() ? nullptr : request.data();
        rac_result_t rc = fn(requestData, request.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("ttsSynthesizeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "ttsSynthesizeProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::ttsSynthesizeStreamProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto request = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<void>::async([request = std::move(request), onEventBytes]() {
        auto fn = proto_compat::symbol<proto_compat::TTSLifecycleStreamProtoFn>(
            "rac_tts_synthesize_stream_lifecycle_proto");
        if (!fn) {
            LOGE("ttsSynthesizeStreamProto: lifecycle stream ABI unavailable");
            return;
        }
        auto reg = registerStreamCallback(onEventBytes);
        const uint8_t* requestData = request.empty() ? nullptr : request.data();
        rac_result_t rc = fn(requestData, request.size(), protoBytesCallback, reg.get());
        if (rc != RAC_SUCCESS) {
            LOGE("ttsSynthesizeStreamProto: rc=%d", rc);
        }
        releaseStreamCallback(reg, "rac_tts_proto_quiesce");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ttsStopProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        auto fn = proto_compat::symbol<proto_compat::TTSBufferProtoFn>(
            "rac_tts_stop_lifecycle_proto");
        if (!fn) {
            LOGE("ttsStopProto: lifecycle stop ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(&out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("ttsStopProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "ttsStopProto");
    });
}

// ============================================================================
// VAD Capability (Backend-Agnostic)
// Calls rac_vad_component_* APIs - works with any registered backend
// Uses a global VAD component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global VAD component handle - shared across all instances
static rac_handle_t g_vad_component_handle = nullptr;
static std::mutex g_vad_mutex;

static rac_handle_t getGlobalVADHandle() {
    std::lock_guard<std::mutex> lock(g_vad_mutex);
    if (g_vad_component_handle == nullptr) {
        rac_result_t result = rac_vad_component_create(&g_vad_component_handle);
        if (result != RAC_SUCCESS) {
            g_vad_component_handle = nullptr;
        }
    }
    return g_vad_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVADModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_vad_component_is_initialized(handle) == RAC_TRUE;
        LOGD("isVADModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadVADModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            return false;
        }
        rac_vad_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_vad_mutex);
            g_vad_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::resetVAD() {
    return Promise<void>::async([]() -> void {
        auto fn = proto_compat::symbol<proto_compat::TTSBufferProtoFn>(
            "rac_vad_reset_lifecycle_proto");
        if (!fn) {
            LOGE("resetVAD: lifecycle reset ABI unavailable");
            return;
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(&out);
        if (rc != RAC_SUCCESS) {
            LOGE("resetVAD: rc=%d", rc);
        }
        proto_compat::freeBuffer(&out);
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>> HybridRunAnywhereCore::vadConfigureProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        auto fn = proto_compat::symbol<proto_compat::VADLifecycleProtoFn>(
            "rac_vad_configure_lifecycle_proto");
        if (!fn) {
            LOGE("vadConfigureProto: lifecycle configure ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vadConfigureProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vadConfigureProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vadProcessProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto request = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [request = std::move(request)]() {
        auto fn = proto_compat::symbol<proto_compat::VADLifecycleProtoFn>(
            "rac_vad_process_lifecycle_proto");
        if (!fn) {
            LOGE("vadProcessProto: lifecycle process ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* requestData = request.empty() ? nullptr : request.data();
        rac_result_t rc = fn(requestData, request.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vadProcessProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vadProcessProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vadGetStatisticsProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        rac_handle_t handle = getGlobalVADHandle();
        auto fn = proto_compat::symbol<proto_compat::VADStatsProtoFn>(
            "rac_vad_component_get_statistics_proto");
        if (!handle || !fn) {
            LOGE("vadGetStatisticsProto: VAD handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(handle, &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vadGetStatisticsProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vadGetStatisticsProto");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::vadSetActivityCallbackProto(
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onActivityBytes) {
    return Promise<bool>::async([onActivityBytes]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        auto fn = proto_compat::symbol<proto_compat::VADSetActivityProtoCallbackFn>(
            "rac_vad_component_set_activity_proto_callback");
        if (!handle || !fn) {
            LOGE("vadSetActivityCallbackProto: VAD handle or proto ABI unavailable");
            return false;
        }
        {
            std::lock_guard<std::mutex> lock(g_vadActivityCallbackMutex);
            g_vadActivityCallback = onActivityBytes;
        }
        rac_result_t rc = fn(handle, vadActivityProtoCallback, nullptr);
        if (rc != RAC_SUCCESS) {
            LOGE("vadSetActivityCallbackProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

// ============================================================================
// VLM Capability (Backend-Agnostic)
// Uses commons lifecycle-owned VLM proto APIs.
// ============================================================================

static rac_bool_t vlmProtoBytesCallback(const uint8_t* protoBytes,
                                        size_t protoSize,
                                        void* userData) {
    protoBytesCallback(protoBytes, protoSize, userData);
    return RAC_TRUE;
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vlmProcessProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto request = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [request = std::move(request)]() {
        auto fn = proto_compat::symbol<proto_compat::VLMProcessProtoFn>(
            "rac_vlm_generate_proto");
        if (!fn) {
            LOGE("vlmProcessProto: lifecycle generate ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* requestData = request.empty() ? nullptr : request.data();
        rac_result_t rc = fn(requestData, request.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vlmProcessProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vlmProcessProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::vlmProcessStreamProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto request = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<void>::async(
        [request = std::move(request), onEventBytes]() {
        auto fn = proto_compat::symbol<proto_compat::VLMProcessStreamProtoFn>(
            "rac_vlm_stream_proto");
        if (!fn) {
            LOGE("vlmProcessStreamProto: lifecycle stream ABI unavailable");
            return;
        }
        auto reg = registerStreamCallback(onEventBytes);
        const uint8_t* requestData = request.empty() ? nullptr : request.data();
        rac_result_t rc = fn(
            requestData,
            request.size(),
            vlmProtoBytesCallback,
            reg.get());
        if (rc != RAC_SUCCESS) {
            LOGE("vlmProcessStreamProto: rc=%d", rc);
        }
        releaseStreamCallback(reg, "rac_vlm_proto_quiesce");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vlmCancelProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        auto fn = proto_compat::symbol<proto_compat::VLMCancelProtoFn>(
            "rac_vlm_cancel_lifecycle_proto");
        if (!fn) {
            LOGE("vlmCancelProto: lifecycle cancel ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(&out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vlmCancelProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vlmCancelProto");
    });
}

// ============================================================================
// Voice Agent Capability (Backend-Agnostic)
// Calls rac_voice_agent_* APIs - requires STT, LLM, TTS, and VAD backends
// Uses a global voice agent handle that composes the global component handles
// Mirrors Swift SDK's CppBridge.VoiceAgent.shared architecture
// ============================================================================

// Global Voice Agent handle - composes the global STT, LLM, TTS, VAD handles
static rac_voice_agent_handle_t g_voice_agent_handle = nullptr;
static std::mutex g_voice_agent_mutex;

static rac_voice_agent_handle_t getGlobalVoiceAgentHandle() {
    std::lock_guard<std::mutex> lock(g_voice_agent_mutex);
    if (g_voice_agent_handle == nullptr) {
        // Get component handles - required for voice agent
        rac_handle_t llmHandle = getGlobalLLMHandle();
        rac_handle_t sttHandle = getGlobalSTTHandle();
        rac_handle_t ttsHandle = getGlobalTTSHandle();
        rac_handle_t vadHandle = getGlobalVADHandle();

        if (!llmHandle || !sttHandle || !ttsHandle || !vadHandle) {
            // Cannot create voice agent without all components
            return nullptr;
        }

        rac_result_t result = rac_voice_agent_create(
            llmHandle, sttHandle, ttsHandle, vadHandle, &g_voice_agent_handle);
        if (result != RAC_SUCCESS) {
            g_voice_agent_handle = nullptr;
        }
    }
    return g_voice_agent_handle;
}

// Expose the global voice-agent handle as a JS number. The
// VoiceAgent.subscribeProtoEvents(handle, ...) Nitro method casts it
// back to rac_voice_agent_handle_t on the C side. 0 means the handle
// isn't allocated yet (pre-initializeVoiceAgentWithLoadedModels).
std::shared_ptr<Promise<double>> HybridRunAnywhereCore::getVoiceAgentHandle() {
    return Promise<double>::async([this]() -> double {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        // reinterpret_cast to uintptr_t then widen to double. JS numbers
        // are 64-bit double, safe for 53 bits of integer precision —
        // more than enough for a 64-bit process pointer on macOS/Linux
        // and 32-bit pointers on iOS/Android ABIs.
        return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initializeVoiceAgentWithLoadedModels() {
    return Promise<bool>::async([this]() -> bool {
        LOGI("Initializing voice agent with loaded models...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent requires STT, LLM, TTS, and VAD backends. "
                                     "Install @runanywhere/llamacpp and @runanywhere/onnx.");
        }

        // Initialize using already-loaded models
        rac_result_t result = rac_voice_agent_initialize_with_loaded_models(handle);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Voice agent requires all models to be loaded. Error: " + std::to_string(result));
        }

        LOGI("Voice agent initialized with loaded models");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVoiceAgentReady() {
    return Promise<bool>::async([]() -> bool {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            return false;
        }

        rac_bool_t isReady = RAC_FALSE;
        rac_result_t result = rac_voice_agent_is_ready(handle, &isReady);
        if (result != RAC_SUCCESS) {
            return false;
        }

        LOGD("isVoiceAgentReady: %s", isReady == RAC_TRUE ? "true" : "false");
        return isReady == RAC_TRUE;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentTranscribeProto(
    const std::shared_ptr<ArrayBuffer>& audioBytes) {
    auto bytes = copyVoiceArrayBufferBytes(audioBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentTranscribeProtoFn>(
            "rac_voice_agent_transcribe_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentTranscribeProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentTranscribeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentTranscribeProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentSynthesizeSpeechProto(
    const std::string& text) {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([text]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentSynthesizeSpeechProtoFn>(
            "rac_voice_agent_synthesize_speech_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentSynthesizeSpeechProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        // Encode a minimal VoiceAgentSynthesizeSpeechProtoRequest on the fly.
        // Proto structure at idl/voice_agent_service.proto:
        //   message VoiceAgentSynthesizeSpeechProtoRequest {
        //     string text = 1;
        //     string session_id = 2;
        //     TTSOptions options = 3;
        //   }
        // Field 1 (text) wire-tag = (1<<3)|2 = 0x0A.
        std::vector<uint8_t> requestBytes;
        if (!text.empty()) {
            requestBytes.push_back(0x0A); // tag=1, wire=length-delimited
            // Varint-encode the length.
            uint32_t len = static_cast<uint32_t>(text.size());
            while (len >= 0x80) {
                requestBytes.push_back(static_cast<uint8_t>((len & 0x7F) | 0x80));
                len >>= 7;
            }
            requestBytes.push_back(static_cast<uint8_t>(len & 0x7F));
            requestBytes.insert(requestBytes.end(), text.begin(), text.end());
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = requestBytes.empty() ? nullptr : requestBytes.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, requestBytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentSynthesizeSpeechProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentSynthesizeSpeechProto");
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::cleanupVoiceAgent() {
    return Promise<void>::async([]() -> void {
        LOGI("Cleaning up voice agent...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (handle) {
            rac_voice_agent_cleanup(handle);
        }

        // Note: We don't destroy the voice agent handle here - it's reusable
        // The models can be unloaded separately via unloadSTTModel, etc.
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentInitializeProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentInitProtoFn>(
            "rac_voice_agent_initialize_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentInitializeProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentInitializeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentInitializeProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentComponentStatesProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentStatesProtoFn>(
            "rac_voice_agent_component_states_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentComponentStatesProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(static_cast<void*>(handle), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentComponentStatesProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentComponentStatesProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentProcessTurnProto(
    const std::shared_ptr<ArrayBuffer>& audioBytes) {
    auto audio = copyVoiceArrayBufferBytes(audioBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([audio = std::move(audio)]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentProcessTurnProtoFn>(
            "rac_voice_agent_process_voice_turn_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentProcessTurnProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const void* data = audio.empty() ? nullptr : audio.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, audio.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentProcessTurnProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentProcessTurnProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentFeedAudioProto(
    const std::shared_ptr<ArrayBuffer>& audioBytes, double sampleRateHz,
    double channels, double encoding, bool isFinal) {
    auto audio = copyVoiceArrayBufferBytes(audioBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [audio = std::move(audio), sampleRateHz, channels, encoding, isFinal]() {
            rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
            auto fn = proto_compat::symbol<proto_compat::VoiceAgentFeedAudioProtoFn>(
                "rac_voice_agent_feed_audio_proto");
            if (!handle || !fn) {
                LOGE("voiceAgentFeedAudioProto: handle or proto ABI unavailable");
                return emptyVoiceProtoBuffer();
            }
            rac_proto_buffer_t out;
            proto_compat::initBuffer(&out);
            const void* data = audio.empty() ? nullptr : audio.data();
            rac_result_t rc = fn(static_cast<void*>(handle), data, audio.size(),
                                 static_cast<int32_t>(sampleRateHz),
                                 static_cast<int32_t>(channels),
                                 static_cast<int32_t>(encoding),
                                 isFinal ? RAC_TRUE : RAC_FALSE, &out);
            if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
                LOGE("voiceAgentFeedAudioProto: rc=%d", rc);
                proto_compat::freeBuffer(&out);
                return emptyVoiceProtoBuffer();
            }
            return copyVoiceProtoBuffer(out, "voiceAgentFeedAudioProto");
        });
}

// ============================================================================
// Global component teardown
// ============================================================================
//
// Reset the LLM/STT/TTS/VAD/voice-agent globals plus the commons lifecycle
// registry so a HybridRunAnywhereCore::destroy() leaves no stale component
// state across subsequent initialize() calls. Each section locks its own
// mutex so we mirror the per-modality lifetime and cannot race a
// concurrently-running operation that already holds a handle copy.
extern "C" void rac_model_lifecycle_reset(void);

void resetAllGlobalComponentHandles() {
    {
        std::lock_guard<std::mutex> lock(g_voice_agent_mutex);
        if (g_voice_agent_handle != nullptr) {
            rac_voice_agent_destroy(g_voice_agent_handle);
            g_voice_agent_handle = nullptr;
        }
    }
    {
        std::lock_guard<std::mutex> lock(g_llm_mutex);
        if (g_llm_component_handle != nullptr) {
            rac_llm_component_cleanup(g_llm_component_handle);
            rac_llm_component_destroy(g_llm_component_handle);
            g_llm_component_handle = nullptr;
        }
    }
    {
        // Cancel any live STT streaming session BEFORE destroying the STT
        // component its callback slot is registered on (cancel -> unset ->
        // quiesce -> free user_data, per rac_stt_stream.h:79-84).
        auto session = takeSTTStreamSession(0);
        cancelSTTStreamSession(session);
        std::lock_guard<std::mutex> lock(g_stt_stream_mutex);
        g_stt_stream_loaded_model_id.clear();
    }
    {
        std::lock_guard<std::mutex> lock(g_stt_mutex);
        if (g_stt_component_handle != nullptr) {
            rac_stt_component_cleanup(g_stt_component_handle);
            rac_stt_component_destroy(g_stt_component_handle);
            g_stt_component_handle = nullptr;
        }
    }
    {
        std::lock_guard<std::mutex> lock(g_tts_mutex);
        if (g_tts_component_handle != nullptr) {
            rac_tts_component_cleanup(g_tts_component_handle);
            rac_tts_component_destroy(g_tts_component_handle);
            g_tts_component_handle = nullptr;
        }
    }
    {
        std::lock_guard<std::mutex> lock(g_vad_mutex);
        if (g_vad_component_handle != nullptr) {
            rac_vad_component_cleanup(g_vad_component_handle);
            rac_vad_component_destroy(g_vad_component_handle);
            g_vad_component_handle = nullptr;
        }
    }

    // Drop the commons lifecycle registry — must run AFTER component
    // destruction so any models registered with the lifecycle are freed
    // through their owning component's destroy path.
    rac_model_lifecycle_reset();
}

} // namespace margelo::nitro::runanywhere
