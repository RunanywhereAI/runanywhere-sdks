/**
 * HybridRunAnywhereCore+Hybrid.cpp
 *
 * THIN Nitro bridge over the commons STT hybrid router (offline sherpa <->
 * cloud). Division of labour is identical to the Kotlin/Swift bindings:
 * commons owns the ENTIRE routing decision (hard-filter eligibility — including
 * the device-state + custom-filter callbacks — ranking, and the confidence
 * cascade with primary->secondary fallback). This bridge only:
 *   1. creates the router handle (rac_stt_hybrid_router_create),
 *   2. creates the two STT services through the registry
 *      (rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE, engine) ->
 *      stt_ops->create -> heap-wrap), replicating the commons JNI
 *      create_stt_service_via_registry recipe verbatim,
 *   3. attaches the services + descriptor bytes and installs the policy bytes
 *      (rac_stt_hybrid_router_set_{offline,online}_service_proto / _set_policy_proto),
 *   4. installs the cross-SDK device-state vtable (rac_hybrid_set_device_state)
 *      and named custom-filter predicates (rac_hybrid_register_custom_filter),
 *   5. drives transcribe (rac_stt_hybrid_router_transcribe_proto) and returns
 *      the response bytes verbatim, and
 *   6. registers the cloud engine plugin (rac_backend_cloud_register).
 *
 * No cascade / filter / rank logic lives here — only marshalling.
 *
 * Symbols are resolved through proto_compat::symbol (dlsym) so the bridge keeps
 * compiling/linking against staged commons artifacts that may lag these ABIs,
 * matching every other *Proto method in this module.
 *
 * Callback bridging:
 *   - Custom filter: commons invokes the predicate SYNCHRONOUSLY on the routing
 *     thread (a Nitro Promise::async background thread during transcribe). We
 *     block that thread on the JS predicate's Nitro promise via
 *     `future.wait_for`, exactly like HybridRunAnywhereCore+Tools.cpp blocks on
 *     the JS tool-executor. The JS thread is free during transcribe, so this is
 *     deadlock-safe.
 *   - Device state: RN cannot call JS synchronously from the routing thread
 *     (unlike the Kotlin JNI CallBooleanMethod / Swift @convention(c) paths), so
 *     instead of installing live JS callbacks we install a vtable that returns
 *     CACHED values and let JS push a fresh snapshot via hybridSetDeviceState.
 *     The routing decision still happens in commons against that vtable.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/hybrid/rac_hybrid_custom_filter.h"
#include "rac/router/hybrid/rac_hybrid_device_state.h"
#include "rac/router/hybrid/rac_hybrid_types.h"
#include "rac/router/hybrid/rac_stt_hybrid_router.h"
#include "rac/router/hybrid/rac_stt_hybrid_router_proto.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

// --- proto-byte ABI function-pointer typedefs (resolved via dlsym) -----------

using HybridRouterCreateFn = rac_result_t (*)(rac_handle_t*);
using HybridRouterDestroyFn = void (*)(rac_handle_t);
using HybridRouterSetServiceProtoFn = rac_result_t (*)(
    rac_handle_t, rac_stt_service_t*, const uint8_t*, size_t);
using HybridRouterSetPolicyProtoFn = rac_result_t (*)(
    rac_handle_t, const uint8_t*, size_t);
using HybridRouterTranscribeProtoFn = rac_result_t (*)(
    rac_handle_t, const uint8_t*, size_t, uint8_t**, size_t*);
using HybridRouterProtoBufferFreeFn = void (*)(uint8_t*);
using HybridRouterCancelFn = rac_result_t (*)(rac_handle_t);

using PluginFindForEngineFn = const rac_engine_vtable_t* (*)(
    rac_primitive_t, const char*);
using SttDestroyFn = void (*)(rac_handle_t);

using HybridSetDeviceStateFn = rac_result_t (*)(
    const rac_hybrid_device_state_ops_t*);
using HybridRegisterCustomFilterFn = rac_result_t (*)(
    const char*, rac_hybrid_custom_filter_predicate_t, void*);
using HybridUnregisterCustomFilterFn = rac_result_t (*)(const char*);

using CloudRegisterFn = rac_result_t (*)(void);
using RegistryListPluginsFn = rac_result_t (*)(const char***, size_t*);
using RegistryFreePluginListFn = void (*)(const char**, size_t);

std::vector<uint8_t> copyHybridArrayBufferBytes(
    const std::shared_ptr<ArrayBuffer>& buffer) {
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

// --- Registry-routed STT service creation ------------------------------------
//
// Mirrors the commons JNI create_stt_service_via_registry
// (sdk/runanywhere-commons/src/jni/rac_stt_hybrid_router_jni.cpp) and the Swift
// HybridSTTRouter.createService: resolve the TRANSCRIBE engine pinned by
// `engineHint` via rac_plugin_find_for_engine, call its create op, and heap-wrap
// the impl in a rac_stt_service_t the router holds by handle. The lookup is
// engine-name-pinned, so a missing engine surfaces a clear error (null vtable)
// instead of silently routing elsewhere. The cloud provider, when relevant,
// already rides in `configJson` (the TS CloudSTT layer injects it, matching the
// Kotlin HybridRouterBridgeAdapter), and the commons cloud engine defaults it
// too — so we forward config verbatim.
rac_stt_service_t* createSttServiceViaRegistry(const std::string& engineHint,
                                               const std::string& modelOrPath,
                                               const std::string& configJson) {
    auto findForEngine =
        proto_compat::symbol<PluginFindForEngineFn>("rac_plugin_find_for_engine");
    if (!findForEngine) {
        LOGE("hybridSttRouterCreateService: rac_plugin_find_for_engine ABI "
             "unavailable");
        return nullptr;
    }

    const rac_engine_vtable_t* vt =
        findForEngine(RAC_PRIMITIVE_TRANSCRIBE, engineHint.c_str());
    if (vt == nullptr || vt->stt_ops == nullptr ||
        vt->stt_ops->create == nullptr) {
        LOGE("hybridSttRouterCreateService: no TRANSCRIBE engine for hint='%s'",
             engineHint.c_str());
        return nullptr;
    }

    const char* modelArg =
        modelOrPath.empty() ? nullptr : modelOrPath.c_str();
    const char* configArg =
        configJson.empty() ? nullptr : configJson.c_str();

    void* impl = nullptr;
    const rac_result_t createRc = vt->stt_ops->create(modelArg, configArg, &impl);
    if (createRc != RAC_SUCCESS || impl == nullptr) {
        LOGE("hybridSttRouterCreateService: create failed hint='%s' rc=%d",
             engineHint.c_str(), createRc);
        return nullptr;
    }

    auto* service =
        static_cast<rac_stt_service_t*>(std::malloc(sizeof(rac_stt_service_t)));
    if (service == nullptr) {
        if (vt->stt_ops->destroy != nullptr) {
            vt->stt_ops->destroy(impl);
        }
        return nullptr;
    }
    service->ops = vt->stt_ops;
    service->impl = impl;
    // rac_stt_destroy free()s this; tag with the model id/path when present,
    // else the engine hint so logs stay legible for cloud services.
    const char* tag = (modelArg != nullptr && modelArg[0] != '\0')
                          ? modelArg
                          : engineHint.c_str();
    service->model_id = ::strdup(tag);
    return service;
}

// --- Device-state vtable (cached snapshot pushed from JS) ---------------------
//
// commons reads is_online / battery_percent / is_thermal_throttled on every
// transcribe to evaluate the NETWORK / Battery hard filters. We cache the last
// snapshot JS pushed and return it from the vtable callbacks. The routing
// decision stays entirely in commons.

std::atomic<bool> g_deviceIsOnline{true};
std::atomic<int32_t> g_deviceBatteryPercent{100};
std::atomic<bool> g_deviceThermalThrottled{false};
std::atomic<bool> g_deviceStateInstalled{false};
std::mutex g_deviceStateMutex;

bool deviceStateIsOnline(void* /*user_data*/) {
    return g_deviceIsOnline.load(std::memory_order_relaxed);
}
int32_t deviceStateBatteryPercent(void* /*user_data*/) {
    return g_deviceBatteryPercent.load(std::memory_order_relaxed);
}
bool deviceStateIsThermalThrottled(void* /*user_data*/) {
    return g_deviceThermalThrottled.load(std::memory_order_relaxed);
}

