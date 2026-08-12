// lora_bridge.cpp — LoRA adapters over the lifecycle proto ABI, plus the
// adapter catalog.
//
// The component-handle entry points (rac_llm_component_load_lora and friends)
// became unreachable when language models moved into commons' lifecycle store
// in F4, because there is no component handle any more. These are the
// replacement: they act on whatever model the lifecycle load made resident.
//
// The catalog half is registry-bound rather than lifecycle-bound: commons keeps
// one process-wide LoRA registry (`rac_get_lora_registry`, created by
// `rac_init`), and every catalog verb takes it. Nothing here creates a second
// one — a per-call registry would be a catalog no other call could see.

#include "lora_bridge.h"

#include <memory>
#include <utility>

#include "proto_bridge.h"

#include "rac/core/rac_core.h"
#include "rac/features/lora/rac_lora_service.h"

namespace rac_electron {
namespace {

using LoraCatalogFn = rac_result_t (*)(rac_lora_registry_handle_t, const uint8_t*, size_t,
                                       rac_proto_buffer_t*);

// One catalog verb, resolved against the process-wide registry at call time.
// `rac_init` creates it, so a call before initialize reports NOT_INITIALIZED
// rather than crashing on a null handle.
Napi::Value RunCatalogCall(const Napi::CallbackInfo& info, const char* context, LoraCatalogFn fn,
                           const char* signature) {
    Napi::Env env = info.Env();
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (registry == nullptr) {
        return RejectWithProtoError(env, RAC_ERROR_NOT_INITIALIZED, context);
    }
    auto payload = std::make_shared<std::vector<uint8_t>>(RequireProtoBytes(info, 0, signature));
    return RunProtoCall(env, context, [fn, registry, payload](rac_proto_buffer_t* out) {
        return fn(registry, payload->empty() ? nullptr : payload->data(), payload->size(), out);
    });
}

Napi::Value LoraApply(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_apply", rac_lora_apply_proto,
                         RequireProtoBytes(info, 0, "loraApplyProto(requestBytes)"));
}

Napi::Value LoraRemove(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_remove", rac_lora_remove_proto,
                         RequireProtoBytes(info, 0, "loraRemoveProto(requestBytes)"));
}

// list and state both take a LoraState request and answer with one; commons
// reads the base model from the lifecycle store rather than from the argument.
Napi::Value LoraList(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_list", rac_lora_list_proto,
                         RequireProtoBytes(info, 0, "loraListProto(stateBytes)"));
}

Napi::Value LoraState(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_state", rac_lora_state_proto,
                         RequireProtoBytes(info, 0, "loraStateProto(stateBytes)"));
}

// Compatibility is lifecycle-bound like apply/remove: commons resolves the
// loaded LLM itself and answers with a typed result rather than a failure when
// nothing is resident.
Napi::Value LoraCompatibility(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "lora_compatibility", rac_lora_compatibility_proto,
                         RequireProtoBytes(info, 0, "loraCompatibilityProto(configBytes)"));
}

Napi::Value LoraRegister(const Napi::CallbackInfo& info) {
    return RunCatalogCall(info, "lora_register", rac_lora_register_proto,
                          "loraRegisterProto(entryBytes)");
}

Napi::Value LoraCatalogList(const Napi::CallbackInfo& info) {
    return RunCatalogCall(info, "lora_catalog_list", rac_lora_catalog_list_proto,
                          "loraCatalogListProto(requestBytes)");
}

Napi::Value LoraCatalogQuery(const Napi::CallbackInfo& info) {
    return RunCatalogCall(info, "lora_catalog_query", rac_lora_catalog_query_proto,
                          "loraCatalogQueryProto(queryBytes)");
}

Napi::Value LoraCatalogGet(const Napi::CallbackInfo& info) {
    return RunCatalogCall(info, "lora_catalog_get", rac_lora_catalog_get_proto,
                          "loraCatalogGetProto(requestBytes)");
}

}  // namespace

void RegisterLoraBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("loraApplyProto", Napi::Function::New(env, LoraApply));
    exports.Set("loraRemoveProto", Napi::Function::New(env, LoraRemove));
    exports.Set("loraListProto", Napi::Function::New(env, LoraList));
    exports.Set("loraStateProto", Napi::Function::New(env, LoraState));
    exports.Set("loraCompatibilityProto", Napi::Function::New(env, LoraCompatibility));
    exports.Set("loraRegisterProto", Napi::Function::New(env, LoraRegister));
    exports.Set("loraCatalogListProto", Napi::Function::New(env, LoraCatalogList));
    exports.Set("loraCatalogQueryProto", Napi::Function::New(env, LoraCatalogQuery));
    exports.Set("loraCatalogGetProto", Napi::Function::New(env, LoraCatalogGet));
}

}  // namespace rac_electron