// --- Custom-filter predicate table (name -> JS callback) ---------------------
//
// commons resolves the predicate by name and invokes it synchronously during
// the router's filter phase. We block that (background) routing thread on the
// JS predicate's Nitro promise, mirroring the tool-executor wait in
// HybridRunAnywhereCore+Tools.cpp. Fail-open (keep candidate) on any error so a
// misbehaving predicate never silently drops every candidate.

constexpr auto kCustomFilterTimeout = std::chrono::seconds(5);

struct CustomFilterEntry {
    HybridRunAnywhereCore::HybridCustomFilterCallback callback;
};

std::mutex g_customFilterMutex;
std::unordered_map<std::string, std::shared_ptr<CustomFilterEntry>>&
customFilterRegistry() {
    static std::unordered_map<std::string, std::shared_ptr<CustomFilterEntry>> reg;
    return reg;
}

std::shared_ptr<CustomFilterEntry> lookupCustomFilter(const std::string& name) {
    std::lock_guard<std::mutex> lock(g_customFilterMutex);
    auto it = customFilterRegistry().find(name);
    return it == customFilterRegistry().end() ? nullptr : it->second;
}

// The C predicate commons calls. user_data is the strdup'd filter name (stable
// table key) — never a raw object pointer — so a late call after unregister
// just misses the lookup and fails open.
rac_bool_t customFilterPredicate(const rac_hybrid_routing_context_t* ctx,
                                 void* user_data) {
    if (user_data == nullptr) {
        return RAC_TRUE;
    }
    const std::string name(static_cast<const char*>(user_data));
    auto entry = lookupCustomFilter(name);
    if (!entry || !entry->callback) {
        return RAC_TRUE;  // fail-open: predicate gone, keep candidate eligible.
    }
    std::string candidateModelId;
    if (ctx != nullptr) {
        candidateModelId = std::string(ctx->candidate_model_id);
    }
    try {
        // Nitro double-Promise: await the outer (invocation marshalling) promise
        // to obtain the inner JS-returned Promise<bool>, then await that — the
        // same two-step the tool-executor callback in
        // HybridRunAnywhereCore+Tools.cpp performs.
        auto outer = entry->callback(candidateModelId);
        if (!outer) {
            return RAC_TRUE;
        }
        auto outerFuture = outer->await();
        if (outerFuture.wait_for(kCustomFilterTimeout) != std::future_status::ready) {
            LOGE("hybrid custom filter '%s' timed out; keeping candidate", name.c_str());
            return RAC_TRUE;
        }
        auto inner = outerFuture.get();
        if (!inner) {
            return RAC_TRUE;
        }
        auto innerFuture = inner->await();
        if (innerFuture.wait_for(kCustomFilterTimeout) != std::future_status::ready) {
            LOGE("hybrid custom filter '%s' inner timed out; keeping candidate",
                 name.c_str());
            return RAC_TRUE;
        }
        return innerFuture.get() ? RAC_TRUE : RAC_FALSE;
    } catch (const std::exception& e) {
        LOGE("hybrid custom filter '%s' threw: %s; keeping candidate", name.c_str(),
             e.what());
        return RAC_TRUE;
    } catch (...) {
        LOGE("hybrid custom filter '%s' threw unknown; keeping candidate", name.c_str());
        return RAC_TRUE;
    }
}

bool isRegistrationSuccess(rac_result_t rc) {
    return rc == RAC_SUCCESS || rc == RAC_ERROR_MODULE_ALREADY_REGISTERED ||
           rc == RAC_ERROR_PLUGIN_DUPLICATE;
}

}  // namespace

// ============================================================================
// Router lifecycle
// ============================================================================

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridSttRouterCreate() {
    return Promise<double>::async([]() -> double {
        auto fn = proto_compat::symbol<HybridRouterCreateFn>(
            "rac_stt_hybrid_router_create");
        if (!fn) {
            LOGE("hybridSttRouterCreate: ABI unavailable");
            return 0.0;
        }
        rac_handle_t handle = nullptr;
        if (fn(&handle) != RAC_SUCCESS || handle == nullptr) {
            return 0.0;
        }
        return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::hybridSttRouterDestroy(
    double routerHandle) {
    return Promise<void>::async([routerHandle]() {
        if (routerHandle == 0.0) {
            return;
        }
        if (auto fn = proto_compat::symbol<HybridRouterDestroyFn>(
                "rac_stt_hybrid_router_destroy")) {
            fn(reinterpret_cast<rac_handle_t>(
                static_cast<uintptr_t>(routerHandle)));
        }
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridSttRouterCreateService(
    const std::string& engineHint,
    const std::string& modelIdOrPath,
    const std::string& configJson) {
    return Promise<double>::async(
        [engineHint, modelIdOrPath, configJson]() -> double {
            rac_stt_service_t* service =
                createSttServiceViaRegistry(engineHint, modelIdOrPath, configJson);
            if (service == nullptr) {
                return 0.0;
            }
            return static_cast<double>(reinterpret_cast<uintptr_t>(service));
        });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::hybridSttRouterDestroyService(
    double serviceHandle) {
    return Promise<void>::async([serviceHandle]() {
        if (serviceHandle == 0.0) {
            return;
        }
        // Both router sides route destruction through rac_stt_destroy, which
        // calls the engine's stt_ops->destroy and frees the wrapper.
        if (auto fn = proto_compat::symbol<SttDestroyFn>("rac_stt_destroy")) {
            fn(reinterpret_cast<rac_handle_t>(
                static_cast<uintptr_t>(serviceHandle)));
        }
    });
}

// ============================================================================
// Pair + policy
// ============================================================================

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridSttRouterSetOfflineService(
    double routerHandle,
    double serviceHandle,
    const std::shared_ptr<ArrayBuffer>& descriptorBytes) {
    auto bytes = copyHybridArrayBufferBytes(descriptorBytes);
    return Promise<double>::async(
        [routerHandle, serviceHandle, bytes = std::move(bytes)]() -> double {
            auto fn = proto_compat::symbol<HybridRouterSetServiceProtoFn>(
                "rac_stt_hybrid_router_set_offline_service_proto");
            if (!fn) {
                LOGE("hybridSttRouterSetOfflineService: ABI unavailable");
                return static_cast<double>(RAC_ERROR_NOT_IMPLEMENTED);
            }
            const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
            return static_cast<double>(fn(
                reinterpret_cast<rac_handle_t>(static_cast<uintptr_t>(routerHandle)),
                reinterpret_cast<rac_stt_service_t*>(
                    static_cast<uintptr_t>(serviceHandle)),
                data, bytes.size()));
        });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridSttRouterSetOnlineService(
    double routerHandle,
    double serviceHandle,
    const std::shared_ptr<ArrayBuffer>& descriptorBytes) {
    auto bytes = copyHybridArrayBufferBytes(descriptorBytes);
    return Promise<double>::async(
        [routerHandle, serviceHandle, bytes = std::move(bytes)]() -> double {
            auto fn = proto_compat::symbol<HybridRouterSetServiceProtoFn>(
                "rac_stt_hybrid_router_set_online_service_proto");
            if (!fn) {
                LOGE("hybridSttRouterSetOnlineService: ABI unavailable");
                return static_cast<double>(RAC_ERROR_NOT_IMPLEMENTED);
            }
            const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
            return static_cast<double>(fn(
                reinterpret_cast<rac_handle_t>(static_cast<uintptr_t>(routerHandle)),
                reinterpret_cast<rac_stt_service_t*>(
                    static_cast<uintptr_t>(serviceHandle)),
                data, bytes.size()));
        });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridSttRouterSetPolicy(
    double routerHandle,
    const std::shared_ptr<ArrayBuffer>& policyBytes) {
    auto bytes = copyHybridArrayBufferBytes(policyBytes);
    return Promise<double>::async(
        [routerHandle, bytes = std::move(bytes)]() -> double {
            auto fn = proto_compat::symbol<HybridRouterSetPolicyProtoFn>(
                "rac_stt_hybrid_router_set_policy_proto");
            if (!fn) {
                LOGE("hybridSttRouterSetPolicy: ABI unavailable");
                return static_cast<double>(RAC_ERROR_NOT_IMPLEMENTED);
            }
            const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
            return static_cast<double>(fn(
                reinterpret_cast<rac_handle_t>(static_cast<uintptr_t>(routerHandle)),
                data, bytes.size()));
        });
}

// ============================================================================
// Transcribe + cancel
// ============================================================================

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::hybridSttRouterTranscribe(
    double routerHandle,
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyHybridArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [routerHandle, bytes = std::move(bytes)]() -> std::shared_ptr<ArrayBuffer> {
            auto fn = proto_compat::symbol<HybridRouterTranscribeProtoFn>(
                "rac_stt_hybrid_router_transcribe_proto");
            if (!fn) {
                LOGE("hybridSttRouterTranscribe: ABI unavailable");
                return ArrayBuffer::allocate(0);
            }
            uint8_t* outBytes = nullptr;
            size_t outSize = 0;
            const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
            rac_result_t rc = fn(
                reinterpret_cast<rac_handle_t>(static_cast<uintptr_t>(routerHandle)),
                data, bytes.size(), &outBytes, &outSize);

            auto freeFn = proto_compat::symbol<HybridRouterProtoBufferFreeFn>(
                "rac_stt_hybrid_router_proto_buffer_free");
            if (rc != RAC_SUCCESS || outBytes == nullptr || outSize == 0) {
                if (rc != RAC_SUCCESS) {
                    LOGE("hybridSttRouterTranscribe: rc=%d", rc);
                }
                if (outBytes != nullptr && freeFn) {
                    freeFn(outBytes);
                }
                return ArrayBuffer::allocate(0);
            }
            auto buffer = ArrayBuffer::copy(outBytes, outSize);
            if (freeFn) {
                freeFn(outBytes);
            }
            return buffer;
        });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridSttRouterCancel(
    double routerHandle) {
    return Promise<double>::async([routerHandle]() -> double {
        if (routerHandle == 0.0) {
            return static_cast<double>(RAC_SUCCESS);
        }
        auto fn = proto_compat::symbol<HybridRouterCancelFn>(
            "rac_stt_hybrid_router_cancel");
        if (!fn) {
            return static_cast<double>(RAC_SUCCESS);  // best-effort no-op
        }
        return static_cast<double>(fn(
            reinterpret_cast<rac_handle_t>(static_cast<uintptr_t>(routerHandle))));
    });
}

// ============================================================================
// Custom-filter predicates (cross-SDK named callback table)
// ============================================================================

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridRegisterCustomFilter(
    const std::string& name,
    const HybridCustomFilterCallback& predicate) {
    return Promise<double>::async([name, predicate]() -> double {
        if (name.empty()) {
            return static_cast<double>(RAC_ERROR_INVALID_PARAMETER);
        }
        auto fn = proto_compat::symbol<HybridRegisterCustomFilterFn>(
            "rac_hybrid_register_custom_filter");
        if (!fn) {
            LOGE("hybridRegisterCustomFilter: ABI unavailable");
            return static_cast<double>(RAC_ERROR_NOT_IMPLEMENTED);
        }
        // Store the JS callback in the process-global table BEFORE registering
        // with commons, so a predicate invocation racing the register call
        // resolves the callback. user_data is the stable strdup'd name; commons
        // copies the name into its own storage, but the predicate reads
        // user_data, so we keep our own copy alive for the table's lifetime.
        {
            std::lock_guard<std::mutex> lock(g_customFilterMutex);
            auto entry = std::make_shared<CustomFilterEntry>();
            entry->callback = predicate;
            customFilterRegistry()[name] = std::move(entry);
        }
        // Persist a strdup'd name as user_data. Leaked intentionally for the
        // process lifetime of the named entry — unregister removes the table
        // entry (after which the predicate fails open), and re-registering the
        // same name overwrites the table entry. The small per-name strdup is
        // bounded by the number of distinct filter names an app uses.
        char* userData = ::strdup(name.c_str());
        rac_result_t rc = fn(name.c_str(), customFilterPredicate, userData);
        if (rc != RAC_SUCCESS) {
            std::lock_guard<std::mutex> lock(g_customFilterMutex);
            customFilterRegistry().erase(name);
            std::free(userData);
            LOGE("hybridRegisterCustomFilter('%s'): rc=%d", name.c_str(), rc);
        }
        return static_cast<double>(rc);
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::hybridUnregisterCustomFilter(
    const std::string& name) {
    return Promise<double>::async([name]() -> double {
        if (name.empty()) {
            return static_cast<double>(RAC_ERROR_INVALID_PARAMETER);
        }
        {
            std::lock_guard<std::mutex> lock(g_customFilterMutex);
            customFilterRegistry().erase(name);
        }
        auto fn = proto_compat::symbol<HybridUnregisterCustomFilterFn>(
            "rac_hybrid_unregister_custom_filter");
        if (!fn) {
            return static_cast<double>(RAC_SUCCESS);
        }
        return static_cast<double>(fn(name.c_str()));
    });
}

// ============================================================================
// Device-state vtable (cached snapshot pushed from JS)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::hybridSetDeviceState(
    bool isOnline,
    double batteryPercent,
    bool thermalThrottled) {
    return Promise<bool>::async([isOnline, batteryPercent, thermalThrottled]() -> bool {
        g_deviceIsOnline.store(isOnline, std::memory_order_relaxed);
        g_deviceBatteryPercent.store(
            static_cast<int32_t>(batteryPercent), std::memory_order_relaxed);
        g_deviceThermalThrottled.store(thermalThrottled, std::memory_order_relaxed);

        // Install the vtable once. The values it returns are the atomics above,
        // so a re-push just updates the atomics with no native re-install.
        if (g_deviceStateInstalled.load(std::memory_order_acquire)) {
            return true;
        }
        std::lock_guard<std::mutex> lock(g_deviceStateMutex);
        if (g_deviceStateInstalled.load(std::memory_order_relaxed)) {
            return true;
        }
        auto fn = proto_compat::symbol<HybridSetDeviceStateFn>(
            "rac_hybrid_set_device_state");
        if (!fn) {
            LOGE("hybridSetDeviceState: ABI unavailable");
            return false;
        }
        rac_hybrid_device_state_ops_t ops{};
        ops.is_online = deviceStateIsOnline;
        ops.battery_percent = deviceStateBatteryPercent;
        ops.is_thermal_throttled = deviceStateIsThermalThrottled;
        ops.user_data = nullptr;  // callbacks read process-global atomics
        rac_result_t rc = fn(&ops);
        if (rc != RAC_SUCCESS) {
            LOGE("hybridSetDeviceState: rac_hybrid_set_device_state rc=%d", rc);
            return false;
        }
        g_deviceStateInstalled.store(true, std::memory_order_release);
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::hybridClearDeviceState() {
    return Promise<bool>::async([]() -> bool {
        std::lock_guard<std::mutex> lock(g_deviceStateMutex);
        auto fn = proto_compat::symbol<HybridSetDeviceStateFn>(
            "rac_hybrid_set_device_state");
        if (!fn) {
            return false;
        }
        rac_result_t rc = fn(nullptr);
        g_deviceStateInstalled.store(false, std::memory_order_release);
        // Reset to the commons optimistic defaults for any future re-install.
        g_deviceIsOnline.store(true, std::memory_order_relaxed);
        g_deviceBatteryPercent.store(100, std::memory_order_relaxed);
        g_deviceThermalThrottled.store(false, std::memory_order_relaxed);
        if (rc != RAC_SUCCESS) {
            LOGE("hybridClearDeviceState: rc=%d", rc);
            return false;
        }
        return true;
    });
}

// ============================================================================
// cloud engine plugin registration (mirrors ONNX.register())
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cloudRegister() {
    return Promise<bool>::async([]() -> bool {
        auto fn = proto_compat::symbol<CloudRegisterFn>(
            "rac_backend_cloud_register");
        if (!fn) {
            LOGE("cloudRegister: rac_backend_cloud_register unavailable "
                 "(cloud engine not linked into this build)");
            return false;
        }
        rac_result_t rc = fn();
        if (!isRegistrationSuccess(rc)) {
            LOGE("cloudRegister: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cloudUnregister() {
    return Promise<bool>::async([]() -> bool {
        auto fn = proto_compat::symbol<CloudRegisterFn>(
            "rac_backend_cloud_unregister");
        if (!fn) {
            return false;
        }
        rac_result_t rc = fn();
        if (rc != RAC_SUCCESS && rc != RAC_ERROR_MODULE_NOT_FOUND) {
            LOGE("cloudUnregister: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cloudIsRegistered() {
    return Promise<bool>::async([]() -> bool {
        auto listFn = proto_compat::symbol<RegistryListPluginsFn>(
            "rac_registry_list_plugins");
        auto freeFn = proto_compat::symbol<RegistryFreePluginListFn>(
            "rac_registry_free_plugin_list");
        if (!listFn) {
            return false;
        }
        const char** names = nullptr;
        size_t count = 0;
        if (listFn(&names, &count) != RAC_SUCCESS || names == nullptr) {
            return false;
        }
        bool found = false;
        for (size_t i = 0; i < count; ++i) {
            if (names[i] != nullptr && std::strcmp(names[i], "cloud") == 0) {
                found = true;
                break;
            }
        }
        if (freeFn) {
            freeFn(names, count);
        }
        return found;
    });
}

}  // namespace margelo::nitro::runanywhere
